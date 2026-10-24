#if canImport(AppKit)
import AppKit
import EditorApp
import EditorCore

/// Действие всех пунктов меню, которые выполняет сам редактор; идентификатор команды — в representedObject.
@objc protocol EditorCommandTarget {
    func performEditorCommand(_ sender: Any?)
}

enum AppInfo {
    /// Название программы (логотип и имя от владельца, 20.10). Внутреннее имя исполняемого файла и идентификатор
    /// (PhotoEditor, ru.ect.photoeditor) прежние — на них завязаны скрипты сверки и настройки.
    static let name = "Nativ Pro"
    /// Язык интерфейса: русский, если он первый в системных настройках языка.
    static let russian = Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
    static func tr(_ english: String, _ russianText: String) -> String { russian ? russianText : english }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Первый созданный контроллер документов становится общим (NSDocumentController.shared).
        _ = EditorDocumentController()
        NSApp.mainMenu = MenuBuilder().build()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { EditorDocumentController.launching = false }
    }

    // Команды уровня приложения — доходят сюда, если ни одно окно их не взяло.
    @objc func performEditorCommand(_ sender: Any?) {
        guard let id = (sender as? NSMenuItem)?.representedObject as? String else { return }
        if id == "file.newFromClipboard" { EditorDocumentController.newFromClipboard() }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let id = menuItem.representedObject as? String else { return true }
        if id == "file.newFromClipboard" { return PasteboardImage.hasImage() }
        return false
    }
}

/// Строит NSMenu по описанию MenuSpec. Стандартные пункты получают системные действия (окна, документы,
/// приложение), остальные — performEditorCommand; что из них доступно, решает validateMenuItem в окне.
struct MenuBuilder {
    /// Пункты со стандартным действием AppKit.
    static let standardActions: [String: String] = [
        "app.about": "orderFrontStandardAboutPanel:",
        "app.hide": "hide:",
        "app.hideOthers": "hideOtherApplications:",
        "app.showAll": "unhideAllApplications:",
        "app.quit": "terminate:",
        "file.new": "newDocument:",
        "file.open": "openDocument:",
        "file.clearRecent": "clearRecentDocuments:",
        "file.close": "performClose:",
        "file.save": "saveDocument:",
        "file.saveAs": "saveDocumentAs:",
        "file.revert": "revertDocumentToSaved:",
        "edit.undo": "undo:",
        "edit.redo": "redo:",
        "edit.cut": "cut:",
        "edit.copy": "copy:",
        "edit.paste": "paste:",
        "edit.delete": "delete:",
        "window.minimize": "performMiniaturize:",
        "window.zoom": "performZoom:",
        "window.bringAllToFront": "arrangeInFront:",
        "window.showTabBar": "toggleTabBar:",
        "window.tabOverview": "toggleTabOverview:",
        "view.fullScreen": "toggleFullScreen:",
    ]

    /// Обратная таблица: действие → идентификатор команды (для проверки доступности в окне).
    static let commandForAction: [String: String] = Dictionary(uniqueKeysWithValues: standardActions.map { ($1, $0) })

    func build() -> NSMenu {
        let main = NSMenu(title: "Main")
        for top in MenuSpec.main() {
            let item = NSMenuItem(title: title(top), action: nil, keyEquivalent: "")
            item.submenu = submenu(top)
            main.addItem(item)
        }
        return main
    }

    func title(_ spec: MenuItemSpec) -> String { spec.title(russian: AppInfo.russian, appName: AppInfo.name) }

    func submenu(_ spec: MenuItemSpec) -> NSMenu {
        let menu = NSMenu(title: title(spec))
        // Доступность пунктов задаёт validateMenuItem у получателя команды.
        menu.autoenablesItems = true
        for node in spec.children {
            switch node {
            case .separator:
                menu.addItem(.separator())
            case .item(let child):
                menu.addItem(item(child))
            }
        }
        switch spec.id {
        case "app.services": NSApp.servicesMenu = menu
        case "window": NSApp.windowsMenu = menu
        case "help": NSApp.helpMenu = menu
        default: break
        }
        return menu
    }

    func item(_ spec: MenuItemSpec) -> NSMenuItem {
        let item = NSMenuItem(title: title(spec), action: nil, keyEquivalent: "")
        item.representedObject = spec.id
        // Значок как у образца: символ Apple по имени из его меню или наш рисунок инструмента.
        if let icon = spec.icon {
            item.image = ToolIcons.menuImage(icon) ?? NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        }
        if spec.isSubmenu || spec.id == "app.services" {
            item.submenu = submenu(spec)
            return item
        }
        if let action = MenuBuilder.standardActions[spec.id] {
            item.action = NSSelectorFromString(action)
        } else {
            item.action = #selector(EditorCommandTarget.performEditorCommand(_:))
        }
        if let s = spec.shortcut {
            item.keyEquivalent = MenuBuilder.keyEquivalent(s)
            item.keyEquivalentModifierMask = MenuBuilder.modifierMask(s.modifiers)
        }
        return item
    }

    static func keyEquivalent(_ s: KeyShortcut) -> String {
        func function(_ code: Int) -> String { String(utf16CodeUnits: [unichar(code)], count: 1) }
        switch s.key {
        case .character(let c): return String(c)
        case .up: return function(NSUpArrowFunctionKey)
        case .down: return function(NSDownArrowFunctionKey)
        case .left: return function(NSLeftArrowFunctionKey)
        case .right: return function(NSRightArrowFunctionKey)
        case .delete: return function(NSBackspaceCharacter)
        case .space: return " "
        }
    }

    static func modifierMask(_ m: KeyShortcut.Modifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if m.contains(.control) { flags.insert(.control) }
        if m.contains(.option) { flags.insert(.option) }
        if m.contains(.shift) { flags.insert(.shift) }
        if m.contains(.command) { flags.insert(.command) }
        return flags
    }
}
#endif
