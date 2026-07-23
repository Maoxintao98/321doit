import AppKit
import SwiftUI

enum ToolIdentifier: String, Hashable, Identifiable {
    case storyboard
    case offload
    case scriptLog
    case shootingDay
    case mediaConverter

    var id: String { rawValue }
}

enum ToolAssociationMode: String, Hashable {
    case independent
    case linkedProject
}

struct ToolDescriptor: Identifiable {
    let id: ToolIdentifier
    let title: (String, String)
    let subtitle: (String, String)
    let detail: (String, String)
    let systemImage: String
    let accent: ToolAccent
}

enum ToolRegistry {
    static let builtIn: [ToolDescriptor] = [
        ToolDescriptor(
            id: .storyboard,
            title: ("灵动分镜", "Living Storyboard"),
            subtitle: ("所想即所见，所画即所拍", "From intent to frame"),
            detail: ("把脑海里的画面，变成现场真正拍得出来的镜头方案", "Turn the film in your head into shots the crew can actually make."),
            systemImage: "rectangle.on.rectangle.angled",
            accent: .storyboard
        ),
        ToolDescriptor(
            id: .offload,
            title: ("极速拷卡", "Turbo Offload"),
            subtitle: ("迅如闪电，坚如磐石", "Lightning fast. Rock solid."),
            detail: ("一次下盘，多重校验，让每份素材安全抵达后期", "Offload once, verify every copy, and send footage safely into post."),
            systemImage: "externaldrive.badge.checkmark",
            accent: .offload
        ),
        ToolDescriptor(
            id: .scriptLog,
            title: ("迅捷场记", "Rapid Script Log"),
            subtitle: ("指尖速记，一键导入", "Fast at your fingertips. One-click import."),
            detail: ("现场少打字、少漏记，收工后直接把清楚的记录交给后期", "Log faster on set and hand post a clean, complete record at wrap."),
            systemImage: "list.clipboard",
            accent: .scriptLog
        ),
        ToolDescriptor(
            id: .shootingDay,
            title: ("拍摄统筹", "Production Planning"),
            subtitle: ("计划周全，现场从容", "Plan thoroughly. Work calmly."),
            detail: ("把人、景、日程和通告排到一起，让现场按计划开拍", "Bring crew, locations, schedules, and call sheets into one shoot-ready plan."),
            systemImage: "calendar.badge.clock",
            accent: .shootingDay
        ),
        ToolDescriptor(
            id: .mediaConverter,
            title: ("媒体转换", "Media Conversion"),
            subtitle: ("瞬息转换，不损品质", "Instant conversion. Quality preserved."),
            detail: ("换封装、转码、核验一次完成，交付不再被格式卡住", "Rewrap, transcode, and verify in one pass—without format headaches at delivery."),
            systemImage: "arrow.triangle.2.circlepath",
            accent: .mediaConverter
        )
    ]

    static func descriptor(for id: ToolIdentifier) -> ToolDescriptor {
        builtIn.first { $0.id == id }!
    }
}

struct ToolHubView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @State private var hoveredTool: ToolIdentifier?
    @State private var operationMode: HubOperationMode = .manual
    @GestureState private var operationDragTranslation: CGFloat = 0
    let projectName: String?
    let runningTaskLabel: String?
    let associationMode: ToolAssociationMode
    let selectMode: (ToolAssociationMode) -> Void
    let launchAI: () -> Void
    let closeAI: () -> Void
    let launch: (ToolIdentifier) -> Void

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private static let miraLogo: NSImage? = {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        return NSImage(contentsOf: resourceURL.appendingPathComponent("Mira/Mira.png"))
    }()

    private enum HubOperationMode: Equatable {
        case manual
        case mira
    }

    var body: some View {
        ZStack {
            colors.surfaceBg

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        workspaceHeader

                        HStack(alignment: .firstTextBaseline) {
                            Text(L10n.t("选择工具", "Choose a Tool", language: lang))
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Label(activeModeLabel, systemImage: associationMode == .linkedProject ? "link" : "square.dashed")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(colors.textSecondary)
                        }
                        .padding(.horizontal, 2)

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 18),
                                GridItem(.flexible(), spacing: 18)
                            ],
                            spacing: 18
                        ) {
                            ForEach(ToolRegistry.builtIn) { descriptor in
                                toolCard(descriptor)
                            }
                        }

                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 36)
                    .padding(.bottom, 44)
                    .frame(maxWidth: 1120)
                    .frame(maxWidth: .infinity)
                }

                if let runningTaskLabel {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text(runningTaskLabel)
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text(L10n.t("任务会在切换工具后继续运行", "Tasks continue while switching tools", language: lang))
                            .font(.system(size: 10))
                            .foregroundStyle(colors.textSecondary)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .background(colors.panelBg)
                    .overlay(alignment: .top) { Divider() }
                }
            }
        }
    }

    private var workspaceHeader: some View {
        HStack(alignment: .center, spacing: 28) {
            HStack(alignment: .center, spacing: 18) {
                AppLogo(size: 52)
                VStack(alignment: .leading, spacing: 7) {
                    Text("321doit")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                    Text(L10n.t(
                        "开源免费的影视制作全能工作站",
                        "A free, open-source filmmaking workstation",
                        language: lang
                    ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                }
            }
            Spacer(minLength: 24)
            modeSelectors
        }
        .padding(26)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colors.panelBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(colors.hairline.opacity(0.7), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 16, y: 8)
    }

    private var modeSelectors: some View {
        VStack(alignment: .leading, spacing: 10) {
            operationModeSwitcher

            Button {
                selectMode(associationMode == .linkedProject ? .independent : .linkedProject)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: associationMode == .linkedProject ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(associationMode == .linkedProject ? colors.accent : colors.textSecondary)
                    Text(L10n.t("使用项目", "Use a Project", language: lang))
                        .fontWeight(.medium)
                        .foregroundStyle(colors.textPrimary)
                    if associationMode == .linkedProject, let projectName {
                        Text("· \(projectName)")
                            .foregroundStyle(colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 11))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(L10n.t(
                "勾选后，点击工具时再选择或新建项目",
                "When enabled, choose or create a project after clicking a tool",
                language: lang
            ))
            .accessibilityIdentifier("toolhub.useProject")
            .padding(.leading, 5)
        }
        .frame(width: 492)
    }

    private var operationModeSwitcher: some View {
        let segmentWidth: CGFloat = 242
        let leadingInset: CGFloat = 4
        let restingOffset = operationMode == .manual ? leadingInset : segmentWidth + leadingInset
        let sliderOffset = min(
            max(restingOffset + operationDragTranslation, leadingInset),
            segmentWidth + leadingInset
        )
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(colors.inputBg.opacity(0.72))
                .overlay(
                    Capsule()
                        .strokeBorder(colors.hairline.opacity(0.7), lineWidth: 0.8)
                )

            Color.clear
                .frame(width: segmentWidth, height: 42)
                .interactiveLiquidGlassCapsule(colors: colors)
                .offset(x: sliderOffset)
                .animation(.easeInOut(duration: 0.24), value: operationMode)

            HStack(spacing: 0) {
                operationModeButton(.manual)
                    .frame(width: segmentWidth)
                operationModeButton(.mira)
                    .frame(width: segmentWidth)
            }

        }
        .frame(width: 492, height: 50)
        .simultaneousGesture(
            DragGesture(minimumDistance: 3)
                .updating($operationDragTranslation) { value, state, _ in
                    state = value.translation.width
                }
                .onEnded { value in
                    let projectedOffset = min(
                        max(restingOffset + value.predictedEndTranslation.width, leadingInset),
                        segmentWidth + leadingInset
                    )
                    let targetMode: HubOperationMode = projectedOffset >= leadingInset + segmentWidth / 2
                        ? .mira
                        : .manual
                    let previousMode = operationMode
                    operationMode = targetMode
                    if targetMode == .mira, previousMode != .mira {
                        launchAI()
                    } else if targetMode == .manual, previousMode == .mira {
                        closeAI()
                    }
                }
        )
    }

    private var activeModeLabel: String {
        associationMode == .linkedProject
            ? (projectName ?? L10n.t("使用项目", "Use a Project", language: lang))
            : L10n.t("单次使用", "One-off Use", language: lang)
    }

    private func operationModeButton(_ mode: HubOperationMode) -> some View {
        let isSelected = operationMode == mode
        let title = mode == .manual
            ? L10n.t("人工操作", "Manual", language: lang)
            : "Mira AI"
        return Button {
            let previousMode = operationMode
            operationMode = mode
            if mode == .mira {
                launchAI()
            } else if previousMode == .mira {
                closeAI()
            }
        } label: {
            HStack(spacing: 9) {
                if mode == .manual {
                    Image(systemName: "hand.point.up.left")
                        .frame(width: 18, height: 18)
                } else if let logo = Self.miraLogo {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image(systemName: "sparkles")
                        .frame(width: 18, height: 18)
                }
                Text(title)
            }
            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? colors.textPrimary : colors.textSecondary.opacity(0.68))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityIdentifier(mode == .manual ? "toolhub.operation.manual" : "toolhub.operation.ai")
        .help(mode == .manual
            ? L10n.t("使用 321Doit 的人工操作工具", "Use 321Doit's manual tools", language: lang)
            : L10n.t("打开 Mira AI 全局工作台", "Open the global Mira AI workspace", language: lang))
    }

    private func toolCard(_ descriptor: ToolDescriptor) -> some View {
        let accent = descriptor.accent
        let isHovered = hoveredTool == descriptor.id
        return Button { launch(descriptor.id) } label: {
            HStack(spacing: 19) {
                ToolAccentIconTile(systemImage: descriptor.systemImage, accent: accent, size: 64)

                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.t(descriptor.title.0, descriptor.title.1, language: lang))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(L10n.t(descriptor.subtitle.0, descriptor.subtitle.1, language: lang))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(accent.primary)
                    Text(L10n.t(descriptor.detail.0, descriptor.detail.1, language: lang))
                        .font(.system(size: 11.5))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 3)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isHovered ? Color.white : colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(isHovered ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(colors.inputBg.opacity(0.65)))
                    )
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colors.panelBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isHovered ? accent.primary.opacity(0.42) : colors.hairline.opacity(0.72), lineWidth: isHovered ? 1.0 : 0.8)
            )
            .shadow(color: isHovered ? accent.primary.opacity(0.16) : Color.black.opacity(0.04), radius: isHovered ? 18 : 8, y: isHovered ? 10 : 4)
            .scaleEffect(isHovered ? 1.008 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("toolhub.tool.\(descriptor.id.rawValue)")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                hoveredTool = hovering ? descriptor.id : nil
            }
        }
    }

}

struct ToolShell<Content: View>: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    let title: String
    let tool: ToolIdentifier
    let associationMode: ToolAssociationMode
    let projectName: String?
    let goHome: () -> Void
    let openProjectManager: () -> Void
    @ViewBuilder let content: () -> Content

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private var accent: ToolAccent { tool.accent }

    var body: some View {
        VStack(spacing: 0) {
            // 工具色沉浸式顶栏（中性底 + 工具色控件，无彩色横条）
            HStack(spacing: 12) {
                Button(action: goHome) {
                    Label(L10n.t("工具箱", "Toolbox", language: lang), systemImage: "square.grid.2x2")
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .accessibilityIdentifier("tool.\(tool.rawValue).backToToolbox")
                Divider().frame(height: 22)
                ToolAccentIconTile(systemImage: toolSystemImage, accent: accent, size: 26, iconSize: 12)
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: openProjectManager) {
                    Label(
                        associationMode == .linkedProject
                            ? (projectName ?? L10n.t("关联项目", "Linked Project", language: lang))
                            : L10n.t("独立模式", "Independent", language: lang),
                        systemImage: associationMode == .linkedProject ? "link" : "square.dashed"
                    )
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .accessibilityIdentifier("tool.\(tool.rawValue).projectContext")
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
            .background(colors.panelBg)
            .overlay(alignment: .bottom) { Divider() }

            content()
        }
        .background(colors.surfaceBg)
        .tint(accent.primary)
        .accentColor(accent.primary)
        .environment(\.toolAccentColor, accent.primary)
    }

    private var toolSystemImage: String {
        ToolRegistry.descriptor(for: tool).systemImage
    }
}
