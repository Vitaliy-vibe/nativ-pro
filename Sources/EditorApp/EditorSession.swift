import EditorCore
import Foundation

/// Состояние открытого документа без AppKit: история, выбранные слои, выполнение команд меню.
/// Окно macOS только показывает это состояние и передаёт сюда команды — поэтому логика проверяется тестами на Linux.
public final class EditorSession {
    public private(set) var history: History
    /// Выбранные слои; последний — основной (с ним работают команды над одним слоем).
    public private(set) var selection: [LayerID] = []
    public let russian: Bool
    /// Что изменилось — окну, чтобы отметить документ изменённым и перерисовать нужное.
    public enum Change { case edit, undo, redo, selection, reset }
    /// Вызывается после любого изменения документа или выбора.
    public var onChange: ((Change) -> Void)?

    public var document: Document { history.current }

    public init(document: Document, russian: Bool) {
        history = History(document)
        self.russian = russian
        if let top = document.layers.last { selection = [top.id] }
    }

    /// Перевод подписей: английский текст — ключ, русский — значение.
    public func tr(_ english: String, _ russianText: String) -> String { russian ? russianText : english }

    public var primary: LayerID? { selection.last }
    public var primaryLayer: Layer? { primary.flatMap { document.layer($0) } }

    // MARK: выбор

    public func select(_ ids: [LayerID]) {
        let valid = ids.filter { document.layer($0) != nil }
        guard valid != selection else { return }
        selection = valid
        onChange?(.selection)
    }

    // MARK: изменения

    /// Изменение документа одним шагом истории. Новый выбор (если задан) применяется вместе с ним.
    public func perform(_ name: String, coalescing: String? = nil, select newSelection: [LayerID]? = nil, _ change: (inout Document) throws -> Void) rethrows {
        try history.perform(name, coalescing: coalescing, change)
        if let newSelection { selection = newSelection }
        dropMissingSelection()
        onChange?(.edit)
    }

    public func endCoalescing() { history.endCoalescing() }

    public func undo() {
        guard history.undo() else { return }
        dropMissingSelection()
        onChange?(.undo)
    }

    public func redo() {
        guard history.redo() else { return }
        dropMissingSelection()
        onChange?(.redo)
    }

    func dropMissingSelection() {
        selection = selection.filter { document.layer($0) != nil }
        if selection.isEmpty, let top = document.layers.last { selection = [top.id] }
    }

    /// Заменить документ целиком без истории (открытие, «Вернуть к сохранённому»).
    public func reset(to document: Document) {
        history = History(document)
        selection = document.layers.last.map { [$0.id] } ?? []
        onChange?(.reset)
    }

    // MARK: свойства слоя из панели

    public func setOpacity(_ id: LayerID, _ value: Float) {
        try? perform(tr("Opacity", "Непрозрачность"), coalescing: "opacity-\(id)") { try $0.updateLayer(id) { $0.opacity = min(max(value, 0), 1) } }
    }

    public func setBlendMode(_ id: LayerID, _ mode: BlendMode) {
        try? perform(tr("Blend Mode", "Режим наложения")) { try $0.updateLayer(id) { $0.blendMode = mode } }
    }

    public func setVisible(_ id: LayerID, _ visible: Bool) {
        try? perform(visible ? tr("Show", "Показать") : tr("Hide", "Скрыть")) { try $0.updateLayer(id) { $0.isVisible = visible } }
    }

    public func rename(_ id: LayerID, _ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, document.layer(id)?.name != trimmed else { return }
        try? perform(tr("Rename Layer", "Переименовать слой")) { try $0.updateLayer(id) { $0.name = trimmed } }
    }

    /// Сдвиг выбранных слоёв (инструмент «Расположение»). Непрерывное перетаскивание — один шаг истории;
    /// после отпускания мыши вызвать endCoalescing().
    public func moveSelection(dx: Int, dy: Int) {
        guard dx != 0 || dy != 0 else { return }
        let ids = topmostSelected().filter { document.layer($0)?.isLocked == false }
        guard !ids.isEmpty else { return }
        try? perform(tr("Move", "Перемещение"), coalescing: "move") { doc in
            for id in ids { try doc.updateLayer(id) { $0.offset(dx: dx, dy: dy) } }
        }
    }

    /// Поля «Позиция X / Y» панели инструмента: левый верхний угол границ слоя.
    public func setPosition(_ id: LayerID, x: Int? = nil, y: Int? = nil) {
        guard let layer = document.layer(id), !layer.isLocked, let b = layer.bounds else { return }
        let dx = (x ?? b.x) - b.x, dy = (y ?? b.y) - b.y
        guard dx != 0 || dy != 0 else { return }
        try? perform(tr("Move", "Перемещение")) { try $0.updateLayer(id) { $0.offset(dx: dx, dy: dy) } }
    }

    /// Перенести слой в другое место дерева (перетаскивание в панели слоёв).
    /// `parent` — группа-приёмник (nil — корень), `index` — место в её списке (0 — низ).
    public func moveLayer(_ id: LayerID, toParent parent: LayerID?, index: Int) {
        guard let from = document.path(of: id) else { return }
        var target: LayerPath = []
        if let parent {
            guard let p = document.path(of: parent), document.layer(at: p).isGroup else { return }
            // Нельзя положить группу внутрь самой себя.
            guard !p.starts(with: from) else { return }
            target = p
        }
        perform(tr("Move Layer", "Переместить слой")) { doc in
            var idx = index
            // Удаление из того же списка ниже места вставки сдвигает индекс.
            if Array(from.dropLast()) == target, from.last! < idx { idx -= 1 }
            let layer = doc.removeLayer(at: from)
            var dest = target
            // Адрес родителя мог сдвинуться, если удалённый слой стоял перед ним в общем предке.
            if let p = parent { dest = doc.path(of: p) ?? [] }
            let count = dest.isEmpty ? doc.layers.count : doc.layer(at: dest).children.count
            doc.insertLayer(layer, at: dest + [min(max(idx, 0), count)])
        }
    }

    /// Выбранные слои без тех, что уже входят в выбранную группу (сдвиг и удаление группы касаются детей).
    func topmostSelected() -> [LayerID] {
        selection.filter { id in
            guard let path = document.path(of: id) else { return false }
            return !selection.contains { other in
                other != id && document.path(of: other).map { path.count > $0.count && path.starts(with: $0) } == true
            }
        }
    }
}

extension Layer {
    mutating func offset(dx: Int, dy: Int) {
        position.x += dx
        position.y += dy
        for i in masks.indices where masks[i].bitmap != nil {
            masks[i].offset.x += dx
            masks[i].offset.y += dy
        }
        if case .group(var children) = content {
            for i in children.indices { children[i].offset(dx: dx, dy: dy) }
            content = .group(children)
        }
    }
}
