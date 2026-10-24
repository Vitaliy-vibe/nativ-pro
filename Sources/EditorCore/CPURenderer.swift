import Foundation

/// Эталонный рендер на CPU.
/// Служит оракулом для рендера на Metal и для сверки с образцом.

public struct RenderResult: Sendable {
    /// RGBA без премультипликации, гамма-пространство sRGB.
    public var image: FloatImage
    /// Слои, которые этап 1 не умеет рисовать: (идентификатор, имя, вид). Их нельзя считать отрисованными.
    public var unsupported: [UnsupportedLayer]

    public init(image: FloatImage, unsupported: [UnsupportedLayer]) {
        self.image = image
        self.unsupported = unsupported
    }
}

public struct UnsupportedLayer: Sendable, Equatable {
    public var id: LayerID
    public var name: String
    public var kind: String

    public init(id: LayerID, name: String, kind: String) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// Что рисовать: прямоугольник в пикселях уровня `level` (уровень L — масштаб 1/2^L).
public struct RenderRegion: Sendable, Equatable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
    public var level: Int

    public init(x: Int, y: Int, width: Int, height: Int, level: Int = 0) {
        precondition(width >= 0 && height >= 0 && (0...8).contains(level), "уровень 0…8")
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.level = level
    }

    /// Весь документ на уровне `level`.
    public static func whole(_ d: Document, level: Int = 0) -> RenderRegion {
        let f = 1 << level
        return RenderRegion(x: 0, y: 0, width: (d.width + f - 1) / f, height: (d.height + f - 1) / f, level: level)
    }
}

public enum CPURenderer {
    /// Сторона куска, на которые делится область для параллельного расчёта.
    public static let chunk = 256

    public static func render(_ document: Document) throws -> RenderResult {
        try render(document, region: .whole(document))
    }

    /// Рисует область документа. Куски считаются параллельно: каждый независим.
    public static func render(_ document: Document, region: RenderRegion) throws -> RenderResult {
        guard document.colorProfile == "sRGB" else { throw DocumentError.unsupportedColorProfile(document.colorProfile) }
        var image = FloatImage(width: region.width, height: region.height, channels: 4)
        let across = (region.width + chunk - 1) / chunk, down = (region.height + chunk - 1) / chunk
        let output = UnsafeOutput(image: &image)
        DispatchQueue.concurrentPerform(iterations: across * down) { i in
            let cx = (i % across) * chunk, cy = (i / across) * chunk
            let w = min(chunk, region.width - cx), h = min(chunk, region.height - cy)
            var canvas = Canvas(x: region.x + cx, y: region.y + cy, image: FloatImage(width: w, height: h, channels: 4), level: region.level)
            drawStack(document.layers, into: &canvas, inherited: Inherited())
            output.copy(canvas.image, toX: cx, y: cy)
        }
        output.finish(into: &image)
        return RenderResult(image: image, unsupported: unsupportedLayers(document.layers))
    }

    /// Неподдержанные видимые слои (список не зависит от области).
    static func unsupportedLayers(_ layers: [Layer]) -> [UnsupportedLayer] {
        var out: [UnsupportedLayer] = []
        for l in layers where l.isVisible {
            switch l.content {
            case .unsupported(let kind): out.append(UnsupportedLayer(id: l.id, name: l.name, kind: kind))
            case .group(let children): out += unsupportedLayers(children)
            case .bitmap: break
            }
        }
        return out
    }

    /// Буфер результата, в который параллельные куски пишут непересекающиеся прямоугольники.
    final class UnsafeOutput: @unchecked Sendable {
        let width: Int
        let pointer: UnsafeMutableBufferPointer<Float>

        init(image: inout FloatImage) {
            width = image.width
            pointer = .allocate(capacity: image.data.count)
            pointer.initialize(repeating: 0)
        }

        func copy(_ part: FloatImage, toX x0: Int, y y0: Int) {
            for y in 0..<part.height {
                let dst = ((y0 + y) * width + x0) * 4
                let src = y * part.width * 4
                for i in 0..<(part.width * 4) { pointer[dst + i] = part.data[src + i] }
            }
        }

        func finish(into image: inout FloatImage) {
            image.data = Array(pointer)
            pointer.deallocate()
        }
    }

    /// Холст куска: прямоугольник [x, x+w) × [y, y+h) в пикселях уровня.
    struct Canvas {
        let x: Int
        let y: Int
        var image: FloatImage
        let level: Int
    }

    /// То, что слой получает от группы pass through: множитель непрозрачности и маски группы.
    struct Inherited {
        var opacity: Float = 1
        var masks: [MaskSet] = []
    }

    /// Источник пикселей слоя в координатах уровня: цвет и альфа (до непрозрачности и масок).
    struct Source {
        let width: Int, height: Int, originX: Int, originY: Int
        let sample: (Int, Int) -> SIMD4<Float>
    }

    /// Маски слоя, подготовленные для одного куска: виды растров на нужном уровне.
    struct MaskSet {
        struct Item {
            let mask: LayerMask
            let view: BitmapView?
            let ox: Int, oy: Int
        }
        let items: [Item]

        init(_ layer: Layer, canvas: Canvas) {
            let level = canvas.level
            items = layer.masks.filter(\.isEnabled).map { mask in
                let ox = mask.offset.x >> level, oy = mask.offset.y >> level
                let view = mask.bitmap?.view(level: level, x0: canvas.x - ox, y0: canvas.y - oy,
                                             x1: canvas.x + canvas.image.width - ox, y1: canvas.y + canvas.image.height - oy)
                return Item(mask: mask, view: view, ox: ox, oy: oy)
            }
        }

        var isEmpty: Bool { items.isEmpty }

        /// Произведение значений масок в точке уровня (плотность и инверсия учтены).
        @inline(__always)
        func value(x: Int, y: Int) -> Float {
            var m: Float = 1
            for it in items {
                var v = it.mask.backgroundValue
                if let view = it.view {
                    let lx = x - it.ox, ly = y - it.oy
                    if lx >= 0, ly >= 0, lx < view.width, ly < view.height { v = view.value(x: lx, y: ly, channel: 0) }
                }
                v = 1 - it.mask.density * (1 - v)
                m *= it.mask.isInverted ? 1 - v : v
                if m == 0 { return 0 }
            }
            return m
        }
    }

    static func drawStack(_ layers: [Layer], into canvas: inout Canvas, inherited: Inherited) {
        // Основание обтравки: слой без обтравки, по альфе которого режутся слои с обтравкой выше.
        // Если основание скрыто, слои с обтравкой над ним тоже не видны; если основания нет (нижний слой
        // или основание — неподдержанный слой / группа pass through), слой рисуется без обрезки.
        enum ClipBase { case none, hidden, base(MaskSet, Source) }
        var clipBase = ClipBase.none
        for layer in layers {
            if layer.isClippingMask, case .hidden = clipBase { continue }
            guard layer.isVisible else {
                if !layer.isClippingMask { clipBase = .hidden }
                continue
            }
            switch layer.content {
            case .unsupported:
                if !layer.isClippingMask { clipBase = .none }
                continue
            case .group(let children) where layer.blendMode == .passThrough:
                var inner = inherited
                inner.opacity *= layer.opacity
                let groupMasks = MaskSet(layer, canvas: canvas)
                if !groupMasks.isEmpty { inner.masks.append(groupMasks) }
                drawStack(children, into: &canvas, inherited: inner)
                if !layer.isClippingMask { clipBase = .none }
                continue
            default:
                break
            }
            guard let source = makeSource(layer, canvas: canvas) else { continue }
            let masks = MaskSet(layer, canvas: canvas)
            var clip: (masks: MaskSet, source: Source)?
            if layer.isClippingMask, case .base(let baseMasks, let baseSource) = clipBase { clip = (baseMasks, baseSource) }
            composite(source, layer: layer, masks: masks, clip: clip, inherited: inherited, into: &canvas)
            if !layer.isClippingMask { clipBase = .base(masks, source) }
        }
    }

    static func makeSource(_ layer: Layer, canvas: Canvas) -> Source? {
        let level = canvas.level
        switch layer.content {
        case .bitmap(let bitmap):
            let ox = layer.position.x >> level, oy = layer.position.y >> level
            let view = bitmap.view(level: level, x0: canvas.x - ox, y0: canvas.y - oy,
                                   x1: canvas.x + canvas.image.width - ox, y1: canvas.y + canvas.image.height - oy)
            return Source(width: view.width, height: view.height, originX: ox, originY: oy) { x, y in
                SIMD4(view.value(x: x, y: y, channel: 0), view.value(x: x, y: y, channel: 1),
                      view.value(x: x, y: y, channel: 2), view.value(x: x, y: y, channel: 3))
            }
        case .group(let children):
            // Изолированная группа: рисуется отдельно на прозрачном фоне той же области.
            var buffer = Canvas(x: canvas.x, y: canvas.y, image: FloatImage(width: canvas.image.width, height: canvas.image.height, channels: 4), level: level)
            drawStack(children, into: &buffer, inherited: Inherited())
            let image = buffer.image
            return Source(width: image.width, height: image.height, originX: canvas.x, originY: canvas.y) { x, y in
                SIMD4(image[x, y, 0], image[x, y, 1], image[x, y, 2], image[x, y, 3])
            }
        case .unsupported:
            return nil
        }
    }

    /// Альфа основания обтравки (альфа пикселя × маски основания, без его непрозрачности — проект п. 9).
    @inline(__always)
    static func clipAlpha(_ clip: (masks: MaskSet, source: Source), x: Int, y: Int) -> Float {
        let lx = x - clip.source.originX, ly = y - clip.source.originY
        guard lx >= 0, ly >= 0, lx < clip.source.width, ly < clip.source.height else { return 0 }
        return clip.source.sample(lx, ly).w * clip.masks.value(x: x, y: y)
    }

    static func composite(_ source: Source, layer: Layer, masks: MaskSet, clip: (masks: MaskSet, source: Source)?, inherited: Inherited, into canvas: inout Canvas) {
        let x0 = max(canvas.x, source.originX), y0 = max(canvas.y, source.originY)
        let x1 = min(canvas.x + canvas.image.width, source.originX + source.width)
        let y1 = min(canvas.y + canvas.image.height, source.originY + source.height)
        guard x0 < x1, y0 < y1 else { return }
        let opacity = layer.opacity * inherited.opacity
        let mode = layer.blendMode
        let cw = canvas.image.width
        for y in y0..<y1 {
            for x in x0..<x1 {
                let s = source.sample(x - source.originX, y - source.originY)
                var a_s = s.w * opacity
                if a_s <= 0 { continue }
                if !masks.isEmpty { a_s *= masks.value(x: x, y: y) }
                for m in inherited.masks { a_s *= m.value(x: x, y: y) }
                if let clip { a_s *= clipAlpha(clip, x: x, y: y) }
                if a_s <= 0 { continue }
                let i = ((y - canvas.y) * cw + (x - canvas.x)) * 4
                let cb = SIMD3(canvas.image.data[i], canvas.image.data[i + 1], canvas.image.data[i + 2])
                let a_b = canvas.image.data[i + 3]
                let cs = SIMD3(s.x, s.y, s.z)
                let co: SIMD3<Float>
                if mode == .behind {
                    co = a_b * cb + (1 - a_b) * a_s * cs
                } else {
                    let mixed = (1 - a_b) * cs + a_b * mode.apply(cb, cs)
                    co = a_s * mixed + (1 - a_s) * a_b * cb
                }
                let a_o = a_s + a_b * (1 - a_s)
                let c = a_o > 0 ? co / a_o : SIMD3(repeating: 0)
                canvas.image.data[i] = min(max(c.x, 0), 1)
                canvas.image.data[i + 1] = min(max(c.y, 0), 1)
                canvas.image.data[i + 2] = min(max(c.z, 0), 1)
                canvas.image.data[i + 3] = min(a_o, 1)
            }
        }
    }
}
