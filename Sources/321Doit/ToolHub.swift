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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var hoveredTool: ToolIdentifier?
    @State private var hoveredHeaderAction: HeaderAction?
    let runningTaskLabel: String?
    let associationMode: ToolAssociationMode
    let selectMode: (ToolAssociationMode) -> Void
    let launchAI: () -> Void
    let openProject: () -> Void
    let showIndependentModeAlert: () -> Void
    let launch: (ToolIdentifier) -> Void

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private var reducesMotion: Bool { systemReduceMotion || settings.settings.general.reduceMotion }
    private static let miraLogo: NSImage? = {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        return NSImage(contentsOf: resourceURL.appendingPathComponent("Mira/Mira.png"))
    }()

    private enum HeaderAction {
        case openProject
        case aiMode
    }

    var body: some View {
        ZStack {
            colors.surfaceBg

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
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
                    .padding(.horizontal, 44)
                    .padding(.top, 32)
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
        HStack(alignment: .center, spacing: 30) {
            HStack(alignment: .center, spacing: 16) {
                AppLogo(size: 48)
                VStack(alignment: .leading, spacing: 5) {
                    Text("321Doit")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                    Text(L10n.t(
                        "本地优先的影视制作全能工作站",
                        "A local-first filmmaking workstation",
                        language: lang
                    ))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                }
            }
            Spacer(minLength: 24)
            modeSelectors
        }
        .padding(24)
        .doitSurface(
            colors: colors,
            cornerRadius: DoitVisual.radiusHero,
            elevation: .raised
        )
    }

    private var modeSelectors: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                selectMode(associationMode == .independent ? .linkedProject : .independent)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: associationMode == .independent ? "checkmark.square.fill" : "square")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(associationMode == .independent ? colors.accent : colors.textSecondary)
                    Text(L10n.t(
                        "不使用项目 · 独立使用工具",
                        "Don't use a project · Open tools independently",
                        language: lang
                    ))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: DoitVisual.controlHeight)
                .contentShape(Rectangle())
                .doitSurface(
                    colors: colors,
                    cornerRadius: DoitVisual.radiusControl,
                    fill: colors.inputBg.opacity(associationMode == .independent ? 0.76 : 0.5),
                    elevation: .inset,
                    accent: colors.accent,
                    isHovered: false
                )
            }
            .buttonStyle(DoitPressableButtonStyle(reduceMotion: reducesMotion, pressedScale: 0.992))
            .focusable(false)
            .help(L10n.t(
                "默认使用项目。勾选后工具将不关联项目直接打开。",
                "Projects are used by default. Select this to open tools without a project.",
                language: lang
            ))
            .accessibilityIdentifier("toolhub.independentMode")
            .animation(DoitVisual.stateAnimation(reduceMotion: reducesMotion), value: associationMode)

            HStack(spacing: 10) {
                headerActionButton(
                    .openProject,
                    title: L10n.t("打开项目", "Open Project", language: lang)
                ) {
                    associationMode == .independent ? showIndependentModeAlert() : openProject()
                }
                headerActionButton(
                    .aiMode,
                    title: L10n.t("AI 模式", "AI Mode", language: lang),
                    action: launchAI
                )
            }
        }
        .frame(width: 400)
    }

    private var activeModeLabel: String {
        associationMode == .linkedProject
            ? L10n.t("项目工作流", "Project Workflow", language: lang)
            : L10n.t("独立使用", "Independent Use", language: lang)
    }

    private func headerActionButton(
        _ headerAction: HeaderAction,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        let isMuted = headerAction == .openProject && associationMode == .independent
        let isHovered = hoveredHeaderAction == headerAction

        return Button(action: action) {
            HStack(spacing: 11) {
                headerActionIcon(headerAction, isMuted: isMuted)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isMuted ? colors.textTertiary.opacity(0.7) : colors.textSecondary)
            }
            .foregroundStyle(isMuted ? colors.textTertiary : colors.textPrimary)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: DoitVisual.largeControlHeight)
            .doitSurface(
                colors: colors,
                cornerRadius: DoitVisual.radiusControl,
                fill: colors.inputBg.opacity(isMuted ? 0.34 : (isHovered ? 0.86 : 0.64)),
                elevation: .panel,
                accent: headerAction == .aiMode ? colors.accent : nil,
                isHovered: isHovered && !isMuted,
                isMuted: isMuted
            )
        }
        .buttonStyle(DoitPressableButtonStyle(reduceMotion: reducesMotion))
        .focusable(false)
        .accessibilityIdentifier(headerAction == .openProject ? "toolhub.openProject" : "toolhub.aiMode")
        .help(headerAction == .openProject
            ? (isMuted
                ? L10n.t("请先关闭独立模式", "Turn off Independent Mode first", language: lang)
                : L10n.t("打开现有的 321Doit 项目", "Open an existing 321Doit project", language: lang))
            : L10n.t("打开 Mira AI 模式", "Open Mira AI Mode", language: lang))
        .onHover { hovering in
            withAnimation(DoitVisual.hoverAnimation(reduceMotion: reducesMotion)) {
                hoveredHeaderAction = hovering ? headerAction : nil
            }
        }
        .animation(DoitVisual.stateAnimation(reduceMotion: reducesMotion), value: associationMode)
    }

    @ViewBuilder
    private func headerActionIcon(_ headerAction: HeaderAction, isMuted: Bool) -> some View {
        if headerAction == .aiMode, let miraLogo = Self.miraLogo {
            Image(nsImage: miraLogo)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: DoitVisual.radiusSmall, style: .continuous))
        } else {
            Image(systemName: headerAction == .openProject ? "folder" : "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isMuted ? colors.textTertiary : colors.textPrimary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: DoitVisual.radiusSmall, style: .continuous)
                        .fill(colors.panelBg.opacity(isMuted ? 0.35 : 0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DoitVisual.radiusSmall, style: .continuous)
                        .strokeBorder(colors.hairline.opacity(isMuted ? 0.25 : 0.55), lineWidth: 0.6)
                )
        }
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
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .leading)
            .doitSurface(
                colors: colors,
                cornerRadius: DoitVisual.radiusCard,
                elevation: .panel,
                accent: accent.primary,
                isHovered: isHovered
            )
        }
        .buttonStyle(DoitPressableButtonStyle(reduceMotion: reducesMotion))
        .accessibilityIdentifier("toolhub.tool.\(descriptor.id.rawValue)")
        .onHover { hovering in
            withAnimation(DoitVisual.hoverAnimation(reduceMotion: reducesMotion)) {
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
