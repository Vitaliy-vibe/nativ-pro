#if canImport(AppKit)
import AppKit

/// Контуры значков полосы, обведённые по картинкам-образцам. В открытой версии их нет — значки рисует ToolIcons.
enum TracedIcons {
    static let layers: [String: [(CGFloat, String)]] = [:]
}
#endif
