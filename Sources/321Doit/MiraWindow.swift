import AppKit
import SwiftUI

@MainActor
final class MiraWindowPresenter: NSObject, NSWindowDelegate {
    static let shared = MiraWindowPresenter()

    private var window: NSWindow?
    private let bridge = OpenCodeBridge()
    private var settings: SettingsStore?

    private override init() {}

    func show(settings: SettingsStore, projectContext: MiraProjectContext?) {
        self.settings = settings
        bridge.setLanguage(settings.settings.general.language)
        let root = MiraWindowView(bridge: bridge, projectContext: projectContext)
            .environmentObject(settings)
            .environment(\.appTheme, settings.settings.general.theme)
            .tint(settings.settings.general.theme.colors(isDark: isSystemDarkAppearance()).accent)
            .preferredColorScheme(colorScheme(for: settings.settings.general.appearance))

        if let window {
            window.contentViewController = NSHostingController(rootView: root)
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 780),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.t("Mira · AI 调度", "Mira · AI Control", language: settings.settings.general.language)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.minSize = NSSize(width: 940, height: 640)
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: root)
            window.center()
            window.makeKeyAndOrderFront(nil)
            self.window = window
            NSApp.activate(ignoringOtherApps: true)
        }

        Task { await bridge.start(projectContext: projectContext) }
    }

    func updateProjectContext(_ context: MiraProjectContext?) {
        guard window?.isVisible == true else { return }
        Task { await bridge.updateProjectContext(context) }
    }

    func hide() {
        window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func shutdown() {
        bridge.shutdown()
        window?.close()
    }

    private func colorScheme(for mode: AppearanceMode) -> ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct MiraWindowView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @ObservedObject var bridge: OpenCodeBridge
    let projectContext: MiraProjectContext?

    @State private var composerText = ""
    @State private var questionSelections: [String: Set<String>] = [:]
    @State private var customQuestionAnswers: [String: String] = [:]
    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private static let miraLogo: NSImage? = {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        return NSImage(contentsOf: resourceURL.appendingPathComponent("Mira/Mira.png"))
    }()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)
                .background(.regularMaterial)
            
            Divider()
                .opacity(0.3)

            conversation
                .background(colors.surfaceBg)
        }
        .frame(minWidth: 940, minHeight: 640)
        .task(id: projectContext) {
            await bridge.updateProjectContext(projectContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .miraProviderCredentialsDidChange)) { _ in
            Task { await bridge.reloadProviderCredentials() }
        }
        .onChange(of: bridge.pendingQuestion?.id) { _ in
            questionSelections = [:]
            customQuestionAnswers = [:]
        }
        .onReceive(NotificationCenter.default.publisher(for: .miraModelServicesDidChange)) { _ in
            Task { await bridge.reloadProviderCredentials() }
        }
        .alert(
            L10n.t("Mira 操作未完成", "Mira Action Could Not Complete", language: lang),
            isPresented: Binding(
                get: { bridge.userFacingError != nil },
                set: { if !$0 { bridge.dismissUserFacingError() } }
            )
        ) {
            Button(L10n.t("好", "OK", language: lang), role: .cancel) {
                bridge.dismissUserFacingError()
            }
        } message: {
            Text(bridge.userFacingError ?? "")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Group {
                    if let logo = Self.miraLogo {
                        Image(nsImage: logo)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.indigo)
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.purple.opacity(0.28), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mira")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(colors.textPrimary)
                    Text(L10n.t("智能制作助理", "Production Agent", language: lang))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(colors.textSecondary)
                }
            }
            .padding(.horizontal, 4)

            Button {
                Task { await bridge.clearSession() }
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                    Text(L10n.t("新建会话", "New Conversation", language: lang))
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(colors.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: colors.accent.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityIdentifier("mira.new-session")

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("当前项目", "CURRENT PROJECT", language: lang))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(colors.textTertiary)
                HStack(spacing: 8) {
                    Image(systemName: projectContext == nil ? "link.badge.plus" : "link")
                        .foregroundStyle(projectContext == nil ? colors.textSecondary : colors.accent)
                    Text(projectContext?.name ?? L10n.t("未连接项目", "No Project Connected", language: lang))
                        .lineLimit(2)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(projectContext == nil ? colors.textSecondary : colors.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.panelBg.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(colors.hairline, lineWidth: 0.5)
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.t("已授权位置", "AUTHORIZED LOCATIONS", language: lang))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(colors.textTertiary)
                    Spacer()
                    Button {
                        chooseAuthorizedFolder()
                    } label: {
                        Label(
                            L10n.t("添加", "Add", language: lang),
                            systemImage: "folder.badge.plus"
                        )
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(colors.accent)
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.t("授权文件夹或磁盘给 Mira", "Authorize a folder or disk for Mira", language: lang))
                }
                if bridge.authorizedRoots.isEmpty {
                    Text(L10n.t("未授权外部位置", "No external locations authorized", language: lang))
                        .font(.system(size: 11))
                        .foregroundStyle(colors.textSecondary)
                } else {
                    ForEach(bridge.authorizedRoots, id: \.path) { root in
                        HStack(spacing: 7) {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                            Text(root.lastPathComponent)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Button {
                                Task { await bridge.removeAuthorizedRoot(root) }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .help(L10n.t("取消授权", "Revoke access", language: lang))
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(colors.textSecondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("历史会话", "CONVERSATIONS", language: lang))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(colors.textTertiary)
                    ScrollView {
                        LazyVStack(spacing: 4) {
                        ForEach(bridge.sessions) { session in
                            HStack(spacing: 0) {
                                Button {
                                    Task { await bridge.selectSession(session.id) }
                                } label: {
                                    HStack {
                                        Image(systemName: "bubble.left")
                                            .font(.system(size: 12))
                                        Text(session.title)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                    .font(.system(size: 12, weight: bridge.currentSessionID == session.id ? .medium : .regular))
                                    .foregroundStyle(bridge.currentSessionID == session.id ? colors.textPrimary : colors.textSecondary)
                                    .padding(.vertical, 8)
                                    .padding(.leading, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .focusable(false)

                                Button {
                                    Task { await bridge.deleteSession(session.id) }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(colors.textSecondary.opacity(0.5))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .help(L10n.t("删除会话", "Delete Session", language: lang))
                            }
                            .background(
                                bridge.currentSessionID == session.id
                                    ? colors.accent.opacity(0.15)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                serviceStatus
                executionPermissionSelector
                modelSelector
                reasoningSelector
            }
        }
        .padding(.top, 40)
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    private func modelButton(_ model: MiraModelOption) -> some View {
        Button {
            Task { await bridge.selectModel(model.id) }
        } label: {
            if bridge.selectedModelID == model.id {
                Label(model.name, systemImage: "checkmark")
            } else {
                Text(model.name)
            }
        }
    }

    private var modelSelector: some View {
        Menu {
            // Zen and Go are two ways of using OpenCode. Keep both visible
            // even before the user signs in, instead of making the menu look
            // as though the free catalog is the only supported service.
            modelGroup(
                title: "OpenCode Zen",
                models: zenModels,
                emptyText: L10n.t("免费模型", "Free models", language: lang)
            )

            modelGroup(
                title: "OpenCode Go",
                models: goModels,
                emptyText: L10n.t(
                    "输入 Go API Key 后显示订阅模型",
                    "Enter your Go API key to show subscription models",
                    language: lang
                ),
                emptyActionTitle: L10n.t("登录或输入 Go API Key…", "Sign In or Enter Go API Key…", language: lang),
                emptyAction: openModelSettings
            )

            Divider()

            Menu(L10n.t("选择你自己的大模型", "Use Your Own Model", language: lang)) {
                if customModels.isEmpty {
                    Text(L10n.t(
                        "尚未配置自定义 API",
                        "No custom API configured",
                        language: lang
                    ))
                    Button(L10n.t("配置自定义 API…", "Configure Custom API…", language: lang)) {
                        openModelSettings()
                    }
                } else {
                    ForEach(customModels) { model in
                        modelButton(model)
                    }
                    Divider()
                    Button(L10n.t("管理自定义 API…", "Manage Custom API…", language: lang)) {
                        openModelSettings()
                    }
                }
            }

            let otherProviders = bridge.modelProviders.filter { provider in
                provider.id != "opencode"
                    && provider.id != "opencode-go"
                    && provider.id != customProviderID
            }
            if !otherProviders.isEmpty {
                Divider()
                ForEach(otherProviders) { provider in
                    modelGroup(title: provider.name, models: provider.models)
                }
            }

            Divider()
            Button(L10n.t("管理模型服务…", "Manage Model Services…", language: lang)) {
                openModelSettings()
            }
        } label: {
            selectorLabel(
                symbol: "cpu",
                title: L10n.t("模型", "Model", language: lang),
                value: bridge.currentModelName
            )
        }
        .menuStyle(.borderlessButton)
        .help(L10n.t("选择模型、同步 OpenCode Go 或配置自定义 API", "Choose a model, sync OpenCode Go, or configure a custom API", language: lang))
    }

    @ViewBuilder
    private func modelGroup(
        title: String,
        models: [MiraModelOption],
        emptyText: String? = nil,
        emptyActionTitle: String? = nil,
        emptyAction: (() -> Void)? = nil
    ) -> some View {
        Menu(title) {
            if models.isEmpty {
                if let emptyText {
                    Text(emptyText)
                }
                if let emptyActionTitle, let emptyAction {
                    Button(emptyActionTitle, action: emptyAction)
                }
            } else {
                ForEach(models) { model in
                    modelButton(model)
                }
            }
        }
    }

    private var openCodeZenModels: [MiraModelOption] {
        bridge.modelProviders.first(where: { $0.id == "opencode" })?.models ?? []
    }

    private var zenModels: [MiraModelOption] {
        openCodeZenModels
    }

    private var goModels: [MiraModelOption] {
        bridge.modelProviders.first(where: { $0.id == "opencode-go" })?.models ?? []
    }

    private var customProviderID: String {
        MiraCustomModelServiceStore.load().providerID
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var customModels: [MiraModelOption] {
        bridge.modelProviders.first(where: { $0.id == customProviderID })?.models ?? []
    }

    private func syncLocalOpenCodeCredentials() {
        do {
            _ = try OpenCodeBridge.syncExistingProviderCredentials(language: lang)
        } catch {
            bridge.presentUserFacingError(error.localizedDescription)
        }
    }

    private func openModelSettings() {
        SettingsWindowPresenter.shared.show(settings: settings, initialSection: .about)
    }

    private var executionPermissionSelector: some View {
        Menu {
            Button {
                Task { await bridge.selectExecutionPermissionMode(.automatic) }
            } label: {
                if bridge.executionPermissionMode == .automatic {
                    Label(L10n.t("全自动", "Automatic", language: lang), systemImage: "checkmark")
                } else {
                    Text(L10n.t("全自动", "Automatic", language: lang))
                }
            }
            Button {
                Task { await bridge.selectExecutionPermissionMode(.confirmEveryWrite) }
            } label: {
                if bridge.executionPermissionMode == .confirmEveryWrite {
                    Label(L10n.t("妈宝模式", "Confirm Every Write", language: lang), systemImage: "checkmark")
                } else {
                    Text(L10n.t("妈宝模式", "Confirm Every Write", language: lang))
                }
            }
        } label: {
            selectorLabel(
                symbol: bridge.executionPermissionMode == .automatic ? "bolt.shield" : "lock.shield",
                title: L10n.t("权限", "Permission", language: lang),
                value: bridge.executionPermissionMode == .automatic
                    ? L10n.t("全自动", "Automatic", language: lang)
                    : L10n.t("妈宝模式", "Confirm Every Write", language: lang)
            )
        }
        .menuStyle(.borderlessButton)
        .help(bridge.executionPermissionMode == .automatic
            ? L10n.t("321Doit 工具可自动执行；仍受授权目录和工具校验限制", "321Doit tools run automatically within authorized locations and tool safeguards", language: lang)
            : L10n.t("Mira 每次写入或执行前都会弹出确认", "Mira asks before every write or execution", language: lang))
        .accessibilityIdentifier("mira.execution-permission-mode")
    }

    private var reasoningSelector: some View {
        Menu {
            Button {
                Task { await bridge.selectReasoningVariant(nil) }
            } label: {
                if bridge.selectedReasoningVariantID == nil {
                    Label(L10n.t("模型默认", "Model default", language: lang), systemImage: "checkmark")
                } else {
                    Text(L10n.t("模型默认", "Model default", language: lang))
                }
            }
            if !bridge.currentModelVariants.isEmpty {
                Divider()
                ForEach(bridge.currentModelVariants) { variant in
                    Button {
                        Task { await bridge.selectReasoningVariant(variant.id) }
                    } label: {
                        if bridge.selectedReasoningVariantID == variant.id {
                            Label(reasoningName(variant), systemImage: "checkmark")
                        } else {
                            Text(reasoningName(variant))
                        }
                    }
                }
            }
        } label: {
            selectorLabel(
                symbol: "brain.head.profile",
                title: L10n.t("思考", "Reasoning", language: lang),
                value: selectedReasoningName
            )
        }
        .menuStyle(.borderlessButton)
        .disabled(bridge.currentModelVariants.isEmpty)
        .help(
            bridge.currentModelVariants.isEmpty
                ? L10n.t("当前模型没有可选的思考级别", "This model has no selectable reasoning levels", language: lang)
                : L10n.t("选择当前模型支持的思考级别", "Choose a reasoning level supported by this model", language: lang)
        )
    }

    private func selectorLabel(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .frame(width: 18, alignment: .center)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(colors.textTertiary)
                Text(value)
                    .lineLimit(1)
                    .font(.system(size: 11, weight: .medium))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9))
                .frame(width: 12, alignment: .center)
        }
        .foregroundStyle(colors.textSecondary)
        .padding(8)
        .background(colors.panelBg.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var selectedReasoningName: String {
        guard let id = bridge.selectedReasoningVariantID,
              let variant = bridge.currentModelVariants.first(where: { $0.id == id }) else {
            return L10n.t("模型默认", "Model default", language: lang)
        }
        return reasoningName(variant)
    }

    private func reasoningName(_ variant: MiraModelVariant) -> String {
        switch variant.id.lowercased() {
        case "none": return L10n.t("不启用", "None", language: lang)
        case "minimal": return L10n.t("极低", "Minimal", language: lang)
        case "low": return L10n.t("低", "Low", language: lang)
        case "medium": return L10n.t("中", "Medium", language: lang)
        case "high": return L10n.t("高", "High", language: lang)
        case "xhigh": return L10n.t("超高", "Extra high", language: lang)
        case "max": return L10n.t("最高", "Maximum", language: lang)
        default: return variant.id
        }
    }

    private var serviceStatus: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(serviceColor)
                .frame(width: 7, height: 7)
            Text(serviceLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(colors.textSecondary)
            Spacer()
            if case .failed = bridge.state {
                Button(L10n.t("重试", "Retry", language: lang)) {
                    Task { await bridge.retry() }
                }
                .buttonStyle(.link)
                .font(.system(size: 10))
            }
        }
        .accessibilityIdentifier("mira.service-status")
    }

    private func chooseAuthorizedFolder() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("授权位置给 Mira", "Authorize a Location for Mira", language: lang)
        panel.message = L10n.t(
            "Mira 只能访问你在这里明确授权的文件夹或磁盘。",
            "Mira can access only folders or disks you explicitly authorize here.",
            language: lang
        )
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.t("授权", "Authorize", language: lang)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await bridge.addAuthorizedRoot(url) }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("AI 调度", "AI Orchestration", language: lang))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text(projectContext == nil
                        ? L10n.t("可在已授权位置中跨项目规划并执行任务", "Plan and execute across projects in authorized locations", language: lang)
                        : L10n.t("Mira 只操作当前明确连接的项目", "Mira is scoped to the explicitly connected project", language: lang))
                        .font(.system(size: 11))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                if bridge.isRunning {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(L10n.t("正在思考", "Thinking", language: lang))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(colors.accent)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(colors.accent.opacity(0.1))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(colors.surfaceBg.opacity(0.85))
            .overlay(Divider().opacity(0.3), alignment: .bottom)

            VStack(spacing: 0) {
                if case .failed(let message) = bridge.state {
                    failureView(message)
                } else if bridge.messages.isEmpty {
                    emptyConversation
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(bridge.messages) { message in
                                    messageView(message)
                                        .id(message.id)
                                }
                                if let permission = bridge.pendingPermission {
                                    permissionCard(permission)
                                        .id("permission-\(permission.id)")
                                }
                                if let question = bridge.pendingQuestion {
                                    questionCard(question)
                                        .id("question-\(question.id)")
                                }
                                Color.clear.frame(height: 24)
                            }
                            .padding(24)
                            .frame(maxWidth: 840)
                            .frame(maxWidth: .infinity)
                        }
                        .clipped()
                        .onChange(of: bridge.messages) { messages in
                            if let last = messages.last {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0.0),
                                .init(color: .black, location: 0.95),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                
                composer
                    .padding(.bottom, 24)
            }
        }
    }

    private var emptyConversation: some View {
        VStack(spacing: 24) {
            Spacer()
            Group {
                if let logo = Self.miraLogo {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(colors.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.indigo.opacity(0.15))
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Color.purple.opacity(0.24), radius: 18, x: 0, y: 8)
            VStack(spacing: 8) {
                Text(L10n.t("今天想完成什么？", "What do you want to accomplish today?", language: lang))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(L10n.t(
                    "Mira 可以协助你查询项目、整理场记、编写分镜、或执行媒体转换任务。",
                    "Mira can help you query projects, organize takes, write storyboards, or execute media conversions.",
                    language: lang
                ))
                .multilineTextAlignment(.center)
                .font(.system(size: 13))
                .foregroundStyle(colors.textSecondary)
                .padding(.horizontal, 40)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(colors.stateWarning)
            Text(L10n.t("Mira 暂时无法启动", "Mira Could Not Start", language: lang))
                .font(.system(size: 18, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            Button(L10n.t("重新连接", "Retry Connection", language: lang)) {
                Task { await bridge.retry() }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func messageView(_ message: MiraMessage) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user { Spacer(minLength: 40) }

            if message.role == .thinking {
                thinkingView(message)
                Spacer(minLength: 40)
            } else if message.role == .tool {
                toolCardView(message)
                Spacer(minLength: 40)
            } else if message.role == .user {
                Text(message.text)
                    .textSelection(.enabled)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [colors.accent, colors.accent.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: colors.accent.opacity(0.15), radius: 4, x: 0, y: 2)
            } else {
                MiraRichText(message.text)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.textPrimary)
                    .lineSpacing(4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(colors.hairline.opacity(0.6), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
                if message.role != .user { Spacer(minLength: 40) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func thinkingView(_ message: MiraMessage) -> some View {
        DisclosureGroup {
            Text(message.text)
                .font(.system(size: 11))
                .foregroundStyle(colors.textSecondary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.purple.opacity(0.7))
                Text(L10n.t("思考过程", "Thinking", language: lang))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.purple.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.purple.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func toolCardView(_ message: MiraMessage) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                if let toolName = message.toolName {
                    Text(toolName)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(colors.accent.opacity(0.7))
                }

                if let input = message.toolInput, !input.isEmpty {
                    toolDetail(
                        L10n.t("输入", "Input", language: lang),
                        value: input,
                        color: colors.textSecondary
                    )
                }

                if let output = message.toolOutput, !output.isEmpty {
                    toolDetail(
                        message.toolStatus == "error" || message.toolStatus == "failed"
                            ? L10n.t("失败原因", "Failure reason", language: lang)
                            : L10n.t("结果", "Result", language: lang),
                        value: output,
                        color: message.toolStatus == "error" || message.toolStatus == "failed"
                            ? colors.stateFail
                            : colors.textSecondary
                    )
                }
            }
            .padding(.top, 5)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: message.toolStatus == "completed" ? "checkmark.circle.fill" : "gearshape.2")
                    .font(.system(size: 12))
                    .foregroundStyle(message.toolStatus == "completed" ? colors.stateSuccess : colors.accent)
                Text(message.text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colors.textPrimary)
                if bridge.isRunning && message.toolStatus != "completed" && message.toolStatus != "error" {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(colors.inputBg.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(colors.hairline.opacity(0.5), lineWidth: 0.5)
        )
    }

    private func toolDetail(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(colors.textTertiary)
            Text(String(value.prefix(300)))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(4)
        }
        .padding(.top, 2)
    }

    private func permissionCard(_ permission: MiraPermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(permission.title, systemImage: "lock.shield")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(colors.stateWarning)
            if let projectContext {
                Text(L10n.t("项目：", "Project: ", language: lang) + projectContext.name)
                    .font(.system(size: 11, weight: .medium))
            }
            Text(permission.detail)
                .font(.system(size: 11))
                .foregroundStyle(colors.textSecondary)
                .lineLimit(5)
            Label(
                permission.reversible
                    ? L10n.t("此操作可恢复或保留审计记录", "This operation is recoverable or audited", language: lang)
                    : L10n.t("此操作不可撤销", "This operation cannot be undone", language: lang),
                systemImage: permission.reversible ? "arrow.uturn.backward.circle" : "exclamationmark.octagon"
            )
            .font(.system(size: 10))
            HStack {
                Button(L10n.t("仅允许本次", "Allow Once", language: lang)) {
                    Task { await bridge.answerPermission(allow: true) }
                }
                .buttonStyle(.borderedProminent)
                Button(L10n.t("取消", "Reject", language: lang)) {
                    Task { await bridge.answerPermission(allow: false) }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(colors.stateWarning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(colors.stateWarning.opacity(0.35), lineWidth: 1)
        )
        .accessibilityIdentifier("mira.permission-card")
    }

    private func questionCard(_ request: MiraQuestionRequest) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                L10n.t("需要你确认", "Your Input Is Needed", language: lang),
                systemImage: "questionmark.bubble"
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(colors.accent)

            ForEach(request.questions) { question in
                VStack(alignment: .leading, spacing: 9) {
                    Text(question.header)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                    Text(question.prompt)
                        .font(.system(size: 11))
                        .foregroundStyle(colors.textSecondary)

                    ForEach(question.options) { option in
                        let isSelected = questionSelections[question.id, default: []].contains(option.label)
                        Button {
                            toggleQuestionOption(option.label, for: question)
                        } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: isSelected
                                    ? (question.allowsMultipleSelection ? "checkmark.square.fill" : "largecircle.fill.circle")
                                    : (question.allowsMultipleSelection ? "square" : "circle"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(isSelected ? colors.accent : colors.textTertiary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.label)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(colors.textPrimary)
                                    if !option.detail.isEmpty {
                                        Text(option.detail)
                                            .font(.system(size: 10))
                                            .foregroundStyle(colors.textSecondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(isSelected ? colors.accent.opacity(0.1) : colors.inputBg.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(isSelected ? colors.accent.opacity(0.45) : colors.hairline.opacity(0.5), lineWidth: 0.6)
                            )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }

                    // A question must always have a place for a human answer.
                    // Some providers omit `allowsCustomAnswer` even when the
                    // assistant asks an open-ended follow-up; showing this
                    // field unconditionally keeps that conversation usable.
                    TextField(
                        question.allowsCustomAnswer
                            ? L10n.t("输入其他答案", "Enter another answer", language: lang)
                            : L10n.t("输入你的回答", "Type your answer", language: lang),
                        text: Binding(
                            get: { customQuestionAnswers[question.id, default: ""] },
                            set: { customQuestionAnswers[question.id] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                }
            }

            HStack {
                Button(L10n.t("继续", "Continue", language: lang)) {
                    Task { await bridge.answerQuestion(answers: answers(for: request)) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAnswer(request))

                Button(L10n.t("暂不回答", "Skip", language: lang)) {
                    Task { await bridge.rejectQuestion() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(colors.accent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(colors.accent.opacity(0.3), lineWidth: 1)
        )
        .accessibilityIdentifier("mira.question-card")
    }

    private func toggleQuestionOption(_ option: String, for question: MiraQuestion) {
        var selection = questionSelections[question.id, default: []]
        if question.allowsMultipleSelection {
            if selection.contains(option) {
                selection.remove(option)
            } else {
                selection.insert(option)
            }
        } else {
            selection = selection == [option] ? [] : [option]
        }
        questionSelections[question.id] = selection
    }

    private func canAnswer(_ request: MiraQuestionRequest) -> Bool {
        request.questions.allSatisfy { question in
            !questionSelections[question.id, default: []].isEmpty
                || !customQuestionAnswers[question.id, default: ""]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
        }
    }

    private func answers(for request: MiraQuestionRequest) -> [[String]] {
        request.questions.map { question in
            var answer = questionSelections[question.id, default: []].sorted()
            let custom = customQuestionAnswers[question.id, default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !custom.isEmpty { answer.append(custom) }
            return answer
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                MiraComposerTextView(text: $composerText) { submittedText in
                    send(submittedText)
                }
                .frame(minHeight: 38, maxHeight: 110)
                .padding(.vertical, 8)
                .padding(.leading, 14)

                if bridge.isRunning {
                    Button {
                        Task { await bridge.stop() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(colors.stateFail)
                            .frame(width: 30, height: 30)
                            .background(colors.stateFail.opacity(0.12))
                            .clipShape(Circle())
                            .overlay(
                                Circle().strokeBorder(colors.stateFail.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .padding(.bottom, 8)
                    .padding(.trailing, 8)
                    .accessibilityIdentifier("mira.stop")
                } else {
                    Button {
                        send(composerText)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .background(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isConnected ? colors.accent.opacity(0.5) : colors.accent)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                    .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isConnected)
                    .padding(.bottom, 8)
                    .padding(.trailing, 8)
                    .accessibilityIdentifier("mira.send")
                }
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(colors.hairline.opacity(0.8), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)

            HStack {
                Label(
                    projectContext == nil
                        ? L10n.t("未附加项目", "No project attached", language: lang)
                        : L10n.t("已附加当前项目", "Current project attached", language: lang),
                    systemImage: projectContext == nil ? "paperclip" : "checkmark.circle.fill"
                )
                .foregroundStyle(projectContext == nil ? colors.textSecondary : colors.accent)
                
                Spacer()
                
                Text(L10n.t(
                    "回车发送 · Shift+回车换行",
                    "Return to send · Shift+Return for newline",
                    language: lang
                ))
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(colors.textSecondary)
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, 40)
    }

    private func send(_ submittedText: String) {
        let text = submittedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, isConnected, !bridge.isRunning else { return }
        composerText = ""
        Task { await bridge.send(text) }
    }

    private var isConnected: Bool {
        if case .connected = bridge.state { return true }
        return false
    }

    private var serviceColor: Color {
        switch bridge.state {
        case .connected: return colors.stateSuccess
        case .starting: return colors.stateRunning
        case .failed: return colors.stateFail
        case .stopped: return colors.textTertiary
        }
    }

    private var serviceLabel: String {
        switch bridge.state {
        case .connected(let version):
            return L10n.t("Mira 已连接 · \(version)", "Mira connected · \(version)", language: lang)
        case .starting:
            return L10n.t("正在启动 Mira", "Starting Mira", language: lang)
        case .failed:
            return L10n.t("连接失败", "Connection failed", language: lang)
        case .stopped:
            return L10n.t("服务已停止", "Service stopped", language: lang)
        }
    }
}
