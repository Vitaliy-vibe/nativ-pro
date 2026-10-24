#if canImport(AppKit)
import AppKit
import EditorApp
import EditorCore
import UniformTypeIdentifiers

/// Корневой вид окна. Стоит в цепочке ответчиков раньше окна, поэтому стандартные действия меню
/// (undo:, copy:, delete: …) при фокусе на холсте или списке слоёв попадают в редактор,
/// а при вводе имени слоя — сначала в поле ввода.
final class EditorRootView: NSView, NSMenuItemValidation, EditorCommandTarget {
    weak var controller: EditorWindowController?

    @objc func performEditorCommand(_ sender: Any?) { controller?.performEditorCommand(sender) }
    @objc func undo(_ sender: Any?) { controller?.run("edit.undo") }
    @objc func redo(_ sender: Any?) { controller?.run("edit.redo") }
    @objc func cut(_ sender: Any?) { controller?.run("edit.cut") }
    @objc func copy(_ sender: Any?) { controller?.run("edit.copy") }
    @objc func paste(_ sender: Any?) { controller?.run("edit.paste") }
    @objc func delete(_ sender: Any?) { controller?.run("edit.delete") }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { controller?.validateMenuItem(menuItem) ?? false }
}

/// Окно документа в раскладке «Стандартная» образца: холст во всё окно, поверх него парящие панели —
/// слева «Слои», справа настройки инструмента и полоса инструментов; в заголовке — кнопка панели слоёв и масштаб.
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, EditorCommandTarget, NSToolbarDelegate {
    let root = EditorRootView()
    let canvas = CanvasView()
    let layersPanel = LayersPanel()
    let arrangePanel = ArrangePanel()
    let toolStrip = ToolStrip()
    /// Панели остальных инструментов полосы — создаются при первом выборе, стоят на месте «Расстановки».
    private var toolPanels: [String: ToolPanel] = [:]
    /// Выбранный инструмент полосы (у холста свой — CanvasTool; для ещё не сделанных инструментов он .inactive).
    private(set) var selectedTool = "tool.arrange"
    let infoBar = NSTextField(labelWithString: "")
    private let infoPanel = FloatingPanel()
    let colorWell = SwatchColorWell()
    /// Основной цвет (кисть и заливка появятся на этапе 5); по умолчанию чёрный, как у образца (замер 24.10: rgb 0 0 0 1).
    var foregroundColor = NSColor.black
    private let zoomSlider = SmallKnobSlider(value: 0, minValue: log2(Viewport.minScale), maxValue: log2(Viewport.maxScale), target: nil, action: nil)

    /// Названия пунктов меню по идентификатору — для шагов истории и восстановления названий.
    static let titles: [String: String] = Dictionary(uniqueKeysWithValues: MenuSpec.flatten(MenuSpec.main()).map {
        ($0.id, $0.title(russian: AppInfo.russian, appName: AppInfo.name))
    })

    /// Команды, которые выполняет окно (остальные — EditorSession.documentCommands).
    static let windowCommands: Set<String> = [
        "view.zoomIn", "view.zoomOut", "view.zoomFit", "view.actualSize",
        "view.hideLayers", "view.hideTools", "view.infoBar",
        "tool.arrange", "tool.hand", "tool.zoom",
        "edit.copy", "edit.copyMerged", "edit.cut", "edit.paste",
        "file.export", "file.import", "insert.choose",
    ]

    var editorDocument: EditorDocument? { document as? EditorDocument }
    /// Сессия документа; окно получает её, когда NSDocument подключает контроллер.
    var session: EditorSession { editorDocument!.session }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1600, height: 1000),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 900, height: 600)
        window.tabbingMode = .preferred
        // Без восстановления окон прошлого запуска: иначе после перезапуска (run_app.sh) снова открывались старые
        // вкладки и сверка с образцом съезжала на высоту строки вкладок (20.10).
        window.isRestorable = false
        // Сверка 9: у образца полоса заголовка цвета холста (30/255), у нас была светлее с синевой (стекло заголовка).
        window.titlebarAppearsTransparent = true
        // Как образца: тёмное окно независимо от системной темы.
        window.appearance = NSAppearance(named: .darkAqua)
        super.init(window: window)
        window.delegate = self
        buildLayout()
        let toolbar = NSToolbar(identifier: "EditorToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.center()
        windowFrameAutosaveName = "EditorWindow"
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    // MARK: раскладка

    private func buildLayout() {
        guard let window else { return }
        root.controller = self
        layersPanel.translatesAutoresizingMaskIntoConstraints = false
        arrangePanel.translatesAutoresizingMaskIntoConstraints = false
        toolStrip.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        infoPanel.translatesAutoresizingMaskIntoConstraints = false

        infoBar.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        infoBar.lineBreakMode = .byTruncatingTail
        infoPanel.embed(infoBar, inset: 6)
        // Строка сведений у образца по умолчанию скрыта (Вид → Показать строку сведений).
        infoPanel.isHidden = true

        // Холст под панелями: панели парят поверх него.
        for v in [canvas, layersPanel, arrangePanel, toolStrip, infoPanel] as [NSView] { root.addSubview(v) }
        // Содержимое — под заголовком и вкладками (как у образца): панели начинаются ровно у contentLayoutGuide
        // окна (в macOS 26 он уже на 8 точек ниже вкладок — замер 19.10: панели образца с y = 88 при вкладках 52…80).
        window.contentView = root
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.canvasBackground.cgColor
        let top = (window.contentLayoutGuide as! NSLayoutGuide).topAnchor
        let g = Theme.gap
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: top),
            canvas.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            layersPanel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: g),
            layersPanel.topAnchor.constraint(equalTo: top, constant: 0),
            layersPanel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -g),
            layersPanel.widthAnchor.constraint(equalToConstant: Theme.layersWidth),

            // Как у образца: полоса инструментов — во всю высоту, как и панели.
            toolStrip.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -g),
            toolStrip.topAnchor.constraint(equalTo: top, constant: 0),
            toolStrip.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -g),
            toolStrip.widthAnchor.constraint(equalToConstant: Theme.stripWidth),

            arrangePanel.trailingAnchor.constraint(equalTo: toolStrip.leadingAnchor, constant: -g),
            arrangePanel.topAnchor.constraint(equalTo: top, constant: 0),
            arrangePanel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -g),
            arrangePanel.widthAnchor.constraint(equalToConstant: Theme.optionsWidth),

            infoPanel.leadingAnchor.constraint(equalTo: layersPanel.trailingAnchor, constant: g),
            infoPanel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -g),
            infoPanel.trailingAnchor.constraint(lessThanOrEqualTo: arrangePanel.leadingAnchor, constant: -g),
        ])
        window.initialFirstResponder = canvas
        updateInsets()
    }

    /// Свободная часть холста — между видимыми панелями; по ней считается «По размеру окна».
    private func updateInsets() {
        let g = Theme.gap
        let left = layersPanel.isHidden ? 0 : g + Theme.layersWidth
        let right = toolStrip.isHidden ? 0 : g + Theme.stripWidth + g + Theme.optionsWidth
        canvas.setInsets(left: left, right: right, top: 0)
    }

    /// Документ подключён (EditorDocument.makeWindowControllers): связать сессию с холстом, панелями и строкой сведений.
    func attach() {
        guard let doc = editorDocument else { return }
        canvas.controller = self
        layersPanel.controller = self
        arrangePanel.controller = self
        toolStrip.controller = self
        canvas.onViewportChange = { [weak self] in self?.viewportChanged() }
        doc.session.onChange = { [weak self, weak doc] change in
            guard let self else { return }
            doc?.noteChange(change)
            switch change {
            case .selection:
                self.layersPanel.syncSelection()
            case .reset:
                self.canvas.resetViewport(for: self.session.document)
                self.layersPanel.reload()
            case .edit, .undo, .redo:
                self.canvas.requestRender()
                self.layersPanel.reload()
            }
            self.arrangePanel.update()
            self.toolPanels[self.selectedTool]?.update()
            self.updateInfoBar()
        }
        canvas.resetViewport(for: doc.session.document)
        layersPanel.reload()
        arrangePanel.update()
        selectTool("tool.arrange")
        window?.makeFirstResponder(canvas)
        updateInfoBar()
        // Журнал раскладки окна для проверки на Mac без скриншотов (только на машине разработки — см. writeLayoutLog).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.writeLayoutLog() }
    }

    /// Рамки частей окна в координатах окна: видно, какая часть какого размера и что чем перекрыто.
    /// Пишется, только если папка ~/PE-reference уже есть (её создаёт скрипт сверки): у пользователей ничего не появляется.
    func writeLayoutLog() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("PE-reference")
        guard let window, FileManager.default.fileExists(atPath: dir.path) else { return }
        func frame(_ v: NSView) -> String {
            let r = v.convert(v.bounds, to: nil)
            return String(format: "x %.0f y %.0f w %.0f h %.0f%@%@", r.minX, r.minY, r.width, r.height,
                          v.isHidden ? " СКРЫТ" : "", v.window == nil ? " НЕ В ОКНЕ" : "")
        }
        var lines = ["== \(Date()) окно \(frame(root)) масштаб экрана \(window.backingScaleFactor) тема \(window.effectiveAppearance.name.rawValue)",
                     "холст: \(frame(canvas)) масштаб \(String(format: "%.3f", canvas.viewport.scale)) документ \(frame(canvas))",
                     "панель слоёв: \(frame(layersPanel))",
                     "панель «Расстановка»: \(frame(arrangePanel))",
                     "полоса инструментов: \(frame(toolStrip))",
                     "строка сведений: \(frame(infoPanel)) «\(infoBar.stringValue)»",
                     "неоднозначная раскладка: \(root.hasAmbiguousLayout)"]
        let menu = NSApp.mainMenu?.items.map(\.title).joined(separator: " | ") ?? "НЕТ"
        lines.append("главное меню: \(menu)")
        lines.append("программа активна: \(NSApp.isActive), окно главное: \(window.isMainWindow), во весь экран: \(window.styleMask.contains(.fullScreen))")
        lines.append("заголовок окна: \(window.toolbar?.items.map(\.itemIdentifier.rawValue).joined(separator: ", ") ?? "нет")")
        let docs = NSDocumentController.shared.documents.map { "\($0.displayName ?? "?")\($0.fileURL == nil ? " (без файла)" : "")\($0.isDocumentEdited ? " изменён" : "")" }
        // Иконка Nativ Pro: собрал ли run_app.sh каталог ресурсов с AppIcon (журнал сборки уходит раньше этого шага).
        let res = (try? FileManager.default.contentsOfDirectory(atPath: Bundle.main.resourcePath ?? "")) ?? []
        lines.append("ресурсы: \(res.sorted().joined(separator: ", ")); CFBundleIconName: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String ?? "нет")")
        lines.append("документы: \(docs.joined(separator: "; ")), вкладок в окне: \(window.tabbedWindows?.count ?? 1)")
        try? (lines.joined(separator: "\n") + "\n").write(to: dir.appendingPathComponent("app-run.log"), atomically: true, encoding: .utf8)
    }

    func windowDidResize(_ notification: Notification) { canvas.requestRender() }

    private func viewportChanged() {
        zoomSlider.doubleValue = log2(canvas.viewport.scale)
        toolPanels[selectedTool]?.viewportChanged()
        updateInfoBar()
    }

    private func updateInfoBar() {
        guard editorDocument != nil else { return }
        let doc = session.document
        var parts = [String(format: "%.1f %%", canvas.viewport.percent),
                     "\(doc.width) × \(doc.height) px",
                     doc.depth == .u16 ? AppInfo.tr("16-bit", "16 бит") : AppInfo.tr("8-bit", "8 бит")]
        if let p = canvas.cursorDocumentPoint { parts.append("x \(p.x)  y \(p.y)") }
        if let problem = canvas.renderProblem { parts.append("⚠︎ " + problem) }
        infoBar.stringValue = parts.joined(separator: "   ·   ")
    }

    // MARK: инструменты

    /// Выбрать инструмент: кнопка в полосе, панель справа (как у образца — у каждого своя), поведение холста.
    /// «Рука» — без своей панели, остаётся прежняя.
    func selectTool(_ id: String) {
        canvas.tool = CanvasTool(rawValue: id) ?? .inactive
        guard ToolStrip.toolIDs.contains(id) else { return }
        selectedTool = id
        toolStrip.update(selected: id)
        showOptionsPanel()
    }

    /// Панель текущего инструмента; остальные скрыты. Пока скрыта полоса — скрыта и панель.
    private func showOptionsPanel() {
        var panel: NSView = arrangePanel
        if selectedTool != "tool.arrange" {
            if toolPanels[selectedTool] == nil {
                let made = ToolPanel.make(selectedTool)
                made.controller = self
                made.translatesAutoresizingMaskIntoConstraints = false
                root.addSubview(made, positioned: .below, relativeTo: toolStrip)
                NSLayoutConstraint.activate([
                    made.leadingAnchor.constraint(equalTo: arrangePanel.leadingAnchor),
                    made.trailingAnchor.constraint(equalTo: arrangePanel.trailingAnchor),
                    made.topAnchor.constraint(equalTo: arrangePanel.topAnchor),
                    made.bottomAnchor.constraint(equalTo: arrangePanel.bottomAnchor),
                ])
                toolPanels[selectedTool] = made
            }
            panel = toolPanels[selectedTool]!
            toolPanels[selectedTool]?.update()
        }
        for v in [arrangePanel] + Array(toolPanels.values) as [NSView] { v.isHidden = toolStrip.isHidden || v !== panel }
    }

    // MARK: команды

    @objc func performEditorCommand(_ sender: Any?) {
        guard let id = (sender as? NSMenuItem)?.representedObject as? String else { return }
        run(id)
    }

    @objc func undo(_ sender: Any?) { run("edit.undo") }
    @objc func redo(_ sender: Any?) { run("edit.redo") }
    @objc func cut(_ sender: Any?) { run("edit.cut") }
    @objc func copy(_ sender: Any?) { run("edit.copy") }
    @objc func paste(_ sender: Any?) { run("edit.paste") }
    @objc func delete(_ sender: Any?) { run("edit.delete") }

    func canRun(_ id: String) -> Bool {
        guard editorDocument != nil else { return false }
        // Буквенные клавиши инструментов не должны срабатывать, пока вводится текст (имя слоя).
        if id.hasPrefix("tool."), window?.firstResponder is NSText { return false }
        switch id {
        case "view.zoomIn", "view.zoomOut", "view.zoomFit", "view.actualSize", "view.hideLayers", "view.hideTools", "view.infoBar",
             "tool.hand", "edit.copyMerged", "file.export", "file.import", "insert.choose":
            return true
        case _ where ToolStrip.toolIDs.contains(id):
            return true
        case "edit.copy": return session.primaryLayer?.bounds != nil
        case "edit.cut": return session.primaryLayer?.bounds != nil && session.canPerform("edit.delete")
        case "edit.paste": return PasteboardImage.hasImage()
        default: return EditorSession.documentCommands.contains(id) && session.canPerform(id)
        }
    }

    func run(_ id: String) {
        guard canRun(id) else { NSSound.beep(); return }
        let title = EditorWindowController.titles[id] ?? id
        switch id {
        case "view.zoomIn": canvas.zoomIn()
        case "view.zoomOut": canvas.zoomOut()
        case "view.zoomFit": canvas.zoomToFit()
        case "view.actualSize": canvas.actualSize()
        case "view.hideLayers":
            layersPanel.isHidden.toggle()
            updateInsets()
        case "view.hideTools":
            toolStrip.isHidden.toggle()
            showOptionsPanel()
            updateInsets()
        case "view.infoBar": infoPanel.isHidden.toggle()
        case "tool.hand": selectTool(id)
        case _ where ToolStrip.toolIDs.contains(id): selectTool(id)
        case "edit.copy": copyLayer()
        case "edit.copyMerged": copyMerged()
        case "edit.cut":
            copyLayer()
            run("edit.delete")
        case "edit.paste": paste()
        case "file.export": exportImage()
        case "file.import", "insert.choose": importImages(title: title)
        default:
            do { try session.run(id, title: title) } catch { presentError(error) }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let id = menuItem.representedObject as? String else { return false }
        let base = EditorWindowController.titles[id] ?? menuItem.title
        guard editorDocument != nil else { return false }
        var title = session.dynamicTitle(id) ?? base
        switch id {
        case "view.hideLayers" where layersPanel.isHidden: title = AppInfo.tr("Show Layers", "Показать слои")
        case "view.hideTools" where toolStrip.isHidden: title = AppInfo.tr("Show Tools", "Показать инструменты")
        case "view.infoBar" where !infoPanel.isHidden: title = AppInfo.tr("Hide Info Bar", "Скрыть строку сведений")
        default: break
        }
        if menuItem.title != title { menuItem.title = title }
        if ToolStrip.toolIDs.contains(id) {
            menuItem.state = selectedTool == id ? .on : .off
        } else if let tool = CanvasTool(rawValue: id) {
            menuItem.state = canvas.tool == tool ? .on : .off
        } else {
            menuItem.state = session.isChecked(id) ? .on : .off
        }
        let ok = canRun(id)
        if !ok && !EditorWindowController.windowCommands.contains(id) && !EditorSession.documentCommands.contains(id) {
            menuItem.toolTip = AppInfo.tr("Not available yet", "Пока не сделано")
        }
        return ok
    }

    // MARK: буфер обмена

    private func copyLayer() {
        guard let layer = session.primaryLayer, let box = layer.bounds?.intersection(session.document.bounds), !box.isEmpty else { return }
        var scratch = Document(width: session.document.width, height: session.document.height, depth: session.document.depth)
        var single = layer
        single.isVisible = true
        single.isClippingMask = false
        scratch.layers = [single]
        do {
            let img = try CPURenderer.render(scratch, region: RenderRegion(x: box.x, y: box.y, width: box.width, height: box.height)).image
            PasteboardImage.write(img, depth: scratch.depth)
        } catch {
            presentError(error)
        }
    }

    private func copyMerged() {
        do {
            PasteboardImage.write(try canvas.renderer.renderWhole(session.document), depth: session.document.depth)
        } catch {
            presentError(error)
        }
    }

    /// Вставка — новым слоем по центру документа.
    private func paste() {
        guard let pasted = PasteboardImage.read(), var layer = pasted.layers.first else { NSSound.beep(); return }
        layer.position = PixelPoint(x: (session.document.width - pasted.width) / 2, y: (session.document.height - pasted.height) / 2)
        session.insert([convertDepth(layer)], title: EditorWindowController.titles["edit.paste"] ?? "Paste")
    }

    /// Растр слоя приводится к глубине документа (рендер и формат файла ждут одну глубину).
    private func convertDepth(_ layer: Layer) -> Layer {
        guard case .bitmap(let b) = layer.content, b.depth != session.document.depth else { return layer }
        var l = layer
        l.content = .bitmap(Bitmap(image: b.toImage(), depth: session.document.depth))
        return l
    }

    // MARK: импорт и экспорт

    private func importImages(title: String) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            var layers: [Layer] = []
            for url in panel.urls {
                do {
                    let b = try ImageFiles.bitmap(from: try Data(contentsOf: url))
                    var l = Layer.bitmap(name: url.deletingPathExtension().lastPathComponent, b)
                    l.position = PixelPoint(x: (self.session.document.width - b.width) / 2, y: (self.session.document.height - b.height) / 2)
                    layers.append(self.convertDepth(l))
                } catch {
                    self.presentError(error)
                }
            }
            self.session.insert(layers, title: title)
        }
    }

    private let exportFormats: [(String, UTType)] = [("PNG", .png), ("JPEG", .jpeg), ("TIFF", .tiff), ("HEIC", .heic)]

    private func exportImage() {
        guard let window else { return }
        let panel = NSSavePanel()
        let picker = NSPopUpButton()
        for (name, _) in exportFormats { picker.addItem(withTitle: name) }
        let chooser = FormatChooser(panel: panel, formats: exportFormats.map(\.1))
        picker.target = chooser
        picker.action = #selector(FormatChooser.changed(_:))
        let label = NSTextField(labelWithString: AppInfo.tr("Format:", "Формат:"))
        let accessory = NSStackView(views: [label, picker])
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        panel.accessoryView = accessory
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (editorDocument?.displayName as NSString?)?.deletingPathExtension ?? "Image"
        let doc = session.document
        panel.beginSheetModal(for: window) { [weak self] response in
            withExtendedLifetime(chooser) {}
            guard response == .OK, let url = panel.url, let self else { return }
            let type = UTType(filenameExtension: url.pathExtension) ?? .png
            do {
                let img = try self.canvas.renderer.renderWhole(doc)
                try ImageFiles.encode(img, as: type, depth: doc.depth).write(to: url)
            } catch {
                self.presentError(error)
            }
        }
    }
}

/// Заголовок окна как у образца. По замеру Accessibility (19.10) он собран из стандартных элементов
/// панели инструментов macOS — так же и здесь: слева группа «панель слоёв» + меню «Вид», затем масштаб
/// (ползунок и «−»/«+»); справа «Центр контента» (переключатель), цвет, «Удалить фон», «Повернуть»,
/// «Поделиться» (системная кнопка) и «Действия с изображением» (кнопка с меню).
extension EditorWindowController {
    private static let viewItem = NSToolbarItem.Identifier("view")
    private static let zoomItem = NSToolbarItem.Identifier("zoom")
    private static let contentItem = NSToolbarItem.Identifier("content")
    private static let colorItem = NSToolbarItem.Identifier("color")
    private static let removeBackgroundItem = NSToolbarItem.Identifier("removeBackground")
    private static let rotateItem = NSToolbarItem.Identifier("rotate")
    private static let shareItem = NSToolbarItem.Identifier("share")
    private static let actionsItem = NSToolbarItem.Identifier("actions")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // Сверка 24.10: гибкий промежуток отнимал у названия 8 точек — у образца его нет, место до правых кнопок занимает название.
        [EditorWindowController.viewItem, EditorWindowController.zoomItem,
         EditorWindowController.contentItem, EditorWindowController.colorItem, EditorWindowController.removeBackgroundItem,
         EditorWindowController.rotateItem, EditorWindowController.shareItem, EditorWindowController.actionsItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    /// Маленькая кнопка внутри своего вида (масштаб); w/h — по замеру Accessibility.
    /// У образца у «−»/«+» нет подсказки, а название — системное по значку («удалить»/«добавить»).
    private func smallButton(_ symbol: String, _ action: Selector, size: CGFloat) -> NSButton {
        // Сверка 10: значок SF панель увеличивала — у образца «−»/«+» около 6 точек; поэтому готовая картинка 8 × 8.
        let name = symbol == "minus" ? AppInfo.tr("remove", "удалить") : AppInfo.tr("add", "добавить")
        // Сверка 13 по пикселям: «−»/«+» у образца 6 × 6, у нас при 10/11 вышло 8 × 8.
        let image = titleIcon(symbol, name, side: 8, pointSize: 9, weight: .regular)
        let b = NSButton(image: image, target: self, action: action)
        b.imageScaling = .scaleNone
        b.contentTintColor = .secondaryLabelColor
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.translatesAutoresizingMaskIntoConstraints = false
        // Замер AppKit шире рамки на 1 точку с каждой стороны (см. NSView.place).
        b.widthAnchor.constraint(equalToConstant: size - 2).isActive = true
        b.heightAnchor.constraint(equalToConstant: size - 2).isActive = true
        return b
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let t = AppInfo.tr
        switch id {
        case EditorWindowController.viewItem:
            // Замер: группа 85, внутри вплотную две кнопки 38 × 34 с y 9 — «Слои» (значок боковой панели, название
            // системное) и кнопка-меню «Вид». Группа пунктов NSToolbarItemGroup выходила шире на 8 и кнопки 42 × 38.
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = t("View", "Вид")
            item.toolTip = t("Choose what to show or hide.", "Выбрать, что показать/скрыть при создании изображения.")
            let sidebar = NSButton(image: NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil) ?? NSImage(),
                                   target: self, action: #selector(toggleLayers))
            // Стрелка у образца мелкая и жирная, между кнопками — тонкая черта (снимок сверки 7).
            // Сверка 10: значок SF кнопка панели всё равно увеличивала — готовая картинка ~8 × 5, как у образца.
            // Сверка 13 по пикселям: у образца стрелка 8 × 5 с линией 2 (у нас при 8/8 вышло 6 × 4 и тонко).
            let chevron = titleIcon("chevron.down", item.label, side: 10, pointSize: 10, weight: .black)
            let viewMenu = MenuButton(image: chevron,
                                      target: self, action: #selector(viewMenuButton(_:)))
            viewMenu.toolTip = item.toolTip
            // Кнопка панели растягивала стрелку под свой размер — у образца она мелкая (сверка 9).
            viewMenu.imageScaling = .scaleNone
            viewMenu.contentTintColor = .labelColor
            let box = NSView()
            box.translatesAutoresizingMaskIntoConstraints = false
            for b in [sidebar, viewMenu] {
                b.bezelStyle = .toolbar
                b.imagePosition = .imageOnly
                b.translatesAutoresizingMaskIntoConstraints = false
                box.addSubview(b)
            }
            NSLayoutConstraint.activate([
                // Вид 81 даёт группу 85 (сверка 4: при 77 группа вышла 81).
                box.widthAnchor.constraint(equalToConstant: 81),
                box.heightAnchor.constraint(equalToConstant: 36),
                sidebar.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 2),
                viewMenu.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 1),
                sidebar.widthAnchor.constraint(equalToConstant: 36), viewMenu.widthAnchor.constraint(equalToConstant: 36),
                sidebar.heightAnchor.constraint(equalToConstant: 32), viewMenu.heightAnchor.constraint(equalToConstant: 32),
                sidebar.centerYAnchor.constraint(equalTo: box.centerYAnchor), viewMenu.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            ])
            let divider = NSBox()
            divider.boxType = .separator
            divider.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(divider)
            NSLayoutConstraint.activate([
                divider.widthAnchor.constraint(equalToConstant: 1), divider.heightAnchor.constraint(equalToConstant: 20),
                divider.centerXAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 0.5),
                divider.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            ])
            item.view = box
            item.isNavigational = true
            return item
        case EditorWindowController.zoomItem:
            let item = NSToolbarItem(itemIdentifier: id)
            zoomSlider.target = self
            zoomSlider.action = #selector(zoomSliderMoved(_:))
            zoomSlider.isContinuous = true
            zoomSlider.trackFillColor = Theme.accent
            zoomSlider.toolTip = EditorWindowController.titles["tool.zoom"]
            zoomSlider.translatesAutoresizingMaskIntoConstraints = false
            // Ручка у образца 16 × 12 — малый ползунок.
            zoomSlider.controlSize = .small
            // Замер: группа 158, «−» 24 × 24, ползунок 102 × 20, «+» 24 × 24; в Accessibility они заходят друг на друга
            // на 1 точку — между рамками 1 точка, поля по 2 (рамка «−» в 6 точках от края группы).
            zoomSlider.widthAnchor.constraint(equalToConstant: 100).isActive = true
            zoomSlider.heightAnchor.constraint(equalToConstant: 18).isActive = true
            let row = NSStackView(views: [smallButton("minus", #selector(zoomOutButton), size: 24),
                                          zoomSlider,
                                          smallButton("plus", #selector(zoomInButton), size: 24)])
            row.spacing = 1
            // Сверка 4: при полях 2/2 группа 154 и «−» в 1 точке от её края; у образца 158 и 5.
            row.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 2)
            row.alignment = .centerY
            item.view = row
            item.label = t("Zoom", "Изменить масштаб")
            item.isNavigational = true
            return item
        case EditorWindowController.contentItem:
            let item = NSToolbarItem(itemIdentifier: id)
            let toggle = NSButton(image: NSImage(systemSymbolName: "square.stack", accessibilityDescription: nil) ?? NSImage(),
                                  target: self, action: #selector(contentButton))
            toggle.setButtonType(.pushOnPushOff)
            toggle.toolTip = t("Browse the curated content library.", "Просмотреть медиатеку специально подобранного контента.")
            toggle.setAccessibilityLabel(t("Content Hub", "Стопка квадратов"))
            // Замер: группа 44, внутри переключатель 38 × 38 с y 7.
            // Сверка 28: в своей капсуле поля даёт сама капсула — вид по ширине кнопки (капсула у образца 37).
            // Сверка 24.10: без гибкого промежутка капсула даёт группу на 8 шире вида — вид 36 даёт 44, как у образца,
            // кнопка — в 3 точках от левого края группы.
            item.view = titleButton(toggle, buttonWidth: 36, boxWidth: 36, trailing: true)
            item.toolTip = toggle.toolTip
            item.label = t("Content Hub", "Центр контента")
            // Сверка 28: у образца «медиатека» — отдельная капсула. Пробел (.space) отделял её, но сдвигал на 8 точек;
            // стиль .prominent (macOS 26) выносит кнопку в свою капсулу без зазора (документация NSToolbarItem.style).
            // Оттенок — серый: капсула у образца 67/255 (без оттенка .prominent красит в акцентный); при оттенке 67 вышло 35 —
            // оттенок ложится на «стекло» нелинейно (67 → 35, 134 → 113), для 67 нужно ≈ 95.
            if #available(macOS 26.0, *) {
                item.style = .prominent
                item.backgroundTintColor = NSColor(srgbRed: 95 / 255, green: 95 / 255, blue: 95 / 255, alpha: 1)
            }
            return item
        case EditorWindowController.colorItem:
            let item = NSToolbarItem(itemIdentifier: id)
            colorWell.colorWellStyle = .minimal
            colorWell.color = foregroundColor
            colorWell.target = self
            colorWell.action = #selector(colorChanged(_:))
            colorWell.translatesAutoresizingMaskIntoConstraints = false
            // Замер: группа 40 (вид 36 — Accessibility даёт группу на 4 шире), образец цвета 38 × 38 у её правого края.
            // Сверка 24.10: у образца в группе две вещи в одной рамке — кнопка «Цвет» и под ней образец (AXColorWell).
            // Кнопка лежит под образцом: нажатия получает образец, кнопка открывает тот же выбор цвета с клавиатуры/VoiceOver.
            let button = NSButton(title: "", target: colorWell, action: #selector(NSColorWell.performClick(_:)))
            button.isBordered = false
            button.setAccessibilityLabel(t("Color", "Цвет"))
            button.translatesAutoresizingMaskIntoConstraints = false
            let box = NSView()
            box.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(button)
            box.addSubview(colorWell)
            NSLayoutConstraint.activate([
                box.widthAnchor.constraint(equalToConstant: 36), box.heightAnchor.constraint(equalToConstant: 36),
                colorWell.widthAnchor.constraint(equalToConstant: 36), colorWell.heightAnchor.constraint(equalToConstant: 36),
                colorWell.trailingAnchor.constraint(equalTo: box.trailingAnchor), colorWell.centerYAnchor.constraint(equalTo: box.centerYAnchor),
                button.widthAnchor.constraint(equalTo: colorWell.widthAnchor), button.heightAnchor.constraint(equalTo: colorWell.heightAnchor),
                button.centerXAnchor.constraint(equalTo: colorWell.centerXAnchor), button.centerYAnchor.constraint(equalTo: colorWell.centerYAnchor),
            ])
            item.view = box
            item.label = t("Color", "Цвет")
            return item
        case EditorWindowController.removeBackgroundItem:
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = t("Remove Background", "Удалить фон")
            item.image = EditorWindowController.removeBackgroundIcon(item.label)
            item.toolTip = t("Remove the background from the selected layer.", "Удалить фон из выбранного слоя.")
            // Как у образца — обычная доступная кнопка; само удаление фона — этап 7, пока звуковой сигнал.
            item.target = self
            item.action = #selector(notYetButton)
            return item
        case EditorWindowController.rotateItem:
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = t("Rotate", "Повернуть")
            item.image = titleIcon("rotate.left", item.label)
            item.toolTip = t("Rotate the document 90° left.", "Поворот документа на 90° влево.")
            item.target = self
            item.action = #selector(rotateButton)
            return item
        case EditorWindowController.shareItem:
            // Замер: группа 36, внутри кнопка-меню 36 × 38 с y 7.
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = t("Share", "Поделиться")
            item.toolTip = t("Share the image.", "Поделиться изображением.")
            let button = MenuButton(image: NSImage(systemSymbolName: "square.and.arrow.up.on.square", accessibilityDescription: item.label) ?? NSImage(),
                                    target: self, action: #selector(shareButton(_:)))
            button.toolTip = item.toolTip
            item.view = titleButton(button, buttonWidth: 34, boxWidth: 34)
            return item
        case EditorWindowController.actionsItem:
            // Замер: группа 40, внутри кнопка-меню 38 × 38 с y 7.
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = t("Image Actions", "Действия с изображением")
            item.toolTip = t("Image operations such as resizing, color profile and more.",
                             "Выполнить операции с изображением, такие как изменение размера, цветового профиля и др.")
            let button = MenuButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: item.label) ?? NSImage(),
                                    target: self, action: #selector(actionsButton(_:)))
            button.toolTip = item.toolTip
            item.view = titleButton(button, buttonWidth: 36, boxWidth: 36)
            return item
        default:
            return nil
        }
    }

    /// Кнопка заголовка в своём виде, как у образца: обычная кнопка панели (в Accessibility на 2 точки больше рамки,
    /// с y 7) в группе с подсказкой. Если сделать кнопку видом пункта напрямую, macOS растягивает её на всю высоту (52).
    private func titleButton(_ button: NSButton, buttonWidth: CGFloat, boxWidth: CGFloat, trailing: Bool = false,
                             trailingOverhang: CGFloat = 0) -> NSView {
        button.bezelStyle = .toolbar
        button.imagePosition = .imageOnly
        button.translatesAutoresizingMaskIntoConstraints = false
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(button)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: boxWidth),
            box.heightAnchor.constraint(equalToConstant: 36),
            button.widthAnchor.constraint(equalToConstant: buttonWidth),
            button.heightAnchor.constraint(equalToConstant: 36),
            trailing ? button.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: trailingOverhang)
                : button.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        return box
    }

    /// Значок пункта заголовка на поле 20 × 20: у образца «Удалить фон» и «Повернуть» по 36 точек шириной
    /// (у нас со значком SF по его ширине выходило 40 и 70).
    /// side/pointSize/weight — для мелких значков («−»/«+», стрелка «Вида»), которые панель иначе увеличивает.
    private func titleIcon(_ symbol: String, _ description: String, side: CGFloat = 20, pointSize: CGFloat = 16,
                           weight: NSFont.Weight = .medium) -> NSImage {
        let base = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            // Сверка 8: при 15 regular линии «Повернуть» тоньше, чем у образца (97-я доля яркости 182 против 253).
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight)) ?? NSImage()
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let s = base.size
            let k = min(side / max(s.width, 1), side / max(s.height, 1), 1)
            let w = s.width * k, h = s.height * k
            base.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }

    /// «Удалить фон» — перерисовка значка образца вектором (его картинка 21 × 22, снята с Mac 19.10, в приложение
    /// не кладётся): рамка 1,5 со скруглением 3, диагональная штриховка снизу-слева вверх-вправо с шагом 6,6,
    /// вокруг круга — пустое поле 2 точки, круг-кольцо радиусом 5,5 с линией 2.
    static func removeBackgroundIcon(_ description: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 21, height: 22), flipped: true) { _ in
            NSColor.black.set()
            // Сверка 12 по пикселям: рамка у образца на экране 19 × 15 (у нас было 20 × 18), кольцо — 9 (у нас 10).
            let frame = NSRect(x: 1, y: 3.75, width: 19, height: 14.5)
            let border = NSBezierPath(roundedRect: frame, xRadius: 3, yRadius: 3)
            border.lineWidth = 1.2
            border.stroke()
            let center = NSPoint(x: 10.5, y: 11.5)
            let r: CGFloat = 4.5
            NSGraphicsContext.saveGraphicsState()
            let clip = NSBezierPath(rect: frame)
            clip.appendOval(in: NSRect(x: center.x - r - 1, y: center.y - r - 1, width: 2 * (r + 1), height: 2 * (r + 1)))
            clip.windingRule = .evenOdd
            clip.addClip()
            let hatch = NSBezierPath()
            hatch.lineWidth = 1.2
            var x: CGFloat = -31.8
            while x < 30 {
                hatch.move(to: NSPoint(x: x, y: 22))
                hatch.line(to: NSPoint(x: x + 22, y: 0))
                x += 6.6
            }
            hatch.stroke()
            NSGraphicsContext.restoreGraphicsState()
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - r + 0.6, y: center.y - r + 0.6, width: 2 * r - 1.2, height: 2 * r - 1.2))
            // Сверка 11: при 2 кольцо, а при 1,5/1,7 рамка и штриховка выходили заметно толще, чем у образца.
            ring.lineWidth = 1.2
            ring.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }

    @objc private func notYetButton() { NSSound.beep() }

    @objc private func viewMenuButton(_ sender: NSButton) {
        let menu = commandMenu(["view.hideLayers", "view.hideTools", "pxm.view.hideToolOptions", "-", "view.infoBar"])
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func shareButton(_ sender: NSButton) {
        let picker = NSSharingServicePicker(items: shareItems())
        picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    @objc private func actionsButton(_ sender: NSButton) {
        let menu = commandMenu(["image.size", "image.canvasSize", "-", "image.rotate180", "image.rotateRight", "image.rotateLeft",
                                "image.flipH", "image.flipV", "-", "image.trim", "image.revealCanvas", "-", "image.superResolution",
                                "-", "image.colorProfile", "image.colorDepth"])
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    /// «Поделиться»: документ сводится в PNG во временной папке и отдаётся системному меню.
    private func shareItems() -> [Any] {
        guard editorDocument != nil, let img = try? canvas.renderer.renderWhole(session.document) else { return [] }
        let name = ((editorDocument?.displayName ?? "Image") as NSString).deletingPathExtension + ".png"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        guard (try? ImageFiles.encode(img, as: .png, depth: session.document.depth).write(to: url)) != nil else { return [] }
        return [url]
    }

    /// Меню из команд главного меню (названия и доступность — те же).
    private func commandMenu(_ ids: [String]) -> NSMenu {
        let menu = NSMenu()
        for id in ids {
            if id == "-" {
                menu.addItem(.separator())
                continue
            }
            let item = NSMenuItem(title: EditorWindowController.titles[id] ?? id, action: #selector(EditorCommandTarget.performEditorCommand(_:)), keyEquivalent: "")
            item.representedObject = id
            item.target = self
            menu.addItem(item)
        }
        return menu
    }

    @objc private func toggleLayers() { run("view.hideLayers") }
    @objc private func zoomInButton() { run("view.zoomIn") }
    @objc private func zoomOutButton() { run("view.zoomOut") }
    @objc private func contentButton() { run("insert.choose") }
    @objc private func rotateButton() { run("image.rotateLeft") }

    @objc private func zoomSliderMoved(_ sender: NSSlider) {
        canvas.setScale(pow(2, sender.doubleValue))
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        foregroundColor = sender.color
    }
}

/// Выбор формата в окне экспорта: меняет тип файла и расширение в имени.
final class FormatChooser: NSObject {
    let panel: NSSavePanel
    let formats: [UTType]

    init(panel: NSSavePanel, formats: [UTType]) {
        self.panel = panel
        self.formats = formats
    }

    @objc func changed(_ sender: NSPopUpButton) {
        let type = formats[max(sender.indexOfSelectedItem, 0)]
        panel.allowedContentTypes = [type]
    }
}
/// Кнопка, открывающая меню: в Accessibility — «кнопка меню» (AXMenuButton), как «Поделиться» и «Действия» у образца.
final class MenuButton: NSButton {
    override func accessibilityRole() -> NSAccessibility.Role? { .menuButton }
}
/// Образец цвета как у образца: маленький кружок (~17 точек) по центру кнопки 36 × 36, а не круг во всю кнопку.
final class SwatchColorWell: NSColorWell {
    override func draw(_ dirtyRect: NSRect) {
        let d: CGFloat = 17
        let r = NSRect(x: bounds.midX - d / 2, y: bounds.midY - d / 2, width: d, height: d)
        color.setFill()
        NSBezierPath(ovalIn: r).fill()
    }
}
#endif
