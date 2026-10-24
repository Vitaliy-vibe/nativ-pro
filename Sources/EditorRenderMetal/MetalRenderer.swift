#if canImport(Metal)
import EditorCore
import Foundation
import Metal

/// Рендер документа на GPU: область в заданном масштабе (уровне), по плиткам.
/// Логика обхода слоёв повторяет CPURenderer (группы, pass through, маски, обтравка, явный список неподдержанных);
/// пиксельные формулы — в MetalShaders.swift.
/// Плитки слоёв и масок загружаются в своём формате (8/16 бит, без перевода во Float) и кешируются:
/// плитки неизменяемые, поэтому текстура верна, пока жива плитка. Холст и покрытие области — Float32.
public final class MetalRenderer {
    public enum Failure: Error, CustomStringConvertible {
        case noDevice
        case shader(String)
        case commandFailed(String)
        public var description: String {
            switch self {
            case .noDevice: return "нет устройства Metal"
            case .shader(let m): return "шейдеры: \(m)"
            case .commandFailed(let m): return "команда GPU: \(m)"
            }
        }
    }

    let device: MTLDevice
    let queue: MTLCommandQueue
    let fill: MTLComputePipelineState
    let maskInit: MTLComputePipelineState
    let put: MTLComputePipelineState
    let mulValue: MTLComputePipelineState
    let mulCov: MTLComputePipelineState
    let compositePipeline: MTLComputePipelineState
    let textures: TextureCache
    let mips: MipCache

    /// `textureBudget` — потолок кеша текстур плиток. Видимые плитки окна 2560×1440 в масштабе 100 % для 5 слоёв
    /// занимают ~150 МБ; полный рендер идёт проходами ≤ 2048 и укладывается в тот же потолок.
    public init(textureBudget: Int = 512 << 20, mips: MipCache = .shared) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { throw Failure.noDevice }
        self.device = device
        self.queue = queue
        self.mips = mips
        textures = TextureCache(budget: textureBudget)
        let options = MTLCompileOptions()
        options.mathMode = .safe
        let library: MTLLibrary
        do { library = try device.makeLibrary(source: metalShaderSource, options: options) } catch { throw Failure.shader("\(error)") }
        func pipeline(_ name: String) throws -> MTLComputePipelineState {
            guard let f = library.makeFunction(name: name) else { throw Failure.shader("нет функции \(name)") }
            return try device.makeComputePipelineState(function: f)
        }
        fill = try pipeline("fill_r")
        maskInit = try pipeline("mask_init")
        put = try pipeline("put_r")
        mulValue = try pipeline("mul_value")
        mulCov = try pipeline("mul_cov")
        compositePipeline = try pipeline("composite")
    }

    /// Наибольшая сторона области за один проход; бо́льшие области рисуются кусками и сшиваются,
    /// чтобы временные текстуры (покрытие, маски) не занимали сотни мегабайт.
    public static let maxPassSide = 2048

    public func render(_ document: Document) throws -> RenderResult {
        try render(document, region: .whole(document))
    }

    public func render(_ document: Document, region: RenderRegion) throws -> RenderResult {
        let side = MetalRenderer.maxPassSide
        guard region.width > side || region.height > side else { return try renderPass(document, region: region) }
        var image = FloatImage(width: region.width, height: region.height, channels: 4)
        var unsupported: [UnsupportedLayer] = []
        for y0 in stride(from: 0, to: region.height, by: side) {
            for x0 in stride(from: 0, to: region.width, by: side) {
                let part = try renderPass(document, region: RenderRegion(x: region.x + x0, y: region.y + y0, width: min(side, region.width - x0),
                                                                          height: min(side, region.height - y0), level: region.level))
                unsupported = part.unsupported
                for y in 0..<part.image.height {
                    let dst = ((y0 + y) * region.width + x0) * 4, src = y * part.image.width * 4
                    image.data.replaceSubrange(dst..<(dst + part.image.width * 4), with: part.image.data[src..<(src + part.image.width * 4)])
                }
            }
        }
        return RenderResult(image: image, unsupported: unsupported)
    }

    func renderPass(_ document: Document, region: RenderRegion) throws -> RenderResult {
        guard document.colorProfile == "sRGB" else { throw DocumentError.unsupportedColorProfile(document.colorProfile) }
        guard let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { throw Failure.commandFailed("нет буфера команд") }
        // Все действия области — в одном кодировщике: команды выполняются по порядку (serial dispatch).
        let pass = Pass(renderer: self, encoder: enc, region: region)
        let canvas = try pass.regionTexture(.rgba32Float)
        try pass.drawStack(document.layers, canvas: canvas, inherited: Inherited())
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        if let error = cb.error { throw Failure.commandFailed("\(error)") }
        return RenderResult(image: readRGBA(canvas), unsupported: unsupportedLayers(document.layers))
    }

    func unsupportedLayers(_ layers: [Layer]) -> [UnsupportedLayer] {
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

    /// Сбросить кеш текстур (например, при нехватке памяти).
    public func purgeTextures() { textures.removeAll() }

    /// Сколько байт занимают закешированные текстуры плиток.
    public var textureBytes: Int { textures.currentBytes }

    // MARK: структуры параметров (раскладка совпадает с MSL)

    struct Inherited {
        var opacity: Float = 1
        var maskOwners: [Layer] = []
    }

    struct CompParams { var origin: SIMD2<Int32>; var mode: Int32; var opacity: Float }               // 16 байт
    struct ExtentParams { var origin: SIMD2<Int32>; var size: SIMD2<Int32>; var background: Float }    // 20 → 24 байта
    struct PutParams { var origin: SIMD2<Int32>; var channel: Int32 }                                  // 12 → 16 байт
    struct ValueParams { var density: Float; var inverted: Int32 }                                     // 8 байт

    /// Плитка растра, попавшая в область: текстура и левый верхний угол в пикселях уровня (координаты документа).
    struct TilePiece {
        let texture: MTLTexture
        let x: Int
        let y: Int
    }

    /// Один проход рендера области: кодирует команды в общий кодировщик.
    struct Pass {
        let renderer: MetalRenderer
        let encoder: MTLComputeCommandEncoder
        let region: RenderRegion

        var level: Int { region.level }

        func regionTexture(_ format: MTLPixelFormat) throws -> MTLTexture {
            try renderer.makeTexture(format, region.width, region.height, write: true)
        }

        /// Плитки растра (на уровне), пересекающие область. `origin` — левый верхний угол растра в документе.
        /// Уменьшенные копии и загрузка в текстуры готовятся параллельно (первый показ в мелком масштабе).
        func pieces(_ bitmap: Bitmap, origin: PixelPoint) throws -> [TilePiece] {
            let ox = origin.x >> level, oy = origin.y >> level
            let span = Tile.size >> level
            let (w, h) = bitmap.levelSize(level)
            let x0 = region.x - ox, y0 = region.y - oy, x1 = x0 + region.width, y1 = y0 + region.height
            guard x1 > 0, y1 > 0, x0 < w, y0 < h else { return [] }
            var wanted: [(tx: Int, ty: Int, source: Tile)] = []
            for ty in (max(0, y0) / span)...((min(h, y1) - 1) / span) {
                for tx in (max(0, x0) / span)...((min(w, x1) - 1) / span) {
                    if let source = bitmap.tiles[ty * bitmap.tilesAcross + tx] { wanted.append((tx, ty, source)) }
                }
            }
            final class Results: @unchecked Sendable {
                var textures: [MTLTexture?]
                var error: Error?
                let lock = NSLock()
                init(_ n: Int) { textures = Array(repeating: nil, count: n) }
            }
            let results = Results(wanted.count)
            let work = wanted, lvl = level, mips = renderer.mips, cache = renderer.textures, device = renderer.device
            DispatchQueue.concurrentPerform(iterations: work.count) { i in
                do {
                    let mip = mips.mip(work[i].source, level: lvl)
                    let t = try cache.texture(for: mip, source: work[i].source, level: lvl, device: device)
                    results.lock.lock()
                    results.textures[i] = t
                    results.lock.unlock()
                } catch {
                    results.lock.lock()
                    results.error = error
                    results.lock.unlock()
                }
            }
            if let error = results.error { throw error }
            return work.enumerated().map { i, item in
                TilePiece(texture: results.textures[i]!, x: ox + item.tx * span, y: oy + item.ty * span)
            }
        }

        func dispatch(_ pipeline: MTLComputePipelineState, width: Int, height: Int, textures: [MTLTexture], params: [UInt8]?) {
            encoder.setComputePipelineState(pipeline)
            for (i, t) in textures.enumerated() { encoder.setTexture(t, index: i) }
            if let params { params.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 0) } }
            let w = pipeline.threadExecutionWidth
            let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
            encoder.dispatchThreads(MTLSize(width: max(width, 1), height: max(height, 1), depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
        }

        func fillValue(_ t: MTLTexture, _ v: Float) {
            dispatch(renderer.fill, width: t.width, height: t.height, textures: [t], params: bytesOf(v))
        }

        /// coverage *= маски слоя (каждая маска: фон вне растра, 0 в пустых плитках, значения плиток; затем плотность и инверсия).
        func applyMasks(_ masks: [LayerMask], to cov: MTLTexture) throws {
            for mask in masks where mask.isEnabled {
                let values = try regionTexture(.r32Float)
                if let bitmap = mask.bitmap {
                    let (w, h) = bitmap.levelSize(level)
                    let p = ExtentParams(origin: SIMD2(Int32((mask.offset.x >> level) - region.x), Int32((mask.offset.y >> level) - region.y)),
                                         size: SIMD2(Int32(w), Int32(h)), background: mask.backgroundValue)
                    dispatch(renderer.maskInit, width: values.width, height: values.height, textures: [values], params: bytesOf(p))
                    for piece in try pieces(bitmap, origin: mask.offset) {
                        let pp = PutParams(origin: SIMD2(Int32(piece.x - region.x), Int32(piece.y - region.y)), channel: 0)
                        dispatch(renderer.put, width: piece.texture.width, height: piece.texture.height, textures: [values, piece.texture], params: bytesOf(pp))
                    }
                } else {
                    fillValue(values, mask.backgroundValue)
                }
                let vp = ValueParams(density: mask.density, inverted: mask.isInverted ? 1 : 0)
                dispatch(renderer.mulValue, width: cov.width, height: cov.height, textures: [cov, values], params: bytesOf(vp))
            }
        }

        enum Source {
            case tiles([TilePiece])
            case buffer(MTLTexture)   // изолированная группа: текстура размером с область

            var pieces: [TilePiece] {
                switch self {
                case .tiles(let p): return p
                case .buffer(let t): return [TilePiece(texture: t, x: 0, y: 0)]
                }
            }
        }

        func drawStack(_ layers: [Layer], canvas: MTLTexture, inherited: Inherited) throws {
            enum ClipBase { case none, hidden, base(MTLTexture) }
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
                    if !layer.masks.isEmpty { inner.maskOwners.append(layer) }
                    try drawStack(children, canvas: canvas, inherited: inner)
                    if !layer.isClippingMask { clipBase = .none }
                    continue
                default:
                    break
                }
                let source: Source
                switch layer.content {
                case .bitmap(let bitmap):
                    source = .tiles(try pieces(bitmap, origin: layer.position))
                case .group(let children):
                    let buffer = try regionTexture(.rgba32Float)
                    try drawStack(children, canvas: buffer, inherited: Inherited())
                    source = .buffer(buffer)
                default:
                    continue
                }
                // Для буфера группы координаты уже относительно области: смещение 0.
                let isBuffer: Bool
                if case .buffer = source { isBuffer = true } else { isBuffer = false }
                func offset(_ p: TilePiece) -> SIMD2<Int32> {
                    isBuffer ? .zero : SIMD2(Int32(p.x - region.x), Int32(p.y - region.y))
                }
                // Покрытие: маски слоя × маски групп pass through × основание обтравки.
                let cov = try regionTexture(.r32Float)
                fillValue(cov, 1)
                try applyMasks(layer.masks, to: cov)
                for owner in inherited.maskOwners { try applyMasks(owner.masks, to: cov) }
                if layer.isClippingMask, case .base(let baseCov) = clipBase {
                    dispatch(renderer.mulCov, width: cov.width, height: cov.height, textures: [cov, baseCov], params: nil)
                }
                let mode = Int32(BlendMode.allCases.firstIndex(of: layer.blendMode)!)
                for piece in source.pieces {
                    let params = CompParams(origin: offset(piece), mode: mode, opacity: layer.opacity * inherited.opacity)
                    dispatch(renderer.compositePipeline, width: piece.texture.width, height: piece.texture.height,
                             textures: [canvas, piece.texture, cov], params: bytesOf(params))
                }
                if !layer.isClippingMask {
                    // Основание обтравки: альфа источника × маски основания (без непрозрачности — как в CPURenderer).
                    let baseCov = try regionTexture(.r32Float)
                    fillValue(baseCov, 0)
                    for piece in source.pieces {
                        let pp = PutParams(origin: offset(piece), channel: 3)
                        dispatch(renderer.put, width: piece.texture.width, height: piece.texture.height, textures: [baseCov, piece.texture], params: bytesOf(pp))
                    }
                    try applyMasks(layer.masks, to: baseCov)
                    clipBase = .base(baseCov)
                }
            }
        }
    }

    // MARK: текстуры

    func makeTexture(_ format: MTLPixelFormat, _ w: Int, _ h: Int, write: Bool) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: max(w, 1), height: max(h, 1), mipmapped: false)
        d.usage = write ? [.shaderRead, .shaderWrite] : [.shaderRead]
        d.storageMode = .shared
        guard let t = device.makeTexture(descriptor: d) else { throw Failure.commandFailed("текстура \(w)×\(h)") }
        return t
    }

    func readRGBA(_ t: MTLTexture) -> FloatImage {
        var img = FloatImage(width: t.width, height: t.height, channels: 4)
        img.data.withUnsafeMutableBytes { raw in
            t.getBytes(raw.baseAddress!, bytesPerRow: t.width * 16, from: MTLRegionMake2D(0, 0, t.width, t.height), mipmapLevel: 0)
        }
        return img
    }
}

/// Байты значения для setBytes, дополненные нулями до шага выравнивания: в MSL структура
/// {int2, int2, float} занимает 24 байта, а MemoryLayout.size в Swift — 20.
func bytesOf<T>(_ value: T) -> [UInt8] {
    var out = withUnsafeBytes(of: value) { Array($0) }
    out += [UInt8](repeating: 0, count: MemoryLayout<T>.stride - out.count)
    return out
}

/// Кеш текстур плиток: ключ — исходная плитка и уровень; слабая ссылка на плитку защищает от повторного
/// использования адреса умершей плитки. При превышении бюджета удаляются давно не использованные.
final class TextureCache: @unchecked Sendable {
    struct Key: Hashable {
        let tile: ObjectIdentifier
        let level: Int
    }

    final class Entry {
        weak var source: Tile?
        let texture: MTLTexture
        let bytes: Int
        var used: UInt64
        init(source: Tile, texture: MTLTexture, bytes: Int, used: UInt64) {
            self.source = source
            self.texture = texture
            self.bytes = bytes
            self.used = used
        }
    }

    let budget: Int
    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var bytes = 0
    private var clock: UInt64 = 0

    init(budget: Int) { self.budget = budget }

    var currentBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return bytes
    }

    func removeAll() {
        lock.lock()
        entries.removeAll()
        bytes = 0
        lock.unlock()
    }

    /// Текстура для `tile` (копии `source` на уровне `level`) в формате плитки: 8/16 бит, 1 или 4 канала.
    func texture(for tile: Tile, source: Tile, level: Int, device: MTLDevice) throws -> MTLTexture {
        let key = Key(tile: ObjectIdentifier(source), level: level)
        lock.lock()
        clock += 1
        if let e = entries[key], e.source === source {
            e.used = clock
            lock.unlock()
            return e.texture
        }
        lock.unlock()
        let format: MTLPixelFormat
        switch (tile.channels, tile.depth) {
        case (1, .u8): format = .r8Unorm
        case (1, .u16): format = .r16Unorm
        case (_, .u8): format = .rgba8Unorm
        case (_, .u16): format = .rgba16Unorm
        }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: tile.width, height: tile.height, mipmapped: false)
        d.usage = [.shaderRead]
        d.storageMode = .shared
        guard let t = device.makeTexture(descriptor: d) else { throw MetalRenderer.Failure.commandFailed("текстура плитки") }
        let region = MTLRegionMake2D(0, 0, tile.width, tile.height)
        let size: Int
        switch tile.storage {
        case .u8(let v):
            v.withUnsafeBytes { t.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: tile.width * tile.channels) }
            size = v.count
        case .u16(let v):
            v.withUnsafeBytes { t.replace(region: region, mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: tile.width * tile.channels * 2) }
            size = v.count * 2
        }
        lock.lock()
        clock += 1
        entries[key] = Entry(source: source, texture: t, bytes: size, used: clock)
        bytes += size
        if bytes > budget {
            for (k, e) in entries where e.source == nil {
                bytes -= e.bytes
                entries[k] = nil
            }
            if bytes > budget {
                for (k, e) in entries.sorted(by: { $0.value.used < $1.value.used }) {
                    bytes -= e.bytes
                    entries[k] = nil
                    if bytes <= budget * 3 / 4 { break }
                }
            }
        }
        lock.unlock()
        return t
    }
}
#endif
