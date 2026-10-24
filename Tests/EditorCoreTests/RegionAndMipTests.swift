@testable import EditorCore
import XCTest

final class RegionAndMipTests: XCTestCase {
    func patterned(_ w: Int, _ h: Int, seed: Int, alphaHoles: Bool = false) -> Bitmap {
        var img = FloatImage(width: w, height: h, channels: 4)
        for y in 0..<h {
            for x in 0..<w {
                img[x, y, 0] = Float((x * (seed + 3) + y) % 256) / 255
                img[x, y, 1] = Float((y * (seed + 5)) % 256) / 255
                img[x, y, 2] = Float((x ^ y) % 256) / 255
                img[x, y, 3] = alphaHoles && (x / 13 + y / 7) % 3 == 0 ? 0 : 1
            }
        }
        return Bitmap(image: img, depth: .u16)
    }

    func document() -> Document {
        var doc = Document(width: 700, height: 530, depth: .u16)
        var top = Layer.bitmap(name: "top", patterned(500, 400, seed: 2, alphaHoles: true), at: PixelPoint(x: 90, y: 60))
        top.blendMode = .softLight
        top.masks = [LayerMask(bitmap: Bitmap(image: patterned(300, 300, seed: 9).toImage().channel0(), depth: .u16),
                               offset: PixelPoint(x: 150, y: 100), backgroundValue: 0.4)]
        var clipped = Layer.bitmap(name: "clip", patterned(700, 530, seed: 4))
        clipped.isClippingMask = true
        clipped.blendMode = .color
        let group = Layer.group(name: "g", [Layer.bitmap(name: "in", patterned(200, 200, seed: 7), at: PixelPoint(x: 400, y: 300))], blendMode: .multiply)
        doc.layers = [.bitmap(name: "base", patterned(700, 530, seed: 1)), top, clipped, group]
        return doc
    }

    func testRegionEqualsCropOfFullRender() throws {
        let doc = document()
        let full = try CPURenderer.render(doc).image
        let region = RenderRegion(x: 211, y: 97, width: 333, height: 290)   // пересекает границы кусков 256
        let part = try CPURenderer.render(doc, region: region).image
        for y in 0..<region.height {
            for x in 0..<region.width {
                for c in 0..<4 { XCTAssertEqual(part[x, y, c], full[region.x + x, region.y + y, c], "x \(x) y \(y)") }
            }
        }
    }

    func testWholeDocumentSplitIntoChunksIsSeamless() throws {
        // Документ больше одного куска: результат не должен зависеть от разбиения на куски.
        let doc = document()
        let full = try CPURenderer.render(doc).image
        var stitched = FloatImage(width: doc.width, height: doc.height, channels: 4)
        for (x0, y0, w, h) in [(0, 0, 350, 265), (350, 0, 350, 265), (0, 265, 350, 265), (350, 265, 350, 265)] {
            let part = try CPURenderer.render(doc, region: RenderRegion(x: x0, y: y0, width: w, height: h)).image
            for y in 0..<h { for x in 0..<w { for c in 0..<4 { stitched[x0 + x, y0 + y, c] = part[x, y, c] } } }
        }
        XCTAssertEqual(stitched, full)
    }

    func testLevelOfSolidColorKeepsColorAndSize() throws {
        var img = FloatImage(width: 600, height: 300, channels: 4)
        for i in stride(from: 0, to: img.data.count, by: 4) { img.data[i] = 0.2; img.data[i + 1] = 0.6; img.data[i + 2] = 0.9; img.data[i + 3] = 1 }
        var doc = Document(width: 600, height: 300, depth: .u16)
        doc.layers = [.bitmap(name: "c", Bitmap(image: img, depth: .u16))]
        let r = try CPURenderer.render(doc, region: .whole(doc, level: 2)).image
        XCTAssertEqual(r.width, 150)
        XCTAssertEqual(r.height, 75)
        assertClose((0..<4).map { r[149, 74, $0] }, [0.2, 0.6, 0.9, 1], 1e-4)
    }

    func testMipHasNoDarkFringeAtTransparency() {
        // Красный пиксель рядом с прозрачным чёрным: среднее с премультипликацией остаётся красным, альфа 0.5.
        var img = FloatImage(width: 2, height: 1, channels: 4)
        img[0, 0, 0] = 1; img[0, 0, 3] = 1
        let t = Bitmap(image: img, depth: .u16).tiles[0]!
        let m = MipCache().mip(t, level: 1)
        XCTAssertEqual(m.width, 1)
        XCTAssertEqual(m.value(x: 0, y: 0, channel: 0), 1, accuracy: 1e-4)
        XCTAssertEqual(m.value(x: 0, y: 0, channel: 3), 0.5, accuracy: 1e-4)
    }

    func testMipCacheNeverServesAnotherTilesMip() {
        let cache = MipCache(budget: 1 << 20)
        for i in 0..<200 {
            var img = FloatImage(width: 4, height: 4, channels: 4)
            for j in stride(from: 0, to: img.data.count, by: 4) { img.data[j] = Float(i % 256) / 255; img.data[j + 3] = 1 }
            let tile = Bitmap(image: img, depth: .u16).tiles[0]!
            XCTAssertEqual(cache.mip(tile, level: 2).value(x: 0, y: 0, channel: 0), Float(i % 256) / 255, accuracy: 1e-4)
        }
    }
}

extension FloatImage {
    /// Первый канал как одноканальное изображение (для масок в тестах).
    func channel0() -> FloatImage {
        var out = FloatImage(width: width, height: height, channels: 1)
        for y in 0..<height { for x in 0..<width { out[x, y, 0] = self[x, y, 0] } }
        return out
    }
}
