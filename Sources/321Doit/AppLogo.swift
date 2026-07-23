import SwiftUI

// MARK: - Brand colors

// ThemeColors are now defined in AppSettings.swift

// MARK: - Logo (squircle tile with three stacked bars in 3:2:1 ratio)

struct AppLogo: View {
    var size: CGFloat = 36
    var showsLabel: Bool = false
    @Environment(\.themeColors) var colors

    var body: some View {
        HStack(spacing: size * 0.28) {
            tile
            if showsLabel {
                VStack(alignment: .leading, spacing: 2) {
                    Text("321Doit")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .tracking(0.3)
                    Text("DIT COPY · VERIFY · TRANSCODE")
                        .font(.system(size: size * 0.22, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
    }

    private var tile: some View {
        ZStack {
            // Background squircle with subtle deep gradient
            RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [colors.inkTop, colors.inkBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: max(0.5, size * 0.012))
                )
                .shadow(color: Color.black.opacity(0.2), radius: size * 0.05, x: 0, y: size * 0.02)

            // Three stacked bars in 3:2:1 width ratio
            VStack(alignment: .leading, spacing: size * 0.085) {
                bar(widthRatio: 0.62, gradient: [colors.accent, colors.accentDeep])
                bar(widthRatio: 0.42, gradient: [colors.accent.opacity(0.9), colors.accentDeep.opacity(0.8)])
                bar(widthRatio: 0.22, gradient: [colors.warm, colors.warm.opacity(0.6)])
            }
            .frame(width: size * 0.66, alignment: .leading)
            .shadow(color: colors.accent.opacity(0.3), radius: size * 0.04, x: 0, y: size * 0.01)
        }
        .frame(width: size, height: size)
    }

    private func bar(widthRatio: CGFloat, gradient: [Color]) -> some View {
        RoundedRectangle(cornerRadius: size * 0.055, style: .continuous)
            .fill(
                LinearGradient(
                    colors: gradient,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: size * 0.66 * widthRatio, height: size * 0.12)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.055, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            )
    }
}

#if DEBUG
struct AppLogo_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            AppLogo(size: 28)
            AppLogo(size: 56, showsLabel: true)
            AppLogo(size: 128)
        }
        .padding(40)
        .background(Color.gray.opacity(0.1))
    }
}
#endif
