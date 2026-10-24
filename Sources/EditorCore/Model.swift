import Foundation

/// Модель документа.
/// Все типы — значения; пиксели — в общих неизменяемых плитках, поэтому копия документа дешёвая
/// и каждое состояние годится как снимок для рендера, сохранения и истории.

public struct LayerID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let uuid: UUID
    public init(_ uuid: UUID = UUID()) { self.uuid = uuid }
    public var description: String { uuid.uuidString }
}

/// Целочисленная точка в координатах документа: начало вверху слева.
public struct PixelPoint: Hashable, Sendable, Codable {
    public var x: Int
    public var y: Int
    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
    public static let zero = PixelPoint(x: 0, y: 0)
}

/// Маска слоя. Растр — один канал; вне растра действует `backgroundValue`
/// (в .pxd: 0 у маски «Hide All», 1 у «Reveal All»; растр у таких масок пустой 0×0).
public struct LayerMask: Sendable {
    public var id = LayerID()
    public var bitmap: Bitmap?
    public var offset: PixelPoint = .zero
    public var backgroundValue: Float
    /// Плотность 0…1: m' = 1 − density·(1 − m).
    public var density: Float = 1
    public var isInverted = false
    public var isEnabled = true

    public init(bitmap: Bitmap?, offset: PixelPoint = .zero, backgroundValue: Float) {
        precondition(bitmap == nil || bitmap!.channels == 1, "маска — один канал")
        self.bitmap = bitmap
        self.offset = offset
        self.backgroundValue = backgroundValue
    }

    public static func revealAll() -> LayerMask { LayerMask(bitmap: nil, backgroundValue: 1) }
    public static func hideAll() -> LayerMask { LayerMask(bitmap: nil, backgroundValue: 0) }

    /// Значение маски 0…1 в точке документа с учётом плотности и инверсии.
    @inline(__always)
    public func value(atDocumentX x: Int, y: Int) -> Float {
        var m = backgroundValue
        if let bitmap {
            let lx = x - offset.x, ly = y - offset.y
            if lx >= 0, ly >= 0, lx < bitmap.width, ly < bitmap.height {
                m = bitmap.value(x: lx, y: ly, channel: 0)
            }
        }
        m = 1 - density * (1 - m)
        return isInverted ? 1 - m : m
    }
}

/// Что лежит в слое. Виды, которые рендер этапа 1 не рисует, хранятся и явно сообщаются как неподдержанные.
public enum LayerContent: Sendable {
    case bitmap(Bitmap)
    case group([Layer])
    /// Слои коррекций, эффектов, текста, фигур, видео, RAW — до своих этапов хранятся как есть.
    case unsupported(kind: String)
}

public struct Layer: Sendable, Identifiable {
    public var id = LayerID()
    public var name: String
    public var content: LayerContent
    /// Левый верхний угол растра слоя в координатах документа.
    public var position: PixelPoint = .zero
    public var isVisible = true
    public var isLocked = false
    /// Непрозрачность 0…1 (в интерфейсе и AppleScript — 0…100).
    public var opacity: Float = 1
    public var blendMode: BlendMode = .normal
    /// Обрезать слой по ближайшему снизу слою без обтравки.
    public var isClippingMask = false
    public var preserveTransparency = false
    public var masks: [LayerMask] = []

    public init(name: String, content: LayerContent) {
        self.name = name
        self.content = content
    }

    public static func bitmap(name: String, _ bitmap: Bitmap, at position: PixelPoint = .zero) -> Layer {
        var layer = Layer(name: name, content: .bitmap(bitmap))
        layer.position = position
        return layer
    }

    public static func group(name: String, _ children: [Layer], blendMode: BlendMode = .passThrough) -> Layer {
        var layer = Layer(name: name, content: .group(children))
        layer.blendMode = blendMode
        return layer
    }

    /// Совокупное значение всех включённых масок (перемножение — см. проект, п. 8).
    @inline(__always)
    func maskValue(x: Int, y: Int) -> Float {
        var m: Float = 1
        for mask in masks where mask.isEnabled {
            m *= mask.value(atDocumentX: x, y: y)
            if m == 0 { return 0 }
        }
        return m
    }
}

public enum DocumentError: Error, Equatable {
    case unsupportedColorProfile(String)
    case layerNotFound(LayerID)
}

public struct Document: Sendable {
    public var width: Int
    public var height: Int
    public var depth: BitDepth
    /// Название профиля. Этап 1 поддерживает только sRGB (проект, п. 5).
    public var colorProfile: String = "sRGB"
    public var resolution: Double = 72
    /// Слои снизу вверх: индекс 0 — нижний.
    public var layers: [Layer] = []

    public init(width: Int, height: Int, depth: BitDepth) {
        self.width = width
        self.height = height
        self.depth = depth
    }

    /// Сколько байт занимают пиксели слоёв и масок (уникальные плитки; общие плитки считаются один раз).
    public var pixelBytes: Int {
        var seen = Set<ObjectIdentifier>()
        var total = 0
        func add(_ b: Bitmap) {
            for case let t? in b.tiles where seen.insert(ObjectIdentifier(t)).inserted {
                total += t.width * t.height * t.channels * (t.depth == .u16 ? 2 : 1)
            }
        }
        func walk(_ list: [Layer]) {
            for l in list {
                switch l.content {
                case .bitmap(let b): add(b)
                case .group(let c): walk(c)
                case .unsupported: break
                }
                for m in l.masks { if let b = m.bitmap { add(b) } }
            }
        }
        walk(layers)
        return total
    }

    /// Поиск слоя на любом уровне вложенности.
    public func layer(_ id: LayerID) -> Layer? {
        func find(_ list: [Layer]) -> Layer? {
            for l in list {
                if l.id == id { return l }
                if case .group(let children) = l.content, let found = find(children) { return found }
            }
            return nil
        }
        return find(layers)
    }

    /// Изменить слой на любом уровне вложенности.
    public mutating func updateLayer(_ id: LayerID, _ change: (inout Layer) -> Void) throws {
        func apply(_ list: inout [Layer]) -> Bool {
            for i in list.indices {
                if list[i].id == id {
                    change(&list[i])
                    return true
                }
                if case .group(var children) = list[i].content, apply(&children) {
                    list[i].content = .group(children)
                    return true
                }
            }
            return false
        }
        guard apply(&layers) else { throw DocumentError.layerNotFound(id) }
    }
}
