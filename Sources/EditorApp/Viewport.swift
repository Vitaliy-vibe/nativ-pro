import EditorCore
import Foundation

/// Части окна, закрытые парящими панелями (в пикселях дисплея): «По размеру окна» вписывает документ
/// в оставшуюся область, как образец — между панелью слоёв и панелью инструмента.
public struct ViewInsets: Equatable, Sendable {
    public var left: Double
    public var right: Double
    public var top: Double
    public var bottom: Double

    public init(left: Double = 0, right: Double = 0, top: Double = 0, bottom: Double = 0) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }
}

/// Положение документа в окне: масштаб и центр. Все размеры окна — в точках экрана устройства (пикселях дисплея),
/// поэтому масштаб 1 = «Реальный размер»: один пиксель документа на один пиксель дисплея.
public struct Viewport: Equatable, Sendable {
    public var documentWidth: Int
    public var documentHeight: Int
    /// Размер области холста в пикселях дисплея.
    public var viewWidth: Double
    public var viewHeight: Double
    /// Пикселей дисплея на пиксель документа.
    public private(set) var scale: Double = 1
    /// Точка документа в центре области холста.
    public var centerX: Double
    public var centerY: Double
    public var insets = ViewInsets()
    /// Включён режим «По размеру окна»: при изменении размера окна документ снова вписывается.
    /// Выключается любым ручным масштабом или сдвигом.
    public private(set) var fitsWindow = true
    /// Вписывание ограничено 100 % (режим открытия документа).
    public private(set) var fitCapped = false

    public static let minScale = 0.01
    public static let maxScale = 64.0
    /// Ступени «Увеличить / Уменьшить».
    public static let steps: [Double] = [0.01, 0.02, 0.03, 0.05, 1.0 / 12, 0.125, 1.0 / 6, 0.25, 1.0 / 3, 0.5, 2.0 / 3,
                                         1, 1.5, 2, 3, 4, 6, 8, 12, 16, 24, 32, 64]
    /// Поля вокруг документа при «По размеру окна».
    /// Доля свободной области, которую занимает документ при «По размеру окна» (у образца — вся).
    public static let fitMargin = 1.0

    public init(documentWidth: Int, documentHeight: Int, viewWidth: Double, viewHeight: Double) {
        self.documentWidth = documentWidth
        self.documentHeight = documentHeight
        self.viewWidth = viewWidth
        self.viewHeight = viewHeight
        centerX = Double(documentWidth) / 2
        centerY = Double(documentHeight) / 2
        zoomToFit(upToActualSize: true)
    }

    // MARK: перевод координат

    public func documentPoint(viewX: Double, viewY: Double) -> (x: Double, y: Double) {
        (centerX + (viewX - viewWidth / 2) / scale, centerY + (viewY - viewHeight / 2) / scale)
    }

    public func viewPoint(documentX: Double, documentY: Double) -> (x: Double, y: Double) {
        ((documentX - centerX) * scale + viewWidth / 2, (documentY - centerY) * scale + viewHeight / 2)
    }

    /// Прямоугольник документа в окне (x, y, ширина, высота) — в пикселях дисплея, начало вверху слева.
    public var documentRectInView: (x: Double, y: Double, width: Double, height: Double) {
        let o = viewPoint(documentX: 0, documentY: 0)
        return (o.x, o.y, Double(documentWidth) * scale, Double(documentHeight) * scale)
    }

    // MARK: масштаб

    public mutating func setScale(_ s: Double, aroundViewX vx: Double? = nil, viewY vy: Double? = nil) {
        let anchorX = vx ?? viewWidth / 2, anchorY = vy ?? viewHeight / 2
        let before = documentPoint(viewX: anchorX, viewY: anchorY)
        fitsWindow = false
        scale = min(max(s, Viewport.minScale), Viewport.maxScale)
        // Точка документа под курсором остаётся под курсором.
        centerX = before.x - (anchorX - viewWidth / 2) / scale
        centerY = before.y - (anchorY - viewHeight / 2) / scale
        clampCenter()
    }

    public mutating func zoomIn(aroundViewX vx: Double? = nil, viewY vy: Double? = nil) {
        setScale(Viewport.steps.first { $0 > scale * 1.001 } ?? Viewport.maxScale, aroundViewX: vx, viewY: vy)
    }

    public mutating func zoomOut(aroundViewX vx: Double? = nil, viewY vy: Double? = nil) {
        setScale(Viewport.steps.last { $0 < scale / 1.001 } ?? Viewport.minScale, aroundViewX: vx, viewY: vy)
    }

    public var fitScale: Double {
        let w = viewWidth - insets.left - insets.right, h = viewHeight - insets.top - insets.bottom
        guard documentWidth > 0, documentHeight > 0, w > 0, h > 0 else { return 1 }
        return min(w / Double(documentWidth), h / Double(documentHeight)) * Viewport.fitMargin
    }

    /// «По размеру окна». При открытии (`upToActualSize`) маленькое изображение не увеличивается больше 100 %,
    /// как в образце; команда «Изменить масштаб под размер» вписывает в любом случае.
    public mutating func zoomToFit(upToActualSize: Bool = false) {
        fitsWindow = true
        fitCapped = upToActualSize
        scale = min(max(upToActualSize ? min(fitScale, 1) : fitScale, Viewport.minScale), Viewport.maxScale)
        // Центр документа — в центре свободной области, а не всего окна.
        centerX = Double(documentWidth) / 2 - (insets.left - insets.right) / 2 / scale
        centerY = Double(documentHeight) / 2 - (insets.top - insets.bottom) / 2 / scale
    }

    public mutating func actualSize() { setScale(1) }

    /// Сдвиг на (dx, dy) пикселей дисплея — как жест двумя пальцами или инструмент «Рука».
    public mutating func pan(dx: Double, dy: Double) {
        fitsWindow = false
        centerX -= dx / scale
        centerY -= dy / scale
        clampCenter()
    }

    /// Панели открыли или закрыли часть окна.
    public mutating func setInsets(_ new: ViewInsets) {
        guard new != insets else { return }
        insets = new
        if fitsWindow { zoomToFit(upToActualSize: fitCapped) }
    }

    /// Изменился размер окна: центр документа остаётся на месте.
    public mutating func resize(viewWidth w: Double, viewHeight h: Double) {
        viewWidth = w
        viewHeight = h
        if fitsWindow {
            zoomToFit(upToActualSize: fitCapped)
        } else {
            clampCenter()
        }
    }

    /// Документ нельзя увести за край окна целиком: центр остаётся в пределах документа.
    mutating func clampCenter() {
        centerX = min(max(centerX, 0), Double(documentWidth))
        centerY = min(max(centerY, 0), Double(documentHeight))
    }

    // MARK: что рисовать

    /// Уровень уменьшенной копии: наибольший L, при котором 1/2^L ещё не мельче масштаба на экране
    /// (картинка уровня потом уменьшается при выводе не больше чем вдвое — без потери резкости).
    public var renderLevel: Int {
        guard scale < 1 else { return 0 }
        return min(max(Int(floor(log2(1 / scale))), 0), 8)
    }

    /// Видимая часть документа: область рендера на уровне `renderLevel` и её прямоугольник в документе.
    public var visibleRegion: (region: RenderRegion, documentRect: PixelRect)? {
        let a = documentPoint(viewX: 0, viewY: 0), b = documentPoint(viewX: viewWidth, viewY: viewHeight)
        let doc = PixelRect(x: 0, y: 0, width: documentWidth, height: documentHeight)
        let x0 = Int(floor(a.x)), y0 = Int(floor(a.y)), x1 = Int(ceil(b.x)), y1 = Int(ceil(b.y))
        let visible = PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).intersection(doc)
        guard !visible.isEmpty else { return nil }
        let level = renderLevel, f = 1 << level
        // Границы — по сетке уровня, чтобы пиксели уменьшенной копии совпадали с пикселями документа.
        let lx0 = visible.x / f, ly0 = visible.y / f
        let lx1 = (visible.maxX + f - 1) / f, ly1 = (visible.maxY + f - 1) / f
        let region = RenderRegion(x: lx0, y: ly0, width: lx1 - lx0, height: ly1 - ly0, level: level)
        let rect = PixelRect(x: lx0 * f, y: ly0 * f, width: (lx1 - lx0) * f, height: (ly1 - ly0) * f)
        return (region, rect)
    }

    /// Масштаб в процентах для строки сведений.
    public var percent: Double { scale * 100 }
}
