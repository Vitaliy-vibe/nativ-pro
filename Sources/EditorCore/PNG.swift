import CZlib

/// Чтение и запись PNG (8/16 бит, серый/RGB/RGBA/палитра), без системных графических библиотек —
/// чтобы ядро одинаково работало на macOS и Linux. Повторяет tools/pngio.py.
public enum PNGError: Error, Equatable {
    case notPNG
    case unsupported(String)
    case corrupt(String)
}

public struct PNGImage: Sendable {
    /// RGBA 0…1 без премультипликации; серые и палитровые изображения разворачиваются в RGBA.
    public var image: FloatImage
    public var bitDepth: Int
    public var hasSRGBChunk: Bool
    public var iccProfileName: String?
}

public enum PNG {
    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    // MARK: чтение

    public static func decode(_ bytes: [UInt8]) throws -> PNGImage {
        guard bytes.count > 8, Array(bytes[0..<8]) == signature else { throw PNGError.notPNG }
        var pos = 8
        var width = 0, height = 0, depth = 0, colorType = 0
        var idat: [UInt8] = []
        var palette: [UInt8] = []
        var trns: [UInt8] = []
        var srgb = false
        var iccName: String?
        func u32(_ p: Int) -> Int { Int(bytes[p]) << 24 | Int(bytes[p + 1]) << 16 | Int(bytes[p + 2]) << 8 | Int(bytes[p + 3]) }
        while pos + 8 <= bytes.count {
            let length = u32(pos)
            let kind = String(decoding: bytes[(pos + 4)..<(pos + 8)], as: UTF8.self)
            let start = pos + 8
            guard start + length + 4 <= bytes.count else { throw PNGError.corrupt("обрезан блок \(kind)") }
            let data = bytes[start..<(start + length)]
            switch kind {
            case "IHDR":
                width = u32(start)
                height = u32(start + 4)
                depth = Int(bytes[start + 8])
                colorType = Int(bytes[start + 9])
                if bytes[start + 12] != 0 { throw PNGError.unsupported("чересстрочный PNG") }
            case "IDAT": idat.append(contentsOf: data)
            case "PLTE": palette = Array(data)
            case "tRNS": trns = Array(data)
            case "sRGB": srgb = true
            case "iCCP":
                if let zero = data.firstIndex(of: 0) { iccName = String(decoding: data[data.startIndex..<zero], as: UTF8.self) }
            case "IEND": pos = bytes.count
            default: break
            }
            pos = start + length + 4
        }
        let channelsByType = [0: 1, 2: 3, 3: 1, 4: 2, 6: 4]
        guard let ch = channelsByType[colorType] else { throw PNGError.unsupported("тип цвета \(colorType)") }
        guard depth == 8 || depth == 16 else { throw PNGError.unsupported("глубина \(depth) бит") }
        guard colorType != 3 || depth == 8 else { throw PNGError.unsupported("палитра с глубиной \(depth)") }
        let bpp = ch * depth / 8
        let stride = width * bpp
        let raw = try inflate(idat, expected: height * (stride + 1))
        let rows = try unfilter(raw, height: height, stride: stride, bpp: bpp)

        var img = FloatImage(width: width, height: height, channels: 4)
        let maxv: Float = depth == 16 ? 65535 : 255
        for y in 0..<height {
            let rowBase = y * stride
            for x in 0..<width {
                @inline(__always) func v(_ c: Int) -> Float {
                    let o = rowBase + (x * ch + c) * (depth / 8)
                    return depth == 16 ? Float(Int(rows[o]) << 8 | Int(rows[o + 1])) / maxv : Float(rows[o]) / maxv
                }
                var rgba: (Float, Float, Float, Float)
                switch colorType {
                case 0: rgba = (v(0), v(0), v(0), 1)
                case 4: rgba = (v(0), v(0), v(0), v(1))
                case 2: rgba = (v(0), v(1), v(2), 1)
                case 3:
                    let idx = Int(rows[rowBase + x])
                    guard idx * 3 + 2 < palette.count else { throw PNGError.corrupt("индекс палитры \(idx)") }
                    let a: Float = idx < trns.count ? Float(trns[idx]) / 255 : 1
                    rgba = (Float(palette[idx * 3]) / 255, Float(palette[idx * 3 + 1]) / 255, Float(palette[idx * 3 + 2]) / 255, a)
                default: rgba = (v(0), v(1), v(2), v(3))
                }
                img[x, y, 0] = rgba.0
                img[x, y, 1] = rgba.1
                img[x, y, 2] = rgba.2
                img[x, y, 3] = rgba.3
            }
        }
        return PNGImage(image: img, bitDepth: depth, hasSRGBChunk: srgb, iccProfileName: iccName)
    }

    /// Растр из PNG с привязанным исходным файлом: значения 8/16 бит переходят в плитки без потерь,
    /// поэтому документ может хранить сам PNG вместо плиток. Пиксели идут прямо в плитки, без промежуточного Float.
    public static func decodeBitmap(_ bytes: [UInt8]) throws -> Bitmap {
        let source = OriginalSource(format: "png", bytes: bytes)
        guard let (header, rows) = try decodeRows(bytes), header.colorType != 3 else {
            // Палитра: через общий путь (Float), это редкие и небольшие файлы.
            let png = try decode(bytes)
            return Bitmap(image: png.image, depth: png.bitDepth == 16 ? .u16 : .u8).withOriginalSource(source)
        }
        let (w, h, depth, colorType) = (header.width, header.height, header.depth, header.colorType)
        let ch = [0: 1, 2: 3, 4: 2, 6: 4][colorType]!
        let stride = w * ch * depth / 8
        var bitmap = Bitmap(width: w, height: h, channels: 4, depth: depth == 16 ? .u16 : .u8)
        for ty in 0..<bitmap.tilesDown {
            for tx in 0..<bitmap.tilesAcross {
                let x0 = tx * Tile.size, y0 = ty * Tile.size
                let tw = min(Tile.size, w - x0), th = min(Tile.size, h - y0)
                // Отображение каналов файла в RGBA: серый — в три канала, отсутствующая альфа — максимум.
                @inline(__always) func rgba(_ sample: (Int) -> Int, maxv: Int) -> (Int, Int, Int, Int) {
                    switch colorType {
                    case 0: let g = sample(0); return (g, g, g, maxv)
                    case 4: let g = sample(0); return (g, g, g, sample(1))
                    case 2: return (sample(0), sample(1), sample(2), maxv)
                    default: return (sample(0), sample(1), sample(2), sample(3))
                    }
                }
                var nonZero = false
                if depth == 16 {
                    var v = [UInt16](repeating: 0, count: tw * th * 4)
                    for y in 0..<th {
                        let row = (y0 + y) * stride
                        for x in 0..<tw {
                            let p = row + (x0 + x) * ch * 2
                            let px = rgba({ c in Int(rows[p + 2 * c]) << 8 | Int(rows[p + 2 * c + 1]) }, maxv: 65535)
                            let o = (y * tw + x) * 4
                            v[o] = UInt16(px.0); v[o + 1] = UInt16(px.1); v[o + 2] = UInt16(px.2); v[o + 3] = UInt16(px.3)
                            if px.0 | px.1 | px.2 | px.3 != 0 { nonZero = true }
                        }
                    }
                    if nonZero { bitmap.replaceTile(tx: tx, ty: ty, with: Tile(width: tw, height: th, channels: 4, storage: .u16(v))) }
                } else {
                    var v = [UInt8](repeating: 0, count: tw * th * 4)
                    for y in 0..<th {
                        let row = (y0 + y) * stride
                        for x in 0..<tw {
                            let p = row + (x0 + x) * ch
                            let px = rgba({ c in Int(rows[p + c]) }, maxv: 255)
                            let o = (y * tw + x) * 4
                            v[o] = UInt8(px.0); v[o + 1] = UInt8(px.1); v[o + 2] = UInt8(px.2); v[o + 3] = UInt8(px.3)
                            if px.0 | px.1 | px.2 | px.3 != 0 { nonZero = true }
                        }
                    }
                    if nonZero { bitmap.replaceTile(tx: tx, ty: ty, with: Tile(width: tw, height: th, channels: 4, storage: .u8(v))) }
                }
            }
        }
        return bitmap.withOriginalSource(source)
    }

    struct Header {
        var width = 0, height = 0, depth = 0, colorType = 0
    }

    /// Заголовок и распакованные строки (без фильтров). nil — если для быстрого пути нужна палитра.
    static func decodeRows(_ bytes: [UInt8]) throws -> (Header, [UInt8])? {
        guard bytes.count > 8, Array(bytes[0..<8]) == signature else { throw PNGError.notPNG }
        var pos = 8
        var header = Header()
        var idat: [UInt8] = []
        func u32(_ p: Int) -> Int { Int(bytes[p]) << 24 | Int(bytes[p + 1]) << 16 | Int(bytes[p + 2]) << 8 | Int(bytes[p + 3]) }
        while pos + 8 <= bytes.count {
            let length = u32(pos)
            let kind = String(decoding: bytes[(pos + 4)..<(pos + 8)], as: UTF8.self)
            let start = pos + 8
            guard start + length + 4 <= bytes.count else { throw PNGError.corrupt("обрезан блок \(kind)") }
            switch kind {
            case "IHDR":
                header = Header(width: u32(start), height: u32(start + 4), depth: Int(bytes[start + 8]), colorType: Int(bytes[start + 9]))
                if bytes[start + 12] != 0 { throw PNGError.unsupported("чересстрочный PNG") }
                if header.colorType == 3 { return nil }
            case "IDAT": idat.append(contentsOf: bytes[start..<(start + length)])
            case "IEND": pos = bytes.count
            default: break
            }
            pos = start + length + 4
        }
        guard let ch = [0: 1, 2: 3, 4: 2, 6: 4][header.colorType] else { throw PNGError.unsupported("тип цвета \(header.colorType)") }
        guard header.depth == 8 || header.depth == 16 else { throw PNGError.unsupported("глубина \(header.depth) бит") }
        let bpp = ch * header.depth / 8
        let stride = header.width * bpp
        let raw = try inflate(idat, expected: header.height * (stride + 1))
        return (header, try unfilter(raw, height: header.height, stride: stride, bpp: bpp))
    }

    static func unfilter(_ data: [UInt8], height: Int, stride: Int, bpp: Int) throws -> [UInt8] {
        var out = [UInt8](repeating: 0, count: height * stride)
        var pos = 0
        for y in 0..<height {
            let ftype = data[pos]
            pos += 1
            let row = y * stride
            let prev = row - stride
            for i in 0..<stride {
                let rawv = Int(data[pos + i])
                let a = i >= bpp ? Int(out[row + i - bpp]) : 0
                let b = y > 0 ? Int(out[prev + i]) : 0
                let c = (i >= bpp && y > 0) ? Int(out[prev + i - bpp]) : 0
                let pred: Int
                switch ftype {
                case 0: pred = 0
                case 1: pred = a
                case 2: pred = b
                case 3: pred = (a + b) >> 1
                case 4:
                    let p = a + b - c
                    let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
                    pred = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
                default: throw PNGError.corrupt("фильтр \(ftype) в строке \(y)")
                }
                out[row + i] = UInt8((rawv + pred) & 0xFF)
            }
            pos += stride
        }
        return out
    }

    // MARK: запись

    /// Пишет RGBA или серое изображение без фильтров, с чанком sRGB.
    public static func encode(_ image: FloatImage, bitDepth: Int = 16, srgb: Bool = true, level: Int32 = 6) throws -> [UInt8] {
        guard bitDepth == 8 || bitDepth == 16 else { throw PNGError.unsupported("глубина \(bitDepth)") }
        let colorType: UInt8
        switch image.channels {
        case 1: colorType = 0
        case 3: colorType = 2
        case 4: colorType = 6
        default: throw PNGError.unsupported("\(image.channels) каналов")
        }
        let bytesPer = bitDepth / 8
        let stride = image.width * image.channels * bytesPer
        var raw = [UInt8](repeating: 0, count: image.height * (stride + 1))
        let maxv: Float = bitDepth == 16 ? 65535 : 255
        for y in 0..<image.height {
            var o = y * (stride + 1) + 1
            for x in 0..<image.width {
                for c in 0..<image.channels {
                    let v = Int((min(max(image[x, y, c], 0), 1) * maxv).rounded())
                    if bitDepth == 16 {
                        raw[o] = UInt8(v >> 8)
                        raw[o + 1] = UInt8(v & 0xFF)
                        o += 2
                    } else {
                        raw[o] = UInt8(v)
                        o += 1
                    }
                }
            }
        }
        var out = signature
        var ihdr: [UInt8] = []
        ihdr += be32(image.width) + be32(image.height)
        ihdr += [UInt8(bitDepth), colorType, 0, 0, 0]
        out += chunk("IHDR", ihdr)
        if srgb { out += chunk("sRGB", [0]) }
        out += chunk("IDAT", try deflate(raw, level: level))
        out += chunk("IEND", [])
        return out
    }

    private static func be32(_ v: Int) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    private static func chunk(_ kind: String, _ data: [UInt8]) -> [UInt8] {
        let body = Array(kind.utf8) + data
        let crc = body.withUnsafeBufferPointer { UInt32(crc32(0, $0.baseAddress, uInt($0.count))) }
        return be32(data.count) + body + be32(Int(crc))
    }

    // MARK: zlib

    static func deflate(_ input: [UInt8], level: Int32 = 6) throws -> [UInt8] {
        var bound = compressBound(uLong(input.count))
        var out = [UInt8](repeating: 0, count: Int(bound))
        let status = out.withUnsafeMutableBufferPointer { dst in
            input.withUnsafeBufferPointer { src in
                compress2(dst.baseAddress, &bound, src.baseAddress, uLong(input.count), level)
            }
        }
        guard status == Z_OK else { throw PNGError.corrupt("zlib compress \(status)") }
        return Array(out.prefix(Int(bound)))
    }

    static func inflate(_ input: [UInt8], expected: Int) throws -> [UInt8] {
        var size = uLongf(expected)
        var out = [UInt8](repeating: 0, count: expected)
        let status = out.withUnsafeMutableBufferPointer { dst in
            input.withUnsafeBufferPointer { src in
                uncompress(dst.baseAddress, &size, src.baseAddress, uLong(input.count))
            }
        }
        guard status == Z_OK, Int(size) == expected else { throw PNGError.corrupt("zlib uncompress \(status), \(size) из \(expected)") }
        return out
    }
}
