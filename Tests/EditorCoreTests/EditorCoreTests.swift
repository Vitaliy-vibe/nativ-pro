@testable import EditorCore
import XCTest

/// Однотонный растр w×h заданного цвета RGBA.
func solid(_ w: Int, _ h: Int, _ rgba: [Float], depth: BitDepth = .u16) -> Bitmap {
    var img = FloatImage(width: w, height: h, channels: 4)
    for y in 0..<h {
        for x in 0..<w {
            for c in 0..<4 { img[x, y, c] = rgba[c] }
        }
    }
    return Bitmap(image: img, depth: depth)
}

func pixel(_ r: RenderResult, _ x: Int, _ y: Int) -> [Float] {
    (0..<4).map { r.image[x, y, $0] }
}

func assertClose(_ a: [Float], _ b: [Float], _ tol: Float = 1e-4, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(a.count, b.count, file: file, line: line)
    for (x, y) in zip(a, b) where abs(x - y) > tol {
        XCTFail("\(a) ≠ \(b)", file: file, line: line)
        return
    }
}

final class PixelsAndPNGTests: XCTestCase {
    func testPNGRoundTrip16And8() throws {
        var img = FloatImage(width: 300, height: 5, channels: 4)
        for i in img.data.indices { img.data[i] = Float((i * 7919) % 65536) / 65535 }
        let back16 = try PNG.decode(try PNG.encode(img, bitDepth: 16))
        XCTAssertEqual(back16.bitDepth, 16)
        XCTAssertTrue(back16.hasSRGBChunk)
        for i in img.data.indices { XCTAssertEqual(back16.image.data[i], img.data[i], accuracy: 0.5 / 65535) }
        let back8 = try PNG.decode(try PNG.encode(img, bitDepth: 8))
        for i in img.data.indices { XCTAssertEqual(back8.image.data[i], img.data[i], accuracy: 0.5 / 255 + 1e-6) }
    }

    func testBitmapAcrossTilesAndSharing() {
        let a = solid(300, 260, [1, 0, 0, 1])
        XCTAssertEqual(a.tilesAcross, 2)
        XCTAssertEqual(a.tilesDown, 2)
        XCTAssertEqual(a.value(x: 299, y: 259, channel: 0), 1)
        XCTAssertEqual(a.value(x: 300, y: 0, channel: 3), 0, "за пределами — пусто")
        var b = a
        b.replaceTile(tx: 0, ty: 0, with: nil)
        XCTAssertEqual(a.value(x: 0, y: 0, channel: 0), 1, "исходный растр не изменился")
        XCTAssertEqual(b.value(x: 0, y: 0, channel: 0), 0)
        XCTAssertTrue(a.tiles[1] === b.tiles[1], "незатронутая плитка общая")
    }

    func testTransparentTilesAreNotStored() {
        let empty = solid(512, 512, [0, 0, 0, 0])
        XCTAssertTrue(empty.tiles.allSatisfy { $0 == nil })
    }
}

final class BlendTests: XCTestCase {
    func v(_ x: Float) -> SIMD3<Float> { SIMD3(repeating: x) }

    func testSeparableReferenceValues() {
        // Значения по формулам W3C, проверенным эталонами.
        XCTAssertEqual(BlendMode.multiply.apply(v(0.5), v(0.4)).x, 0.2, accuracy: 1e-6)
        XCTAssertEqual(BlendMode.screen.apply(v(0.5), v(0.4)).x, 0.7, accuracy: 1e-6)
        XCTAssertEqual(BlendMode.overlay.apply(v(0.25), v(0.8)).x, 0.4, accuracy: 1e-6)
        XCTAssertEqual(BlendMode.softLight.apply(v(0.2), v(0.8)).x, 0.2 + 0.6 * ((((16 * 0.2) - 12) * 0.2 + 4) * 0.2 - 0.2), accuracy: 1e-6)
        XCTAssertEqual(BlendMode.colorDodge.apply(v(0.5), v(0.5)).x, 1, accuracy: 1e-6)
        XCTAssertEqual(BlendMode.colorBurn.apply(v(0.5), v(0.5)).x, 0, accuracy: 1e-6)
        XCTAssertEqual(BlendMode.divide.apply(v(0.3), v(0.6)).x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(BlendMode.subtract.apply(v(0.3), v(0.6)).x, 0, accuracy: 1e-6)
    }

    func testHardMixStrictThreshold() {
        // Подтверждено эталоном: на точной границе b + s = 1 результат 0.
        XCTAssertEqual(BlendMode.hardMix.apply(v(0.5), v(0.5)).x, 0)
        XCTAssertEqual(BlendMode.hardMix.apply(v(0.5), v(0.51)).x, 1)
    }

    func testNonSeparableKeepsBackdropLuminosity() {
        let b = SIMD3<Float>(0.2, 0.6, 0.4), s = SIMD3<Float>(0.9, 0.1, 0.3)
        XCTAssertEqual(Blend.lum(BlendMode.color.apply(b, s)), Blend.lum(b), accuracy: 1e-5)
        XCTAssertEqual(Blend.lum(BlendMode.luminosity.apply(b, s)), Blend.lum(s), accuracy: 1e-5)
    }

    func testAppleScriptNamesRoundTrip() {
        XCTAssertEqual(BlendMode.allCases.count, 28)
        for m in BlendMode.allCases { XCTAssertEqual(BlendMode(appleScriptName: m.appleScriptName), m) }
    }
}

final class CompositeTests: XCTestCase {
    func doc(_ layers: [Layer], w: Int = 4, h: Int = 4) -> Document {
        var d = Document(width: w, height: h, depth: .u16)
        d.layers = layers
        return d
    }

    func testNormalOpacityInGammaSpace() throws {
        var top = Layer.bitmap(name: "top", solid(4, 4, [1, 1, 1, 1]))
        top.opacity = 0.5
        let r = try CPURenderer.render(doc([.bitmap(name: "base", solid(4, 4, [0, 0, 0, 1])), top]))
        assertClose(pixel(r, 0, 0), [0.5, 0.5, 0.5, 1])
    }

    func testOverTransparentCanvasKeepsColor() throws {
        let r = try CPURenderer.render(doc([.bitmap(name: "half", solid(4, 4, [0.2, 0.4, 0.6, 0.5]))]))
        assertClose(pixel(r, 1, 1), [0.2, 0.4, 0.6, 0.5])
    }

    func testPositionOffset() throws {
        let r = try CPURenderer.render(doc([.bitmap(name: "bg", solid(8, 8, [1, 1, 1, 1])),
                                            .bitmap(name: "dot", solid(2, 2, [1, 0, 0, 1]), at: PixelPoint(x: 3, y: 5))], w: 8, h: 8))
        assertClose(pixel(r, 3, 5), [1, 0, 0, 1])
        assertClose(pixel(r, 4, 6), [1, 0, 0, 1])
        assertClose(pixel(r, 5, 5), [1, 1, 1, 1])
        assertClose(pixel(r, 3, 4), [1, 1, 1, 1])
    }

    func testMasksHideRevealDensityInvert() throws {
        var top = Layer.bitmap(name: "top", solid(4, 4, [1, 0, 0, 1]))
        top.masks = [.hideAll()]
        let base = Layer.bitmap(name: "base", solid(4, 4, [0, 0, 1, 1]))
        assertClose(pixel(try CPURenderer.render(doc([base, top])), 0, 0), [0, 0, 1, 1])
        top.masks[0].density = 0.25  // m' = 1 − 0.25·(1 − 0) = 0.75
        assertClose(pixel(try CPURenderer.render(doc([base, top])), 0, 0), [0.75, 0, 0.25, 1])
        top.masks[0].density = 1
        top.masks[0].isInverted = true
        assertClose(pixel(try CPURenderer.render(doc([base, top])), 0, 0), [1, 0, 0, 1])
        top.masks[0].isEnabled = false
        top.masks[0].isInverted = false
        assertClose(pixel(try CPURenderer.render(doc([base, top])), 0, 0), [1, 0, 0, 1])
    }

    func testClippingUsesBaseAlphaAndHiddenBaseHidesClipped() throws {
        let bg = Layer.bitmap(name: "bg", solid(4, 4, [1, 1, 1, 1]))
        var base = Layer.bitmap(name: "base", solid(2, 4, [0, 0, 1, 1]))  // только левая половина
        var clipped = Layer.bitmap(name: "clipped", solid(4, 4, [1, 0, 0, 1]))
        clipped.isClippingMask = true
        let r = try CPURenderer.render(doc([bg, base, clipped]))
        assertClose(pixel(r, 0, 0), [1, 0, 0, 1], 1e-4)
        assertClose(pixel(r, 3, 0), [1, 1, 1, 1], 1e-4)
        base.isVisible = false
        let hidden = try CPURenderer.render(doc([bg, base, clipped]))
        assertClose(pixel(hidden, 0, 0), [1, 1, 1, 1], 1e-4)
    }

    func testPassThroughVersusIsolatedGroup() throws {
        let base = Layer.bitmap(name: "base", solid(4, 4, [0.5, 0.5, 0.5, 1]))
        var mult = Layer.bitmap(name: "mult", solid(4, 4, [0.5, 0.5, 0.5, 1]))
        mult.blendMode = .multiply
        // pass through: multiply видит фон документа → 0.25
        let pass = try CPURenderer.render(doc([base, .group(name: "g", [mult], blendMode: .passThrough)]))
        assertClose(pixel(pass, 0, 0), [0.25, 0.25, 0.25, 1])
        // изолированная группа: multiply по пустому фону → слой как есть, затем normal → 0.5
        let iso = try CPURenderer.render(doc([base, .group(name: "g", [mult], blendMode: .normal)]))
        assertClose(pixel(iso, 0, 0), [0.5, 0.5, 0.5, 1])
    }

    func testBehindDoesNotCoverOpaqueBackdrop() throws {
        var top = Layer.bitmap(name: "top", solid(4, 4, [1, 0, 0, 1]))
        top.blendMode = .behind
        let r = try CPURenderer.render(doc([.bitmap(name: "base", solid(4, 4, [0, 0, 1, 1])), top]))
        assertClose(pixel(r, 0, 0), [0, 0, 1, 1])
    }

    func testUnsupportedLayersAreReportedNotSilentlySkipped() throws {
        let text = Layer(name: "Заголовок", content: .unsupported(kind: "text"))
        let r = try CPURenderer.render(doc([.bitmap(name: "bg", solid(4, 4, [1, 1, 1, 1])), text]))
        XCTAssertEqual(r.unsupported.map(\.name), ["Заголовок"])
    }

    func testOnlySRGBAccepted() {
        var d = doc([])
        d.colorProfile = "Display P3"
        XCTAssertThrowsError(try CPURenderer.render(d))
    }
}

final class HistoryTests: XCTestCase {
    func testUndoRedoAndNames() throws {
        var d = Document(width: 4, height: 4, depth: .u8)
        let layer = Layer.bitmap(name: "L", solid(4, 4, [1, 0, 0, 1], depth: .u8))
        d.layers = [layer]
        var h = History(d)
        try h.perform("Изменить непрозрачность") { try $0.updateLayer(layer.id) { $0.opacity = 0.3 } }
        try h.perform("Скрыть слой") { try $0.updateLayer(layer.id) { $0.isVisible = false } }
        XCTAssertEqual(h.undoName, "Скрыть слой")
        XCTAssertTrue(h.undo())
        XCTAssertEqual(h.current.layers[0].isVisible, true)
        XCTAssertEqual(h.current.layers[0].opacity, 0.3)
        XCTAssertEqual(h.redoName, "Скрыть слой")
        XCTAssertTrue(h.redo())
        XCTAssertEqual(h.current.layers[0].isVisible, false)
    }

    func testCoalescingSliderDrag() throws {
        var d = Document(width: 1, height: 1, depth: .u8)
        let layer = Layer.bitmap(name: "L", solid(1, 1, [1, 1, 1, 1], depth: .u8))
        d.layers = [layer]
        var h = History(d)
        for v in stride(from: Float(0.9), through: 0.1, by: -0.1) {
            try h.perform("Изменить непрозрачность", coalescing: "opacity") { try $0.updateLayer(layer.id) { $0.opacity = v } }
        }
        XCTAssertEqual(h.undoStack.count, 1)
        h.undo()
        XCTAssertEqual(h.current.layers[0].opacity, 1)
    }

    func testFailedChangeLeavesNoStep() {
        var h = History(Document(width: 1, height: 1, depth: .u8))
        XCTAssertThrowsError(try h.perform("Нет такого слоя") { try $0.updateLayer(LayerID()) { $0.opacity = 0 } })
        XCTAssertFalse(h.canUndo)
    }

    func testLimit() throws {
        var h = History(Document(width: 1, height: 1, depth: .u8), limit: 3)
        for i in 0..<10 { h.perform("шаг \(i)") { $0.resolution = Double(i) } }
        XCTAssertEqual(h.undoStack.count, 3)
        XCTAssertEqual(h.undoName, "шаг 9")
    }
}
