#if canImport(AppKit)
import AppKit
import EditorApp

/// Вертикальная полоса инструментов у правого края (как у образца): группы значков, выбранный — в кружке.
/// Инструменты, которых ещё нет, показаны приглушёнными; щелчок по ним ничего не делает.
final class ToolStrip: FloatingPanel {
    weak var controller: EditorWindowController?
    private var buttons: [String: NSButton] = [:]

    /// Группы инструментов сверху вниз — порядок как в полосе образца (раскладка «Стандартная»).
    static let groups: [[String]] = [
        ["tool.arrange"],
        ["tool.style", "tool.adjustments", "tool.effects"],
        ["tool.selectRect", "tool.lassoFree", "tool.selectQuick"],
        ["tool.paint", "tool.fill", "tool.erase"],
        ["tool.repair", "tool.clone", "tool.sharpen", "tool.lighten", "tool.saturate", "tool.distort"],
        ["tool.pen", "tool.shape", "tool.type"],
        ["tool.zoom", "tool.crop", "tools.more"],
    ]

    /// Все инструменты полосы (без «…»).
    static let toolIDs: Set<String> = Set(groups.joined().filter { $0 != "tools.more" })

    /// Названия кнопок у образца (Accessibility, сверка 16) — там, где они не совпадают с пунктами меню.
    static let axNames: [String: String] = AppInfo.russian ? [
        "tool.paint": "Рисовать", "tool.erase": "Стереть", "tool.repair": "Исправить", "tool.sharpen": "Резкость",
        "tool.saturate": "Повысить насыщенность", "tool.distort": "Исказить", "tool.crop": "Обрезать",
    ] : [:]

    /// Подсказки — тексты образца (снято через Accessibility 19.10).
    static let tips: [String: String] = [
        "tool.arrange": "Перемещать, вращать и масштабировать слои. Активируйте инструмент сочетанием клавиш V.",
        "tool.style": "Измените вид слоёв, применяя заливки, штрихи и тени. Активируйте инструмент сочетанием клавиш S.",
        "tool.adjustments": "Сделайте тонкую правку или полностью измените цвета изображений. Активируйте инструмент сочетанием клавиш A.",
        "tool.effects": "Изменить вид слоёв, применяя такие эффекты, как размытие, искажение и другие. Активируйте инструмент сочетанием клавиш F.",
        "tool.selectRect": "Выбрать квадратные или прямоугольные области. Активируйте инструмент сочетанием клавиш M.",
        "tool.lassoFree": "Выбрать области свободной формы. Активируйте инструмент сочетанием клавиш L.",
        "tool.selectQuick": "Быстро выбрать объекты или области, рисуя поверх них. Активируйте инструмент сочетанием клавиш Q.",
        "tool.paint": "Закраска и скетч, используя коллекцию кистей. Активируйте инструмент сочетанием клавиш B.",
        "tool.fill": "Заливка областей сплошным цветом. Активируйте инструмент сочетанием клавиш N.",
        "tool.erase": "Сотрите кистями области изображения. Активируйте инструмент сочетанием клавиш E.",
        "tool.repair": "Удалить маленькие дефекты или объекты целиком с изображений. Активируйте инструмент сочетанием клавиш R.",
        "tool.clone": "Копировать части изображения с одного места на другое. Активируйте инструмент сочетанием клавиш O.",
        "tool.sharpen": "Проведите кистью по участкам, чтобы сделать их резче.",
        "tool.lighten": "Проведите кистью по участкам, чтобы сделать их ярче.",
        "tool.saturate": "Проведите кистью по участкам, чтобы сделать их более живыми и сияющими.",
        "tool.distort": "Толкать и тянуть области изображения в любом направлении.",
        "tool.pen": "Нарисовать векторные пути, чтобы создать фигуры. Активируйте инструмент сочетанием клавиш P.",
        "tool.shape": "Нарисовать векторные фигуры и управлять вашей коллекцией фигур. Активируйте инструмент сочетанием клавиш U.",
        "tool.type": "Добавить или форматировать текст. Активируйте инструмент сочетанием клавиш T.",
        "tool.zoom": "Масштабируйте изображения и перемещайтесь по ним. Активируйте инструмент сочетанием клавиш Z.",
        "tool.crop": "Обрезать и выпрямить изображения. Активируйте инструмент сочетанием клавиш C.",
    ]

    /// Раскладка как у образца: панель 41 точка во всю высоту, кнопки 35 × 37 вплотную, внизу — «…» 19 × 19.
    /// Промежутки между группами у образца растягиваются поровну: (высота − 816) / 6 — замер при высоте 904
    /// (14,67) и 940 (20,67), 19–20.10. Верх первой кнопки — 3, от последней до «…» — 7 точек.
    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.cornerRadius = Theme.stripWidth / 2
        // «…» — по замеру: 19 × 19, низ в 10 точках от края.
        let more = Theme.iconButton("ellipsis", AppInfo.tr("Show hidden tools or customize the tool list.", "Показать скрытые инструменты или настроить список инструментов."),
                                    size: 13, target: self, action: #selector(pick(_:)))
        more.identifier = .init("tools.more")
        more.place(in: self, x: 11, y: 10, w: 19, h: 19, fromBottom: true)

        var previous: NSButton?
        var firstGap: NSLayoutGuide?
        for group in ToolStrip.groups {
            var startsGroup = true
            for id in group where id != "tools.more" {
                let b = NSButton(image: ToolIcons.image(id), target: self, action: #selector(pick(_:)))
                // Как у образца: переключатель (AXCheckBox) с названием инструмента и подсказкой.
                b.setButtonType(.toggle)
                b.isBordered = false
                b.imagePosition = .imageOnly
                b.imageScaling = .scaleNone
                let title = ToolStrip.axNames[id] ?? EditorWindowController.titles[id] ?? id
                b.toolTip = AppInfo.russian ? (ToolStrip.tips[id] ?? title) : title
                b.setAccessibilityLabel(title)
                b.identifier = .init(id)
                b.wantsLayer = true
                b.layer?.cornerRadius = 15
                // Рамка 33 × 35 — в Accessibility 35 × 37 (см. NSView.place).
                b.translatesAutoresizingMaskIntoConstraints = false
                addSubview(b)
                var c = [b.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
                         b.widthAnchor.constraint(equalToConstant: 33),
                         b.heightAnchor.constraint(equalToConstant: 35)]
                if let previous {
                    if startsGroup {
                        let gap = NSLayoutGuide()
                        addLayoutGuide(gap)
                        c += [gap.topAnchor.constraint(equalTo: previous.bottomAnchor),
                              b.topAnchor.constraint(equalTo: gap.bottomAnchor),
                              gap.heightAnchor.constraint(greaterThanOrEqualToConstant: 2)]
                        if let firstGap { c.append(gap.heightAnchor.constraint(equalTo: firstGap.heightAnchor)) } else { firstGap = gap }
                    } else {
                        c.append(b.topAnchor.constraint(equalTo: previous.topAnchor, constant: 37))
                    }
                } else {
                    c.append(b.topAnchor.constraint(equalTo: topAnchor, constant: 4))
                }
                NSLayoutConstraint.activate(c)
                previous = b
                startsGroup = false
                buttons[id] = b
            }
        }
        // От низа последней кнопки до «…» — 7 точек в Accessibility (между рамками 9). В низком окне уступает.
        if let previous {
            previous.bottomAnchor.constraint(equalTo: more.topAnchor, constant: -9).withPriority(.defaultHigh).isActive = true
        }
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    /// Отметить выбранный инструмент.
    func update(selected: String) {
        for (id, b) in buttons {
            let isSelected = id == selected
            b.state = isSelected ? .on : .off
            b.layer?.backgroundColor = isSelected ? NSColor(white: 1, alpha: 0.9).cgColor : NSColor.clear.cgColor
            // Невыбранный — готовый цвет 224/255, как у образца; выбранный — шаблон, чёрный на белом круге.
            b.image = ToolIcons.image(id, tint: isSelected ? nil : NSColor(white: 224 / 255, alpha: 1))
            b.contentTintColor = isSelected ? .black : nil
        }
    }

    @objc private func pick(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        // Все инструменты выбираются и показывают свою панель (как у образца); на холсте пока работают
        // только сделанные (CanvasTool), остальные щелчком по холсту ничего не делают.
        guard ToolStrip.toolIDs.contains(id) else {
            NSSound.beep()
            // Переключатель уже сменил состояние — вернуть выбор текущему инструменту.
            if let current = controller?.selectedTool { update(selected: current) }
            return
        }
        controller?.run(id)
    }
}
#endif
