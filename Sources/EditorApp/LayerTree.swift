import EditorCore

/// Адрес слоя в дереве: индексы от корня (в каждом списке индекс 0 — нижний слой).
public typealias LayerPath = [Int]

/// Прямоугольник в пикселях документа.
public struct PixelRect: Equatable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Int { x + width }
    public var maxY: Int { y + height }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public func union(_ o: PixelRect) -> PixelRect {
        if isEmpty { return o }
        if o.isEmpty { return self }
        let x0 = min(x, o.x), y0 = min(y, o.y)
        return PixelRect(x: x0, y: y0, width: max(maxX, o.maxX) - x0, height: max(maxY, o.maxY) - y0)
    }

    public func intersection(_ o: PixelRect) -> PixelRect {
        let x0 = max(x, o.x), y0 = max(y, o.y)
        let x1 = min(maxX, o.maxX), y1 = min(maxY, o.maxY)
        guard x0 < x1, y0 < y1 else { return PixelRect(x: x0, y: y0, width: 0, height: 0) }
        return PixelRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}

extension Layer {
    /// Границы содержимого в координатах документа: растр — его прямоугольник, группа — объединение детей.
    /// У неподдержанных слоёв границ пока нет (nil).
    public var bounds: PixelRect? {
        switch content {
        case .bitmap(let b):
            return PixelRect(x: position.x, y: position.y, width: b.width, height: b.height)
        case .group(let children):
            let rects = children.compactMap(\.bounds)
            guard let first = rects.first else { return nil }
            return rects.dropFirst().reduce(first) { $0.union($1) }
        case .unsupported:
            return nil
        }
    }

    public var isGroup: Bool {
        if case .group = content { return true }
        return false
    }

    public var children: [Layer] {
        if case .group(let c) = content { return c }
        return []
    }

    /// Копия с новыми идентификаторами (у вложенных слоёв и масок тоже) — для «Дублировать» и вставки.
    public func withFreshIDs() -> Layer {
        var copy = self
        copy.id = LayerID()
        copy.masks = masks.map { m in
            var m = m
            m.id = LayerID()
            return m
        }
        if case .group(let children) = content { copy.content = .group(children.map { $0.withFreshIDs() }) }
        return copy
    }
}

extension Document {
    public var bounds: PixelRect { PixelRect(x: 0, y: 0, width: width, height: height) }

    public func path(of id: LayerID) -> LayerPath? {
        func find(_ list: [Layer], _ prefix: LayerPath) -> LayerPath? {
            for (i, l) in list.enumerated() {
                if l.id == id { return prefix + [i] }
                if case .group(let c) = l.content, let p = find(c, prefix + [i]) { return p }
            }
            return nil
        }
        return find(layers, [])
    }

    public func layer(at path: LayerPath) -> Layer {
        var list = layers
        for i in path.dropLast() { list = list[i].children }
        return list[path.last!]
    }

    /// Список, в котором лежит слой по адресу `path` (родитель — группа или корень).
    public func siblings(of path: LayerPath) -> [Layer] {
        var list = layers
        for i in path.dropLast() { list = list[i].children }
        return list
    }

    /// Изменить список детей по адресу родителя (пустой адрес — корень).
    public mutating func editList(_ parent: LayerPath, _ change: (inout [Layer]) -> Void) {
        func go(_ list: inout [Layer], _ rest: ArraySlice<Int>) {
            guard let i = rest.first else {
                change(&list)
                return
            }
            var children = list[i].children
            go(&children, rest.dropFirst())
            list[i].content = .group(children)
        }
        go(&layers, parent[...])
    }

    @discardableResult
    public mutating func removeLayer(at path: LayerPath) -> Layer {
        var removed: Layer!
        editList(Array(path.dropLast())) { removed = $0.remove(at: path.last!) }
        return removed
    }

    /// Вставить слой так, чтобы он оказался по адресу `path`.
    public mutating func insertLayer(_ layer: Layer, at path: LayerPath) {
        editList(Array(path.dropLast())) { $0.insert(layer, at: path.last!) }
    }

    /// Все слои дерева сверху вниз, как в панели слоёв: (слой, глубина вложенности).
    public func flattenedTopDown() -> [(layer: Layer, depth: Int)] {
        var out: [(Layer, Int)] = []
        func walk(_ list: [Layer], _ depth: Int) {
            for l in list.reversed() {
                out.append((l, depth))
                walk(l.children, depth + 1)
            }
        }
        walk(layers, 0)
        return out
    }
}

extension Document {
    /// Верхний видимый растровый слой с непрозрачным пикселем в точке — щелчок инструментом «Расположение».
    public func topmostLayer(atX x: Int, y: Int) -> LayerID? {
        func find(_ list: [Layer]) -> LayerID? {
            for l in list.reversed() where l.isVisible {
                switch l.content {
                case .bitmap(let b):
                    let lx = x - l.position.x, ly = y - l.position.y
                    if lx >= 0, ly >= 0, lx < b.width, ly < b.height, b.value(x: lx, y: ly, channel: 3) > 0 { return l.id }
                case .group(let children):
                    if let id = find(children) { return id }
                case .unsupported:
                    break
                }
            }
            return nil
        }
        return find(layers)
    }
}

extension Document {
    /// Слой верхнего уровня, в который входит слой (для автовыбора «Группы»).
    public func topLevelAncestor(of id: LayerID) -> LayerID? {
        guard let p = path(of: id) else { return nil }
        return layers[p[0]].id
    }
}
