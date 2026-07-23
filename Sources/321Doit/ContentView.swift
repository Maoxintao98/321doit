import SwiftUI

// MARK: - Glass effect helpers

private extension View {
    @ViewBuilder
    func glassOrBackground(_ fallback: Color, cornerRadius: CGFloat = 0) -> some View {
        #if LEGACY_SDK
        self.background(fallback)
        #else
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(fallback)
        }
        #endif
    }
}

struct OffloadView: View {
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var model: OffloadViewModel
    @Environment(\.themeColors) private var colors
    @State private var showWelcome: Bool = false
    @State private var showFFmpegGuide: Bool = false
    @State private var pendingFFmpegGuide: Bool = false

    var body: some View {
        HSplitView {
            Inspector(model: model)
                .frame(minWidth: 340, idealWidth: 400, maxWidth: 480)
            WorkArea(model: model)
                .frame(minWidth: 560)
        }
        .frame(minWidth: 980, minHeight: 680)
        .tint(colors.toolAccent(.offload))
        .accentColor(colors.toolAccent(.offload))
        .background(colors.surfaceBg)
        .background(WindowChromeConfigurator())
        .alert("321Doit", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onAppear {
            syncMenuState()
            model.language = settings.settings.general.language
            scheduleFFmpegGuideIfNeeded()
            // Apply default LUT from settings to the model on launch.
            applySettingDefaultsToModel()
        }
        .onChange(of: settings.settings.general.language) { newLang in
            model.language = newLang
        }
        .onReceive(model.$isRunning) { _ in syncMenuState() }
        .onReceive(model.$lastReport) { _ in syncMenuState() }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.newProject.notificationName)) { _ in newProject() }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.selectSource.notificationName)) { _ in
            guard !model.isRunning else { return }
            model.pickSource()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.addDestination.notificationName)) { _ in
            guard !model.isRunning else { return }
            model.addTarget()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.runPreflight.notificationName)) { _ in
            guard !model.isRunning else { return }
            model.updatePreflight(appSettings: settings.settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.startTask.notificationName)) { _ in
            guard !model.isRunning else { return }
            model.start(appSettings: settings.settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.cancelTask.notificationName)) { _ in
            guard model.isRunning else { return }
            model.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.verifyOnly.notificationName)) { _ in
            guard !model.isRunning else { return }
            model.verifyOnly = true
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.enableProxies.notificationName)) { _ in
            guard !model.isRunning else { return }
            model.generateProxies = true
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.openLastReport.notificationName)) { _ in
            model.revealReports()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppMenuCommand.revealOutputFolder.notificationName)) { _ in
            model.revealOutputFolder()
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeSheet(
                language: $settings.settings.general.language,
                onDismiss: {
                    settings.settings.welcomeAcknowledged = true
                    showWelcome = false
                    if pendingFFmpegGuide {
                        pendingFFmpegGuide = false
                        showFFmpegGuide = true
                    }
                }
            )
            .environmentObject(settings)
            .tint(colors.toolAccent(.offload))
            .accentColor(colors.toolAccent(.offload))
        }
        .sheet(isPresented: $showFFmpegGuide) {
            FFmpegGuideSheet(
                ffmpegPath: $settings.settings.transcode.ffmpegPath,
                onDismiss: { showFFmpegGuide = false }
            )
            .environmentObject(settings)
            .tint(colors.toolAccent(.offload))
            .accentColor(colors.toolAccent(.offload))
        }
    }

    private func applySettingDefaultsToModel() {
        guard !model.hasAppliedTaskDefaults else { return }
        if model.projectName.isEmpty {
            model.projectName = settings.settings.projectTemplate.defaultProjectName
        }
        model.generateProxies = settings.settings.transcode.autoTranscodeOnVerified
        // Pre-fill LUT default if user has one set and no LUT chosen yet.
        if model.transcodeProfile.lutPath == nil,
           !settings.settings.lut.defaultLUTPath.isEmpty {
            model.transcodeProfile.lutPath = settings.settings.lut.defaultLUTPath
            model.transcodeProfile.lutMode = settings.settings.lut.autoApply ? .applyLUT : .none
        }
        model.transcodeProfile.lutIntensity = settings.settings.lut.intensity
        if model.transcodeProfile.codec == .proresProxy {
            model.transcodeProfile.codec = settings.settings.transcode.defaultCodec
            model.transcodeProfile.quality = settings.settings.transcode.defaultQuality
            model.transcodeProfile.bitrate = settings.settings.transcode.defaultBitrate
            model.transcodeProfile.scale = settings.settings.transcode.defaultScale
            model.transcodeProfile.attemptRaw = settings.settings.transcode.attemptRawSources
        }
        model.safeCopyPackage = true
        model.editorialDeliveryPackage = false
        model.hasAppliedTaskDefaults = true
    }

    private func scheduleFFmpegGuideIfNeeded() {
        guard FFmpegLocator.executableURL(configuredPath: settings.settings.transcode.ffmpegPath) == nil else {
            return
        }
        if showWelcome {
            pendingFFmpegGuide = true
        } else {
            DispatchQueue.main.async {
                showFFmpegGuide = true
            }
        }
    }

    private func syncMenuState() {
        AppMenuState.shared.isRunning = model.isRunning
        AppMenuState.shared.hasLastReport = model.lastReport != nil
    }

    private func newProject() {
        guard !model.isRunning else { return }
        model.projectName = settings.settings.projectTemplate.defaultProjectName
        model.cardNumber = ""
        model.operatorName = ""
        model.camera = ""
        model.location = ""
        model.notes = ""
        model.sourceURL = nil
        model.targetRoots = []
        model.transcodeProfile = .default
        model.hasAppliedTaskDefaults = false
        applySettingDefaultsToModel()
        model.safeCopyPackage = true
        model.editorialDeliveryPackage = false
        model.verifyOnly = false
        model.lastReport = nil
        model.logs = []
        model.updatePreflight(appSettings: settings.settings)
        syncMenuState()
    }
}

// MARK: - Welcome sheet

private struct FFmpegGuideSheet: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @Binding var ffmpegPath: String
    let onDismiss: () -> Void

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "film.stack")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(colors.toolAccent(.offload))
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("没有找到 FFmpeg", "FFmpeg was not found", language: lang))
                        .font(.system(size: 19, weight: .semibold))
                    Text(L10n.t("321Doit 仍然可以继续使用。", "321Doit can still be used.", language: lang))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(colors.stateSuccess)
                }
            }

            Text(L10n.t(
                "FFmpeg 是一个免费开源的视频工具。没有它时，拷贝、校验、PDF / MHL 报告、基础系统转码仍可使用；但以下功能会受限或不可用：LUT 烧录、H.266 / VVC、RAW 或部分专业格式解码、通过 FFmpeg 走 VideoToolbox 的 H.264 / HEVC 高级转码。",
                "FFmpeg is a free open-source video tool. Without it, copy, verification, PDF / MHL reports, and basic system transcoding still work; these features are limited or unavailable: LUT bake-in, H.266 / VVC, RAW or some professional format decoding, and FFmpeg-based VideoToolbox H.264 / HEVC transcoding.",
                language: lang
            ))
            .font(.system(size: 12))
            .foregroundStyle(colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("如果你已经安装了 FFmpeg，但放在其他位置，可以直接选择 ffmpeg 文件。", "If FFmpeg is already installed somewhere else, choose the ffmpeg executable file.", language: lang))
                    .font(.system(size: 11, weight: .medium))
                HStack(spacing: 8) {
                    Text(ffmpegPath.isEmpty ? L10n.t("未设置自定义路径", "No custom path selected", language: lang) : ffmpegPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ffmpegPath.isEmpty ? colors.textSecondary : colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(colors.inputBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    Button(L10n.t("选择路径", "Choose Path", language: lang)) {
                        pickFFmpeg()
                    }
                }
            }

            HStack(spacing: 10) {
                Button(L10n.t("查看 FFmpeg 官网", "View FFmpeg Website", language: lang)) {
                    if let url = URL(string: "https://ffmpeg.org/download.html") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Spacer()
                Button(L10n.t("先继续使用", "Continue for Now", language: lang), action: onDismiss)
                    .keyboardShortcut(.escape, modifiers: [])
                Button(L10n.t("完成", "Done", language: lang), action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(24)
        .frame(width: 620)
    }

    private func pickFFmpeg() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("选择 ffmpeg 可执行文件", "Choose ffmpeg executable", language: lang)
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.t("选择", "Choose", language: lang)
        if panel.runModal() == .OK, let url = panel.url {
            SecurityScopedBookmarks.save(url: url, role: "ffmpeg")
            ffmpegPath = url.path
        }
    }
}

private struct WelcomeSheet: View {
    @EnvironmentObject private var settings: SettingsStore
    @Binding var language: AppLanguage
    let onDismiss: () -> Void
    @Environment(\.themeColors) private var colors

    private var lang: AppLanguage { language.resolved }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 14) {
                AppLogo(size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("欢迎使用 321Doit", "Welcome to 321Doit", language: lang))
                        .font(.system(size: 19, weight: .semibold))
                    Text(L10n.t("影视制作全能工作站 · 从分镜到后期",
                                "Filmmaking Workstation · Storyboard to Post",
                                language: lang))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Picker("", selection: $language) {
                    ForEach(AppLanguage.allCases) { l in
                        Text(l.displayName(language: lang)).tag(l)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 160)
            }

            Divider()

            // Intro paragraph
            Text(introText())
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)

            // Five workstations
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("五个专业工具，一个项目工作区", "Five professional tools, one workspace", language: lang))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(colors.textSecondary)

                pillar("1",
                       title: L10n.t("灵动分镜", "Living Storyboard", language: lang),
                       detail: L10n.t(
                        "用分镜表、分层画布、导演轮、机位与走位，把剧本意图变成可执行镜头。",
                        "Turn script intent into executable shots with a shot table, layered canvas, director wheels, blocking, and camera plans.",
                        language: lang
                       ))
                pillar("2",
                       title: L10n.t("拍摄统筹", "Production Planning", language: lang),
                       detail: L10n.t(
                        "统一管理拍摄日历、每日通告、场景、人员、地点和现场信息。",
                        "Manage shooting calendars, call sheets, scenes, crew, locations, and on-set information.",
                        language: lang
                       ))
                pillar("3",
                       title: L10n.t("迅捷场记", "Rapid Script Log", language: lang),
                       detail: L10n.t(
                        "键盘优先记录场、镜、次、多机位与连戏信息，并通过 iPad 和剪辑软件继续流动。",
                        "Log scenes, shots, takes, multicam, and continuity with a keyboard-first workflow that extends to iPad and NLEs.",
                        language: lang
                       ))
                pillar("4",
                       title: L10n.t("极速拷卡", "Turbo Offload", language: lang),
                       detail: L10n.t(
                        "最多三目标安全下盘、回读校验、严格续传、ASC MHL 与多格式报告。",
                        "Verified offload to up to three destinations with read-back checks, strict resume, ASC MHL, and reports.",
                        language: lang
                       ))
                pillar("5",
                       title: L10n.t("媒体转换", "Media Conversion", language: lang),
                       detail: L10n.t(
                        "分析媒体并完成换封装、视频转码与无损音频转换，覆盖主流容器和专业编码。",
                        "Inspect media and perform rewrap, video transcode, and lossless audio conversion across major containers and professional codecs.",
                        language: lang
                       ))
            }

            // Notes
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("注意", "Notes", language: lang))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(colors.textSecondary)
                bullet(L10n.t(
                    "全部流程在本机离线完成，不上传任何数据。",
                    "Everything runs locally — no data leaves your machine.",
                    language: lang))
                bullet(L10n.t(
                    "LUT、H.266 (VVC) 与 RAW 解码依赖 FFmpeg；正式安装包已随附离线版本。",
                    "LUT, H.266 (VVC), and RAW decoding require FFmpeg; the formal installer includes an offline build.",
                    language: lang))
                bullet(L10n.t(
                    "随时可以在「设置 ▸ 通用」里切换语言，也可以从菜单栏的「首选项」打开。",
                    "Switch language any time in Preferences ▸ General — accessible from the menu bar.",
                    language: lang))
                bullet(L10n.t(
                    "上线前请自行做一次小规模测试。",
                    "Always run a small test on your own gear before relying on it on set.",
                    language: lang))
            }

            Spacer(minLength: 2)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Free & Open Source")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                    Toggle(isOn: $settings.settings.skipWelcomeOnLaunch) {
                        Text(L10n.t("不再显示此弹窗", "Do not show this popup again", language: lang))
                            .font(.system(size: 11))
                            .foregroundStyle(colors.textSecondary)
                    }
                }
                Spacer()
                Button(action: onDismiss) {
                    Text(L10n.t("我知道了", "Got it", language: lang))
                        .frame(minWidth: 140)
                }
                .keyboardShortcut(.return, modifiers: [])
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 600)
    }

    private func introText() -> String {
        L10n.t(
            "321Doit 是一款免费、开源、本地优先的 macOS 影视制作全能工作站。它把分镜、统筹、场记、素材安全、媒体转换与后期交接连接在同一个项目流程里。每个工具既能独立使用，也能共享项目上下文。",
            "321Doit is a free, open-source, local-first filmmaking workstation for macOS. It connects storyboarding, planning, script logging, media safety, conversion, and post handoff in one project workflow. Every tool works independently or with shared project context.",
            language: lang
        )
    }

    @ViewBuilder
    private func pillar(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .frame(width: 22, height: 22)
                .background(colors.toolAccent(.offload).opacity(0.18))
                .foregroundStyle(ToolAccent.offload.deep)
                .clipShape(Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("·")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(colors.textSecondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Handoff buttons

private struct HandoffActionButtons: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @ObservedObject var model: OffloadViewModel

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    private var hasPackage: Bool {
        model.firstHandoff != nil
    }

    private var resolveAvailable: Bool {
        model.hasResolveHandoff && HandoffAppDetector.isResolveInstalled()
    }

    private var finalCutAvailable: Bool {
        model.hasFinalCutHandoff && HandoffAppDetector.isFinalCutInstalled()
    }

    var body: some View {
        Menu {
            Button(action: model.revealHandoffPackage) {
                Label(L10n.t("打开归类包", "Open Sort Package", language: lang), systemImage: "shippingbox")
            }
            .disabled(!hasPackage)
            
            if model.hasResolveHandoff {
                Button(action: model.sendToResolve) {
                    Label(L10n.t("发送到 DaVinci", "Send to DaVinci", language: lang), systemImage: "wand.and.stars")
                }
                .disabled(!resolveAvailable)
            }

            if model.hasFinalCutHandoff {
                Button(action: model.sendToFinalCut) {
                    Label(L10n.t("发送到 Final Cut Pro", "Send to Final Cut Pro", language: lang), systemImage: "film.stack")
                }
                .disabled(!finalCutAvailable)
            }
        } label: {
            Label(L10n.t("交接", "Handoff", language: lang), systemImage: "shippingbox")
                .labelStyle(.titleAndIcon)
        }
        .controlSize(.regular)
        .disabled(!hasPackage)
        .help(L10n.t("打开按拍摄计划归类的素材包，或发送到剪辑软件", "Open the shooting-plan sort package or send to an NLE", language: lang))
    }
}

// MARK: - Theme

private enum Theme {
    static let panelRadius: CGFloat = 8

    static func stateColor(_ state: TargetState, _ colors: ThemeColors) -> Color {
        switch state {
        case .pending:     return Color.secondary
        case .copying:     return colors.toolAccent(.offload)
        case .verifying:   return colors.toolAccent(.offload)
        case .transcoding: return colors.stateWarning
        case .completed:   return colors.stateSuccess
        case .failed:      return colors.stateFail
        }
    }

    static func stateLabel(_ state: TargetState, language: AppLanguage) -> String {
        switch state {
        case .pending:     return L10n.t("等待", "PENDING", language: language)
        case .copying:     return L10n.t("拷贝中", "COPYING", language: language)
        case .verifying:   return L10n.t("校验中", "VERIFYING", language: language)
        case .transcoding: return L10n.t("转码中", "TRANSCODING", language: language)
        case .completed:   return L10n.t("完成", "COMPLETED", language: language)
        case .failed:      return L10n.t("失败", "FAILED", language: language)
        }
    }
}

// MARK: - Top bar

struct OffloadTopBar: View {
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var model: OffloadViewModel
    @Environment(\.themeColors) private var colors

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    private var jobTitle: String {
        let p = model.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = model.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty && c.isEmpty { return L10n.t("未命名任务", "Untitled Job", language: lang) }
        if p.isEmpty { return c }
        if c.isEmpty { return p }
        return "\(p) · \(c)"
    }

    private var globalStateText: String {
        if model.isRunning { return L10n.t("运行中", "Running", language: lang) }
        if model.lastReport != nil { return L10n.t("已完成", "Completed", language: lang) }
        return L10n.t("待机", "Idle", language: lang)
    }

    private var globalStateColor: Color {
        if model.isRunning { return colors.toolAccent(.offload) }
        if model.lastReport != nil { return colors.stateSuccess }
        return .secondary
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(jobTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(model.outputPreview)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 270, alignment: .leading)

            Spacer(minLength: 12)

            VStack(alignment: .center, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(globalStateColor).frame(width: 6, height: 6)
                    Text(globalStateText)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(globalStateColor)
                }
                ProgressView(value: model.snapshot.progress)
                    .progressViewStyle(.linear)
                    .tint(colors.toolAccent(.offload))
                    .frame(width: 220)
                Text("\(model.snapshot.completedFiles)/\(model.snapshot.totalFiles) \(L10n.t("文件", "files", language: lang)) · \(formatBytes(model.snapshot.copiedBytes)) / \(formatBytes(model.snapshot.totalBytes)) · \(Int(model.snapshot.progress * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
                Text("\(L10n.t("平均", "AVG", language: lang)) \(speedLabel(model.snapshot.averageBytesPerSecond, language: lang)) · \(L10n.t("当前", "NOW", language: lang)) \(speedLabel(model.snapshot.currentBytesPerSecond, language: lang)) · \(L10n.t("预计", "ETA", language: lang)) \(etaLabel(model.snapshot.etaSeconds, language: lang))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button(action: model.revealReports) {
                    Label(L10n.t("报告", "Reports", language: lang), systemImage: "doc.text.magnifyingglass")
                        .labelStyle(.titleAndIcon)
                }
                .controlSize(.regular)
                .disabled(model.lastReport == nil)
                .accessibilityIdentifier("offload.reports")
                .help(L10n.t("显示报告", "Reveal Reports", language: lang))

                if model.isRunning {
                    Button(role: .destructive, action: model.cancel) {
                        Label(L10n.t("取消", "Stop", language: lang), systemImage: "stop.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .controlSize(.regular)
                    .accessibilityIdentifier("offload.cancel")
                } else {
                    Button(role: .destructive, action: model.resetTask) {
                        Label(L10n.t("重置", "Reset", language: lang), systemImage: "arrow.counterclockwise")
                            .labelStyle(.titleAndIcon)
                    }
                    .controlSize(.regular)
                    .accessibilityIdentifier("offload.reset")
                    .help(L10n.t("清空当前配置，从零开始", "Clear current settings and start from scratch", language: lang))

                    Button(action: { model.start(appSettings: settings.settings) }) {
                        Label(L10n.t("开始拷卡", "Start Copy", language: lang), systemImage: "play.fill")
                            .labelStyle(.titleAndIcon)
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!model.canStart)
                    .accessibilityIdentifier("offload.start")
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(colors.surfaceBg)
    }
}

private func speedLabel(_ bytesPerSecond: Double, language: AppLanguage) -> String {
    guard bytesPerSecond > 1 else {
        return L10n.t("计算中", "calculating", language: language)
    }
    return "\(formatBytes(UInt64(bytesPerSecond)))/s"
}

private func etaLabel(_ seconds: TimeInterval?, language: AppLanguage) -> String {
    guard let seconds, seconds.isFinite, seconds > 0 else {
        return L10n.t("计算中", "calculating", language: language)
    }
    let total = Int(seconds.rounded())
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
    return String(format: "%02d:%02d", m, s)
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
    }
}

// MARK: - Inspector (left)

private struct Inspector: View {
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var model: OffloadViewModel
    @Environment(\.themeColors) private var colors

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private var registeredCards: [String] {
        model.cameraRegistry.flatMap(\.cardNames).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private var registeredCameras: [String] {
        model.cameraRegistry.map(\.label).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    @State private var showMoreMetadata = false
    @State private var showAdvancedOptions = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if model.hasRestoredPendingTask {
                    restoredTaskBanner
                }
                source
                destinations
                metadata
                options
                preflight
            }
            .padding(18)
        }
    }

@ViewBuilder
private var restoredTaskBanner: some View {
    HStack(alignment: .top, spacing: 10) {
        Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
            .foregroundStyle(colors.stateWarning)
            .font(.system(size: 16))
            .padding(.top, 2)
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t("已恢复上次意外中断的任务", "Recovered interrupted task", language: lang))
                .font(.system(size: 13, weight: .semibold))
            Text(L10n.t("已自动填入未完成的任务信息，点击下方「开始拷贝」即可进行断点续传。",
                        "Information for the incomplete task has been filled in. Click 'Start' below to resume.",
                        language: lang))
                .font(.system(size: 11))
                .foregroundStyle(colors.textSecondary)
        }
        Spacer()
        Button {
            model.hasRestoredPendingTask = false
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
    .padding(12)
    .background(colors.stateWarning.opacity(0.1))
    .cornerRadius(6)
    .overlay(
        RoundedRectangle(cornerRadius: 6)
            .stroke(colors.stateWarning.opacity(0.3), lineWidth: 1)
    )
}

// Metadata

    // Metadata

    private var metadata: some View {
        Section(title: L10n.t("任务信息", "Job Info", language: lang)) {
            VStack(spacing: 10) {
                LabeledField(
                    L10n.t("项目名称", "Project", language: lang),
                    text: $model.projectName,
                    required: true,
                    disabled: model.isRunning,
                    accessibilityIdentifier: "offload.projectName"
                )
                HStack(alignment: .bottom, spacing: 8) {
                    if registeredCards.isEmpty {
                        LabeledField(
                            L10n.t("卡号", "Card", language: lang),
                            text: $model.cardNumber,
                            required: true,
                            disabled: model.isRunning,
                            accessibilityIdentifier: "offload.cardNumber"
                        )
                    } else {
                        pickerField(
                            title: L10n.t("卡号", "Card", language: lang),
                            selection: $model.cardNumber,
                            values: registeredCards,
                            required: true
                        )
                        .disabled(model.isRunning)
                    }
                    Button {
                        model.incrementReel()
                    } label: {
                        Label(model.nextReelSuggestion, systemImage: "plus.forwardslash.minus")
                            .labelStyle(.titleAndIcon)
                    }
                    .controlSize(.small)
                    .disabled(model.isRunning)
                    .help(L10n.t("自动递增卡号", "Auto-increment Card / Reel", language: lang))
                }
                LabeledField(
                    L10n.t("操作员", "Operator", language: lang),
                    text: $model.operatorName,
                    required: true,
                    disabled: model.isRunning,
                    accessibilityIdentifier: "offload.operatorName"
                )

                DisclosureGroup(isExpanded: $showMoreMetadata) {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            if registeredCameras.isEmpty {
                                LabeledField("机位", text: $model.camera, disabled: model.isRunning)
                            } else {
                                pickerField(title: "机位", selection: $model.camera, values: registeredCameras)
                                    .disabled(model.isRunning)
                            }
                            LabeledField(L10n.t("地点", "Location", language: lang), text: $model.location, disabled: model.isRunning)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            FieldLabel(L10n.t("备注", "Notes", language: lang))
                            TextField("", text: $model.notes, axis: .vertical)
                                .textFieldStyle(.plain)
                                .lineLimit(2...4)
                                .padding(8)
                                .background(colors.inputBg)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(colors.hairline, lineWidth: 0.5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .disabled(model.isRunning)
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text(L10n.t("更多信息（机位 · 地点 · 备注）", "More (Camera · Location · Notes)", language: lang))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
    }

    private func pickerField(title: String, selection: Binding<String>, values: [String], required: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(title + (required ? " *" : ""))
            Picker("", selection: selection) {
                if selection.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L10n.t("请选择", "Select", language: lang)).tag("")
                }
                ForEach(values, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    // Source

    private var source: some View {
        Section(title: L10n.t("来源", "Source", language: lang)) {
            VStack(alignment: .leading, spacing: 8) {
                PathRow(
                    icon: "sdcard",
                    path: model.sourceURL?.path,
                    placeholder: L10n.t("未选择来源卡或文件夹", "No source selected", language: lang)
                )
                if let candidate = model.mountedSourceCandidate {
                    MountedSourceCard(model: model, candidate: candidate)
                }
                Button(action: model.pickSource) {
                    Label(model.sourceURL == nil
                          ? L10n.t("选择来源", "Select Source", language: lang)
                          : L10n.t("更换来源", "Change Source", language: lang),
                          systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .disabled(model.isRunning)
                .accessibilityIdentifier("offload.selectSource")
            }
        }
    }

    // Destinations

    private var destinations: some View {
        Section(
            title: L10n.t("目标盘", "Destinations", language: lang),
            accessory: AnyView(
                Text("\(model.targetRoots.count) / 3")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(model.targetRoots.isEmpty ? colors.textSecondary : colors.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            )
        ) {
            VStack(alignment: .leading, spacing: 8) {
                if model.targetRoots.isEmpty {
                    PathRow(icon: "externaldrive", path: nil,
                            placeholder: L10n.t("未选择目标盘", "No destination selected", language: lang))
                } else {
                    ForEach(Array(model.targetRoots.enumerated()), id: \.element.path) { idx, url in
                        HStack(spacing: 8) {
                            Text("\(idx + 1)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .frame(width: 16, height: 16)
                                .background(Color.primary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            PathRow(icon: "externaldrive", path: url.path, placeholder: "")
                            Button {
                                model.removeTarget(url)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(colors.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isRunning)
                            .help(L10n.t("移除", "Remove", language: lang))
                        }
                    }
                }
                Button(action: model.addTarget) {
                    Label(L10n.t("添加目标盘", "Add Destination", language: lang), systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
                .disabled(model.isRunning || model.targetRoots.count >= 3)
                .accessibilityIdentifier("offload.addDestination")
            }
        }
    }

    // Options (verify / proxy / advanced)

    private var options: some View {
        Section(title: L10n.t("任务选项", "Options", language: lang)) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $model.verifyOnly) {
                    Text(L10n.t("只重新校验已有备份",
                                "Verify Only / Re-check existing backup",
                                language: lang))
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .disabled(model.isRunning)

                Toggle(isOn: $model.generateProxies) {
                    Text(L10n.t("拷贝校验后生成代理或转码文件",
                                "Generate proxy / transcode after verified copy",
                                language: lang))
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .disabled(model.isRunning)

                if model.generateProxies {
                    transcodeControls
                }

                DisclosureGroup(isExpanded: $showAdvancedOptions) {
                    VStack(alignment: .leading, spacing: 18) {
                        burnIn
                        frameExtraction
                    }
                    .padding(.top, 8)
                } label: {
                    Text(L10n.t("高级选项（画面烧录 · 截图导出）", "Advanced (Burn-in · Frame Extraction)", language: lang))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
    }

    private var transcodeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Codec & Quality Group
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    FieldLabel(L10n.t("编码", "Codec", language: lang))
                    Picker("", selection: $model.transcodeProfile.codec) {
                        Text("Apple ProRes 422 Proxy").tag(TranscodeCodec.proresProxy)
                        Text("Apple ProRes 422 LT").tag(TranscodeCodec.proresLT)
                        Text("Apple ProRes 422").tag(TranscodeCodec.prores422)
                        Text("Apple ProRes 422 HQ").tag(TranscodeCodec.prores422HQ)
                        Text("Apple ProRes 4444").tag(TranscodeCodec.prores4444)
                        Text("Apple ProRes 4444 XQ").tag(TranscodeCodec.prores4444XQ)
                        Divider()
                        Text("H.264 / AVC").tag(TranscodeCodec.h264)
                        Text("H.265 / HEVC").tag(TranscodeCodec.h265)
                        Text("H.266 / VVC").tag(TranscodeCodec.h266)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(model.isRunning)
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        FieldLabel(L10n.t("画质", "Quality", language: lang))
                        Picker("", selection: $model.transcodeProfile.quality) {
                            ForEach(TranscodeQuality.allCases) { q in
                                Text(transcodeQualityLabel(q)).tag(q)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(model.isRunning
                                  || model.transcodeProfile.codec.isProRes
                                  || model.transcodeProfile.bitrate != .auto)
                        .help(model.transcodeProfile.codec.isProRes
                              ? L10n.t("ProRes 画质由 profile 决定", "ProRes quality is fixed by the profile.", language: lang)
                              : L10n.t("选了固定码率后画质档位不再生效", "Disabled when a fixed bitrate is set.", language: lang))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        FieldLabel(L10n.t("码率", "Bitrate", language: lang))
                        Picker("", selection: $model.transcodeProfile.bitrate) {
                            ForEach(TranscodeBitrate.allCases) { b in
                                Text(transcodeBitrateLabel(b)).tag(b)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(model.isRunning || model.transcodeProfile.codec.isProRes)
                        .help(model.transcodeProfile.codec.isProRes
                              ? L10n.t("ProRes 码率由 profile 决定", "ProRes bitrate is fixed by the profile.", language: lang)
                              : L10n.t("选 Auto 用 CRF 画质档；其它档位为目标码率", "Auto uses CRF; other values are target bitrates.", language: lang))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                        FieldLabel(L10n.t("分辨率", "Scale", language: lang))
                        Picker("", selection: $model.transcodeProfile.scale) {
                            ForEach(TranscodeScale.allCases) { s in
                                Text(transcodeScaleLabel(s)).tag(s)
                            }
                        }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .disabled(model.isRunning)
                }

                Toggle(isOn: $model.transcodeProfile.attemptRaw) {
                    Text(L10n.t("尝试视频 RAW 转码 (R3D · BRAW · ARRIRAW · CRM · MLV …)",
                                "Attempt RAW video transcode (R3D · BRAW · ARRIRAW · CRM · MLV …)",
                                language: lang))
                        .font(.system(size: 12))
                }
                .disabled(model.isRunning)
            }
            .padding(8)
            .background(Color.primary.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(colors.hairline, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // LUT block
            lutBlock


            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)
                Text(L10n.t("依赖 FFmpeg（正式安装包已随附离线版本）。无 FFmpeg 时回退到 AVFoundation：仅支持 ProRes 422 / H.264 / HEVC，VVC、LUT 与 RAW 不可用。",
                            "Requires FFmpeg (included offline with the formal installer). Without FFmpeg, falls back to AVFoundation: only ProRes 422 / H.264 / HEVC; VVC, LUT and RAW unavailable.",
                            language: lang))
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private var lutBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(L10n.t("LUT 模式", "LUT Mode", language: lang), selection: $model.transcodeProfile.lutMode) {
                ForEach(LUTMode.allCases) { mode in
                    Text(lutModeLabel(mode)).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .disabled(model.isRunning)

            if model.transcodeProfile.lutMode != .none {
                HStack(spacing: 6) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 11))
                        .foregroundStyle(ToolAccent.offload.deep)
                    Text(model.transcodeProfile.lutPath?.isEmpty == false
                         ? (model.transcodeProfile.lutPath ?? "")
                         : L10n.t("未选择 LUT 文件", "No LUT chosen", language: lang))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(model.transcodeProfile.lutPath?.isEmpty == false ? colors.textPrimary : colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                    Button(L10n.t("选择…", "Choose…", language: lang)) {
                        model.pickLUT()
                    }
                    .controlSize(.small)
                    .disabled(model.isRunning)
                    if model.transcodeProfile.lutPath?.isEmpty == false {
                        Button {
                            model.transcodeProfile.lutPath = nil
                        } label: {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isRunning)
                    }
                }

                HStack {
                    Text(L10n.t("强度", "Intensity", language: lang))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(colors.textSecondary)
                    Slider(value: $model.transcodeProfile.lutIntensity, in: 0...1)
                        .disabled(model.isRunning)
                    Text(String(format: "%.2f", model.transcodeProfile.lutIntensity))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 40)
                }
            }
        }
        .padding(8)
        .background(model.transcodeProfile.lutMode != .none ? colors.toolAccent(.offload).opacity(0.06) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    model.transcodeProfile.lutMode != .none ? colors.toolAccent(.offload).opacity(0.4) : Color.clear,
                    lineWidth: 0.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var burnIn: some View {
        Section(title: L10n.t("画面烧录", "Burn-in", language: lang)) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $model.transcodeProfile.burnIn.enabled) {
                    Text(L10n.t("开启画面烧录", "Enable Burn-in", language: lang))
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .disabled(model.isRunning)
                .onChange(of: model.transcodeProfile.burnIn.enabled) { enabled in
                    if enabled {
                        model.generateProxies = true
                    }
                }

                if model.transcodeProfile.burnIn.enabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(L10n.t("烧录到", "Burn into", language: lang), selection: $model.transcodeProfile.burnIn.target) {
                            ForEach(BurnInTarget.allCases) { target in
                                Text(bilingual(target.label, lang)).tag(target)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(model.isRunning)

                        HStack {
                            Picker(L10n.t("位置", "Position", language: lang), selection: $model.transcodeProfile.burnIn.position) {
                                ForEach(BurnInPosition.allCases) { p in
                                    Text(bilingual(p.label, lang)).tag(p)
                                }
                            }
                            Picker(L10n.t("大小", "Size", language: lang), selection: $model.transcodeProfile.burnIn.size) {
                                ForEach(BurnInSize.allCases) { s in
                                    Text(bilingual(s.label, lang)).tag(s)
                                }
                            }
                        }
                        
                        let bFields = Binding(get: { model.transcodeProfile.burnIn.fields }, set: { model.transcodeProfile.burnIn.fields = $0 })
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                            Toggle(L10n.t("文件名", "File name", language: lang), isOn: bFields.fileName)
                            Toggle(L10n.t("时间码", "Timecode", language: lang), isOn: bFields.timecode)
                            Toggle(L10n.t("储存卡号", "Card ID", language: lang), isOn: bFields.reelOrCard)
                            Toggle(L10n.t("摄影机编号", "Camera ID", language: lang), isOn: bFields.cameraID)
                            Toggle(L10n.t("项目名称", "Project Name", language: lang), isOn: bFields.projectName)
                            Toggle(L10n.t("拍摄日", "Shoot Day", language: lang), isOn: bFields.shootDay)
                        }
                        .font(.system(size: 11))
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func bilingual(_ pair: (String, String), _ lang: AppLanguage) -> String {
        L10n.t(pair.0, pair.1, language: lang)
    }

    private func transcodeQualityLabel(_ quality: TranscodeQuality) -> String {
        switch quality {
        case .low: return L10n.t("低", "Low", language: lang)
        case .medium: return L10n.t("中", "Medium", language: lang)
        case .high: return L10n.t("高", "High", language: lang)
        }
    }

    private func transcodeBitrateLabel(_ bitrate: TranscodeBitrate) -> String {
        switch bitrate {
        case .auto: return L10n.t("自动", "Auto (CRF)", language: lang)
        case .mbps5, .mbps10, .mbps25, .mbps50, .mbps100, .mbps200, .mbps400:
            return bitrate.displayName
        }
    }

    private func transcodeScaleLabel(_ scale: TranscodeScale) -> String {
        switch scale {
        case .original: return L10n.t("原始", "Original", language: lang)
        case .uhd2160: return "UHD 3840"
        case .hd1080: return "FHD 1920"
        case .hd720: return "HD 1280"
        case .half: return L10n.t("原始 1/2", "Half size", language: lang)
        }
    }

    private func lutModeLabel(_ mode: LUTMode) -> String {
        switch mode {
        case .none: return L10n.t("不应用 LUT", "None", language: lang)
        case .applyLUT: return L10n.t("应用 LUT", "Apply LUT", language: lang)
        case .cleanAndLUT: return L10n.t("同时输出干净版和 LUT 版", "Clean and LUT copies", language: lang)
        }
    }

    // Handoff

    @ViewBuilder
    private var handoff: some View {
        Section(title: L10n.t("后期交接", "Post Handoff", language: lang)) {
            VStack(alignment: .leading, spacing: 8) {
                Picker(L10n.t("导入目标软件", "Import Target", language: lang), selection: $settings.settings.handoff.target) {
                    ForEach(HandoffTarget.allCases) { target in
                        Text(bilingual(target.label, lang)).tag(target)
                    }
                }
                .pickerStyle(.menu)
                .disabled(model.isRunning)

                if settings.settings.handoff.target != .none {
                    Toggle(isOn: $settings.settings.handoff.importProxies) {
                        Text(L10n.t("交接时链接代理", "Link proxies in handoff", language: lang))
                            .font(.system(size: 12))
                    }
                    .disabled(model.isRunning)

                    if settings.settings.handoff.target.includesResolve {
                        Toggle(isOn: $settings.settings.handoff.resolveImportOriginals) {
                            Text(L10n.t("导入原始素材", "Import original media", language: lang))
                                .font(.system(size: 12))
                        }
                        .disabled(model.isRunning)

                        HStack {
                            Text(L10n.t("OK", "OK", language: lang))
                            Spacer()
                            Picker("", selection: $settings.settings.handoff.resolveOKMapping.clipColor) {
                                ForEach(ResolveClipColor.allCases) { color in
                                    Text(L10n.t(color.label.0, color.label.1, language: lang)).tag(color)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 118)
                        }
                        .font(.system(size: 12))
                        .disabled(model.isRunning)

                        HStack {
                            Text(L10n.t("NG", "NG", language: lang))
                            Spacer()
                            Picker("", selection: $settings.settings.handoff.resolveNGMapping.clipColor) {
                                ForEach(ResolveClipColor.allCases) { color in
                                    Text(L10n.t(color.label.0, color.label.1, language: lang)).tag(color)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 118)
                        }
                        .font(.system(size: 12))
                        .disabled(model.isRunning)
                    }

                    if settings.settings.handoff.target.includesFinalCut {
                        Toggle(isOn: $settings.settings.handoff.generateStarterTimeline) {
                            Text(L10n.t("生成 Final Cut 起始时间线", "Generate Final Cut starter timeline", language: lang))
                                .font(.system(size: 12))
                        }
                        .disabled(model.isRunning)
                    }

                    Toggle(isOn: $settings.settings.handoff.autoOpenAfterHandoff) {
                        Text(L10n.t("完成后自动发送到已安装软件", "Auto-send when installed", language: lang))
                            .font(.system(size: 12))
                    }
                    .disabled(model.isRunning)

                    Text(L10n.t("05_HANDOFF/按拍摄计划归类.command · Resolve · FinalCutPro", "05_HANDOFF/Organize by Shooting Plan.command · Resolve · FinalCutPro", language: lang))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // Frame Extraction

    @ViewBuilder
    private var frameExtraction: some View {
        Section(title: L10n.t("截图导出", "Frame Extraction", language: lang)) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $model.transcodeProfile.frameExtraction.enabled) {
                    Text(L10n.t("导出随机截图", "Export Random Frames", language: lang))
                        .font(.system(size: 12))
                }
                .toggleStyle(.switch)
                .disabled(model.isRunning)

                if model.transcodeProfile.frameExtraction.enabled {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L10n.t("每视频抽取帧数:", "Frames per video:", language: lang))
                                .font(.system(size: 11))
                            Stepper(value: $model.transcodeProfile.frameExtraction.framesPerVideo, in: 1...10) {
                                Text("\(model.transcodeProfile.frameExtraction.framesPerVideo)")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                        }
                        
                        let feFields = Binding(get: { model.transcodeProfile.frameExtraction }, set: { model.transcodeProfile.frameExtraction = $0 })
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(L10n.t("将截图写入 PDF 报告表格", "Embed frames in PDF report", language: lang), isOn: feFields.embedInPDF)
                            Toggle(L10n.t("截图应用 LUT", "Apply LUT to frames", language: lang), isOn: feFields.applyLUT)
                        }
                        .font(.system(size: 11))
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // Preflight

    private var preflight: some View {
        let results = PreflightChecker.run(
            projectName: model.projectName,
            cardNumber: model.cardNumber,
            operatorName: model.operatorName,
            sourceURL: model.sourceURL,
            targetRoots: model.targetRoots,
            outputFolderName: model.outputPreview,
            outputFolderNames: model.outputFolderNames,
            settings: settings.settings,
            generateProxies: model.generateProxies,
            transcodeProfile: model.transcodeProfile,
            language: lang
        )
        let problems = results.filter { $0.severity != .ok }
        return Section(title: L10n.t("预检", "Preflight", language: lang)) {
            VStack(alignment: .leading, spacing: 7) {
                if problems.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(colors.stateSuccess)
                        Text(L10n.t("预检全部通过（\(results.count) 项）", "All \(results.count) checks passed", language: lang))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(colors.textPrimary)
                    }
                } else {
                    ForEach(problems) { item in
                        PreflightResultRow(result: item)
                    }
                    Text(L10n.t("其余 \(results.count - problems.count) 项已通过", "\(results.count - problems.count) other checks passed", language: lang))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
    }
}

// MARK: - Section

private struct Section<Content: View>: View {
    let title: String
    var accessory: AnyView? = nil
    @Environment(\.themeColors) private var colors
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Spacer()
                if let a = accessory { a }
            }
            content()
        }
    }
}

private struct FieldLabel: View {
    let title: String
    var required: Bool = false
    @Environment(\.themeColors) private var colors

    init(_ title: String, required: Bool = false) {
        self.title = title
        self.required = required
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(colors.textSecondary)
            if required {
                Text("•")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(colors.stateFail)
            }
        }
    }
}

private struct LabeledField: View {
    let title: String
    @Binding var text: String
    var required: Bool = false
    var disabled: Bool = false
    var accessibilityIdentifier: String?
    @Environment(\.themeColors) private var colors

    init(
        _ title: String,
        text: Binding<String>,
        required: Bool = false,
        disabled: Bool = false,
        accessibilityIdentifier: String? = nil
    ) {
        self.title = title
        self._text = text
        self.required = required
        self.disabled = disabled
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            FieldLabel(title, required: required)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(colors.inputBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(colors.hairline, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .disabled(disabled)
                .accessibilityIdentifier(accessibilityIdentifier ?? "")
        }
    }
}

private struct PathRow: View {
    let icon: String
    let path: String?
    let placeholder: String
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(colors.textSecondary)
                .frame(width: 14)
            Text(path ?? placeholder)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(path == nil ? colors.textSecondary : colors.textPrimary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(colors.inputBg)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(colors.hairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct PreflightRow: View {
    let ok: Bool
    let text: String
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundStyle(ok ? colors.stateSuccess : colors.textSecondary)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(ok ? colors.textPrimary : colors.textSecondary)
        }
    }
}

private struct PreflightResultRow: View {
    let result: PreflightCheckResult
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.message)
                    .font(.system(size: 11))
                    .foregroundStyle(colors.textPrimary)
                if let detail = result.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var symbol: String {
        switch result.severity {
        case .ok: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch result.severity {
        case .ok: return colors.stateSuccess
        case .warning: return colors.stateWarning
        case .error: return colors.stateFail
        }
    }
}

private struct MountedSourceCard: View {
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var model: OffloadViewModel
    @Environment(\.themeColors) private var colors
    let candidate: MountedSourceCandidate

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(L10n.t("检测到新素材盘", "New media volume detected", language: lang), systemImage: "sdcard.fill")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(candidate.status)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.stateWarning)
            }
            cardLine("卷名", "Volume", candidate.volumeName)
            if let suggested = candidate.suggestedCardName {
                cardLine("建议登记为", "Suggested Card", suggested)
            }
            cardLine("路径", "Path", candidate.url.path)
            cardLine(
                "疑似设备",
                "Likely Device",
                candidate.profile == .unknown
                    ? L10n.t("未识别出明确摄影机结构，但发现 \(candidate.videoFileCount) 个视频文件", "No clear camera structure, but found \(candidate.videoFileCount) video files", language: lang)
                    : candidate.profile.displayName
            )
            if let mediaRoot = candidate.profile.mediaRootRelativePath, !mediaRoot.isEmpty {
                cardLine("素材目录", "Media Root", candidate.url.appendingPathComponent(mediaRoot, isDirectory: true).path)
            }
            cardLine("识别依据", "Evidence", candidate.profile.evidence.isEmpty ? L10n.t("视频扩展名扫描", "Video extension scan", language: lang) : candidate.profile.evidence.joined(separator: ", "))
            HStack {
                Button(L10n.t("确认作为来源", "Use as Source", language: lang)) {
                    model.acceptMountedSourceCandidate()
                }
                .buttonStyle(.borderedProminent)
                Button(L10n.t("忽略", "Ignore", language: lang)) {
                    model.ignoreMountedSourceCandidate()
                }
                Spacer()
            }
        }
        .padding(10)
        .background(colors.inputBg)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(colors.toolAccent(.offload).opacity(0.45), lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func cardLine(_ zh: String, _ en: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(L10n.t(zh, en, language: lang))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Work area (right)

private struct WorkArea: View {
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var model: OffloadViewModel
    @Environment(\.themeColors) private var colors

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VSplitView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if !model.failedFileEntries.isEmpty {
                            FailureActions(model: model)
                        }
                        if model.snapshot.targets.isEmpty {
                            EmptyTargets()
                        } else {
                            VStack(spacing: 10) {
                                ForEach(model.snapshot.targets, id: \TargetProgress.id) { target in
                                    TargetLane(
                                        target: target,
                                        totalBytes: max(model.snapshot.totalBytes, 1),
                                        proxyReport: proxyReport(for: target)
                                    )
                                }
                            }
                        }
                    }
                    .padding(18)
                }
                .frame(minHeight: 240)
                .glassOrBackground(colors.panelBg)

                LogPanel(logs: model.logs)
                    .frame(minHeight: 140, idealHeight: 180)
            }
        }
    }

    private func proxyReport(for target: TargetProgress) -> TargetReport? {
        model.lastReport?.targets.first(where: { $0.outputURL == target.outputURL })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 6) {
                    Circle().fill(globalStateColor).frame(width: 6, height: 6)
                    Text(globalStateText)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(globalStateColor)
                }

                Spacer(minLength: 8)

                Text(model.outputPreview)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                if model.isRunning || model.lastReport != nil {
                    ProgressView(value: model.snapshot.progress)
                        .progressViewStyle(.linear)
                        .tint(colors.toolAccent(.offload))
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(model.snapshot.completedFiles)/\(model.snapshot.totalFiles) \(L10n.t("文件", "files", language: lang)) · \(formatBytes(model.snapshot.copiedBytes)) / \(formatBytes(model.snapshot.totalBytes)) · \(Int(model.snapshot.progress * 100))%")
                        Text("\(L10n.t("平均", "AVG", language: lang)) \(speedLabel(model.snapshot.averageBytesPerSecond, language: lang)) · \(L10n.t("预计", "ETA", language: lang)) \(etaLabel(model.snapshot.etaSeconds, language: lang))")
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
                } else {
                    Spacer()
                }

                Button(action: model.revealReports) {
                    Label(L10n.t("报告", "Reports", language: lang), systemImage: "doc.text.magnifyingglass")
                        .labelStyle(.titleAndIcon)
                }
                .controlSize(.regular)
                .disabled(model.lastReport == nil)

                if model.isRunning {
                    Button(role: .destructive, action: model.cancel) {
                        Label(L10n.t("取消", "Stop", language: lang), systemImage: "stop.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .controlSize(.regular)
                } else {
                    Button(role: .destructive, action: model.resetTask) {
                        Label(L10n.t("重置", "Reset", language: lang), systemImage: "arrow.counterclockwise")
                            .labelStyle(.titleAndIcon)
                    }
                    .controlSize(.regular)

                    Button(action: { model.start(appSettings: settings.settings) }) {
                        Label(L10n.t("开始拷卡", "Start Copy", language: lang), systemImage: "play.fill")
                            .labelStyle(.titleAndIcon)
                            .frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!model.canStart)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(colors.panelBg)
    }

    private var globalStateText: String {
        if model.isRunning { return L10n.t("运行中", "Running", language: lang) }
        if model.lastReport != nil { return L10n.t("已完成", "Completed", language: lang) }
        return L10n.t("待机", "Idle", language: lang)
    }

    private var globalStateColor: Color {
        if model.isRunning { return colors.toolAccent(.offload) }
        if model.lastReport != nil { return colors.stateSuccess }
        return .secondary
    }

    private func elapsedString(from start: Date) -> String {
        let s = Int(Date().timeIntervalSince(start))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return String(format: "ELAPSED  %02d:%02d:%02d", h, m, sec)
    }
}

private struct FailureActions: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @ObservedObject var model: OffloadViewModel

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(colors.stateFail)
            Text(L10n.t("存在失败文件", "Failed files exist", language: lang))
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Button(L10n.t("查看失败列表", "View Failed", language: lang)) {
                model.showFailedFiles()
            }
            Button(L10n.t("导出失败报告", "Export Failed Report", language: lang)) {
                model.exportFailedReport()
            }
        }
        .padding(10)
        .background(colors.stateFail.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(colors.stateFail.opacity(0.35), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct EmptyTargets: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(colors.textSecondary)
            Text(L10n.t("等待任务开始", "Waiting to start", language: lang))
                .font(.system(size: 12, weight: .medium))
            Text(L10n.t("选择来源和目标盘，然后点击开始拷卡",
                        "Select source and destinations, then press Start Copy",
                        language: lang))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}

private struct TargetLane: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    let target: TargetProgress
    let totalBytes: UInt64
    let proxyReport: TargetReport?

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    private var copyProgress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(target.copiedBytes) / Double(totalBytes)
    }
    private var verifyProgress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(target.verifiedBytes) / Double(totalBytes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.stateColor(target.state, colors))
                    .frame(width: 8, height: 8)
                Text(target.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(Theme.stateLabel(target.state, language: lang))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(Theme.stateColor(target.state, colors))
            }

            // Output path
            HStack(spacing: 6) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundStyle(colors.textSecondary)
                Text(target.outputURL.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            HStack(spacing: 6) {
                Image(systemName: "speedometer")
                    .font(.system(size: 9))
                    .foregroundStyle(colors.textSecondary)
                Text("\(L10n.t("写入速度", "Write speed", language: lang)): \(speedLabel(target.bytesPerSecond, language: lang))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
            }

            // Progress bars
            VStack(alignment: .leading, spacing: 6) {
                LaneBar(
                    label: L10n.t("拷贝", "Copy", language: lang),
                    bytes: target.copiedBytes,
                    total: totalBytes,
                    progress: copyProgress,
                    tint: colors.toolAccent(.offload)
                )
                LaneBar(
                    label: L10n.t("校验", "Verify", language: lang),
                    bytes: target.verifiedBytes,
                    total: totalBytes,
                    progress: verifyProgress,
                    tint: colors.toolAccent(.offload)
                )
                if let transcodeProgress = target.transcodeProgress {
                    LaneBarSimple(
                        label: L10n.t("转码", "Transcode", language: lang),
                        progress: transcodeProgress,
                        tint: colors.stateWarning
                    )
                }
            }

            // Error
            if let error = target.error {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(colors.stateFail)
                    Text(error)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(colors.stateFail)
                        .textSelection(.enabled)
                }
            }

            // Proxy / transcode
            if let report = proxyReport, let proxyURL = report.proxyURL {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: report.proxyErrors.isEmpty ? "film" : "exclamationmark.triangle")
                            .font(.system(size: 10))
                            .foregroundStyle(report.proxyErrors.isEmpty ? colors.textSecondary : Color.orange)
                        Text(L10n.t("转码", "Transcode", language: lang))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1.0)
                            .foregroundStyle(colors.textSecondary)
                        Text("\(report.proxyFilesCreated) \(L10n.t("个", "files", language: lang)) → \(proxyURL.lastPathComponent)/")
                            .font(.system(size: 10, design: .monospaced))
                        Text(proxyURL.deletingLastPathComponent().path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }

                    if !report.proxyErrors.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(report.proxyErrors.prefix(2).enumerated()), id: \.offset) { _, error in
                                Text(compactProxyError(error))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(Color.orange)
                                    .lineLimit(2)
                                    .textSelection(.enabled)
                            }
                            if report.proxyErrors.count > 2 {
                                Text("+\(report.proxyErrors.count - 2) \(L10n.t("条转码错误，详见报告", "more transcode errors, see report", language: lang))")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(colors.textSecondary)
                            }
                        }
                        .padding(.leading, 16)
                    }
                }
            }
        }
        .padding(12)
        .glassOrBackground(colors.surfaceBg, cornerRadius: Theme.panelRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius)
                .strokeBorder(colors.hairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
    }

    private func compactProxyError(_ error: String) -> String {
        error
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: " / ")
    }
}

private struct LaneBar: View {
    let label: String
    let bytes: UInt64
    let total: UInt64
    let progress: Double
    let tint: Color
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(colors.textSecondary)
                Spacer()
                Text("\(formatBytes(bytes)) / \(formatBytes(total))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint.opacity(0.12))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint)
                        .frame(width: max(0, min(1, progress)) * geo.size.width)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Log

private struct LogPanel: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    let logs: [String]

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L10n.t("日志", "Log", language: lang))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(logs.count) \(L10n.t("行", "lines", language: lang))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassOrBackground(colors.panelBg)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if logs.isEmpty {
                            Text(L10n.t("(无日志)", "(No logs)", language: lang))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(colors.textSecondary)
                                .padding(12)
                        } else {
                            ForEach(Array(logs.enumerated()), id: \.offset) { idx, line in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(String(format: "%04d", idx + 1))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(colors.textTertiary)
                                    Text(line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 1.5)
                                .id(idx)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
                .background(colors.inputBg)
                .onChange(of: logs.count) { newCount in
                    if newCount > 0 {
                        withAnimation(.linear(duration: 0.1)) {
                            proxy.scrollTo(newCount - 1, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
}

private struct LaneBarSimple: View {
    let label: String
    let progress: Double
    let tint: Color
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(colors.textSecondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint.opacity(0.12))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(tint)
                        .frame(width: max(0, min(1, progress)) * geo.size.width)
                }
            }
            .frame(height: 4)
        }
    }
}
