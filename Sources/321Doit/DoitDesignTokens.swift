import SwiftUI

// MARK: - 321Doit design tokens (Liquid Glass shell era)
//
// Single source of truth for the redesigned shell surfaces. These tokens
// converge the scattered ad-hoc values (font sizes 8–29, radii 8–20) into one
// semantic scale. Existing modules keep their current look until they are
// migrated surface-by-surface; new and redesigned code must use these tokens.

/// Semantic type scale. Hard floor: nothing below 11 pt renders in the shell,
/// so every level stays legible on set in bright sun or a dark DIT tent.
enum DoitFont {
    /// Hero names on launch / overview. Was ad-hoc 29.
    static let display = Font.system(size: 28, weight: .semibold)
    /// Page-level titles. Was ad-hoc 16–19.
    static let title1 = Font.system(size: 20, weight: .semibold)
    /// Section headers. Was ad-hoc 12–14.
    static let title2 = Font.system(size: 15, weight: .semibold)
    /// Primary content text. Was ad-hoc 11–12.
    static let body = Font.system(size: 13, weight: .regular)
    /// Emphasized body (list rows, primary buttons).
    static let bodyEmphasis = Font.system(size: 13, weight: .semibold)
    /// Secondary explanatory text. Was ad-hoc 10–11.
    static let callout = Font.system(size: 12, weight: .regular)
    /// Metadata, labels, eyebrows. The absolute floor — was ad-hoc 8–10.
    static let caption = Font.system(size: 11, weight: .medium)
    /// Paths, file numbers, speeds. Monospaced for column alignment.
    static let mono = Font.system(size: 12, weight: .medium, design: .monospaced)
    /// Small monospaced metadata (paths in dense rows). Still ≥ 11.
    static let monoCaption = Font.system(size: 11, weight: .regular, design: .monospaced)
}

/// 4 pt spacing grid. Use these instead of literal paddings.
enum DoitSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

/// Canonical corner radii for the glass shell. Supersedes the historical
/// mix of 8/13/14/15/16/18/20; `DoitVisual` remains for unmigrated modules.
enum DoitRadius {
    /// Inline controls, chips, small inputs.
    static let control: CGFloat = 8
    /// Cards and grouped content.
    static let card: CGFloat = 12
    /// Floating panels, sheets, sidebar.
    static let panel: CGFloat = 16
}

extension View {
    /// Applies a semantic shell font. Exists so call sites read
    /// `.doitFont(.title2)` instead of reaching for literals.
    func doitFont(_ font: Font) -> some View {
        self.font(font)
    }
}
