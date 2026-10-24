#if canImport(AppKit)
import AppKit

/// Картинки панелей инструментов, обведённые по образцам. В открытой версии их нет — вместо них значки SF Symbols
/// (TracedPanelIcons.image).
enum TracedPanelIcons {
    static let icons: [String: (CGSize, [(CGFloat, String)])] = [:]
}
#endif
