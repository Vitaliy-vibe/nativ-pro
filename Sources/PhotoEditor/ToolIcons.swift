#if canImport(AppKit)
import AppKit

/// Значки инструментов в стиле образца: плотные залитые фигуры 20×20, шаблонные (цвет задаёт кнопка).
/// Где у Apple есть такой же залитый символ — берём его; остальное нарисовано здесь.
/// Сверка с оригиналом: PhotoEditor --icon-sheet (лист «оригинал | наш», tools/run_app.sh).
enum ToolIcons {
    /// Картинка 29 × 29 — как значки полосы образца (icon_* 29 pt; сверка 26).
    static let side: CGFloat = 29

    /// Поправка размера по замеру сверки 17 (ширина/высота глифа у образца к нашей при общем 0,95).
    /// Сверка 19: у значков с меткой «…» в прошлый замер попадала и метка — сами глифы у образца крупнее
    /// и подняты над меткой; масштаб и сдвиг (точки значка, y вниз) — по рамке глифа на снимке.
    static let extraScale: [String: CGFloat] = [
        "tool.style": 1.2, "tool.adjustments": 0.94, "tool.effects": 1.26, "tool.lassoFree": 0.97, "tool.selectQuick": 1.21,
        "tool.paint": 1.28, "tool.fill": 1.13, "tool.erase": 1.57, "tool.repair": 1.32, "tool.sharpen": 1.46,
        "tool.lighten": 1.63, "tool.saturate": 1.03, "tool.distort": 1.43, "tool.pen": 1.14, "tool.shape": 1.17,
        "tool.type": 0.97, "tool.zoom": 1.26, "tool.crop": 1.49,
    ]
    /// Сверка 21: центры глифов у нас в среднем на 1–2,5 точки ниже, чем у образца; замер каждого (без области метки).
    static let offset: [String: NSPoint] = [
        "tool.style": NSPoint(x: 1, y: -3.5), "tool.adjustments": NSPoint(x: 1, y: -2), "tool.effects": NSPoint(x: -2.5, y: -3), "tool.selectRect": NSPoint(x: 0, y: -1),
        "tool.lassoFree": NSPoint(x: -0.5, y: -2), "tool.selectQuick": NSPoint(x: 1.2, y: -2.1), "tool.paint": NSPoint(x: 1.9, y: -1.0),
        "tool.fill": NSPoint(x: 0.2, y: -2.6), "tool.erase": NSPoint(x: 1.8, y: -1), "tool.repair": NSPoint(x: 0.5, y: -2),
        "tool.clone": NSPoint(x: 0, y: -2), "tool.sharpen": NSPoint(x: -0.5, y: -2), "tool.lighten": NSPoint(x: 1.1, y: -2.4),
        "tool.saturate": NSPoint(x: 1, y: -2.5), "tool.distort": NSPoint(x: -2, y: 0), "tool.pen": NSPoint(x: -1, y: -1),
        "tool.shape": NSPoint(x: -0.5, y: -1), "tool.type": NSPoint(x: -1, y: -0.5), "tool.zoom": NSPoint(x: 0, y: -2.5),
        "tool.crop": NSPoint(x: 0.7, y: -3.5),
    ]

    /// Поправка обведённых значков (сверка 24.10 по пикселям): у образца для экрана 1x своя картинка 29 px, подогнанная
    /// под пиксели, — у «Текста» ножка на полточки левее, ведро «Заливки» на ~0,6 точки уже и ниже по верху,
    /// рамка «Обрезать» на точку уже (стойки 10,2 и 19,8 против наших 9,8 и 20,4) и на полточки ниже.
    /// (сдвиг, масштаб по x и y вокруг точки-опоры) в точках клетки 29 × 29, y вниз.
    static let tracedNudge: [String: (shift: NSPoint, scale: CGSize, anchor: NSPoint)] = [
        "tool.type": (NSPoint(x: -0.5, y: 0), CGSize(width: 0.977, height: 1), NSPoint(x: 14.5, y: 0)),   // концы перекладины 104, не 128
        "tool.fill": (.zero, CGSize(width: 0.95, height: 0.95), NSPoint(x: 7.75, y: 22.25)),
        "tool.crop": (NSPoint(x: 0.4, y: -0.2), CGSize(width: 0.906, height: 0.97), NSPoint(x: 9.8, y: 10)),
    ]

    /// Инструменты с вариантами (в образце — значок «…» в углу).
    static let withVariants: Set<String> = [
        "tool.selectRect", "tool.lassoFree", "tool.selectQuick", "tool.paint", "tool.fill", "tool.erase",
        "tool.sharpen", "tool.lighten", "tool.saturate", "tool.distort", "tool.pen", "tool.shape", "tool.type", "tool.crop",
    ]

    /// tint — готовый цвет вместо шаблона: невыбранная кнопка-переключатель AppKit рисует шаблонный значок тусклее
    /// (сверка 16: яркость линий 75–170 против 224 у образца), поэтому невыбранные значки красятся заранее.
    static func image(_ id: String, badge: Bool = true, tint: NSColor? = nil) -> NSImage {
        let img = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            NSColor.black.set()
            if let traced = TracedIcons.layers[id] {
                // Контуры, обведённые по картинке образца (клетка 29 × 29 = вся картинка значка), по уровням
                // прозрачности снизу вверх; «копия» — каждый уровень заменяет прозрачность под собой, а не копит её.
                // Сверка 26: картинка у образца на 1 точку выше центра кнопки.
                NSGraphicsContext.saveGraphicsState()
                let t = NSAffineTransform()
                t.translateX(by: 0, yBy: -1)
                if let n = tracedNudge[id] {
                    t.translateX(by: n.shift.x + n.anchor.x, yBy: n.shift.y + n.anchor.y)
                    t.scaleX(by: n.scale.width, yBy: n.scale.height)
                    t.translateX(by: -n.anchor.x, yBy: -n.anchor.y)
                }
                t.concat()
                NSGraphicsContext.current?.compositingOperation = .copy
                for (opacity, d) in traced {
                    let path = tracedPath(d)
                    path.windingRule = .evenOdd
                    NSColor(white: 0, alpha: opacity).setFill()
                    path.fill()
                }
                NSGraphicsContext.restoreGraphicsState()
            } else {
                // Глиф у образца занимает ~80 % клетки — уменьшаем вокруг центра.
                NSGraphicsContext.saveGraphicsState()
                let t = NSAffineTransform()
                let shift = offset[id] ?? .zero
                t.translateX(by: side / 2 + shift.x, yBy: side / 2 + shift.y)
                // Рисунки заданы в клетке 20 × 20. Сверка 17 по пикселям: при 0,86 глифы мельче, чем у образца, на ~10 %,
                // отдельные (extraScale) — на 20–40 %.
                t.scale(by: 22 / 20 * 0.95 * (extraScale[id] ?? 1))   // рисунки без контура — прежний размер (22)
                t.translateX(by: -10, yBy: -10)
                t.concat()
                draw(id)
                NSGraphicsContext.restoreGraphicsState()
            }
            if badge && withVariants.contains(id) {
                // Значок «…» рисуется в клетке 20 × 20, прижатой к правому нижнему углу.
                NSGraphicsContext.saveGraphicsState()
                let b = NSAffineTransform()
                b.translateX(by: side - 20, yBy: side - 20)
                b.concat()
                drawBadge()
                NSGraphicsContext.restoreGraphicsState()
            }
            if let tint {
                tint.set()
                NSRect(x: 0, y: 0, width: side, height: side).fill(using: .sourceAtop)
            }
            return true
        }
        img.isTemplate = tint == nil
        return img
    }

    // MARK: помощники

    /// Контур из строки TracedIcons: команды M x y / L x y / C x1 y1 x2 y2 x y / Z.
    static func tracedPath(_ text: String) -> NSBezierPath {
        let path = NSBezierPath()
        let t = text.split(separator: " ")
        var i = 0
        func n(_ k: Int) -> CGFloat { CGFloat(Double(t[i + k]) ?? 0) }
        while i < t.count {
            switch t[i] {
            case "M": path.move(to: NSPoint(x: n(1), y: n(2))); i += 3
            case "L": path.line(to: NSPoint(x: n(1), y: n(2))); i += 3
            case "C": path.curve(to: NSPoint(x: n(5), y: n(6)), controlPoint1: NSPoint(x: n(1), y: n(2)), controlPoint2: NSPoint(x: n(3), y: n(4))); i += 7
            case "Z": path.close(); i += 1
            default: i += 1
            }
        }
        return path
    }

    private static func symbol(_ name: String, in rect: NSRect, weight: NSFont.Weight = .semibold, rotate: CGFloat = 0) {
        guard let s = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: rect.height, weight: weight)) else { return }
        // Вписать с сохранением пропорций.
        let k = min(rect.width / s.size.width, rect.height / s.size.height)
        let w = s.size.width * k, h = s.size.height * k
        let r = NSRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        if rotate != 0 {
            let t = NSAffineTransform()
            t.translateX(by: rect.midX, yBy: rect.midY)
            t.rotate(byDegrees: rotate)
            t.translateX(by: -rect.midX, yBy: -rect.midY)
            t.concat()
        }
        s.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
    }

    private static func fill(_ p: NSBezierPath, alpha: CGFloat = 1) {
        NSColor(white: 0, alpha: alpha).setFill()
        p.fill()
    }

    /// Стереть фигуру (прозрачный зазор между частями значка).
    private static func clear(_ p: NSBezierPath, stroke width: CGFloat? = nil) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.set()
        if let width {
            p.lineWidth = width
            p.stroke()
        } else {
            p.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func star(cx: CGFloat, cy: CGFloat, outer: CGFloat, inner: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        for i in 0..<10 {
            let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
            let r = i % 2 == 0 ? outer : inner
            let pt = NSPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.line(to: pt) }
        }
        p.close()
        return p
    }

    /// «…» в правом нижнем углу: у инструмента есть варианты.
    /// Метка «…» как у образца (сверка 16 по пикселям): яркий кружок диаметром 9 с центром в (17,5; 15,5)
    /// значка, вокруг — прозрачный зазор 1, внутри три точки через 2,2. Клетка сдвинута на 2 (см. image).
    private static func drawBadge() {
        // Центр метки — на (6,5; 4,5) от центра значка (замер сверки 16 при картинке 22); клетка сдвинута на side − 20.
        // Сверка 24.10 по пикселям: у образца кружок 9 × 9 с центром в середине пикселя (у нас был на полточки выше
        // и левее — размазывался на 10) и точки через 2,5.
        let cx: CGFloat = side / 2 + 7 - (side - 20), cy: CGFloat = side / 2 + 5 - (side - 20)
        clear(circle(cx, cy, 5.5))
        fill(circle(cx, cy, 4.5))
        for dx in [-2.5, 0, 2.5] as [CGFloat] { clear(circle(cx + dx, cy, 0.75)) }
    }

    // MARK: значки

    private static func draw(_ id: String) {
        switch id {
        case "tool.arrange":
            symbol("cursorarrow", in: NSRect(x: 3, y: 2, width: 14, height: 16), weight: .bold)
        case "tool.style":
            symbol("paintbrush.fill", in: NSRect(x: 2, y: 2, width: 16, height: 16))
        case "tool.adjustments":
            for (x, y) in [(7.0, 7.5), (13.0, 7.5), (10.0, 12.8)] as [(CGFloat, CGFloat)] { fill(circle(x, y, 5.2), alpha: 0.5) }
        case "tool.effects":
            // Звезда в горизонтальных полосах, ярче справа — «эффект в движении».
            let s = star(cx: 10.5, cy: 10.5, outer: 8.5, inner: 3.6)
            NSGraphicsContext.saveGraphicsState()
            s.addClip()
            let g = NSGradient(starting: NSColor(white: 0, alpha: 0.15), ending: .black)
            // Полосы под наклоном, к левому краю гаснут.
            for k in stride(from: CGFloat(-20), to: 30, by: 2.2) {
                let band = NSBezierPath()
                band.move(to: NSPoint(x: 0, y: k + 12))
                band.line(to: NSPoint(x: 20, y: k))
                band.line(to: NSPoint(x: 20, y: k + 1.3))
                band.line(to: NSPoint(x: 0, y: k + 13.3))
                band.close()
                NSGraphicsContext.saveGraphicsState()
                band.addClip()
                g?.draw(in: NSRect(x: 0, y: 0, width: 20, height: 20), angle: 0)
                NSGraphicsContext.restoreGraphicsState()
            }
            NSGraphicsContext.restoreGraphicsState()
        case "tool.selectRect":
            let p = NSBezierPath(rect: NSRect(x: 3, y: 3, width: 12, height: 12))
            p.lineWidth = 1.5
            p.lineCapStyle = .round
            p.setLineDash([1.2, 2.1], count: 2, phase: 0)
            p.stroke()
        case "tool.lassoFree":
            // Пунктирная петля лассо с хвостиком.
            let loop = NSBezierPath()
            loop.move(to: NSPoint(x: 7, y: 17))
            loop.curve(to: NSPoint(x: 6, y: 11), controlPoint1: NSPoint(x: 9, y: 15), controlPoint2: NSPoint(x: 8, y: 12))
            loop.curve(to: NSPoint(x: 9, y: 3), controlPoint1: NSPoint(x: 2, y: 9), controlPoint2: NSPoint(x: 4, y: 3))
            loop.curve(to: NSPoint(x: 16, y: 7), controlPoint1: NSPoint(x: 13, y: 3), controlPoint2: NSPoint(x: 17, y: 4))
            loop.curve(to: NSPoint(x: 9, y: 12), controlPoint1: NSPoint(x: 15, y: 10), controlPoint2: NSPoint(x: 12, y: 12))
            loop.curve(to: NSPoint(x: 6, y: 11), controlPoint1: NSPoint(x: 8, y: 12), controlPoint2: NSPoint(x: 7, y: 11.5))
            loop.lineWidth = 1.7
            loop.lineCapStyle = .round
            loop.setLineDash([0.1, 2.4], count: 2, phase: 0)
            loop.stroke()
        case "tool.selectQuick":
            let p = circle(8, 11, 5.6)
            p.lineWidth = 1.5
            p.setLineDash([1.6, 1.4], count: 2, phase: 0)
            p.stroke()
            clear(NSBezierPath(rect: NSRect(x: 9, y: 1, width: 10, height: 9)))
            symbol("paintbrush.pointed.fill", in: NSRect(x: 9, y: 1, width: 9, height: 9))
        case "tool.paint":
            symbol("paintbrush.pointed.fill", in: NSRect(x: 2, y: 2, width: 14, height: 14))
        case "tool.fill":
            // Ведро с краской: корпус, светлый ободок сверху.
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 4, y: 5))
            body.line(to: NSPoint(x: 14, y: 5))
            body.line(to: NSPoint(x: 13, y: 15.5))
            body.curve(to: NSPoint(x: 5, y: 15.5), controlPoint1: NSPoint(x: 12.4, y: 17.5), controlPoint2: NSPoint(x: 5.6, y: 17.5))
            body.close()
            fill(body)
            clear(NSBezierPath(ovalIn: NSRect(x: 5, y: 4, width: 8, height: 2.6)))
            fill(NSBezierPath(ovalIn: NSRect(x: 6, y: 4.4, width: 6, height: 1.6)), alpha: 0.45)
            // Потёк краски через край.
            clear(NSBezierPath(roundedRect: NSRect(x: 8.6, y: 5.6, width: 3.2, height: 6.4), xRadius: 1.6, yRadius: 1.6))
            fill(NSBezierPath(roundedRect: NSRect(x: 9.2, y: 5.6, width: 2, height: 5.6), xRadius: 1, yRadius: 1), alpha: 0.45)
        case "tool.erase":
            symbol("eraser.fill", in: NSRect(x: 2, y: 2, width: 14, height: 14))
        case "tool.repair":
            symbol("bandage.fill", in: NSRect(x: 2, y: 2, width: 16, height: 16))
        case "tool.clone":
            // Источник (залитый круг) и его копия — пунктир со стрелкой.
            fill(circle(8, 10.5, 5.5))
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: 11, y: 10), radius: 7, startAngle: -70, endAngle: 120)
            arc.lineWidth = 1.4
            arc.setLineDash([1.6, 1.4], count: 2, phase: 0)
            arc.stroke()
            let head = NSBezierPath()
            head.move(to: NSPoint(x: 12.5, y: 1.2))
            head.line(to: NSPoint(x: 16.5, y: 3.5))
            head.line(to: NSPoint(x: 12.8, y: 5.6))
            head.close()
            fill(head)
        case "tool.sharpen":
            // Растр точек: крупные в центре, мельче к краю.
            for y in stride(from: CGFloat(2), through: 18, by: 1.45) {
                for x in stride(from: CGFloat(2) + (Int(y / 1.45) % 2 == 0 ? 0 : 0.72), through: 18, by: 1.45) {
                    let d = hypot(x - 10, y - 10)
                    guard d <= 8.3 else { continue }
                    fill(circle(x, y, 0.62 - d * 0.045))
                }
            }
        case "tool.lighten":
            symbol("sun.max.fill", in: NSRect(x: 2, y: 2, width: 15, height: 15))
        case "tool.saturate":
            for (x, y, a) in [(7.5, 7, 0.55), (12.5, 7, 0.4), (14, 11.5, 0.5), (10, 14, 0.45), (6, 11.5, 0.6)] as [(CGFloat, CGFloat, CGFloat)] {
                fill(circle(x, y, 4.3), alpha: a)
            }
        case "tool.distort":
            symbol("hand.point.up.left.fill", in: NSRect(x: 3, y: 4, width: 14, height: 14), rotate: 160)
            let arrow = NSBezierPath()
            arrow.appendArc(withCenter: NSPoint(x: 13, y: 7), radius: 4.5, startAngle: 200, endAngle: 300)
            arrow.lineWidth = 1.3
            arrow.stroke()
        case "tool.pen":
            // Перо (наконечник): рисуем остриём вниз и поворачиваем остриём влево-вниз.
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform()
            t.translateX(by: 10, yBy: 10)
            t.rotate(byDegrees: 45)
            t.translateX(by: -10, yBy: -10)
            t.concat()
            let nib = NSBezierPath()
            nib.move(to: NSPoint(x: 10, y: 19))
            nib.curve(to: NSPoint(x: 5.6, y: 9.5), controlPoint1: NSPoint(x: 8, y: 15.5), controlPoint2: NSPoint(x: 5.6, y: 12))
            nib.line(to: NSPoint(x: 7.4, y: 6.4))
            nib.line(to: NSPoint(x: 12.6, y: 6.4))
            nib.line(to: NSPoint(x: 14.4, y: 9.5))
            nib.curve(to: NSPoint(x: 10, y: 19), controlPoint1: NSPoint(x: 14.4, y: 12), controlPoint2: NSPoint(x: 12, y: 15.5))
            nib.close()
            fill(nib)
            clear(circle(10, 11.3, 1.3))
            let slit = NSBezierPath()
            slit.move(to: NSPoint(x: 10, y: 11.3))
            slit.line(to: NSPoint(x: 10, y: 19.5))
            clear(slit, stroke: 0.8)
            fill(NSBezierPath(roundedRect: NSRect(x: 7.3, y: 1.5, width: 5.4, height: 3.6), xRadius: 0.8, yRadius: 0.8))
            NSGraphicsContext.restoreGraphicsState()
        case "tool.shape":
            let back = NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: 11, height: 11), xRadius: 3, yRadius: 3)
            fill(back, alpha: 0.6)
            let front = NSBezierPath(roundedRect: NSRect(x: 6.5, y: 6.5, width: 10.5, height: 10.5), xRadius: 3, yRadius: 3)
            clear(front, stroke: 2.4)
            fill(front)
        case "tool.type":
            fill(NSBezierPath(rect: NSRect(x: 4, y: 3, width: 12, height: 1.6)))
            fill(NSBezierPath(rect: NSRect(x: 9.2, y: 3, width: 1.6, height: 14)))
        case "tool.zoom":
            symbol("magnifyingglass", in: NSRect(x: 2, y: 2, width: 16, height: 16), weight: .medium)
        case "tool.crop":
            symbol("crop", in: NSRect(x: 2, y: 2, width: 16, height: 16), weight: .medium)
        case "tool.hand":
            symbol("hand.raised.fill", in: NSRect(x: 2, y: 2, width: 16, height: 16))
        case "tools.more":
            for x in [5.0, 10.0, 15.0] as [CGFloat] { fill(circle(x, 10, 1.4)) }
        default:
            symbol("questionmark", in: NSRect(x: 4, y: 4, width: 12, height: 12))
        }
    }

    /// Значок пункта меню для картинок образца icon-menu-… — наш рисунок того же инструмента (если он нарисован).
    static func menuImage(_ name: String) -> NSImage? {
        guard name.hasPrefix("icon-menu-") else { return nil }
        let tool = String(name.dropFirst("icon-menu-".count))
        let map = ["arrange": "tool.arrange", "style": "tool.style", "adjustments": "tool.adjustments", "effects": "tool.effects",
                   "rectangularselection": "tool.selectRect", "freeselection": "tool.lassoFree", "quickselection": "tool.selectQuick",
                   "paint": "tool.paint", "fill": "tool.fill", "erase": "tool.erase", "repair": "tool.repair", "clone": "tool.clone",
                   "sharpen": "tool.sharpen", "lighten": "tool.lighten", "saturate": "tool.saturate", "distort": "tool.distort",
                   "pen": "tool.pen", "type": "tool.type", "zoom": "tool.zoom", "crop": "tool.crop", "hand": "tool.hand"]
        guard let id = map[tool] else { return nil }
        let img = image(id, badge: false)
        img.size = NSSize(width: 16, height: 16)
        return img
    }

    // MARK: лист сверки с оригиналом

    /// Имена картинок образца (Assets.car), с которыми сверяется каждый наш значок.
    static let references: [(id: String, reference: String)] = [
        ("tool.arrange", "icon-menu-arrange"), ("tool.style", "icon-menu-style"), ("tool.adjustments", "icon-menu-adjustments"),
        ("tool.effects", "icon-menu-effects"), ("tool.selectRect", "icon-menu-rectangularselection"), ("tool.lassoFree", "icon-menu-freeselection"),
        ("tool.selectQuick", "icon-menu-quickselection"), ("tool.paint", "icon-menu-paint"), ("tool.fill", "icon-menu-fill"),
        ("tool.erase", "icon-menu-erase"), ("tool.repair", "icon-menu-repair"), ("tool.clone", "icon-menu-clone"),
        ("tool.sharpen", "icon-menu-sharpen"), ("tool.lighten", "icon-menu-lighten"), ("tool.saturate", "icon-menu-saturate"),
        ("tool.distort", "icon-menu-distort"), ("tool.pen", "icon-menu-pen"), ("tool.shape", "icon-menu-polygon"),
        ("tool.type", "icon-menu-type"), ("tool.zoom", "icon-menu-zoom"), ("tool.crop", "icon-menu-crop"), ("tool.hand", "icon-menu-hand"),
    ]

    /// Лист PNG: в каждой строке — оригинал из выгрузки (если есть) и наш значок, белым на тёмном, ×4.
    static func writeSheet(referenceDir: String, to path: String) -> Bool {
        let cell: CGFloat = 96, label: CGFloat = 130
        let width = label + 2 * cell, height = cell * CGFloat(references.count)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.17, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        for (i, entry) in references.enumerated() {
            let y = height - CGFloat(i + 1) * cell
            (entry.id as NSString).draw(at: NSPoint(x: 6, y: y + cell / 2 - 7),
                                        withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12)])
            let refPath = (referenceDir as NSString).appendingPathComponent(entry.reference + ".png")
            if let ref = NSImage(contentsOfFile: refPath) {
                ref.draw(in: NSRect(x: label + 8, y: y + 8, width: cell - 16, height: cell - 16))
            }
            white(image(entry.id)).draw(in: NSRect(x: label + cell + 8, y: y + 8, width: cell - 16, height: cell - 16))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return FileManager.default.createFile(atPath: path, contents: data)
    }

    /// Шаблонный значок, окрашенный в белый (для листа сверки).
    private static func white(_ template: NSImage) -> NSImage {
        NSImage(size: template.size, flipped: false) { r in
            template.draw(in: r)
            NSColor.white.set()
            r.fill(using: .sourceAtop)
            return true
        }
    }
}
#endif
