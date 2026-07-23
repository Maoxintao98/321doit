import AppKit

func isSystemDarkAppearance() -> Bool {
    guard let appearance = NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua) else {
        return false
    }
    return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
}
