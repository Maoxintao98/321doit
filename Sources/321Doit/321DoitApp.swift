import AppKit
import SwiftUI

@main
struct ThreeTwoOneDoitApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var lifecycleDelegate
    @StateObject private var settings = SettingsStore()
    @StateObject private var menuState = AppMenuState.shared
    @State private var didRunStartupUpdateCheck = false
    @State private var didConfigureLogging = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environment(\.appTheme, settings.settings.general.theme)
                .tint(settings.settings.general.theme.colors(isDark: isSystemDarkAppearance()).accent)
                .accentColor(settings.settings.general.theme.colors(isDark: isSystemDarkAppearance()).accent)
                .suppressAutomaticFocusEffect()
                .frame(minWidth: 1360, minHeight: 820)
                .preferredColorScheme(colorScheme(for: settings.settings.general.appearance))
                .background(MainWindowAccessor())
                .onAppear {
                    lifecycleDelegate.language = settings.settings.general.language
                    if !didConfigureLogging {
                        didConfigureLogging = true
                        configureLogging(settings.settings.logs)
                        AppLogger.logSessionStart()
                    }
                    if !didRunStartupUpdateCheck, settings.settings.update.autoCheckForUpdates {
                        didRunStartupUpdateCheck = true
                        UpdateChecker.shared.checkForUpdates(
                            receiveBeta: settings.settings.update.receiveBeta,
                            presentNoUpdate: false
                        )
                    }
                }
                .onChange(of: settings.settings.general.language) { language in
                    lifecycleDelegate.language = language
                }
                .onChange(of: settings.settings.logs) { logs in
                    configureLogging(logs)
                    AppLogger.log(.info, category: "settings", "Logging configuration updated")
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button(t("退出 321Doit", "Quit 321Doit")) {
                    lifecycleDelegate.requestGuardedQuit()
                }
                .keyboardShortcut("q", modifiers: [.command])
            }

            CommandGroup(replacing: .appSettings) {
                Button(t("设置...", "Preferences...")) { openSettingsWindow() }
                    .keyboardShortcut(",", modifiers: [.command])
                Button(t("显示项目管理器...", "Show Project Manager...")) { post(.showProjectManager) }
            }

            CommandGroup(replacing: .appInfo) {
                Button(t("关于 321Doit", "About 321Doit")) { AboutWindowPresenter.shared.show(settings: settings) }
                Button(t("联系与支持...", "Contact & Support...")) { post(.contactSupport) }
                Button(t("检查更新...", "Check for Updates...")) {
                    UpdateChecker.shared.checkForUpdates(
                        receiveBeta: settings.settings.update.receiveBeta,
                        presentNoUpdate: false
                    )
                }
            }

            CommandGroup(replacing: .newItem) {
                Button(t("新建项目", "New Project")) { post(.newProject) }
                    .keyboardShortcut("n", modifiers: [.command])
                    .disabled(menuState.isRunning)
                Button(t("打开项目...", "Open Project...")) { post(.openProject) }
                    .keyboardShortcut("o", modifiers: [.command])
                    .disabled(menuState.isRunning)
                Button(t("保存项目", "Save Project")) { post(.saveProject) }
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(menuState.isRunning)
                Button(t("项目管理器...", "Project Manager...")) { post(.showProjectManager) }
                Divider()
                Button(t("选择来源...", "Select Source...")) { post(.selectSource) }
                    .disabled(menuState.isRunning)
                Button(t("添加目标盘...", "Add Destination...")) { post(.addDestination) }
                    .disabled(menuState.isRunning)
                Divider()
                Button(t("打开上次报告", "Open Last Report")) { post(.openLastReport) }
                    .disabled(!menuState.hasLastReport)
                Button(t("打开输出目录", "Reveal Output Folder")) { post(.revealOutputFolder) }
                    .disabled(!menuState.hasLastReport)
            }

            CommandGroup(after: .sidebar) {
                Button(t("项目管理器...", "Project Manager...")) { post(.showProjectManager) }
            }

            CommandMenu(t("项目", "Project")) {
                Button(t("打开项目文件夹", "Open Project Folder")) { post(.openProjectFolder) }
            }

            CommandMenu(t("场记", "Script Log")) {
                Button(t("上一条", "Previous Take")) { post(.previousTake) }
                Button(t("下一条", "Next Take")) { post(.nextTake) }
                Button(t("上一镜", "Previous Shot")) { post(.previousScene) }
                Button(t("下一镜", "Next Shot")) { post(.nextScene) }
            }

            CommandMenu(t("任务", "Tasks")) {
                Button(t("运行预检", "Run Preflight")) { post(.runPreflight) }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(menuState.isRunning)
                Button(t("开始 3·2·1 任务", "Start 3·2·1 Task")) { post(.startTask) }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(menuState.isRunning)
                Button(t("暂停 / 取消", "Pause / Cancel")) { post(.cancelTask) }
                    .disabled(!menuState.isRunning)
                Divider()
                Button(t("只校验已有备份", "Verify Only")) { post(.verifyOnly) }
                    .disabled(menuState.isRunning)
                Button(t("生成代理（随任务执行）", "Generate Proxies (During Task)")) { post(.enableProxies) }
                    .disabled(menuState.isRunning)
                Button(t("生成报告", "Generate Report")) { post(.openLastReport) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!menuState.hasLastReport)
            }

            CommandMenu(t("工具", "Tools")) {
                Button(t("选择 FFmpeg...", "Select FFmpeg...")) { selectFFmpeg() }
                    .disabled(menuState.isRunning)
                Button(t("重新检测 FFmpeg", "Re-check FFmpeg")) { recheckFFmpeg() }
                Divider()
                Button(t("清理已验证更新缓存...", "Clear Verified Update Cache...")) { clearVerifiedUpdateCache() }
                Button(t("打开日志目录", "Open Logs Folder")) { openLogsFolder() }
                Divider()
                Button(t("联系与支持...", "Contact & Support...")) { post(.contactSupport) }
            }

            CommandGroup(replacing: .help) {
                Button(t("321Doit 帮助", "321Doit Help")) {
                    NSWorkspace.shared.open(URL(string: "\(UpdateSettings.githubURL)/blob/main/README.md")!)
                }
                Button(t("联系与支持...", "Contact & Support...")) { post(.contactSupport) }
                Button(t("开源许可", "Open Source Licenses")) { openProjectFile("LICENSE") }
                Button(t("开源鸣谢", "Open Source Acknowledgements")) {
                    NSWorkspace.shared.open(URL(string: "\(UpdateSettings.githubURL)/blob/main/THIRD_PARTY_NOTICES.md")!)
                }
                Button(t("FFmpeg 许可说明", "FFmpeg License Info")) {
                    NSWorkspace.shared.open(URL(string: "https://ffmpeg.org/legal.html")!)
                }
                Divider()
                Button(t("报告问题...", "Report an Issue...")) {
                    NSWorkspace.shared.open(URL(string: UpdateSettings.issueURL)!)
                }
            }
        }
    }

    private func colorScheme(for mode: AppearanceMode) -> ColorScheme? {
        switch mode {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    private func t(_ zh: String, _ en: String) -> String {
        L10n.t(zh, en, language: settings.settings.general.language)
    }

    private func post(_ command: AppMenuCommand) {
        NotificationCenter.default.post(name: command.notificationName, object: nil)
    }

    private func openSettingsWindow() {
        SettingsWindowPresenter.shared.show(settings: settings)
    }

    private func selectFFmpeg() {
        let panel = NSOpenPanel()
        panel.title = t("选择 ffmpeg 可执行文件", "Choose ffmpeg executable")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            SecurityScopedBookmarks.save(url: url, role: "ffmpeg")
            settings.settings.transcode.ffmpegPath = url.path
        }
    }

    private func recheckFFmpeg() {
        let alert = NSAlert()
        alert.messageText = "FFmpeg"
        if let url = FFmpegLocator.executableURL(configuredPath: settings.settings.transcode.ffmpegPath) {
            alert.informativeText = t("已找到：\(url.path)", "Found: \(url.path)")
            alert.alertStyle = .informational
        } else {
            alert.informativeText = t("未找到 FFmpeg。拷贝与校验可用，LUT / RAW / 部分转码不可用。", "FFmpeg was not found. Copy and verify still work; LUT / RAW / some transcodes are unavailable.")
            alert.alertStyle = .warning
        }
        alert.runModal()
    }

    private func openLogsFolder() {
        let fm = FileManager.default
        let url = AppLogger.directoryURL(customPath: settings.settings.logs.logFolder)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    private func configureLogging(_ logs: LogSettings) {
        let level: AppLogLevel
        switch logs.level {
        case .normal: level = .info
        case .detailed: level = .detailed
        case .debug: level = .debug
        }
        AppLogger.configure(
            folderPath: logs.logFolder,
            retentionDays: logs.retentionDays,
            minimumLevel: level,
            writeText: logs.exportText,
            writeJSON: logs.exportJSON
        )
    }

    private func openProjectFile(_ name: String) {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(name)
        NSWorkspace.shared.open(url)
    }

    private func clearVerifiedUpdateCache() {
        let confirmation = NSAlert()
        confirmation.messageText = t("清理已验证更新缓存？", "Clear verified update cache?")
        confirmation.informativeText = t(
            "只会删除 321Doit 已下载并校验过的更新安装包，不会删除项目、素材、报告、日志或未完成任务。需要时可以重新下载。",
            "Only update installers downloaded and verified by 321Doit will be removed. Projects, media, reports, logs, and incomplete tasks are not affected. Updates can be downloaded again when needed."
        )
        confirmation.alertStyle = .warning
        confirmation.addButton(withTitle: t("清理", "Clear"))
        confirmation.addButton(withTitle: t("取消", "Cancel"))
        guard confirmation.runModal() == .alertFirstButtonReturn else { return }

        let resultAlert = NSAlert()
        do {
            let result = try CacheMaintenance.clearVerifiedUpdateCache()
            let size = ByteCountFormatter.string(fromByteCount: result.byteCount, countStyle: .file)
            resultAlert.messageText = t("更新缓存已清理", "Update cache cleared")
            resultAlert.informativeText = t(
                "已删除 \(result.fileCount) 个文件（\(size)）。",
                "Removed \(result.fileCount) files (\(size))."
            )
            resultAlert.alertStyle = .informational
        } catch {
            AppLogger.log(.error, category: "maintenance", "Could not clear update cache: \(error.localizedDescription)")
            resultAlert.messageText = t("无法清理更新缓存", "Could not clear update cache")
            resultAlert.informativeText = error.localizedDescription
            resultAlert.alertStyle = .warning
        }
        resultAlert.runModal()
    }
}

extension View {
    @ViewBuilder
    func suppressAutomaticFocusEffect() -> some View {
        if #available(macOS 14.0, *) {
            focusEffectDisabled()
        } else {
            self
        }
    }
}

@MainActor
private final class AboutWindowPresenter {
    static let shared = AboutWindowPresenter()
    private var window: NSWindow?

    private init() {}

    func show(settings: SettingsStore) {
        let root = AboutPanelView()
            .environmentObject(settings)
            .environment(\.appTheme, settings.settings.general.theme)
            .tint(settings.settings.general.theme.colors(isDark: isDarkAppearance).accent)
            .accentColor(settings.settings.general.theme.colors(isDark: isDarkAppearance).accent)
            .preferredColorScheme(colorScheme(for: settings.settings.general.appearance))

        if let window {
            window.contentViewController = NSHostingController(rootView: root)
            configure(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 430),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(rootView: root)
        configure(window)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private var isDarkAppearance: Bool {
        isSystemDarkAppearance()
    }

    private func configure(_ window: NSWindow) {
        window.title = "321Doit"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
    }

    private func colorScheme(for mode: AppearanceMode) -> ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class SettingsWindowPresenter {
    static let shared = SettingsWindowPresenter()
    private var window: NSWindow?

    private init() {}

    func show(settings: SettingsStore, initialSection: PrefSection = .general) {
        let root = PreferencesView(initialSelection: initialSection)
            .environmentObject(settings)
            .environment(\.appTheme, settings.settings.general.theme)
            .tint(settings.settings.general.theme.colors(isDark: isDarkAppearance).accent)
            .accentColor(settings.settings.general.theme.colors(isDark: isDarkAppearance).accent)
            .preferredColorScheme(colorScheme(for: settings.settings.general.appearance))

        if let window {
            window.contentViewController = NSHostingController(rootView: root)
            configure(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(rootView: root)
        configure(window)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    private var isDarkAppearance: Bool {
        isSystemDarkAppearance()
    }

    private func configure(_ window: NSWindow) {
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
    }

    private func colorScheme(for mode: AppearanceMode) -> ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppMenuCommand: String, CaseIterable {
    case newProject
    case openProject
    case saveProject
    case selectSource
    case addDestination
    case runPreflight
    case startTask
    case cancelTask
    case verifyOnly
    case enableProxies
    case openLastReport
    case revealOutputFolder
    case previousTake
    case nextTake
    case previousScene
    case nextScene
    case showProjectManager
    case openProjectFolder
    case contactSupport

    var notificationName: Notification.Name {
        Notification.Name("321doit.menu.\(rawValue)")
    }
}

@MainActor
final class AppMenuState: ObservableObject {
    static let shared = AppMenuState()

    @Published var isRunning = false
    @Published var hasLastReport = false

    private init() {}
}
