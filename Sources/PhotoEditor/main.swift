#if canImport(AppKit)
import AppKit

// Запуск: делегат строит меню и создаёт контроллер документов (типы файлов — в Info.plist пакета .app, см. tools/run_app.sh).
// Лист сверки значков с оригиналом: PhotoEditor --icon-sheet <папка с картинками образца> <out.png>
let arguments = CommandLine.arguments
if arguments.count == 4, arguments[1] == "--icon-sheet" {
    exit(ToolIcons.writeSheet(referenceDir: arguments[2], to: arguments[3]) ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
#else
print("PhotoEditor — приложение macOS; на этой системе собирается только для проверки сборки.")
#endif
