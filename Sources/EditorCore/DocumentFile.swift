import Foundation

/// Собственный формат документа, версия 1.
/// Устроен как .pxd по форме (zip без сжатия + SQLite + плитки), но схема и кодирование свои:
///
///   document.sqlite         описание документа, слоёв, масок и плиток
///   tiles/<id>/<tx>_<ty>    пиксели плитки, закодированные TileCodec (формат 1: little-endian u8/u16 + zlib)
///   sources/<id>            исходный файл неизменённого растра (вместо плиток; формат 3)
///   preview.png             превью 8 бит для Finder и окна «Открыть»
///
/// Неподдержанные этапом 1 виды слоёв сохраняются с их видом (`kind`) и при загрузке остаются неподдержанными.
public enum DocumentFileError: Error, Equatable {
    case notADocument
    case newerFormat(Int)
    case corrupt(String)
}

public enum DocumentFile {
    /// 3 — растры с исходным файлом хранятся как файл (таблица sources);
    /// 2 — плитки кодируются TileCodec (столбец tiles.codec); 1 — сырые пиксели + zlib. Все читаются.
    public static let formatVersion = 3
    static let schema = """
        CREATE TABLE info (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE layers (id TEXT PRIMARY KEY, parent TEXT, idx INTEGER NOT NULL, props TEXT NOT NULL);
        CREATE TABLE masks (id TEXT PRIMARY KEY, layer TEXT NOT NULL, idx INTEGER NOT NULL, props TEXT NOT NULL);
        CREATE TABLE bitmaps (owner TEXT PRIMARY KEY, width INTEGER NOT NULL, height INTEGER NOT NULL, channels INTEGER NOT NULL, depth INTEGER NOT NULL);
        CREATE TABLE tiles (owner TEXT NOT NULL, tx INTEGER NOT NULL, ty INTEGER NOT NULL, entry TEXT NOT NULL, codec TEXT NOT NULL, PRIMARY KEY (owner, tx, ty));
        CREATE TABLE sources (owner TEXT PRIMARY KEY, entry TEXT NOT NULL, format TEXT NOT NULL);
        """

    struct LayerProps: Codable {
        var name: String
        var kind: String          // bitmap | group | unsupported
        var unsupportedKind: String?
        var x: Int
        var y: Int
        var visible: Bool
        var locked: Bool
        var opacity: Float
        var blend: BlendMode
        var clipping: Bool
        var preserveTransparency: Bool
    }

    struct MaskProps: Codable {
        var x: Int
        var y: Int
        var background: Float
        var density: Float
        var inverted: Bool
        var enabled: Bool
    }

    // MARK: сохранение

    public static func save(_ document: Document) throws -> [UInt8] {
        let profile = ProcessInfo.processInfo.environment["PE_PROFILE"] != nil
        var mark = Date()
        func lap(_ what: String) {
            guard profile else { return }
            let now = Date()
            print(String(format: "  [сохранение] %@: %.2f с", what, now.timeIntervalSince(mark)))
            mark = now
        }
        var zip = ZipWriter()
        var tileEntries: [(owner: String, tx: Int, ty: Int, name: String, bytes: [UInt8])] = []
        var bitmaps: [(owner: String, bitmap: Bitmap)] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        // Сначала только собираем список плиток; сжимаются они потом параллельно.
        var pending: [(owner: String, tx: Int, ty: Int, tile: Tile)] = []
        var sources: [(owner: String, name: String, source: OriginalSource)] = []
        func collect(_ owner: String, _ bitmap: Bitmap) throws {
            bitmaps.append((owner, bitmap))
            // Неизменённый растр из файла: храним сам файл, как образец.
            if let source = bitmap.originalSource, ImageDecoders.canDecode(source.format) {
                sources.append((owner, "sources/\(owner)", source))
                return
            }
            for ty in 0..<bitmap.tilesDown {
                for tx in 0..<bitmap.tilesAcross {
                    guard let tile = bitmap.tiles[ty * bitmap.tilesAcross + tx] else { continue }
                    pending.append((owner, tx, ty, tile))
                }
            }
        }

        let db = try SQLiteDatabase.serialize { db in
            try db.execute(schema)
            let info: [(String, String)] = [
                ("format_version", String(formatVersion)), ("width", String(document.width)), ("height", String(document.height)),
                ("depth", String(document.depth.rawValue)), ("color_profile", document.colorProfile), ("resolution", String(document.resolution)),
            ]
            for (k, v) in info { try db.query("INSERT INTO info VALUES (?, ?)", [.text(k), .text(v)]) }

            func store(_ layers: [Layer], parent: LayerID?) throws {
                for (i, layer) in layers.enumerated() {
                    var props = LayerProps(name: layer.name, kind: "bitmap", unsupportedKind: nil, x: layer.position.x, y: layer.position.y,
                                           visible: layer.isVisible, locked: layer.isLocked, opacity: layer.opacity, blend: layer.blendMode,
                                           clipping: layer.isClippingMask, preserveTransparency: layer.preserveTransparency)
                    switch layer.content {
                    case .bitmap(let bitmap): try collect(layer.id.description, bitmap)
                    case .group: props.kind = "group"
                    case .unsupported(let kind):
                        props.kind = "unsupported"
                        props.unsupportedKind = kind
                    }
                    let json = String(decoding: try encoder.encode(props), as: UTF8.self)
                    try db.query("INSERT INTO layers VALUES (?, ?, ?, ?)",
                                 [.text(layer.id.description), parent.map { .text($0.description) } ?? .null, .int(Int64(i)), .text(json)])
                    for (m, mask) in layer.masks.enumerated() {
                        let mp = MaskProps(x: mask.offset.x, y: mask.offset.y, background: mask.backgroundValue, density: mask.density,
                                           inverted: mask.isInverted, enabled: mask.isEnabled)
                        try db.query("INSERT INTO masks VALUES (?, ?, ?, ?)",
                                     [.text(mask.id.description), .text(layer.id.description), .int(Int64(m)),
                                      .text(String(decoding: try encoder.encode(mp), as: UTF8.self))])
                        if let bitmap = mask.bitmap { try collect(mask.id.description, bitmap) }
                    }
                    if case .group(let children) = layer.content { try store(children, parent: layer.id) }
                }
            }
            try store(document.layers, parent: nil)
            lap("описание слоёв")
            tileEntries = try compressTiles(pending)
            lap("сжатие плиток")
            for (owner, b) in bitmaps {
                try db.query("INSERT INTO bitmaps VALUES (?, ?, ?, ?, ?)",
                             [.text(owner), .int(Int64(b.width)), .int(Int64(b.height)), .int(Int64(b.channels)), .int(Int64(b.depth.rawValue))])
            }
            for src in sources {
                try db.query("INSERT INTO sources VALUES (?, ?, ?)", [.text(src.owner), .text(src.name), .text(src.source.format)])
            }
            for t in tileEntries {
                try db.query("INSERT INTO tiles VALUES (?, ?, ?, ?, ?)",
                             [.text(t.owner), .int(Int64(t.tx)), .int(Int64(t.ty)), .text(t.name), .text(TileCodec.current.rawValue)])
            }
        }
        lap("база и сжатие плиток")
        try zip.add("document.sqlite", db)
        for t in tileEntries { try zip.add(t.name, t.bytes) }
        for src in sources { try zip.add(src.name, src.source.bytes) }
        lap("zip")
        let previewImage = try preview(document)
        lap("превью: рендер")
        try zip.add("preview.png", try PNG.encode(previewImage, bitDepth: 8))
        lap("превью: PNG")
        let out = try zip.finish()
        lap("zip: каталог")
        return out
    }

    /// Сторона превью не больше этого числа пикселей.
    public static let previewMaxSide = 1024

    /// Превью: весь документ на уровне уменьшения, при котором длинная сторона ≤ previewMaxSide.
    static func preview(_ document: Document) throws -> FloatImage {
        var level = 0
        while level < 8, max(document.width, document.height) >> level > previewMaxSide { level += 1 }
        return try CPURenderer.render(document, region: .whole(document, level: level)).image
    }

    /// Параллельное кодирование плиток (TileCodec.current, быстрый уровень zlib).
    static func compressTiles(_ pending: [(owner: String, tx: Int, ty: Int, tile: Tile)]) throws -> [(owner: String, tx: Int, ty: Int, name: String, bytes: [UInt8])] {
        final class Results: @unchecked Sendable {
            var items: [[UInt8]?]
            var error: Error?
            let lock = NSLock()
            init(_ n: Int) { items = Array(repeating: nil, count: n) }
        }
        let results = Results(pending.count)
        DispatchQueue.concurrentPerform(iterations: pending.count) { i in
            do {
                let packed = try TileCodec.current.encode(pending[i].tile)
                results.lock.lock()
                results.items[i] = packed
                results.lock.unlock()
            } catch {
                results.lock.lock()
                results.error = error
                results.lock.unlock()
            }
        }
        if let error = results.error { throw error }
        return pending.enumerated().map { i, p in (p.owner, p.tx, p.ty, "tiles/\(p.owner)/\(p.tx)_\(p.ty)", results.items[i]!) }
    }

    static func tileBytes(_ tile: Tile) -> [UInt8] {
        switch tile.storage {
        case .u8(let v): return v
        case .u16(let v):
            var out = [UInt8](repeating: 0, count: v.count * 2)
            for (i, x) in v.enumerated() {
                out[2 * i] = UInt8(x & 0xFF)
                out[2 * i + 1] = UInt8(x >> 8)
            }
            return out
        }
    }

    // MARK: загрузка

    public static func load(_ bytes: [UInt8]) throws -> Document {
        let zip: ZipReader
        do { zip = try ZipReader(bytes) } catch { throw DocumentFileError.notADocument }
        guard zip.contains("document.sqlite") else { throw DocumentFileError.notADocument }
        var document: Document?
        let decoder = JSONDecoder()
        try SQLiteDatabase.open(bytes: try zip.read("document.sqlite")) { db in
            var info: [String: String] = [:]
            for row in try db.query("SELECT key, value FROM info") {
                if let k = row[0].text, let v = row[1].text { info[k] = v }
            }
            guard let version = info["format_version"].flatMap(Int.init) else { throw DocumentFileError.corrupt("нет format_version") }
            guard version <= formatVersion else { throw DocumentFileError.newerFormat(version) }
            guard let w = info["width"].flatMap(Int.init), let h = info["height"].flatMap(Int.init),
                  let d = info["depth"].flatMap(Int.init).flatMap(BitDepth.init(rawValue:)) else {
                throw DocumentFileError.corrupt("размеры или глубина")
            }
            var doc = Document(width: w, height: h, depth: d)
            doc.colorProfile = info["color_profile"] ?? "sRGB"
            doc.resolution = info["resolution"].flatMap(Double.init) ?? 72

            // Исходные файлы слоёв (формат 3) декодируются заранее, все сразу и параллельно.
            var decodedSources: [String: Bitmap] = [:]
            if version >= 3 {
                var jobs: [(owner: String, source: OriginalSource)] = []
                for row in try db.query("SELECT owner, entry, format FROM sources") {
                    guard let owner = row[0].text, let entry = row[1].text, let format = row[2].text else { throw DocumentFileError.corrupt("источник") }
                    jobs.append((owner, OriginalSource(format: format, bytes: try zip.read(entry))))
                }
                final class Decoded: @unchecked Sendable {
                    var bitmaps: [Bitmap?]
                    var error: Error?
                    let lock = NSLock()
                    init(_ n: Int) { bitmaps = Array(repeating: nil, count: n) }
                }
                let work = jobs
                let results = Decoded(work.count)
                DispatchQueue.concurrentPerform(iterations: work.count) { i in
                    do {
                        let b = try ImageDecoders.decode(work[i].source)
                        results.lock.lock()
                        results.bitmaps[i] = b
                        results.lock.unlock()
                    } catch {
                        results.lock.lock()
                        results.error = error
                        results.lock.unlock()
                    }
                }
                if let error = results.error { throw error }
                for (i, job) in work.enumerated() { decodedSources[job.owner] = results.bitmaps[i] }
            }

            func bitmap(_ owner: String) throws -> Bitmap? {
                guard let row = try db.query("SELECT width, height, channels, depth FROM bitmaps WHERE owner = ?", [.text(owner)]).first,
                      let bw = row[0].int, let bh = row[1].int, let ch = row[2].int,
                      let depth = row[3].int.flatMap({ BitDepth(rawValue: Int($0)) }) else { return nil }
                if let decoded = decodedSources[owner] {
                    guard decoded.width == Int(bw), decoded.height == Int(bh), decoded.channels == Int(ch), decoded.depth == depth else {
                        throw DocumentFileError.corrupt("исходный файл \(owner) не совпадает с описанием растра")
                    }
                    return decoded
                }
                var bmp = Bitmap(width: Int(bw), height: Int(bh), channels: Int(ch), depth: depth)
                var jobs: [(tx: Int, ty: Int, packed: [UInt8], codec: TileCodec)] = []
                let sql = version >= 2 ? "SELECT tx, ty, entry, codec FROM tiles WHERE owner = ?" : "SELECT tx, ty, entry FROM tiles WHERE owner = ?"
                for t in try db.query(sql, [.text(owner)]) {
                    guard let tx = t[0].int.map(Int.init), let ty = t[1].int.map(Int.init), let entry = t[2].text,
                          tx < bmp.tilesAcross, ty < bmp.tilesDown else { throw DocumentFileError.corrupt("плитка \(owner)") }
                    let codec = version >= 2 ? t[3].text.flatMap(TileCodec.init(rawValue:)) : .rawZlib
                    guard let codec else { throw DocumentFileError.corrupt("неизвестное кодирование плитки \(owner)") }
                    jobs.append((tx, ty, try zip.read(entry), codec))
                }
                // Распаковка плиток параллельно.
                final class Decoded: @unchecked Sendable {
                    var tiles: [Tile?]
                    var error: Error?
                    let lock = NSLock()
                    init(_ n: Int) { tiles = Array(repeating: nil, count: n) }
                }
                let work = jobs
                let decoded = Decoded(work.count)
                let geometry = (width: bmp.width, height: bmp.height, channels: bmp.channels)
                DispatchQueue.concurrentPerform(iterations: work.count) { i in
                    let job = work[i]
                    let tw = min(Tile.size, geometry.width - job.tx * Tile.size), th = min(Tile.size, geometry.height - job.ty * Tile.size)
                    do {
                        let tile = try job.codec.decode(job.packed, width: tw, height: th, channels: geometry.channels, depth: depth)
                        decoded.lock.lock()
                        decoded.tiles[i] = tile
                        decoded.lock.unlock()
                    } catch {
                        decoded.lock.lock()
                        decoded.error = error
                        decoded.lock.unlock()
                    }
                }
                if let error = decoded.error { throw error }
                for (i, job) in jobs.enumerated() { bmp.replaceTile(tx: job.tx, ty: job.ty, with: decoded.tiles[i]) }
                return bmp
            }

            func loadLayers(parent: String?) throws -> [Layer] {
                let rows = parent == nil
                    ? try db.query("SELECT id, props FROM layers WHERE parent IS NULL ORDER BY idx")
                    : try db.query("SELECT id, props FROM layers WHERE parent = ? ORDER BY idx", [.text(parent!)])
                return try rows.map { row in
                    guard let idText = row[0].text, let uuid = UUID(uuidString: idText), let json = row[1].text else {
                        throw DocumentFileError.corrupt("слой")
                    }
                    let p = try decoder.decode(LayerProps.self, from: Data(json.utf8))
                    let content: LayerContent
                    switch p.kind {
                    case "bitmap":
                        guard let b = try bitmap(idText) else { throw DocumentFileError.corrupt("растр слоя \(p.name)") }
                        content = .bitmap(b)
                    case "group": content = .group(try loadLayers(parent: idText))
                    default: content = .unsupported(kind: p.unsupportedKind ?? p.kind)
                    }
                    var layer = Layer(name: p.name, content: content)
                    layer.id = LayerID(uuid)
                    layer.position = PixelPoint(x: p.x, y: p.y)
                    layer.isVisible = p.visible
                    layer.isLocked = p.locked
                    layer.opacity = p.opacity
                    layer.blendMode = p.blend
                    layer.isClippingMask = p.clipping
                    layer.preserveTransparency = p.preserveTransparency
                    for m in try db.query("SELECT id, props FROM masks WHERE layer = ? ORDER BY idx", [.text(idText)]) {
                        guard let mid = m[0].text, let muuid = UUID(uuidString: mid), let mj = m[1].text else { throw DocumentFileError.corrupt("маска") }
                        let mp = try decoder.decode(MaskProps.self, from: Data(mj.utf8))
                        var mask = LayerMask(bitmap: try bitmap(mid), offset: PixelPoint(x: mp.x, y: mp.y), backgroundValue: mp.background)
                        mask.id = LayerID(muuid)
                        mask.density = mp.density
                        mask.isInverted = mp.inverted
                        mask.isEnabled = mp.enabled
                        layer.masks.append(mask)
                    }
                    return layer
                }
            }
            doc.layers = try loadLayers(parent: nil)
            document = doc
        }
        guard let document else { throw DocumentFileError.corrupt("пустой документ") }
        return document
    }
}

/// Декодеры исходных файлов слоёв. В ядре — PNG; платформенные (JPEG, HEIC… через ImageIO) подключатся позже.
/// Декодер обязан давать ровно те пиксели, что были в документе при сохранении.
public enum ImageDecoders {
    public static func canDecode(_ format: String) -> Bool { format == "png" }

    public static func decode(_ source: OriginalSource) throws -> Bitmap {
        switch source.format {
        case "png": return try PNG.decodeBitmap(source.bytes)
        default: throw DocumentFileError.corrupt("нет декодера для «\(source.format)»")
        }
    }
}
