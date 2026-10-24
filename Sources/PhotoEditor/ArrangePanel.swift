#if canImport(AppKit)
import AppKit
import EditorApp
import EditorCore

/// Как выбирать слой щелчком инструментом «Расстановка».
enum AutoSelectMode: Int {
    case layer = 0
    case group = 1
}

/// Панель настроек инструмента «Расстановка» — копия инспектора образца.
/// Координаты элементов (точки от левого верхнего угла панели 272 × 904) сняты с работающего образца
/// через Accessibility; подсказки — его же тексты.
final class ArrangePanel: FloatingPanel {
    weak var controller: EditorWindowController?
    /// Элементы, связанные с командами меню: доступность обновляется в update().
    private var commandControls: [(NSControl, [String])] = []
    private let widthField = ArrangePanel.field()
    private let heightField = ArrangePanel.field()
    private let xField = ArrangePanel.field()
    private let yField = ArrangePanel.field()
    private let angleField = ArrangePanel.field()
    private let widthStep = NSStepper(), heightStep = NSStepper(), xStep = NSStepper(), yStep = NSStepper(), angleStep = NSStepper()
    private let knob = AngleKnob()
    private var autoSelectBox: NSButton!
    private let autoSelectPopup = NSPopUpButton()
    private let orderLeft = NSSegmentedControl()
    private let orderRight = NSSegmentedControl()
    private let alignControl = NSSegmentedControl()
    private let distributeControl = NSSegmentedControl()

    /// Кнопки, которые у образца доступны, а у нас команда ещё не сделана («Преобразование…», «Искажение…»).
    static let notYet: Set<String> = ["arrange.transform.resize", "arrange.warp"]

    var autoSelectEnabled: Bool { autoSelectBox.state == .on }
    var autoSelectMode: AutoSelectMode { AutoSelectMode(rawValue: autoSelectPopup.indexOfSelectedItem) ?? .group }

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    /// Поле числа как у образца: без рамки, на тёмной скруглённой подложке.
    static func field() -> NSTextField {
        let f = NSTextField()
        f.cell = CenteredTextFieldCell(textCell: "")
        f.isEditable = true
        f.isSelectable = true
        f.cell?.isScrollable = true
        f.isBezeled = false
        f.drawsBackground = true
        f.backgroundColor = Theme.fieldBackground
        f.wantsLayer = true
        f.layer?.cornerRadius = 6
        f.alignment = .right
        f.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        return f
    }

    /// Поставить элемент в точку (x, y) панели (от верха или от низа); w/h — размер, если задан.
    private func put(_ v: NSView, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat? = nil, _ h: CGFloat? = nil, fromBottom: Bool = false) {
        v.place(in: self, x: x, y: y, w: w, h: h, fromBottom: fromBottom)
    }

    /// Шрифты выведены из замеров 19.10 (высота рамки в Accessibility и ширина того же текста у нас при 13 точках):
    /// заголовок панели 14 жирный (рамка 19), заголовки разделов 12 жирный (17), подписи полей 12 обычный (17).
    private func label(_ text: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat? = nil, _ h: CGFloat? = nil,
                       size: CGFloat = 12, weight: NSFont.Weight = .regular, alignment: NSTextAlignment = .natural) {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.alignment = alignment
        put(l, x, y, w, h)
    }

    /// Подпись под кнопками: у образца полужирная, цвета основного текста (224/255 на снимке, не серая),
    /// рамка задана замером (под сдвоенными кнопками — 62 × 44 при любом числе строк), текст по центру.
    private func caption(_ text: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.alignment = .center
        l.textColor = .labelColor
        l.preferredMaxLayoutWidth = w - 2
        put(l, x, y, w, h)
    }

    /// Однострочная подпись по центру над точкой centerX: в рамке по замеру образца (31 и 78) наш текст обрезался
    /// («Уго», «Перевернут» — сверка 7), поэтому ширина по тексту, середина — как у образца.
    private func centeredCaption(_ text: String, centerX: CGFloat, y: CGFloat) {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.alignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: leadingAnchor, constant: centerX),
            l.topAnchor.constraint(equalTo: topAnchor, constant: y + 1),
        ])
    }

    private func line(_ y: CGFloat, bottom: Bool = false) {
        put(Theme.separator(), 14, y, 244, 1, fromBottom: bottom)
    }

    private func segments(_ c: NSSegmentedControl, _ symbols: [String], _ ids: [String], _ tips: [String], width: CGFloat) {
        c.segmentCount = symbols.count
        c.trackingMode = .momentary
        c.segmentStyle = .rounded
        c.controlSize = .large
        for (i, s) in symbols.enumerated() {
            c.setImage(NSImage(systemSymbolName: s, accessibilityDescription: tips[i]), forSegment: i)
            c.setToolTip(tips[i], forSegment: i)
            c.setWidth(width, forSegment: i)
        }
        c.target = self
        c.action = #selector(segmentPressed(_:))
        commandControls.append((c, ids))
    }

    private func button(_ title: String, _ id: String, _ tip: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, fromBottom: Bool = false) {
        let b = TightButton(title: title, target: self, action: #selector(command(_:)))
        b.bezelStyle = .push
        b.controlSize = .large
        // Сверка 8: «Заблокировать» у образца 88 точек текста, у нас при 13 — 95 → шрифт 12.
        b.font = .systemFont(ofSize: 12)
        b.bezelColor = Theme.buttonBezel
        b.identifier = .init(id)
        b.toolTip = tip
        put(b, x, y, w, 30, fromBottom: fromBottom)
        commandControls.append((b, [id]))
    }

    private func numberRow(_ prefix: String, _ field: NSTextField, _ step: NSStepper, x: CGFloat, y: CGFloat, tip: String, action: Selector?) {
        // Замер: «Ш:»/«X:» 21 точку, «В:»/«Y:» 20, текст прижат вправо, правый край — за 5 точек до поля.
        let w: CGFloat = x < 100 ? 21 : 20
        label(prefix, x - 5 - w, y + 4, w, 17, alignment: .right)
        field.toolTip = tip
        field.target = self
        field.action = action
        put(field, x, y, 75, 24)
        step.controlSize = .small
        step.valueWraps = false
        step.minValue = -1_000_000
        step.maxValue = 1_000_000
        step.toolTip = tip
        step.target = self
        step.action = #selector(stepped(_:))
        put(step, x + 78, y + 3, 15, 17)
    }

    private func build() {
        let t = AppInfo.tr
        label(t("Arrange", "Расстановка"), 14, 16, 232, 19, size: 14, weight: .bold)
        line(41)

        // Порядок: два сдвоенных переключателя, подписи под каждым сегментом.
        segments(orderLeft, ["square.3.layers.3d.bottom.filled", "square.3.layers.3d.top.filled"], ["arrange.back", "arrange.front"],
                 [t("Move the selected objects to the back.", "Переместите выбранные объекты на задний слой."),
                  t("Move the selected objects to the front.", "Переместите выбранные объекты на передний слой.")], width: 57)
        segments(orderRight, ["square.2.layers.3d.bottom.filled", "square.2.layers.3d.top.filled"], ["arrange.backward", "arrange.forward"],
                 [t("Move the selected objects back one layer.", "Переместите выбранные объекты назад на один слой."),
                  t("Move the selected objects forward one layer.", "Переместите выбранные объекты вперед на один слой.")], width: 57)
        // Замер 19.10: сегменты на 4 точки правее рамки сдвоенной кнопки — ставим рамку так, чтобы сегменты легли как у образца.
        put(orderLeft, 13, 53, 123, 36)
        put(orderRight, 136, 53, 123, 36)
        caption(t("To Back", "На задний план"), 14, 86, 62, 44)
        caption(t("To Front", "На передний план"), 71, 86, 62, 44)
        caption(t("Backward", "Назад"), 137, 86, 62, 44)
        caption(t("Forward", "Вперед"), 194, 86, 62, 44)
        line(140)

        segments(alignControl, ["align.vertical.top.fill", "align.vertical.center.fill", "align.vertical.bottom.fill",
                                "align.horizontal.left.fill", "align.horizontal.center.fill", "align.horizontal.right.fill"],
                 ["align.top", "align.vcenter", "align.bottom", "align.left", "align.hcenter", "align.right"],
                 [t("Align the top edges of the selected objects.", "Выровнять выбранные объекты по верхнему краю."),
                  t("Align the vertical centers of the selected objects.", "Выровнять центры выбранных объектов по вертикали."),
                  t("Align the bottom edges of the selected objects.", "Выровнять выбранные объекты по нижнему краю."),
                  t("Align the left edges of the selected objects.", "Выровнять выбранные объекты по левому краю."),
                  t("Align the horizontal centers of the selected objects.", "Выровнять центры выбранных объектов по горизонтали."),
                  t("Align the right edges of the selected objects.", "Выровнять выбранные объекты по правому краю.")], width: 39)
        segments(distributeControl, ["distribute.vertical.top.fill", "distribute.vertical.center.fill", "distribute.vertical.bottom.fill",
                                     "distribute.horizontal.left.fill", "distribute.horizontal.center.fill", "distribute.horizontal.right.fill"],
                 ["distribute.top", "distribute.vcenter", "distribute.bottom", "distribute.left", "distribute.hcenter", "distribute.right"],
                 [t("Distribute by top edges.", "Равномерно распределить выбранные объекты в соответствии с их верхними краями."),
                  t("Distribute by vertical centers.", "Равномерно распределить выбранные объекты в соответствии с их центрами по вертикали."),
                  t("Distribute by bottom edges.", "Равномерно распределить выбранные объекты в соответствии с их нижними краями."),
                  t("Distribute by left edges.", "Равномерно распределить выбранные объекты в соответствии с их левыми краями."),
                  t("Distribute by horizontal centers.", "Равномерно распределить выбранные объекты в соответствии с их центрами по горизонтали."),
                  t("Distribute by right edges.", "Равномерно распределить выбранные объекты в соответствии с их правыми краями.")], width: 39)
        put(alignControl, 14, 150, 245, 36)
        put(distributeControl, 14, 189, 245, 36)
        line(236)

        label(t("Size", "Размер"), 15, 249, weight: .bold)
        numberRow(t("W:", "Ш:"), widthField, widthStep, x: 38, y: 274, tip: t("Set the width of the object.", "Задайте ширину объекта."), action: nil)
        numberRow(t("H:", "В:"), heightField, heightStep, x: 162, y: 274, tip: t("Set the height of the object.", "Задайте высоту объекта."), action: nil)
        let keep = NSButton(checkboxWithTitle: t("Constrain Proportions", "Соблюдать пропорции"), target: nil, action: nil)
        keep.state = .on
        keep.toolTip = t("Keep the width-to-height ratio when resizing.", "Выберите сохранение пропорций (ширина к высоте) при изменении размеров этого объекта.")
        put(keep, 38, 306, 220, 24)
        let original = NSButton(title: t("Original Size", "Исходный размер"), target: nil, action: nil)
        original.bezelStyle = .push
        original.controlSize = .large
        original.font = .systemFont(ofSize: 12)
        original.bezelColor = Theme.buttonBezel
        original.toolTip = t("Return the selected object to its original size.", "Верните выбранный объект к его исходным размерам.")
        put(original, 38, 338, 219, 30)
        line(383)

        label(t("Position", "Позиция"), 15, 396, weight: .bold)
        numberRow("X:", xField, xStep, x: 38, y: 421, tip: t("Distance from the top-left corner of the object to the left edge of the canvas.",
                                                              "Задать расстояние от левого верхнего угла объекта до левого края полотна."), action: #selector(positionTyped(_:)))
        numberRow("Y:", yField, yStep, x: 162, y: 421, tip: t("Distance from the top-left corner of the object to the top edge of the canvas.",
                                                              "Задать расстояние от левого верхнего угла объекта до верхнего края полотна."), action: #selector(positionTyped(_:)))
        line(460)

        label(t("Rotate", "Повернуть"), 15, 473, weight: .bold)
        knob.sliderType = .circular
        knob.minValue = 0
        knob.maxValue = 360
        knob.toolTip = t("Change the angle of the object.", "Измените угол объекта.")
        put(knob, 15, 498, 26, 26)
        angleField.stringValue = "0°"
        angleField.toolTip = t("Set the angle of the object.", "Задайте угол объекта.")
        put(angleField, 47, 499, 66, 24)
        angleStep.controlSize = .small
        angleStep.toolTip = angleField.toolTip
        put(angleStep, 116, 502, 15, 17)
        centeredCaption(t("Angle", "Угол"), centerX: 80.5, y: 527)
        let flips: [(String, String, String, CGFloat)] = [
            ("arrow.trianglehead.left.and.right.righttriangle.left.righttriangle.right.fill", "arrange.flipH",
             t("Flip the object horizontally.", "Переверните объект по горизонтали."), 162),
            ("arrow.trianglehead.up.and.down.righttriangle.up.righttriangle.down.fill", "arrange.flipV",
             t("Flip the object vertically.", "Переверните объект по вертикали."), 212),
        ]
        for (symbol, id, tip, x) in flips {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(), target: self, action: #selector(command(_:)))
            b.identifier = .init(id)
            b.toolTip = tip
            b.bezelStyle = .push
            b.controlSize = .large
            b.bezelColor = Theme.buttonBezel
            put(b, x, 497, 45, 29)
            commandControls.append((b, [id]))
        }
        centeredCaption(t("Flip", "Перевернуть"), centerX: 208, y: 527)
        line(553)

        button(t("Lock", "Заблокировать"), "arrange.lock", t("Lock the selected objects to prevent editing.", "Блокируйте выбранные объекты, чтобы запретить правку."), 15, 567, 118)
        button(t("Unlock", "Разблокировать"), "arrange.unlock", t("Unlock the selected objects for editing.", "Разблокируйте выбранные объекты для правки."), 139, 567, 118)
        button(t("Hide", "Скрыть"), "arrange.hide", t("Hide the selected objects.", "Скройте выбранные объекты, чтобы сделать их невидимыми."), 15, 606, 118)
        button(t("Show", "Показать"), "arrange.show", t("Show the selected objects.", "Покажите выбранные объекты, чтобы сделать их видимыми."), 139, 606, 118)
        line(649)
        button(t("Group", "Сгруппировать"), "arrange.group", t("Group the selected objects into a single group layer.", "Сгруппируйте выбранные объекты в единый слой группы."), 15, 663, 118)
        button(t("Ungroup", "Разгруппировать"), "arrange.ungroup", t("Ungroup the selected objects.", "Разгруппируйте выбранные объекты."), 139, 663, 118)
        line(706)
        button(t("Merge Layers", "Объединить слои"), "arrange.merge", t("Destructively merge the selected objects into one.", "Деструктивно объединить выбранные объекты в один объект."), 15, 720, 242)
        line(763)

        autoSelectBox = NSButton(checkboxWithTitle: t("Auto Select:", "Автовыбор:"), target: nil, action: nil)
        // Подпись 12, как у флажков образца (при 13 рамка была на 5 точек шире — сверка 20.10).
        autoSelectBox.font = .systemFont(ofSize: 12)
        autoSelectBox.state = .on
        autoSelectBox.toolTip = t("Turn layer auto-selection on or off.", "Включить/выключить автовыбор слоев.")
        // Ширина по тексту: в 93 по замеру наш текст обрезался («Автовыб…», сверка 7).
        put(autoSelectBox, 15, 780, nil, 18)
        autoSelectPopup.addItems(withTitles: [t("Layer", "Слой"), t("Group", "Сгруппировать")])
        // Как у образца по умолчанию: щелчок выбирает группу целиком.
        autoSelectPopup.selectItem(at: AutoSelectMode.group.rawValue)
        put(autoSelectPopup, 155, 777, 102, 26)

        line(57, bottom: true)
        button(t("Transform…", "Преобразование…"), "arrange.transform.resize",
               t("Transform the object: resize, rotate and more.", "Преобразовать объект: изменить его размер, повернуть его и выполнить другие действия."), 15, 15, 129, fromBottom: true)
        button(t("Warp…", "Искажение…"), "arrange.warp", t("Bend and distort the object with a warp grid.", "Изогнуть и исказить объект по сетке искажения."), 150, 15, 107, fromBottom: true)
    }

    /// Обновить доступность кнопок и значения полей по выбранному слою.
    func update() {
        guard let controller, controller.editorDocument != nil else { return }
        for (c, ids) in commandControls {
            if let seg = c as? NSSegmentedControl {
                for (i, id) in ids.enumerated() { seg.setEnabled(controller.canRun(id), forSegment: i) }
            } else {
                // Как у образца — доступны при выбранном слое; пока команды нет, нажатие даёт звуковой сигнал.
                c.isEnabled = controller.canRun(ids[0]) || (ArrangePanel.notYet.contains(ids[0]) && controller.session.primaryLayer != nil)
                (c as? NSButton)?.bezelColor = c.isEnabled ? Theme.buttonBezel : Theme.buttonBezelDisabled
            }
        }
        let layer = controller.session.primaryLayer
        let b = layer?.bounds
        widthField.stringValue = b.map { "\($0.width) px" } ?? "—"
        heightField.stringValue = b.map { "\($0.height) px" } ?? "—"
        let editable = b != nil && layer?.isLocked == false
        for v in [xField, yField, xStep, yStep] as [NSControl] { v.isEnabled = editable }
        // Не перебивать то, что пользователь сейчас вводит.
        if window?.firstResponder !== xField.currentEditor() { xField.stringValue = b.map { "\($0.x) px" } ?? "—" }
        if window?.firstResponder !== yField.currentEditor() { yField.stringValue = b.map { "\($0.y) px" } ?? "—" }
        xStep.integerValue = b?.x ?? 0
        yStep.integerValue = b?.y ?? 0
    }

    @objc private func command(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        controller?.run(id)
    }

    @objc private func segmentPressed(_ sender: NSSegmentedControl) {
        guard let ids = commandControls.first(where: { $0.0 === sender })?.1, sender.selectedSegment >= 0 else { return }
        controller?.run(ids[sender.selectedSegment])
    }

    @objc private func positionTyped(_ sender: NSTextField) {
        guard let controller, let id = controller.session.primary else { return }
        let digits = sender.stringValue.filter { $0.isNumber || $0 == "-" }
        guard let v = Int(digits) else { update(); return }
        if sender === xField { controller.session.setPosition(id, x: v) } else { controller.session.setPosition(id, y: v) }
    }

    @objc private func stepped(_ sender: NSStepper) {
        guard let controller, let id = controller.session.primary else { return }
        if sender === xStep { controller.session.setPosition(id, x: sender.integerValue) }
        if sender === yStep { controller.session.setPosition(id, y: sender.integerValue) }
    }
}
/// Кнопка с узкими полями по бокам, как у образца: у стандартной большой кнопки поля шире и текст обрезался
/// («Преобразовани…», «Разгруппиров…» — сверка 7).
final class TightButton: NSButton {
    override class var cellClass: AnyClass? {
        get { TightButtonCell.self }
        set {}
    }
}

final class TightButtonCell: NSButtonCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        let r = super.titleRect(forBounds: rect)
        return NSRect(x: rect.minX + 6, y: r.minY, width: rect.width - 12, height: r.height)
    }
}
/// Ручка угла как у образца: 0° — горизонтальная чёрточка 6 × 2 справа от центра (на «3 часа»), рост против
/// часовой стрелки (снимок сверки 14 по пикселям); у стандартной круглой ручки AppKit 0° наверху и по часовой.
final class AngleKnob: NSSlider {
    override class var cellClass: AnyClass? {
        get { AngleKnobCell.self }
        set {}
    }
}

final class AngleKnobCell: NSSliderCell {
    private func center(in view: NSView) -> NSPoint { NSPoint(x: view.bounds.midX, y: view.bounds.midY) }

    /// Целиком своя отрисовка: стандартная круглая ручка рисовала поверх ещё и свою отметку наверху (сверка 15).
    /// Круг — 70/255 на фоне панели 55, как у образца.
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let d = min(cellFrame.width, cellFrame.height)
        let circle = NSRect(x: cellFrame.midX - d / 2, y: cellFrame.midY - d / 2, width: d, height: d)
        NSColor(white: 1, alpha: 0.075).setFill()
        NSBezierPath(ovalIn: circle).fill()
        drawKnob(knobRect(flipped: controlView.isFlipped))
    }

    override func drawKnob(_ knobRect: NSRect) {
        guard let view = controlView else { return }
        let c = center(in: view)
        let a = CGFloat(doubleValue) * .pi / 180
        let up: CGFloat = view.isFlipped ? -1 : 1
        let path = NSBezierPath()
        path.move(to: NSPoint(x: c.x + 3 * cos(a), y: c.y + up * 3 * sin(a)))
        path.line(to: NSPoint(x: c.x + 9 * cos(a), y: c.y + up * 9 * sin(a)))
        path.lineWidth = 2
        NSColor.labelColor.setStroke()
        path.stroke()
    }

    private func angle(at point: NSPoint, in view: NSView) -> Double {
        let c = center(in: view)
        let up: CGFloat = view.isFlipped ? -1 : 1
        let deg = atan2(up * (point.y - c.y), point.x - c.x) * 180 / .pi
        return Double(deg < 0 ? deg + 360 : deg)
    }

    override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
        doubleValue = angle(at: startPoint, in: controlView)
        controlView.needsDisplay = true
        return true
    }

    override func continueTracking(last lastPoint: NSPoint, current currentPoint: NSPoint, in controlView: NSView) -> Bool {
        doubleValue = angle(at: currentPoint, in: controlView)
        controlView.needsDisplay = true
        if let control = controlView as? NSControl { control.sendAction(control.action, to: control.target) }
        return true
    }
}
#endif
