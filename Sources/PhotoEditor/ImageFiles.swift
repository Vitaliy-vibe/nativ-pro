#if canImport(AppKit)
import AppKit
import EditorCore
import ImageIO
import UniformTypeIdentifiers

enum ImageIOError: LocalizedError {
    case unreadable
    case cannotEncode(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: return AppInfo.tr("The image could not be read.", "Не удалось прочитать изображение.")
        case .cannotEncode(let t): return AppInfo.tr("Cannot write \(t).", "Не удалось записать \(t).")
        }
    }
}

/// Перевод между пикселями ядра (FloatImage / Bitmap, sRGB без премультипликации) и CGImage / файлами.
enum ImageFiles {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Растр, залитый одним цветом; одинаковые плитки общие (память — на одну плитку каждого размера).
    static func filled(width: Int, height: Int, depth: BitDepth, rgba: [Float]) -> Bitmap {
        var b = Bitmap(width: width, height: height, channels: 4, depth: depth)
        var cache: [Int: Tile] = [:]
        for ty in 0..<b.tilesDown {
            for tx in 0..<b.tilesAcross {
                let w = min(Tile.size, width - tx * Tile.size), h = min(Tile.size, height - ty * Tile.size)
                let key = w << 16 | h
                if cache[key] == nil {
                    switch depth {
                    case .u8:
                        let px = rgba.map { UInt8(($0 * 255).rounded()) }
                        var buf = [UInt8](repeating: 0, count: w * h * 4)
                        for i in 0..<(w * h) { for c in 0..<4 { buf[i * 4 + c] = px[c] } }
                        cache[key] = Tile(width: w, height: h, channels: 4, storage: .u8(buf))
                    case .u16:
                        let px = rgba.map { UInt16(($0 * 65535).rounded()) }
                        var buf = [UInt16](repeating: 0, count: w * h * 4)
                        for i in 0..<(w * h) { for c in 0..<4 { buf[i * 4 + c] = px[c] } }
                        cache[key] = Tile(width: w, height: h, channels: 4, storage: .u16(buf))
                    }
                }
                b.replaceTile(tx: tx, ty: ty, with: cache[key])
            }
        }
        return b
    }

    // MARK: чтение

    /// Документ из файла изображения. PNG читает ядро (файл сохранится в документе как исходник),
    /// остальное — ImageIO macOS с переводом в sRGB.
    static func document(from data: Data, layerName: String) throws -> Document {
        let bitmap = try bitmap(from: data)
        var doc = Document(width: bitmap.width, height: bitmap.height, depth: bitmap.depth)
        doc.layers = [.bitmap(name: layerName, bitmap)]
        return doc
    }

    static func bitmap(from data: Data) throws -> Bitmap {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]), let b = try? PNG.decodeBitmap([UInt8](data)) { return b }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { throw ImageIOError.unreadable }
        return try bitmap(from: cg)
    }

    /// CGImage → растр: рисуем в контекст sRGB (8 или 16 бит по исходнику) и снимаем премультипликацию.
    static func bitmap(from cg: CGImage) throws -> Bitmap {
        let w = cg.width, h = cg.height
        let deep = cg.bitsPerComponent > 8
        let image: FloatImage
        if deep {
            var buf = [UInt16](repeating: 0, count: w * h * 4)
            let ok = buf.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 16, bytesPerRow: w * 8, space: sRGB,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
                else { return false }
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { throw ImageIOError.unreadable }
            image = unpremultiply(w, h) { Float(buf[$0]) / 65535 }
        } else {
            var buf = [UInt8](repeating: 0, count: w * h * 4)
            let ok = buf.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { throw ImageIOError.unreadable }
            image = unpremultiply(w, h) { Float(buf[$0]) / 255 }
        }
        return Bitmap(image: image, depth: deep ? .u16 : .u8)
    }

    static func unpremultiply(_ w: Int, _ h: Int, _ sample: (Int) -> Float) -> FloatImage {
        var img = FloatImage(width: w, height: h, channels: 4)
        img.data.withUnsafeMutableBufferPointer { out in
            for i in 0..<(w * h) {
                let a = sample(i * 4 + 3)
                out[i * 4 + 3] = a
                guard a > 0 else { continue }
                for c in 0..<3 { out[i * 4 + c] = min(sample(i * 4 + c) / a, 1) }
            }
        }
        return img
    }

    // MARK: вывод

    /// FloatImage → CGImage (без премультипликации, sRGB): 8 бит — для экрана и JPEG, 16 бит — для TIFF/PNG.
    static func cgImage(_ img: FloatImage, sixteenBit: Bool = false) -> CGImage? {
        let w = img.width, h = img.height, n = w * h * 4
        let data: Data
        if sixteenBit {
            var buf = [UInt16](repeating: 0, count: n)
            img.data.withUnsafeBufferPointer { src in
                for i in 0..<n { buf[i] = UInt16((min(max(src[i], 0), 1) * 65535).rounded()) }
            }
            data = buf.withUnsafeBytes { Data($0) }
        } else {
            var buf = [UInt8](repeating: 0, count: n)
            img.data.withUnsafeBufferPointer { src in
                for i in 0..<n { buf[i] = UInt8((min(max(src[i], 0), 1) * 255).rounded()) }
            }
            data = Data(buf)
        }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let info = sixteenBit
            ? CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue | CGBitmapInfo.byteOrder16Little.rawValue)
            : CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        return CGImage(width: w, height: h, bitsPerComponent: sixteenBit ? 16 : 8, bitsPerPixel: sixteenBit ? 64 : 32,
                       bytesPerRow: w * (sixteenBit ? 8 : 4), space: sRGB, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Файл изображения из готового рендера. PNG пишет ядро (8/16 бит по документу), остальное — ImageIO.
    static func encode(_ img: FloatImage, as type: UTType, depth: BitDepth) throws -> Data {
        if type.conforms(to: .png) {
            return Data(try PNG.encode(img, bitDepth: depth == .u16 ? 16 : 8))
        }
        let deep = depth == .u16 && (type.conforms(to: .tiff))
        guard let cg = cgImage(img, sixteenBit: deep) else { throw ImageIOError.cannotEncode(type.preferredFilenameExtension ?? "?") }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, type.identifier as CFString, 1, nil) else {
            throw ImageIOError.cannotEncode(type.preferredFilenameExtension ?? "?")
        }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageIOError.cannotEncode(type.preferredFilenameExtension ?? "?") }
        return out as Data
    }
}

/// Картинки в буфере обмена: пишем PNG (его понимают все программы), читаем PNG или любое изображение.
enum PasteboardImage {
    static func hasImage() -> Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    static func write(_ img: FloatImage, depth: BitDepth) {
        guard let png = try? PNG.encode(img, bitDepth: depth == .u16 ? 16 : 8) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(Data(png), forType: .png)
    }

    /// Документ из одного слоя с картинкой из буфера.
    static func read() -> Document? {
        let pb = NSPasteboard.general
        var bitmap: Bitmap?
        if let data = pb.data(forType: .png) {
            bitmap = try? ImageFiles.bitmap(from: data)
        }
        if bitmap == nil, let image = NSImage(pasteboard: pb), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            bitmap = try? ImageFiles.bitmap(from: cg)
        }
        guard let b = bitmap else { return nil }
        var doc = Document(width: b.width, height: b.height, depth: b.depth)
        doc.layers = [.bitmap(name: AppInfo.tr("Pasted Layer", "Вставленный слой"), b)]
        return doc
    }
}
#endif
