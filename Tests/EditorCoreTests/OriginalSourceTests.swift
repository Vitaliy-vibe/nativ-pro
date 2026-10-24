@testable import EditorCore
import XCTest

final class OriginalSourceTests: XCTestCase {
    func pngBytes(_ w: Int, _ h: Int, depth: Int) throws -> [UInt8] {
        var img = FloatImage(width: w, height: h, channels: 4)
        for y in 0..<h {
            for x in 0..<w {
                img[x, y, 0] = Float(x) / Float(w)
                img[x, y, 1] = Float(y) / Float(h)
                img[x, y, 2] = Float((x * y) % 97) / 96
                img[x, y, 3] = 1
            }
        }
        return try PNG.encode(img, bitDepth: depth, level: 9)
    }

    func testUnmodifiedLayerIsStoredAsItsSourceFile() throws {
        let png = try pngBytes(300, 270, depth: 16)
        let bitmap = try PNG.decodeBitmap(png)
        XCTAssertEqual(bitmap.originalSource?.bytes, png)
        var doc = Document(width: 300, height: 270, depth: .u16)
        let layer = Layer.bitmap(name: "photo", bitmap)
        doc.layers = [layer]
        let file = try DocumentFile.save(doc)
        let zip = try ZipReader(file)
        XCTAssertTrue(zip.contains("sources/\(layer.id)"))
        XCTAssertFalse(zip.entries.contains { $0.name.hasPrefix("tiles/") }, "плиток быть не должно")
        let loaded = try DocumentFile.load(file)
        guard case .bitmap(let back) = loaded.layers[0].content else { return XCTFail("не растр") }
        XCTAssertEqual(back.toImage(), bitmap.toImage())
        XCTAssertEqual(back.originalSource?.bytes, png, "после открытия исходник сохраняется")
    }

    func testModifiedLayerDropsSourceAndIsStoredAsTiles() throws {
        var bitmap = try PNG.decodeBitmap(try pngBytes(64, 64, depth: 8))
        bitmap.replaceTile(tx: 0, ty: 0, with: nil)
        XCTAssertNil(bitmap.originalSource)
        var doc = Document(width: 64, height: 64, depth: .u8)
        doc.layers = [.bitmap(name: "edited", bitmap)]
        let zip = try ZipReader(try DocumentFile.save(doc))
        XCTAssertFalse(zip.entries.contains { $0.name.hasPrefix("sources/") })
    }

    func testMismatchedSourceIsReportedAsCorrupt() throws {
        // Растр 64×64, а «исходник» — другой PNG 10×10: такое описание противоречиво.
        let bitmap = try PNG.decodeBitmap(try pngBytes(64, 64, depth: 8)).withOriginalSource(OriginalSource(format: "png", bytes: try pngBytes(10, 10, depth: 8)))
        var doc = Document(width: 64, height: 64, depth: .u8)
        doc.layers = [.bitmap(name: "bad", bitmap)]
        XCTAssertThrowsError(try DocumentFile.load(try DocumentFile.save(doc))) {
            guard case DocumentFileError.corrupt = $0 else { return XCTFail("ожидалась ошибка «повреждён», получено \($0)") }
        }
    }
}
