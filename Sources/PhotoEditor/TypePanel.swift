#if canImport(AppKit)
import AppKit
import EditorApp

/// «Текст» (замеры образца 20.10): стиль текста («Подпись»), шрифт, начертание и размер, B/I/U/S и доп. опции,
/// цвет, выравнивание по горизонтали и вертикали, «Интервалы», «Отступы», преобразование в фигуру и пиксели.
/// Значки — системные (у образца в Accessibility их системные названия: «выделить жирным», «дом», «конец»…).
final class TypePanel: ToolPanel {
    init() {
        let t = AppInfo.tr
        super.init(title: ToolPanel.titles["tool.type"]!, header: [])
        put(TextStyleCard(title: t("Caption", "Подпись")), 15, 55, 242, 49)
        line(117)
        label(t("Font", "Шрифт"), 15, 130, 46, 17, weight: .bold)
        let family = NSPopUpButton()
        family.addItems(withTitles: ["Helvetica"])
        family.toolTip = t("Choose the font family.", "Выбрать семейство шрифта.")
        put(family, 15, 156, 242, 26)
        let face = NSPopUpButton()
        face.addItems(withTitles: [t("Regular", "Обычный"), t("Bold", "Жирный"), t("Oblique", "Наклонный")])
        face.toolTip = t("Choose the typeface.", "Выбрать гарнитуру шрифта.")
        put(face, 15, 191, 155, 26)
        let size = ComboPlate(title: " ", target: nil, action: nil)
        size.isBordered = false
        size.valueText = "22 px"
        size.toolTip = t("Set the font size.", "Установить размер шрифта.")
        put(size, 176, 191, 81, 26)
        for (symbol, x, tip) in [("textformat.size.smaller", CGFloat(14), t("Decrease the font size.", "Уменьшить размер шрифта.")),
                                 ("textformat.size.larger", CGFloat(240), t("Increase the font size.", "Увеличить размер шрифта."))] {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: symbol.hasSuffix("larger") ? 17 : 16, weight: .regular)) ?? NSImage(), target: nil, action: nil)
            b.isBordered = false
            b.imagePosition = .imageOnly
            b.contentTintColor = .labelColor
            b.toolTip = tip
            put(b, x, 228, 18, 18)
        }
        // Размер: залитая дорожка, ручка-капсула, отметка посередине (ручка при 22 px — на 8 %).
        let slider = PointerSlider(value: 8, minValue: 0, maxValue: 100, target: nil, action: nil)
        slider.capsule = true
        slider.style(filled: true, ticks: .center)
        slider.toolTip = t("Adjust the font size.", "Настроить размер шрифта.")
        put(slider, 37, 227, 198, 20)
        segments(["bold", "italic", "underline", "strikethrough"], widths: [43, 43, 44, 43], selected: [],
                 tips: [t("Make the text bold.", "Сделать текст жирным."), t("Make the text italic.", "Сделать текст курсивным."),
                        t("Underline the text.", "Подчеркнуть текст."), t("Strike through the text.", "Зачеркнутый текст.")],
                 frame: NSRect(x: 15, y: 257, width: 175, height: 26), single: false)
        let more = IconPlateButton(symbol: "gearshape")
        more.toolTip = t("Show more options.", "Показать дополнительные опции.")
        put(more, 196, 257, 58, 26)
        line(296)
        label(t("Color", "Цвет"), 14, 312, 31, 17)
        put(EyedropperColorWell(), 170, 308, 87, 26)
        line(345)
        label(t("Alignment", "Выравнивание"), 15, 358, 96, 17, weight: .bold)
        segments(["text.alignleft", "text.aligncenter", "text.alignright", "text.justify"], widths: [59, 60, 59, 59], selected: [0],
                 tips: [t("Align the text to the left.", "Выровнять текст по левому краю."), t("Center the text.", "Выровнять текст по центру."),
                        t("Align the text to the right.", "Выровнять текст по правому краю."),
                        t("Justify the text.", "Выровнять текст по всей ширине (от центра вправо и влево).")],
                 frame: NSRect(x: 17, y: 384, width: 239, height: 26), single: true)
        segments(["arrow.up.to.line", "arrow.down.and.line.horizontal.and.arrow.up", "arrow.down.to.line"], widths: [79, 80, 79], selected: [1],
                 tips: [t("Align the text to the top of the text box.", "Выровнять текст по верху текстового окна."),
                        t("Align the text to the middle of the text box.", "Выровнять текст по середине текстового окна."),
                        t("Align the text to the bottom of the text box.", "Выровнять текст по низу текстового окна.")],
                 frame: NSRect(x: 16, y: 419, width: 240, height: 26), single: true)
        line(458)
        disclosure(t("Spacing", "Интервалы"), y: 471, width: 87)
        line(500)
        disclosure(t("Indents", "Отступы"), y: 513, width: 70)
        line(542)
        disable(wideButton(t("Convert to Shape", "Преобразовать в\u{00A0}фигуру"), t("Convert the selected text into a shape layer.", "Преобразовать выбранный текст в слой фигуры."), 15, 556, 242))
        disable(wideButton(t("Convert to Pixels", "Преобразовать в\u{00A0}пиксели"), t("Convert the selected text into a pixel (image) layer.", "Преобразовать выбранный текст в пиксельный слой (изображение)."), 15, 595, 242))
        line(638)
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    /// Сегменты со значками: у образца каждый — флажок (AXSegment), выбранный залит акцентом. single — выбран
    /// всегда один (выравнивание), иначе — любые (B/I/U/S).
    private func segments(_ symbols: [String], widths: [CGFloat], selected: Set<Int>, tips: [String], frame: NSRect, single: Bool) {
        let control = NSSegmentedControl()
        control.segmentCount = symbols.count
        control.trackingMode = .selectAny
        control.segmentStyle = .rounded
        control.selectedSegmentBezelColor = Theme.accent
        for (i, symbol) in symbols.enumerated() {
            control.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold)), forSegment: i)
            control.setWidth(widths[i], forSegment: i)
            control.setSelected(selected.contains(i), forSegment: i)
            control.setToolTip(tips[i], forSegment: i)
        }
        if single {
            control.target = self
            control.action = #selector(singleSegment(_:))
        }
        put(control, frame.minX, frame.minY, frame.width, frame.height)
    }

    @objc private func singleSegment(_ sender: NSSegmentedControl) {
        let picked = sender.selectedSegment
        for i in 0..<sender.segmentCount { sender.setSelected(i == picked, forSegment: i) }
    }

    /// «› Интервалы»: стрелка-переключатель во всю ширину подписи и подпись 12 жирная с x = 29.
    private func disclosure(_ title: String, y: CGFloat, width: CGFloat) {
        put(DisclosureToggle(), 15, y, width, 17)
        label(title, 29, y, width - 14, 17, weight: .bold)
    }
}

/// Карточка стиля текста («Подпись»): подложка как у карточки кисти, образец — текст Helvetica 20 чёрным
/// на выделении 191 (17…99 × 10…36 от угла карточки, снимок 24.10), «⌄» справа. В Accessibility — кнопка.
final class TextStyleCard: NSButton {
    init(title: String) {
        super.init(frame: .zero)
        isBordered = false
        self.title = title
        toolTip = title
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
        let font = NSFont(name: "Helvetica", size: 20) ?? .systemFont(ofSize: 20)
        let text = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: NSColor.black])
        let w = text.size().width
        NSColor(white: 191 / 255, alpha: 1).setFill()
        NSRect(x: 17, y: 10, width: w + 1, height: 26).fill()
        // Базовая линия — в 31 от верха карточки (снимок 24.10).
        text.draw(at: NSPoint(x: 18, y: 31 - font.ascender))
        if let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold).applying(.init(paletteColors: [.labelColor]))) {
            let s = chevron.size
            chevron.draw(in: NSRect(x: 223 - s.width / 2, y: 23.5 - s.height / 2, width: s.width, height: s.height),
                         from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}

/// Кнопка-значок с меню на подложке 81 («доп. опции» у «Текста»): значок слева, «⌄» справа.
final class IconPlateButton: NSButton {
    private let symbol: String

    init(symbol: String) {
        self.symbol = symbol
        super.init(frame: .zero)
        isBordered = false
        title = ""
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.buttonBezel.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        for (name, size, x) in [(symbol, CGFloat(16), CGFloat(19)), ("chevron.down", CGFloat(9), bounds.maxX - 14)] {
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: size, weight: name == symbol ? .regular : .heavy)
                    .applying(.init(paletteColors: [.labelColor]))) else { continue }
            let s = image.size
            image.draw(in: NSRect(x: x - s.width / 2, y: bounds.midY - s.height / 2, width: s.width, height: s.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}
#endif
