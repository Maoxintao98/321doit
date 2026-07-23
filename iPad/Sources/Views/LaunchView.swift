import SwiftUI

/// Minimal launch animation: the app mark draws in with a soft scale/fade, then
/// the "Designed by Mao Xintao" credit fades up beneath it. Calls `onFinish`
/// after a short beat so the main UI takes over.
struct LaunchView: View {
    var onFinish: () -> Void

    @State private var markVisible = false
    @State private var creditVisible = false

    var body: some View {
        ZStack {
            // Same charcoal-blue as the app icon background.
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.13, blue: 0.18),
                         Color(red: 0.04, green: 0.06, blue: 0.10)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                LaunchMark()
                    .frame(width: 96, height: 96)
                    .scaleEffect(markVisible ? 1 : 0.82)
                    .opacity(markVisible ? 1 : 0)

                Text("Designed by Mao Xintao")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.55))
                    .opacity(creditVisible ? 1 : 0)
                    .offset(y: creditVisible ? 0 : 6)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                markVisible = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.45)) {
                creditVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                onFinish()
            }
        }
    }
}

/// The three-bar app mark (3:2:1), matching the app icon, drawn in SwiftUI so it
/// scales crisply at any size.
private struct LaunchMark: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let barH = w * 0.16
            let spacing = w * 0.13
            let radius = barH * 0.34
            let ratios: [CGFloat] = [1.0, 0.66, 0.34]
            let grads: [[Color]] = [
                [Color(red: 0.30, green: 0.78, blue: 1.00), Color(red: 0.14, green: 0.50, blue: 0.95)],
                [Color(red: 0.30, green: 0.78, blue: 1.00).opacity(0.9), Color(red: 0.14, green: 0.50, blue: 0.95).opacity(0.85)],
                [Color(red: 1.00, green: 0.78, blue: 0.30), Color(red: 1.00, green: 0.78, blue: 0.30).opacity(0.7)]
            ]
            VStack(alignment: .leading, spacing: spacing) {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(LinearGradient(colors: grads[i], startPoint: .leading, endPoint: .trailing))
                        .frame(width: w * ratios[i], height: barH)
                }
            }
            .frame(width: w, height: w, alignment: .center)
        }
    }
}
