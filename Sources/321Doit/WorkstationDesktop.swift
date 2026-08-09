import SwiftUI

enum WorkstationSection: String, CaseIterable, Identifiable {
    case overview
    case scriptWorkshop
    case storyboard
    case shootingDay
    case scriptLog
    case offload
    case mediaConverter
    case handoff
    case reports

    var id: String { rawValue }

    var toolIdentifier: ToolIdentifier? {
        switch self {
        case .scriptWorkshop: return .scriptWorkshop
        case .storyboard: return .storyboard
        case .shootingDay: return .shootingDay
        case .scriptLog: return .scriptLog
        case .offload: return .offload
        case .mediaConverter: return .mediaConverter
        case .overview, .handoff, .reports: return nil
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .overview: return L10n.t("总览", "Overview", language: language)
        case .scriptWorkshop: return L10n.t("剧本", "Script", language: language)
        case .storyboard: return L10n.t("分镜", "Storyboard", language: language)
        case .shootingDay: return L10n.t("统筹", "Planning", language: language)
        case .scriptLog: return L10n.t("场记", "Script Log", language: language)
        case .offload: return L10n.t("下盘", "Offload", language: language)
        case .mediaConverter: return L10n.t("转换", "Convert", language: language)
        case .handoff: return L10n.t("交付", "Handoff", language: language)
        case .reports: return L10n.t("报告", "Reports", language: language)
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .scriptWorkshop: return "text.document"
        case .storyboard: return "rectangle.on.rectangle.angled"
        case .shootingDay: return "calendar.badge.clock"
        case .scriptLog: return "list.clipboard"
        case .offload: return "externaldrive.badge.checkmark"
        case .mediaConverter: return "arrow.triangle.2.circlepath"
        case .handoff: return "shippingbox"
        case .reports: return "doc.text.magnifyingglass"
        }
    }
}

enum WorkstationQuickAction {
    case offload
    case verify
    case convert
}

private struct WorkstationNavigationGroup: Identifiable {
    let id: String
    let title: (String, String)
    let sections: [WorkstationSection]
}

/// A restrained wordmark for the workstation chrome. The full app icon is
/// intentionally not placed in another dark tile here; at navigation scale it
/// reads as a second tool button instead of a brand.
private struct WorkstationWordmark: View {
    let size: CGFloat
    let primary: Color
    let accent: Color

    var body: some View {
        HStack(spacing: max(7, size * 0.34)) {
            Capsule(style: .continuous)
                .fill(accent)
                .frame(width: max(3, size * 0.12), height: size * 0.94)
            HStack(spacing: 0) {
                Text("321")
                    .font(.system(size: size, weight: .bold, design: .rounded))
                Text("Doit")
                    .font(.system(size: size, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("321Doit")
    }
}

struct WorkstationLaunchView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    let recentProjects: [RecentProject]
    let resumeProject: (RecentProject) -> Void
    let openProject: (RecentProject) -> Void
    let newProject: () -> Void
    let browseProject: () -> Void
    let quickAction: (WorkstationQuickAction) -> Void
    let launchAI: () -> Void

    @State private var hoveredID: String?

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private var reducesMotion: Bool { systemReduceMotion || settings.settings.general.reduceMotion }
    private var firstAccessibleProject: RecentProject? { recentProjects.first(where: \.isAccessible) }

    var body: some View {
        ZStack {
            DoitGlassBackdrop(colors: colors)

            ScrollView {
                VStack(alignment: .leading, spacing: DoitSpacing.xl) {
                    masthead

                    if let firstAccessibleProject {
                        continueCard(firstAccessibleProject)
                    }

                    recentProjectsSection
                    quickTasksSection
                }
                .padding(.horizontal, DoitSpacing.xxl)
                .padding(.top, 42)
                .padding(.bottom, 54)
                .frame(maxWidth: 1_180, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("workstation.launch")
    }

    private var masthead: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                WorkstationWordmark(size: 30, primary: colors.textPrimary, accent: colors.accent)
                Text(L10n.t(
                    "把一部片，从纸面推进到现场与后期",
                    "Move a film from the page to set and post",
                    language: lang
                ))
                .font(DoitFont.body)
                .foregroundStyle(colors.textSecondary)
            }

            Spacer()

            Button(action: launchAI) {
                Label("Mira AI", systemImage: "sparkles")
                    .font(DoitFont.bodyEmphasis)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .interactiveLiquidGlassCapsule(colors: colors)
            }
            .buttonStyle(.plain)
            .foregroundStyle(colors.textPrimary)

            Button(action: newProject) {
                Label(L10n.t("新建项目", "New Project", language: lang), systemImage: "plus")
                    .font(DoitFont.bodyEmphasis)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityIdentifier("workstation.newProject")
        }
    }

    private func continueCard(_ project: RecentProject) -> some View {
        let isHovered = hoveredID == "continue"
        return Button { resumeProject(project) } label: {
            HStack(spacing: DoitSpacing.lg) {
                VStack(alignment: .leading, spacing: DoitSpacing.xs) {
                    Text(L10n.t("继续工作", "CONTINUE WORKING", language: lang))
                        .font(DoitFont.caption)
                        .tracking(1.2)
                        .foregroundStyle(colors.warm)
                    Text(displayName(project))
                        .font(DoitFont.display)
                        .foregroundStyle(colors.textPrimary)
                    Text(project.lastOpenedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(DoitFont.callout)
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                HStack(spacing: 9) {
                    Text(L10n.t("回到上次工作位置", "Return to your last workspace", language: lang))
                        .font(DoitFont.callout)
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, DoitSpacing.md)
                .frame(height: 38)
                .background(colors.accent, in: Capsule())
                .shadow(color: colors.accent.opacity(0.30), radius: isHovered ? 12 : 6, x: 0, y: 4)
            }
            .padding(.horizontal, DoitSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .liquidGlassSurface(colors: colors, cornerRadius: DoitRadius.panel)
            .overlay(
                RoundedRectangle(cornerRadius: DoitRadius.panel, style: .continuous)
                    .strokeBorder(isHovered ? colors.accent.opacity(0.55) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(DoitPressableButtonStyle(reduceMotion: reducesMotion, pressedScale: 0.996))
        .accessibilityIdentifier("workstation.continue")
        .onHover { hovering in
            withAnimation(DoitVisual.hoverAnimation(reduceMotion: reducesMotion)) {
                hoveredID = hovering ? "continue" : nil
            }
        }
    }

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: DoitSpacing.sm) {
            HStack {
                sectionTitle(L10n.t("最近项目", "Recent Projects", language: lang))
                Spacer()
                Button(action: browseProject) {
                    Label(L10n.t("打开其他项目", "Open Another Project", language: lang), systemImage: "folder")
                        .font(DoitFont.callout)
                }
                .buttonStyle(.borderless)
            }

            if recentProjects.isEmpty {
                emptyProjects
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: DoitSpacing.sm), GridItem(.flexible(), spacing: DoitSpacing.sm)],
                    spacing: DoitSpacing.sm
                ) {
                    ForEach(recentProjects.prefix(6)) { project in
                        recentProjectCard(project)
                    }
                }
            }
        }
    }

    private var quickTasksSection: some View {
        VStack(alignment: .leading, spacing: DoitSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle(L10n.t("快速任务", "Quick Tasks", language: lang))
                Spacer()
                Text(L10n.t("无需创建项目", "No project required", language: lang))
                    .font(DoitFont.caption)
                    .foregroundStyle(colors.textTertiary)
            }

            HStack(spacing: DoitSpacing.sm) {
                quickTaskButton(
                    id: "offload",
                    title: L10n.t("安全下盘", "Verified Offload", language: lang),
                    subtitle: L10n.t("复制、校验与报告", "Copy, verify, and report", language: lang),
                    systemImage: "externaldrive.badge.checkmark"
                ) { quickAction(.offload) }
                quickTaskButton(
                    id: "verify",
                    title: L10n.t("校验备份", "Verify Backup", language: lang),
                    subtitle: L10n.t("只核验已有副本", "Check an existing copy", language: lang),
                    systemImage: "checkmark.shield"
                ) { quickAction(.verify) }
                quickTaskButton(
                    id: "convert",
                    title: L10n.t("媒体转换", "Media Conversion", language: lang),
                    subtitle: L10n.t("换封装、转码与检查", "Rewrap, transcode, and inspect", language: lang),
                    systemImage: "arrow.triangle.2.circlepath"
                ) { quickAction(.convert) }
            }
        }
    }

    private func recentProjectCard(_ project: RecentProject) -> some View {
        let key = "project-\(project.id)"
        let isHovered = hoveredID == key
        return Button { openProject(project) } label: {
            HStack(spacing: 14) {
                Image(systemName: project.isAccessible ? "folder" : "exclamationmark.triangle")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(project.isAccessible ? colors.textSecondary : colors.stateWarning)
                    .frame(width: 36, height: 36)
                    .background(colors.inputBg.opacity(0.76), in: RoundedRectangle(cornerRadius: DoitRadius.control, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName(project))
                        .font(DoitFont.bodyEmphasis)
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                    Text(project.url.deletingPathExtension().deletingLastPathComponent().path)
                        .font(DoitFont.monoCaption)
                        .foregroundStyle(colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Image(systemName: project.isAccessible ? "arrow.right" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isHovered ? colors.textPrimary : colors.textTertiary)
            }
            .padding(.horizontal, DoitSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 74)
            .liquidGlassSurface(colors: colors, cornerRadius: DoitRadius.card)
            .overlay(
                RoundedRectangle(cornerRadius: DoitRadius.card, style: .continuous)
                    .strokeBorder(isHovered ? colors.accent.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(DoitPressableButtonStyle(reduceMotion: reducesMotion, pressedScale: 0.995))
        .onHover { hovering in
            withAnimation(DoitVisual.hoverAnimation(reduceMotion: reducesMotion)) {
                hoveredID = hovering ? key : nil
            }
        }
    }

    private func quickTaskButton(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        let key = "quick-\(id)"
        let isHovered = hoveredID == key
        return Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(colors.inputBg.opacity(0.78), in: RoundedRectangle(cornerRadius: DoitRadius.control, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(DoitFont.bodyEmphasis)
                        .foregroundStyle(colors.textPrimary)
                    Text(subtitle)
                        .font(DoitFont.caption)
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 68)
            .liquidGlassSurface(colors: colors, cornerRadius: DoitRadius.card)
            .overlay(
                RoundedRectangle(cornerRadius: DoitRadius.card, style: .continuous)
                    .strokeBorder(isHovered ? colors.accent.opacity(0.45) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(DoitPressableButtonStyle(reduceMotion: reducesMotion, pressedScale: 0.995))
        .onHover { hovering in
            withAnimation(DoitVisual.hoverAnimation(reduceMotion: reducesMotion)) {
                hoveredID = hovering ? key : nil
            }
        }
    }

    private var emptyProjects: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(colors.textTertiary)
            Text(L10n.t("从一个新项目开始你的下一部片", "Start your next film with a new project", language: lang))
                .font(DoitFont.callout)
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 116)
        .liquidGlassSurface(colors: colors, cornerRadius: DoitRadius.card)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DoitFont.title2)
            .foregroundStyle(colors.textPrimary)
    }

    private func displayName(_ project: RecentProject) -> String {
        let normalized = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || normalized == "Untitled" || normalized == "未命名项目" {
            return project.url.deletingPathExtension().lastPathComponent
        }
        return normalized
    }
}

struct WorkstationShell<Content: View>: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @Binding var selection: WorkstationSection
    let isProjectLinked: Bool
    let projectName: String?
    let projectPath: String?
    let runningTaskLabel: String?
    let goToLibrary: () -> Void
    let openProjectManager: () -> Void
    let launchAI: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var hoveredSection: WorkstationSection?

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private var reducesMotion: Bool { systemReduceMotion || settings.settings.general.reduceMotion }

    /// Inner cards sit on the glass rail; they use a quiet adaptive fill
    /// rather than a second layer of glass.
    private var railInnerFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.white.opacity(0.42)
    }
    private var railInnerHairline: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.06)
    }

    private var groups: [WorkstationNavigationGroup] {
        if !isProjectLinked {
            return [
                WorkstationNavigationGroup(
                    id: "quick",
                    title: ("快速任务", "QUICK TASKS"),
                    sections: [.offload, .mediaConverter]
                )
            ]
        }
        return [
            WorkstationNavigationGroup(id: "create", title: ("创作", "CREATE"), sections: [.scriptWorkshop, .storyboard]),
            WorkstationNavigationGroup(id: "produce", title: ("制作", "PRODUCE"), sections: [.shootingDay, .scriptLog]),
            WorkstationNavigationGroup(id: "media", title: ("素材", "MEDIA"), sections: [.offload, .mediaConverter]),
            WorkstationNavigationGroup(id: "finish", title: ("交付", "FINISH"), sections: [.handoff, .reports])
        ]
    }

    var body: some View {
        HStack(spacing: DoitSpacing.sm) {
            navigationRail
            VStack(spacing: 0) {
                workspaceHeader
                Divider().overlay(colors.hairline)
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.leading, DoitSpacing.sm)
        .padding(.vertical, DoitSpacing.sm)
        .background { DoitGlassBackdrop(colors: colors) }
        .tint(colors.accent)
        .accentColor(colors.accent)
        .environment(\.toolAccentColor, colors.accent)
        .accessibilityIdentifier("workstation.shell")
    }

    private var navigationRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: goToLibrary) {
                HStack {
                    WorkstationWordmark(size: 17, primary: colors.textPrimary, accent: colors.accent)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .frame(height: 60)

            Button(action: openProjectManager) {
                VStack(alignment: .leading, spacing: DoitSpacing.xxs) {
                    Text(isProjectLinked
                         ? L10n.t("当前项目", "CURRENT PROJECT", language: lang)
                         : L10n.t("快速任务", "QUICK TASK", language: lang))
                        .font(DoitFont.caption)
                        .tracking(0.8)
                        .foregroundStyle(colors.textTertiary)
                    HStack(spacing: 6) {
                        Text(projectName ?? L10n.t("未关联项目", "No linked project", language: lang))
                            .font(DoitFont.bodyEmphasis)
                            .foregroundStyle(colors.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(colors.textTertiary)
                    }
                }
                .padding(.horizontal, DoitSpacing.sm)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .background(railInnerFill, in: RoundedRectangle(cornerRadius: DoitRadius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: DoitRadius.card, style: .continuous).strokeBorder(railInnerHairline, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DoitSpacing.sm)
            .padding(.bottom, DoitSpacing.md)

            if isProjectLinked {
                navigationButton(.overview)
                    .padding(.bottom, DoitSpacing.sm)
            }

            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: DoitSpacing.xxs) {
                    Text(L10n.t(group.title.0, group.title.1, language: lang))
                        .font(DoitFont.caption)
                        .tracking(1.0)
                        .foregroundStyle(colors.textTertiary)
                        .padding(.horizontal, 18)
                        .padding(.top, DoitSpacing.xs)
                        .padding(.bottom, DoitSpacing.xxs)
                    ForEach(group.sections) { section in
                        navigationButton(section)
                    }
                }
                .padding(.bottom, DoitSpacing.xs)
            }

            Spacer(minLength: DoitSpacing.sm)

            if let runningTaskLabel {
                HStack(alignment: .top, spacing: DoitSpacing.xs) {
                    ProgressView().controlSize(.small)
                    Text(runningTaskLabel)
                        .font(DoitFont.caption)
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(3)
                }
                .padding(DoitSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(railInnerFill, in: RoundedRectangle(cornerRadius: DoitRadius.control, style: .continuous))
                .padding(.horizontal, DoitSpacing.xs)
                .padding(.bottom, DoitSpacing.xs)
            }

            Button(action: launchAI) {
                Label("Mira AI", systemImage: "sparkles")
                    .font(DoitFont.bodyEmphasis)
                    .foregroundStyle(colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DoitSpacing.sm)
                    .frame(height: 40)
                    .background(railInnerFill, in: RoundedRectangle(cornerRadius: DoitRadius.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: DoitRadius.control, style: .continuous).strokeBorder(railInnerHairline, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DoitSpacing.sm)
            .padding(.bottom, DoitSpacing.sm)
        }
        .frame(width: 220)
        .liquidGlassSurface(colors: colors, cornerRadius: DoitRadius.panel)
    }

    private func navigationButton(_ section: WorkstationSection) -> some View {
        let selected = selection == section
        let hovered = hoveredSection == section
        return Button {
            selection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .frame(width: 18)
                Text(section.title(language: lang))
                    .font(selected ? DoitFont.bodyEmphasis : DoitFont.body)
                Spacer()
            }
            .foregroundStyle(selected ? colors.textPrimary : colors.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(
                selected
                    ? colors.accent.opacity(colorScheme == .dark ? 0.22 : 0.14)
                    : (hovered ? colors.textPrimary.opacity(0.05) : Color.clear),
                in: RoundedRectangle(cornerRadius: DoitRadius.control, style: .continuous)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(selected ? colors.accent : Color.clear)
                    .frame(width: 3, height: 20)
                    .padding(.leading, 1)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DoitSpacing.sm)
        .accessibilityIdentifier("workstation.section.\(section.rawValue)")
        .onHover { hovering in
            withAnimation(DoitVisual.hoverAnimation(reduceMotion: reducesMotion)) {
                hoveredSection = hovering ? section : nil
            }
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selection.title(language: lang))
                    .font(DoitFont.title2)
                    .foregroundStyle(colors.textPrimary)
                if let projectPath, isProjectLinked {
                    Text(projectPath)
                        .font(DoitFont.monoCaption)
                        .foregroundStyle(colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(L10n.t("不写入项目，可随时返回项目库", "Runs outside a project; return to the library at any time", language: lang))
                        .font(DoitFont.caption)
                        .foregroundStyle(colors.textTertiary)
                }
            }

            Spacer()

            if let runningTaskLabel {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini)
                    Text(runningTaskLabel)
                        .font(DoitFont.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, DoitSpacing.sm)
                .frame(height: 30)
                .interactiveLiquidGlassCapsule(colors: colors)
            }

            Button(action: launchAI) {
                Label("Mira AI", systemImage: "sparkles")
                    .font(DoitFont.callout)
                    .fontWeight(.semibold)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(colors.surfaceBg.opacity(0.58))
    }
}

struct WorkstationProjectOverview: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors

    let projectName: String
    let projectPath: String
    let scriptSceneCount: Int
    let storyboardSceneCount: Int
    let shootingDayCount: Int
    let takeCount: Int
    let runningTaskLabel: String?
    let continueSection: WorkstationSection
    let continueAction: () -> Void
    let openSection: (WorkstationSection) -> Void

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DoitSpacing.lg) {
                overviewHeader
                progressSection
                HStack(alignment: .top, spacing: DoitSpacing.md) {
                    nextActions
                    projectFacts
                }
            }
            .padding(.horizontal, DoitSpacing.xl)
            .padding(.vertical, DoitSpacing.xl)
            .frame(maxWidth: 1_080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background { DoitGlassBackdrop(colors: colors) }
        .accessibilityIdentifier("workstation.overview")
    }

    private var overviewHeader: some View {
        HStack(alignment: .center, spacing: DoitSpacing.lg) {
            VStack(alignment: .leading, spacing: DoitSpacing.xs) {
                Text(L10n.t("项目总览", "PROJECT OVERVIEW", language: lang))
                    .font(DoitFont.caption)
                    .tracking(1.25)
                    .foregroundStyle(colors.warm)
                Text(projectName)
                    .font(DoitFont.display)
                    .foregroundStyle(colors.textPrimary)
                Text(projectPath)
                    .font(DoitFont.monoCaption)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(action: continueAction) {
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("继续工作", "CONTINUE", language: lang))
                            .font(DoitFont.caption)
                            .tracking(0.8)
                        Text(continueSection.title(language: lang))
                            .font(DoitFont.bodyEmphasis)
                    }
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, DoitSpacing.md)
                .frame(height: 52)
                .foregroundStyle(.white)
                .background(colors.accent, in: RoundedRectangle(cornerRadius: DoitRadius.card, style: .continuous))
                .shadow(color: colors.accent.opacity(0.30), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(DoitSpacing.lg)
        .liquidGlassSurface(colors: colors, cornerRadius: DoitRadius.panel)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(L10n.t("制作进程", "Production Progress", language: lang))
            HStack(spacing: DoitSpacing.sm) {
                progressCard(.scriptWorkshop, value: "\(scriptSceneCount)", detail: L10n.t("场剧本", "script scenes", language: lang))
                progressCard(.storyboard, value: "\(storyboardSceneCount)", detail: L10n.t("场分镜", "storyboard scenes", language: lang))
                progressCard(.shootingDay, value: "\(shootingDayCount)", detail: L10n.t("个拍摄日", "shooting days", language: lang))
                progressCard(.scriptLog, value: "\(takeCount)", detail: "Take")
            }
        }
    }

    private var nextActions: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle(L10n.t("接下来", "Next", language: lang))
            actionRow(
                title: L10n.t("继续完善剧本与场景结构", "Continue shaping the script and scenes", language: lang),
                detail: L10n.t("剧本与分镜使用稳定场景身份连接", "Script and storyboard stay linked by stable scene identity", language: lang),
                section: .scriptWorkshop
            )
            actionRow(
                title: L10n.t("把镜头方案排入拍摄日", "Schedule shot plans into shooting days", language: lang),
                detail: L10n.t("分镜可同步至统筹与场记", "Storyboard data can flow into planning and script log", language: lang),
                section: .shootingDay
            )
            if let runningTaskLabel {
                actionRow(
                    title: L10n.t("查看正在运行的素材任务", "Review the active media task", language: lang),
                    detail: runningTaskLabel,
                    section: .offload
                )
            }
        }
        .padding(DoitSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .liquidGlassSurface(colors: colors, cornerRadius: DoitRadius.card)
    }

    private var projectFacts: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle(L10n.t("项目状态", "Project Status", language: lang))
            factRow(L10n.t("剧本场景", "Script Scenes", language: lang), "\(scriptSceneCount)")
            factRow(L10n.t("分镜场景", "Storyboard Scenes", language: lang), "\(storyboardSceneCount)")
            factRow(L10n.t("拍摄日", "Shooting Days", language: lang), "\(shootingDayCount)")
            factRow("Take", "\(takeCount)")
            Divider()
            Text(L10n.t(
                "所有数据保存在本地项目包中。",
                "All data stays inside the local project package.",
                language: lang
            ))
            .font(DoitFont.caption)
            .foregroundStyle(colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DoitSpacing.lg)
        .frame(width: 260, alignment: .topLeading)
        .liquidGlassSurface(colors: colors, cornerRadius: DoitRadius.card)
    }

    private func progressCard(_ section: WorkstationSection, value: String, detail: String) -> some View {
        Button { openSection(section) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: section.systemImage)
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(colors.textSecondary)
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text(detail)
                    .font(DoitFont.caption)
                    .foregroundStyle(colors.textTertiary)
            }
            .padding(DoitSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .liquidGlassSurface(colors: colors, cornerRadius: DoitRadius.card)
        }
        .buttonStyle(.plain)
    }

    private func actionRow(title: String, detail: String, section: WorkstationSection) -> some View {
        Button { openSection(section) } label: {
            HStack(spacing: DoitSpacing.sm) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(colors.inputBg.opacity(0.7), in: RoundedRectangle(cornerRadius: DoitRadius.control, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(DoitFont.bodyEmphasis)
                        .foregroundStyle(colors.textPrimary)
                    Text(detail)
                        .font(DoitFont.caption)
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(colors.textTertiary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(colors.textSecondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(colors.textPrimary)
        }
        .font(DoitFont.callout)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(DoitFont.title2)
            .foregroundStyle(colors.textPrimary)
    }
}
