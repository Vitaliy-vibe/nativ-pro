/// История отмен.
/// Документ — значение с общими плитками, поэтому шаг истории — просто прежнее состояние документа:
/// неизменённые плитки не копируются.
public struct History: Sendable {
    public struct Step: Sendable {
        /// Название для меню: «Отменить <name>».
        public let name: String
        public let before: Document
        let coalescingKey: String?
    }

    public private(set) var current: Document
    public private(set) var undoStack: [Step] = []
    public private(set) var redoStack: [Step] = []
    /// Сколько шагов отмены хранить (старые отбрасываются).
    public var limit: Int

    public init(_ document: Document, limit: Int = 200) {
        self.current = document
        self.limit = limit
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var undoName: String? { undoStack.last?.name }
    public var redoName: String? { redoStack.last?.name }

    /// Выполнить изменение как один шаг. Если `coalescing` совпадает с ключом предыдущего шага,
    /// изменения сливаются в него (например, перетаскивание ползунка непрозрачности).
    /// Изменение, бросившее ошибку, не попадает в историю и не меняет документ.
    public mutating func perform(_ name: String, coalescing key: String? = nil, _ change: (inout Document) throws -> Void) rethrows {
        var next = current
        try change(&next)
        if let key, let last = undoStack.last, last.coalescingKey == key, redoStack.isEmpty {
            current = next
            return
        }
        undoStack.append(Step(name: name, before: current, coalescingKey: key))
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        redoStack.removeAll()
        current = next
    }

    /// Закрыть объединение: следующий шаг с тем же ключом станет отдельным (например, отпустили ползунок).
    public mutating func endCoalescing() {
        guard let last = undoStack.popLast() else { return }
        undoStack.append(Step(name: last.name, before: last.before, coalescingKey: nil))
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let step = undoStack.popLast() else { return false }
        redoStack.append(Step(name: step.name, before: current, coalescingKey: nil))
        current = step.before
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let step = redoStack.popLast() else { return false }
        undoStack.append(Step(name: step.name, before: current, coalescingKey: nil))
        current = step.before
        return true
    }
}
