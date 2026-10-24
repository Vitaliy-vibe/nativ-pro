#if canImport(AppKit)
import AppKit
import EditorApp
import EditorCore

/// Элемент дерева для NSOutlineView. Один объект на слой на всё время жизни панели —
/// иначе после перезагрузки списка терялись бы раскрытые группы.
final class LayerItem: NSObject {
    let id: LayerID
    init(_ id: LayerID) { self.id = id }
}

/// Панель «Слои» слева (как у образца): заголовок с «+», маской и «…», режим наложения и непрозрачность
/// выбранного слоя, список с миниатюрами, поиск внизу. Порядок и вложенность — перетаскиванием.
final class LayersPanel: FloatingPanel, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate {
    weak var controller: EditorWindowController?
    private let outline = NSOutlineView()
    private let blendPopup = NSPopUpButton()
    private var opacitySlider: NSSlider!
    private let opacityValue = NSTextField()
    private let search = NSSearchField()
    private var items: [LayerID: LayerItem] = [:]
    private var thumbnails: [LayerID: (key: String, image: NSImage)] = [:]
    private var syncing = false
    private static let dragType = NSPasteboard.PasteboardType("ru.ect.photoeditor.layer")

    private var session: EditorSession? { controller?.session }

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    /// Поставить элемент в точку (x, y) панели (от верха или от низа); w/h — размер, если задан.
    private func put(_ v: NSView, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat? = nil, _ h: CGFloat? = nil, fromBottom: Bool = false) {
        v.place(in: self, x: x, y: y, w: w, h: h, fromBottom: fromBottom)
    }

    /// Раскладка — по координатам панели слоёв образца (270 × 904, снято через Accessibility 19.10).
    private func build() {
        let t = AppInfo.tr
        let title = NSTextField(labelWithString: t("Layers", "Слои"))
        // Шрифты по замерам 19.10: заголовок 14 жирный (рамка 19), «Непрозрачность» 12 (17), размер слоя 10 (15).
        title.font = .systemFont(ofSize: 14, weight: .bold)
        put(title, 11, 16)
        let add = Theme.iconButton("plus", t("Insert a layer.", "Ввести слой."), size: 15, target: self, action: #selector(addLayerMenu(_:)))
        let mask = Theme.iconButton("square.dashed.inset.filled", t("Add a mask to the selected layer.", "Добавить маску к выбранному слою."), size: 14, target: self, action: #selector(addMaskMenu(_:)))
        mask.image = LayersPanel.maskIcon(t("Add a mask to the selected layer.", "Добавить маску к выбранному слою."))
        let more = Theme.iconButton("ellipsis", t("Change the layers sidebar view.", "Изменить вид бокового меню слоев."), size: 15, target: self, action: #selector(showMore(_:)))
        put(add, 189, 17, 18, 20)
        put(mask, 216, 17, 18, 20)
        put(more, 243, 17, 18, 20)
        // Разделители — по строкам пикселей на снимке образца: под заголовком 41, под непрозрачностью 94,
        // над поиском 850 (от низа 52); вертикальная черта между режимом наложения и непрозрачностью x 104, y 56…79.
        put(Theme.separator(), 12, 41, 247, 1)
        put(Theme.separator(), 103, 55, 3, 26)

        blendPopup.target = self
        blendPopup.action = #selector(blendChanged(_:))
        blendPopup.toolTip = t("Choose how the object blends with other objects.", "Выбрать, как объект смешивается с другими объектами в изображении.")
        for (n, group) in BlendMode.menuGroups.enumerated() {
            if n > 0 { blendPopup.menu?.addItem(.separator()) }
            for mode in group {
                let item = NSMenuItem(title: mode.title(russian: AppInfo.russian), action: nil, keyEquivalent: "")
                item.representedObject = mode.rawValue
                blendPopup.menu?.addItem(item)
            }
        }
        put(blendPopup, 11, 55, 87, 26)

        let opacityTitle = NSTextField(labelWithString: t("Opacity", "Непрозрачность"))
        opacityTitle.font = .systemFont(ofSize: 12)
        put(opacityTitle, 111, 52)
        opacityValue.isBezeled = false
        opacityValue.drawsBackground = false
        opacityValue.isEditable = true
        opacityValue.alignment = .right
        opacityValue.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        opacityValue.toolTip = t("Set the opacity of the object.", "Задать прозрачность объекта.")
        opacityValue.target = self
        opacityValue.action = #selector(opacityTyped(_:))
        put(opacityValue, 212, 49, 48, 24)
        opacitySlider = Theme.slider(target: self, action: #selector(opacityChanged(_:)))
        // Ручка у образца 16 × 12 — малый размер ползунка.
        opacitySlider.controlSize = .small
        opacitySlider.toolTip = t("Adjust the opacity of the object.", "Настроить прозрачность объекта.")
        put(opacitySlider, 110, 66, 150, 20)
        put(Theme.separator(), 12, 94, 247, 1)

        let column = NSTableColumn(identifier: .init("layer"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.rowHeight = 47
        outline.intercellSpacing = NSSize(width: 0, height: 0)
        outline.allowsMultipleSelection = true
        outline.style = .fullWidth
        outline.backgroundColor = .clear
        outline.selectionHighlightStyle = .regular
        outline.indentationPerLevel = 16
        outline.dataSource = self
        outline.delegate = self
        // Имя слоя у образца — простой текст; переименование — двойным щелчком.
        outline.target = self
        outline.doubleAction = #selector(beginRename(_:))
        outline.registerForDraggedTypes([LayersPanel.dragType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 109),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -68),
        ])
        put(Theme.separator(), 12, 52, 247, 1, fromBottom: true)

        search.placeholderString = t("Search", "Поиск")
        search.toolTip = t("Enter a layer name.", "Ввести имя слоя.")
        search.controlSize = .large
        search.delegate = self
        search.sendsSearchStringImmediately = true
        put(search, 12, 12, 213, 30, fromBottom: true)
        // У образца — переключатель «фильтровать» на круглой подложке 81/255 (снимок 19.10); фильтр слоёв — позже,
        // пока нажатие даёт звуковой сигнал.
        let filter = Theme.iconButton("line.3.horizontal.decrease", t("Filter the layers list.", "Фильтр списка слоев."), size: 14, target: self, action: #selector(filterPressed(_:)))
        filter.setButtonType(.pushOnPushOff)
        filter.setAccessibilityLabel(t("filter", "фильтровать"))
        filter.wantsLayer = true
        filter.layer?.cornerRadius = 14
        filter.layer?.backgroundColor = NSColor(white: 1, alpha: 0.13).cgColor
        put(filter, 230, 12, 30, 30, fromBottom: true)
    }

    // MARK: обновление из модели

    func reload() {
        guard let session else { return }
        let alive = Set(session.document.flattenedTopDown().map { $0.layer.id })
        items = items.filter { alive.contains($0.key) }
        thumbnails = thumbnails.filter { alive.contains($0.key) }
        syncing = true
        outline.reloadData()
        syncing = false
        syncSelection()
    }

    /// Выделить в списке выбранные слои (без перезагрузки строк).
    func syncSelection() {
        guard let session else { return }
        syncing = true
        defer { syncing = false }
        var rows = IndexSet()
        for id in session.selection {
            if let path = session.document.path(of: id) {
                var list = session.document.layers
                for i in path.dropLast() {
                    outline.expandItem(item(list[i].id))
                    list = list[i].children
                }
            }
            let row = outline.row(forItem: item(id))
            if row >= 0 { rows.insert(row) }
        }
        outline.selectRowIndexes(rows, byExtendingSelection: false)
        updateControls()
    }

    private func updateControls() {
        let layer = session?.primaryLayer
        blendPopup.isEnabled = layer != nil
        opacitySlider.isEnabled = layer != nil
        guard let layer else { return }
        if let item = blendPopup.menu?.items.first(where: { ($0.representedObject as? String) == layer.blendMode.rawValue }) {
            blendPopup.select(item)
        }
        opacitySlider.doubleValue = Double(layer.opacity * 100)
        opacityValue.stringValue = "\(Int((layer.opacity * 100).rounded())) %"
    }

    private func item(_ id: LayerID) -> LayerItem {
        if let it = items[id] { return it }
        let it = LayerItem(id)
        items[id] = it
        return it
    }

    /// Совпадает ли слой (или кто-то из его детей) с поиском.
    private func matches(_ layer: Layer, _ query: String) -> Bool {
        layer.name.localizedCaseInsensitiveContains(query) || layer.children.contains { matches($0, query) }
    }

    /// Дети в порядке панели (сверху вниз), с учётом поиска.
    private func children(of item: Any?) -> [Layer] {
        guard let session else { return [] }
        let list: [Layer]
        if let it = item as? LayerItem {
            list = session.document.layer(it.id)?.children ?? []
        } else {
            list = session.document.layers
        }
        let query = search.stringValue.trimmingCharacters(in: .whitespaces)
        return list.reversed().filter { query.isEmpty || matches($0, query) }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === search else { return }
        reload()
    }

    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { children(of: item).count }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { self.item(children(of: item)[index].id) }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let it = item as? LayerItem else { return false }
        return session?.document.layer(it.id)?.isGroup == true
    }

    // MARK: строка слоя: миниатюра, имя, размер, видимость

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { LayerRowView() }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let it = item as? LayerItem, let layer = session?.document.layer(it.id) else { return nil }
        let cell = NSTableCellView()
        func put(_ v: NSView, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat? = nil, _ h: CGFloat? = nil) {
            v.place(in: cell, x: x, y: y, w: w, h: h)
        }
        // Миниатюра, имя (жирным) и размер под ним, справа — галочка видимости (как в строке образца).
        let thumb = NSImageView(image: thumbnail(layer))
        thumb.imageScaling = .scaleProportionallyUpOrDown
        // Замер 19.10: миниатюра 36 × 36 с тонкой светлой рамкой, имя — с x 60 (83 в окне), размер под ним.
        put(thumb, 15, 5, 36, 36)
        thumb.wantsLayer = true
        thumb.layer?.borderWidth = 1
        thumb.layer?.borderColor = NSColor(white: 1, alpha: 0.25).cgColor
        let name = NSTextField(labelWithString: layer.name)
        name.font = .systemFont(ofSize: 12, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        name.target = self
        name.action = #selector(renamed(_:))
        name.toolTip = layer.name
        put(name, 60, 7, nil, 17)
        var detail: [String] = []
        if let b = layer.bounds { detail.append("\(b.width) × \(b.height) px") }
        if !layer.masks.isEmpty { detail.append(AppInfo.tr("mask", "маска")) }
        if layer.isClippingMask { detail.append(AppInfo.tr("clipped", "обтравка")) }
        if layer.blendMode != .normal && layer.blendMode != .passThrough { detail.append(layer.blendMode.title(russian: AppInfo.russian)) }
        if layer.opacity < 1 { detail.append("\(Int((layer.opacity * 100).rounded())) %") }
        if layer.isLocked { detail.append("🔒") }
        let sub = NSTextField(labelWithString: detail.joined(separator: " · "))
        sub.font = .systemFont(ofSize: 10)
        // У образца размер слоя тусклее вторичного цвета: 124/255 на выделенной строке 71 — третичный.
        sub.textColor = .tertiaryLabelColor
        sub.lineBreakMode = .byTruncatingTail
        put(sub, 60, 23, nil, 15)
        let eye = Theme.checkbox("", target: self, action: #selector(visibilityChanged(_:)))
        eye.state = layer.isVisible ? .on : .off
        eye.toolTip = AppInfo.tr("Hide the layer to make it invisible.", "Скрыть слой, чтобы он стал невидим.")
        eye.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(eye)
        NSLayoutConstraint.activate([
            eye.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5),
            eye.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            eye.widthAnchor.constraint(equalToConstant: 20), eye.heightAnchor.constraint(equalToConstant: 20),
            // Имя у образца растянуто до галочки (160 точек, правый край за 3 точки до неё).
            name.trailingAnchor.constraint(equalTo: eye.leadingAnchor, constant: -5),
            sub.trailingAnchor.constraint(lessThanOrEqualTo: eye.leadingAnchor, constant: -4),
        ])
        cell.textField = name
        cell.alphaValue = layer.isVisible ? 1 : 0.5
        return cell
    }

    /// Миниатюра слоя: он один, в уменьшенной копии (уровень — чтобы длинная сторона была ≤ 80 точек).
    func layerThumbnail(_ layer: Layer) -> NSImage { thumbnail(layer) }

    private func thumbnail(_ layer: Layer) -> NSImage {
        guard let session, let b = layer.bounds?.intersection(session.document.bounds), !b.isEmpty else {
            return NSImage(systemSymbolName: layer.isGroup ? "folder" : "questionmark.square.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        // Пересчитывать, только если слой изменился: ключ — положение, свойства и сами плитки.
        let key = thumbnailKey(layer)
        if let cached = thumbnails[layer.id], cached.key == key { return cached.image }
        var level = 0
        while level < 8 && max(b.width, b.height) >> level > 80 { level += 1 }
        var scratch = Document(width: session.document.width, height: session.document.height, depth: session.document.depth)
        var single = layer
        single.isVisible = true
        single.opacity = 1
        single.isClippingMask = false
        scratch.layers = [single]
        let f = 1 << level
        let x0 = b.x / f, y0 = b.y / f
        let region = RenderRegion(x: x0, y: y0, width: max(1, (b.maxX + f - 1) / f - x0), height: max(1, (b.maxY + f - 1) / f - y0), level: level)
        guard let result = try? CPURenderer.render(scratch, region: region), let cg = ImageFiles.cgImage(result.image) else { return NSImage() }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        thumbnails[layer.id] = (key, image)
        return image
    }

    private func thumbnailKey(_ layer: Layer) -> String {
        var parts = ["\(layer.position.x),\(layer.position.y)"]
        func walk(_ l: Layer) {
            switch l.content {
            case .bitmap(let b): parts.append(b.tiles.map { $0.map { "\(ObjectIdentifier($0).hashValue)" } ?? "-" }.joined(separator: ","))
            case .group(let c): c.forEach(walk)
            case .unsupported: break
            }
            parts.append("\(l.isVisible)\(l.opacity)\(l.blendMode.rawValue)\(l.masks.count)\(l.position.x),\(l.position.y)")
        }
        walk(layer)
        return parts.joined(separator: "|")
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !syncing, let session else { return }
        var ids = outline.selectedRowIndexes.compactMap { (outline.item(atRow: $0) as? LayerItem)?.id }
        // Основной выбранный слой — тот, по которому щёлкнули последним.
        if outline.selectedRow >= 0, let last = (outline.item(atRow: outline.selectedRow) as? LayerItem)?.id, let i = ids.firstIndex(of: last) {
            ids.append(ids.remove(at: i))
        }
        session.select(ids)
        updateControls()
    }

    // MARK: перетаскивание

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let it = item as? LayerItem else { return nil }
        let pb = NSPasteboardItem()
        pb.setString(it.id.uuid.uuidString, forType: LayersPanel.dragType)
        return pb
    }

    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard let dragged = draggedID(info), let session else { return [] }
        if let target = item as? LayerItem {
            guard session.document.layer(target.id)?.isGroup == true,
                  let from = session.document.path(of: dragged), let to = session.document.path(of: target.id), !to.starts(with: from)
            else { return [] }
        }
        return .move
    }

    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let dragged = draggedID(info), let session else { return false }
        let parent = (item as? LayerItem)?.id
        let count = parent.flatMap { session.document.layer($0)?.children.count } ?? session.document.layers.count
        // В панели индекс 0 — верх, в модели — низ; «на группу» (-1) — наверх группы.
        let storageIndex = index < 0 ? count : count - index
        session.moveLayer(dragged, toParent: parent, index: storageIndex)
        return true
    }

    private func draggedID(_ info: NSDraggingInfo) -> LayerID? {
        guard let s = info.draggingPasteboard.string(forType: LayersPanel.dragType), let uuid = UUID(uuidString: s) else { return nil }
        return LayerID(uuid)
    }

    // MARK: действия

    private func layerID(for view: NSView) -> LayerID? {
        let row = outline.row(for: view)
        return row >= 0 ? (outline.item(atRow: row) as? LayerItem)?.id : nil
    }

    /// «+»: какой слой вставить (как меню «Ввести слой» у образца).
    @objc private func addLayerMenu(_ sender: NSButton) {
        popUp(["insert.emptyLayer", "insert.choose", "-", "insert.text", "insert.shape", "-", "insert.adjustments", "insert.effects"], from: sender)
    }

    /// Значок маски: какую маску добавить.
    @objc private func addMaskMenu(_ sender: NSButton) {
        popUp(["mask.revealAll", "mask.hideAll", "mask.fromSelection", "-", "mask.remove", "mask.clipping"], from: sender)
    }

    private func popUp(_ ids: [String], from sender: NSView) {
        let menu = NSMenu()
        for id in ids {
            if id == "-" {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: EditorWindowController.titles[id] ?? id, action: #selector(EditorCommandTarget.performEditorCommand(_:)), keyEquivalent: "")
            item.representedObject = id
            item.target = controller
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func opacityTyped(_ sender: NSTextField) {
        guard let id = session?.primary, let v = Double(sender.stringValue.filter { $0.isNumber || $0 == "." || $0 == "," }.replacingOccurrences(of: ",", with: ".")) else {
            updateControls()
            return
        }
        session?.setOpacity(id, Float(min(max(v, 0), 100) / 100))
        session?.endCoalescing()
    }

    /// Меню «…»: команды над выбранными слоями.
    @objc private func showMore(_ sender: NSButton) {
        let menu = NSMenu()
        for id in ["edit.duplicate", "edit.delete", "-", "arrange.group", "arrange.ungroup", "arrange.merge", "arrange.mergeAll", "-",
                   "mask.revealAll", "mask.hideAll", "mask.remove", "mask.clipping", "-", "arrange.lock", "arrange.unlock"] {
            if id == "-" {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: EditorWindowController.titles[id] ?? id, action: #selector(EditorCommandTarget.performEditorCommand(_:)), keyEquivalent: "")
            item.representedObject = id
            item.target = controller
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func visibilityChanged(_ sender: NSButton) {
        guard let id = layerID(for: sender) else { return }
        session?.setVisible(id, sender.state == .on)
    }

    /// Значок маски как у образца (снимок сверки 14 по пикселям): залитый скруглённый квадрат 12,5 с круглым
    /// вырезом диаметром 8 по центру.
    static func maskIcon(_ description: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: true) { _ in
            let square = NSRect(x: 0.75, y: 0.75, width: 12.5, height: 12.5)
            let path = NSBezierPath(roundedRect: square, xRadius: 2.5, yRadius: 2.5)
            path.appendOval(in: square.insetBy(dx: 2.25, dy: 2.25))
            path.windingRule = .evenOdd
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }

    @objc private func filterPressed(_ sender: NSButton) {
        sender.state = .off
        NSSound.beep()
    }

    @objc private func beginRename(_ sender: Any?) {
        let row = outline.clickedRow
        guard row >= 0, let cell = outline.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
              let field = cell.textField else { return }
        field.isEditable = true
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    @objc private func renamed(_ sender: NSTextField) {
        sender.isEditable = false
        guard let id = layerID(for: sender) else { return }
        session?.rename(id, sender.stringValue)
    }

    @objc private func blendChanged(_ sender: NSPopUpButton) {
        guard let id = session?.primary, let raw = sender.selectedItem?.representedObject as? String, let mode = BlendMode(rawValue: raw) else { return }
        session?.setBlendMode(id, mode)
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        guard let id = session?.primary else { return }
        opacityValue.stringValue = "\(Int(sender.doubleValue.rounded())) %"
        session?.setOpacity(id, Float(sender.doubleValue / 100))
        // Отпустили ползунок — следующее движение станет новым шагом истории.
        if NSApp.currentEvent?.type == .leftMouseUp { session?.endCoalescing() }
    }
}

/// Строка списка слоёв: выделение — серая скруглённая подложка (71/255, радиус 10, отступ 7 слева и справа,
/// высота 46 из 47 — снимок 19.10), текст при выделении не перекрашивается в белый, как у образца.
final class LayerRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { false }
        set {}
    }

    override func drawSelection(in dirtyRect: NSRect) {
        let r = NSRect(x: 7, y: 0, width: bounds.width - 14, height: bounds.height - 1)
        NSColor(srgbRed: 71 / 255, green: 71 / 255, blue: 71 / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: r, xRadius: 10, yRadius: 10).fill()
    }
}
#endif
