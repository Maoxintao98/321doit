import AppKit
import SwiftUI

// MARK: - Workstation accent
//
// Tool identity now comes from navigation and iconography, not a rainbow of
// module colors. Every tool shares the same restrained slate accent so moving
// between modules feels like staying at one production desk.

enum ToolAccent: String, CaseIterable, Identifiable {
    case scriptWorkshop
    case storyboard
    case offload
    case scriptLog
    case shootingDay
    case mediaConverter
    case handoff
    case reports

    var id: String { rawValue }

    /// Primary accent color, adaptive to light/dark appearance.
    var primary: Color {
        Self.adaptive(light: (0.25, 0.36, 0.42), dark: (0.51, 0.64, 0.70))
    }

    /// Deeper companion of `primary`, used as the gradient end stop.
    var deep: Color {
        Self.adaptive(light: (0.16, 0.26, 0.31), dark: (0.38, 0.51, 0.57))
    }

    /// Signature two-stop gradient (primary → deep). Use for icon tiles,
    /// primary buttons and progress fills — never for large backgrounds.
    var gradient: LinearGradient {
        LinearGradient(
            colors: [primary, deep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Soft glow used for hover edge-light and focus halos.
    var glow: Color { primary.opacity(0.45) }

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1.0)
        })
    }
}

extension ToolIdentifier {
    var accent: ToolAccent {
        switch self {
        case .scriptWorkshop: return .scriptWorkshop
        case .storyboard: return .storyboard
        case .offload: return .offload
        case .scriptLog: return .scriptLog
        case .shootingDay: return .shootingDay
        case .mediaConverter: return .mediaConverter
        }
    }
}

extension ThemeColors {
    /// Kept as an API for existing module views; all modules now share one
    /// workstation accent.
    func toolAccent(_ tool: ToolIdentifier) -> Color {
        _ = tool
        return accent
    }
}

private struct ToolAccentColorEnvironmentKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var toolAccentColor: Color? {
        get { self[ToolAccentColorEnvironmentKey.self] }
        set { self[ToolAccentColorEnvironmentKey.self] = newValue }
    }
}

// MARK: - Reusable accent-aware components

/// A squircle icon tile filled with the tool's signature gradient.
struct ToolAccentIconTile: View {
    let systemImage: String
    let accent: ToolAccent
    var size: CGFloat = 64
    var iconSize: CGFloat? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(accent.gradient)
                .overlay(
                    // Top inner highlight — the "实体按键" light edge.
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: max(0.5, size * 0.012))
                        .blendMode(.screen)
                )
                .shadow(color: accent.primary.opacity(0.32), radius: size * 0.10, x: 0, y: size * 0.05)
            Image(systemName: systemImage)
                .font(.system(size: iconSize ?? size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
