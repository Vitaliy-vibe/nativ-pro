#if canImport(AppKit)
import AppKit

/// Внешний вид окна по образцу образца (раскладка «Стандартная», снимок 19.10):
/// тёмная тема, малиновый акцент, парящие скруглённые панели поверх холста.
enum Theme {
    /// Цвет акцента образца (основной цвет в заголовке у него rgb 1, 0.196, 0.294 — снято через Accessibility).
    static let accent = NSColor(srgbRed: 1, green: 0.196, blue: 0.294, alpha: 1)
    static let canvasBackground = NSColor(white: 0.12, alpha: 1)
    /// Фон панелей образца — ровный серый 55/255 без синевы (снимок окна 19.10), рамка светлее на 5 уровней.
    static let panelBackground = NSColor(srgbRed: 55 / 255, green: 55 / 255, blue: 55 / 255, alpha: 1)
    static let panelBorder = NSColor(white: 1, alpha: 0.025)
    /// Подложка числовых полей: 68/255 на фоне панели 55 (снимок 19.10).
    static let fieldBackground = NSColor(white: 1, alpha: 0.065)
    static let panelCorner: CGFloat = 12
    /// Отступ парящих панелей от краёв холста.
    static let gap: CGFloat = 8
    // Размеры панелей образца (Accessibility, окно 1600 × 1000, 19.10).
    static let layersWidth: CGFloat = 270
    static let optionsWidth: CGFloat = 272
    static let stripWidth: CGFloat = 41
    static let secondaryText = NSColor.secondaryLabelColor
    /// Подложка серых кнопок и списков образца — 81/255 на панели 55 (снимок 20.10; без цвета у нас 70).
    static let buttonBezel = NSColor(white: 81 / 255, alpha: 1)
    /// Недоступная кнопка у образца гаснет до 68; AppKit приглушает заданный цвет до 55 + 0,69 × (цвет − 55) → 74.
    static let buttonBezelDisabled = NSColor(white: 74 / 255, alpha: 1)

    static func sectionTitle(_ text: String) -> NSTextField {
        let t = NSTextField(labelWithString: text)
        t.font = .systemFont(ofSize: 12, weight: .semibold)
        return t
    }

    static func caption(_ text: String) -> NSTextField {
        let t = NSTextField(wrappingLabelWithString: text)
        t.font = .systemFont(ofSize: 10)
        t.textColor = secondaryText
        t.alignment = .center
        return t
    }

    static func separator() -> NSBox {
        let b = NSBox()
        b.boxType = .separator
        return b
    }

    /// Кнопка-значок без рамки (заголовки панелей, полоса инструментов).
    static func iconButton(_ symbol: String, _ tip: String, size: CGFloat = 16, target: AnyObject?, action: Selector?) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular)) ?? NSImage()
        let b = NSButton(image: image, target: target, action: action)
        b.isBordered = false
        b.toolTip = tip
        b.imagePosition = .imageOnly
        // У образца значки цвета основного текста (яркость 225), без этого у нас 165 (сверка 15).
        b.contentTintColor = .labelColor
        return b
    }

    /// Скруглённая кнопка с текстом («Заблокировать», «Сгруппировать»…).
    static func pillButton(_ title: String, target: AnyObject?, action: Selector?) -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .regular
        b.font = .systemFont(ofSize: 12)
        return b
    }

    static func checkbox(_ title: String, target: AnyObject?, action: Selector?) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: target, action: action)
        // Цвет акцента красит и подпись, поэтому — только у галочек без текста (видимость слоя).
        if title.isEmpty { b.contentTintColor = accent }
        return b
    }

    static func slider(target: AnyObject?, action: Selector) -> NSSlider {
        let s = SmallKnobSlider(value: 100, minValue: 0, maxValue: 100, target: target, action: action)
        s.trackFillColor = accent
        s.isContinuous = true
        s.controlSize = .small
        return s
    }
}

extension NSView {
    /// Поставить вид по замеру Accessibility (x, y, w, h от левого верхнего или левого нижнего угла `parent`).
    /// Замер AppKit показывает и элементы управления, и подписи на 1 точку шире рамки с каждой стороны
    /// (сверка 2, 19.10: прежняя отдельная поправка подписей давала сдвиг −2/−2). Поэтому рамка = замер с поправкой.
    /// Разделитель (NSBox) в Accessibility не виден; при той же поправке его линия ложится в строку y
    /// (от низа — в строку высота − y − 2), сверено по пикселям снимка 19.10.
    func place(in parent: NSView, x: CGFloat, y: CGFloat, w: CGFloat? = nil, h: CGFloat? = nil, fromBottom: Bool = false) {
        translatesAutoresizingMaskIntoConstraints = false
        if superview !== parent { parent.addSubview(self) }
        let d: CGFloat = 1
        let shrink: CGFloat = 2
        leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: x + d).isActive = true
        if fromBottom {
            bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -(y + d)).isActive = true
        } else {
            topAnchor.constraint(equalTo: parent.topAnchor, constant: y + d).isActive = true
        }
        if let w { widthAnchor.constraint(equalToConstant: w - shrink).isActive = true }
        if let h { heightAnchor.constraint(equalToConstant: h - shrink).isActive = true }
    }
}

extension NSLayoutConstraint {
    func withPriority(_ p: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        priority = p
        return self
    }
}

/// Парящая панель: ровный серый фон со скруглёнными углами поверх холста (у образца панели непрозрачные).
class FloatingPanel: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = Theme.panelBackground.cgColor
        layer?.cornerRadius = Theme.panelCorner
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = Theme.panelBorder.cgColor
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    /// Вложить содержимое с внутренними отступами.
    func embed(_ content: NSView, inset: CGFloat = 12) {
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            content.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
    }
}

/// Ячейка числового поля: текст по центру по высоте и с отступом 5 точек от краёв, как в полях образца
/// (у обычной ячейки без рамки текст прижат кверху).
final class CenteredTextFieldCell: NSTextFieldCell {
    private func centered(_ rect: NSRect) -> NSRect {
        var r = rect.insetBy(dx: 3, dy: 0)
        let h = min(cellSize(forBounds: rect).height, rect.height)
        r.origin.y += (rect.height - h) / 2
        r.size.height = h
        return r
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect { centered(super.titleRect(forBounds: rect)) }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: centered(cellFrame), in: controlView)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centered(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: centered(rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}
/// Ползунок с ручкой 16 × 12, как у образца (у малого ползунка AppKit ручка 18 × 14 — сверка 12 по пикселям).
final class SmallKnobSlider: NSSlider {
    override class var cellClass: AnyClass? {
        get { SmallKnobSliderCell.self }
        set {}
    }
}

final class SmallKnobSliderCell: NSSliderCell {
    override func knobRect(flipped: Bool) -> NSRect { super.knobRect(flipped: flipped).insetBy(dx: 1, dy: 1) }
}
#endif
