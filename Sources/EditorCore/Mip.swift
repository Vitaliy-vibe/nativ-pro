import Foundation

/// Уменьшенные копии плиток для отрисовки в мелком масштабе (уровень L — уменьшение в 2^L раз).
/// Плитки неизменяемые, поэтому копия, построенная для плитки, верна, пока плитка жива; кеш хранит
/// слабую ссылку на исходную плитку и проверяет её при каждом обращении.
/// Уменьшение — среднее 2×2 с премультипликацией по альфе (без тёмной каймы на краях прозрачности).
public final class MipCache: @unchecked Sendable {
    public static let shared = MipCache()

    /// Предел памяти под копии (байты); при превышении удаляются давно не использованные.
    public var budget: Int
    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0
    private var bytes = 0

    struct Key: Hashable {
        let tile: ObjectIdentifier
        let level: Int
    }

    final class Entry {
        weak var source: Tile?
        let mip: Tile
        var used: UInt64
        init(source: Tile, mip: Tile, used: UInt64) {
            self.source = source
            self.mip = mip
            self.used = used
        }
    }

    public init(budget: Int = 1 << 30) {
        self.budget = budget
    }

    /// Копия плитки на уровне `level` (0 — сама плитка).
    public func mip(_ tile: Tile, level: Int) -> Tile {
        if level == 0 { return tile }
        let key = Key(tile: ObjectIdentifier(tile), level: level)
        lock.lock()
        clock += 1
        if let e = entries[key], e.source === tile {
            e.used = clock
            lock.unlock()
            return e.mip
        }
        lock.unlock()
        let finer = mip(tile, level: level - 1)
        let reduced = MipCache.halve(finer)
        lock.lock()
        clock += 1
        entries[key] = Entry(source: tile, mip: reduced, used: clock)
        bytes += MipCache.size(reduced)
        if bytes > budget { evict() }
        lock.unlock()
        return reduced
    }

    /// Сколько байт сейчас занимают копии.
    public var currentBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return bytes
    }

    public func removeAll() {
        lock.lock()
        entries.removeAll()
        bytes = 0
        lock.unlock()
    }

    private func evict() {
        // Сначала убрать копии умерших плиток, затем давно не использованные — до 3/4 бюджета.
        for (k, e) in entries where e.source == nil {
            bytes -= MipCache.size(e.mip)
            entries[k] = nil
        }
        guard bytes > budget else { return }
        for (k, e) in entries.sorted(by: { $0.value.used < $1.value.used }) {
            bytes -= MipCache.size(e.mip)
            entries[k] = nil
            if bytes <= budget * 3 / 4 { break }
        }
    }

    static func size(_ t: Tile) -> Int { t.width * t.height * t.channels * (t.depth == .u16 ? 2 : 1) }

    /// Уменьшение вдвое: среднее 2×2 (на нечётном краю — по имеющимся пикселям), с премультипликацией для RGBA.
    static func halve(_ t: Tile) -> Tile {
        let w = (t.width + 1) / 2, h = (t.height + 1) / 2, ch = t.channels
        let src = t.floats()
        var out = [Float](repeating: 0, count: w * h * ch)
        for y in 0..<h {
            let y0 = 2 * y, y1 = min(2 * y + 1, t.height - 1)
            for x in 0..<w {
                let x0 = 2 * x, x1 = min(2 * x + 1, t.width - 1)
                // Четыре соседа; на краю повторяются, что равносильно среднему по имеющимся.
                let idx = [(y0 * t.width + x0) * ch, (y0 * t.width + x1) * ch, (y1 * t.width + x0) * ch, (y1 * t.width + x1) * ch]
                let o = (y * w + x) * ch
                if ch == 4 {
                    var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                    for i in idx {
                        let pa = src[i + 3]
                        r += src[i] * pa
                        g += src[i + 1] * pa
                        b += src[i + 2] * pa
                        a += pa
                    }
                    if a > 0 {
                        out[o] = r / a
                        out[o + 1] = g / a
                        out[o + 2] = b / a
                    }
                    out[o + 3] = a / 4
                } else {
                    out[o] = (src[idx[0]] + src[idx[1]] + src[idx[2]] + src[idx[3]]) / 4
                }
            }
        }
        return Tile(floats: out, width: w, height: h, channels: ch, depth: t.depth)
    }
}

extension Tile {
    /// Все значения 0…1 одним массивом.
    func floats() -> [Float] {
        switch storage {
        case .u8(let v): return v.map { Float($0) / 255 }
        case .u16(let v): return v.map { Float($0) / 65535 }
        }
    }

    convenience init(floats: [Float], width: Int, height: Int, channels: Int, depth: BitDepth) {
        switch depth {
        case .u8: self.init(width: width, height: height, channels: channels, storage: .u8(floats.map { UInt8(min(max($0, 0), 1) * 255 + 0.5) }))
        case .u16: self.init(width: width, height: height, channels: channels, storage: .u16(floats.map { UInt16(min(max($0, 0), 1) * 65535 + 0.5) }))
        }
    }
}

/// Растр на заданном уровне для быстрого чтения внутри одного куска рендера:
/// нужные плитки взяты из кеша один раз, дальше — прямой доступ без блокировок.
struct BitmapView {
    let width: Int
    let height: Int
    let span: Int
    let across: Int
    let tiles: [Tile?]

    @inline(__always)
    func value(x: Int, y: Int, channel: Int) -> Float {
        guard x >= 0, y >= 0, x < width, y < height, let t = tiles[(y / span) * across + x / span] else { return 0 }
        return t.value(x: x % span, y: y % span, channel: channel)
    }
}

extension Bitmap {
    /// Вид растра на уровне `level`; уменьшенные плитки берутся только там, где растр пересекает
    /// прямоугольник `[x0, x1) × [y0, y1)` (в пикселях уровня, относительно начала растра).
    func view(level: Int, x0: Int, y0: Int, x1: Int, y1: Int, cache: MipCache = .shared) -> BitmapView {
        let span = Tile.size >> level
        let (w, h) = levelSize(level)
        var tiles = [Tile?](repeating: nil, count: self.tiles.count)
        let tx0 = max(0, x0) / span, ty0 = max(0, y0) / span
        let tx1 = min(tilesAcross - 1, (min(w, x1) - 1) / span), ty1 = min(tilesDown - 1, (min(h, y1) - 1) / span)
        if x1 > 0, y1 > 0, x0 < w, y0 < h, tx0 <= tx1, ty0 <= ty1 {
            for ty in ty0...ty1 {
                for tx in tx0...tx1 { tiles[ty * tilesAcross + tx] = levelTile(tx: tx, ty: ty, level: level, cache: cache) }
            }
        }
        return BitmapView(width: w, height: h, span: span, across: tilesAcross, tiles: tiles)
    }

    /// Размер растра на уровне `level`.
    public func levelSize(_ level: Int) -> (width: Int, height: Int) {
        let f = 1 << level
        return ((width + f - 1) / f, (height + f - 1) / f)
    }

    /// Плитка-копия на уровне `level` для плитки (tx, ty); `nil` — пусто.
    /// На уровне L плитка покрывает (256 >> L)×(256 >> L) пикселей уровня.
    @inline(__always)
    public func levelTile(tx: Int, ty: Int, level: Int, cache: MipCache = .shared) -> Tile? {
        guard let t = tiles[ty * tilesAcross + tx] else { return nil }
        return cache.mip(t, level: level)
    }

    /// Значение канала в пикселе уровня `level` (за пределами — 0).
    @inline(__always)
    public func value(x: Int, y: Int, channel: Int, level: Int, cache: MipCache = .shared) -> Float {
        if level == 0 { return value(x: x, y: y, channel: channel) }
        let span = Tile.size >> level
        let (lw, lh) = levelSize(level)
        guard x >= 0, y >= 0, x < lw, y < lh else { return 0 }
        guard let t = levelTile(tx: x / span, ty: y / span, level: level, cache: cache) else { return 0 }
        return t.value(x: x % span, y: y % span, channel: channel)
    }
}
