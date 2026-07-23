import AppKit
import SwiftUI

/// The compact project chooser shown when Project Mode is selected.
/// The former long-form capability catalogue is intentionally not part of
/// this flow: choosing a project should be a quick decision, not a tour.
struct ProjectQuickPickerView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @ObservedObject var store: ScriptLogStore
    @ObservedObject var recentProjects: RecentProjectStore
    let openNewProjectOnAppear: Bool
    let enterWorkspace: (Workspace) -> Void

    @State private var isNewProjectPresented = false
    @State private var handledInitialRequest = false

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header
            HStack(spacing: 18) {
                actionCard(
                    title: L10n.t("新建项目", "New Project", language: lang),
                    subtitle: L10n.t("创建项目资料和保存位置", "Create project data and location", language: lang),
                    systemImage: "plus",
                    tint: colors.accent
                ) {
                    isNewProjectPresented = true
                }
                actionCard(
                    title: L10n.t("打开项目", "Open Project", language: lang),
                    subtitle: L10n.t("选择已有 321Doit 项目", "Choose an existing 321Doit project", language: lang),
                    systemImage: "folder",
                    tint: colors.stateSuccess
                ) {
                    openProject()
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("最近项目", "Recent Projects", language: lang))
                    .font(.system(size: 13, weight: .semibold))

                if recentProjects.projects.isEmpty {
                    Text(L10n.t("还没有最近项目", "No recent projects yet", language: lang))
                        .font(.system(size: 12))
                        .foregroundStyle(colors.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 86)
                        .background(colors.inputBg.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(recentProjects.projects.prefix(6)) { project in
                                recentRow(project)
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
            }
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 38)
        .frame(maxWidth: 1_040, alignment: .topLeading)
        .frame(minWidth: 900, minHeight: 620, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.surfaceBg)
        .sheet(isPresented: $isNewProjectPresented) {
            NewProjectSheet { name, folder in
                if store.createNewProject(name: name, folderURL: folder) {
                    recentProjects.record(
                        url: store.projectFolderURL,
                        name: LocalizedDisplay.projectName(store.project, language: lang)
                    )
                    isNewProjectPresented = false
                    enterWorkspace(.project)
                }
            }
            .environmentObject(settings)
            .environment(\.appTheme, settings.settings.general.theme)
            .tint(colors.accent)
        }
        .onAppear {
            guard openNewProjectOnAppear, !handledInitialRequest else { return }
            handledInitialRequest = true
            isNewProjectPresented = true
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            AppLogo(size: 54)
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.t("选择项目", "Choose a Project", language: lang))
                    .font(.system(size: 28, weight: .semibold))
                Text(L10n.t("新建、打开或继续最近使用的项目", "Create, open, or continue a recent project", language: lang))
                    .font(.system(size: 13))
                    .foregroundStyle(colors.textSecondary)
            }
            .layoutPriority(1)
            Spacer()
        }
    }

    private func actionCard(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 54, height: 54)
                    .background(tint)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(colors.textTertiary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(colors.panelBg)
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(colors.hairline.opacity(0.75), lineWidth: 0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func recentRow(_ project: RecentProject) -> some View {
        Button {
            guard project.isAccessible else { return }
            if store.openProject(at: project.url) {
                recentProjects.record(
                    url: store.projectFolderURL,
                    name: LocalizedDisplay.projectName(store.project, language: lang)
                )
                enterWorkspace(.project)
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: project.isAccessible ? "folder.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(project.isAccessible ? colors.accent : colors.stateWarning)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(project.path)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if project.isAccessible {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(colors.textTertiary)
                } else {
                    Text(L10n.t("不可访问", "Unavailable", language: lang))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(colors.stateWarning)
                }
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(colors.inputBg.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func openProject() {
        if store.openProject() {
            recentProjects.record(
                url: store.projectFolderURL,
                name: LocalizedDisplay.projectName(store.project, language: lang)
            )
            enterWorkspace(.project)
        }
    }
}
