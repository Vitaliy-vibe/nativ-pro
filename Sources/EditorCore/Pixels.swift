/// Хранение пикселей: неизменяемые плитки, растр из плиток и плотное изображение для рендера.

/// Глубина цвета документа (бит на канал).
public enum BitDepth: Int, Sendable, Codable {
    case u8 = 8
    case u16 = 16

    var maxValue: Float { self == .u8 ? 255 : 65535 }
}

/// Плитка: прямоугольник не больше `Tile.size`×`Tile.size`, каналы без премультипликации.
/// Неизменяемая — разные состояния документа используют одни и те же плитки.
public final class Tile: Sendable {
    public static let size = 256

    public enum Storage: Sendable {
        case u8([UInt8])
        case u16([UInt16])
    }

    public let width: Int
    public let height: Int
    public let channels: Int
    public let storage: Storage

    public init(width: Int, height: Int, channels: Int, storage: Storage) {
        precondition(width > 0 && height > 0 && width <= Tile.size && height <= Tile.size)
        switch storage {
        case .u8(let v): precondition(v.count == width * height * channels)
        case .u16(let v): precondition(v.count == width * height * channels)
        }
        self.width = width
        self.height = height
        self.channels = channels
        self.storage = storage
    }

    public var depth: BitDepth {
        if case .u8 = storage { return .u8 }
        return .u16
    }

    /// Значение канала 0…1.
    @inline(__always)
    public func value(x: Int, y: Int, channel: Int) -> Float {
        let i = (y * width + x) * channels + channel
        switch storage {
        case .u8(let v): return Float(v[i]) / 255
        case .u16(let v): return Float(v[i]) / 65535
        }
    }
}

/// Исходный файл, из которого растр получен без изменений.
/// Хранится в документе вместо плиток, пока растр не меняли.
public struct OriginalSource: Sendable, Equatable {
    /// Формат файла: "png" (декодер в ядре; другие форматы — через декодеры платформы, позже).
    public let format: String
    public let bytes: [UInt8]

    public init(format: String, bytes: [UInt8]) {
        self.format = format
        self.bytes = bytes
    }
}

/// Растр произвольного размера из плиток. `nil` на месте плитки — все каналы 0 (пусто/прозрачно).
public struct Bitmap: Sendable {
    public let width: Int
    public let height: Int
    public let channels: Int
    public let depth: BitDepth
    public private(set) var tiles: [Tile?]
    /// Исходный файл растра; сбрасывается при любом изменении плиток.
    public private(set) var originalSource: OriginalSource?

    public var tilesAcross: Int { (width + Tile.size - 1) / Tile.size }
    public var tilesDown: Int { (height + Tile.size - 1) / Tile.size }

    public init(width: Int, height: Int, channels: Int, depth: BitDepth) {
        precondition(width >= 0 && height >= 0 && (channels == 1 || channels == 4))
        self.width = width
        self.height = height
        self.channels = channels
        self.depth = depth
        self.tiles = Array(repeating: nil, count: ((width + Tile.size - 1) / Tile.size) * ((height + Tile.size - 1) / Tile.size))
    }

    /// Строит растр из плотного изображения (значения 0…1 с квантованием до глубины).
    public init(image: FloatImage, depth: BitDepth) {
        self.init(width: image.width, height: image.height, channels: image.channels, depth: depth)
        for ty in 0..<tilesDown {
            for tx in 0..<tilesAcross {
                let x0 = tx * Tile.size, y0 = ty * Tile.size
                let w = min(Tile.size, width - x0), h = min(Tile.size, height - y0)
                var allZero = true
                switch depth {
                case .u8:
                    var buf = [UInt8](repeating: 0, count: w * h * channels)
                    for y in 0..<h {
                        for x in 0..<w {
                            for c in 0..<channels {
                                let v = UInt8((min(max(image[x0 + x, y0 + y, c], 0), 1) * 255).rounded())
                                buf[(y * w + x) * channels + c] = v
                                if v != 0 { allZero = false }
                            }
                        }
                    }
                    if !allZero { tiles[ty * tilesAcross + tx] = Tile(width: w, height: h, channels: channels, storage: .u8(buf)) }
                case .u16:
                    var buf = [UInt16](repeating: 0, count: w * h * channels)
                    for y in 0..<h {
                        for x in 0..<w {
                            for c in 0..<channels {
                                let v = UInt16((min(max(image[x0 + x, y0 + y, c], 0), 1) * 65535).rounded())
                                buf[(y * w + x) * channels + c] = v
                                if v != 0 { allZero = false }
                            }
                        }
                    }
                    if !allZero { tiles[ty * tilesAcross + tx] = Tile(width: w, height: h, channels: channels, storage: .u16(buf)) }
                }
            }
        }
    }

    /// Значение канала 0…1; за пределами растра — 0.
    @inline(__always)
    public func value(x: Int, y: Int, channel: Int) -> Float {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        guard let tile = tiles[(y / Tile.size) * tilesAcross + x / Tile.size] else { return 0 }
        return tile.value(x: x % Tile.size, y: y % Tile.size, channel: channel)
    }

    /// Привязать исходный файл. Вызывающий отвечает за то, что пиксели растра в точности получены из него
    /// (см. PNG.decodeBitmap); иначе в документ попадёт не то изображение.
    public func withOriginalSource(_ source: OriginalSource) -> Bitmap {
        var copy = self
        copy.originalSource = source
        return copy
    }

    /// Заменяет одну плитку; остальные остаются общими с исходным растром. Исходный файл больше не соответствует пикселям.
    public mutating func replaceTile(tx: Int, ty: Int, with tile: Tile?) {
        originalSource = nil
        if let tile {
            precondition(tile.channels == channels && tile.depth == depth)
            precondition(tile.width == min(Tile.size, width - tx * Tile.size) && tile.height == min(Tile.size, height - ty * Tile.size))
        }
        tiles[ty * tilesAcross + tx] = tile
    }

    /// Плотная копия во Float.
    public func toImage() -> FloatImage {
        var img = FloatImage(width: width, height: height, channels: channels)
        for y in 0..<height {
            for x in 0..<width {
                for c in 0..<channels {
                    img[x, y, c] = value(x: x, y: y, channel: c)
                }
            }
        }
        return img
    }
}

/// Плотное изображение во Float, построчно, каналы подряд. Используется рендером и вводом-выводом.
public struct FloatImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let channels: Int
    public var data: [Float]

    public init(width: Int, height: Int, channels: Int, fill: Float = 0) {
        self.width = width
        self.height = height
        self.channels = channels
        self.data = [Float](repeating: fill, count: width * height * channels)
    }

    @inline(__always)
    public subscript(x: Int, y: Int, c: Int) -> Float {
        get { data[(y * width + x) * channels + c] }
        set { data[(y * width + x) * channels + c] = newValue }
    }
}
