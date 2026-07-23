import SwiftUI

extension View {
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
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
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
            self.glassEffect(.regular.interactive(), in: .capsule)
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
