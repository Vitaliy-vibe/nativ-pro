import CZlib

/// Минимальный zip: запись без сжатия, чтение записей stored и deflate.
/// Без zip64: архив и записи до 4 ГБ, иначе явная ошибка.
public enum ZipError: Error, Equatable {
    case tooLarge
    case notZip
    case corrupt(String)
    case unsupportedMethod(Int)
    case missingEntry(String)
}

public struct ZipWriter {
    private var data: [UInt8] = []
    private var central: [UInt8] = []
    private var count = 0

    public init() {}

    public mutating func add(_ name: String, _ bytes: [UInt8]) throws {
        let nameBytes = Array(name.utf8)
        guard bytes.count < Int(UInt32.max), data.count < Int(UInt32.max) else { throw ZipError.tooLarge }
        let crc = Zip.crc(bytes)
        let offset = UInt32(data.count)
        // Локальный заголовок.
        data += le32(0x04034B50) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
        data += le32(crc) + le32(UInt32(bytes.count)) + le32(UInt32(bytes.count))
        data += le16(UInt16(nameBytes.count)) + le16(0) + nameBytes
        data += bytes
        // Запись центрального каталога.
        central += le32(0x02014B50) + le16(0x031E) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0x21)
        central += le32(crc) + le32(UInt32(bytes.count)) + le32(UInt32(bytes.count))
        central += le16(UInt16(nameBytes.count)) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0o100644 << 16) + le32(offset)
        central += nameBytes
        count += 1
    }

    public func finish() throws -> [UInt8] {
        guard data.count + central.count < Int(UInt32.max), count < 0xFFFF else { throw ZipError.tooLarge }
        var out = data + central
        out += le32(0x06054B50) + le16(0) + le16(0) + le16(UInt16(count)) + le16(UInt16(count))
        out += le32(UInt32(central.count)) + le32(UInt32(data.count)) + le16(0)
        return out
    }

    private func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    private func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)] }
}

public struct ZipReader {
    public struct Entry: Sendable {
        public let name: String
        let method: Int
        let compressedSize: Int
        let size: Int
        let crc: UInt32
        let localOffset: Int
    }

    public let entries: [Entry]
    private let bytes: [UInt8]

    public init(_ bytes: [UInt8]) throws {
        self.bytes = bytes
        guard bytes.count >= 22 else { throw ZipError.notZip }
        func u16(_ p: Int) -> Int { Int(bytes[p]) | Int(bytes[p + 1]) << 8 }
        func u32(_ p: Int) -> Int { u16(p) | u16(p + 2) << 16 }
        // Конец центрального каталога ищем с конца (после него может быть комментарий до 64 КБ).
        var eocd = -1
        var p = bytes.count - 22
        while p >= max(0, bytes.count - 22 - 0xFFFF) {
            if u32(p) == 0x06054B50 {
                eocd = p
                break
            }
            p -= 1
        }
        guard eocd >= 0 else { throw ZipError.notZip }
        let total = u16(eocd + 10)
        var pos = u32(eocd + 16)
        var list: [Entry] = []
        for _ in 0..<total {
            guard pos + 46 <= bytes.count, u32(pos) == 0x02014B50 else { throw ZipError.corrupt("центральный каталог") }
            let nameLen = u16(pos + 28), extraLen = u16(pos + 30), commentLen = u16(pos + 32)
            guard pos + 46 + nameLen <= bytes.count else { throw ZipError.corrupt("имя записи") }
            let name = String(decoding: bytes[(pos + 46)..<(pos + 46 + nameLen)], as: UTF8.self)
            list.append(Entry(name: name, method: u16(pos + 10), compressedSize: u32(pos + 20), size: u32(pos + 24),
                              crc: UInt32(u32(pos + 16)), localOffset: u32(pos + 42)))
            pos += 46 + nameLen + extraLen + commentLen
        }
        entries = list
    }

    public func contains(_ name: String) -> Bool { entries.contains { $0.name == name } }

    public func read(_ name: String) throws -> [UInt8] {
        guard let e = entries.first(where: { $0.name == name }) else { throw ZipError.missingEntry(name) }
        func u16(_ p: Int) -> Int { Int(bytes[p]) | Int(bytes[p + 1]) << 8 }
        let h = e.localOffset
        guard h + 30 <= bytes.count, u16(h) | u16(h + 2) << 16 == 0x04034B50 else { throw ZipError.corrupt("локальный заголовок \(name)") }
        let start = h + 30 + u16(h + 26) + u16(h + 28)
        guard start + e.compressedSize <= bytes.count else { throw ZipError.corrupt("данные \(name)") }
        let raw = Array(bytes[start..<(start + e.compressedSize)])
        let out: [UInt8]
        switch e.method {
        case 0: out = raw
        case 8: out = try Zip.inflateRaw(raw, expected: e.size)
        default: throw ZipError.unsupportedMethod(e.method)
        }
        guard Zip.crc(out) == e.crc else { throw ZipError.corrupt("CRC \(name)") }
        return out
    }
}

public enum Zip {
    public static func crc(_ bytes: [UInt8]) -> UInt32 {
        bytes.withUnsafeBufferPointer { UInt32(crc32(0, $0.baseAddress, uInt($0.count))) }
    }

    /// Распаковка deflate без zlib-заголовка (как в zip и в плитках .pxd).
    public static func inflateRaw(_ input: [UInt8], expected: Int) throws -> [UInt8] {
        var stream = z_stream()
        var rc = inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard rc == Z_OK else { throw ZipError.corrupt("inflateInit2 \(rc)") }
        defer { inflateEnd(&stream) }
        var out = [UInt8](repeating: 0, count: max(expected, 1))
        var src = input
        rc = src.withUnsafeMutableBufferPointer { inBuf in
            out.withUnsafeMutableBufferPointer { outBuf in
                stream.next_in = inBuf.baseAddress
                stream.avail_in = uInt(inBuf.count)
                stream.next_out = outBuf.baseAddress
                stream.avail_out = uInt(outBuf.count)
                return CZlib.inflate(&stream, Z_FINISH)
            }
        }
        guard rc == Z_STREAM_END, Int(stream.total_out) == expected else { throw ZipError.corrupt("inflate \(rc), \(stream.total_out) из \(expected)") }
        return Array(out.prefix(expected))
    }
}
