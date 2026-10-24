#if canImport(Metal)
import EditorCore
import EditorRenderMetal
import XCTest

/// Рендер на Metal должен совпадать с эталонным CPU-рендером (а тот — с образцом, см. pe reftest).
final class MetalVsCPUTests: XCTestCase {
    func randomBitmap(_ w: Int, _ h: Int, channels: Int = 4, seed: Int) -> Bitmap {
        var img = FloatImage(width: w, height: h, channels: channels)
        var state = UInt64(truncatingIfNeeded: seed &* 2654435761 &+ 1)
        for i in img.data.indices {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            img.data[i] = Float(state >> 40) / Float(1 << 24)
        }
        return Bitmap(image: img, depth: .u16)
    }

    func maxDiff(_ a: FloatImage, _ b: FloatImage) -> Float {
        zip(a.data, b.data).map { abs($0 - $1) }.max() ?? 0
    }

    func testAllBlendModesMatchCPU() throws {
        let metal = try MetalRenderer()
        for (i, mode) in BlendMode.allCases.enumerated() {
            var doc = Document(width: 64, height: 48, depth: .u16)
            var top = Layer.bitmap(name: "top", randomBitmap(50, 40, seed: i + 100), at: PixelPoint(x: 7, y: 5))
            top.blendMode = mode
            top.opacity = 0.7
            doc.layers = [.bitmap(name: "base", randomBitmap(64, 48, seed: i)), top]
            let d = maxDiff(try CPURenderer.render(doc).image, try metal.render(doc).image)
            XCTAssertLessThan(d, 2e-4, "режим \(mode): расхождение \(d)")
        }
    }

    func testRegionsAndLevelsMatchCPU() throws {
        let metal = try MetalRenderer()
        var doc = Document(width: 900, height: 700, depth: .u16)
        var top = Layer.bitmap(name: "top", randomBitmap(600, 500, seed: 11), at: PixelPoint(x: 130, y: 90))
        top.blendMode = .overlay
        top.masks = [LayerMask(bitmap: randomBitmap(500, 300, channels: 1, seed: 12), offset: PixelPoint(x: 200, y: 150), backgroundValue: 0.25)]
        var clipped = Layer.bitmap(name: "clip", randomBitmap(900, 700, seed: 13))
        clipped.isClippingMask = true
        clipped.blendMode = .hue
        let group = Layer.group(name: "g", [Layer.bitmap(name: "in", randomBitmap(300, 300, seed: 14), at: PixelPoint(x: 500, y: 350))], blendMode: .multiply)
        doc.layers = [.bitmap(name: "base", randomBitmap(900, 700, seed: 10)), top, clipped, group]
        let regions = [RenderRegion(x: 211, y: 97, width: 333, height: 290),
                       RenderRegion(x: 0, y: 0, width: 450, height: 350, level: 1),
                       RenderRegion(x: 40, y: 30, width: 150, height: 120, level: 2),
                       .whole(doc, level: 3)]
        for r in regions {
            let d = maxDiff(try CPURenderer.render(doc, region: r).image, try metal.render(doc, region: r).image)
            XCTAssertLessThan(d, 2e-4, "область \(r): расхождение \(d)")
        }
    }

    func testMasksGroupsClippingMatchCPU() throws {
        let metal = try MetalRenderer()
        var doc = Document(width: 80, height: 60, depth: .u16)
        var masked = Layer.bitmap(name: "masked", randomBitmap(60, 50, seed: 1), at: PixelPoint(x: 10, y: 4))
        var mask = LayerMask(bitmap: randomBitmap(30, 30, channels: 1, seed: 2), offset: PixelPoint(x: 20, y: 10), backgroundValue: 0.3)
        mask.density = 0.8
        mask.isInverted = true
        masked.masks = [mask, .revealAll()]
        masked.blendMode = .softLight
        var clipped = Layer.bitmap(name: "clipped", randomBitmap(80, 60, seed: 3))
        clipped.isClippingMask = true
        clipped.blendMode = .color
        var inner = Layer.bitmap(name: "inner", randomBitmap(40, 40, seed: 4), at: PixelPoint(x: 30, y: 15))
        inner.blendMode = .multiply
        var pass = Layer.group(name: "pass", [inner], blendMode: .passThrough)
        pass.opacity = 0.6
        pass.masks = [LayerMask(bitmap: randomBitmap(80, 60, channels: 1, seed: 5), backgroundValue: 1)]
        let isolated = Layer.group(name: "iso", [Layer.bitmap(name: "x", randomBitmap(20, 20, seed: 6), at: PixelPoint(x: 5, y: 5))], blendMode: .screen)
        let text = Layer(name: "Текст", content: .unsupported(kind: "text"))
        doc.layers = [.bitmap(name: "base", randomBitmap(80, 60, seed: 7)), masked, clipped, pass, isolated, text]
        let cpu = try CPURenderer.render(doc), gpu = try metal.render(doc)
        XCTAssertLessThan(maxDiff(cpu.image, gpu.image), 2e-4)
        XCTAssertEqual(gpu.unsupported.map(\.name), ["Текст"])
    }
}
#endif
