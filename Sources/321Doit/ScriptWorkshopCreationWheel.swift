import AppKit
import SwiftUI

struct ScriptWorkshopWheelOverlayState: Equatable {
    var origin: CGPoint
    var highlightedKind: ScriptWorkshopBlockKind?
    var showsCharacterRing: Bool
    var characterPage: Int
    var highlightedCharacterID: String?
    var usesKeyboardSelection: Bool
    var targetSceneID: UUID
    var targetBlockID: UUID
}

enum ScriptWorkshopWheelEvent {
    case began(CGPoint)
    case moved(CGPoint)
    case activated(CGPoint)
    case keyboard(ScriptWorkshopWheelKeyboardInput)
    case ended(CGPoint)
    case cancelled
}

struct ScriptWorkshopCreationWheel: View {
    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var revealsPrimary = false
    @State private var revealsSecondary = false

    let highlightedKind: ScriptWorkshopBlockKind?
    let characterPages: [[ScriptWorkshopWheelCharacterChoice]]
    let activeCharacterPage: Int
    let showsCharacterRing: Bool
    let highlightedCharacterID: String?
    let language: AppLanguage

    private let accent = ToolAccent.scriptWorkshop

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height) * 0.94
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = diameter / 2
            let count = max(options.count, 1)
            let step = 360.0 / Double(count)

            ZStack {
                Circle()
                    .fill(colors.inputBg.opacity(0.76))
                    .frame(width: diameter * 0.66, height: diameter * 0.66)
                    .position(center)
                    .shadow(color: Color.black.opacity(0.24), radius: 24, y: 12)
                    .scaleEffect(revealsPrimary ? 1 : 0.35)
                    .opacity(revealsPrimary ? 1 : 0)

                ForEach(Array(options.enumerated()), id: \.element.kind) { index, option in
                    let start = Angle.degrees(-90 - step / 2 + Double(index) * step)
                    let end = Angle.degrees(-90 - step / 2 + Double(index + 1) * step)
                    let mid = Angle.degrees(-90 + Double(index) * step)
                    let selected = option.kind == highlightedKind
                    let segment = ScriptWorkshopWheelSegment(
                        startAngle: start,
                        endAngle: end,
                        innerRatio: 0.26,
                        outerRatio: 0.64
                    )

                    ZStack {
                        segment
                            .fill(selected ? accent.primary : colors.panelBg)
                        segment
                            .strokeBorder(
                                selected ? Color.white.opacity(0.52) : colors.hairline.opacity(0.86),
                                lineWidth: selected ? 1.5 : 0.8
                            )
                        VStack(spacing: 5) {
                            Text("\(index + 1)")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(selected ? Color.white.opacity(0.88) : colors.textTertiary)
                            Image(systemName: option.systemImage)
                                .font(.system(size: 16, weight: .semibold))
                            Text(option.label)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(selected ? Color.white : colors.textPrimary)
                        .position(
                            x: diameter / 2 + cos(CGFloat(mid.radians)) * radius * 0.45,
                            y: diameter / 2 + sin(CGFloat(mid.radians)) * radius * 0.45
                        )
                    }
                    .frame(width: diameter, height: diameter)
                    .position(center)
                    .scaleEffect(revealsPrimary ? (selected ? 1.035 : 1) : 0.46)
                    .opacity(revealsPrimary ? 1 : 0)
                    .shadow(
                        color: selected ? accent.primary.opacity(0.32) : .clear,
                        radius: selected ? 12 : 0
                    )
                    .animation(
                        reduceMotion
                            ? nil
                            : .spring(response: 0.27, dampingFraction: 0.72)
                                .delay(Double(index) * 0.018),
                        value: revealsPrimary
                    )
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.76),
                        value: selected
                    )
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(option.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }

                if showsCharacterRing {
                    let visiblePages = Array(characterPages.prefix(activeCharacterPage + 1))
                    ForEach(Array(visiblePages.enumerated()), id: \.offset) { pageIndex, choices in
                        characterRing(
                            choices: choices,
                            pageIndex: pageIndex,
                            visiblePageCount: visiblePages.count,
                            diameter: diameter,
                            center: center
                        )
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                    }
                }

                Circle()
                    .fill(colors.panelBg)
                    .frame(width: diameter * 0.23, height: diameter * 0.23)
                    .overlay {
                        VStack(spacing: 5) {
                            Text(L10n.t("创作轮", "Creation Wheel", language: language))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(colors.textSecondary)
                            Text(centerValue)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(accent.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    }
                    .overlay(
                        Circle().strokeBorder(accent.primary.opacity(0.30), lineWidth: 1)
                    )
                    .position(center)
                    .scaleEffect(revealsPrimary ? 1 : 0.18)
                    .opacity(revealsPrimary ? 1 : 0)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.66),
                        value: revealsPrimary
                    )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(8)
        .allowsHitTesting(false)
        .accessibilityIdentifier("scriptWorkshop.creationWheel")
        .onAppear {
            if reduceMotion {
                revealsPrimary = true
                revealsSecondary = showsCharacterRing
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.70)) {
                    revealsPrimary = true
                }
                revealsSecondary = showsCharacterRing
            }
        }
        .onChange(of: showsCharacterRing) { isShowing in
            if reduceMotion {
                revealsSecondary = isShowing
            } else {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.74)) {
                    revealsSecondary = isShowing
                }
            }
        }
    }

    private var centerValue: String {
        if let highlightedCharacterID,
           let choice = characterPages
            .flatMap({ $0 })
            .first(where: { $0.id == highlightedCharacterID }) {
            if choice.isMore {
                return L10n.t("更多人物", "More characters", language: language)
            }
            return choice.isAdd
                ? L10n.t("新增人物", "New character", language: language)
                : choice.name ?? ""
        }
        guard let highlightedKind else {
            return L10n.t("指向后松开", "Point, then release", language: language)
        }
        return options.first(where: { $0.kind == highlightedKind })?.label ?? ""
    }

    @ViewBuilder
    private func characterRing(
        choices: [ScriptWorkshopWheelCharacterChoice],
        pageIndex: Int,
        visiblePageCount: Int,
        diameter: CGFloat,
        center: CGPoint
    ) -> some View {
        let count = max(choices.count, 1)
        let step = 360.0 / Double(count)
        let radius = diameter / 2
        let ringRatios = ScriptWorkshopWheelInteraction.characterRingRatios(
            pageIndex: pageIndex,
            visiblePageCount: visiblePageCount
        )
        let innerRatio = ringRatios.inner
        let outerRatio = ringRatios.outer
        let labelRatio = (innerRatio + outerRatio) / 2
        let isActivePage = pageIndex == activeCharacterPage

        ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
            let start = Angle.degrees(-90 - step / 2 + Double(index) * step)
            let end = Angle.degrees(-90 - step / 2 + Double(index + 1) * step)
            let mid = Angle.degrees(-90 + Double(index) * step)
            let selected = choice.id == highlightedCharacterID
                || (!isActivePage && choice.isMore && pageIndex < activeCharacterPage)
            let label: String = if choice.isMore {
                L10n.t("更多", "More", language: language)
            } else if choice.isAdd {
                L10n.t("新增人物", "New", language: language)
            } else {
                choice.name ?? ""
            }

            ZStack {
                ScriptWorkshopWheelSegment(
                    startAngle: start,
                    endAngle: end,
                    innerRatio: innerRatio,
                    outerRatio: outerRatio
                )
                .fill(selected ? accent.primary : colors.inputBg.opacity(isActivePage ? 0.96 : 0.74))
                ScriptWorkshopWheelSegment(
                    startAngle: start,
                    endAngle: end,
                    innerRatio: innerRatio,
                    outerRatio: outerRatio
                )
                .strokeBorder(
                    selected ? Color.white.opacity(0.62) : colors.hairline.opacity(0.82),
                    lineWidth: selected ? 1.5 : 0.8
                )
                VStack(spacing: 3) {
                    if isActivePage {
                        Text("\(index + 1)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(selected ? Color.white.opacity(0.88) : colors.textTertiary)
                    }
                    Image(systemName: choice.isMore ? "ellipsis.circle.fill" : (choice.isAdd ? "person.badge.plus" : "person.crop.circle.fill"))
                        .font(.system(size: visiblePageCount > 1 ? 11 : 14, weight: .semibold))
                    Text(label)
                        .font(.system(size: visiblePageCount > 1 ? 8 : 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: max(34, diameter * 0.78 * sin(.pi / CGFloat(count))))
                }
                .foregroundStyle(selected ? Color.white : colors.textPrimary)
                .position(
                    x: diameter / 2 + cos(CGFloat(mid.radians)) * radius * labelRatio,
                    y: diameter / 2 + sin(CGFloat(mid.radians)) * radius * labelRatio
                )
            }
            .frame(width: diameter, height: diameter)
            .position(center)
            .scaleEffect(revealsSecondary ? (selected ? 1.025 : 1) : 0.68)
            .rotationEffect(.degrees(revealsSecondary ? 0 : -7))
            .opacity(revealsSecondary ? 1 : 0)
            .shadow(
                color: selected ? accent.primary.opacity(0.28) : .clear,
                radius: selected ? 10 : 0
            )
            .animation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.31, dampingFraction: 0.72)
                        .delay(0.075 + Double(index) * 0.014),
                value: revealsSecondary
            )
            .animation(
                reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.78),
                value: selected
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    private var options: [ScriptWorkshopWheelOption] {
        ScriptWorkshopWheelRegistry.primary.map {
            ScriptWorkshopWheelOption(
                kind: $0.kind,
                label: label(for: $0.kind),
                systemImage: $0.systemImage
            )
        }
    }

    private func label(for kind: ScriptWorkshopBlockKind) -> String {
        switch kind {
        case .action: return L10n.t("动作", "Action", language: language)
        case .character: return L10n.t("人物", "Character", language: language)
        case .dialogue: return L10n.t("对白", "Dialogue", language: language)
        case .parenthetical: return L10n.t("括号", "Parenthetical", language: language)
        case .transition: return L10n.t("转场", "Transition", language: language)
        case .shot: return L10n.t("镜头", "Shot", language: language)
        case .note: return L10n.t("笔记", "Note", language: language)
        }
    }
}

private struct ScriptWorkshopWheelOption {
    let kind: ScriptWorkshopBlockKind
    let label: String
    let systemImage: String
}

private struct ScriptWorkshopWheelSegment: InsettableShape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRatio: CGFloat
    var outerRatio: CGFloat = 1
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = min(rect.width, rect.height) / 2
        let outerRadius = baseRadius * outerRatio - insetAmount
        let innerRadius = baseRadius * innerRatio + insetAmount
        var path = Path()
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> ScriptWorkshopWheelSegment {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

enum ScriptWorkshopEditorIdentity {
    static let blockEditor = NSUserInterfaceItemIdentifier("scriptWorkshop.blockEditor")
}

/// Converts AppKit window points into the exact SwiftUI wheel-host coordinate
/// space. Keeping this conversion in NSView avoids flipped-axis and shell-offset
/// mismatches between the native editor and the rendered sectors.
@MainActor
final class ScriptWorkshopWheelCoordinateConverter: ObservableObject {
    fileprivate weak var hostView: NSView?

    func localPoint(from windowPoint: CGPoint, in window: NSWindow?) -> CGPoint? {
        guard let hostView,
              let window,
              hostView.window === window else { return nil }
        return hostView.convert(windowPoint, from: nil)
    }
}

struct ScriptWorkshopWheelCoordinateReader: NSViewRepresentable {
    let converter: ScriptWorkshopWheelCoordinateConverter

    func makeNSView(context: Context) -> NSView {
        let view = ScriptWorkshopWheelCoordinateView()
        converter.hostView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        converter.hostView = nsView
    }

    static func dismantleNSView(
        _ nsView: NSView,
        coordinator: Void
    ) {
        // A rebuilt reader replaces this reference during make/update.
    }
}

private final class ScriptWorkshopWheelCoordinateView: NSView {
    override var isFlipped: Bool { true }
}
