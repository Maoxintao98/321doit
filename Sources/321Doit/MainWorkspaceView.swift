import AppKit
import SwiftUI

private let workspaceTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
}()

struct ContentView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @StateObject private var projectStore = ScriptLogStore()
    @StateObject private var independentScriptLogStore = ScriptLogStore(loadPersistedProject: false)
    @StateObject private var linkedOffloadModel = OffloadViewModel(persistenceID: "linked")
    @StateObject private var independentOffloadModel = OffloadViewModel(
        persistenceID: "independent",
        migrateLegacyPendingTask: true
    )
    @StateObject private var storyboardStore = StoryboardStore()
    @StateObject private var recentProjects = RecentProjectStore()
    @State private var isSupportPresented = false
    @State private var activeTool: ToolIdentifier?
    @State private var associationMode: ToolAssociationMode = .linkedProject
    @State private var isIndependentModeAlertPresented = false
    @State private var shootingDayNavigation: Workspace = .shootingDay
    @State private var didInitializeIndependentWorkspace = false

    private var linkedProjectName: String? {
        guard projectStore.projectFolderURL != nil else { return nil }
        let name = LocalizedDisplay.projectName(projectStore.project, language: settings.settings.general.language)
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized != "Untitled", normalized != "未命名项目" else { return nil }
        return name
    }

    private var activeOffloadModel: OffloadViewModel {
        associationMode == .linkedProject ? linkedOffloadModel : independentOffloadModel
    }

    var body: some View {
        Group {
            switch activeTool {
            case .storyboard:
                ToolShell(
                    title: L10n.t("灵动分镜", "Living Storyboard", language: settings.settings.general.language),
                    tool: .storyboard,
                    associationMode: associationMode,
                    projectName: linkedProjectName,
                    goHome: { activeTool = nil },
                    openProjectManager: { showProjectManagerWindow() }
                ) {
                    StoryboardWorkspaceView(
                        store: storyboardStore,
                        workflowStore: associationMode == .linkedProject ? projectStore : independentScriptLogStore
                    )
                }
            case .offload:
                ToolShell(
                    title: L10n.t("极速拷卡", "Turbo Offload", language: settings.settings.general.language),
                    tool: .offload,
                    associationMode: associationMode,
                    projectName: linkedProjectName,
                    goHome: { activeTool = nil },
                    openProjectManager: { showProjectManagerWindow() }
                ) {
                    OffloadView(model: activeOffloadModel)
                }
            case .scriptLog:
                ToolShell(
                    title: L10n.t("迅捷场记", "Rapid Script Log", language: settings.settings.general.language),
                    tool: .scriptLog,
                    associationMode: associationMode,
                    projectName: linkedProjectName,
                    goHome: { activeTool = nil },
                    openProjectManager: { showProjectManagerWindow() }
                ) {
                    if associationMode == .linkedProject {
                        ScriptLogView(store: projectStore)
                    } else {
                        ScriptLogView(store: independentScriptLogStore)
                    }
                }
            case .shootingDay:
                ToolShell(
                    title: L10n.t("拍摄统筹", "Production Planning", language: settings.settings.general.language),
                    tool: .shootingDay,
                    associationMode: associationMode,
                    projectName: linkedProjectName,
                    goHome: { activeTool = nil },
                    openProjectManager: { showProjectManagerWindow() }
                ) {
                    ShootingDayWorkspaceView(
                        store: associationMode == .linkedProject ? projectStore : independentScriptLogStore,
                        selection: $shootingDayNavigation
                    )
                }
            case .mediaConverter:
                ToolShell(
                    title: L10n.t("媒体转换", "Media Conversion", language: settings.settings.general.language),
                    tool: .mediaConverter,
                    associationMode: associationMode,
                    projectName: linkedProjectName,
                    goHome: { activeTool = nil },
                    openProjectManager: { showProjectManagerWindow() }
                ) {
                    MediaConverterView(
                        associationMode: associationMode,
                        projectID: associationMode == .linkedProject ? projectStore.project.id : nil,
                        projectName: linkedProjectName,
                        projectFolderURL: associationMode == .linkedProject ? projectStore.projectFolderURL : nil,
                        configuredFFmpegPath: settings.settings.transcode.ffmpegPath
                    )
                }
            case nil:
                ToolHubView(
                    runningTaskLabel: runningTaskLabel,
                    associationMode: associationMode,
                    selectMode: { selectAssociationMode($0) },
                    launchAI: { showMiraWindow() },
                    openProject: { openGlobalProject() },
                    showIndependentModeAlert: { isIndependentModeAlertPresented = true },
                    launch: { launchFromHub($0) }
                )
            }
        }
        .sheet(isPresented: $isSupportPresented) {
            SupportView()
                .environmentObject(settings)
                .environment(\.appTheme, settings.settings.general.theme)
                .tint(colors.accent)
        }
        .alert(L10n.t("请关闭独立模式", "Turn Off Independent Mode", language: settings.settings.general.language), isPresented: $isIndependentModeAlertPresented) {
            Button(L10n.t("好", "OK", language: settings.settings.general.language), role: .cancel) {}
        } message: {
            Text(L10n.t(
                "打开项目需要使用项目工作流。请先取消“不使用项目 · 独立使用工具”。",
                "Opening a project requires the project workflow. Turn off “Don't use a project · Open tools independently” first.",
                language: settings.settings.general.language
            ))
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.contactSupport.notificationName)) { _ in
            isSupportPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.showProjectManager.notificationName)) { _ in
            showProjectManagerWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.newProject.notificationName)) { _ in
            showProjectManagerWindow(openNewProjectSheet: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.openProject.notificationName)) { _ in
            openGlobalProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .open321DoitProject)) { notification in
            guard let url = notification.object as? URL else { return }
            handleProjectURL(url)
            _ = AppLifecycleDelegate.current?.consumePendingProjectURL()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.openProjectFolder.notificationName)) { _ in
            NSWorkspace.shared.open(projectStore.projectFolderURL ?? projectStore.storageDirectoryURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.saveProject.notificationName)) { _ in
            guard activeTool == .scriptLog else { return }
            let store = associationMode == .linkedProject ? projectStore : independentScriptLogStore
            if store.projectFolderURL == nil {
                _ = store.chooseProjectFolder()
            } else {
                store.save()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.previousTake.notificationName)) { _ in
            guard activeTool == .scriptLog else { return }
            (associationMode == .linkedProject ? projectStore : independentScriptLogStore).navigateTake(offset: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.nextTake.notificationName)) { _ in
            guard activeTool == .scriptLog else { return }
            (associationMode == .linkedProject ? projectStore : independentScriptLogStore).navigateTake(offset: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.previousScene.notificationName)) { _ in
            guard activeTool == .scriptLog else { return }
            (associationMode == .linkedProject ? projectStore : independentScriptLogStore).navigateShot(offset: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.nextScene.notificationName)) { _ in
            guard activeTool == .scriptLog else { return }
            (associationMode == .linkedProject ? projectStore : independentScriptLogStore).navigateShot(offset: 1)
        }
        .onChange(of: shootingDayNavigation) { workspace in
            guard activeTool == .shootingDay else { return }
            switch workspace {
            case .scriptLog:
                activeTool = .scriptLog
            case .offload:
                launch(.offload, mode: associationMode)
            case .project:
                showProjectManagerWindow()
            case .shootingDay:
                break
            case .handoff, .reports:
                launch(.offload, mode: associationMode)
            }
            shootingDayNavigation = .shootingDay
        }
        .onChange(of: associationMode) { mode in
            AppLifecycleDelegate.current?.setIndependentModeActive(mode == .independent)
        }
        .onReceive(NotificationCenter.default.publisher(for: .miraProjectDataDidChange)) { notification in
            handleMiraProjectDataChange(notification)
        }
        .onAppear {
            initializeIndependentWorkspaceLifecycle()
            if let pendingURL = AppLifecycleDelegate.current?.consumePendingProjectURL() {
                handleProjectURL(pendingURL)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            settings.saveNow()
            if projectStore.hasUnsavedChanges { projectStore.save() }
            AppLogger.log(.info, category: "lifecycle", "Flushed pending settings and project changes before termination")
        }
    }

    private func selectAssociationMode(_ mode: ToolAssociationMode) {
        associationMode = mode
    }

    private func showMiraWindow() {
        if projectStore.hasUnsavedChanges {
            projectStore.save()
        }
        // First-run setup must lead with the user's own model service. Full
        // Disk Access is optional: without it Mira can still use locations
        // explicitly authorized in its sidebar after configuration.
        guard OpenCodeBridge.hasUserConfiguredService() else {
            MiraWindowPresenter.shared.show(
                settings: settings,
                projectContext: nil
            )
            return
        }
        guard prepareMiraDiskAccess() else { return }
        MiraWindowPresenter.shared.show(
            settings: settings,
            projectContext: nil
        )
    }

    private func prepareMiraDiskAccess() -> Bool {
        let diskRoot = URL(fileURLWithPath: "/", isDirectory: true)
        if MiraAuthorizedRoots.all().contains(where: { $0.standardizedFileURL.path == diskRoot.path }) {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.icon = NSApp.applicationIconImage
        alert.messageText = L10n.t(
            "Mira 需要完全磁盘访问权限",
            "Mira Needs Full Disk Access",
            language: settings.settings.general.language
        )
        alert.informativeText = L10n.t(
            "点击“打开系统设置”，在“隐私与安全性 → 完全磁盘访问权限”中添加并启用 321Doit。完成后回到 321Doit，再次选择 Mira AI。若暂不授权，Mira 仍可打开，但只能访问你之后在侧栏单独授权的位置。",
            "Open System Settings, then add and enable 321Doit under Privacy & Security → Full Disk Access. Return to 321Doit and select Mira AI again. If you continue without it, Mira opens but can access only locations you authorize separately in its sidebar.",
            language: settings.settings.general.language
        )
        alert.addButton(withTitle: L10n.t(
            "打开系统设置",
            "Open System Settings",
            language: settings.settings.general.language
        ))
        alert.addButton(withTitle: L10n.t(
            "暂不授权",
            "Not Now",
            language: settings.settings.general.language
        ))

        guard alert.runModal() == .alertFirstButtonReturn else { return true }
        MiraAuthorizedRoots.add(diskRoot)
        guard let privacyURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return false }
        NSWorkspace.shared.open(privacyURL)
        return false
    }

    private func handleMiraProjectDataChange(_ notification: Notification) {
        if let change = notification.object as? MiraProjectDataChange {
            let changedPath = URL(fileURLWithPath: change.projectPath).standardizedFileURL.path

            if change.action == "created",
               let created = try? ProjectRepository.load(from: URL(fileURLWithPath: changedPath)) {
                recentProjects.record(url: URL(fileURLWithPath: changedPath), name: created.name)
            }

            if change.action == "trashed" {
                if let recent = recentProjects.projects.first(where: {
                    $0.url.standardizedFileURL.path == changedPath
                }) {
                    recentProjects.remove(recent)
                }
                if projectStore.projectFolderURL?.standardizedFileURL.path == changedPath {
                    _ = projectStore.newProject()
                    associationMode = .independent
                    activeTool = nil
                }
                return
            }

            guard associationMode == .linkedProject,
                  projectStore.projectFolderURL?.standardizedFileURL.path == changedPath,
                  !projectStore.hasUnsavedChanges else { return }
            projectStore.reload()
            storyboardStore.reload()
            recentProjects.record(
                url: projectStore.projectFolderURL,
                name: LocalizedDisplay.projectName(projectStore.project, language: settings.settings.general.language)
            )
            return
        }

        // Compatibility with older project-bound Mira notifications.
        guard associationMode == .linkedProject,
              let projectID = notification.object as? UUID,
              projectID == projectStore.project.id,
              !projectStore.hasUnsavedChanges else { return }
        projectStore.reload()
        storyboardStore.reload()
    }

    private func launchFromHub(_ tool: ToolIdentifier) {
        if associationMode == .linkedProject {
            showProjectManagerWindow(
                selectLinkedModeAfterSelection: true,
                launchAfterSelection: tool
            )
            return
        }
        launch(tool, mode: associationMode)
    }

    private var runningTaskLabel: String? {
        if linkedOffloadModel.isRunning {
            return linkedOffloadModel.snapshot.message
        }
        if independentOffloadModel.isRunning {
            return independentOffloadModel.snapshot.message
        }
        return nil
    }

    private func launch(_ tool: ToolIdentifier, mode: ToolAssociationMode) {
        associationMode = mode
        if tool == .storyboard {
            storyboardStore.configure(
                linkedProjectID: mode == .linkedProject ? projectStore.project.id : nil,
                projectFolderURL: mode == .linkedProject
                    ? projectStore.projectFolderURL
                    : (IndependentWorkspacePersistence.shouldRestore
                        ? IndependentWorkspacePersistence.restoreProjectURL
                        : nil),
                title: mode == .linkedProject ? linkedProjectName : nil
            )
        }
        if tool == .shootingDay {
            shootingDayNavigation = .shootingDay
        }
        if tool == .offload {
            let model = mode == .linkedProject ? linkedOffloadModel : independentOffloadModel
            model.onOffloadSucceeded = nil
            model.projectAssociationMode = mode == .linkedProject ? .linkedProject : .independent
            model.linkedProjectID = mode == .linkedProject ? projectStore.project.id : nil
            if mode == .linkedProject {
                syncOffloadContext(model)
            }
        }
        activeTool = tool
    }

    private func syncOffloadContext(_ model: OffloadViewModel) {
        guard !model.isRunning else { return }
        let name = projectStore.project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name != "Untitled", name != "未命名项目" {
            model.projectName = projectStore.project.name
        }
        model.operatorName = projectStore.project.ditName
        model.cameraRegistry = projectStore.project.cameraRegistry
        if model.camera.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.camera = projectStore.project.cameraRegistry.first?.label ?? ""
        }
        if model.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.cardNumber = projectStore.project.cameraRegistry.flatMap(\.cardNames).first ?? ""
        }
    }

    private func openGlobalProject() {
        if projectStore.openProject() {
            associationMode = .linkedProject
            recentProjects.record(
                url: projectStore.projectFolderURL,
                name: LocalizedDisplay.projectName(projectStore.project, language: settings.settings.general.language)
            )
        }
    }

    private func initializeIndependentWorkspaceLifecycle() {
        if !didInitializeIndependentWorkspace {
            didInitializeIndependentWorkspace = true
            if IndependentWorkspacePersistence.shouldRestore {
                _ = independentScriptLogStore.restoreIndependentWorkspace(
                    from: IndependentWorkspacePersistence.restoreProjectURL
                )
            }
        }

        AppLifecycleDelegate.current?.configureIndependentWorkspaceLifecycle(
            isActive: associationMode == .independent,
            retainForUpdate: {
                let destination = independentScriptLogStore.projectFolderURL
                    ?? IndependentWorkspacePersistence.projectFolderURL
                try independentScriptLogStore.persistIndependentWorkspace(
                    to: destination
                )
                try storyboardStore.saveCopy(toProjectFolder: destination)
                IndependentWorkspacePersistence.markForRestore(at: destination)
            },
            saveAsProject: {
                guard independentScriptLogStore.chooseProjectFolder(),
                      let destination = independentScriptLogStore.projectFolderURL else {
                    return false
                }
                try storyboardStore.saveCopy(toProjectFolder: destination)
                IndependentWorkspacePersistence.markForRestore(at: destination)
                return true
            },
            discard: {
                try IndependentWorkspacePersistence.discardPersistedData()
                independentScriptLogStore.resetIndependentWorkspaceInMemory()
            }
        )
    }

    private func handleProjectURL(_ url: URL) {
        guard projectStore.openProject(at: url) else {
            projectStore.alertMessage = L10n.t(
                "无法打开：这不是有效的 321Doit 工程文件。",
                "Could not open this file because it is not a valid 321Doit project.",
                language: settings.settings.general.language
            )
            return
        }
        associationMode = .linkedProject
        activeTool = nil
        recentProjects.record(
            url: projectStore.projectFolderURL,
            name: LocalizedDisplay.projectName(projectStore.project, language: settings.settings.general.language)
        )
        AppLogger.log(.info, category: "project", "Opened project from Finder: \(url.lastPathComponent)")
    }

    private func showProjectManagerWindow(
        openNewProjectSheet: Bool = false,
        selectLinkedModeAfterSelection: Bool = false,
        launchAfterSelection: ToolIdentifier? = nil
    ) {
        ProjectManagerWindowPresenter.shared.show(
            settings: settings,
            store: projectStore,
            recentProjects: recentProjects,
            openNewProjectSheet: openNewProjectSheet,
            enterWorkspace: { _ in
                if selectLinkedModeAfterSelection {
                    associationMode = .linkedProject
                }
                if let launchAfterSelection {
                    launch(launchAfterSelection, mode: .linkedProject)
                }
            },
            showSupport: {
                isSupportPresented = true
            }
        )
    }
}

struct GlobalBrandBar: View {
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: 10) {
            AppLogo(size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("321Doit")
                    .font(.system(size: 15, weight: .semibold))
                Text("STORYBOARD · PLAN · LOG · OFFLOAD · CONVERT")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(colors.panelBg)
    }
}

struct MainWorkspaceView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @Binding var selectedWorkspace: Workspace
    @ObservedObject var scriptLogStore: ScriptLogStore
    @ObservedObject var offloadModel: OffloadViewModel
    let showProjectManager: () -> Void

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(spacing: 0) {
            AppTopBar(
                selection: $selectedWorkspace,
                store: scriptLogStore,
                showProjectManager: showProjectManager,
                openProject: {
                    selectedWorkspace = .project
                    _ = scriptLogStore.openProject()
                },
                saveAs: {
                    selectedWorkspace = .project
                    _ = scriptLogStore.chooseProjectFolder()
                },
                save: {
                    scriptLogStore.save()
                }
            )
            Divider()

            Group {
                switch selectedWorkspace {
                case .offload:
                OffloadView(model: offloadModel)
                case .project:
                ProjectView(store: scriptLogStore)
                case .shootingDay:
                ShootingDayWorkspaceView(store: scriptLogStore, selection: $selectedWorkspace)
                case .scriptLog:
                ScriptLogView(store: scriptLogStore)
                case .handoff:
                HandoffWorkspaceView(selection: $selectedWorkspace, model: offloadModel)
                case .reports:
                ReportsWorkspaceView(selection: $selectedWorkspace, store: scriptLogStore)
                }
            }
        }
        .frame(minWidth: 1360, minHeight: 820)
        .background(colors.surfaceBg)
        .onMoveCommand { direction in
            guard selectedWorkspace == .scriptLog else { return }
            switch direction {
            case .left:
                scriptLogStore.navigateTake(offset: -1)
            case .right:
                scriptLogStore.navigateTake(offset: 1)
            case .up:
                scriptLogStore.navigateShot(offset: -1)
            case .down:
                scriptLogStore.navigateShot(offset: 1)
            @unknown default:
                break
            }
        }
        .alert("321Doit Script Log", isPresented: Binding(
            get: { scriptLogStore.alertMessage != nil },
            set: { if !$0 { scriptLogStore.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { scriptLogStore.alertMessage = nil }
        } message: {
            Text(scriptLogStore.alertMessage ?? "")
        }
        .onChange(of: scriptLogStore.project.name) { newName in
            if !newName.isEmpty && newName != "Untitled" && newName != "未命名项目" {
                offloadModel.projectName = newName
            }
        }
        .onChange(of: scriptLogStore.project.ditName) { ditName in
            offloadModel.operatorName = ditName
        }
        .onChange(of: scriptLogStore.project.cameraRegistry) { registry in
            offloadModel.cameraRegistry = registry
            if offloadModel.camera.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                offloadModel.camera = registry.first?.label ?? ""
            }
            if offloadModel.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                offloadModel.cardNumber = registry.flatMap(\.cardNames).first ?? ""
            }
        }
        .onChange(of: selectedWorkspace) { workspace in
            guard workspace == .offload else { return }
            syncOffloadContextFromProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.newProject.notificationName)) { _ in
            selectedWorkspace = .project
            _ = scriptLogStore.newProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.openProject.notificationName)) { _ in
            selectedWorkspace = .project
            _ = scriptLogStore.openProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.openProjectFolder.notificationName)) { _ in
            NSWorkspace.shared.open(scriptLogStore.projectFolderURL ?? scriptLogStore.storageDirectoryURL)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.saveProject.notificationName)) { _ in
            guard selectedWorkspace == .project || selectedWorkspace == .shootingDay || selectedWorkspace == .scriptLog else { return }
            scriptLogStore.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.previousTake.notificationName)) { _ in
            guard selectedWorkspace == .scriptLog else { return }
            scriptLogStore.navigateTake(offset: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.nextTake.notificationName)) { _ in
            guard selectedWorkspace == .scriptLog else { return }
            scriptLogStore.navigateTake(offset: 1)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.previousScene.notificationName)) { _ in
            guard selectedWorkspace == .scriptLog else { return }
            scriptLogStore.navigateShot(offset: -1)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.nextScene.notificationName)) { _ in
            guard selectedWorkspace == .scriptLog else { return }
            scriptLogStore.navigateShot(offset: 1)
        }
        .onChange(of: settings.settings.general.language) { newLanguage in
            scriptLogStore.language = newLanguage
        }
        .onAppear {
            scriptLogStore.language = settings.settings.general.language
            if !scriptLogStore.project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               scriptLogStore.project.name != "Untitled" && scriptLogStore.project.name != "未命名项目" {
                offloadModel.projectName = scriptLogStore.project.name
            }
            offloadModel.operatorName = scriptLogStore.project.ditName
            offloadModel.cameraRegistry = scriptLogStore.project.cameraRegistry
            if offloadModel.camera.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                offloadModel.camera = scriptLogStore.project.cameraRegistry.first?.label ?? ""
            }
            if offloadModel.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                offloadModel.cardNumber = scriptLogStore.project.cameraRegistry.flatMap(\.cardNames).first ?? ""
            }
            syncOffloadContextFromProject()
            // During 拷盘, copy the current script log into each destination's
            // `_ScriptLog` folder once the offload succeeds. Both stores live for
            // the app's lifetime, so a strong capture is fine here.
            offloadModel.onOffloadSucceeded = { roots in
                scriptLogStore.copyScriptLog(toTargetRoots: roots)
            }
        }
        .background {
            let undo = settings.settings.shortcuts.undo
            Button("", action: scriptLogStore.undoLastChange)
                .keyboardShortcut(undo.key.keyEquivalent, modifiers: undo.modifiers)
                .opacity(0)
        }
    }

    private func syncOffloadContextFromProject() {
        guard !offloadModel.isRunning else { return }

        let projectName = scriptLogStore.project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !projectName.isEmpty, projectName != "Untitled", projectName != "未命名项目" {
            offloadModel.projectName = scriptLogStore.project.name
        }

        offloadModel.cameraRegistry = scriptLogStore.project.cameraRegistry
        if offloadModel.operatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            offloadModel.operatorName = scriptLogStore.project.ditName
        }
        if offloadModel.camera.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            offloadModel.camera = scriptLogStore.project.cameraRegistry.first?.label ?? ""
        }
        if offloadModel.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            offloadModel.cardNumber = scriptLogStore.project.cameraRegistry.flatMap(\.cardNames).first ?? ""
        }

        guard let day = scriptLogStore.currentShootingDay else { return }
        let location = firstNonEmpty([
            day.callSheet.mainLocation,
            day.callSheet.locationInfo.shootingLocation,
            day.callSheet.locationInfo.meetingPoint,
            day.callSheet.scenePlans.first?.location ?? ""
        ])
        if !location.isEmpty {
            offloadModel.location = location
        }
        if day.callSheet.ditPlan.shouldGenerateHandoffPackage {
            offloadModel.editorialDeliveryPackage = true
        }
    }

    private func firstNonEmpty(_ values: [String]) -> String {
        values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
    }

    private var workspaceBar: some View {
        HStack(alignment: .center, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                WorkspaceSwitcher(selection: $selectedWorkspace, language: lang)
                    .padding(.horizontal, 2)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(selectedWorkspace.title(language: lang))
                    .font(.system(size: 13, weight: .semibold))
                Text(selectedWorkspace.subtitle(language: lang))
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 18)
        .background(colors.panelBg)
    }
}

struct AppTopBar: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @Binding var selection: Workspace
    @ObservedObject var store: ScriptLogStore
    let showProjectManager: () -> Void
    let openProject: () -> Void
    let saveAs: () -> Void
    let save: () -> Void

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                AppLogo(size: 22)
                    .accessibilityLabel("321Doit")
                WorkspaceSwitcher(selection: $selection, language: lang)
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 7)
            .padding(.bottom, 6)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selection.title(language: lang))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(projectSummary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                    Text(store.storageDirectoryURL.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 18)

                HStack(spacing: 8) {
                    if selection == .scriptLog {
                        Button {
                            store.isInspectorVisible.toggle()
                        } label: {
                            Label(L10n.t("检查器", "Inspector", language: lang), systemImage: store.isInspectorVisible ? "sidebar.right" : "sidebar.trailing")
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                    }

                    Button(action: openProject) {
                        Text(L10n.t("打开项目", "Open Project", language: lang))
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)

                    Button(action: saveAs) {
                        Text(L10n.t("另存为", "Save As", language: lang))
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)

                    Button(action: save) {
                        Text(L10n.t("保存", "Save", language: lang))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 7)
            .padding(.bottom, 9)
        }
        .background(colors.panelBg)
    }

    private var projectSummary: String {
        [
            LocalizedDisplay.projectName(store.project, language: lang),
            L10n.t("\(store.project.shootingDays.count)拍摄日", "\(store.project.shootingDays.count) shooting day(s)", language: lang),
            L10n.t("\(store.takeCount)条", "\(store.takeCount) takes", language: lang),
            saveState
        ].joined(separator: " · ")
    }

    private var saveState: String {
        if store.hasUnsavedChanges {
            return L10n.t("未保存", "Unsaved", language: lang)
        }
        if let saved = store.lastSavedAt {
            return "\(L10n.t("已保存", "Saved", language: lang)) \(workspaceTimeFormatter.string(from: saved))"
        }
        return L10n.t("未保存", "Not Saved", language: lang)
    }
}

struct ProjectHeader: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @ObservedObject var store: ScriptLogStore
    var isScriptLog: Bool

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedDisplay.projectName(store.project, language: lang))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(store.storageDirectoryURL.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            if store.hasUnsavedChanges {
                if !isScriptLog {
                    Text(L10n.t("未保存", "Unsaved", language: lang))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(colors.stateWarning)
                }
            } else if let saved = store.lastSavedAt {
                if !isScriptLog {
                    Text("\(L10n.t("已保存", "Saved", language: lang)) \(workspaceTimeFormatter.string(from: saved))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                }
            }
            Spacer()
            if isScriptLog {
                Button {
                    store.isInspectorVisible.toggle()
                } label: {
                    Label(L10n.t("检查器", "Inspector", language: lang), systemImage: store.isInspectorVisible ? "sidebar.right" : "sidebar.trailing")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(colors.surfaceBg)
    }
}

struct ProjectView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @ObservedObject var store: ScriptLogStore
    @State private var showProjectPaths = false

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                projectInfoPanel
                principalCastPanel
                departmentContactsPanel
                cameraRegistryPanel
                projectPathsPanel
            }
            .padding(22)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(colors.surfaceBg)
    }

    private var projectInfoPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Label(L10n.t("项目基本信息", "Project Info", language: lang), systemImage: "folder")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(store.project.shootingDays.count) \(L10n.t("拍摄日", "shooting day(s)", language: lang)) · \(store.takeCount) \(L10n.t("条", "takes", language: lang))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 260), spacing: 14),
                    GridItem(.flexible(minimum: 260), spacing: 14)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                projectField(L10n.t("项目名", "Project Name", language: lang), text: Binding(
                    get: { store.project.name },
                    set: store.setProjectName
                ))
                projectField(L10n.t("导演", "Director", language: lang), text: Binding(
                    get: { store.project.director },
                    set: store.setDirector
                ))
                projectField(L10n.t("摄影指导", "DP", language: lang), text: Binding(
                    get: { store.project.dp },
                    set: store.setDP
                ))
                projectField("DIT", text: Binding(
                    get: { store.project.ditName },
                    set: store.setDITName
                ))
                projectField(L10n.t("场记", "Script Supervisor", language: lang), text: Binding(
                    get: { store.project.scriptSupervisor },
                    set: store.setScriptSupervisor
                ))
                cameraCountField
            }
        }
        .workspaceCard(colors: colors)
    }

    private var cameraCountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("机位数量", "Camera Count", language: lang))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            Stepper(value: Binding(
                get: { store.project.cameraRegistry.count },
                set: store.setCameraCount
            ), in: 1...12) {
                Text("\(store.project.cameraRegistry.count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .frame(minWidth: 32, alignment: .leading)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.inputBg)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(colors.hairline, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var principalCastPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.t("主要角色与演员", "Principal Cast", language: lang), systemImage: "person.text.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: store.addPrincipalCastMember) {
                    Label(L10n.t("新增角色", "Add Cast", language: lang), systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.accent)
                .controlSize(.small)
            }

            if store.project.principalCast.isEmpty {
                Text(L10n.t("暂无主要角色", "No principal cast", language: lang))
                    .font(.system(size: 11))
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(colors.inputBg)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(colors.hairline, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        registryHeader(L10n.t("演员", "Performer", language: lang), width: 180)
                        registryHeader(L10n.t("角色", "Character", language: lang), width: 180)
                        registryHeader(L10n.t("电话", "Phone", language: lang), width: 160)
                        registryHeader(L10n.t("备注", "Note", language: lang), width: 220)
                        registryHeader(L10n.t("操作", "Actions", language: lang), width: 80)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 7)

                    Divider()

                    ForEach(Array(store.project.principalCast.enumerated()), id: \.element.id) { index, cast in
                        PrincipalCastRow(cast: cast, store: store)
                            .padding(.vertical, 9)
                        if index < store.project.principalCast.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .workspaceCard(colors: colors)
    }

    private var cameraRegistryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.t("机位与卡号配置", "Camera Registry", language: lang), systemImage: "camera.aperture")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: store.addRegisteredCamera) {
                    Label(L10n.t("新增机位", "Add Camera", language: lang), systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.accent)
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    registryHeader(L10n.t("机位", "Camera", language: lang), width: 120)
                    registryHeader(L10n.t("卡号", "Card", language: lang), width: 360)
                    registryHeader(L10n.t("下一素材号", "Next Clip ID", language: lang), width: 210)
                    registryHeader(L10n.t("操作", "Actions", language: lang), width: 92)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 7)

                Divider()

                ForEach(Array(store.project.cameraRegistry.enumerated()), id: \.element.id) { index, camera in
                    RegisteredCameraRow(camera: camera, store: store)
                        .padding(.vertical, 9)
                    if index < store.project.cameraRegistry.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .workspaceCard(colors: colors)
    }

    private var departmentContactsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L10n.t("部门联系单", "Department Contacts", language: lang), systemImage: "person.crop.rectangle.stack")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: store.addDepartmentContact) {
                    Label(L10n.t("新增部门", "Add Department", language: lang), systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.accent)
                .controlSize(.small)
            }

            if store.project.departmentContacts.isEmpty {
                Text(L10n.t("暂无部门联系人。", "No department contacts yet.", language: lang))
                    .font(.system(size: 11))
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(colors.inputBg)
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(colors.hairline, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        registryHeader(L10n.t("部门", "Department", language: lang), width: 170)
                        registryHeader(L10n.t("负责人", "Lead", language: lang), width: 180)
                        registryHeader(L10n.t("电话", "Phone", language: lang), width: 160)
                        registryHeader(L10n.t("备注", "Note", language: lang), width: 220)
                        registryHeader(L10n.t("操作", "Actions", language: lang), width: 80)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 7)

                    Divider()

                    ForEach(Array(store.project.departmentContacts.enumerated()), id: \.element.id) { index, contact in
                        DepartmentContactRow(contact: contact, store: store)
                            .padding(.vertical, 9)
                        if index < store.project.departmentContacts.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .workspaceCard(colors: colors)
    }

    private var projectPathsPanel: some View {
        DisclosureGroup(isExpanded: $showProjectPaths) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 10) {
                    Text(L10n.t("当前项目路径", "Current Project Path", language: lang))
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 150, alignment: .leading)
                    Text(store.storageDirectoryURL.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(colors.inputBg)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(colors.hairline, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button(L10n.t("显示", "Reveal", language: lang)) {
                        NSWorkspace.shared.activateFileViewerSelecting([store.storageDirectoryURL])
                    }
                    .controlSize(.small)
                }

                ProjectPathRow(title: L10n.t("默认项目根目录", "Default Project Root", language: lang), path: $settings.settings.general.defaultProjectRoot, lang: lang)
            }
            .padding(.top, 12)
        } label: {
            Label(L10n.t("项目文件与输出位置", "Project Files & Outputs", language: lang), systemImage: "folder")
                .font(.system(size: 13, weight: .semibold))
        }
        .workspaceCard(colors: colors)
    }

    private func registryHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(colors.textSecondary)
            .frame(width: width, alignment: .leading)
    }

    private func projectField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .padding(9)
                .background(colors.inputBg)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(colors.hairline, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct PrincipalCastRow: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    let cast: PrincipalCastMember
    @ObservedObject var store: ScriptLogStore

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            registryField(L10n.t("演员", "Performer", language: lang), width: 180, text: Binding(
                get: { cast.performerName },
                set: { value in store.updatePrincipalCastMember(id: cast.id) { $0.performerName = value } }
            ))
            registryField(L10n.t("角色", "Character", language: lang), width: 180, text: Binding(
                get: { cast.characterName },
                set: { value in store.updatePrincipalCastMember(id: cast.id) { $0.characterName = value } }
            ))
            registryField(L10n.t("电话", "Phone", language: lang), width: 160, text: Binding(
                get: { cast.phone },
                set: { value in store.updatePrincipalCastMember(id: cast.id) { $0.phone = value } }
            ))
            registryField(L10n.t("备注", "Note", language: lang), width: 220, text: Binding(
                get: { cast.note },
                set: { value in store.updatePrincipalCastMember(id: cast.id) { $0.note = value } }
            ))

            Button(role: .destructive) {
                store.removePrincipalCastMember(id: cast.id)
            } label: {
                Label(L10n.t("删除", "Delete", language: lang), systemImage: "trash")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(colors.textSecondary)
            .frame(width: 80, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }

    private func registryField(_ title: String, width: CGFloat, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(width: width)
            .background(colors.inputBg)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(colors.hairline, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct DepartmentContactRow: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    let contact: DepartmentContact
    @ObservedObject var store: ScriptLogStore

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            departmentField
                .frame(width: 170, alignment: .leading)
            registryField(L10n.t("负责人", "Lead", language: lang), width: 180, text: Binding(
                get: { contact.leadName },
                set: { value in store.updateDepartmentContact(id: contact.id) { $0.leadName = value } }
            ))
            registryField(L10n.t("电话", "Phone", language: lang), width: 160, text: Binding(
                get: { contact.phone },
                set: { value in store.updateDepartmentContact(id: contact.id) { $0.phone = value } }
            ))
            registryField(L10n.t("备注", "Note", language: lang), width: 220, text: Binding(
                get: { contact.note },
                set: { value in store.updateDepartmentContact(id: contact.id) { $0.note = value } }
            ))

            Button(role: .destructive) {
                store.removeDepartmentContact(id: contact.id)
            } label: {
                Label(L10n.t("删除", "Delete", language: lang), systemImage: "trash")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(colors.textSecondary)
            .frame(width: 80, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }

    private var departmentField: some View {
        HStack(spacing: 4) {
            registryField(L10n.t("部门", "Department", language: lang), width: 136, text: Binding(
                get: { contact.departmentName },
                set: { value in store.updateDepartmentContact(id: contact.id) { $0.departmentName = value } }
            ))
            Menu {
                ForEach(ScriptLogStore.defaultDepartmentNames(language: settings.settings.general.language), id: \.self) { name in
                    Button(name) {
                        store.updateDepartmentContact(id: contact.id) { $0.departmentName = name }
                    }
                }
            } label: {
                Image(systemName: "chevron.down.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(colors.accent)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L10n.t("选择部门", "Choose department", language: lang))
        }
    }

    private func registryField(_ title: String, width: CGFloat, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(width: width)
            .background(colors.inputBg)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(colors.hairline, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct RegisteredCameraRow: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    let camera: RegisteredCamera
    @ObservedObject var store: ScriptLogStore

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            registryField(L10n.t("机位", "Camera", language: lang), width: 88, text: Binding(
                get: { camera.label },
                set: { value in store.updateRegisteredCamera(id: camera.id) { $0.label = value } }
            ))
            .frame(width: 120, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(camera.cardNames.enumerated()), id: \.offset) { index, _ in
                    HStack(spacing: 6) {
                        registryField(index == 0 ? "A01" : L10n.t("请输入卡号", "Enter Card", language: lang), width: 280, text: Binding(
                            get: { camera.cardNames.indices.contains(index) ? camera.cardNames[index] : "" },
                            set: { value in store.updateRegisteredCameraCard(cameraID: camera.id, cardIndex: index, value: value) }
                        ))
                        Button {
                            store.removeCard(from: camera.id, cardIndex: index)
                        } label: {
                            Image(systemName: "minus.circle")
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(colors.textSecondary)
                        .disabled(camera.cardNames.count <= 1)
                    }
                }

                Button {
                    store.addCard(to: camera.id)
                } label: {
                    Label(L10n.t("添加卡号", "Add Card", language: lang), systemImage: "plus.circle")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.accent)
            }
            .frame(width: 360, alignment: .leading)

            registryField(L10n.t("下一素材号", "Next Clip ID", language: lang), width: 180, text: Binding(
                get: { camera.nextExpectedClipID },
                set: { value in store.updateRegisteredCamera(id: camera.id) { $0.nextExpectedClipID = value } }
            ))
            .frame(width: 210, alignment: .leading)

            Button(role: .destructive) {
                store.removeRegisteredCamera(id: camera.id)
            } label: {
                Label(L10n.t("删除", "Delete", language: lang), systemImage: "trash")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(colors.textSecondary)
            .disabled(store.project.cameraRegistry.count <= 1)
            .frame(width: 92, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }

    private func registryField(_ title: String, width: CGFloat, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(width: width)
            .background(colors.inputBg)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(colors.hairline, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ProjectPathRow: View {
    @Environment(\.themeColors) private var colors
    let title: String
    @Binding var path: String
    var lang: AppLanguage

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 150, alignment: .leading)
            Text(path.isEmpty ? L10n.t("未设置", "Not Set", language: lang) : path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(path.isEmpty ? colors.textSecondary : colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(colors.inputBg)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(colors.hairline, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Button(L10n.t("选择", "Select", language: lang)) {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    path = url.path
                }
            }
            .controlSize(.small)
        }
    }
}

struct HandoffWorkspaceView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @Binding var selection: Workspace
    @ObservedObject var model: OffloadViewModel

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Label(L10n.t("后期交接", "Handoff", language: lang), systemImage: "shippingbox")
                        .font(.system(size: 22, weight: .semibold))
                    Spacer()
                    if model.firstHandoff != nil {
                        Text(L10n.t("已有交接包", "Handoff ready", language: lang))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(colors.stateSuccess)
                    }
                }

                handoffActions
                    .workspaceCard(colors: colors)

                handoffSettings
                    .workspaceCard(colors: colors)
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.surfaceBg)
    }

    private var handoffActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("交接包", "Handoff Package", language: lang))
                .font(.system(size: 13, weight: .semibold))

            if model.firstHandoff == nil {
                Text(L10n.t(
                    "还没有可用的 DIT 下盘结果。完成一次 DIT 下盘后，这里会显示交接包、Resolve 脚本和 Final Cut Pro XML 入口。",
                    "No DIT offload result is available yet. Complete an Offload task first; the handoff package, Resolve script and Final Cut Pro XML entries will appear here.",
                    language: lang
                ))
                .font(.system(size: 12))
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                Button {
                    selection = .offload
                } label: {
                    Label(L10n.t("进入 DIT 下盘", "Go to Offload", language: lang), systemImage: "externaldrive.badge.checkmark")
                }
            } else {
                HStack(spacing: 10) {
                    Button(action: model.revealHandoffPackage) {
                        Label(L10n.t("打开交接包", "Open Handoff", language: lang), systemImage: "shippingbox")
                    }
                    .buttonStyle(.borderedProminent)

                    if model.hasResolveHandoff {
                        Button(action: model.sendToResolve) {
                            Label(L10n.t("发送到 DaVinci", "Send to DaVinci", language: lang), systemImage: "wand.and.stars")
                        }
                        .disabled(!HandoffAppDetector.isResolveInstalled())
                    }

                    if model.hasFinalCutHandoff {
                        Button(action: model.sendToFinalCut) {
                            Label(L10n.t("发送到 Final Cut Pro", "Send to Final Cut Pro", language: lang), systemImage: "film.stack")
                        }
                        .disabled(!HandoffAppDetector.isFinalCutInstalled())
                    }
                }

                if let rootURL = model.firstHandoff?.rootURL {
                    Text(rootURL.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var handoffSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("交接设置", "Handoff Settings", language: lang))
                .font(.system(size: 13, weight: .semibold))
            Picker(L10n.t("目标软件", "Target", language: lang), selection: $settings.settings.handoff.target) {
                ForEach(HandoffTarget.allCases) { target in
                    Text(L10n.t(target.label.0, target.label.1, language: lang)).tag(target)
                }
            }
            .pickerStyle(.menu)

            Toggle(isOn: $settings.settings.handoff.importProxies) {
                Text(L10n.t("交接时链接代理", "Link proxies in handoff", language: lang))
                    .font(.system(size: 12))
            }
            .disabled(settings.settings.handoff.target == .none)

            Toggle(isOn: $settings.settings.handoff.generateStarterTimeline) {
                Text(L10n.t("生成 Final Cut 起始时间线", "Generate Final Cut starter timeline", language: lang))
                    .font(.system(size: 12))
            }
            .disabled(!settings.settings.handoff.target.includesFinalCut)

            Toggle(isOn: $settings.settings.handoff.injectScriptLogMetadata) {
                Text(L10n.t("将场记记录（状态、标签）注入到交接包中", "Inject Script Log metadata (statuses, tags) into handoff", language: lang))
                    .font(.system(size: 12))
            }
            .disabled(settings.settings.handoff.target == .none)

            Toggle(isOn: $settings.settings.handoff.autoOpenAfterHandoff) {
                Text(L10n.t("完成后自动发送到已安装软件", "Auto-send when installed", language: lang))
                    .font(.system(size: 12))
            }
            .disabled(settings.settings.handoff.target == .none)

            Divider()
            Text(L10n.t("DaVinci Resolve 导入内容与标签", "DaVinci Resolve Import & Labels", language: lang))
                .font(.system(size: 12, weight: .semibold))
            ResolveHandoffOptionsView(
                handoff: $settings.settings.handoff,
                language: lang,
                compact: true
            )
            Text(L10n.t(
                "这些映射会保存到交接设置里；目标软件选为 DaVinci Resolve 或双软件时生效，不需要先完成下卡。",
                "These mappings are saved in handoff settings and take effect when the target includes DaVinci Resolve; no completed offload is required to configure them.",
                language: lang
            ))
            .font(.system(size: 10))
            .foregroundStyle(colors.textSecondary)
        }
    }
}

struct ReportsWorkspaceView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @Binding var selection: Workspace
    @ObservedObject var store: ScriptLogStore

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(L10n.t("报告", "Reports", language: lang), systemImage: "doc.text.magnifyingglass")
                .font(.system(size: 22, weight: .semibold))

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.t("场记导出", "Script Log Export", language: lang))
                    .font(.system(size: 13, weight: .semibold))
                HStack {
                    Button(action: store.exportCSV) {
                        Label("CSV", systemImage: "tablecells")
                    }
                    Button(action: store.exportJSON) {
                        Label("JSON", systemImage: "curlybraces")
                    }
                    Button(action: store.exportPDFPlaceholder) {
                        Label("PDF MVP", systemImage: "doc.richtext")
                    }
                }
                Text(L10n.t("CSV / JSON 为完整导出；PDF 当前是可用的 MVP 摘要版。", "CSV / JSON are complete exports; PDF is currently an MVP summary.", language: lang))
                    .font(.system(size: 11))
                    .foregroundStyle(colors.textSecondary)
            }
            .workspaceCard(colors: colors)

            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("DIT 下盘报告", "DIT Offload Reports", language: lang))
                    .font(.system(size: 13, weight: .semibold))
                Text(L10n.t("MHL / PDF / CSV / JSON / TXT 报告仍在 DIT 下盘任务完成后生成。", "MHL / PDF / CSV / JSON / TXT reports are still generated after an Offload task completes.", language: lang))
                    .font(.system(size: 12))
                    .foregroundStyle(colors.textSecondary)
                Button {
                    selection = .offload
                } label: {
                    Label(L10n.t("进入 DIT 下盘", "Go to Offload", language: lang), systemImage: "externaldrive.badge.checkmark")
                }
            }
            .workspaceCard(colors: colors)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.surfaceBg)
    }
}

private extension View {
    func workspaceCard(colors: ThemeColors) -> some View {
        self
            .padding(16)
            .background(colors.panelBg)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(colors.hairline, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
