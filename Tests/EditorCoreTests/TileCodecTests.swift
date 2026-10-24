@testable import EditorCore
import XCTest

final class TileCodecTests: XCTestCase {
    func randomTile(_ w: Int, _ h: Int, channels: Int, depth: BitDepth, seed: UInt64) -> Tile {
        var state = seed &* 6364136223846793005 &+ 1
        func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 33
        }
        let n = w * h * channels
        switch depth {
        case .u8: return Tile(width: w, height: h, channels: channels, storage: .u8((0..<n).map { i in i % 7 == 0 ? 255 : UInt8(next() & 0xFF) }))
        case .u16: return Tile(width: w, height: h, channels: channels, storage: .u16((0..<n).map { i in i % 5 == 0 ? 65535 : UInt16(next() & 0xFFFF) }))
        }
    }

    func values(_ t: Tile) -> [Int] {
        switch t.storage {
        case .u8(let v): return v.map(Int.init)
        case .u16(let v): return v.map(Int.init)
        }
    }

    func testLosslessForAllShapes() throws {
        for depth in [BitDepth.u8, .u16] {
            for channels in [1, 4] {
                for (w, h) in [(1, 1), (17, 3), (256, 256), (255, 1)] {
                    let t = randomTile(w, h, channels: channels, depth: depth, seed: UInt64(w * 31 + h + channels))
                    for codec in [TileCodec.rawZlib, .deltaPlanesZlib] {
                        let back = try codec.decode(try codec.encode(t), width: w, height: h, channels: channels, depth: depth)
                        XCTAssertEqual(values(back), values(t), "\(codec) \(depth) \(channels)к \(w)×\(h)")
                    }
                }
            }
        }
    }

    func testSmoothDataCompressesMuchBetterWithDelta() throws {
        var v = [UInt16](repeating: 0, count: 256 * 256 * 4)
        for y in 0..<256 { for x in 0..<256 { for c in 0..<4 { v[(y * 256 + x) * 4 + c] = UInt16((x * 200 + y * 37 + c * 1000) & 0xFFFF) } } }
        let t = Tile(width: 256, height: 256, channels: 4, storage: .u16(v))
        let raw = try TileCodec.rawZlib.encode(t).count, delta = try TileCodec.deltaPlanesZlib.encode(t).count
        XCTAssertLessThan(delta * 5, raw, "delta \(delta) против raw \(raw)")
    }

    func testReadsFormatVersion1() throws {
        // Файл формата 1: таблица tiles без столбца codec, плитки — сырые пиксели + zlib.
        var img = FloatImage(width: 3, height: 2, channels: 4)
        for i in img.data.indices { img.data[i] = Float(i % 4 == 3 ? 1 : (i % 9)) / 8 }
        let bitmap = Bitmap(image: img, depth: .u16)
        let tile = bitmap.tiles[0]!
        let layerID = LayerID()
        let db = try SQLiteDatabase.serialize { db in
            try db.execute("""
                CREATE TABLE info (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE layers (id TEXT PRIMARY KEY, parent TEXT, idx INTEGER NOT NULL, props TEXT NOT NULL);
                CREATE TABLE masks (id TEXT PRIMARY KEY, layer TEXT NOT NULL, idx INTEGER NOT NULL, props TEXT NOT NULL);
                CREATE TABLE bitmaps (owner TEXT PRIMARY KEY, width INTEGER NOT NULL, height INTEGER NOT NULL, channels INTEGER NOT NULL, depth INTEGER NOT NULL);
                CREATE TABLE tiles (owner TEXT NOT NULL, tx INTEGER NOT NULL, ty INTEGER NOT NULL, entry TEXT NOT NULL, PRIMARY KEY (owner, tx, ty));
                """)
            for (k, v) in [("format_version", "1"), ("width", "3"), ("height", "2"), ("depth", "16"), ("color_profile", "sRGB"), ("resolution", "72")] {
                try db.query("INSERT INTO info VALUES (?, ?)", [.text(k), .text(v)])
            }
            let props = #"{"blend":"normal","clipping":false,"kind":"bitmap","locked":false,"name":"L","opacity":1,"preserveTransparency":false,"visible":true,"x":0,"y":0}"#
            try db.query("INSERT INTO layers VALUES (?, NULL, 0, ?)", [.text(layerID.description), .text(props)])
            try db.query("INSERT INTO bitmaps VALUES (?, 3, 2, 4, 16)", [.text(layerID.description)])
            try db.query("INSERT INTO tiles VALUES (?, 0, 0, 't')", [.text(layerID.description)])
        }
        var zip = ZipWriter()
        try zip.add("document.sqlite", db)
        try zip.add("t", try TileCodec.rawZlib.encode(tile))
        let doc = try DocumentFile.load(try zip.finish())
        guard case .bitmap(let loaded) = doc.layers[0].content else { return XCTFail("не растр") }
        XCTAssertEqual(loaded.toImage(), bitmap.toImage())
    }
}
