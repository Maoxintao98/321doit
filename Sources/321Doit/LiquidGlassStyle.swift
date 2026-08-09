import SwiftUI

/// Shared visual metrics for the app's highest-frequency surfaces. Keeping
/// these values here prevents each workspace from drifting into a different
/// radius, shadow, control height, or motion language.
enum DoitVisual {
    static let radiusSmall: CGFloat = 8
    static let radiusControl: CGFloat = 12
    static let radiusCard: CGFloat = 16
    static let radiusHero: CGFloat = 20

    static let controlHeight: CGFloat = 44
    static let largeControlHeight: CGFloat = 56
    static let hairlineWidth: CGFloat = 0.75

    static let pressDuration = 0.09
    static let hoverDuration = 0.16
    static let stateDuration = 0.22
    static let transitionDuration = 0.28

    static func hoverAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: hoverDuration)
    }

    static func stateAnimation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: stateDuration)
    }
}

enum DoitSurfaceElevation {
    case inset
    case panel
    case raised
}

/// A quiet field of brand-colored light for glass surfaces to refract.
/// Liquid Glass becomes visually flat when it sits on a single opaque color;
/// this backdrop provides depth without turning the workstation decorative.
struct DoitGlassBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    let colors: ThemeColors

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            colors.surfaceBg

            LinearGradient(
                colors: [
                    colors.accent.opacity(isDark ? 0.24 : 0.17),
                    colors.surfaceBg.opacity(0.06),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(isDark ? 0.075 : 0.52),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 12,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    colors.warm.opacity(isDark ? 0.15 : 0.12),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 600
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct DoitSurfaceModifier: ViewModifier {
    let colors: ThemeColors
    let cornerRadius: CGFloat
    let fill: Color?
    let elevation: DoitSurfaceElevation
    let accent: Color?
    let isHovered: Bool
    let isMuted: Bool

    private var resolvedFill: Color {
        if let fill { return fill }
        switch elevation {
        case .inset: return colors.inputBg.opacity(isMuted ? 0.34 : 0.58)
        case .panel, .raised: return colors.panelBg.opacity(isMuted ? 0.48 : 0.96)
        }
    }

    private var borderColor: Color {
        if isMuted { return colors.hairline.opacity(0.34) }
        if isHovered, let accent { return accent.opacity(0.42) }
        return colors.hairline.opacity(elevation == .inset ? 0.52 : 0.72)
    }

    private var shadowColor: Color {
        guard !isMuted else { return .clear }
        if isHovered, let accent { return accent.opacity(0.14) }
        switch elevation {
        case .inset: return .clear
        case .panel: return Color.black.opacity(0.035)
        case .raised: return Color.black.opacity(0.07)
        }
    }

    private var shadowRadius: CGFloat {
        if isHovered { return 16 }
        return elevation == .raised ? 14 : 7
    }

    private var shadowY: CGFloat {
        if isHovered { return 8 }
        return elevation == .raised ? 7 : 3
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(resolvedFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        borderColor,
                        lineWidth: isHovered && accent != nil ? 1 : DoitVisual.hairlineWidth
                    )
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }
}

struct DoitPressableButtonStyle: ButtonStyle {
    var reduceMotion = false
    var pressedScale: CGFloat = 0.985

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : pressedScale)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: DoitVisual.pressDuration),
                value: configuration.isPressed
            )
    }
}

extension View {
    func doitSurface(
        colors: ThemeColors,
        cornerRadius: CGFloat = DoitVisual.radiusCard,
        fill: Color? = nil,
        elevation: DoitSurfaceElevation = .panel,
        accent: Color? = nil,
        isHovered: Bool = false,
        isMuted: Bool = false
    ) -> some View {
        modifier(DoitSurfaceModifier(
            colors: colors,
            cornerRadius: cornerRadius,
            fill: fill,
            elevation: elevation,
            accent: accent,
            isHovered: isHovered,
            isMuted: isMuted
        ))
    }

    @ViewBuilder
    func liquidGlassSurface(colors: ThemeColors, cornerRadius: CGFloat = 16) -> some View {
        #if LEGACY_SDK
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(colors.hairline.opacity(0.78), lineWidth: 0.6)
            )
            .shadow(color: Color.black.opacity(0.055), radius: 12, x: 0, y: 8)
        #else
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.42), colors.hairline.opacity(0.64)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: Color.black.opacity(0.085), radius: 16, x: 0, y: 9)
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(colors.hairline.opacity(0.78), lineWidth: 0.6)
                )
                .shadow(color: Color.black.opacity(0.055), radius: 12, x: 0, y: 8)
        }
        #endif
    }

    /// Interactive capsule used by controls that physically move or respond
    /// to pointer input. Keep it untinted so the surrounding content supplies
    /// all reflected color, matching the native Liquid Glass behavior.
    @ViewBuilder
    func interactiveLiquidGlassCapsule(colors: ThemeColors) -> some View {
        #if LEGACY_SDK
        self
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(colors.hairline.opacity(0.78), lineWidth: 0.6)
            )
            .shadow(color: Color.black.opacity(0.055), radius: 12, x: 0, y: 8)
        #else
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular.interactive(), in: .capsule)
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.44), colors.hairline.opacity(0.62)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.75
                        )
                )
                .shadow(color: Color.black.opacity(0.075), radius: 12, x: 0, y: 7)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(colors.hairline.opacity(0.78), lineWidth: 0.6)
                )
                .shadow(color: Color.black.opacity(0.055), radius: 12, x: 0, y: 8)
        }
        #endif
    }
}
