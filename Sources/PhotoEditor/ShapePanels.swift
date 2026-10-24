#if canImport(AppKit)
import AppKit
import EditorApp

/// «Перо» и «Фигура» (замеры образца 20.10): «Добавить стиль» и стили слоя будущей фигуры — «Заливка» и
/// «Обводка» карточками, раскрытая карточка со своими настройками. Координаты внутри карточки — от верха её строки.

/// «Перо»: «Добавить стиль», «Заливка» (выкл.), «Обводка» (вкл., раскрыта); внизу «Сбросить стиль».
final class PenPanel: ToolPanel {
    init() {
        let t = AppInfo.tr
        super.init(title: ToolPanel.titles["tool.pen"]!, header: [])
        wideButton(t("Add Style", "Добавить стиль"), t("Apply a layer style to this layer.", "Применить стиль слоя к этому слою."),
                   15, 57, 242, prominent: true)
        line(100)
        styleCard(t("Fill", "Заливка"), y: 115)
        let stroke = styleCard(t("Stroke", "Обводка"), on: true, y: 167, height: 203)
        fillTypePopup(t("Choose the stroke fill type.", "Выбрать тип заливки штриха."), in: stroke)
        let style = StrokeStyleButton()
        style.toolTip = t("Choose a stroke style preset or adjust the stroke settings.", "Выбрать набор стилей штриха или отрегулировать настройки штриха.")
        style.place(in: stroke, x: 27, y: 76, w: 136, h: 26)
        let width = NSTextField()
        width.cell = CenteredTextFieldCell(textCell: "3 px")
        width.isEditable = true
        width.isBezeled = false
        width.drawsBackground = false
        width.alignment = .right
        width.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        width.toolTip = t("Set the stroke width.", "Задать ширину штриха.")
        // Подложка поля 54 × 24 цвета 84 (на карточке), число кончается в 7 точках от её правого края.
        let plate = NSView()
        plate.wantsLayer = true
        plate.layer?.backgroundColor = NSColor(white: 84 / 255, alpha: 1).cgColor
        plate.layer?.cornerRadius = 4
        plate.frame = NSRect(x: 170, y: 77, width: 54, height: 24)
        stroke.addSubview(plate)
        width.place(in: stroke, x: 169, y: 77, w: 52, h: 24)
        let stepper = NSStepper()
        stepper.controlSize = .small
        stepper.minValue = 0
        stepper.maxValue = 1000
        stepper.integerValue = 3
        stepper.toolTip = t("Adjust the stroke width.", "Настроить ширину штриха.")
        stepper.place(in: stroke, x: 228, y: 80, w: 15, h: 17)
        EyedropperColorWell().place(in: stroke, x: 27, y: 111, w: 87, h: 26)
        label(t("Opacity", "Непрозрачность"), 27, 147, 101, 17, in: stroke)
        numberField("100\u{00A0}%", tip: t("Set the stroke opacity.", "Задать прозрачность штриха."), NSRect(x: 187, y: 144, width: 58, height: 24), in: stroke)
        let slider = NSSlider(value: 100, minValue: 0, maxValue: 100, target: self, action: #selector(ToolPanel.noAction(_:)))
        slider.controlSize = .small
        slider.trackFillColor = Theme.accent
        slider.toolTip = t("Adjust the stroke opacity.", "Настроить прозрачность штриха.")
        slider.place(in: stroke, x: 27, y: 160, w: 218, h: 24)
        line(57, bottom: true)
        wideButton(t("Reset Style", "Сбросить стиль"), t("Reset the shape layer style to the default style.", "Сбросить стиль слоя фигуры к стилю по умолчанию."),
                   15, 15, 242, fromBottom: true)
    }

    required init?(coder: NSCoder) { fatalError("не используется") }
}

/// «Фигура»: карточка фигуры («Прямоугольник»), «Добавить стиль», «Заливка» (вкл., раскрыта), «Обводка» (выкл.);
/// внизу недоступная «Сбросить стиль».
final class ShapePanel: ToolPanel {
    init() {
        let t = AppInfo.tr
        super.init(title: ToolPanel.titles["tool.shape"]!, header: [])
        put(BrushCard(name: t("Rectangle", "Прямоугольник"), size: "257 × 257 px", stroke: .square), 15, 55, 242, 49)
        line(117)
        wideButton(t("Add Style", "Добавить стиль"), t("Apply a layer style to this layer.", "Применить стиль слоя к этому слою."),
                   15, 131, 242, prominent: true)
        line(174)
        let fill = styleCard(t("Fill", "Заливка"), on: true, y: 189, height: 168)
        fillTypePopup(t("Choose the fill type.", "Выбрать тип заливки."), in: fill)
        let well = EyedropperColorWell()
        well.color = NSColor(srgbRed: 0, green: 0.635, blue: 1, alpha: 1)
        well.place(in: fill, x: 27, y: 76, w: 87, h: 26)
        opacityRow(menu: NSRect(x: 27, y: 110, width: 180, height: 23), field: NSRect(x: 187, y: 109, width: 58, height: 24),
                   slider: NSRect(x: 27, y: 127, width: 218, height: 20),
                   menuTip: t("Choose how the fill blends with the filled object.", "Выбрать, как заливка смешивается с заливаемым объектом."),
                   fieldTip: t("Set the fill opacity.", "Задайте прозрачность заполнения."),
                   sliderTip: t("Adjust the fill opacity.", "Настроить прозрачность заливки."), in: fill)
        styleCard(t("Stroke", "Обводка"), y: 357)
        line(57, bottom: true)
        disable(wideButton(t("Reset Style", "Сбросить стиль"), t("Reset the shape layer style to the default style.", "Сбросить стиль слоя фигуры к стилю по умолчанию."),
                           15, 15, 242, fromBottom: true))
    }

    required init?(coder: NSCoder) { fatalError("не используется") }
}

extension ToolPanel {
    /// Тип заливки («Цвет», «Градиент», «Картинка») в раскрытой карточке: (27, 41) 218 × 26.
    func fillTypePopup(_ tip: String, in card: NSView) {
        let t = AppInfo.tr
        let popup = NSPopUpButton()
        popup.addItems(withTitles: [t("Color", "Цвет"), t("Gradient", "Градиент"), t("Image", "Изображение")])
        popup.toolTip = tip
        // На карточке подложка списка у образца 96 (у нас без цвета 85 — сверка 24.10).
        popup.bezelColor = NSColor(white: 96 / 255, alpha: 1)
        popup.place(in: card, x: 27, y: 41, w: 218, h: 26)
    }
}

/// Стиль штриха («Перо»): подложка 132 × 24 цвета 85 (на карточке) со скруглением 4, белая линия 2 точки
/// посередине (19…101 от края кнопки) и «⌄» серым справа — снимок 24.10. В Accessibility — кнопка.
final class StrokeStyleButton: NSButton {
    init() {
        super.init(frame: .zero)
        isBordered = false
        title = ""
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 85 / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 1, y: 0, width: 132, height: 24), xRadius: 4, yRadius: 4).fill()
        NSColor.white.setFill()
        NSRect(x: 19, y: 11, width: 83, height: 2).fill()
        if let image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold).applying(.init(paletteColors: [NSColor(white: 1, alpha: 0.75)]))) {
            let s = image.size
            image.draw(in: NSRect(x: 117.5 - s.width / 2, y: 12 - s.height / 2, width: s.width, height: s.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}
#endif
