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
    @Environment(\.colorScheme) private var colorScheme
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
    private var heroPrimary: Color { Color(red: 0.95, green: 0.94, blue: 0.91) }
    private var heroSecondary: Color { Color(red: 0.69, green: 0.72, blue: 0.72) }
    private var heroEyebrow: Color { Color(red: 0.72, green: 0.57, blue: 0.39) }
    private var heroBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.13, green: 0.15, blue: 0.16), Color(red: 0.08, green: 0.09, blue: 0.095)]
                : [Color(red: 0.14, green: 0.16, blue: 0.17), Color(red: 0.08, green: 0.095, blue: 0.105)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            colors.surfaceBg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    masthead

                    if let firstAccessibleProject {
                        continueCard(firstAccessibleProject)
                    }

                    recentProjectsSection
                    quickTasksSection
                }
                .padding(.horizontal, 52)
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
                WorkstationWordmark(size: 28, primary: colors.textPrimary, accent: colors.accent)
                Text(L10n.t(
                    "把一部片，从纸面推进到现场与后期",
                    "Move a film from the page to set and post",
                    language: lang
                ))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(colors.textSecondary)
            }

            Spacer()

            Button(action: launchAI) {
                Label("Mira AI", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .background(colors.inputBg, in: Capsule())
                    .overlay(Capsule().strokeBorder(colors.hairline, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .foregroundStyle(colors.textPrimary)

            Button(action: newProject) {
                Label(L10n.t("新建项目", "New Project", language: lang), systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 34)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityIdentifier("workstation.newProject")
        }
    }

    private func continueCard(_ project: RecentProject) -> some View {
        let isHovered = hoveredID == "continue"
        return Button { resumeProject(project) } label: {
            HStack(spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("继续工作", "CONTINUE WORKING", language: lang))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(heroEyebrow)
                    Text(displayName(project))
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(heroPrimary)
                    Text(project.lastOpenedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(heroSecondary)
                }
                Spacer()
                HStack(spacing: 9) {
                    Text(L10n.t("回到上次工作位置", "Return to your last workspace", language: lang))
                        .font(.system(size: 11.5, weight: .medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(heroPrimary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Color.white.opacity(isHovered ? 0.14 : 0.09), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
            }
            .padding(.horizontal, 26)
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
            .background(
                heroBackground,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isHovered ? colors.accent.opacity(0.72) : Color.white.opacity(0.09), lineWidth: 0.7)
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
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                sectionTitle(L10n.t("最近项目", "Recent Projects", language: lang))
                Spacer()
                Button(action: browseProject) {
                    Label(L10n.t("打开其他项目", "Open Another Project", language: lang), systemImage: "folder")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
            }

            if recentProjects.isEmpty {
                emptyProjects
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(recentProjects.prefix(6)) { project in
                        recentProjectCard(project)
                    }
                }
            }
        }
    }

    private var quickTasksSection: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle(L10n.t("快速任务", "Quick Tasks", language: lang))
                Spacer()
                Text(L10n.t("无需创建项目", "No project required", language: lang))
                    .font(.system(size: 10.5))
                    .foregroundStyle(colors.textTertiary)
            }

            HStack(spacing: 12) {
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
                    .frame(width: 34, height: 34)
                    .background(colors.inputBg.opacity(0.76), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName(project))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                    Text(project.url.deletingPathExtension().deletingLastPathComponent().path)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Image(systemName: project.isAccessible ? "arrow.right" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isHovered ? colors.textPrimary : colors.textTertiary)
            }
            .padding(.horizontal, 15)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(colors.panelBg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isHovered ? colors.accent.opacity(0.32) : colors.hairline, lineWidth: 0.6)
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(colors.inputBg.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(isHovered ? colors.panelBg : colors.surfaceBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colors.hairline, lineWidth: 0.6))
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
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(colors.textTertiary)
            Text(L10n.t("从一个新项目开始你的下一部片", "Start your next film with a new project", language: lang))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 112)
        .background(colors.panelBg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(colors.hairline, lineWidth: 0.6))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
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

    @Binding var selection: WorkstationSection
    let isProjectLinked: Bool
    let projectName: String?
    let projectPath: String?
    let runningTaskLabel: String?
    let goToLibrary: () -> Void
    let openProjectManager: () -> Void
    let launchAI: () -> Void
    @ViewBuilder let content: () -> Content

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private var railBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.055, green: 0.065, blue: 0.070)
            : Color(red: 0.115, green: 0.130, blue: 0.140)
    }
    private var railCard: Color { Color.white.opacity(colorScheme == .dark ? 0.065 : 0.075) }
    private var railHairline: Color { Color.white.opacity(0.10) }
    private var railPrimary: Color { Color(red: 0.94, green: 0.94, blue: 0.91) }
    private var railSecondary: Color { Color(red: 0.70, green: 0.73, blue: 0.73) }
    private var railTertiary: Color { Color(red: 0.49, green: 0.53, blue: 0.54) }
    private var railAccent: Color { Color(red: 0.54, green: 0.67, blue: 0.72) }

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
        HStack(spacing: 12) {
            navigationRail
            VStack(spacing: 0) {
                workspaceHeader
                Divider()
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.leading, 12)
        .padding(.vertical, 12)
        .background(colors.surfaceBg)
        .tint(colors.accent)
        .accentColor(colors.accent)
        .environment(\.toolAccentColor, colors.accent)
        .accessibilityIdentifier("workstation.shell")
    }

    private var navigationRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: goToLibrary) {
                HStack {
                    WorkstationWordmark(size: 16, primary: railPrimary, accent: railAccent)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .frame(height: 62)

            Button(action: openProjectManager) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isProjectLinked
                         ? L10n.t("当前项目", "CURRENT PROJECT", language: lang)
                         : L10n.t("快速任务", "QUICK TASK", language: lang))
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(railTertiary)
                    HStack(spacing: 6) {
                        Text(projectName ?? L10n.t("未关联项目", "No linked project", language: lang))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(railPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(railTertiary)
                    }
                }
                .padding(.horizontal, 13)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                .background(railCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(railHairline, lineWidth: 0.6))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.bottom, 18)

            if isProjectLinked {
                navigationButton(.overview)
                    .padding(.bottom, 12)
            }

            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t(group.title.0, group.title.1, language: lang))
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(railTertiary)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    ForEach(group.sections) { section in
                        navigationButton(section)
                    }
                }
                .padding(.bottom, 11)
            }

            Spacer(minLength: 12)

            if let runningTaskLabel {
                HStack(alignment: .top, spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(runningTaskLabel)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(railSecondary)
                        .lineLimit(3)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(railCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            Button(action: launchAI) {
                Label("Mira AI", systemImage: "sparkles")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(railPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 13)
                    .frame(height: 38)
                    .background(railCard, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(width: 184)
        .background(railBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(railHairline, lineWidth: 0.6)
        )
    }

    private func navigationButton(_ section: WorkstationSection) -> some View {
        let selected = selection == section
        return Button { selection = section } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .frame(width: 16)
                Text(section.title(language: lang))
                    .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(selected ? railPrimary : railSecondary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(selected ? Color.white.opacity(0.11) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(selected ? railAccent : Color.clear)
                    .frame(width: 3, height: 18)
                    .padding(.leading, 1)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 13)
        .accessibilityIdentifier("workstation.section.\(section.rawValue)")
    }

    private var workspaceHeader: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selection.title(language: lang))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                if let projectPath, isProjectLinked {
                    Text(projectPath)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(L10n.t("不写入项目，可随时返回项目库", "Runs outside a project; return to the library at any time", language: lang))
                        .font(.system(size: 9.5))
                        .foregroundStyle(colors.textTertiary)
                }
            }

            Spacer()

            if let runningTaskLabel {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini)
                    Text(runningTaskLabel)
                        .font(.system(size: 9.5, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(colors.inputBg.opacity(0.7), in: Capsule())
            }

            Button(action: launchAI) {
                Label("Mira AI", systemImage: "sparkles")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(colors.surfaceBg)
    }
}

struct WorkstationProjectOverview: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme

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
    private var heroBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.14, green: 0.16, blue: 0.17), Color(red: 0.08, green: 0.09, blue: 0.095)]
                : [Color(red: 0.15, green: 0.17, blue: 0.18), Color(red: 0.09, green: 0.105, blue: 0.115)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    private var heroPrimary: Color { Color(red: 0.95, green: 0.94, blue: 0.91) }
    private var heroSecondary: Color { Color(red: 0.68, green: 0.71, blue: 0.71) }
    private var heroEyebrow: Color { Color(red: 0.72, green: 0.57, blue: 0.39) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                overviewHeader
                progressSection
                HStack(alignment: .top, spacing: 16) {
                    nextActions
                    projectFacts
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 1_080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(colors.surfaceBg)
        .accessibilityIdentifier("workstation.overview")
    }

    private var overviewHeader: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("项目总览", "PROJECT OVERVIEW", language: lang))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.25)
                    .foregroundStyle(heroEyebrow)
                Text(projectName)
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(heroPrimary)
                Text(projectPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(heroSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(action: continueAction) {
                HStack(spacing: 11) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("继续工作", "CONTINUE", language: lang))
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(0.8)
                        Text(continueSection.title(language: lang))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .foregroundStyle(heroPrimary)
                .background(
                    Color(red: 0.27, green: 0.39, blue: 0.45),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(heroBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 0.6))
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(L10n.t("制作进程", "Production Progress", language: lang))
            HStack(spacing: 10) {
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(colors.panelBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(colors.hairline, lineWidth: 0.6))
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
            .font(.system(size: 9.5))
            .foregroundStyle(colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 260, alignment: .topLeading)
        .background(colors.panelBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(colors.hairline, lineWidth: 0.6))
    }

    private func progressCard(_ section: WorkstationSection, value: String, detail: String) -> some View {
        Button { openSection(section) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: section.systemImage)
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(colors.textSecondary)
                Text(value)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.textPrimary)
                Text(detail)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(colors.textTertiary)
            }
            .padding(15)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(colors.panelBg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(colors.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
    }

    private func actionRow(title: String, detail: String, section: WorkstationSection) -> some View {
        Button { openSection(section) } label: {
            HStack(spacing: 12) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(colors.inputBg.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .semibold))
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
        .font(.system(size: 10.5))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(colors.textPrimary)
    }
}
