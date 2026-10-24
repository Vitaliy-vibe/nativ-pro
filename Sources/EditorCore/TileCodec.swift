/// Кодирование плиток для файла документа.
///
/// `delta-planes-zlib` (формат 2): по каждому каналу — разность с соседом слева в строке (как фильтр Sub в PNG,
/// по модулю 2^8 или 2^16), затем значения раскладываются по плоскостям: канал за каналом, у 16 бит — сначала
/// старшие байты, потом младшие. Плавные области дают длинные серии нулей, и zlib сжимает их в разы лучше,
/// чем сырые пиксели. `raw-zlib` (формат 1) — сырые пиксели little-endian; читается для старых файлов.
public enum TileCodec: String, Sendable {
    case rawZlib = "raw-zlib"
    case deltaPlanesZlib = "delta-planes-zlib"

    public static let current = TileCodec.deltaPlanesZlib

    public func encode(_ tile: Tile, level: Int32 = 1) throws -> [UInt8] {
        switch self {
        case .rawZlib: return try PNG.deflate(DocumentFile.tileBytes(tile), level: level)
        case .deltaPlanesZlib: return try PNG.deflate(TileCodec.deltaPlanes(tile), level: level)
        }
    }

    public func decode(_ packed: [UInt8], width: Int, height: Int, channels: Int, depth: BitDepth) throws -> Tile {
        let count = width * height * channels
        let bytesPer = depth == .u16 ? 2 : 1
        let raw = try PNG.inflate(packed, expected: count * bytesPer)
        switch self {
        case .rawZlib:
            if depth == .u8 { return Tile(width: width, height: height, channels: channels, storage: .u8(raw)) }
            var v = [UInt16](repeating: 0, count: count)
            for k in 0..<count { v[k] = UInt16(raw[2 * k]) | UInt16(raw[2 * k + 1]) << 8 }
            return Tile(width: width, height: height, channels: channels, storage: .u16(v))
        case .deltaPlanesZlib:
            return TileCodec.undoDeltaPlanes(raw, width: width, height: height, channels: channels, depth: depth)
        }
    }

    static func deltaPlanes(_ tile: Tile) -> [UInt8] {
        let w = tile.width, h = tile.height, ch = tile.channels, n = w * h
        switch tile.storage {
        case .u8(let v):
            var out = [UInt8](repeating: 0, count: n * ch)
            for c in 0..<ch {
                let plane = c * n
                for y in 0..<h {
                    var prev: UInt8 = 0
                    for x in 0..<w {
                        let cur = v[(y * w + x) * ch + c]
                        out[plane + y * w + x] = cur &- prev
                        prev = cur
                    }
                }
            }
            return out
        case .u16(let v):
            var out = [UInt8](repeating: 0, count: n * ch * 2)
            for c in 0..<ch {
                let hi = 2 * c * n, lo = hi + n
                for y in 0..<h {
                    var prev: UInt16 = 0
                    for x in 0..<w {
                        let cur = v[(y * w + x) * ch + c]
                        let d = cur &- prev
                        prev = cur
                        out[hi + y * w + x] = UInt8(d >> 8)
                        out[lo + y * w + x] = UInt8(d & 0xFF)
                    }
                }
            }
            return out
        }
    }

    static func undoDeltaPlanes(_ raw: [UInt8], width w: Int, height h: Int, channels ch: Int, depth: BitDepth) -> Tile {
        let n = w * h
        switch depth {
        case .u8:
            var v = [UInt8](repeating: 0, count: n * ch)
            for c in 0..<ch {
                let plane = c * n
                for y in 0..<h {
                    var prev: UInt8 = 0
                    for x in 0..<w {
                        prev = prev &+ raw[plane + y * w + x]
                        v[(y * w + x) * ch + c] = prev
                    }
                }
            }
            return Tile(width: w, height: h, channels: ch, storage: .u8(v))
        case .u16:
            var v = [UInt16](repeating: 0, count: n * ch)
            for c in 0..<ch {
                let hi = 2 * c * n, lo = hi + n
                for y in 0..<h {
                    var prev: UInt16 = 0
                    for x in 0..<w {
                        let d = UInt16(raw[hi + y * w + x]) << 8 | UInt16(raw[lo + y * w + x])
                        prev = prev &+ d
                        v[(y * w + x) * ch + c] = prev
                    }
                }
            }
            return Tile(width: w, height: h, channels: ch, storage: .u16(v))
        }
    }
}
