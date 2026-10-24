import EditorCore

/// Повороты на 90° и отражения — точные перестановки пикселей, без пересчёта цвета.
public enum RightAngle: Sendable, CaseIterable {
    case rotate180, rotateRight, rotateLeft, flipHorizontal, flipVertical

    var swapsAxes: Bool { self == .rotateRight || self == .rotateLeft }

    /// Куда попадает прямоугольник `r`, лежащий в рамке `w×h` с началом 0,0.
    func map(_ r: PixelRect, inWidth w: Int, height h: Int) -> PixelRect {
        switch self {
        case .flipHorizontal: return PixelRect(x: w - r.maxX, y: r.y, width: r.width, height: r.height)
        case .flipVertical: return PixelRect(x: r.x, y: h - r.maxY, width: r.width, height: r.height)
        case .rotate180: return PixelRect(x: w - r.maxX, y: h - r.maxY, width: r.width, height: r.height)
        // По часовой: точка (x, y) → (h − 1 − y, x).
        case .rotateRight: return PixelRect(x: h - r.maxY, y: r.x, width: r.height, height: r.width)
        // Против часовой: (x, y) → (y, w − 1 − x).
        case .rotateLeft: return PixelRect(x: r.y, y: w - r.maxX, width: r.height, height: r.width)
        }
    }

    /// Из какого пикселя исходника (размер w×h) берётся пиксель (X, Y) результата.
    @inline(__always)
    func source(_ X: Int, _ Y: Int, w: Int, h: Int) -> (Int, Int) {
        switch self {
        case .flipHorizontal: return (w - 1 - X, Y)
        case .flipVertical: return (X, h - 1 - Y)
        case .rotate180: return (w - 1 - X, h - 1 - Y)
        case .rotateRight: return (Y, h - 1 - X)
        case .rotateLeft: return (w - 1 - Y, X)
        }
    }
}

extension Bitmap {
    /// Растр после поворота или отражения; глубина и каналы сохраняются, пустые плитки остаются пустыми.
    public func transformed(_ op: RightAngle) -> Bitmap {
        let w = width, h = height
        let outW = op.swapsAxes ? h : w, outH = op.swapsAxes ? w : h
        var out = Bitmap(width: outW, height: outH, channels: channels, depth: depth)
        let size = Tile.size
        for ty in 0..<out.tilesDown {
            for tx in 0..<out.tilesAcross {
                let x0 = tx * size, y0 = ty * size
                let tw = min(size, outW - x0), th = min(size, outH - y0)
                switch depth {
                case .u8:
                    var buf = [UInt8](repeating: 0, count: tw * th * channels)
                    var any = false
                    for y in 0..<th {
                        for x in 0..<tw {
                            let (sx, sy) = op.source(x0 + x, y0 + y, w: w, h: h)
                            guard let t = tiles[(sy / size) * tilesAcross + sx / size], case .u8(let src) = t.storage else { continue }
                            let si = ((sy % size) * t.width + sx % size) * channels, di = (y * tw + x) * channels
                            for c in 0..<channels where src[si + c] != 0 {
                                buf[di + c] = src[si + c]
                                any = true
                            }
                        }
                    }
                    if any { out.replaceTile(tx: tx, ty: ty, with: Tile(width: tw, height: th, channels: channels, storage: .u8(buf))) }
                case .u16:
                    var buf = [UInt16](repeating: 0, count: tw * th * channels)
                    var any = false
                    for y in 0..<th {
                        for x in 0..<tw {
                            let (sx, sy) = op.source(x0 + x, y0 + y, w: w, h: h)
                            guard let t = tiles[(sy / size) * tilesAcross + sx / size], case .u16(let src) = t.storage else { continue }
                            let si = ((sy % size) * t.width + sx % size) * channels, di = (y * tw + x) * channels
                            for c in 0..<channels where src[si + c] != 0 {
                                buf[di + c] = src[si + c]
                                any = true
                            }
                        }
                    }
                    if any { out.replaceTile(tx: tx, ty: ty, with: Tile(width: tw, height: th, channels: channels, storage: .u16(buf))) }
                }
            }
        }
        return out
    }
}

extension Layer {
    /// Повернуть или отразить слой внутри рамки `box` (координаты документа); `newOrigin` — левый верхний угол
    /// рамки после преобразования (при повороте на 90° у рамки меняются стороны).
    func transformed(_ op: RightAngle, box: PixelRect, newOrigin: PixelPoint) -> Layer {
        var l = self
        func place(_ r: PixelRect) -> PixelPoint {
            let rel = PixelRect(x: r.x - box.x, y: r.y - box.y, width: r.width, height: r.height)
            let m = op.map(rel, inWidth: box.width, height: box.height)
            return PixelPoint(x: newOrigin.x + m.x, y: newOrigin.y + m.y)
        }
        switch content {
        case .bitmap(let b):
            l.position = place(PixelRect(x: position.x, y: position.y, width: b.width, height: b.height))
            l.content = .bitmap(b.transformed(op))
        case .group(let children):
            l.content = .group(children.map { $0.transformed(op, box: box, newOrigin: newOrigin) })
        case .unsupported:
            break
        }
        l.masks = masks.map { m in
            var m = m
            if let b = m.bitmap {
                m.offset = place(PixelRect(x: m.offset.x, y: m.offset.y, width: b.width, height: b.height))
                m.bitmap = b.transformed(op)
            }
            return m
        }
        return l
    }
}

extension Document {
    /// «Изображение → Повернуть»: весь документ; при повороте на 90° меняются ширина и высота.
    public mutating func transformImage(_ op: RightAngle) {
        let box = bounds
        layers = layers.map { $0.transformed(op, box: box, newOrigin: .zero) }
        if op.swapsAxes { swap(&width, &height) }
    }
}
