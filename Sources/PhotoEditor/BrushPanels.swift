#if canImport(AppKit)
import AppKit
import EditorApp

/// Панели кистей и масштаба (замеры образца 20.10; разделители — по пикселям
/// снимка): «Резкость», «Осветление», «Повысить насыщенность», «Штамп»,
/// «Рисовать», «Стереть», «Изменить масштаб».

/// «Резкость», «Осветление», «Повысить насыщенность»: размер кисти, мягкость, сила, диапазон тонов;
/// внизу «сравнить» и «Сбросить». У трёх панелей одна раскладка, разные только подсказки.
final class ToneBrushPanel: ToolPanel {
    init(_ id: String) {
        let t = AppInfo.tr
        super.init(title: ToolPanel.titles[id]!, header: [])
        // Подсказки образца: (размер — поле, ползунок; мягкость — поле, ползунок; сила — поле, ползунок; «сравнить»).
        let tips: [String] = switch id {
        case "tool.sharpen": [
            t("Set the brush size of the Sharpen tool.", "Задайте размер кисти инструмента Резкость."),
            t("Adjust the brush size for the Sharpen tool.", "Настроить размер кисти для инструмента «Резкость»."),
            t("Set how much to soften the edges of the Sharpen tool brush.", "Задайте, насколько смягчить края инструмента кисти Резкость."),
            t("Adjust how much to soften the edges of the Sharpen tool brush.", "Настроить степень смягчения краев кисти для инструмента «Резкость»."),
            t("Set the strength of the sharpening effect.", "Задайте силу эффекта резкости."),
            t("Adjust the intensity of the sharpening effect.", "Настроить интенсивность эффекта резкости."),
            t("Show how the image looked before sharpening objects within it.", "Покажите, как выглядело изображение до повышения резкости объектов внутри него."),
        ]
        case "tool.lighten": [
            t("Set the brush size of the Lighten tool.", "Задайте размер кисти инструмента осветления."),
            t("Adjust the brush size for the Lighten tool.", "Настроить размер кисти для инструмента «Осветление»."),
            t("Set how much to soften the edges of the Lighten tool brush.", "Задайте, насколько смягчить края инструмента кисти осветления."),
            t("Adjust how much to soften the edges of the Lighten tool brush.", "Настроить степень смягчения краев кисти для инструмента «Осветление»."),
            t("Set the strength of the lightening effect.", "Задайте силу эффекта осветления."),
            t("Adjust the intensity of the lightening effect.", "Настроить интенсивность эффекта осветления."),
            t("Show how the image looked before lightening within it.", "Показать, как выглядело изображение до осветления внутри него."),
        ]
        default: [
            t("Set the brush size of the Saturate tool.", "Задать размер кисти инструмента насыщенности."),
            t("Adjust the brush size for the Saturate tool.", "Настроить размер кисти для инструмента «Насыщенность»."),
            t("Set how much to soften the edges of the Saturate tool brush.", "Задайте, насколько смягчить края инструмента кисти насыщенности."),
            t("Adjust how much to soften the edges of the Saturate tool brush.", "Настроить степень смягчения краев кисти для инструмента «Насыщенность»"),
            t("Set the strength of the saturation effect.", "Задайте силу эффекта насыщенности."),
            t("Adjust the intensity of the saturation effect.", "Настроить интенсивность эффекта насыщенности."),
            t("Show how the image looked before saturating objects within it.", "Показать, как выглядело изображение до усиления насыщенности объектов внутри него."),
        ]
        }
        sliderRow(t("Brush Size", "Размер кисти"), 25, 15, 51, fieldTip: tips[0], sliderTip: tips[1])
        sliderRow(t("Softness", "Мягкость"), 100, 15, 89, fieldTip: tips[2], sliderTip: tips[3])
        line(138)
        sliderRow(t("Strength", "Сила"), 50, 15, 148, fieldTip: tips[4], sliderTip: tips[5])
        line(197)
        // Диапазон тонов: строки с 210, ширины названий и пояснений — по тексту образца.
        let ranges = SelectionModeList(rows: [
            (t("All", "Все"), t("The entire color range of the image.", "Весь цветовой диапазон изображения."), 210),
            (t("Shadows", "Тени"), t("The darkest areas of the image.", "Самые темные области изображения."), 251),
            (t("Midtones", "Полутона"), t("Halfway between the light and dark areas.", "Посредине между светлыми и темными местами."), 292),
            (t("Highlights", "Акценты"), t("The lightest areas of the image.", "Самые светлые области изображения."), 346),
        ], widths: [199, 194, 220, 198])
        ranges.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ranges)
        NSLayoutConstraint.activate([
            ranges.leadingAnchor.constraint(equalTo: leadingAnchor),
            ranges.widthAnchor.constraint(equalToConstant: Theme.optionsWidth),
            ranges.topAnchor.constraint(equalTo: topAnchor),
            ranges.heightAnchor.constraint(equalToConstant: 390),
        ])
        line(392)
        compareAndReset(compareTip: tips[6], resetTip: t("Reset all your current changes.", "Сбросить все ваши текущие изменения."))
    }

    required init?(coder: NSCoder) { fatalError("не используется") }
}

/// «Штамп»: размер кисти, мягкость, непрозрачность, три флажка; внизу «сравнить» и «Сбросить».
final class ClonePanel: ToolPanel {
    init() {
        let t = AppInfo.tr
        super.init(title: ToolPanel.titles["tool.clone"]!, header: [])
        sliderRow(t("Brush Size", "Размер кисти"), 25, 15, 51,
                  fieldTip: t("Set the brush size of the Clone tool.", "Задайте размер кисти инструмента «Штамп»."),
                  sliderTip: t("Adjust the brush size for the Clone tool.", "Настроить размер кисти для инструмента «Штамп»."))
        sliderRow(t("Softness", "Мягкость"), 50, 15, 89,
                  fieldTip: t("Set how much to soften the edges of the Clone tool brush.", "Задайте, насколько смягчить края кисти инструмента «Штамп»."),
                  sliderTip: t("Adjust how much to soften the edges of the Clone tool brush.", "Настроить степень смягчения краев кисти в инструменте «Штамп»."))
        opacityRow(menu: NSRect(x: 15, y: 127, width: 181, height: 23), field: NSRect(x: 199, y: 127, width: 58, height: 22),
                   slider: NSRect(x: 15, y: 145, width: 242, height: 20),
                   menuTip: t("Choose how to blend strokes with the object in the image.", "Выбрать, как смешать штрихи с объектом в изображении."),
                   fieldTip: t("Set the fill opacity.", "Задайте прозрачность заполнения."),
                   sliderTip: t("Adjust the fill opacity.", "Настроить прозрачность заливки."))
        line(176)
        checkbox(t("Sample All Layers", "Все слои — образцы"), on: false,
                 tip: t("Select to make the Clone tool consider every layer in the image.",
                        "Выбрать, чтобы инструмент «Штамп» учитывал каждый слой в изображении."), 15, 188)
        checkbox(t("Fixed Source Location", "Фиксировать место источника"), on: true,
                 tip: t("Always sample the same part of the image with each new stroke.",
                        "Всегда выбирать образец той же части изображения при каждом новом штрихе."), 15, 212)
        checkbox(t("Show Source Marker", "Показать маркер источника"), on: true,
                 tip: t("Choose to show the clone source marker.", "Выбрать показ маркера штампа источника."), 15, 236)
        line(271)
        compareAndReset(compareTip: t("Show how the image looked before cloning within it.", "Показать, как выглядело изображение до клонирования штампом в нем."),
                        resetTip: t("Reset all your current changes.", "Сбросить все ваши текущие изменения."))
    }

    required init?(coder: NSCoder) { fatalError("не используется") }
}

/// «Рисовать» и «Стереть»: карточка кисти, (цвет), размер, мягкость, непрозрачность, «Дополнительные настройки»,
/// «Сглаживание»; у «Рисовать» внизу «Штрих кистью…».
final class BrushPanel: ToolPanel {
    init(_ id: String) {
        let t = AppInfo.tr
        let paint = id == "tool.paint"
        super.init(title: ToolPanel.titles[id]!, header: [])
        let card = paint ? BrushCard(name: t("Jimbo Chisel", "Резец Jimbo"), size: "40 px", stroke: .chisel)
                         : BrushCard(name: t("Basic Hard", "Обычная жесткая"), size: "100 px", stroke: .round)
        put(card, 15, 55, 242, 49)
        line(117)
        // Под карточкой у образца всё сдвинуто на 35 точек у «Рисовать» (строка «Цвет»).
        let d: CGFloat = paint ? 35 : 0
        if paint {
            label(t("Color", "Цвет"), 14, 133, 31, 17)
            put(EyedropperColorWell(), 170, 129, 87, 26)
        }
        // Размер в px: шкала нелинейная, ручка у образца при 100 px — на 11 %, при 40 px — на 6 % (замер 20.10).
        sliderRow(t("Brush Size", "Размер кисти"), paint ? 40 : 100, unit: " px", position: paint ? 6.3 : 10.8, 15, 127 + d,
                  fieldTip: t("Set the brush size.", "Задать размер кисти."), sliderTip: t("Adjust the brush size.", "Настроить размер кисти."))
        sliderRow(t("Softness", "Мягкость"), 0, 15, 165 + d,
                  fieldTip: t("Set how much to soften the edges of the brush.", "Задайте, насколько смягчить края кисти."),
                  sliderTip: t("Adjust how much to soften the edges of the brush.", "Настроить степень смягчения краев кисти."))
        if paint {
            opacityRow(menu: NSRect(x: 15, y: 238, width: 181, height: 23), field: NSRect(x: 199, y: 238, width: 58, height: 22),
                       slider: NSRect(x: 15, y: 256, width: 242, height: 20), value: 49,
                       menuTip: t("Choose how to blend strokes with the object in the image.", "Выбрать, как смешать штрихи с объектом в изображении."),
                       fieldTip: t("Set the brush opacity.", "Задать прозрачность кисти."),
                       sliderTip: t("Adjust the brush opacity.", "Настроить прозрачность кисти."))
        } else {
            sliderRow(t("Opacity", "Непрозрачность"), 100, 15, 203,
                      fieldTip: t("Set the brush opacity.", "Задать прозрачность кисти."), sliderTip: t("Adjust the brush opacity.", "Настроить прозрачность кисти."))
        }
        line(252 + d)
        // «> Дополнительные настройки»: стрелка — переключатель 194 × 17, подпись 12 жирная справа от неё.
        let tip = t("Show or hide advanced brush settings.", "Показать/скрыть дополнительные настройки кисти.")
        let more = DisclosureToggle()
        more.toolTip = tip
        put(more, 15, 265 + d, 194, 17)
        label(t("Advanced Settings", "Дополнительные настройки"), 29, 265 + d, 180, 17, weight: .bold).toolTip = tip
        line(294 + d)
        let smooth = NSButton(checkboxWithTitle: t("Smoothing", "Сглаживание"), target: self, action: #selector(ToolPanel.noAction(_:)))
        smooth.font = .systemFont(ofSize: 12)
        smooth.state = .off
        smooth.toolTip = t("Choose to automatically smooth brush strokes.", "Выбрать автоматическое сглаживание мазков кисти.")
        put(smooth, 15, 307 + d, 103, 24)
        let amount = ValueCombo("10\u{00A0}%", tip: t("Choose how much smoothing to apply to brush strokes.", "Выбрать, насколько сильно должно быть применено сглаживание мазка кисти."))
        amount.place(in: self, menu: NSRect(x: 176, y: 308 + d, width: 81, height: 26))
        amount.isEnabled = false
        line(347 + d)
        if paint {
            line(57, bottom: true)
            wideButton(t("Stroke with Brush…", "Штрих кистью…"),
                       t("Stroke the selection, shape or layer outline with the brush.", "Проведите кистью по выбранной области, фигуре или контуру слоя."),
                       15, 15, 242, fromBottom: true)
        }
    }

    required init?(coder: NSCoder) { fatalError("не используется") }
}

/// Карточка выбранной кисти (у образца — переключатель 242 × 49, по нажатию открывает набор кистей):
/// подложка 38 со скруглением и светлой обводкой, слева мазок кисти, справа название 12 полужирным, размер 10
/// серым и стрелка вниз. Мазки — векторные приближения превью образца (снимок 20.10).
final class BrushCard: NSButton {
    enum Stroke { case round, chisel, square }
    private let name: String
    private let size: String
    private let stroke: Stroke

    init(name: String, size: String, stroke: Stroke) {
        self.name = name
        self.size = size
        self.stroke = stroke
        super.init(frame: .zero)
        setButtonType(.pushOnPushOff)
        isBordered = false
        title = name
        toolTip = name
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let plate = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor(white: 38 / 255, alpha: 1).setFill()
        plate.fill()
        NSColor(white: 79 / 255, alpha: 1).setStroke()
        plate.lineWidth = 1
        plate.stroke()

        // Мазок: верхняя и нижняя кромки — многочлены 6-й степени от x (координаты от угла карточки), подобраны
        // по превью образца 20.10 (расхождение кромок ≤ 1 точки).
        // У «Фигуры» вместо мазка — квадрат 30 × 29 цвета 222, текст левее (снимок 20.10).
        if stroke == .square {
            NSColor(white: 222 / 255, alpha: 1).setFill()
            NSRect(x: 11, y: 9, width: 30, height: 29).fill()
        }
        let (x0, x1, top, bottom): (CGFloat, CGFloat, [Double], [Double]) = switch stroke {
        case .square: (0, 0, [], [])
        case .round: (11, 94,
                      [7.027229e-09, -2.032397e-06, 2.288167e-04, -1.289178e-02, 3.941118e-01, -6.438655e+00, 5.765585e+01],
                      [-6.106913e-09, 2.058145e-06, -2.761534e-04, 1.847395e-02, -6.302164e-01, 1.008783e+01, -2.983196e+01])
        case .chisel: (14, 92,
                       [3.843989e-09, -1.251603e-06, 1.622530e-04, -1.093857e-02, 4.196714e-01, -8.860529e+00, 9.304444e+01],
                       [-2.825959e-09, 8.851564e-07, -1.111573e-04, 6.821757e-03, -1.992989e-01, 2.352575e+00, 1.986987e+01])
        }
        func value(_ c: [Double], _ x: CGFloat) -> CGFloat { CGFloat(c.reduce(0) { $0 * Double(x) + $1 }) }
        let path = NSBezierPath()
        if top.isEmpty { return drawText() }
        let steps = 80
        for i in 0...steps {
            let x = x0 + (x1 - x0) * CGFloat(i) / CGFloat(steps)
            let p = NSPoint(x: x, y: value(top, x))
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        for i in (0...steps).reversed() {
            let x = x0 + (x1 - x0) * CGFloat(i) / CGFloat(steps)
            path.line(to: NSPoint(x: x, y: max(value(bottom, x), value(top, x))))
        }
        path.close()
        NSColor(white: 0.86, alpha: 1).setFill()
        path.fill()
        drawText()
    }

    private func drawText() {
        let textX: CGFloat = stroke == .square ? 52 : 108
        let textW: CGFloat = stroke == .square ? 150 : 92
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (name as NSString).draw(in: NSRect(x: textX, y: 9, width: textW, height: 16), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ])
        (size as NSString).draw(in: NSRect(x: textX, y: 25, width: textW, height: 14), withAttributes: [
            .font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor(white: 121 / 255, alpha: 1),
        ])
        if let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold).applying(.init(paletteColors: [.labelColor]))) {
            let s = chevron.size
            chevron.draw(in: NSRect(x: 223 - s.width / 2, y: 23.5 - s.height / 2, width: s.width, height: s.height),
                         from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}

/// Стрелка раскрытия раздела (у образца — переключатель AXToggle во всю ширину подписи): «›», раскрыто — «⌄».
final class DisclosureToggle: NSButton {
    init() {
        super.init(frame: .zero)
        setButtonType(.pushOnPushOff)
        isBordered = false
        title = ""
        target = self
        action = #selector(toggled)
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    @objc private func toggled() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let symbol = state == .on ? "chevron.down" : "chevron.right"
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .bold).applying(.init(paletteColors: [.labelColor]))) else { return }
        let s = image.size
        image.draw(in: NSRect(x: 5 - s.width / 2, y: bounds.midY - s.height / 2, width: s.width, height: s.height))
    }
}

/// Поле со значением и меню («100 %», «10 %»): подложка 81 (недоступное — 68) со скруглением 6, текст слева,
/// «⌄» справа. В Accessibility, как у образца, — кнопка меню во всю рамку и поле с числом поверх.
final class ValueCombo {
    let button = ComboPlate(title: " ", target: nil, action: nil)
    let field = NSTextField()

    init(_ text: String, tip: String) {
        button.isBordered = false
        button.toolTip = tip
        field.cell = CenteredTextFieldCell(textCell: text)
        field.isEditable = true
        field.isBezeled = false
        field.drawsBackground = false
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    }

    /// По рамке кнопки меню из замера. Поле у образца — 64 × 24 на 2 точки ниже, но текст в нём на 2 правее
    /// и на 2 выше нашего (сверка 24.10) — ставим по тексту.
    func place(in parent: NSView, menu f: NSRect) {
        button.place(in: parent, x: f.minX, y: f.minY, w: f.width, h: f.height)
        field.place(in: parent, x: f.minX + 2, y: f.minY, w: 64, h: 24)
    }

    var isEnabled: Bool {
        get { field.isEnabled }
        set {
            field.isEnabled = newValue
            // Недоступный текст у образца ярче, чем у AppKit: 147 на подложке 68.
            field.textColor = newValue ? .labelColor : NSColor(white: 1, alpha: 0.42)
            button.isEnabled = newValue
            button.needsDisplay = true
        }
    }
}

/// Подложка поля со значением: сама рисует плашку и «⌄» (отдельная картинка попадала в Accessibility как
/// «перейти вниз»), в Accessibility — кнопка меню.
final class ComboPlate: NSButton {
    /// Значение, нарисованное прямо на подложке («22 px» у «Текста»: там у образца нет отдельного поля).
    var valueText: String?

    override func accessibilityRole() -> NSAccessibility.Role? { .menuButton }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: (isEnabled ? 81 : 68) / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        if let valueText {
            let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            (valueText as NSString).draw(at: NSPoint(x: 9, y: (bounds.height - (font.ascender - font.descender)) / 2),
                                         withAttributes: [.font: font, .foregroundColor: NSColor.labelColor])
        }
        guard let image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .heavy)
                .applying(.init(paletteColors: [NSColor(white: 1, alpha: isEnabled ? 1 : 0.27)]))) else { return }
        // Стрелка у образца белая (255), недоступная — 119 на 68; на точку правее и ниже середины.
        let s = image.size
        image.draw(in: NSRect(x: bounds.maxX - 13 - s.width / 2, y: bounds.midY + 1 - s.height / 2, width: s.width, height: s.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

/// «Изменить масштаб»: навигатор (весь документ и рамка видимой части), масштаб, режим, флажки, две кнопки.
final class ZoomPanel: ToolPanel {
    private let navigator = NavigatorView()
    private let level = ValueCombo("100\u{00A0}%", tip: AppInfo.tr("Set the zoom level of the image.", "Задайте уровень масштабирования изображения."))
    /// Шкала симметрична: 100 % — ровно посередине, как у образца (верх ограничен самим масштабом холста).
    private let slider = PointerSlider(value: 0, minValue: log2(Viewport.minScale), maxValue: -log2(Viewport.minScale), target: nil, action: nil)

    init() {
        let t = AppInfo.tr
        super.init(title: ToolPanel.titles["tool.zoom"]!, header: [])
        label(t("Navigator", "Навигатор"), 15, 59, 69, 17, weight: .bold)
        level.place(in: self, menu: NSRect(x: 176, y: 55, width: 81, height: 26))
        level.field.target = self
        level.field.action = #selector(levelEntered(_:))
        // Навигатор (в Accessibility не виден): картинка в рамке 230 × 228 с (21, 90) — по пикселям снимка.
        navigator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(navigator)
        NSLayoutConstraint.activate([
            navigator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 21),
            navigator.topAnchor.constraint(equalTo: topAnchor, constant: 90),
            navigator.widthAnchor.constraint(equalToConstant: 230),
            navigator.heightAnchor.constraint(equalToConstant: 228),
        ])
        let minus = Theme.iconButton("minus.magnifyingglass", t("Zoom out of the image.", "Уменьшить уровень масштабирования изображения."),
                                     size: 12, target: self, action: #selector(zoomOut))
        minus.setAccessibilityLabel(t("zoom out", "уменьшить"))
        put(minus, 13, 332, 20, 18)
        // Ползунок с отметками на концах — у образца ручка-указатель 8 × 16.
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.isContinuous = true
        slider.toolTip = t("Adjust the zoom level of the image.", "Настроить уровень масштабирования изображения.")
        put(slider, 37, 331, 198, 18)
        let plus = Theme.iconButton("plus.magnifyingglass", t("Zoom in on the image.", "Увеличить уровень масштабирования изображения."),
                                    size: 12, target: self, action: #selector(zoomIn))
        plus.setAccessibilityLabel(t("zoom in", "увеличить"))
        put(plus, 239, 332, 20, 18)
        line(362)
        label(t("Mode", "Режим"), 15, 375, 45, 17, weight: .bold)
        let modes = SelectionModeList(rows: [
            (t("Zoom In", "Увеличить"), "", 402),
            (t("Zoom Out", "Уменьшить"), "", 428),
        ], widths: [64, 68])
        modes.translatesAutoresizingMaskIntoConstraints = false
        addSubview(modes)
        NSLayoutConstraint.activate([
            modes.leadingAnchor.constraint(equalTo: leadingAnchor),
            modes.widthAnchor.constraint(equalToConstant: Theme.optionsWidth),
            modes.topAnchor.constraint(equalTo: topAnchor),
            modes.heightAnchor.constraint(equalToConstant: 450),
        ])
        line(460)
        checkbox(t("Scrubby Zoom", "Масштабирование перетягиванием"), on: true,
                 tip: t("Drag left or right on the canvas to zoom the image.", "Перетащить влево или вправо на холсте, чтобы масштабировать изображение."), 15, 477)
        line(512)
        checkbox(t("Auto-Center", "Автоцентрировать"), on: true, tip: "", 15, 524).toolTip = nil
        let hint = NSTextField(labelWithString: t("Automatically center the image.", "Автоцентровка изображения."))
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = NSColor(white: 121 / 255, alpha: 1)
        hint.place(in: self, x: 37, y: 541, w: 236, h: 15)
        line(569)
        let actual = wideButton(t("Actual Size", "Реальный размер"), t("Zoom the image to its actual size.", "Изменить масштаб изображения на его действительный размер."), 15, 583, 242)
        actual.target = self
        actual.action = #selector(actualSize)
        let fit = wideButton(t("Zoom to Fit", "Изменить масштаб под\u{00A0}размер"), t("Zoom the image to fit the \(AppInfo.name) window.", "Изменить масштаб изображения под размер окна \(AppInfo.name)."), 15, 622, 242)
        fit.target = self
        fit.action = #selector(zoomToFit)
        line(665)
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    /// Картинка навигатора — весь документ; update() зовётся при каждой правке, пока выбран этот инструмент.
    override func update() {
        guard let controller else { return }
        if let img = try? controller.canvas.renderer.renderWhole(controller.session.document), let cg = ImageFiles.cgImage(img) {
            navigator.image = cg
        }
        viewportChanged()
    }

    override func viewportChanged() {
        guard let canvas = controller?.canvas else { return }
        let v = canvas.viewport
        slider.doubleValue = log2(v.scale)
        level.field.stringValue = "\(Int((v.scale * 100).rounded()))\u{00A0}%"
        // Видимая часть документа в долях от его размера.
        let a = v.documentPoint(viewX: 0, viewY: 0), b = v.documentPoint(viewX: v.viewWidth, viewY: v.viewHeight)
        let w = Double(max(v.documentWidth, 1)), h = Double(max(v.documentHeight, 1))
        navigator.visible = NSRect(x: max(a.x / w, 0), y: max(a.y / h, 0),
                                   width: min(b.x / w, 1) - max(a.x / w, 0), height: min(b.y / h, 1) - max(a.y / h, 0))
    }

    @objc private func sliderMoved(_ sender: NSSlider) { controller?.canvas.setScale(pow(2, sender.doubleValue)) }
    @objc private func zoomIn() { controller?.run("view.zoomIn") }
    @objc private func zoomOut() { controller?.run("view.zoomOut") }
    @objc private func actualSize() { controller?.run("view.actualSize") }
    @objc private func zoomToFit() { controller?.run("view.zoomFit") }

    @objc private func levelEntered(_ sender: NSTextField) {
        let digits = sender.stringValue.filter { $0.isNumber || $0 == "." || $0 == "," }.replacingOccurrences(of: ",", with: ".")
        if let p = Double(digits), p > 0 { controller?.canvas.setScale(p / 100) } else { viewportChanged() }
    }
}

/// Ползунок как у образца (снимки 20.10): дорожка 4 точки цвета 75 (у масштаба залитая часть — акцент,
/// под концами отметки 2 × 2 цвета 83, ручка-указатель 8 × 16 с острым низом); у «Выпрямить» и перспективы
/// дорожка не залита, ручка — капсула 10 × 18 цвета 225.
final class PointerSlider: NSSlider {
    override class var cellClass: AnyClass? {
        get { PointerSliderCell.self }
        set {}
    }

    /// Ручка-капсула 10 × 18 («Выпрямить», перспектива, размер шрифта).
    var capsule: Bool {
        get { (cell as? PointerSliderCell)?.capsule ?? false }
        set { (cell as? PointerSliderCell)?.capsule = newValue; needsDisplay = true }
    }

    /// Залита ли дорожка до ручки и где отметки: на концах (масштаб), посередине (размер шрифта) или нет.
    func style(filled: Bool, ticks: PointerSliderCell.Ticks) {
        (cell as? PointerSliderCell)?.filled = filled
        (cell as? PointerSliderCell)?.ticks = ticks
        needsDisplay = true
    }
}

final class PointerSliderCell: NSSliderCell {
    enum Ticks { case none, ends, center }
    var capsule = false
    /// Цветная дорожка («Температура», «Оттенок»): градиент слева направо вместо заливки.
    var gradient: [NSColor]?
    var filled = true
    var ticks = Ticks.ends
    private var knobWidth: CGFloat { capsule ? 10 : 8 }

    private func position(in rect: NSRect) -> CGFloat {
        let f = maxValue > minValue ? (doubleValue - minValue) / (maxValue - minValue) : 0
        return rect.minX + knobWidth / 2 + CGFloat(min(max(f, 0), 1)) * (rect.width - knobWidth)
    }

    override func knobRect(flipped: Bool) -> NSRect {
        guard let view = controlView else { return .zero }
        let x = position(in: view.bounds)
        let h: CGFloat = capsule ? 18 : 16
        return NSRect(x: x - knobWidth / 2, y: view.bounds.midY - h / 2, width: knobWidth, height: h)
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        guard let view = controlView else { return }
        let b = view.bounds
        let track = NSRect(x: b.minX, y: b.midY - 2, width: b.width, height: 4)
        // Белый 10 %: на панели 75, на карточке цветокоррекции 91 (снимки 20.10).
        NSColor(white: 1, alpha: 0.1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
        if let gradient {
            NSGradient(colors: gradient)?.draw(in: NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2), angle: 0)
        }
        if filled {
            Theme.accent.setFill()
            NSBezierPath(roundedRect: NSRect(x: track.minX, y: track.minY, width: position(in: b) - track.minX, height: 4), xRadius: 2, yRadius: 2).fill()
        }
        let xs: [CGFloat] = switch ticks {
        case .none: []
        case .ends: [b.minX + 3, b.maxX - 5]
        case .center: [b.midX - 1]
        }
        NSColor(white: 83 / 255, alpha: 1).setFill()
        for x in xs { NSRect(x: x, y: flipped ? b.midY + 4 : b.midY - 6, width: 2, height: 2).fill() }
    }

    override func drawKnob(_ knobRect: NSRect) {
        let r = knobRect
        NSColor(white: 225 / 255, alpha: 1).setFill()
        if capsule {
            NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
            return
        }
        let flipped = controlView?.isFlipped ?? true
        // Скругление 3 сверху, низ сходится за 3 точки до ширины 2.
        let path = NSBezierPath()
        func y(_ d: CGFloat) -> CGFloat { flipped ? r.minY + d : r.maxY - d }
        path.move(to: NSPoint(x: r.minX, y: y(3)))
        path.curve(to: NSPoint(x: r.minX + 3, y: y(0)), controlPoint1: NSPoint(x: r.minX, y: y(1.3)), controlPoint2: NSPoint(x: r.minX + 1.3, y: y(0)))
        path.line(to: NSPoint(x: r.maxX - 3, y: y(0)))
        path.curve(to: NSPoint(x: r.maxX, y: y(3)), controlPoint1: NSPoint(x: r.maxX - 1.3, y: y(0)), controlPoint2: NSPoint(x: r.maxX, y: y(1.3)))
        path.line(to: NSPoint(x: r.maxX, y: y(13)))
        path.line(to: NSPoint(x: r.midX + 1, y: y(16)))
        path.line(to: NSPoint(x: r.midX - 1, y: y(16)))
        path.line(to: NSPoint(x: r.minX, y: y(13)))
        path.close()
        path.fill()
    }
}

/// Образец цвета с пипеткой (у образца в «Рисовать» и «Заливке»; в Accessibility — один образец 87 × 26):
/// плашка цвета 58 × 24 со скруглением 4, справа кнопка пипетки 24 × 24 с подложкой (белый 7 %). Пипетка — выбор цвета
/// с экрана, плашка открывает выбор цвета как обычный образец.
final class EyedropperColorWell: NSColorWell {
    init() {
        super.init(frame: .zero)
        colorWellStyle = .expanded
        color = .black
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    override var isFlipped: Bool { true }

    private var dropperRect: NSRect { NSRect(x: bounds.maxX - 24, y: bounds.minY, width: 24, height: 24) }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 58, height: 24), xRadius: 4, yRadius: 4).fill()
        // Подложка пипетки — белый 7 %: на панели 69, на карточке стиля 84 (снимки 20.10 и 24.10).
        NSColor(white: 1, alpha: 0.07).setFill()
        NSBezierPath(roundedRect: dropperRect, xRadius: 5, yRadius: 5).fill()
        if let image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular).applying(.init(paletteColors: [.labelColor]))) {
            let s = image.size
            image.draw(in: NSRect(x: dropperRect.midX - s.width / 2, y: dropperRect.midY - s.height / 2, width: s.width, height: s.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard dropperRect.contains(p) else { return super.mouseDown(with: event) }
        NSColorSampler().show { [weak self] picked in
            guard let self, let picked else { return }
            self.color = picked
            self.sendAction(self.action, to: self.target)
        }
    }
}

/// Навигатор: документ, вписанный в рамку, и поверх — видимая часть (белая линия снаружи, чёрная внутри,
/// по 1 точке; снимок образца 20.10).
final class NavigatorView: NSView {
    var image: CGImage? { didSet { needsDisplay = true } }
    /// Видимая часть в долях документа (0…1).
    var visible = NSRect(x: 0, y: 0, width: 1, height: 1) { didSet { if visible != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let k = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let w = CGFloat(image.width) * k, h = CGFloat(image.height) * k
        let r = NSRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: r.maxY + r.minY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: r)
        ctx.restoreGState()
        let frame = NSRect(x: r.minX + visible.minX * w, y: r.minY + visible.minY * h, width: visible.width * w, height: visible.height * h)
            .intersection(r)
        guard !frame.isEmpty else { return }
        NSColor.white.setStroke()
        let outer = NSBezierPath(rect: frame.insetBy(dx: 0.5, dy: 0.5))
        outer.lineWidth = 1
        outer.stroke()
        NSColor.black.setStroke()
        let inner = NSBezierPath(rect: frame.insetBy(dx: 1.5, dy: 1.5))
        inner.lineWidth = 1
        inner.stroke()
    }
}
#endif
