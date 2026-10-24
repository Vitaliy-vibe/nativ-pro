import EditorCore
import EditorRenderMetal
import Foundation

/// pe — консольная утилита ядра.
///   pe reftest --manifest M --inputs DIR --out DIR [--suites blend,masks,probe] [--renderer cpu|metal]
///       строит наши результаты для заданий-эталонов.
///   pe render-png <вход.png> <выход.png>
///   pe bench [--size 4000x3000] [--layers 5] [--renderer cpu|metal] [--export 1] [--noise шагов8бит]
///       синтетический документ (слои, маска, группа): окно 100 % и «по размеру», весь документ, сохранение, открытие, память.
///   pe pack --images DIR --out FILE
///       документ из слоёв pe gen-images (как в замере образца) — в наш формат; время и размер.
///   pe diff <a.png> <b.png>
///       наибольшее и среднее отличие двух PNG.
///   pe gen-images --size ШxВ [--layers 5] --out DIR
///       слои того же документа в PNG 16 бит — для замера образца.
///       прогон PNG через ядро (чтение → документ → рендер → запись) для проверки ввода-вывода.

struct CLIError: Error, CustomStringConvertible {
    let description: String
}

func readFile(_ path: String) throws -> [UInt8] {
    guard let data = FileManager.default.contents(atPath: path) else { throw CLIError(description: "не прочитан файл \(path)") }
    return [UInt8](data)
}

func writeFile(_ path: String, _ bytes: [UInt8]) throws {
    let dir = (path as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    guard FileManager.default.createFile(atPath: path, contents: Data(bytes)) else { throw CLIError(description: "не записан файл \(path)") }
}

/// Растр из PNG с привязанным исходным файлом (документ сохранит сам PNG, пока слой не меняли).
func loadBitmap(_ path: String) throws -> (Bitmap, BitDepth) {
    let bitmap = try PNG.decodeBitmap(try readFile(path))
    return (bitmap, bitmap.depth)
}

func loadMask(_ path: String) throws -> Bitmap {
    let png = try PNG.decode(try readFile(path))
    var gray = FloatImage(width: png.image.width, height: png.image.height, channels: 1)
    for y in 0..<gray.height {
        for x in 0..<gray.width { gray[x, y, 0] = png.image[x, y, 0] }
    }
    return Bitmap(image: gray, depth: png.bitDepth == 16 ? .u16 : .u8)
}

/// Документ из одного изображения — как «Открыть PNG» в образце.
func openImage(_ path: String) throws -> Document {
    let (bitmap, depth) = try loadBitmap(path)
    var doc = Document(width: bitmap.width, height: bitmap.height, depth: depth)
    doc.layers = [.bitmap(name: "Image Layer", bitmap)]
    return doc
}

enum JobOutcome {
    case rendered(Document)
    case notInPhase(String)
}

func buildJob(_ job: [String: Any], inputs: String) throws -> JobOutcome {
    let id = job["id"] as? String ?? "?"
    let suite = job["suite"] as? String ?? "?"
    let params = job["params"] as? [String: Any] ?? [:]
    let input = { (name: String) in (inputs as NSString).appendingPathComponent(name) }
    switch suite {
    case "blend":
        guard let modeName = params["blend_mode"] as? String, let mode = BlendMode(appleScriptName: modeName) else {
            throw CLIError(description: "\(id): неизвестный режим \(params["blend_mode"] ?? "nil")")
        }
        var doc = try openImage(input("base_a.png"))
        var top = Layer.bitmap(name: "top_b", try loadBitmap(input("top_b.png")).0)
        top.blendMode = mode
        top.opacity = Float((params["opacity"] as? NSNumber)?.doubleValue ?? 100) / 100
        doc.layers.append(top)
        return .rendered(doc)
    case "masks":
        switch id {
        case "mask_from_image":
            var doc = try openImage(input("base_a.png"))
            var top = Layer.bitmap(name: "top_b", try loadBitmap(input("top_b.png")).0)
            top.masks = [LayerMask(bitmap: try loadMask(input("mask_grad.png")), backgroundValue: 1)]
            doc.layers.append(top)
            return .rendered(doc)
        case "mask_hide_all":
            var doc = try openImage(input("base_a.png"))
            var top = Layer.bitmap(name: "top_b", try loadBitmap(input("top_b.png")).0)
            top.masks = [.hideAll()]
            doc.layers.append(top)
            return .rendered(doc)
        default:
            return .notInPhase("использует фигуру (этап 6)")
        }
    case "probe":
        guard id == "position_8_40" else { return .notInPhase("журнал, не изображение") }
        var doc = try openImage(input("white64.png"))
        doc.layers.append(.bitmap(name: "red16", try loadBitmap(input("red16.png")).0, at: PixelPoint(x: 8, y: 40)))
        return .rendered(doc)
    default:
        return .notInPhase("набор «\(suite)» относится к следующим этапам")
    }
}

/// Выбранный рендер: эталонный CPU или Metal (только macOS); умеет рисовать область в масштабе.
struct Renderer {
    let name: String
    let region: (Document, RenderRegion) throws -> RenderResult
    /// Байты в кеше текстур (только Metal).
    var textureBytes: () -> Int = { 0 }
    func whole(_ d: Document) throws -> RenderResult { try region(d, .whole(d)) }
}

func makeRenderer(_ name: String) throws -> Renderer {
    switch name {
    case "cpu": return Renderer(name: name) { try CPURenderer.render($0, region: $1) }
    case "metal":
        #if canImport(Metal)
        let metal = try MetalRenderer()
        var r = Renderer(name: name) { try metal.render($0, region: $1) }
        r.textureBytes = { metal.textureBytes }
        return r
        #else
        throw CLIError(description: "рендер Metal есть только на macOS")
        #endif
    default: throw CLIError(description: "неизвестный рендер «\(name)» (cpu или metal)")
    }
}

func reftest(_ args: [String: String]) throws {
    guard let manifestPath = args["--manifest"], let inputs = args["--inputs"], let out = args["--out"] else {
        throw CLIError(description: "нужны --manifest, --inputs, --out")
    }
    let suites = Set((args["--suites"] ?? "blend,masks,probe").split(separator: ",").map(String.init))
    let render = try makeRenderer(args["--renderer"] ?? "cpu")
    let data = try readFile(manifestPath)
    guard let root = try JSONSerialization.jsonObject(with: Data(data)) as? [String: Any], let jobs = root["jobs"] as? [[String: Any]] else {
        throw CLIError(description: "манифест не разобран")
    }
    var rendered = 0, skipped: [String] = [], unsupported: [String] = [], failed: [String] = []
    for job in jobs where suites.contains(job["suite"] as? String ?? "") {
        let id = job["id"] as? String ?? "?"
        do {
            switch try buildJob(job, inputs: inputs) {
            case .notInPhase(let why):
                skipped.append("\(id): \(why)")
            case .rendered(let doc):
                let result = try render.whole(doc)
                if !result.unsupported.isEmpty {
                    unsupported.append("\(id): " + result.unsupported.map { "«\($0.name)» (\($0.kind))" }.joined(separator: ", "))
                }
                guard let output = job["output"] as? String else { continue }
                try writeFile((out as NSString).appendingPathComponent(output), try PNG.encode(result.image, bitDepth: 16))
                rendered += 1
            }
        } catch {
            failed.append("\(id): \(error)")
        }
    }
    print("Построено: \(rendered)")
    if !skipped.isEmpty { print("Не входит в этап 1 (\(skipped.count)):\n  " + skipped.joined(separator: "\n  ")) }
    if !unsupported.isEmpty { print("НЕ ОТРИСОВАНЫ слои (\(unsupported.count)):\n  " + unsupported.joined(separator: "\n  ")) }
    if !failed.isEmpty {
        print("ОШИБКИ (\(failed.count)):\n  " + failed.joined(separator: "\n  "))
        exit(1)
    }
}

/// Пиковая память процесса в МБ (getrusage: на macOS — байты, на Linux — килобайты).
func peakMemoryMB() -> Double {
    var usage = rusage()
    #if os(macOS)
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_maxrss) / 1_048_576
    #else
    getrusage(__rusage_who_t(RUSAGE_SELF.rawValue), &usage)
    return Double(usage.ru_maxrss) / 1024
    #endif
}

/// Узор слоя для замеров (одинаковый у pe bench и pe gen-images): плитки u16, без полноразмерных промежуточных изображений.
/// `noise` — амплитуда шума в шагах 8 бит (≈ шум матрицы фотоаппарата); 0 — чистый узор.
func benchPattern(_ w: Int, _ h: Int, seed: Int, channels: Int = 4, noise: Int = 0) -> Bitmap {
    var b = Bitmap(width: w, height: h, channels: channels, depth: .u16)
    for ty in 0..<b.tilesDown {
        for tx in 0..<b.tilesAcross {
            let tw = min(Tile.size, w - tx * Tile.size), th = min(Tile.size, h - ty * Tile.size)
            var v = [UInt16](repeating: 0, count: tw * th * channels)
            for y in 0..<th {
                for x in 0..<tw {
                    let gx = tx * Tile.size + x, gy = ty * Tile.size + y, o = (y * tw + x) * channels
                    if noise > 0 {
                        // Плавные переходы как на фото + шум (детерминированный хэш координат).
                        func n(_ k: Int) -> Int {
                            var z = UInt64(truncatingIfNeeded: gx &* 73856093 ^ gy &* 19349663 ^ (seed &+ k) &* 83492791)
                            z = (z ^ (z >> 33)) &* 0xff51afd7ed558ccd
                            z ^= z >> 33
                            return Int(z % UInt64(2 * noise * 257 + 1)) - noise * 257
                        }
                        let base = [gx * 65535 / max(w - 1, 1), gy * 65535 / max(h - 1, 1), (gx + gy) * 65535 / max(w + h - 2, 1)]
                        for c in 0..<min(channels, 3) { v[o + c] = UInt16(min(max(base[(c + seed) % 3] + n(c), 0), 65535)) }
                        if channels == 4 { v[o + 3] = 65535 }
                    } else {
                        v[o] = UInt16(((gx &* (seed + 3) &+ gy) % 256) * 257)
                        if channels == 4 {
                            v[o + 1] = UInt16(((gy &* (seed + 5)) % 256) * 257)
                            v[o + 2] = UInt16(((gx ^ gy) % 256) * 257)
                            v[o + 3] = 65535
                        }
                    }
                }
            }
            b.replaceTile(tx: tx, ty: ty, with: Tile(width: tw, height: th, channels: channels, storage: .u16(v)))
        }
    }
    return b
}

/// Режимы слоёв замера: слой i (с 1) получает benchModes[i % 6]; у слоя 1 — маска из узора 99.
let benchModes: [BlendMode] = [.multiply, .softLight, .color, .overlay, .screen, .hardMix]

/// Сравнение двух PNG: наибольшее и среднее отличие каналов (в шагах 16 бит) и доля пикселей, отличающихся больше 1/255.
func diff(_ a: String, _ b: String) throws {
    let x = try PNG.decode(try readFile(a)).image, y = try PNG.decode(try readFile(b)).image
    guard x.width == y.width, x.height == y.height else {
        throw CLIError(description: "размеры \(x.width)×\(x.height) и \(y.width)×\(y.height)")
    }
    var maxd: Float = 0, sum: Double = 0, over = 0
    for p in 0..<(x.width * x.height) {
        var pd: Float = 0
        for c in 0..<4 {
            let d = abs(x.data[p * 4 + c] - y.data[p * 4 + c])
            pd = max(pd, d)
            sum += Double(d)
        }
        maxd = max(maxd, pd)
        if pd > 1.0 / 255 { over += 1 }
    }
    let n = Double(x.width * x.height * 4)
    print(String(format: "diff %@ ↔ %@: макс %.1f шагов 16 бит (%.4f), среднее %.2f шага, пикселей с отличием > 1/255: %.4f%%",
                 (a as NSString).lastPathComponent, (b as NSString).lastPathComponent, maxd * 65535, maxd, sum / n * 65535,
                 Double(over) / Double(x.width * x.height) * 100))
}

/// Слои замера в PNG 16 бит — для такого же документа в образце.
func genImages(_ args: [String: String]) throws {
    let size = (args["--size"] ?? "4000x3000").split(separator: "x").compactMap { Int($0) }
    guard size.count == 2, let out = args["--out"] else { throw CLIError(description: "pe gen-images --size ШxВ --layers N --out DIR") }
    let layers = max(Int(args["--layers"] ?? "5") ?? 5, 2)
    for i in 0..<layers {
        try writeFile((out as NSString).appendingPathComponent("layer_\(i).png"),
                      try PNG.encode(benchPattern(size[0], size[1], seed: i).toImage(), bitDepth: 16, level: 1))
    }
    try writeFile((out as NSString).appendingPathComponent("mask.png"),
                  try PNG.encode(benchPattern(size[0], size[1], seed: 99, channels: 1).toImage(), bitDepth: 16, level: 1))
    print("записано \(layers) слоёв и маска в \(out)")
}

/// Документ из слоёв pe gen-images — сохранить в наш формат.
func pack(_ args: [String: String]) throws {
    guard let dir = args["--images"], let out = args["--out"] else { throw CLIError(description: "pe pack --images DIR --out FILE") }
    let start = Date()
    let path = { (n: String) in (dir as NSString).appendingPathComponent(n) }
    var doc = try openImage(path("layer_0.png"))
    var i = 1
    while FileManager.default.fileExists(atPath: path("layer_\(i).png")) {
        var l = Layer.bitmap(name: "layer_\(i)", try loadBitmap(path("layer_\(i).png")).0)
        l.blendMode = benchModes[i % benchModes.count]
        l.opacity = 0.8
        if i == 1 { l.masks = [LayerMask(bitmap: try loadMask(path("mask.png")), backgroundValue: 1)] }
        doc.layers.append(l)
        i += 1
    }
    let opened = Date().timeIntervalSince(start)
    let t = Date()
    let bytes = try DocumentFile.save(doc)
    let saveTime = Date().timeIntervalSince(t)
    try writeFile(out, bytes)
    let t2 = Date()
    _ = try DocumentFile.load(bytes)
    print(String(format: "pack %@: открытие PNG и сборка %.2f с | сохранение %.2f с (%.1f МБ) | открытие %.2f с",
                 (dir as NSString).lastPathComponent, opened, saveTime, Double(bytes.count) / 1_048_576, Date().timeIntervalSince(t2)))
}

func bench(_ args: [String: String]) throws {
    let size = (args["--size"] ?? "4000x3000").split(separator: "x").compactMap { Int($0) }
    guard size.count == 2 else { throw CLIError(description: "--size ШxВ") }
    let (w, h) = (size[0], size[1])
    let layerCount = max(Int(args["--layers"] ?? "5") ?? 5, 2)
    let renderer = try makeRenderer(args["--renderer"] ?? "cpu")
    func clock() -> Double { Date().timeIntervalSinceReferenceDate }
    func timed<T>(_ body: () throws -> T) rethrows -> (T, Double) {
        let t = clock()
        let r = try body()
        return (r, clock() - t)
    }

    let noise = Int(args["--noise"] ?? "0") ?? 0
    func pattern(_ seed: Int, channels: Int = 4) -> Bitmap { benchPattern(w, h, seed: seed, channels: channels, noise: noise) }
    let (doc, buildTime) = timed { () -> Document in
        var doc = Document(width: w, height: h, depth: .u16)
        var layers: [Layer] = [.bitmap(name: "base", pattern(0))]
        for i in 1..<layerCount {
            var l = Layer.bitmap(name: "layer \(i)", pattern(i))
            l.blendMode = benchModes[i % benchModes.count]
            l.opacity = 0.8
            if i == 1 { l.masks = [LayerMask(bitmap: pattern(99, channels: 1), backgroundValue: 1)] }
            layers.append(l)
        }
        let inner = layers.removeLast()
        layers.append(.group(name: "group", [inner], blendMode: .passThrough))
        doc.layers = layers
        return doc
    }

    // Окно 2560×1440: в масштабе 100 % (центр документа) и «весь снимок по размеру окна».
    let vw = min(2560, w), vh = min(1440, h)
    let actual = RenderRegion(x: (w - vw) / 2, y: (h - vh) / 2, width: vw, height: vh, level: 0)
    var fitLevel = 0
    while fitLevel < 8, (w >> fitLevel) > 2560 || (h >> fitLevel) > 1440 { fitLevel += 1 }
    let fit = RenderRegion.whole(doc, level: fitLevel)
    let (_, actualCold) = try timed { try renderer.region(doc, actual) }
    let (_, actualWarm) = try timed { try renderer.region(doc, actual) }
    let (_, fitCold) = try timed { try renderer.region(doc, fit) }
    let (_, fitWarm) = try timed { try renderer.region(doc, fit) }

    // Полный рендер кусками 2048×2048 (результат не копится в памяти — как при экспорте по частям).
    let (unsupported, fullTime) = try timed { () -> Int in
        var n = 0
        for y0 in stride(from: 0, to: h, by: 2048) {
            for x0 in stride(from: 0, to: w, by: 2048) {
                n = try renderer.region(doc, RenderRegion(x: x0, y: y0, width: min(2048, w - x0), height: min(2048, h - y0))).unsupported.count
            }
        }
        return n
    }
    let workPeak = peakMemoryMB()
    let mb = { (b: Int) in Double(b) / 1_048_576 }
    let memoryLine = String(format: "память: пиксели документа %.0f МБ, копии %.0f МБ, текстуры %.0f МБ, пик при работе %.0f МБ",
                            mb(doc.pixelBytes), mb(MipCache.shared.currentBytes), mb(renderer.textureBytes()), workPeak)
    let (saved, saveTime) = try timed { try DocumentFile.save(doc) }
    let (_, loadTime) = try timed { try DocumentFile.load(saved) }
    let mp = Double(w * h) / 1_000_000
    print(String(format: "bench %@ %dx%d (%.1f МП), слоёв %d | построение %.2f с | окно 100%% %dx%d: %.0f мс, повторно %.0f мс | окно «по размеру» (1/%d): %.0f мс, повторно %.0f мс | весь документ %.2f с (%.0f МП·слоёв/с) | сохранение %.2f с (%.0f МБ), открытие %.2f с | пик памяти с сохранением и открытием %.0f МБ | неподдержано %d",
                 renderer.name, w, h, mp, layerCount, buildTime, vw, vh, actualCold * 1000, actualWarm * 1000, 1 << fitLevel,
                 fitCold * 1000, fitWarm * 1000, fullTime, mp * Double(layerCount) / fullTime, saveTime,
                 Double(saved.count) / 1_048_576, loadTime, peakMemoryMB(), unsupported))
    print("  " + memoryLine)
    if args["--export"] != nil {
        // Экспорт PNG 16 бит целиком — для сравнения с экспортом образца (память после этого замера не учитывается).
        let (png, exportTime) = try timed { try PNG.encode(try renderer.whole(doc).image, bitDepth: 16, level: 1) }
        print(String(format: "  экспорт PNG 16 бит: %.2f с", exportTime))
        if let path = args["--export-path"] { try writeFile(path, png) }
    }
}

func parseFlags(_ list: ArraySlice<String>) -> [String: String] {
    var out: [String: String] = [:]
    var it = list.makeIterator()
    while let key = it.next() {
        if key.hasPrefix("--"), let value = it.next() { out[key] = value }
    }
    return out
}

let argv = CommandLine.arguments
do {
    switch argv.dropFirst().first {
    case "reftest":
        try reftest(parseFlags(argv.dropFirst(2)))
    case "bench":
        try bench(parseFlags(argv.dropFirst(2)))
    case "gen-images":
        try genImages(parseFlags(argv.dropFirst(2)))
    case "pack":
        try pack(parseFlags(argv.dropFirst(2)))
    case "diff":
        guard argv.count == 4 else { throw CLIError(description: "pe diff <a.png> <b.png>") }
        try diff(argv[2], argv[3])
    case "render-png":
        guard argv.count == 4 else { throw CLIError(description: "pe render-png <вход.png> <выход.png>") }
        let result = try CPURenderer.render(try openImage(argv[2]))
        try writeFile(argv[3], try PNG.encode(result.image, bitDepth: 16))
    default:
        print("pe reftest --manifest M --inputs DIR --out DIR [--suites blend,masks,probe] [--renderer cpu|metal]\npe render-png <вход.png> <выход.png>")
    }
} catch {
    FileHandle.standardError.write(Data("ошибка: \(error)\n".utf8))
    exit(1)
}
