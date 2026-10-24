#if canImport(AppKit)
import AppKit
import EditorApp

/// «Цветокоррекция» (замеры образца 20.10): коллекция («Современная фотопленка», пустые плитки), «Автоулучшение»,
/// под ним прокручиваемый список регулировок (с 274 до 59 от низа; высота содержимого 2075): раскрыты «Гистограмма»,
/// «Баланс белого», «Основные», «Цветовой баланс», остальные свёрнуты; внизу «сравнить» и «Сбросить».
/// Координаты карточек — от верха их строки (строка = y из замера − 274).
final class AdjustmentsPanel: ToolPanel {
    private let histogram = HistogramView()

    init() {
        let t = AppInfo.tr
        super.init(title: ToolPanel.titles["tool.adjustments"]!, header: ToolPanel.headers["tool.adjustments"]!)
        collectionPopup(t("Modern Film", "Современная фотопленка"), tip: t("Choose a color adjustments collection.", "Выбрать коллекцию цветокоррекции."))
        let grid = PresetGrid(gradients: [])
        grid.emptyTiles = true
        placeGrid(grid)
        line(202)
        let auto = wideButton(t("Auto Enhance", "Автоулучшение"),
                              t("Click to automatically enhance the color balance and exposure of the image.",
                                "Нажмите, чтобы автоматически улучшить баланс цвета и экспозицию изображения."), 15, 216, 242)
        auto.setButtonType(.pushOnPushOff)
        line(259)

        let list = FlippedView()
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = list
        list.frame = NSRect(x: 0, y: 0, width: Theme.optionsWidth, height: 2075)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.widthAnchor.constraint(equalToConstant: Theme.optionsWidth),
            scroll.topAnchor.constraint(equalTo: topAnchor, constant: 274),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -59),
        ])

        let change = t("Turn this adjustment on or off.", "Включить/выключить эту регулировку.")
        // Гистограмма: без «Сбросить» и «автоматически».
        let hist = card(t("Histogram", "Гистограмма"), y: 0, height: 164, on: true, auto: nil, reset: false, in: list,
                        switchTip: t("Turn the histogram on or off.", "Включить/выключить гистограмму."))
        histogram.frame = NSRect(x: 28, y: 42, width: 216, height: 100)
        hist.addSubview(histogram)

        let white = card(t("White Balance", "Баланс белого"), y: 164, height: 171, on: true,
                         auto: t("Click to automatically adjust the white balance.", "Нажать, чтобы автоматически отрегулировать баланс белого."),
                         reset: true, in: list, switchTip: change)
        label(t("Gray", "Серый"), 27, 45, 42, 17, in: white)
        let picker = ToggleIconButton(symbol: "eyedropper", plate: true)
        picker.toolTip = t("Click to set the white balance by picking a neutral gray in the image.",
                           "Нажмите, чтобы установить баланс белого, выбрав нейтральный серый цвет в изображении.")
        picker.place(in: white, x: 213, y: 41, w: 32, h: 26)
        adjustmentRow(t("Temperature", "Температура"), y: 74, in: white,
                      gradient: [NSColor(srgbRed: 45 / 255, green: 169 / 255, blue: 251 / 255, alpha: 1),
                                 NSColor(srgbRed: 251 / 255, green: 189 / 255, blue: 65 / 255, alpha: 1)],
                      fieldTip: t("Set the overall temperature of the image to make it warmer or cooler.", "Задайте общую температуру изображения, чтобы сделать его теплее или холоднее."),
                      sliderTip: t("Adjust the overall temperature of the image to make it warmer or cooler.", "Настроить общую температуру изображения, чтобы сделать его теплее или холоднее."))
        adjustmentRow(t("Tint", "Оттенок"), y: 112, in: white,
                      gradient: [NSColor(srgbRed: 52 / 255, green: 198 / 255, blue: 73 / 255, alpha: 1),
                                 NSColor(srgbRed: 250 / 255, green: 68 / 255, blue: 186 / 255, alpha: 1)],
                      fieldTip: t("Set the overall tint of the image.", "Задать общий оттенок изображения."),
                      sliderTip: t("Adjust the overall tint of the image.", "Настроить общий оттенок изображения."))

        let basics = card(t("Basics", "Основные"), y: 335, height: 364, on: true,
                          auto: t("Click to automatically adjust the basics.", "Нажать, чтобы автоматически отрегулировать основные параметры."),
                          reset: true, in: list, switchTip: change)
        let rows: [(String, String, String)] = [
            (t("Exposure", "Экспозиция"), t("Set the overall amount of light in the image.", "Задайте общее количество света изображения."),
             t("Adjust the overall amount of light in the image.", "Настроить общее количество света на изображении.")),
            (t("Highlights", "Акценты"), t("Set the overall brightness of the lightest areas of the image.", "Задайте общее осветление самых ярких участков изображения."),
             t("Adjust the overall brightness of the lightest areas of the image.", "Настроить общую осветленность самых ярких участков изображения.")),
            (t("Shadows", "Тени"), t("Set the overall brightness of the darkest areas of the image.", "Задайте общее осветление самых темных участков изображения."),
             t("Adjust the overall brightness of the darkest areas of the image.", "Настроить общую осветленность самых темных участков изображения.")),
            (t("Brightness", "Яркость"), t("Set the overall brightness of the midtones of the image.", "Задайте общее осветление полутоновых участков изображения."),
             t("Adjust the overall brightness of the midtones of the image.", "Настроить общую осветленность средних по яркости участков изображения.")),
            (t("Contrast", "Контраст"), t("Set the contrast between the light and dark areas of the image.", "Задайте контраст между светлыми и темными областями изображения."),
             t("Adjust the contrast between the lightest and darkest areas of the image.", "Настроить контраст между самыми светлыми и самыми темными областями изображения.")),
            (t("Black Point", "Точка черного"), t("Set the dynamic range of the dark areas in the image.", "Задайте динамический диапазон темных областей в изображении."),
             t("Adjust the dynamic range of the darkest areas of the image.", "Настроить динамический диапазон самых темных областей изображения.")),
            (t("Texture", "Текстура"), t("Set the overall sharpness and focus of the fine details of the image.", "Задать общую резкость и фокус мелких деталей изображения."),
             t("Adjust the overall sharpness and focus of the fine details of the image.", "Настроить общую резкость и фокус мелких деталей изображения.")),
            (t("Clarity", "Четкость"), t("Set the overall structure and contrast of the fine details of the image.", "Задать общую структуру и контраст мелких деталей изображения."),
             t("Adjust the overall structure and contrast of the fine details of the image.", "Настроить общую структуру и контрастность мелких деталей изображения.")),
        ]
        for (i, (name, fieldTip, sliderTip)) in rows.enumerated() {
            adjustmentRow(name, y: 39 + CGFloat(i) * 38, in: basics, gradient: nil, fieldTip: fieldTip, sliderTip: sliderTip)
        }

        card(t("Selective Clarity", "Выборочная четкость"), y: 699, height: 52, on: false, auto: nil, reset: true, in: list, switchTip: change)
        card(t("Hue & Saturation", "Тон и\u{00A0}насыщенность"), y: 751, height: 67, on: false,
             auto: t("Click to automatically adjust the hue and saturation.", "Нажмите, чтобы автоматически настроить тон и насыщенность."),
             reset: true, in: list, switchTip: change)
        card(t("Selective Color", "Выборочный цвет"), y: 818, height: 52, on: false,
             auto: t("Click to automatically adjust the selective color.", "Нажать, чтобы автоматически отрегулировать выборочный цвет."),
             reset: true, in: list, switchTip: change)
        let balance = card(t("Color Balance", "Цветовой баланс"), y: 870, height: 539, on: true,
                           auto: t("Click to automatically adjust the color balance.", "Нажать, чтобы автоматически отрегулировать цветовой баланс."),
                           reset: true, in: list, switchTip: change)
        let mode = NSPopUpButton()
        mode.addItems(withTitles: [t("Three-Way Color", "Трехвариантный цвет"), t("Two-Way Color", "Двухвариантный цвет")])
        mode.bezelColor = NSColor(white: 96 / 255, alpha: 1)
        mode.place(in: balance, x: 27, y: 41, w: 218, h: 26)
        for (i, name) in [t("Highlights", "Акценты"), t("Midtones", "Полутона"), t("Shadows", "Тени")].enumerated() {
            let top = CGFloat(i) * 149
            let wheel = ColorWheelView()
            wheel.frame = NSRect(x: 80, y: 84 + top, width: 112, height: 112)
            balance.addSubview(wheel)
            // Подпись по ширине текста, по центру круга (x 136).
            let caption = NSTextField(labelWithString: name)
            caption.font = .systemFont(ofSize: 12)
            caption.translatesAutoresizingMaskIntoConstraints = false
            balance.addSubview(caption)
            NSLayoutConstraint.activate([
                caption.centerXAnchor.constraint(equalTo: balance.leadingAnchor, constant: 136),
                caption.topAnchor.constraint(equalTo: balance.topAnchor, constant: 201 + top),
                // Сверка 24.10: у образца рамка подписи на 4 точки шире текста при том же центре.
                caption.widthAnchor.constraint(equalToConstant: ceil(caption.intrinsicContentSize.width) + 4),
            ])
            caption.alignment = .center
            // Системное название значка, как у образца («Стрелка с треугольным наконечником… против часовой стрелки»);
            // неактивна, пока круг не меняли (сверка 24.10).
            let undo = NSButton(image: NSImage(systemSymbolName: "arrow.trianglehead.counterclockwise", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .regular)) ?? NSImage(), target: nil, action: nil)
            undo.isBordered = false
            undo.imagePosition = .imageOnly
            undo.contentTintColor = .labelColor
            undo.toolTip = t("Reset", "Сбросить")
            undo.isEnabled = false
            undo.place(in: balance, x: 228, y: 88 + top, w: 18, h: 18)
        }
        let collapsed = [t("Levels", "Уровни"), t("Curves", "Кривые"), t("Replace Color", "Замена цвета"), t("Remove Color", "Удалить цвет"),
                         t("Fade", "Затухание"), t("Black & White", "Монохром"), t("Color Monochrome", "Монохромный цвет"),
                         t("Channel Mixer", "Микшер каналов"), "LUT", t("Vignette", "Виньетка"), t("Sharpen", "Резкость"), t("Grain", "Зерно")]
        for (i, name) in collapsed.enumerated() {
            card(name, y: 1409 + CGFloat(i) * 52, height: 52, on: false, auto: nil, reset: true, in: list, switchTip: change)
        }
        let customize = wideButton(t("Customize", "Настроить"), t("Customize the visibility of individual color adjustments.", "Настройте видимость индивидуальной цветокоррекции."), 15, 0, 242)
        customize.removeFromSuperview()
        customize.place(in: list, x: 15, y: 2032, w: 242, h: 30)

        compareAndReset(compareTip: t("Show how the object looks without any color adjustments.", "Показать, как выглядит объект без цветокоррекции."),
                        resetTip: t("Reset the color adjustments of the object to their defaults.", "Сбросить цветокоррекцию объекта к значениям по умолчанию."))
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    /// Гистограмма — по всему документу.
    override func update() {
        guard let controller, let img = try? controller.canvas.renderer.renderWhole(controller.session.document),
              let cg = ImageFiles.cgImage(img) else { return }
        histogram.image = cg
    }

    /// Карточка регулировки: подложка 71 (240 × высота − 10, скругление 14), название 12 полужирное, справа
    /// переключатель; «Сбросить» (не видна, пока нечего сбрасывать) — 17 × 17 в 148 (с «автоматически») или 175,
    /// «автоматически» — палочка 29 × 20 в 168. В высоких строках (двухстрочное название) всё ниже на 7.
    @discardableResult
    private func card(_ title: String, y: CGFloat, height: CGFloat, on: Bool, auto: String?, reset: Bool, in list: NSView,
                      switchTip: String) -> NSView {
        let card = FlippedView(frame: NSRect(x: 0, y: y, width: Theme.optionsWidth, height: height))
        list.addSubview(card)
        let plate = NSView(frame: NSRect(x: 16, y: 0, width: 240, height: height - 10))
        plate.wantsLayer = true
        plate.layer?.backgroundColor = NSColor(white: 71 / 255, alpha: 1).cgColor
        plate.layer?.cornerRadius = 14
        card.addSubview(plate)
        let dy: CGFloat = height == 67 ? 7 : 0
        let name = NSTextField(wrappingLabelWithString: title)
        name.font = .systemFont(ofSize: 12, weight: .bold)   // как в StyleCard (сверка 24.10)
        name.preferredMaxLayoutWidth = height == 67 ? 119 : 200
        name.place(in: card, x: 27, y: 12, w: height == 67 ? 121 : nil)
        let toggle = NSSwitch()
        toggle.controlSize = .small
        toggle.state = on ? .on : .off
        toggle.toolTip = switchTip
        toggle.place(in: card, x: 205, y: 8 + dy, w: 34, h: 26)   // рамка как у образца, см. StyleCard
        if reset {
            // У образца кнопка есть, но не нарисована, пока регулировка не изменена.
            let b = NSButton(image: NSImage(size: NSSize(width: 15, height: 15)), target: nil, action: nil)
            b.isBordered = false
            b.isEnabled = false
            b.setAccessibilityLabel(AppInfo.tr("Reset", "Сбросить"))
            b.place(in: card, x: auto == nil ? 175 : 148, y: 12 + dy + (dy > 0 ? 1 : 0), w: 17, h: 17)
        }
        if let auto {
            let wand = ToggleIconButton(symbol: "wand.and.sparkles", plate: false)
            wand.toolTip = auto
            wand.setAccessibilityLabel(AppInfo.tr("Adjust Automatically", "Настроить автоматически"))
            wand.place(in: card, x: 168, y: 13 + dy, w: 29, h: 20)
        }
        return card
    }

    /// «Название … 0 %» и ползунок с ручкой посередине (у «Баланса белого» — с цветной дорожкой): подпись в y + 3,
    /// число 58 × 24 с x = 187, ползунок 218 × 24 на 16 ниже.
    private func adjustmentRow(_ title: String, y: CGFloat, in card: NSView, gradient: [NSColor]?, fieldTip: String, sliderTip: String) {
        label(title, 27, y + 3, nil, 17, in: card)
        numberField("0\u{00A0}%", tip: fieldTip, NSRect(x: 187, y: y, width: 58, height: 24), in: card)
        let slider = PointerSlider(value: 0, minValue: -100, maxValue: 100, target: nil, action: nil)
        slider.capsule = true
        slider.style(filled: false, ticks: .none)
        (slider.cell as? PointerSliderCell)?.gradient = gradient
        slider.toolTip = sliderTip
        slider.place(in: card, x: 27, y: y + 16, w: 218, h: 24)
    }
}

/// Вид с началом координат вверху (содержимое списка и карточки по замерам сверху вниз).
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Кнопка-переключатель со значком («пипетка» баланса белого — на подложке белый 13 %, «автоматически» — без неё).
final class ToggleIconButton: NSButton {
    private let symbol: String
    private let plate: Bool

    init(symbol: String, plate: Bool) {
        self.symbol = symbol
        self.plate = plate
        super.init(frame: .zero)
        setButtonType(.pushOnPushOff)
        isBordered = false
        title = ""
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        imagePosition = .imageOnly
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        if plate {
            NSColor(white: 1, alpha: 0.13).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        }
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)
                .applying(.init(paletteColors: [state == .on ? Theme.accent : .labelColor]))) else { return }
        let s = image.size
        image.draw(in: NSRect(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2, width: s.width, height: s.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

/// Гистограмма документа (фон 77): яркость — серой заливкой, каналы R, G, B — линиями (снимок образца 20.10).
final class HistogramView: NSView {
    var image: CGImage? { didSet { recompute() } }
    private var bins: [[Double]] = []

    override var isFlipped: Bool { true }

    private func recompute() {
        defer { needsDisplay = true }
        guard let image else { bins = []; return }
        // Уменьшенная копия: на гистограмму хватает до 256 × 256.
        let k = min(1, 256 / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * k)), h = max(1, Int(Double(image.height) * k))
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var r = [Double](repeating: 0, count: 256), g = r, b = r, l = r
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 0 {
            let pr = Int(pixels[i]), pg = Int(pixels[i + 1]), pb = Int(pixels[i + 2])
            r[pr] += 1; g[pg] += 1; b[pb] += 1
            l[min(255, (pr * 299 + pg * 587 + pb * 114) / 1000)] += 1
        }
        bins = [l, r, g, b]
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 77 / 255, alpha: 1).setFill()
        bounds.fill()
        guard bins.count == 4 else { return }
        let top = max(bins.flatMap { $0 }.max() ?? 1, 1)
        func path(_ values: [Double], closed: Bool) -> NSBezierPath {
            let p = NSBezierPath()
            for (i, v) in values.enumerated() {
                let pt = NSPoint(x: bounds.width * CGFloat(i) / 255, y: bounds.height * (1 - CGFloat(v / top)))
                if i == 0 { closed ? p.move(to: NSPoint(x: 0, y: bounds.height)) : p.move(to: pt) }
                if i > 0 || closed { p.line(to: pt) }
            }
            if closed { p.line(to: NSPoint(x: bounds.width, y: bounds.height)); p.close() }
            return p
        }
        NSColor(white: 110 / 255, alpha: 1).setFill()
        path(bins[0], closed: true).fill()
        let colors = [NSColor(srgbRed: 0.92, green: 0.27, blue: 0.24, alpha: 1), NSColor(srgbRed: 0.55, green: 0.78, blue: 0.31, alpha: 1),
                      NSColor(srgbRed: 0.28, green: 0.57, blue: 0.95, alpha: 1)]
        for (values, color) in zip(bins.dropFirst(), colors) {
            color.setStroke()
            let p = path(values, closed: false)
            p.lineWidth = 1.5
            p.stroke()
        }
    }
}

/// Цветовой круг «Цветового баланса»: оттенок по кругу, насыщенность от центра (Core Image).
final class ColorWheelView: NSView {
    private lazy var wheel: CGImage? = {
        let d = 224.0
        guard let f = CIFilter(name: "CIHueSaturationValueGradient", parameters: ["inputRadius": d / 2, "inputValue": 1.0, "inputSoftness": 0.0]),
              let out = f.outputImage else { return nil }
        return CIContext().createCGImage(out, from: CGRect(x: -d / 2, y: -d / 2, width: d, height: d))
    }()

    override func draw(_ dirtyRect: NSRect) {
        guard let wheel, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.addEllipse(in: bounds)
        ctx.clip()
        ctx.draw(wheel, in: bounds)
        ctx.restoreGState()
        NSColor.white.setStroke()
        let dot = NSBezierPath(ovalIn: NSRect(x: bounds.midX - 4, y: bounds.midY - 4, width: 8, height: 8))
        dot.lineWidth = 1.5
        dot.stroke()
    }
}
#endif
