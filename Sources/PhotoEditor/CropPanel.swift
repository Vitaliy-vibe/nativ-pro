#if canImport(AppKit)
import AppKit
import EditorApp

/// «Обрезать» (замеры образца 20.10; разделители на 346, 487, 567, 620 — по пикселям, детектор их не видит:
/// у левого края линия светлее): размер обрезки, «Автообрезка», повороты и отражения, «Выпрямить»,
/// «Автовыпрямление», перспектива, наложение, «Удалить обрезанные пиксели»; внизу «Сбросить», «Отменить»,
/// «Применить». Значки — обведённые картинки образца (TracedPanelIcons).
final class CropPanel: ToolPanel {
    private let width = NSTextField()
    private let height = NSTextField()

    init() {
        let t = AppInfo.tr
        super.init(title: ToolPanel.titles["tool.crop"]!, header: [])
        let preset = PlateTitleButton(title: t("Custom Size", "Пользовательский размер"))
        put(preset, 15, 55, 242, 26)
        label(t("W:", "Ш:"), 12, 93, 21, 17)
        sizeField(width, x: 38, tip: t("Set the width of the crop rectangle.", "Задать ширину обрезки прямоугольника выборки."))
        label(t("H:", "В:"), 137, 93, 20, 17)
        sizeField(height, x: 162, tip: t("Set the height of the crop rectangle.", "Задать высоту обрезки прямоугольника выборки."))
        line(127)
        toggleButton(t("Auto Crop", "Автообрезка"), t("Crop the image automatically.", "Автоматически обрезать изображение."), y: 141)
        line(184)
        let turns: [(String, String)] = [
            ("crop_rotate_left", t("Rotate the image counterclockwise.", "Поворот изображения против часовой стрелки.")),
            ("crop_rotate_right", t("Rotate the image clockwise.", "Поворот изображения по часовой стрелке.")),
            ("flip_horizontal", t("Flip the image horizontally.", "Переворот изображения по горизонтали.")),
            ("flip_vertical", t("Flip the image vertically.", "Переворот изображения по вертикали.")),
        ]
        for (i, (icon, tip)) in turns.enumerated() {
            // Белым готовым рисунком: шаблон в серой кнопке AppKit рисовал чёрным (сверка 24.10).
            let b = TightButton(image: TracedPanelIcons.image(icon, tint: .labelColor), target: nil, action: nil)
            b.title = ""
            b.imagePosition = .imageOnly
            // В натуральную величину: иначе кнопка ужимала значок до своей высоты текста (сверка 24.10).
            b.imageScaling = .scaleNone
            b.bezelStyle = .push
            b.controlSize = .large
            b.bezelColor = Theme.buttonBezel
            b.contentTintColor = .labelColor
            b.toolTip = tip
            put(b, 15 + CGFloat(i) * 62, 198, 56, 30)
        }
        line(241)
        label(t("Straighten", "Выпрямить"), 15, 254, 192, 17, weight: .bold)
        numberField("0°", tip: t("Set the rotation of the image.", "Задать вращение изображения."), NSRect(x: 200, y: 251, width: 58, height: 24))
        iconSliderRow(left: "straighten_left", right: "straighten_right", y: 273, iconW: 21, iconH: 19,
                      leftTip: t("Rotate the image one degree to the left.", "Поворот изображения на один градус влево."),
                      rightTip: t("Rotate the image one degree to the right.", "Поворот изображения на один градус вправо."),
                      sliderTip: t("Adjust the rotation of the image.", "Настроить поворот изображения."))
        toggleButton(t("Auto Straighten", "Автовыпрямление"), t("Straighten the image automatically.", "Автоматически выпрямлять изображение."), y: 303)
        line(346)
        label(t("Perspective", "Перспектива"), 15, 359, 85, 17, weight: .bold)
        let vTip = t("Adjust the vertical perspective of the image.", "Настроить вертикальную перспективу изображения.")
        label(t("Vertical", "Вертикаль"), 15, 386, 192, 17)
        numberField("0\u{00A0}%", tip: t("Set the vertical perspective of the image.", "Задать вертикальную перспективу изображения."), NSRect(x: 200, y: 383, width: 58, height: 24))
        iconSliderRow(left: "perspective_top", right: "perspective_bottom", y: 405, iconW: 18, iconH: 18,
                      leftTip: vTip, rightTip: vTip, sliderTip: vTip)
        let hTip = t("Adjust the horizontal perspective of the image.", "Настроить горизонтальную перспективу изображения.")
        label(t("Horizontal", "Горизонталь"), 15, 436, 192, 17)
        numberField("0\u{00A0}%", tip: t("Set the horizontal perspective of the image.", "Задать горизонтальную перспективу изображения."), NSRect(x: 200, y: 433, width: 58, height: 24))
        iconSliderRow(left: "perspective_left", right: "perspective_right", y: 455, iconW: 18, iconH: 18,
                      leftTip: hTip, rightTip: hTip, sliderTip: hTip)
        line(487)
        label(t("Overlay", "Наложение"), 15, 500, 74, 17, weight: .bold)
        let overlay = NSPopUpButton()
        overlay.addItems(withTitles: [t("Rule of Thirds", "Правило третей"), t("Grid", "Сетка"), t("Golden Ratio", "Золотое сечение"),
                                      t("Golden Spiral", "Золотая спираль"), t("Diagonal", "Диагональ"), t("Triangle", "Треугольник"),
                                      t("Center", "Центр"), t("None", "Нет")])
        overlay.item(at: 0)?.image = TracedPanelIcons.image("grid_thirds")
        overlay.toolTip = t("Choose and adjust the grid shown in the crop selection area.", "Выбрать и настроить сетку, показанную в области выбора обрезки.")
        put(overlay, 15, 526, 242, 26)
        line(567)
        checkbox(t("Delete Cropped Pixels", "Удалить обрезанные пиксели"), on: false,
                 tip: t("Choose to permanently delete all areas outside the crop frame.", "Выберите, чтобы необратимо удалить все области вне прямоугольника кадрирования."), 15, 584)
        line(620)
        // Низ: разделитель в 116 от низа, недоступная «Сбросить», разделитель, «Отменить» и «Применить».
        line(114, bottom: true)
        disable(wideButton(t("Reset", "Сбросить"), t("Reset all current changes made with the Crop tool.", "Сбросить все текущие изменения, сделанные инструментом обрезки."),
                           15, 72, 242, fromBottom: true))
        line(57, bottom: true)
        wideButton(t("Cancel", "Отменить"), t("Reset all current changes and stop cropping the image.", "Сбросить все текущие изменения и прекратить обрезку изображения."),
                   15, 15, 118, fromBottom: true)
        wideButton(t("Apply", "Применить"), t("Crop the image.", "Обрезать изображение."), 139, 15, 118, prominent: true, fromBottom: true)
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    /// Размер обрезки — пока весь документ.
    override func update() {
        guard let doc = controller?.session.document else { return }
        width.stringValue = "\(doc.width) px"
        height.stringValue = "\(doc.height) px"
    }

    /// Поле размера с подложкой 68 (73 × 23, на 2 правее и на 1 ниже рамки поля) и стрелками справа.
    private func sizeField(_ field: NSTextField, x: CGFloat, tip: String) {
        let plate = NSView()
        plate.wantsLayer = true
        plate.layer?.backgroundColor = NSColor(white: 68 / 255, alpha: 1).cgColor
        plate.layer?.cornerRadius = 5
        // Через place(): панель не перевёрнута по y, рамкой подложка уезжала вниз (сверка 24.10).
        plate.place(in: self, x: x + 1, y: 89, w: 75, h: 25)
        field.cell = CenteredTextFieldCell(textCell: "")
        field.isEditable = true
        field.isBezeled = false
        field.drawsBackground = false
        field.alignment = .right
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        field.toolTip = tip
        put(field, x, 89, 75, 25)
        let stepper = NSStepper()
        stepper.controlSize = .small
        stepper.toolTip = tip
        put(stepper, x + 78, 92, 15, 17)
    }

    /// Серая кнопка-переключатель во всю ширину («Автообрезка», «Автовыпрямление»): в Accessibility — AXToggle.
    private func toggleButton(_ title: String, _ tip: String, y: CGFloat) {
        let b = wideButton(title, tip, 15, y, 242)
        b.setButtonType(.pushOnPushOff)
        b.state = .off
    }

    /// Значок — ползунок-капсула — значок (выпрямление, перспектива): значки без рамки, ползунок 198 × 20 с x = 37.
    private func iconSliderRow(left: String, right: String, y: CGFloat, iconW: CGFloat, iconH: CGFloat,
                               leftTip: String, rightTip: String, sliderTip: String) {
        for (name, x, tip) in [(left, CGFloat(iconW > 20 ? 13 : 14), leftTip), (right, CGFloat(iconW > 20 ? 238 : 240), rightTip)] {
            let b = NSButton(image: TracedPanelIcons.image(name), target: nil, action: nil)
            b.isBordered = false
            b.imagePosition = .imageOnly
            b.contentTintColor = .labelColor
            b.toolTip = tip
            put(b, x, y + 1, iconW, iconH)
        }
        let slider = PointerSlider(value: 0, minValue: -45, maxValue: 45, target: nil, action: nil)
        slider.capsule = true
        slider.style(filled: false, ticks: .none)
        slider.toolTip = sliderTip
        put(slider, 37, y, 198, 20)
    }
}

/// Кнопка-список во всю ширину («Пользовательский размер»): подложка 81 со скруглением 6, название 12 слева,
/// «⌄» справа; в Accessibility — кнопка с названием, как у образца.
final class PlateTitleButton: NSButton {
    init(title: String) {
        super.init(frame: .zero)
        isBordered = false
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.buttonBezel.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let h = font.ascender - font.descender
        (title as NSString).draw(at: NSPoint(x: 12, y: (bounds.height - h) / 2), withAttributes: [.font: font, .foregroundColor: NSColor.labelColor])
        if let image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .heavy).applying(.init(paletteColors: [.white]))) {
            let s = image.size
            image.draw(in: NSRect(x: bounds.maxX - 15 - s.width / 2, y: bounds.midY - s.height / 2, width: s.width, height: s.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}
#endif
