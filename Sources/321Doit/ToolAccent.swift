import AppKit
import SwiftUI

// MARK: - Tool accent colors ("缤纷" design language)
//
// Each tool owns one high-saturation cinematic accent color. Colors only appear
// where attention is wanted (icon tiles, active states, primary actions,
// progress), while the surrounding canvas stays neutral.
//
// Every accent ships in two variants (light / dark appearance) plus a deeper
// companion used to build the signature two-stop gradient.

enum ToolAccent: String, CaseIterable, Identifiable {
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
        switch self {
        case .storyboard:      return Self.adaptive(light: (0.91, 0.20, 0.32), dark: (1.00, 0.36, 0.45)) // 分镜绯红
        case .offload:        return Self.adaptive(light: (0.04, 0.52, 1.00), dark: (0.24, 0.61, 1.00)) // 电光青蓝
        case .scriptLog:      return Self.adaptive(light: (1.00, 0.42, 0.10), dark: (1.00, 0.54, 0.24)) // 打板橙
        case .shootingDay:    return Self.adaptive(light: (0.12, 0.66, 0.48), dark: (0.24, 0.81, 0.60)) // 场务绿
        case .mediaConverter: return Self.adaptive(light: (0.48, 0.36, 1.00), dark: (0.60, 0.51, 1.00)) // 转码紫
        case .handoff:        return Self.adaptive(light: (0.90, 0.28, 0.56), dark: (0.94, 0.42, 0.66)) // 品红
        case .reports:        return Self.adaptive(light: (0.85, 0.65, 0.08), dark: (1.00, 0.79, 0.24)) // 校验金
        }
    }

    /// Deeper companion of `primary`, used as the gradient end stop.
    var deep: Color {
        switch self {
        case .storyboard:      return Self.adaptive(light: (0.72, 0.10, 0.22), dark: (0.88, 0.22, 0.34))
        case .offload:        return Self.adaptive(light: (0.02, 0.38, 0.85), dark: (0.16, 0.48, 0.92))
        case .scriptLog:      return Self.adaptive(light: (0.85, 0.30, 0.04), dark: (0.92, 0.42, 0.14))
        case .shootingDay:    return Self.adaptive(light: (0.06, 0.50, 0.36), dark: (0.14, 0.66, 0.46))
        case .mediaConverter: return Self.adaptive(light: (0.35, 0.24, 0.85), dark: (0.46, 0.38, 0.92))
        case .handoff:        return Self.adaptive(light: (0.72, 0.16, 0.42), dark: (0.82, 0.28, 0.52))
        case .reports:        return Self.adaptive(light: (0.66, 0.48, 0.02), dark: (0.85, 0.62, 0.12))
        }
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
        case .storyboard: return .storyboard
        case .offload: return .offload
        case .scriptLog: return .scriptLog
        case .shootingDay: return .shootingDay
        case .mediaConverter: return .mediaConverter
        }
    }
}

extension ThemeColors {
    /// The owning tool's identity color. Inside a tool's UI, interactive
    /// accents (primary buttons, progress, selection) use this instead of the
    /// theme accent so every tool keeps its own color ("缤纷").
    func toolAccent(_ tool: ToolIdentifier) -> Color { tool.accent.primary }
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
