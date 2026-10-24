import Foundation

/// Описание главного меню без AppKit: дерево пунктов с клавишами и названиями на двух языках.
/// Окно macOS строит из него NSMenu; на Linux дерево проверяется тестами (уникальность, клавиши).

public struct KeyShortcut: Equatable, Sendable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let command = Modifiers(rawValue: 8)
    }

    public enum Key: Equatable, Sendable {
        /// Буква в нижнем регистре или знак, как его печатает клавиша без Shift.
        case character(Character)
        case up, down, left, right
        case delete
        case space
    }

    public var modifiers: Modifiers
    public var key: Key

    public init(modifiers: Modifiers, key: Key) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Разбор записи вида «⇧⌘N», «⌃⌘↑», «⌥⌫», «Z».
    public init?(_ text: String) {
        var mods: Modifiers = []
        var rest = Substring(text)
        while let c = rest.first, let m = KeyShortcut.modifierSymbols[c] {
            mods.insert(m)
            rest = rest.dropFirst()
        }
        let key: Key
        switch rest {
        case "↑": key = .up
        case "↓": key = .down
        case "←": key = .left
        case "→": key = .right
        case "⌫": key = .delete
        case "Space": key = .space
        default:
            guard rest.count == 1, let c = rest.first else { return nil }
            key = .character(Character(c.lowercased()))
        }
        modifiers = mods
        self.key = key
    }

    static let modifierSymbols: [Character: Modifiers] = ["⌃": .control, "⌥": .option, "⇧": .shift, "⌘": .command]

    public var description: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        switch key {
        case .character(let c): s += c.uppercased()
        case .up: s += "↑"
        case .down: s += "↓"
        case .left: s += "←"
        case .right: s += "→"
        case .delete: s += "⌫"
        case .space: s += "Space"
        }
        return s
    }
}

public indirect enum MenuNode: Sendable {
    case item(MenuItemSpec)
    case separator
}

public struct MenuItemSpec: Sendable {
    public var id: String
    public var shortcut: KeyShortcut?
    public var english: String
    public var russian: String
    /// Значок пункта как у образца: имя символа Apple (SF Symbols) или его картинки icon-menu-… / custom.…
    public var icon: String?
    public var children: [MenuNode]

    public var isSubmenu: Bool { !children.isEmpty }

    public func title(russian useRussian: Bool, appName: String) -> String {
        (useRussian ? russian : english).replacingOccurrences(of: "{app}", with: appName)
    }
}

public enum MenuSpecError: Error, Equatable {
    case badLine(Int, String)
    case badIndent(Int)
    case badShortcut(Int, String)
}

public enum MenuSpec {
    /// Верхние меню приложения (образца → File → … → Help).
    public static func main() -> [MenuItemSpec] {
        // Текст меню — часть исходника; ошибка в нём ловится тестом MenuSpecTests.
        try! parse(mainMenuText)
    }

    public static func parse(_ text: String) throws -> [MenuItemSpec] {
        // Стек открытых подменю: (уровень, пункт). Пункт вкладывается в родителя, когда встречается
        // строка того же или меньшего уровня либо кончается текст.
        var roots: [MenuItemSpec] = []
        var stack: [(level: Int, item: MenuItemSpec)] = []

        func closeLevels(downTo level: Int) {
            while let top = stack.last, top.level >= level {
                stack.removeLast()
                if stack.isEmpty {
                    roots.append(top.item)
                } else {
                    stack[stack.count - 1].item.children.append(.item(top.item))
                }
            }
        }

        for (n, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNo = n + 1
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let spaces = raw.prefix(while: { $0 == " " }).count
            guard spaces % 2 == 0 else { throw MenuSpecError.badIndent(lineNo) }
            let level = spaces / 2
            guard level <= stack.count else { throw MenuSpecError.badIndent(lineNo) }
            let body = raw.dropFirst(spaces)
            closeLevels(downTo: level)
            if body == "-" {
                guard level > 0, !stack.isEmpty else { throw MenuSpecError.badLine(lineNo, String(body)) }
                stack[stack.count - 1].item.children.append(.separator)
                continue
            }
            let parts = body.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 4 || parts.count == 5, !parts[0].isEmpty, !parts[2].isEmpty, !parts[3].isEmpty else {
                throw MenuSpecError.badLine(lineNo, String(body))
            }
            var shortcut: KeyShortcut?
            if !parts[1].isEmpty {
                guard let s = KeyShortcut(parts[1]) else { throw MenuSpecError.badShortcut(lineNo, parts[1]) }
                shortcut = s
            }
            let icon = parts.count == 5 && !parts[4].isEmpty ? parts[4] : nil
            stack.append((level, MenuItemSpec(id: parts[0], shortcut: shortcut, english: parts[2], russian: parts[3], icon: icon, children: [])))
        }
        closeLevels(downTo: 0)
        return roots
    }

    /// Все пункты дерева (без разделителей), сверху вниз.
    public static func flatten(_ items: [MenuItemSpec]) -> [MenuItemSpec] {
        var out: [MenuItemSpec] = []
        func walk(_ item: MenuItemSpec) {
            out.append(item)
            for case .item(let child) in item.children { walk(child) }
        }
        items.forEach(walk)
        return out
    }
}
