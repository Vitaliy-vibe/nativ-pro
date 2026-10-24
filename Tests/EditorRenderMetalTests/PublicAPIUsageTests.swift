import EditorCore
import XCTest

/// Компилируется и на Linux: использует ядро так же, как EditorRenderMetal (без @testable),
/// чтобы ошибки уровня доступа ловились до сборки на Mac.
final class PublicAPIUsageTests: XCTestCase {
    func testAPIUsedByMetalRendererIsPublic() throws {
        var img = FloatImage(width: 2, height: 2, channels: 4)
        img.data[0] = 1
        var layer = Layer.bitmap(name: "L", Bitmap(image: img, depth: .u16), at: PixelPoint(x: 1, y: 1))
        var mask = LayerMask(bitmap: nil, offset: .zero, backgroundValue: 1)
        mask.density = 0.5
        layer.masks = [mask]
        let m = layer.masks[0]
        _ = (m.isEnabled, m.bitmap?.toImage(), m.offset.x, m.backgroundValue, m.density, m.isInverted)
        _ = (layer.isVisible, layer.isClippingMask, layer.opacity, layer.position.y, layer.name, layer.id)
        XCTAssertNotNil(BlendMode.allCases.firstIndex(of: layer.blendMode))
        if case .bitmap(let b) = layer.content { XCTAssertEqual(b.toImage().width, 2) }
        let result = RenderResult(image: img, unsupported: [UnsupportedLayer(id: layer.id, name: layer.name, kind: "text")])
        XCTAssertEqual(result.unsupported.count, 1)
        // Плитки, уровни и кеш копий — как в MetalRenderer.Pass.pieces и TextureCache.
        let bitmap = Bitmap(image: img, depth: .u16)
        let (lw, lh) = bitmap.levelSize(1)
        XCTAssertEqual(lw + lh, 2)
        if let t = bitmap.levelTile(tx: 0, ty: 0, level: 1, cache: MipCache.shared), let src = bitmap.tiles[0 * bitmap.tilesAcross + 0] {
            _ = (t.width, t.height, t.channels, t.depth, src.width)
            if case .u16(let v) = t.storage { XCTAssertEqual(v.count, t.width * t.height * t.channels) }
        }
        let region = RenderRegion(x: 0, y: 0, width: 1, height: 1, level: 1)
        _ = (region.x, region.y, region.width, region.height, region.level, RenderRegion.whole(Document(width: 1, height: 1, depth: .u8)))
        _ = try CPURenderer.render(Document(width: 2, height: 2, depth: .u8), region: region)
        var doc = Document(width: 2, height: 2, depth: .u8)
        doc.colorProfile = "Display P3"
        XCTAssertThrowsError(try CPURenderer.render(doc)) { XCTAssertEqual($0 as? DocumentError, .unsupportedColorProfile("Display P3")) }
    }
}
