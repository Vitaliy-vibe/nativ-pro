#if canImport(AppKit)
import AppKit
import EditorApp
import EditorCore
import EditorRenderMetal

/// Инструменты холста этапа 2.
enum CanvasTool: String {
    case arrange = "tool.arrange"
    case hand = "tool.hand"
    case zoom = "tool.zoom"
    /// Инструмент полосы, который на холсте ещё не сделан: щелчки ничего не меняют.
    case inactive = "tool.inactive"
}

/// Рендер видимой области в фоне: одна очередь, из нескольких ожидающих запросов выполняется только последний.
final class CanvasRenderer {
    struct Job {
        var document: Document
        var region: RenderRegion
        var documentRect: PixelRect
        var completion: (CGImage?, PixelRect, String?) -> Void
    }

    private let queue = DispatchQueue(label: "canvas.render", qos: .userInteractive)
    private let lock = NSLock()
    private var next: Job?
    private var busy = false
    /// Metal, если есть; иначе эталонный CPU-рендер.
    private let metal: MetalRenderer? = try? MetalRenderer()

    func submit(_ job: Job) {
        lock.lock()
        next = job
        if busy {
            lock.unlock()
            return
        }
        busy = true
        lock.unlock()
        queue.async { self.drain() }
    }

    private func drain() {
        while true {
            lock.lock()
            guard let job = next else {
                busy = false
                lock.unlock()
                return
            }
            next = nil
            lock.unlock()
            var image: CGImage?
            var failure: String?
            do {
                let result = try metal?.render(job.document, region: job.region) ?? CPURenderer.render(job.document, region: job.region)
                image = ImageFiles.cgImage(result.image)
                if !result.unsupported.isEmpty {
                    failure = AppInfo.tr("Not shown yet: ", "Пока не показываются: ") + result.unsupported.map(\.name).joined(separator: ", ")
                }
            } catch {
                failure = "\(error)"
            }
            let rect = job.documentRect
            DispatchQueue.main.async { job.completion(image, rect, failure) }
        }
    }

    /// Весь документ в полном размере — для экспорта и «Скопировать сведённое».
    /// Идёт в той же очереди, что и рендер окна: MetalRenderer не рассчитан на одновременные вызовы.
    func renderWhole(_ document: Document) throws -> FloatImage {
        try queue.sync { try (metal?.render(document) ?? CPURenderer.render(document)).image }
    }
}

/// Холст: показывает документ в масштабе, двигает его жестами и колёсиком, передаёт щелчки инструментам.
final class CanvasView: NSView {
    weak var controller: EditorWindowController?
    let renderer = CanvasRenderer()
    private(set) var viewport = Viewport(documentWidth: 1, documentHeight: 1, viewWidth: 1, viewHeight: 1)
    private var image: CGImage?
    private var imageRect: PixelRect?
    private var requested = 0
    private var shown = 0
    private var spaceDown = false
    private var dragLast: NSPoint?
    private var handCursorPushed = false
    /// Накопленный дробный сдвиг слоя при перетаскивании (в пикселях документа).
    private var moveRemainder = (x: 0.0, y: 0.0)
    var tool: CanvasTool = .arrange { didSet { window?.invalidateCursorRects(for: self) } }
    /// Курсор над документом (для строки сведений).
    private(set) var cursorDocumentPoint: (x: Int, y: Int)?
    var onViewportChange: (() -> Void)?
    var renderProblem: String?

    private static let checker: NSColor = {
        let img = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            NSColor(white: 1, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 16, height: 16).fill()
            NSColor(white: 0.85, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 8, height: 8).fill()
            NSRect(x: 8, y: 8, width: 8, height: 8).fill()
            return true
        }
        return NSColor(patternImage: img)
    }()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        // С macOS 14 вид по умолчанию не обрезает рисование своими границами — фон холста заливал соседние колонки.
        clipsToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("не используется") }
    override var isOpaque: Bool { true }

    var backingScale: Double { Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1) }

    // MARK: размеры и масштаб

    /// Новый документ или изменился его размер — «по размеру окна».
    func resetViewport(for document: Document) {
        viewport = Viewport(documentWidth: document.width, documentHeight: document.height,
                            viewWidth: max(1, bounds.width * backingScale), viewHeight: max(1, bounds.height * backingScale))
        viewport.setInsets(ViewInsets(left: insetPoints.left * backingScale, right: insetPoints.right * backingScale, top: insetPoints.top * backingScale))
        image = nil
        imageRect = nil
        viewportChanged()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        viewport.resize(viewWidth: max(1, newSize.width * backingScale), viewHeight: max(1, newSize.height * backingScale))
        viewportChanged()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        viewport.resize(viewWidth: max(1, bounds.width * backingScale), viewHeight: max(1, bounds.height * backingScale))
        applyInsets()
    }

    /// Сколько точек слева и справа закрыто панелями (окно передаёт при показе и скрытии панелей).
    private var insetPoints = (left: 0.0, right: 0.0, top: 0.0)

    func setInsets(left: Double, right: Double, top: Double) {
        insetPoints = (left, right, top)
        applyInsets()
    }

    private func applyInsets() {
        let s = backingScale
        viewport.setInsets(ViewInsets(left: insetPoints.left * s, right: insetPoints.right * s, top: insetPoints.top * s))
        viewportChanged()
    }

    func setScale(_ scale: Double) { viewport.setScale(scale); viewportChanged() }

    func zoomIn() { viewport.zoomIn(); viewportChanged() }
    func zoomOut() { viewport.zoomOut(); viewportChanged() }
    func zoomToFit() { viewport.zoomToFit(); viewportChanged() }
    func actualSize() { viewport.actualSize(); viewportChanged() }

    private func viewportChanged() {
        requestRender()
        needsDisplay = true
        onViewportChange?()
    }

    // MARK: рендер

    func requestRender() {
        guard let doc = controller?.session.document else { return }
        if doc.width != viewport.documentWidth || doc.height != viewport.documentHeight {
            let insets = viewport.insets
            viewport = Viewport(documentWidth: doc.width, documentHeight: doc.height, viewWidth: viewport.viewWidth, viewHeight: viewport.viewHeight)
            viewport.setInsets(insets)
            image = nil
            onViewportChange?()
        }
        guard let visible = viewport.visibleRegion else {
            image = nil
            needsDisplay = true
            return
        }
        requested += 1
        let ticket = requested
        renderer.submit(.init(document: doc, region: visible.region, documentRect: visible.documentRect) { [weak self] img, rect, problem in
            guard let self, ticket > self.shown else { return }
            self.shown = ticket
            self.image = img
            self.imageRect = rect
            if self.renderProblem != problem {
                self.renderProblem = problem
                self.onViewportChange?()
            }
            self.needsDisplay = true
        })
    }

    /// Прямоугольник документа (в пикселях документа) → прямоугольник в точках окна.
    private func viewRect(_ r: PixelRect) -> NSRect {
        let a = viewport.viewPoint(documentX: Double(r.x), documentY: Double(r.y))
        let s = backingScale
        return NSRect(x: a.x / s, y: a.y / s, width: Double(r.width) * viewport.scale / s, height: Double(r.height) * viewport.scale / s)
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.canvasBackground.setFill()
        dirtyRect.intersection(bounds).fill()
        let docRect = viewRect(PixelRect(x: 0, y: 0, width: viewport.documentWidth, height: viewport.documentHeight))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.patternPhase = docRect.origin
        CanvasView.checker.setFill()
        docRect.intersection(dirtyRect).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let image, let imageRect else { return }
        let ctx = NSGraphicsContext.current
        ctx?.saveGraphicsState()
        NSBezierPath(rect: docRect).addClip()
        // Крупно — видны отдельные пиксели (как в образце), мельче — сглаживание.
        ctx?.imageInterpolation = viewport.scale >= 2 ? .none : .high
        let ns = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        ns.draw(in: viewRect(imageRect), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        ctx?.restoreGraphicsState()
    }

    // MARK: мышь и жесты

    private func pixelPoint(_ event: NSEvent) -> (x: Double, y: Double) {
        let p = convert(event.locationInWindow, from: nil)
        return (p.x * backingScale, p.y * backingScale)
    }

    private func documentPoint(_ event: NSEvent) -> (x: Double, y: Double) {
        let p = pixelPoint(event)
        return viewport.documentPoint(viewX: p.x, viewY: p.y)
    }

    private var effectiveTool: CanvasTool { spaceDown ? .hand : tool }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        dragLast = convert(event.locationInWindow, from: nil)
        moveRemainder = (0, 0)
        switch effectiveTool {
        case .zoom:
            let p = pixelPoint(event)
            if event.modifierFlags.contains(.option) {
                viewport.zoomOut(aroundViewX: p.x, viewY: p.y)
            } else {
                viewport.zoomIn(aroundViewX: p.x, viewY: p.y)
            }
            viewportChanged()
        case .arrange:
            // Щелчок вне выбранных слоёв выбирает верхний слой под курсором.
            guard let session = controller?.session else { return }
            let d = documentPoint(event)
            let x = Int(floor(d.x)), y = Int(floor(d.y))
            let insideSelected = session.selection.contains { id in
                guard let r = session.document.layer(id)?.bounds else { return false }
                return x >= r.x && y >= r.y && x < r.maxX && y < r.maxY
            }
            // Автовыбор (панель «Расстановка»): выключен — щелчок не меняет выбор; «Сгруппированные» — выбирается вся группа.
            let panel = controller?.arrangePanel
            if !insideSelected, panel?.autoSelectEnabled != false, var hit = session.document.topmostLayer(atX: x, y: y) {
                if panel?.autoSelectMode == .group, let top = session.document.topLevelAncestor(of: hit) { hit = top }
                session.select(event.modifierFlags.contains(.shift) ? session.selection + [hit] : [hit])
            }
        case .hand:
            NSCursor.closedHand.push()
            handCursorPushed = true
        case .inactive:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let last = dragLast else { return }
        let dx = (p.x - last.x) * backingScale, dy = (p.y - last.y) * backingScale
        dragLast = p
        switch effectiveTool {
        case .hand:
            viewport.pan(dx: dx, dy: dy)
            viewportChanged()
        case .arrange:
            moveRemainder.x += dx / viewport.scale
            moveRemainder.y += dy / viewport.scale
            let ix = Int(moveRemainder.x.rounded(.towardZero)), iy = Int(moveRemainder.y.rounded(.towardZero))
            moveRemainder.x -= Double(ix)
            moveRemainder.y -= Double(iy)
            controller?.session.moveSelection(dx: ix, dy: iy)
        case .zoom, .inactive:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if handCursorPushed {
            NSCursor.pop()
            handCursorPushed = false
        }
        controller?.session.endCoalescing()
        dragLast = nil
    }

    override func scrollWheel(with event: NSEvent) {
        let p = pixelPoint(event)
        // ⌘ или ⌥ с колёсиком — масштаб вокруг курсора; без них — прокрутка.
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
            viewport.setScale(viewport.scale * exp(dy * 0.01), aroundViewX: p.x, viewY: p.y)
        } else {
            let k = (event.hasPreciseScrollingDeltas ? 1.0 : 10.0) * backingScale
            viewport.pan(dx: event.scrollingDeltaX * k, dy: event.scrollingDeltaY * k)
        }
        viewportChanged()
    }

    override func magnify(with event: NSEvent) {
        let p = pixelPoint(event)
        viewport.setScale(viewport.scale * (1 + event.magnification), aroundViewX: p.x, viewY: p.y)
        viewportChanged()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let d = documentPoint(event)
        let x = Int(floor(d.x)), y = Int(floor(d.y))
        cursorDocumentPoint = (x >= 0 && y >= 0 && x < viewport.documentWidth && y < viewport.documentHeight) ? (x, y) : nil
        onViewportChange?()
    }

    override func mouseExited(with event: NSEvent) {
        cursorDocumentPoint = nil
        onViewportChange?()
    }

    override func cursorUpdate(with event: NSEvent) {
        switch effectiveTool {
        case .hand: NSCursor.openHand.set()
        case .zoom: NSCursor.crosshair.set()
        case .arrange, .inactive: NSCursor.arrow.set()
        }
    }

    // MARK: клавиши

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            if !spaceDown {
                spaceDown = true
                NSCursor.openHand.set()
            }
            return
        }
        // Стрелки с инструментом «Расположение» двигают слой на 1 пиксель (с Shift — на 10).
        if tool == .arrange, event.modifierFlags.intersection([.command, .option, .control]).isEmpty, let session = controller?.session {
            let step = event.modifierFlags.contains(.shift) ? 10 : 1
            var d: (Int, Int)?
            switch event.keyCode {
            case 123: d = (-step, 0)
            case 124: d = (step, 0)
            case 125: d = (0, step)
            case 126: d = (0, -step)
            default: break
            }
            if let d {
                session.moveSelection(dx: d.0, dy: d.1)
                session.endCoalescing()
                return
            }
        }
        // Однобуквенные клавиши инструментов и ⌫ — через меню.
        if NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            spaceDown = false
            window?.invalidateCursorRects(for: self)
            NSCursor.arrow.set()
            return
        }
        super.keyUp(with: event)
    }
}
#endif
