import EditorApp
import EditorCore
import XCTest

func solidBitmap(_ w: Int, _ h: Int, _ rgba: [Float], depth: BitDepth = .u8) -> Bitmap {
    var img = FloatImage(width: w, height: h, channels: 4)
    for y in 0..<h {
        for x in 0..<w {
            for c in 0..<4 { img[x, y, c] = rgba[c] }
        }
    }
    return Bitmap(image: img, depth: depth)
}

/// Документ 100×80: фон, красный квадрат, синий квадрат (снизу вверх).
func sampleSession() -> (EditorSession, [LayerID]) {
    var doc = Document(width: 100, height: 80, depth: .u8)
    let bg = Layer.bitmap(name: "bg", solidBitmap(100, 80, [1, 1, 1, 1]))
    let red = Layer.bitmap(name: "red", solidBitmap(20, 10, [1, 0, 0, 1]), at: PixelPoint(x: 10, y: 5))
    let blue = Layer.bitmap(name: "blue", solidBitmap(10, 10, [0, 0, 1, 1]), at: PixelPoint(x: 50, y: 30))
    doc.layers = [bg, red, blue]
    return (EditorSession(document: doc, russian: true), [bg.id, red.id, blue.id])
}

final class MenuSpecTests: XCTestCase {
    func testMainMenuParsesWithUniqueIDsAndShortcuts() throws {
        let menus = MenuSpec.main()
        XCTAssertEqual(menus.map(\.english), ["{app}", "File", "Edit", "Insert", "Image", "Tools", "Format", "Arrange", "View", "Window", "Help"])
        let all = MenuSpec.flatten(menus)
        XCTAssertGreaterThan(all.count, 200)
        XCTAssertEqual(all.first { $0.id == "file.new" }?.russian, "Новый…")
        XCTAssertEqual(all.first { $0.id == "app.hide" }?.icon, "eye.slash")
        let ids = all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "повтор идентификатора: \(Dictionary(grouping: ids, by: { $0 }).filter { $1.count > 1 }.keys)")
        // Все команды документа есть в меню.
        for id in EditorSession.documentCommands { XCTAssertTrue(ids.contains(id), id) }
    }

    func testShortcutParsing() {
        XCTAssertEqual(KeyShortcut("⇧⌘N"), KeyShortcut(modifiers: [.shift, .command], key: .character("n")))
        XCTAssertEqual(KeyShortcut("⌃⌘↑")?.key, .up)
        XCTAssertEqual(KeyShortcut("⌥⌫")?.key, .delete)
        XCTAssertEqual(KeyShortcut("⌘+")?.key, .character("+"))
        XCTAssertNil(KeyShortcut("⌘"))
        XCTAssertThrowsError(try MenuSpec.parse("a | | A | А\n   b | | B | Б"))
    }
}

final class SessionTests: XCTestCase {
    func testUndoRedoWithNames() throws {
        let (s, ids) = sampleSession()
        s.setOpacity(ids[2], 0.5)
        s.setOpacity(ids[2], 0.3)
        s.endCoalescing()
        XCTAssertEqual(s.document.layer(ids[2])?.opacity, 0.3)
        XCTAssertEqual(s.dynamicTitle("edit.undo"), "Отменить «Непрозрачность»")
        try s.run("edit.undo", title: "Undo")
        XCTAssertEqual(s.document.layer(ids[2])?.opacity, 1, "перетаскивание ползунка — один шаг")
        try s.run("edit.redo", title: "Redo")
        XCTAssertEqual(s.document.layer(ids[2])?.opacity, 0.3)
    }

    func testStackingDuplicateDelete() throws {
        let (s, ids) = sampleSession()
        s.select([ids[1]])
        try s.run("arrange.front", title: "Front")
        XCTAssertEqual(s.document.layers.map(\.name), ["bg", "blue", "red"])
        try s.run("arrange.back", title: "Back")
        XCTAssertEqual(s.document.layers.map(\.name), ["red", "bg", "blue"])
        XCTAssertFalse(s.canPerform("arrange.backward"))
        try s.run("edit.duplicate", title: "Duplicate")
        XCTAssertEqual(s.document.layers.map(\.name), ["red", "red копия", "bg", "blue"])
        XCTAssertNotEqual(s.document.layers[1].id, ids[1])
        try s.run("edit.delete", title: "Delete")
        XCTAssertEqual(s.document.layers.map(\.name), ["red", "bg", "blue"])
        XCTAssertEqual(s.primary, ids[1], "после удаления выбран слой ниже")
    }

    func testGroupUngroupAndMoveIntoGroup() throws {
        let (s, ids) = sampleSession()
        s.select([ids[1], ids[2]])
        try s.run("arrange.group", title: "Group")
        XCTAssertEqual(s.document.layers.count, 2)
        let g = s.document.layers[1]
        XCTAssertEqual(g.children.map(\.name), ["red", "blue"])
        XCTAssertEqual(g.blendMode, .passThrough)
        // Сдвиг группы двигает детей.
        s.moveSelection(dx: 3, dy: -2)
        s.endCoalescing()
        XCTAssertEqual(s.document.layer(ids[1])?.position, PixelPoint(x: 13, y: 3))
        // Перенос фона внутрь группы, наверх.
        s.moveLayer(ids[0], toParent: g.id, index: 2)
        XCTAssertEqual(s.document.layers.count, 1)
        XCTAssertEqual(s.document.layers[0].children.map(\.name), ["red", "blue", "bg"])
        s.select([g.id])
        try s.run("arrange.ungroup", title: "Ungroup")
        XCTAssertEqual(s.document.layers.map(\.name), ["red", "blue", "bg"])
        // Группу нельзя положить в саму себя.
        s.select([ids[0], ids[1]])
        try s.run("arrange.group", title: "Group")
        let g2 = s.primary!
        s.moveLayer(g2, toParent: g2, index: 0)
        XCTAssertEqual(s.document.layer(g2)?.children.count, 2)
    }

    func testMergeMatchesRender() throws {
        let (s, ids) = sampleSession()
        try s.run("edit.undo", title: "") // ничего не делает
        let before = try CPURenderer.render(s.document)
        s.select([ids[2]])
        try s.run("arrange.merge", title: "Merge")
        XCTAssertEqual(s.document.layers.map(\.name), ["bg", "blue"])
        let after = try CPURenderer.render(s.document)
        XCTAssertEqual(before.image, after.image)
        try s.run("arrange.mergeAll", title: "Merge All")
        XCTAssertEqual(s.document.layers.count, 1)
        XCTAssertEqual(try CPURenderer.render(s.document).image, before.image)
    }

    func testRotateImageKeepsPixels() throws {
        let (s, _) = sampleSession()
        let before = try CPURenderer.render(s.document).image
        try s.run("image.rotateRight", title: "R")
        XCTAssertEqual(s.document.width, 80)
        XCTAssertEqual(s.document.height, 100)
        let rotated = try CPURenderer.render(s.document).image
        // Пиксель (x, y) исходника — в (H − 1 − y, x) после поворота по часовой.
        for (x, y) in [(15, 7), (55, 35), (0, 0), (99, 79)] {
            for c in 0..<4 { XCTAssertEqual(rotated[80 - 1 - y, x, c], before[x, y, c]) }
        }
        try s.run("image.rotateLeft", title: "L")
        XCTAssertEqual(try CPURenderer.render(s.document).image, before)
        try s.run("image.flipH", title: "H")
        try s.run("image.flipH", title: "H")
        try s.run("image.rotate180", title: "180")
        try s.run("image.flipV", title: "V")
        try s.run("image.flipH", title: "H")
        XCTAssertEqual(try CPURenderer.render(s.document).image, before)
    }

    func testRotateLayerAroundCenterAndAlign() throws {
        let (s, ids) = sampleSession()
        s.select([ids[1]])
        try s.run("arrange.rotateRight", title: "R")
        // 20×10 в (10,5) → 10×20 с тем же центром (20, 10).
        XCTAssertEqual(s.document.layer(ids[1])?.bounds, PixelRect(x: 15, y: 0, width: 10, height: 20))
        try s.run("align.right", title: "Right")
        XCTAssertEqual(s.document.layer(ids[1])?.bounds?.maxX, 100, "один слой выравнивается по холсту")
        s.select([ids[1], ids[2]])
        try s.run("align.top", title: "Top")
        XCTAssertEqual(s.document.layer(ids[2])?.bounds?.y, 0)
    }

    func testSetPositionAndTopLevelAncestor() throws {
        let (s, ids) = sampleSession()
        s.setPosition(ids[1], x: 0, y: 70)
        XCTAssertEqual(s.document.layer(ids[1])?.position, PixelPoint(x: 0, y: 70))
        s.select([ids[1], ids[2]])
        try s.run("arrange.group", title: "Group")
        XCTAssertEqual(s.document.topLevelAncestor(of: ids[2]), s.primary)
    }

    func testMasksAndToggles() throws {
        let (s, ids) = sampleSession()
        s.select([ids[2]])
        XCTAssertFalse(s.canPerform("mask.remove"))
        try s.run("mask.hideAll", title: "Hide All")
        XCTAssertEqual(try CPURenderer.render(s.document).image[55, 35, 2], 1, "под скрытым синим — белый фон")
        XCTAssertEqual(try CPURenderer.render(s.document).image[55, 35, 0], 1)
        try s.run("mask.disable", title: "Disable")
        XCTAssertEqual(try CPURenderer.render(s.document).image[55, 35, 0], 0)
        try s.run("mask.clipping", title: "Clip")
        XCTAssertEqual(s.dynamicTitle("mask.clipping"), "Отменить обтравочную маску")
        try s.run("format.preserveTransparency", title: "PT")
        XCTAssertTrue(s.isChecked("format.preserveTransparency"))
        try s.run("arrange.lock", title: "Lock")
        s.moveSelection(dx: 5, dy: 5)
        XCTAssertEqual(s.document.layer(ids[2])?.position, PixelPoint(x: 50, y: 30), "заблокированный слой не двигается")
        XCTAssertFalse(s.canPerform("arrange.lock"))
        XCTAssertTrue(s.canPerform("arrange.unlock"))
    }
}

final class ViewportTests: XCTestCase {
    func testFitZoomAndMapping() {
        var v = Viewport(documentWidth: 4000, documentHeight: 3000, viewWidth: 2000, viewHeight: 1000)
        XCTAssertEqual(v.scale, 1000.0 / 3000 * Viewport.fitMargin, accuracy: 1e-9)
        XCTAssertEqual(v.renderLevel, 1)
        v.actualSize()
        XCTAssertEqual(v.renderLevel, 0)
        // Точка под курсором остаётся под курсором при масштабе.
        let p = v.documentPoint(viewX: 300, viewY: 200)
        v.zoomIn(aroundViewX: 300, viewY: 200)
        XCTAssertEqual(v.scale, 1.5)
        let q = v.documentPoint(viewX: 300, viewY: 200)
        XCTAssertEqual(p.x, q.x, accuracy: 1e-9)
        XCTAssertEqual(p.y, q.y, accuracy: 1e-9)
        v.zoomOut()
        v.zoomOut()
        XCTAssertEqual(v.scale, 2.0 / 3, accuracy: 1e-9)
    }

    func testFitFollowsWindowUntilManualZoom() {
        // Окно создаётся раньше, чем получает размер: вписывание должно пересчитаться.
        var v = Viewport(documentWidth: 1920, documentHeight: 1080, viewWidth: 1, viewHeight: 1)
        v.resize(viewWidth: 2000, viewHeight: 1500)
        XCTAssertEqual(v.scale, 1, accuracy: 1e-9, "при открытии не больше 100 %")
        v.resize(viewWidth: 1000, viewHeight: 800)
        XCTAssertEqual(v.scale, 1000.0 / 1920 * Viewport.fitMargin, accuracy: 1e-9)
        v.zoomIn()
        let s = v.scale
        v.resize(viewWidth: 1000, viewHeight: 800)
        XCTAssertEqual(v.scale, s, "после ручного масштаба размер окна масштаб не меняет")
        v.zoomToFit()
        v.resize(viewWidth: 1000, viewHeight: 800)
        XCTAssertEqual(v.scale, 1000.0 / 1920 * Viewport.fitMargin, accuracy: 1e-9)
    }

    func testFitBetweenPanels() {
        var v = Viewport(documentWidth: 2000, documentHeight: 1000, viewWidth: 2600, viewHeight: 1300)
        v.setInsets(ViewInsets(left: 300, right: 300))
        XCTAssertEqual(v.scale, 1, accuracy: 1e-9)
        let r = v.documentRectInView
        XCTAssertEqual(r.x, 300, accuracy: 1e-9, "документ начинается у края левой панели")
        XCTAssertEqual(r.x + r.width, 2300, accuracy: 1e-9)
    }

    func testVisibleRegionOnLevelGrid() throws {
        var v = Viewport(documentWidth: 4000, documentHeight: 3000, viewWidth: 1000, viewHeight: 800)
        v.setScale(0.3)
        XCTAssertEqual(v.renderLevel, 1)
        let vis = try XCTUnwrap(v.visibleRegion)
        XCTAssertEqual(vis.region.level, 1)
        XCTAssertEqual(vis.documentRect.width, vis.region.width * 2)
        XCTAssertEqual(vis.documentRect.x, vis.region.x * 2)
        // Масштаб 100 %: видна середина документа размером с окно.
        v.actualSize()
        let mid = try XCTUnwrap(v.visibleRegion)
        XCTAssertEqual(mid.region, RenderRegion(x: 1500, y: 1100, width: 1000, height: 800, level: 0))
        // Сдвиг за край ограничивается: центр не уходит за документ.
        v.pan(dx: 1e7, dy: 0)
        XCTAssertEqual(v.centerX, 0)
    }
}
