#if canImport(AppKit)
import AppKit
import CoreImage
import EditorApp

/// Панель настроек инструмента справа (инспектор образца): своя у каждого инструмента полосы.
/// Координаты элементов — замеры Accessibility с работающего образца (20.10:
/// снимки всех 21 панели), в точках от левого верхнего угла панели.
class ToolPanel: FloatingPanel {
    weak var controller: EditorWindowController?

    /// Панель инструмента полосы. Те, что ещё не построены 1:1, — только шапка (заголовок как у образца).
    static func make(_ id: String) -> ToolPanel {
        switch id {
        case "tool.style": return StylePanel()
        case "tool.selectRect", "tool.lassoFree", "tool.selectQuick": return SelectionPanel(id)
        case "tool.effects": return EffectsPanel()
        case "tool.fill": return ColorFillPanel()
        case "tool.repair": return RepairPanel()
        case "tool.distort": return DistortPanel()
        case "tool.sharpen", "tool.lighten", "tool.saturate": return ToneBrushPanel(id)
        case "tool.clone": return ClonePanel()
        case "tool.paint", "tool.erase": return BrushPanel(id)
        case "tool.zoom": return ZoomPanel()
        case "tool.pen": return PenPanel()
        case "tool.shape": return ShapePanel()
        case "tool.crop": return CropPanel()
        case "tool.type": return TypePanel()
        case "tool.adjustments": return AdjustmentsPanel()
        default: return ToolPanel(title: ToolPanel.titles[id] ?? id, header: ToolPanel.headers[id] ?? [])
        }
    }

    /// Заголовки панелей — тексты образца (у некоторых инструментов не совпадают с названием кнопки полосы).
    static let titles: [String: String] = AppInfo.russian ? [
        "tool.style": "Стиль", "tool.adjustments": "Цветокоррекция", "tool.effects": "Эффекты",
        "tool.selectRect": "Выбор прямоугольником", "tool.lassoFree": "Свободный выбор", "tool.selectQuick": "Быстрый выбор",
        "tool.paint": "Рисовать", "tool.fill": "Заливка цветом", "tool.erase": "Стереть", "tool.repair": "Исправить",
        "tool.clone": "Штамп", "tool.sharpen": "Резкость", "tool.lighten": "Осветление", "tool.saturate": "Повысить насыщенность",
        "tool.distort": "Исказить", "tool.pen": "Перо", "tool.shape": "Фигура", "tool.type": "Текст",
        "tool.zoom": "Изменить масштаб", "tool.crop": "Обрезать",
    ] : [
        "tool.style": "Style", "tool.adjustments": "Color Adjustments", "tool.effects": "Effects",
        "tool.selectRect": "Rectangular Selection", "tool.lassoFree": "Freeform Selection", "tool.selectQuick": "Quick Selection",
        "tool.paint": "Paint", "tool.fill": "Color Fill", "tool.erase": "Erase", "tool.repair": "Repair",
        "tool.clone": "Clone", "tool.sharpen": "Sharpen", "tool.lighten": "Lighten", "tool.saturate": "Saturate",
        "tool.distort": "Distort", "tool.pen": "Pen", "tool.shape": "Shape", "tool.type": "Type",
        "tool.zoom": "Zoom", "tool.crop": "Crop",
    ]

    /// Кнопки в шапке справа от заголовка (замер 20.10): «…» — меню панели, «добавить» — новый слой.
    enum HeaderItem { case menu, add(String) }
    static let headers: [String: [HeaderItem]] = [
        "tool.style": [.menu],
        "tool.adjustments": [.menu, .add(AppInfo.tr("Create a new color adjustments layer.", "Создать новый слой цветокоррекции."))],
        "tool.effects": [.menu, .add(AppInfo.tr("Create a new effects layer.", "Создать новый слой эффектов."))],
    ]

    init(title: String, header: [HeaderItem]) {
        super.init(frame: .zero)
        label(title, 14, 16, 232, 19, size: 14, weight: .bold)
        line(41)
        for item in header {
            switch item {
            case .menu: menuDots(241, 16)
            case .add(let tip):
                // Замер: 18 × 20 в (214, 16), значок «+» цвета текста.
                let b = Theme.iconButton("plus", tip, size: 13, target: nil, action: nil)
                b.setAccessibilityLabel(AppInfo.tr("add", "добавить"))
                put(b, 214, 16, 18, 20)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    /// Обновить по выбранному слою (вызывается при каждой правке документа).
    func update() {}

    /// Масштаб или положение холста изменились.
    func viewportChanged() {}

    // MARK: детали, общие для панелей

    func put(_ v: NSView, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat? = nil, _ h: CGFloat? = nil, fromBottom: Bool = false) {
        v.place(in: self, x: x, y: y, w: w, h: h, fromBottom: fromBottom)
    }

    /// Шрифты — как в «Расстановке» (замеры 19.10): заголовок 14 жирный, разделы 12 жирный, подписи 12.
    @discardableResult
    func label(_ text: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat? = nil, _ h: CGFloat? = nil,
               size: CGFloat = 12, weight: NSFont.Weight = .regular, in parent: NSView? = nil) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.place(in: parent ?? self, x: x, y: y, w: w, h: h)
        return l
    }

    /// Разделитель во всю ширину содержимого (14…258), как в «Расстановке».
    func line(_ y: CGFloat, bottom: Bool = false) {
        put(Theme.separator(), 14, y, 244, 1, fromBottom: bottom)
    }

    /// «…» — меню (AXMenuButton 18 × 22): у образца три точки цвета текста. Точки нашего значка в той же
    /// рамке на точку правее и ниже (сверка 20.10) — рамка на точку левее и выше.
    func menuDots(_ x: CGFloat, _ y: CGFloat) {
        let image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold)) ?? NSImage()
        // Без подписи: иначе macOS называет значок «Еще», у образца у кнопки подписи нет.
        image.accessibilityDescription = ""
        let b = MenuButton(image: image, target: self, action: #selector(ToolPanel.noAction(_:)))
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.contentTintColor = .labelColor
        put(b, x - 1, y - 1, 18, 22)
    }

    /// Большая кнопка во всю ширину (30 точек): серая или цвета акцента («Добавить стиль»).
    @discardableResult
    func wideButton(_ title: String, _ tip: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat,
                    prominent: Bool = false, fromBottom: Bool = false) -> NSButton {
        let b = TightButton(title: title, target: nil, action: nil)
        b.bezelStyle = .push
        b.controlSize = .large
        b.font = .systemFont(ofSize: 12, weight: prominent ? .semibold : .regular)
        // Цвет подложки по снимку образца: акцент — 252/63/95 (AppKit рисует заданный цвет чуть насыщеннее),
        // серая — 81 (без цвета у нас 70).
        b.bezelColor = prominent ? NSColor(srgbRed: 1, green: 59 / 255, blue: 90 / 255, alpha: 1) : Theme.buttonBezel
        b.toolTip = tip
        put(b, x, y, w, 30, fromBottom: fromBottom)
        return b
    }

    /// «Непрозрачность (Режим) ⌃⌄ … 100 %» и ползунок под ней — как у образца в «Стиле», «Заливке», «Фигуре».
    /// Подпись — кнопка меню режима наложения; у образца название режима сокращено в самом тексте («Обычн…»).
    /// Рамки — замеры Accessibility каждой панели (меню, число, ползунок).
    func opacityRow(menu menuFrame: NSRect, field fieldFrame: NSRect, slider sliderFrame: NSRect, value: Double = 100,
                    menuTip: String, fieldTip: String, sliderTip: String, in parent: NSView? = nil) {
        let host = parent ?? self
        let menu = MenuButton(title: AppInfo.tr("Opacity (Norm…)", "Непрозрачность (Обычн…)"), target: self, action: #selector(ToolPanel.noAction(_:)))
        menu.isBordered = false
        menu.font = .systemFont(ofSize: 12)
        menu.image = NSImage(systemSymbolName: "chevron.up.chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        menu.imagePosition = .imageTrailing
        // ⌃⌄ сразу за текстом, как у образца (иначе — у правого края рамки).
        menu.imageHugsTitle = true
        menu.alignment = .left
        // Цвет основного текста, как у образца (без этого AppKit рисует подпись кнопки без рамки серой — сверка 24.10).
        menu.contentTintColor = .labelColor
        menu.toolTip = menuTip
        menu.place(in: host, x: menuFrame.minX, y: menuFrame.minY, w: menuFrame.width, h: menuFrame.height)
        numberField("\(Int(value))\u{00A0}%", tip: fieldTip, fieldFrame, in: host)
        // Ручка обычного малого ползунка 18 × 14 (как у образца здесь, в отличие от панели «Слои»).
        let slider = NSSlider(value: value, minValue: 0, maxValue: 100, target: self, action: #selector(ToolPanel.noAction(_:)))
        slider.controlSize = .small
        slider.trackFillColor = Theme.accent
        slider.toolTip = sliderTip
        slider.place(in: host, x: sliderFrame.minX, y: sliderFrame.minY, w: sliderFrame.width, h: sliderFrame.height)
    }

    /// Число справа от подписи («100 %», «50 %»): 12 точек по центру строки, цифры кончаются в 4 точках от правого
    /// края рамки образца (у нас в ячейке — в 5, поэтому рамка на 1 правее и на 1 выше; сверка 20.10).
    @discardableResult
    func numberField(_ text: String, tip: String, _ frame: NSRect, in parent: NSView? = nil) -> NSTextField {
        let field = NSTextField()
        field.cell = CenteredTextFieldCell(textCell: text)
        field.isEditable = true
        field.isBezeled = false
        field.drawsBackground = false
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        field.toolTip = tip
        field.place(in: parent ?? self, x: frame.minX + 1, y: frame.minY - 1, w: 58, h: 24)
        return field
    }

    /// «Подпись … 50 %» и ползунок под ней («Размер кисти», «Мягкость», «Сила»…): подпись 12 в (x, y + 3),
    /// число 12 по правому краю, малый ползунок на 18 точек ниже — замеры 20.10.
    /// position — положение ручки в процентах, если шкала не прямая (размер кисти в px у образца нелинейный).
    @discardableResult
    func sliderRow(_ title: String, _ value: Double, unit: String = "\u{00A0}%", position: Double? = nil, _ x: CGFloat, _ y: CGFloat,
                   width: CGFloat = 242, fieldTip: String, sliderTip: String, in parent: NSView? = nil) -> NSSlider {
        let host = parent ?? self
        label(title, x, y + 3, nil, 17, in: host)
        numberField("\(Int(value))\(unit)", tip: fieldTip, NSRect(x: x + width - 58, y: y, width: 58, height: 22), in: host)
        let slider = NSSlider(value: position ?? value, minValue: 0, maxValue: 100, target: self, action: #selector(ToolPanel.noAction(_:)))
        slider.controlSize = .small
        slider.trackFillColor = Theme.accent
        slider.toolTip = sliderTip
        slider.place(in: host, x: x, y: y + 18, w: width, h: 20)
        return slider
    }

    /// Флажок с подписью 12 (при 13 текст на 8 % шире, чем у образца — снимок 20.10), рамка во всю ширину.
    @discardableResult
    func checkbox(_ title: String, on: Bool, tip: String, _ x: CGFloat, _ y: CGFloat, in parent: NSView? = nil) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(ToolPanel.noAction(_:)))
        b.font = .systemFont(ofSize: 12)
        b.state = on ? .on : .off
        b.toolTip = tip
        b.place(in: parent ?? self, x: x, y: y, w: 242, h: 18)
        return b
    }

    /// Набор образцов под списком коллекции: ровно по замеру (13, 88) 248 × 102, без поправки place() — у простого
    /// вида рамка в Accessibility не расширена (сверка 20.10).
    func placeGrid(_ grid: PresetGrid) {
        grid.setAccessibilityRole(.list)
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 88),
            grid.widthAnchor.constraint(equalToConstant: 248),
            grid.heightAnchor.constraint(equalToConstant: 102),
        ])
    }

    /// Список коллекции («Градиенты», «Эфир», …) с «…» справа.
    func collectionPopup(_ title: String, tip: String) {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: [title])
        popup.toolTip = tip
        put(popup, 15, 55, 218, 26)
        menuDots(241, 57)
    }

    /// Внизу панели: разделитель и «сравнить» (до правки) + «Сбросить» по 118, у образца обе недоступны,
    /// пока нечего сравнивать.
    func compareAndReset(compareTip: String, resetTip: String) {
        line(57, bottom: true)
        // Значок — системный «квадрат с заливкой, черта, квадрат» (его название образца и отдаёт в Accessibility).
        let symbol = NSImage(systemSymbolName: "square.filled.and.line.vertical.and.square", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) ?? NSImage()
        let compare = TightButton(image: symbol, target: nil, action: nil)
        // Без названия: иначе AppKit подставляет «Кнопка» (сверка панелей 24.10).
        compare.title = ""
        compare.imagePosition = .imageOnly
        compare.bezelStyle = .push
        compare.controlSize = .large
        compare.toolTip = compareTip
        compare.setAccessibilityLabel(AppInfo.tr("Filled square and vertical line in a square", "Квадрат с заливкой и вертикальная линия в квадрате"))
        put(compare, 15, 15, 118, 30, fromBottom: true)
        let reset = wideButton(AppInfo.tr("Reset", "Сбросить"), resetTip, 139, 15, 118, fromBottom: true)
        for b in [compare, reset] { disable(b) }
    }

    /// Внизу панели одна недоступная «Сбросить» во всю ширину.
    func resetOnly(_ tip: String) {
        line(57, bottom: true)
        disable(wideButton(AppInfo.tr("Reset", "Сбросить"), tip, 15, 15, 242, fromBottom: true))
    }

    /// Недоступная кнопка как у образца: подложка 68 и текст 119 (у AppKit по умолчанию текст 91 — сверка 20.10).
    func disable(_ b: NSButton) {
        b.isEnabled = false
        b.bezelColor = Theme.buttonBezelDisabled
        if !b.title.isEmpty {
            b.attributedTitle = NSAttributedString(string: b.title, attributes: [
                .font: b.font ?? .systemFont(ofSize: 12),
                .foregroundColor: NSColor(white: 1, alpha: 0.27),
                .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = .center; return p }(),
            ])
        }
    }

    /// Карточка стиля слоя во всю ширину панели, строка с y (замер строки таблицы образца).
    @discardableResult
    func styleCard(_ title: String, on: Bool = false, y: CGFloat, height: CGFloat = 52) -> StyleCard {
        let t = AppInfo.tr
        let card = StyleCard(title: title, deleteTip: t("Delete this layer style.", "Удалить этот стиль слоя."),
                             switchTip: t("Turn this layer style on or off.", "Включить/выключить этот стиль слоя."), on: on, height: height)
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.widthAnchor.constraint(equalToConstant: Theme.optionsWidth),
            card.topAnchor.constraint(equalTo: topAnchor, constant: y),
            card.heightAnchor.constraint(equalToConstant: height),
        ])
        return card
    }

    @objc func noAction(_ sender: Any?) {}
}

/// Режим выделения с пояснением («Создать», «Добавление», «Вычитание», «Пересечение») — у образца кружок
/// 16 × 16 в (16, y + 1), название 12 в (37, y), под ним серое пояснение 10 (цвет 121/255) в одну-две строки
/// (шрифты — по ширине текста на снимке 20.10: при 13 и 11 у нас было шире на 8 %). Первая строка у образца
/// уже остальных — 184. У кистей с диапазоном тонов («Все», «Тени»…) ширины свои — по тексту (widths).
final class SelectionModeList: NSView {
    private var radios: [NSButton] = []
    override var isFlipped: Bool { true }

    init(rows: [(String, String, CGFloat)], widths: [CGFloat]? = nil) {
        super.init(frame: .zero)
        for (i, (title, note, y)) in rows.enumerated() {
            let radio = RowRadioButton(radioButtonWithTitle: "", target: self, action: #selector(pick(_:)))
            radio.state = i == 0 ? .on : .off
            // Строка без пояснения («Увеличить»): у образца рамка кнопки — кружок с подписью (ширина текста + 22).
            let wide = note.isEmpty && widths != nil
            radio.imagePosition = .imageLeading
            radio.alignment = .left
            let w: CGFloat = widths?[i] ?? (i == 0 ? 184 : 220)
            // Сверка 24.10: с пояснением рамка кнопки у образца — вся строка: ширина текста + 22, от верха названия
            // до низа пояснения (кружок — в левом верхнем углу, RowRadioButton).
            radio.place(in: self, x: 15, y: y, w: wide || !note.isEmpty ? w + 22 : 18, h: note.isEmpty ? 18 : nil)
            radios.append(radio)
            let name = NSTextField(labelWithString: title)
            name.font = .systemFont(ofSize: 12)
            name.place(in: self, x: 37, y: y, w: w, h: 17)
            if note.isEmpty { continue }
            let hint = NSTextField(wrappingLabelWithString: note)
            hint.font = .systemFont(ofSize: 10)
            hint.textColor = NSColor(white: 121 / 255, alpha: 1)
            hint.preferredMaxLayoutWidth = w - 2
            hint.place(in: self, x: 37, y: y + 18, w: w)
            radio.bottomAnchor.constraint(equalTo: hint.bottomAnchor).isActive = true
        }
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    @objc private func pick(_ sender: NSButton) {
        for r in radios { r.state = r === sender ? .on : .off }
    }
}

/// Радиокнопка во всю строку режима: кружок 16 × 16 в левом верхнем углу, а не по центру высоты.
/// Системная ячейка рисуется в квадрате 16 × 16 (в нём она выглядит как обычная радиокнопка), а не во всю рамку.
final class RowRadioButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        cell?.draw(withFrame: NSRect(x: 0, y: 0, width: 16, height: 16), in: self)
    }
}

/// «Выбор прямоугольником», «Свободный выбор», «Быстрый выбор»: режим выделения, у быстрого — кисть и флажки,
/// затем «Выбор объекта», «Выбрать и маскировать…», «Инвертировать выбранное»; внизу «Отменить выбор».
final class SelectionPanel: ToolPanel {
    init(_ id: String) {
        let t = AppInfo.tr
        super.init(title: ToolPanel.titles[id]!, header: [])
        let modes = SelectionModeList(rows: [
            (t("New", "Создать"), t("Creates a new selection.", "Создает новую выбранную область."), 54),
            (t("Add", "Добавление"), t("Adds areas to the selection.", "Позволяет добавлять области к\u{00A0}выбранному."), 95),
            (t("Subtract", "Вычитание"), t("Subtracts areas from the selection.", "Позволяет вычитать области из\u{00A0}выбранного."), 149),
            (t("Intersect", "Пересечение"), t("Limits the new selection to the existing one.", "Ограничивает границы новой выбранной области существующей областью."), 203),
        ])
        modes.translatesAutoresizingMaskIntoConstraints = false
        addSubview(modes)
        NSLayoutConstraint.activate([
            modes.leadingAnchor.constraint(equalTo: leadingAnchor),
            modes.widthAnchor.constraint(equalToConstant: Theme.optionsWidth),
            modes.topAnchor.constraint(equalTo: topAnchor),
            modes.heightAnchor.constraint(equalToConstant: 260),
        ])
        line(262)
        var y: CGFloat = 276
        if id == "tool.selectQuick" {
            sliderRow(t("Brush Size", "Размер кисти"), 50, 15, 272,
                      fieldTip: t("Set the selection brush size.", "Задать размер кисти выбора."),
                      sliderTip: t("Adjust the selection brush size.", "Настроить размер кисти выбора."))
            line(321)
            checkbox(t("Sample All Layers", "Все слои — образцы"), on: true,
                     tip: t("Select to make the Quick Selection tool consider every object in the image.",
                            "Выберите, чтобы инструмент быстрого выбора учитывал каждый объект в изображении."), 15, 333)
            checkbox(t("Show Selection Preview", "Показать превью выбора"), on: true,
                     tip: t("Choose to preview the initial selection before making it.",
                            "Выбрать показ превью начального выбора перед тем, как сделать его."), 15, 357)
            line(392)
            y = 406
        }
        wideButton(t("Select Subject", "Выбор объекта"), t("Automatically select the subject of the image.", "Автоматически сделать выбор объекта изображения."), 15, y, 242)
        wideButton(t("Select and Mask…", "Выбрать и маскировать…"), t("Refine the selection.", "Улучшить выбранную область."), 15, y + 39, 242)
        wideButton(t("Invert Selection", "Инвертировать выбранное"), t("Turn the selection inside out.", "Вывернуть выбранное наизнанку."), 15, y + 78, 242)
        line(y + 121)
        line(57, bottom: true)
        disable(wideButton(t("Deselect", "Отменить выбор"), t("Clear the selection.", "Очистить выбранное."), 15, 15, 242, fromBottom: true))
    }

    required init?(coder: NSCoder) { fatalError("не используется") }
}

/// Набор образцов (коллекция стилей, цветокоррекций, эффектов): 2 ряда по 4 плитки 54 × 43 с шагом 62 × 51,
/// последняя — «+» (добавить свой). Замер 20.10: сетка (13, 88), плитка внутри ячейки 60 × 49 со сдвигом 3,
/// скругление 8, по краю светлая обводка в 1 точку; у «+» фон 60, рамка 89, крест 10 × 10 цвета 111.
final class PresetGrid: NSView {
    /// Цвета сверху и снизу каждой плитки (вертикальный градиент), по снимку образца.
    var gradients: [(NSColor, NSColor)] = []
    /// Или картинки (миниатюры слоя с эффектом): вписаны с обрезкой по плитке.
    var images: [NSImage] = [] { didSet { needsDisplay = true } }
    /// Пустые плитки (коллекция цветокоррекций без слоя): заливка 65, обводка 94 — снимок 20.10.
    var emptyTiles = false

    override var isFlipped: Bool { true }

    init(gradients: [(NSColor, NSColor)]) {
        self.gradients = gradients
        super.init(frame: .zero)
        let add = NSImageView()
        add.isEnabled = false
        add.setAccessibilityLabel("page preset add")
        // Как у образца: образ «+» в Accessibility — 56 × 45 в последней ячейке.
        add.place(in: self, x: 188, y: 53, w: 56, h: 45)
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    static func tile(_ i: Int) -> NSRect {
        NSRect(x: 3 + CGFloat(i % 4) * 62, y: 3 + CGFloat(i / 4) * 51, width: 54, height: 43)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, image) in images.prefix(7).enumerated() where image.size.width > 0 {
            let r = PresetGrid.tile(i)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).addClip()
            let k = max(r.width / image.size.width, r.height / image.size.height)
            let w = image.size.width * k, h = image.size.height * k
            image.draw(in: NSRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h), from: .zero,
                       operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
        }
        if emptyTiles {
            for i in 0..<7 {
                let r = PresetGrid.tile(i)
                NSColor(white: 65 / 255, alpha: 1).setFill()
                NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
                NSColor(white: 94 / 255, alpha: 1).setStroke()
                let rim = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 7.5, yRadius: 7.5)
                rim.lineWidth = 1
                rim.stroke()
            }
        }
        for (i, (top, bottom)) in gradients.prefix(7).enumerated() {
            let r = PresetGrid.tile(i)
            let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
            NSGradient(starting: top, ending: bottom)?.draw(in: path, angle: 90)
            NSColor(white: 1, alpha: 0.12).setStroke()
            let rim = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 7.5, yRadius: 7.5)
            rim.lineWidth = 1
            rim.stroke()
        }
        let r = PresetGrid.tile(7)
        NSColor(white: 60 / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
        NSColor(white: 89 / 255, alpha: 1).setStroke()
        let border = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 7.5, yRadius: 7.5)
        border.lineWidth = 1
        border.stroke()
        NSColor(white: 111 / 255, alpha: 1).setFill()
        NSRect(x: r.midX - 5, y: r.midY - 0.75, width: 10, height: 1.5).fill()
        NSRect(x: r.midX - 0.75, y: r.midY - 5, width: 1.5, height: 10).fill()
    }
}

/// Карточка стиля слоя («Заливка», «Обводка», «Тень»…): скруглённая подложка 240 × (высота строки − 10) цвета 71,
/// скругление 14 (замеры 20.10 и 24.10), слева название, справа корзина и переключатель. Строки свёрнутых
/// карточек идут с шагом 52; у раскрытой («Обводка» в «Пере») настройки кладут внутрь карточки по замерам от её верха.
final class StyleCard: NSView {
    override var isFlipped: Bool { true }

    init(title: String, deleteTip: String, switchTip: String, on: Bool = false, height: CGFloat = 52) {
        super.init(frame: .zero)
        let plate = NSView()
        plate.wantsLayer = true
        plate.layer?.backgroundColor = NSColor(white: 71 / 255, alpha: 1).cgColor
        plate.layer?.cornerRadius = 14
        // Подложка в Accessibility не видна — без поправки place(): ровно (16, 0) 240 × (высота − 10).
        plate.frame = NSRect(x: 16, y: 0, width: 240, height: height - 10)
        addSubview(plate)
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 12, weight: .bold)   // сверка 24.10: при semibold названия на 2–4 точки уже, чем у образца
        name.place(in: self, x: 27, y: 12, h: 17)
        let trash = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) ?? NSImage(), target: nil, action: nil)
        trash.isBordered = false
        trash.imagePosition = .imageOnly
        trash.contentTintColor = .labelColor
        trash.setAccessibilityLabel(AppInfo.tr("trash", "корзина"))
        trash.toolTip = deleteTip
        trash.place(in: self, x: 175, y: 12, w: 17, h: 17)
        let toggle = NSSwitch()
        toggle.controlSize = .small
        toggle.state = on ? .on : .off
        toggle.toolTip = switchTip
        // У образца переключатель — NSSwitch с заданной рамкой (205, 8) 34 × 26: дорожка 44 × 20 рисуется по центру
        // рамки и выходит за неё (сверка 24.10). Та же рамка у нас.
        toggle.place(in: self, x: 205, y: 8, w: 34, h: 26)
    }

    required init?(coder: NSCoder) { fatalError("не используется") }
}

/// «Стиль»: коллекция готовых стилей, «Добавить стиль», непрозрачность, список стилей слоя, «Сбросить стиль».
final class StylePanel: ToolPanel {
    init() {
        let t = AppInfo.tr
        super.init(title: ToolPanel.titles["tool.style"]!, header: ToolPanel.headers["tool.style"]!)
        collectionPopup(t("Gradients", "Градиенты"), tip: t("Choose a style collection.", "Выбрать коллекцию стилей."))
        // Цвета плиток — снимок образца 20.10 (верх и низ градиента).
        let grid = PresetGrid(gradients: [
            (NSColor(srgbRed: 218 / 255, green: 84 / 255, blue: 100 / 255, alpha: 1), NSColor(srgbRed: 218 / 255, green: 45 / 255, blue: 44 / 255, alpha: 1)),
            (NSColor(srgbRed: 230 / 255, green: 221 / 255, blue: 233 / 255, alpha: 1), NSColor(srgbRed: 253 / 255, green: 202 / 255, blue: 242 / 255, alpha: 1)),
            (NSColor(srgbRed: 238 / 255, green: 164 / 255, blue: 183 / 255, alpha: 1), NSColor(srgbRed: 254 / 255, green: 132 / 255, blue: 125 / 255, alpha: 1)),
            (NSColor(srgbRed: 254 / 255, green: 204 / 255, blue: 47 / 255, alpha: 1), NSColor(srgbRed: 253 / 255, green: 165 / 255, blue: 42 / 255, alpha: 1)),
            (NSColor(srgbRed: 235 / 255, green: 81 / 255, blue: 188 / 255, alpha: 1), NSColor(srgbRed: 200 / 255, green: 77 / 255, blue: 243 / 255, alpha: 1)),
            (NSColor(srgbRed: 34 / 255, green: 183 / 255, blue: 189 / 255, alpha: 1), NSColor(srgbRed: 27 / 255, green: 147 / 255, blue: 159 / 255, alpha: 1)),
            (NSColor(srgbRed: 45 / 255, green: 203 / 255, blue: 248 / 255, alpha: 1), NSColor(srgbRed: 39 / 255, green: 114 / 255, blue: 238 / 255, alpha: 1)),
        ])
        placeGrid(grid)
        line(202)
        wideButton(t("Add Style", "Добавить стиль"), t("Apply a layer style to this layer.", "Применить стиль слоя к этому слою."),
                   15, 216, 242, prominent: true)
        line(259)
        opacityRow(menu: NSRect(x: 14, y: 267, width: 192, height: 23), field: NSRect(x: 200, y: 267, width: 58, height: 24),
                   slider: NSRect(x: 15, y: 286, width: 242, height: 20),
                   menuTip: t("Choose how the object blends with other objects.", "Выбрать, как объект смешивается с другими объектами в изображении."),
                   fieldTip: t("Set the opacity of the object.", "Задать прозрачность объекта."),
                   sliderTip: t("Adjust the opacity of the object.", "Настроить прозрачность объекта."))
        line(314)
        let names = [t("Fill", "Заливка"), t("Stroke", "Обводка"), t("Inner Shadow", "Внутренняя тень"), t("Shadow", "Тень")]
        for (i, name) in names.enumerated() { styleCard(name, y: 329 + CGFloat(i) * 52) }
        line(57, bottom: true)
        wideButton(t("Reset Style", "Сбросить стиль"), t("Reset the style to its default.", "Сброс стиля на значение по умолчанию."),
                   15, 15, 242, fromBottom: true)
    }

    required init?(coder: NSCoder) { fatalError("не используется") }
}
/// «Эффекты»: коллекция («Эфир») — миниатюры слоя с эффектом, «Добавить эффект», пустой список с подсказкой,
/// внизу «сравнить» и «Сбросить».
final class EffectsPanel: ToolPanel {
    private let grid = PresetGrid(gradients: [])
    private var thumbKey: String?

    init() {
        let t = AppInfo.tr
        super.init(title: ToolPanel.titles["tool.effects"]!, header: ToolPanel.headers["tool.effects"]!)
        collectionPopup(t("Ether", "Эфир"), tip: t("Choose an effects collection.", "Выбрать коллекцию эффектов."))
        placeGrid(grid)
        line(202)
        wideButton(t("Add Effect", "Добавить эффект"), t("Apply an effect to this layer.", "Применить эффект к этому слою."),
                   15, 216, 242, prominent: true)
        line(259)
        // Пустой список: картинка 76 × 76 и текст под ней — по середине области списка (у образца 274…877 при высоте
        // 940: картинка с 495, текст с 581, 172 × 62).
        let area = NSLayoutGuide()
        addLayoutGuide(area)
        let icon = NSImageView(image: TracedPanelIcons.image("create_effects"))
        icon.setAccessibilityLabel("create effects icon")
        icon.imageScaling = .scaleNone
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        let hint = NSTextField(wrappingLabelWithString: t("To apply an effect to this layer, click the Add Effect button above.",
                                                          "Чтобы применить эффект к этому слою, нажмите выше на кнопке «Добавить эффект»."))
        // Средний 12: при полужирном строка на 4,5 % шире, чем у образца, и перенос другой (сверка 20.10).
        hint.font = .systemFont(ofSize: 12, weight: .medium)
        hint.alignment = .center
        hint.isEnabled = false
        hint.textColor = .labelColor
        hint.preferredMaxLayoutWidth = 170
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)
        NSLayoutConstraint.activate([
            area.topAnchor.constraint(equalTo: topAnchor, constant: 274),
            area.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -63),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 76),
            icon.heightAnchor.constraint(equalToConstant: 76),
            icon.topAnchor.constraint(equalTo: area.centerYAnchor, constant: 495 - 575.5),
            hint.centerXAnchor.constraint(equalTo: centerXAnchor),
            hint.widthAnchor.constraint(equalToConstant: 170),
            hint.topAnchor.constraint(equalTo: area.centerYAnchor, constant: 582 - 575.5),
        ])
        compareAndReset(compareTip: t("Show how the objects look without any effects.", "Показать, как выглядят объекты без каких-либо эффектов."),
                        resetTip: t("Reset the effects of the object to their defaults.", "Сбросить эффекты объекта к значениям по умолчанию."))
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    /// Миниатюры коллекции «Эфир» — выбранный слой с эффектом. Пока эффектов нет, это приближение Core Image
    /// к снимку образца 20.10 (приглушённый с виньеткой, яркий, светлый тёплый, тёмный красный, тёмный старинный,
    /// блёклый розовый, умеренный); точные — вместе с самими эффектами.
    override func update() {
        guard let controller, let layer = controller.session.primaryLayer else { grid.images = []; return }
        let key = "\(layer.id)|\(layer.position.x),\(layer.position.y)|\(controller.session.document.layers.count)"
        guard key != thumbKey, let base = controller.layersPanel.layerThumbnail(layer).cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        thumbKey = key
        let source = CIImage(cgImage: base)
        let chains: [[(String, [String: Any])]] = [
            [("CIColorControls", ["inputSaturation": 0.85]), ("CIVignette", ["inputIntensity": 0.8, "inputRadius": 1.2])],
            [("CIColorControls", ["inputSaturation": 1.7, "inputContrast": 1.15])],
            [("CIColorControls", ["inputSaturation": 0.8, "inputBrightness": 0.08, "inputContrast": 0.85]),
             ("CITemperatureAndTint", ["inputNeutral": CIVector(x: 6500, y: 0), "inputTargetNeutral": CIVector(x: 5200, y: 0)])],
            [("CIColorControls", ["inputBrightness": -0.12, "inputContrast": 1.1]),
             ("CIColorMatrix", ["inputGVector": CIVector(x: 0, y: 0.6, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 0.55, w: 0)]),
             ("CIVignette", ["inputIntensity": 1.0, "inputRadius": 1.0])],
            [("CIPhotoEffectTransfer", [:]), ("CIColorControls", ["inputBrightness": -0.1]), ("CIVignette", ["inputIntensity": 1.0, "inputRadius": 1.0])],
            [("CIColorControls", ["inputSaturation": 0.45, "inputBrightness": 0.15, "inputContrast": 0.7]),
             ("CIColorMatrix", ["inputBiasVector": CIVector(x: 0.08, y: 0, z: 0.02, w: 0)])],
            [("CIColorControls", ["inputSaturation": 1.1, "inputContrast": 1.05]), ("CIVignette", ["inputIntensity": 0.5, "inputRadius": 1.2])],
        ]
        let context = CIContext()
        grid.images = chains.map { chain in
            var image = source
            for (name, params) in chain {
                guard let f = CIFilter(name: name) else { continue }
                f.setValue(image, forKey: kCIInputImageKey)
                for (k, v) in params { f.setValue(v, forKey: k) }
                image = f.outputImage ?? image
            }
            guard let cg = context.createCGImage(image, from: source.extent) else { return NSImage() }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
    }
}

/// «Заливка цветом»: цвет, непрозрачность, флажки; внизу «Сбросить».
final class ColorFillPanel: ToolPanel {
    init() {
        let t = AppInfo.tr
        super.init(title: ToolPanel.titles["tool.fill"]!, header: [])
        label(t("Color", "Цвет"), 14, 59, 31, 17)
        // Образец цвета с пипеткой (замер 20.10: плашка 58 × 24 с x = 171, кнопка пипетки 24 × 24 с x = 232).
        put(EyedropperColorWell(), 170, 55, 87, 26)
        line(137)
        opacityRow(menu: NSRect(x: 15, y: 88, width: 181, height: 23), field: NSRect(x: 199, y: 88, width: 58, height: 22),
                   slider: NSRect(x: 15, y: 106, width: 242, height: 20),
                   menuTip: t("Choose how the color blends with the filled object.", "Выбрать, как цвет смешивается с заполняемым объектом."),
                   fieldTip: t("Set the fill opacity.", "Задайте прозрачность заполнения."),
                   sliderTip: t("Adjust the fill opacity.", "Настроить прозрачность заливки."))
        checkbox(t("Sample All Layers", "Все слои — образцы"), on: false,
                 tip: t("Select to make the Color Fill tool consider every object in the image.",
                        "Выберите, чтобы инструмент «Заливка цветом» учитывал каждый объект в изображении."), 15, 149)
        checkbox(t("Smooth Edges", "Сглаженные края"), on: true,
                 tip: t("Choose natural smoothing when filling an outline.", "Выберите естественное сглаживание при заливке контура."), 15, 173)
        checkbox(t("Preserve Transparency", "Сохранить прозрачность"), on: false,
                 tip: t("Choose to fill only non-transparent areas.", "Выбрать заливку только непрозрачных областей."), 15, 197)
        line(232)
        resetOnly(t("Reset all your current changes.", "Сбросить все ваши текущие изменения."))
    }

    required init?(coder: NSCoder) { fatalError("не используется") }
}

/// «Исправить»: размер кисти, «Все слои — образцы», «Исправить выбранное»; внизу «сравнить» и «Сбросить».
final class RepairPanel: ToolPanel {
    init() {
        let t = AppInfo.tr
        super.init(title: ToolPanel.titles["tool.repair"]!, header: [])
        sliderRow(t("Brush Size", "Размер кисти"), 15, 15, 51,
                  fieldTip: t("Set the brush size of the Repair tool.", "Задать размер кисти инструмента исправления."),
                  sliderTip: t("Adjust the brush size for the Repair tool.", "Настроить размер кисти для инструмента «Восстановление»."))
        line(100)
        checkbox(t("Sample All Layers", "Все слои — образцы"), on: false,
                 tip: t("Select to make the Repair tool consider every object in the image.",
                        "Выбрать, чтобы инструмент «Исправление» учитывал каждый объект в изображении."), 15, 117)
        line(153)
        disable(wideButton(t("Repair Selection", "Исправить выбранное"), t("Repair the entire selected area of the image.", "Исправить всю выбранную область изображения."), 15, 167, 242))
        line(210)
        compareAndReset(compareTip: t("Show how the image looked before the repairs.", "Показать, как выглядело изображение до исправлений в нем."),
                        resetTip: t("Reset all your current changes.", "Сбросить все ваши текущие изменения."))
    }

    required init?(coder: NSCoder) { fatalError("не используется") }
}

/// «Исказить»: размер кисти и сила; внизу «сравнить» и «Сбросить».
final class DistortPanel: ToolPanel {
    init() {
        let t = AppInfo.tr
        super.init(title: ToolPanel.titles["tool.distort"]!, header: [])
        sliderRow(t("Brush Size", "Размер кисти"), 25, 15, 51,
                  fieldTip: t("Set the brush size for the Distort tool.", "Задать размер кисти для инструмента искажения."),
                  sliderTip: t("Adjust the brush size for the Distort tool.", "Настроить размер кисти для инструмента «Искажение»."))
        sliderRow(t("Strength", "Сила"), 50, 15, 89,
                  fieldTip: t("Set the intensity of the distort effect.", "Задать интенсивность эффекта искажения."),
                  sliderTip: t("Adjust the intensity of the distort effect.", "Настроить интенсивность эффекта искажения."))
        line(138)
        compareAndReset(compareTip: t("Show how the image looked before distorting it.", "Показать внешний вид изображения до его искажения."),
                        resetTip: t("Reset all your current changes.", "Сбросить все ваши текущие изменения."))
    }

    required init?(coder: NSCoder) { fatalError("не используется") }
}

extension TracedPanelIcons {
    /// Картинка панели по обведённым контурам: слабые (пустые состояния, непрозрачность до 15 %) — белым поверх,
    /// слой за слоем; значки — шаблоном, каждый уровень заменяет прозрачность под собой (как значки полосы).
    static func image(_ name: String) -> NSImage {
        guard let (size, layers) = icons[name] else { return symbolImage(name) }
        let faint = (layers.first?.0 ?? 1) < 0.1
        let img = NSImage(size: size, flipped: true) { _ in
            if !faint { NSGraphicsContext.current?.compositingOperation = .copy }
            for (opacity, d) in layers {
                let path = ToolIcons.tracedPath(d)
                path.windingRule = .evenOdd
                (faint ? NSColor(white: 1, alpha: opacity) : NSColor(white: 0, alpha: opacity)).setFill()
                path.fill()
            }
            return true
        }
        img.isTemplate = !faint
        return img
    }

    /// Системные значки на случай, когда обведённых контуров нет (сборка без них).
    private static let fallbackSymbols: [String: (String, CGFloat)] = [
        "create_effects": ("sparkles", 48), "create_adjustments": ("slider.horizontal.3", 48),
        "crop_rotate_left": ("rotate.left", 13), "crop_rotate_right": ("rotate.right", 13),
        "flip_horizontal": ("arrow.left.and.right.righttriangle.left.righttriangle.right", 12),
        "flip_vertical": ("arrow.up.and.down.righttriangle.up.righttriangle.down", 12),
        "straighten_left": ("level", 13), "straighten_right": ("level", 13),
        "perspective_top": ("perspective", 13), "perspective_bottom": ("perspective", 13),
        "perspective_left": ("perspective", 13), "perspective_right": ("perspective", 13),
        "grid_thirds": ("squareshape.split.3x3", 12),
    ]

    private static func symbolImage(_ name: String) -> NSImage {
        guard let (symbol, size) = fallbackSymbols[name],
              let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size, weight: .regular)) else { return NSImage() }
        img.isTemplate = true
        return img
    }

    /// Та же картинка, закрашенная цветом (для кнопок, которые не красят шаблон сами).
    static func image(_ name: String, tint: NSColor) -> NSImage {
        let template = image(name)
        return NSImage(size: template.size, flipped: false) { rect in
            template.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
#endif
