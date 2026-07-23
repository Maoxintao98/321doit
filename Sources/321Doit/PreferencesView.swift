import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Section enumeration

enum PrefSection: String, CaseIterable, Identifiable {
    case general
    case projectTemplate
    case copyVerify
    case checksum
    case report
    case transcode
    case ffmpeg
    case lut
    case handoff
    case shortcuts
    case safety
    case performance
    case notification
    case logs
    case about

    var id: String { rawValue }

    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .general:         return L10n.t("通用", "General", language: lang)
        case .projectTemplate: return L10n.t("拷卡默认值", "Offload Defaults", language: lang)
        case .copyVerify:      return L10n.t("拷贝与校验", "Copy & Verify", language: lang)
        case .checksum:        return L10n.t("校验设置", "Checksum", language: lang)
        case .report:          return L10n.t("报告", "Reports", language: lang)
        case .transcode:       return L10n.t("代理与转码", "Proxy & Transcode", language: lang)
        case .ffmpeg:          return "FFmpeg"
        case .lut:             return L10n.t("LUT 与色彩", "LUT & Color", language: lang)
        case .handoff:         return L10n.t("后期交接", "Post Handoff", language: lang)
        case .shortcuts:       return L10n.t("快捷键", "Shortcuts", language: lang)
        case .safety:          return L10n.t("磁盘与安全", "Storage Safety", language: lang)
        case .performance:     return L10n.t("性能", "Performance", language: lang)
        case .notification:    return L10n.t("通知", "Notifications", language: lang)
        case .logs:            return L10n.t("日志与诊断", "Logs & Diagnostics", language: lang)
        case .about:           return L10n.t("更新与关于", "Updates & About", language: lang)
        }
    }

    var symbol: String {
        switch self {
        case .general:         return "gearshape"
        case .projectTemplate: return "doc.badge.gearshape"
        case .copyVerify:      return "arrow.triangle.branch"
        case .checksum:        return "checkmark.shield"
        case .report:          return "doc.richtext"
        case .transcode:       return "film"
        case .ffmpeg:          return "terminal"
        case .lut:             return "camera.filters"
        case .handoff:         return "shippingbox"
        case .shortcuts:       return "keyboard"
        case .safety:          return "lock.shield"
        case .performance:     return "speedometer"
        case .notification:    return "bell"
        case .logs:            return "list.bullet.clipboard"
        case .about:           return "info.circle"
        }
    }
}

// MARK: - Root preferences container

struct PreferencesView: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors
    @Environment(\.appTheme) private var theme
    @State private var selection: PrefSection = .general

    init(initialSelection: PrefSection = .general) {
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationSplitView {
            List(PrefSection.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label(section.label(store.settings.general.language), systemImage: section.symbol)
                }
            }
            .listStyle(.sidebar)
            .tint(colors.accent)
            .accentColor(colors.accent)
            .frame(minWidth: 220)
            .navigationTitle(L10n.t("首选项", "Preferences", language: store.settings.general.language))
        } detail: {
            ScrollView {
                content
                    .padding(20)
                    .frame(maxWidth: 640, alignment: .leading)
            }
            .frame(minWidth: 560)
            .frame(minWidth: 560)
            .background(colors.surfaceBg)
        }
        .frame(minWidth: 820, minHeight: 600)
        .toolbar { toolbarContent }
        .tint(colors.accent)
        .accentColor(colors.accent)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general:         GeneralPane()
        case .projectTemplate: ProjectTemplatePane()
        case .copyVerify:      CopyVerifyPane()
        case .checksum:        ChecksumPane()
        case .report:          ReportPane()
        case .transcode:       TranscodePane()
        case .ffmpeg:          FFmpegPane()
        case .lut:             LUTPane()
        case .handoff:         HandoffPane()
        case .shortcuts:       ShortcutsPane()
        case .safety:          StorageSafetyPane()
        case .performance:     PerformancePane()
        case .notification:    NotificationPane()
        case .logs:            LogsPane()
        case .about:           AboutPane()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                runImport()
            } label: {
                Label(L10n.t("导入", "Import", language: store.settings.general.language), systemImage: "square.and.arrow.down")
            }
            Button {
                runExport()
            } label: {
                Label(L10n.t("导出", "Export", language: store.settings.general.language), systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                confirmReset()
            } label: {
                Label(L10n.t("恢复默认", "Reset", language: store.settings.general.language), systemImage: "arrow.uturn.backward")
            }
        }
    }

    private func runImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            guard confirmImport() else { return }
            do {
                try store.importJSON(from: url)
            } catch {
                presentError(L10n.t("导入失败", "Import failed", language: store.settings.general.language), error)
            }
        }
    }

    private func runExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = OutputFileNamer.fileName(
            projectName: "321Doit",
            date: Date(),
            attribute: L10n.t("设置", "Settings", language: store.settings.general.language),
            extension: "json"
        )
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try store.exportJSON(to: url)
            } catch {
                presentError(L10n.t("导出失败", "Export failed", language: store.settings.general.language), error)
            }
        }
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.messageText = L10n.t("恢复全部默认设置？", "Reset all settings to defaults?", language: store.settings.general.language)
        alert.informativeText = L10n.t(
            "你将丢失当前所有自定义设置，此操作无法撤销。",
            "You will lose all custom settings. This cannot be undone.",
            language: store.settings.general.language
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.t("恢复默认", "Reset", language: store.settings.general.language))
        alert.addButton(withTitle: L10n.t("取消", "Cancel", language: store.settings.general.language))
        if alert.runModal() == .alertFirstButtonReturn {
            store.resetToDefaults()
        }
    }

    private func confirmImport() -> Bool {
        let alert = NSAlert()
        alert.messageText = L10n.t("导入设置并覆盖当前设置？", "Import settings and replace current settings?", language: store.settings.general.language)
        alert.informativeText = L10n.t(
            "321Doit 会先检查 app 与 schemaVersion。导入失败不会改变当前设置。",
            "321Doit checks app and schemaVersion first. A failed import will not change current settings.",
            language: store.settings.general.language
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.t("导入", "Import", language: store.settings.general.language))
        alert.addButton(withTitle: L10n.t("取消", "Cancel", language: store.settings.general.language))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

// MARK: - Reusable layout

struct PrefHeader: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.appTheme) private var theme
    let title_zh: String
    let title_en: String
    let subtitle_zh: String
    let subtitle_en: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.t(title_zh, title_en, language: store.settings.general.language))
                .font(.system(size: 20, weight: .semibold))
            Text(L10n.t(subtitle_zh, subtitle_en, language: store.settings.general.language))
                .font(.system(size: 12))
        }
    }
}

struct PrefGroup<Content: View>: View {
    let title_zh: String
    let title_en: String
    @ViewBuilder let content: () -> Content
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t(title_zh, title_en, language: store.settings.general.language))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(colors.sectionHeader)
            
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(14)
            .background(colors.panelBg)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(colors.hairline, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct PathPickerRow: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors
    let title_zh: String
    let title_en: String
    @Binding var path: String
    var allowsFiles: Bool = false

    func pick() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = !allowsFiles
        panel.canChooseFiles = allowsFiles
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            SecurityScopedBookmarks.save(url: url, role: allowsFiles ? "filePreference" : "folderPreference")
            path = url.path
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(L10n.t(title_zh, title_en, language: store.settings.general.language))
                .font(.system(size: 11))
                .frame(width: 120, alignment: .leading)
            
            HStack(spacing: 8) {
                Text(path.isEmpty 
                 ? L10n.t("未设置", "Not set", language: store.settings.general.language)
                 : path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(path.isEmpty ? colors.textSecondary : colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(colors.inputBg)
            .cornerRadius(6)
            .onTapGesture { pick() }
            
            Button(L10n.t("选择", "Pick", language: store.settings.general.language)) { pick() }
                .controlSize(.small)
        }
    }
}

struct DangerToggle: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors
    let title_zh: String
    let title_en: String
    let detail_zh: String
    let detail_en: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 6) {
                    if isOn {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.orange)
                    }
                    Text(L10n.t(title_zh, title_en, language: store.settings.general.language))
                        .font(.system(size: 12))
                }
            }
            Text(L10n.t(detail_zh, detail_en, language: store.settings.general.language))
                .font(.system(size: 10))
                .foregroundStyle(colors.textSecondary)
                .padding(.leading, 22)
        }
        .padding(8)
        .background(isOn ? Color.orange.opacity(0.08) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isOn ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private func bilingual(_ value: (String, String), _ lang: AppLanguage) -> String {
    L10n.t(value.0, value.1, language: lang)
}

// MARK: - General

private struct GeneralPane: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PrefHeader(
                title_zh: "通用", title_en: "General",
                subtitle_zh: "界面、语言与启动行为",
                subtitle_en: "Appearance, language and startup behavior"
            )

            PrefGroup(title_zh: "语言与外观", title_en: "LANGUAGE & APPEARANCE") {
                Picker(L10n.t("语言", "Language", language: store.settings.general.language),
                       selection: store.binding(\.general.language)) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName(language: store.settings.general.language)).tag(lang)
                    }
                }
                Picker(L10n.t("界面主题", "Appearance", language: store.settings.general.language),
                       selection: store.binding(\.general.appearance)) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(bilingual(mode.label, store.settings.general.language)).tag(mode)
                    }
                }
            }

            PrefGroup(title_zh: "启动行为", title_en: "STARTUP") {
                Toggle(L10n.t("显示项目管理器功能介绍", "Show feature overview in Project Manager", language: store.settings.general.language),
                       isOn: store.binding(\.general.showProjectManagerCapabilities))
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors

    private var lang: AppLanguage { store.settings.general.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PrefHeader(
                title_zh: "快捷键",
                title_en: "Shortcuts",
                subtitle_zh: "场记盲操按键映射",
                subtitle_en: "Script log keyboard mappings"
            )

            PrefGroup(title_zh: "场记", title_en: "SCRIPT LOG") {
                ForEach(ScriptLogShortcutAction.allCases) { action in
                    ShortcutEditorRow(
                        title: action.title(language: lang),
                        command: shortcutBinding(for: action)
                    )
                    if action != .undo {
                        Divider()
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        store.settings.shortcuts = ScriptLogShortcutSettings()
                    } label: {
                        Label(L10n.t("恢复默认快捷键", "Restore Default Shortcuts", language: lang), systemImage: "arrow.uturn.backward")
                    }
                    .controlSize(.small)
                }
                .padding(.top, 4)
            }

            PrefGroup(title_zh: "导航与项目", title_en: "NAVIGATION & PROJECT") {
                StaticShortcutRow(
                    title: L10n.t("上一条", "Previous Take", language: lang),
                    shortcut: "←"
                )
                Divider()
                StaticShortcutRow(
                    title: L10n.t("下一条", "Next Take", language: lang),
                    shortcut: "→"
                )
                Divider()
                StaticShortcutRow(
                    title: L10n.t("上一镜", "Previous Shot", language: lang),
                    shortcut: "↑"
                )
                Divider()
                StaticShortcutRow(
                    title: L10n.t("下一镜", "Next Shot", language: lang),
                    shortcut: "↓"
                )
                Divider()
                StaticShortcutRow(
                    title: L10n.t("保存工程", "Save Project", language: lang),
                    shortcut: "Command + S"
                )
                Divider()
                StaticShortcutRow(
                    title: L10n.t("新建工程", "New Project", language: lang),
                    shortcut: "Command + N"
                )
                Divider()
                StaticShortcutRow(
                    title: L10n.t("打开工程", "Open Project", language: lang),
                    shortcut: "Command + O"
                )
            }
        }
    }

    private func shortcutBinding(for action: ScriptLogShortcutAction) -> Binding<ShortcutCommand> {
        Binding(
            get: { store.settings.shortcuts[action] },
            set: { store.settings.shortcuts[action] = $0 }
        )
    }
}

private struct StaticShortcutRow: View {
    @Environment(\.themeColors) private var colors

    let title: String
    let shortcut: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 150, alignment: .leading)

            Spacer()

            Text(shortcut)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(colors.textSecondary)
                .lineLimit(1)
                .frame(width: 130, alignment: .trailing)
        }
    }
}

private struct ShortcutEditorRow: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors

    let title: String
    @Binding var command: ShortcutCommand

    private var lang: AppLanguage { store.settings.general.language }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 150, alignment: .leading)

            Picker(L10n.t("按键", "Key", language: lang), selection: $command.key) {
                ForEach(ShortcutKey.allCases) { key in
                    Text(key.label).tag(key)
                }
            }
            .labelsHidden()
            .frame(width: 96)

            HStack(spacing: 6) {
                modifierButton("⌃", isOn: $command.control, help: "Control")
                modifierButton("⌥", isOn: $command.option, help: "Option")
                modifierButton("⇧", isOn: $command.shift, help: "Shift")
                modifierButton("⌘", isOn: $command.command, help: "Command")
            }

            Spacer()

            Text(command.displayName)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(colors.textSecondary)
                .lineLimit(1)
                .frame(width: 130, alignment: .trailing)
        }
    }

    private func modifierButton(_ title: String, isOn: Binding<Bool>, help: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 24)
        }
        .buttonStyle(.plain)
        .background(isOn.wrappedValue ? colors.accent.opacity(0.22) : colors.inputBg)
        .foregroundStyle(isOn.wrappedValue ? colors.accent : colors.textSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isOn.wrappedValue ? colors.accent.opacity(0.65) : colors.hairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .help(help)
    }
}

// MARK: - Project template

private struct ProjectTemplatePane: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PrefHeader(
                title_zh: "拷卡默认值", title_en: "Offload Defaults",
                subtitle_zh: "新建拷卡任务时自动填写的默认项目名",
                subtitle_en: "Default project name for new offload tasks"
            )

            PrefGroup(title_zh: "任务信息", title_en: "TASK INFO") {
                LabeledContent(L10n.t("项目名", "Project name", language: store.settings.general.language)) {
                    TextField("", text: store.binding(\.projectTemplate.defaultProjectName)).textFieldStyle(.roundedBorder)
                }
                Text(L10n.t(
                    "其他项目元数据由项目管理器维护；卡号、操作员、摄影机和输出包在每个任务中单独确认。",
                    "Other project metadata lives in Project Manager; card, operator, camera and package options are confirmed per task.",
                    language: store.settings.general.language
                ))
                .font(.system(size: 10))
                .foregroundStyle(colors.textSecondary)
            }
        }
    }
}

// MARK: - Copy & Verify

private struct CopyVerifyPane: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PrefHeader(
                title_zh: "拷贝与校验", title_en: "Copy & Verify",
                subtitle_zh: "默认偏保守 — 任何静默覆盖都需要主动开启",
                subtitle_en: "Defaults are conservative — silent overwrites are opt-in"
            )

            PrefGroup(title_zh: "目标盘", title_en: "TARGETS") {
                Label(
                    L10n.t("支持 1–3 个目标盘；开始前固定检查容量、格式和物理卷", "Supports 1–3 destinations; capacity, format, and physical volume are always checked", language: store.settings.general.language),
                    systemImage: "externaldrive.badge.checkmark"
                )
                .font(.system(size: 12, weight: .semibold))
            }

            PrefGroup(title_zh: "文件处理", title_en: "FILE HANDLING") {
                Label(
                    L10n.t("每个目标盘生成一份安全母版", "One verified master per destination", language: store.settings.general.language),
                    systemImage: "checkmark.shield"
                )
                .font(.system(size: 12, weight: .semibold))
                Text(L10n.t("固定保留文件夹结构与时间戳，跳过 macOS 垃圾文件，并且绝不静默覆盖已有目录。",
                            "Folder structure and timestamps are always preserved, macOS junk is skipped, and existing folders are never silently overwritten.",
                            language: store.settings.general.language))
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)

                Toggle(L10n.t("严格断点续传（强制重新校验现有文件）", "Strict resume: re-hash all existing files", language: store.settings.general.language),
                       isOn: store.binding(\.copyVerify.strictResume))

                Stepper(value: store.binding(\.copyVerify.ioRetryCount), in: 0...8) {
                    Text(L10n.t("I/O 写入失败自动重试次数：\(store.settings.copyVerify.ioRetryCount)",
                                "Auto-retry I/O writes: \(store.settings.copyVerify.ioRetryCount)",
                                language: store.settings.general.language))
                }
                
                Text(L10n.t("开启后，断点续传会重新计算来源和目标 hash；同名输出目录无 session.json 时仍会阻止覆盖。",
                            "When enabled, resume re-hashes both source and destination files; matching output folders without session.json are still blocked.",
                            language: store.settings.general.language))
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)
            }
        }
    }
}

// MARK: - Checksum

private struct ChecksumPane: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PrefHeader(
                title_zh: "校验设置", title_en: "Checksum",
                subtitle_zh: "选择实际用于源端读取与目标端读回比对的校验算法",
                subtitle_en: "Choose the checksum used for source-read and target-readback verification"
            )

            PrefGroup(title_zh: "算法与策略", title_en: "ALGORITHM & POLICY") {
                Picker(L10n.t("默认校验算法", "Default algorithm", language: store.settings.general.language),
                       selection: store.binding(\.checksum.algorithm)) {
                    ForEach(ChecksumAlgorithm.allCases) { algo in
                        Text(bilingual(algo.label, store.settings.general.language)).tag(algo)
                    }
                }
                if store.settings.checksum.algorithm == .xxhash64 {
                    Picker(L10n.t("xxHash64 实现", "xxHash64 implementation", language: store.settings.general.language),
                           selection: store.binding(\.checksum.xxHash64Implementation)) {
                        ForEach(XXHash64Implementation.allCases) { implementation in
                            Text(bilingual(implementation.label, store.settings.general.language)).tag(implementation)
                        }
                    }
                    Text(L10n.t("自动与高性能模式使用 C shim；兼容模式使用 Swift reference implementation。",
                                "Automatic and high-performance modes use the C shim; compatibility uses the Swift reference implementation.",
                                language: store.settings.general.language))
                        .font(.system(size: 10))
                        .foregroundStyle(colors.textSecondary)
                }
                Stepper(value: store.binding(\.checksum.retryOnFailure), in: 0...5) {
                    Text(L10n.t("校验失败自动重试次数：\(store.settings.checksum.retryOnFailure)",
                                "Auto-retry on failure: \(store.settings.checksum.retryOnFailure)",
                                language: store.settings.general.language))
                }
                Text(L10n.t(
                    "源端读取与目标端读回校验固定启用；单个目标失败不会取消其他目标。",
                    "Source-read and destination readback verification are always enabled; one failed destination does not cancel the others.",
                    language: store.settings.general.language
                ))
                .font(.system(size: 10))
                .foregroundStyle(colors.textSecondary)
            }

            PrefGroup(title_zh: "导出", title_en: "EXPORTS") {
                Toggle(L10n.t("生成 sidecar checksum 文件", "Write sidecar checksum files", language: store.settings.general.language),
                       isOn: store.binding(\.checksum.writeSidecarChecksum))
                Toggle(L10n.t("生成 ASC MHL", "Generate ASC MHL", language: store.settings.general.language),
                       isOn: store.binding(\.checksum.generateAscMHL))
                Toggle(L10n.t("生成 CSV 校验日志", "Generate CSV log", language: store.settings.general.language),
                       isOn: store.binding(\.checksum.generateCSVLog))
                Toggle(L10n.t("生成 JSON 校验日志", "Generate JSON log", language: store.settings.general.language),
                       isOn: store.binding(\.checksum.generateJSONLog))
                Toggle(L10n.t("记录软件 / macOS / 机器名等环境信息",
                              "Record app / macOS / host environment in report",
                              language: store.settings.general.language),
                       isOn: store.binding(\.checksum.recordEnvironmentInReport))
            }
        }
    }
}

// MARK: - Report

private struct ReportPane: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PrefHeader(
                title_zh: "报告", title_en: "Reports",
                subtitle_zh: "报告输出与任务完成后的打开方式",
                subtitle_en: "Report output and post-task actions"
            )

            PrefGroup(title_zh: "输出", title_en: "OUTPUT") {
                Label(
                    L10n.t("始终生成完整 PDF 技术报告", "Always generate the full PDF technical report", language: store.settings.general.language),
                    systemImage: "doc.richtext"
                )
                .font(.system(size: 12, weight: .semibold))
                Toggle(L10n.t("同时生成 TXT 简版报告", "Also generate a brief TXT report", language: store.settings.general.language),
                       isOn: store.binding(\.report.generateBriefReport))
                Toggle(L10n.t("完成后自动打开报告", "Auto-open report on finish", language: store.settings.general.language),
                       isOn: store.binding(\.report.autoOpenReportOnFinish))
                Toggle(L10n.t("完成后自动打开报告所在文件夹",
                              "Auto-open report folder on finish",
                              language: store.settings.general.language),
                       isOn: store.binding(\.report.autoOpenReportFolderOnFinish))
            }

        }
    }
}

// MARK: - Transcode

private struct TranscodePane: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PrefHeader(
                title_zh: "代理与转码", title_en: "Proxy & Transcode",
                subtitle_zh: "拷卡任务的代理生成默认值",
                subtitle_en: "Proxy-generation defaults for offload tasks"
            )

            PrefGroup(title_zh: "默认行为", title_en: "DEFAULT BEHAVIOR") {
                Toggle(L10n.t("校验通过后自动生成代理或转码",
                              "Auto-transcode after verification",
                              language: store.settings.general.language),
                       isOn: store.binding(\.transcode.autoTranscodeOnVerified))
                Text(L10n.t(
                    "代理写入每个输出包的 PROXIES 目录，并保持可追溯的原片映射。",
                    "Proxies are written to each package's PROXIES folder with traceable original-media mapping.",
                    language: store.settings.general.language
                ))
                .font(.system(size: 10))
                .foregroundStyle(colors.textSecondary)
            }

            PrefGroup(title_zh: "默认编码", title_en: "DEFAULT CODEC") {
                Picker(L10n.t("编码", "Codec", language: store.settings.general.language),
                       selection: store.binding(\.transcode.defaultCodec)) {
                    ForEach(TranscodeCodec.allCases) { c in
                        Text(c.displayName).tag(c)
                    }
                }
	        Picker(L10n.t("画质", "Quality", language: store.settings.general.language),
	                       selection: store.binding(\.transcode.defaultQuality)) {
	                    ForEach(TranscodeQuality.allCases) { q in
	                        Text(qualityLabel(q)).tag(q)
	                    }
	                }
	                Picker(L10n.t("码率", "Bitrate", language: store.settings.general.language),
	                       selection: store.binding(\.transcode.defaultBitrate)) {
	                    ForEach(TranscodeBitrate.allCases) { b in
	                        Text(bitrateLabel(b)).tag(b)
	                    }
	                }
	                Picker(L10n.t("默认分辨率", "Default scale", language: store.settings.general.language),
	                       selection: store.binding(\.transcode.defaultScale)) {
	                    ForEach(TranscodeScale.allCases) { s in
	                        Text(scaleLabel(s)).tag(s)
	                    }
	                }
            }

            PrefGroup(title_zh: "高级", title_en: "ADVANCED") {
                Toggle(L10n.t("启用硬件加速", "Hardware acceleration", language: store.settings.general.language),
                       isOn: store.binding(\.transcode.enableHardwareAcceleration))
                Toggle(L10n.t("尝试视频 RAW 解码 (R3D / BRAW / ARRIRAW / CRM …)",
                              "Attempt RAW decode (R3D / BRAW / ARRIRAW / CRM …)",
                              language: store.settings.general.language),
                       isOn: store.binding(\.transcode.attemptRawSources))
                Text(L10n.t(
                    "转码失败会写入任务报告，但不会把已经成功的拷贝与校验标记为失败。",
                    "Transcode failures are recorded in the task report without changing a successful copy-and-verify result.",
                    language: store.settings.general.language
                ))
                .font(.system(size: 10))
                .foregroundStyle(colors.textSecondary)
            }
            
            PrefGroup(title_zh: "FFmpeg", title_en: "FFmpeg") {
                Text(L10n.t("FFmpeg 路径与安装助手已移到左侧独立的「FFmpeg」设置页。",
                            "FFmpeg path and installer live in the dedicated FFmpeg settings page.",
                            language: store.settings.general.language))
                    .font(.system(size: 11))
                    .foregroundStyle(colors.textSecondary)
            }
        }
    }

    private var lang: AppLanguage { store.settings.general.language.resolved }

    private func qualityLabel(_ quality: TranscodeQuality) -> String {
        switch quality {
        case .low: return L10n.t("低", "Low", language: lang)
        case .medium: return L10n.t("中", "Medium", language: lang)
        case .high: return L10n.t("高", "High", language: lang)
        }
    }

    private func bitrateLabel(_ bitrate: TranscodeBitrate) -> String {
        switch bitrate {
        case .auto: return L10n.t("自动", "Auto (CRF)", language: lang)
        case .mbps5, .mbps10, .mbps25, .mbps50, .mbps100, .mbps200, .mbps400:
            return bitrate.displayName
        }
    }

    private func scaleLabel(_ scale: TranscodeScale) -> String {
        switch scale {
        case .original: return L10n.t("原始", "Original", language: lang)
        case .uhd2160: return "UHD 3840"
        case .hd1080: return "FHD 1920"
        case .hd720: return "HD 1280"
        case .half: return L10n.t("原始 1/2", "Half size", language: lang)
        }
    }
}

// MARK: - FFmpeg

private struct FFmpegPane: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors
    @State private var ffmpegInfo: FFmpegInfo = FFmpegInfo(isAvailable: false, path: nil, version: "—", architecture: "—", codecs: [])
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PrefHeader(
                title_zh: "FFmpeg",
                title_en: "FFmpeg",
                subtitle_zh: "高级转码依赖项；不安装也可以继续拷贝、校验和出报告",
                subtitle_en: "Advanced transcode dependency; copy, verify and reports still work without it"
            )

            PrefGroup(title_zh: "状态", title_en: "STATUS") {
                HStack(alignment: .top) {
                    Image(systemName: ffmpegInfo.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(ffmpegInfo.isAvailable ? colors.stateSuccess : colors.stateWarning)
                        .padding(.top, 2)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ffmpegInfo.summary)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(nil)
                        
                        if ffmpegInfo.isAvailable {
                            let codecsString = ffmpegInfo.codecs.isEmpty ? "None" : ffmpegInfo.codecs.joined(separator: ", ")
                            Text("Codecs: \(codecsString)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(colors.textSecondary)
                        }
                    }
                    
                    Spacer()
                    Button(L10n.t("重新检测", "Re-check", language: store.settings.general.language)) {
                        refresh()
                    }
                    .controlSize(.small)
                }
                Text(L10n.t(
                    "未找到 FFmpeg 时，321Doit 仍可完成素材拷贝、校验、PDF/MHL/CSV/JSON/TXT 报告。受限功能：LUT 烧录、H.266、RAW / 部分专业格式解码、FFmpeg 路径下的 VideoToolbox H.264/HEVC 转码。",
                    "Without FFmpeg, 321Doit still copies, verifies, and writes PDF/MHL/CSV/JSON/TXT reports. Limited features: LUT bake-in, H.266, RAW / some professional format decoding, and FFmpeg-based VideoToolbox H.264/HEVC transcoding.",
                    language: store.settings.general.language
                ))
                .font(.system(size: 11))
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            PrefGroup(title_zh: "路径", title_en: "PATH") {
                PathPickerRow(title_zh: "自定义 FFmpeg 路径", title_en: "Custom FFmpeg path",
                              path: store.binding(\.transcode.ffmpegPath), allowsFiles: true)
                Text(L10n.t("优先使用电脑上已有的 FFmpeg；没有时自动使用安装器随附的离线 FFmpeg/FFprobe。自定义路径无效时会自动回退检测。",
                            "An existing system FFmpeg is preferred; otherwise 321Doit uses the offline FFmpeg/FFprobe included by the installer. Invalid custom paths fall back to auto-detection.",
                            language: store.settings.general.language))
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)
            }

        }
        .onAppear { refresh() }
        .onChange(of: store.settings.transcode.ffmpegPath) { _ in refresh() }
        .onDisappear { refreshTask?.cancel() }
    }

    private func refresh() {
        refreshTask?.cancel()
        let configuredPath = store.settings.transcode.ffmpegPath
        let language = store.settings.general.language
        refreshTask = Task { @MainActor in
            let info = await Task.detached(priority: .utility) {
                FFmpegLocator.getInfo(configuredPath: configuredPath, language: language)
            }.value
            guard !Task.isCancelled else { return }
            ffmpegInfo = info
        }
    }
}

// MARK: - LUT

private struct LUTPane: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PrefHeader(
                title_zh: "LUT 与色彩", title_en: "LUT & Color",
                subtitle_zh: "代理生成时套用 3D LUT （需要 ffmpeg）",
                subtitle_en: "Apply a 3D LUT during proxy generation (requires ffmpeg)"
            )

            PrefGroup(title_zh: "默认 LUT", title_en: "DEFAULT LUT") {
                PathPickerRow(title_zh: "默认 LUT 文件", title_en: "Default LUT file",
                              path: store.binding(\.lut.defaultLUTPath), allowsFiles: true)
                Toggle(L10n.t("自动应用默认 LUT", "Auto-apply default LUT", language: store.settings.general.language),
                       isOn: store.binding(\.lut.autoApply))
                HStack {
                    Text(L10n.t("LUT 强度", "LUT intensity", language: store.settings.general.language))
                    Slider(value: store.binding(\.lut.intensity), in: 0...1)
                    Text(String(format: "%.2f", store.settings.lut.intensity))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 44)
                }
                Text(L10n.t(
                    "可在单个任务中临时选择其他 LUT；这里只设置新任务的默认值。",
                    "A different LUT can still be selected per task; this page only defines the new-task default.",
                    language: store.settings.general.language
                ))
                .font(.system(size: 10))
                .foregroundStyle(colors.textSecondary)
            }
        }
    }
}

// MARK: - Storage Safety

private struct StorageSafetyPane: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PrefHeader(
                title_zh: "磁盘与安全", title_en: "Storage Safety",
                subtitle_zh: "关键保护固定生效，不提供会造成误判的假开关",
                subtitle_en: "Critical safeguards are always active; misleading no-op switches are not exposed"
            )

            PrefGroup(title_zh: "固定安全规则", title_en: "ALWAYS-ON SAFEGUARDS") {
                safetyRule("源盘不写入、不修改", "Never write to or modify the source", icon: "lock.shield")
                safetyRule("目标端必须读回并比对 Hash", "Always read back and verify destination hashes", icon: "checkmark.shield")
                safetyRule("空间不足、同卷或路径嵌套时阻止开始", "Block insufficient space, same-volume, and nested paths", icon: "externaldrive.badge.exclamationmark")
                safetyRule("检查 FAT32 大文件限制与大小写文件名冲突", "Check FAT32 file-size limits and case-name conflicts", icon: "doc.badge.gearshape")
                safetyRule("绝不静默覆盖已有输出", "Never silently overwrite an existing output", icon: "exclamationmark.octagon")
                Text(L10n.t(
                    "以后只有在完整实现确认流程、执行逻辑和报告记录后，才会重新加入可关闭的高级安全选项。",
                    "Advanced safety overrides will return only after confirmation, execution, and report logging are fully implemented.",
                    language: store.settings.general.language
                ))
                .font(.system(size: 10))
                .foregroundStyle(colors.textSecondary)
            }
        }
    }

    private func safetyRule(_ zh: String, _ en: String, icon: String) -> some View {
        Label(L10n.t(zh, en, language: store.settings.general.language), systemImage: icon)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(colors.textPrimary)
    }
}

// MARK: - Performance

private struct PerformancePane: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PrefHeader(
                title_zh: "性能", title_en: "Performance",
                subtitle_zh: "默认值适合大多数 Mac，无需调整",
                subtitle_en: "Defaults are sane for most Macs"
            )

            PrefGroup(title_zh: "I/O", title_en: "I/O") {
                Stepper(value: store.binding(\.performance.copyBufferKB), in: 64...8192, step: 64) {
                    Text(L10n.t("拷贝缓冲区：\(store.settings.performance.copyBufferKB) KB",
                                "Copy buffer: \(store.settings.performance.copyBufferKB) KB",
                                language: store.settings.general.language))
                }
                Text(L10n.t("采用单文件流式读取，并同时写入所有已选择目标盘。",
                            "Files are streamed one at a time and written to all selected destinations together.",
                            language: store.settings.general.language))
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)
            }

            PrefGroup(title_zh: "速度限制", title_en: "RATE LIMIT") {
                Toggle(L10n.t("限制拷贝速度", "Limit copy speed", language: store.settings.general.language),
                       isOn: store.binding(\.performance.enableSpeedLimit))
                if store.settings.performance.enableSpeedLimit {
                    Stepper(value: store.binding(\.performance.speedLimitMBps), in: 1...2000, step: 10) {
                        Text(L10n.t("速度限制：\(store.settings.performance.speedLimitMBps) MB/s",
                                    "Speed limit: \(store.settings.performance.speedLimitMBps) MB/s",
                                    language: store.settings.general.language))
                    }
                }
            }

            PrefGroup(title_zh: "任务保护", title_en: "TASK PROTECTION") {
                Label(
                    L10n.t("拷卡任务运行时固定阻止系统闲置休眠", "System idle sleep is prevented while an offload task is active", language: store.settings.general.language),
                    systemImage: "moon.zzz"
                )
                .font(.system(size: 12, weight: .semibold))
            }
        }
    }
}

// MARK: - Notifications

private struct NotificationPane: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PrefHeader(
                title_zh: "通知", title_en: "Notifications",
                subtitle_zh: "完成 / 失败时如何提醒你",
                subtitle_en: "How to notify you on finish or failure"
            )

            PrefGroup(title_zh: "本机通知", title_en: "LOCAL NOTIFICATIONS") {
                Toggle(L10n.t("完成播放声音", "Play sound on finish", language: store.settings.general.language),
                       isOn: store.binding(\.notification.soundOnFinish))
                Toggle(L10n.t("校验失败播放警告音",
                              "Play warning sound on verify failure",
                              language: store.settings.general.language),
                       isOn: store.binding(\.notification.warnSoundOnVerifyFailure))
                Toggle(L10n.t("发送 macOS 系统通知",
                              "Post macOS system notification",
                              language: store.settings.general.language),
                       isOn: store.binding(\.notification.systemNotification))
                Toggle(L10n.t("完成后弹窗", "Popup on finish", language: store.settings.general.language),
                       isOn: store.binding(\.notification.popupOnFinish))
                Toggle(L10n.t("失败后弹窗", "Popup on failure", language: store.settings.general.language),
                       isOn: store.binding(\.notification.popupOnFailure))
                Toggle(L10n.t("Dock 显示进度", "Show progress on Dock icon", language: store.settings.general.language),
                       isOn: store.binding(\.notification.dockProgress))
                Toggle(L10n.t("完成后自动打开报告", "Auto-open report", language: store.settings.general.language),
                       isOn: store.binding(\.notification.autoOpenReportOnFinish))
                Toggle(L10n.t("完成后自动打开输出文件夹",
                              "Auto-open output folder",
                              language: store.settings.general.language),
                       isOn: store.binding(\.notification.autoOpenOutputFolderOnFinish))
            }

            PrefGroup(title_zh: "Webhook", title_en: "WEBHOOKS") {
                Text(L10n.t("Webhook URL 存储在 macOS Keychain；settings.json 只保存启用状态、类型、名称和脱敏地址。",
                            "Webhook URLs are stored in macOS Keychain; settings.json keeps only enabled state, type, name and masked address.",
                            language: store.settings.general.language))
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)
                WebhookRow(kind: .slack)
                WebhookRow(kind: .feishu)
                WebhookRow(kind: .wecom)
                WebhookRow(kind: .custom)
                if let warning = store.credentialWarning {
                    Text(warning)
                        .font(.system(size: 10))
                        .foregroundStyle(colors.stateWarning)
                }
                Button(role: .destructive) {
                    do {
                        try store.clearWebhookCredentials()
                    } catch {
                        presentError(error)
                    }
                } label: {
                    Label(L10n.t("清除 Webhook 凭据", "Clear Webhook Credentials", language: store.settings.general.language), systemImage: "key.slash")
                }
            }
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "321Doit"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private struct WebhookRow: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors
    let kind: WebhookKind
    @State private var draftURL = ""
    @State private var statusText = ""

    private var lang: AppLanguage { store.settings.general.language.resolved }
    private var endpoint: WebhookEndpointSettings { store.settings.notification.endpoint(for: kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(isOn: enabledBinding) {
                    Text(kind.displayName)
                        .font(.system(size: 12, weight: .medium))
                }
                Spacer()
                Text(endpoint.maskedURL.isEmpty ? L10n.t("未设置", "Not set", language: lang) : endpoint.maskedURL)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(endpoint.maskedURL.isEmpty ? colors.textSecondary : colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: 8) {
                SecureField(L10n.t("粘贴新的 Webhook URL", "Paste a new webhook URL", language: lang), text: $draftURL)
                    .textFieldStyle(.roundedBorder)
                Button(L10n.t("保存", "Save", language: lang)) {
                    save()
                }
                .disabled(draftURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(L10n.t("测试", "Test", language: lang)) {
                    test()
                }
                .disabled(endpoint.maskedURL.isEmpty)
            }
            if !statusText.isEmpty {
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)
            }
        }
        .padding(8)
        .background(colors.inputBg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { endpoint.enabled },
            set: { newValue in
                var updated = endpoint
                updated.enabled = newValue
                store.settings.notification.setEndpoint(updated)
            }
        )
    }

    private func save() {
        do {
            try store.setWebhookURL(draftURL, for: kind)
            statusText = L10n.t("已保存到 Keychain", "Saved to Keychain", language: lang)
            draftURL = ""
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func test() {
        statusText = L10n.t("正在发送测试…", "Sending test…", language: lang)
        Task {
            do {
                try await WebhookNotifier.sendTest(kind: kind)
                await MainActor.run {
                    statusText = L10n.t("测试发送成功", "Test sent", language: lang)
                }
            } catch {
                await MainActor.run {
                    statusText = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Logs

private struct LogsPane: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PrefHeader(
                title_zh: "日志与诊断", title_en: "Logs & Diagnostics",
                subtitle_zh: "任务恢复与本机诊断信息",
                subtitle_en: "Task recovery and local diagnostics"
            )

            PrefGroup(title_zh: "任务恢复", title_en: "TASK RECOVERY") {
                Toggle(L10n.t("崩溃后保留未完成任务记录",
                              "Keep incomplete task records after crash",
                              language: store.settings.general.language),
                       isOn: store.binding(\.logs.keepIncompleteTaskOnCrash))
                Text(L10n.t(
                    "开启后，未完成的极速拷卡任务会保存必要参数，并在下次启动时提供恢复。任务日志随报告写入，不会包含素材内容。",
                    "When enabled, an unfinished Turbo Offload task saves the parameters needed for recovery on next launch. Task logs are written with reports and never include media content.",
                    language: store.settings.general.language
                ))
                .font(.system(size: 10))
                .foregroundStyle(colors.textSecondary)
            }

            PrefGroup(title_zh: "本机日志", title_en: "LOCAL LOGS") {
                if let warning = store.persistenceWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(colors.stateWarning)
                }
                Text(L10n.t(
                    "默认保存位置：\(AppLogger.directoryURL(customPath: store.settings.logs.logFolder).path)",
                    "Default location: \(AppLogger.directoryURL(customPath: store.settings.logs.logFolder).path)",
                    language: store.settings.general.language
                ))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(colors.textSecondary)
                .textSelection(.enabled)

                Stepper(
                    L10n.t("保留 \(store.settings.logs.retentionDays) 天", "Keep for \(store.settings.logs.retentionDays) days", language: store.settings.general.language),
                    value: store.binding(\.logs.retentionDays),
                    in: 7...180
                )

                Picker(
                    L10n.t("日志详细程度", "Log detail", language: store.settings.general.language),
                    selection: store.binding(\.logs.level)
                ) {
                    ForEach(LogLevel.allCases) { level in
                        Text(bilingual(level.label, store.settings.general.language)).tag(level)
                    }
                }
                .pickerStyle(.segmented)

                Toggle(L10n.t("保存文本日志", "Write text logs", language: store.settings.general.language),
                       isOn: store.binding(\.logs.exportText))
                Toggle(L10n.t("同时保存 JSONL 日志", "Also write JSONL logs", language: store.settings.general.language),
                       isOn: store.binding(\.logs.exportJSON))

                Button(L10n.t("打开日志目录", "Open Logs Folder", language: store.settings.general.language)) {
                    let url = AppLogger.directoryURL(customPath: store.settings.logs.logFolder)
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

// MARK: - About

// MARK: - Handoff (Post Handoff)

private struct HandoffPane: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors
    @State private var detectionRevision = 0

    private var lang: AppLanguage { store.settings.general.language.resolved }

    private var resolveAppURL: URL? {
        _ = detectionRevision
        return HandoffAppDetector.resolveAppURL()
    }
    private var finalCutAppURL: URL? {
        _ = detectionRevision
        return HandoffAppDetector.finalCutAppURL()
    }
    private var resolveInstalled: Bool { resolveAppURL != nil }
    private var finalCutInstalled: Bool { finalCutAppURL != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PrefHeader(
                title_zh: "后期交接", title_en: "Post Handoff",
                subtitle_zh: "在拷卡、校验、代理生成完成后，为后期软件生成可导入的交接包",
                subtitle_en: "Generate handoff packages for downstream NLEs after copy, verify, and proxy"
            )

            PrefGroup(title_zh: "交接目标", title_en: "HANDOFF TARGET") {
                Picker(
                    L10n.t("目标软件", "Target", language: lang),
                    selection: store.binding(\.handoff.target)
                ) {
                    ForEach(HandoffTarget.allCases) { target in
                        Text(bilingual(target.label, lang)).tag(target)
                    }
                }
                .pickerStyle(.menu)

                Text(L10n.t(
                    "321Doit 在交接包内生成 manifest.json 与对应导入文件，不会伪造原生工程文件。",
                    "321Doit writes manifest.json plus per-NLE import files into the handoff package; it never fabricates native project files.",
                    language: lang
                ))
                .font(.system(size: 10))
                .foregroundStyle(colors.textSecondary)

                installationStatus
            }

            PrefGroup(title_zh: "项目参数", title_en: "PROJECT") {
                LabeledTextField(
                    title_zh: "项目名称", title_en: "Project Name",
                    placeholder_zh: "默认使用 321Doit 任务的项目名",
                    placeholder_en: "Defaults to the offload project name",
                    text: store.binding(\.handoff.projectName)
                )
                LabeledTextField(
                    title_zh: "拍摄日 / Day 编号", title_en: "Shoot Day",
                    placeholder_zh: "例如 Day01，留空则使用卡号",
                    placeholder_en: "e.g. Day01, falls back to card name",
                    text: store.binding(\.handoff.shootDay)
                )
                LabeledTextField(
                    title_zh: "拍摄日期", title_en: "Date (YYYY-MM-DD)",
                    placeholder_zh: "留空则使用任务开始日期",
                    placeholder_en: "Falls back to job start date",
                    text: store.binding(\.handoff.shootDate)
                )

                Picker(
                    L10n.t("帧率", "Frame rate", language: lang),
                    selection: store.binding(\.handoff.frameRate)
                ) {
                    ForEach(HandoffFrameRate.allCases) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
                Picker(
                    L10n.t("分辨率", "Resolution", language: lang),
                    selection: store.binding(\.handoff.resolution)
                ) {
                    ForEach(HandoffResolution.allCases) { res in
                        Text(res.displayName).tag(res)
                    }
                }
                LabeledTimecodeField(
                    title_zh: "时间线起始码", title_en: "Start Timecode",
                    placeholder_zh: "例如 01:00:00:00",
                    placeholder_en: "e.g. 01:00:00:00",
                    text: store.binding(\.handoff.startTimecode)
                )
                Picker(
                    L10n.t("色彩管理", "Color Management", language: lang),
                    selection: store.binding(\.handoff.colorMode)
                ) {
                    ForEach(HandoffColorMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }

            PrefGroup(title_zh: "交接选项", title_en: "OPTIONS") {
                if store.settings.handoff.target.includesFinalCut {
                    Toggle(isOn: store.binding(\.handoff.generateStarterTimeline)) {
                        Text(L10n.t("生成 Final Cut 起始时间线", "Generate Final Cut starter timeline", language: lang))
                    }
                    Text(L10n.t(
                        "仅用于 Final Cut Pro；DaVinci Resolve 交接只导入媒体和链接代理，不自动新建时间线。",
                        "Final Cut Pro only. DaVinci Resolve handoff imports media and links proxies without creating a timeline.",
                        language: lang
                    )).font(.system(size: 10)).foregroundStyle(colors.textSecondary)
                }

                Toggle(isOn: store.binding(\.handoff.importProxies)) {
                    Text(L10n.t("导入代理", "Import proxies", language: lang))
                }
                Text(L10n.t(
                    "若 321Doit 已生成代理，会在交接文件中显式建立原片与代理的映射；Resolve 导入脚本会链接代理，FCP 通过 media-rep 识别。",
                    "When proxies exist, the handoff explicitly maps original↔proxy. Resolve import scripts link proxies, and FCP reads media-rep.",
                    language: lang
                )).font(.system(size: 10)).foregroundStyle(colors.textSecondary)

                Toggle(isOn: store.binding(\.handoff.importLUT)) {
                    Text(L10n.t("导入 LUT", "Import LUT", language: lang))
                }
                Text(L10n.t(
                    "将 LUT 复制进 INTEGRATIONS/LUT/（旧版输出包为 05_HANDOFF/LUT/）。仅在目标软件支持时尝试套用，失败只记为警告。",
                    "Copies the LUT into INTEGRATIONS/LUT/ (05_HANDOFF/LUT/ in legacy packages). The NLE only applies it when supported; failures remain warnings.",
                    language: lang
                )).font(.system(size: 10)).foregroundStyle(colors.textSecondary)

                Toggle(isOn: store.binding(\.handoff.generateImportScripts)) {
                    Text(L10n.t("生成导入脚本", "Generate import scripts", language: lang))
                }

                Toggle(isOn: store.binding(\.handoff.autoOpenAfterHandoff)) {
                    Text(L10n.t("任务完成后自动发送", "Auto-send after task completes", language: lang))
                }
            }

            PrefGroup(title_zh: "DaVinci Resolve 导入", title_en: "DAVINCI RESOLVE IMPORT") {
                ResolveHandoffOptionsView(
                    handoff: store.binding(\.handoff),
                    language: lang
                )
                Text(L10n.t(
                    "Resolve 脚本使用 SetClipProperty、SetClipColor 和 AddFlag 写入元数据、素材颜色与旗标。目标软件选为 DaVinci Resolve 或双软件时生效。",
                    "The Resolve script uses SetClipProperty, SetClipColor and AddFlag for metadata, clip colors and flags. These options take effect when the target includes DaVinci Resolve.",
                    language: lang
                ))
                .font(.system(size: 10))
                .foregroundStyle(colors.textSecondary)
            }
        }
        .onAppear(perform: refreshApplicationDetection)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshApplicationDetection()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            refreshApplicationDetection()
        }
    }

    @ViewBuilder
    private var installationStatus: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                statusRow(
                    installed: resolveInstalled,
                    installedLabel_zh: "已检测到 DaVinci Resolve",
                    installedLabel_en: "DaVinci Resolve is installed",
                    missingLabel_zh: "未检测到 DaVinci Resolve（仍可生成交接包）",
                    missingLabel_en: "DaVinci Resolve not found (handoff package still works)"
                )
                statusRow(
                    installed: finalCutInstalled,
                    installedLabel_zh: "已检测到 Final Cut Pro",
                    installedLabel_en: "Final Cut Pro is installed",
                    missingLabel_zh: "未检测到 Final Cut Pro（仍可生成交接包）",
                    missingLabel_en: "Final Cut Pro not found (handoff package still works)"
                )
            }
            Spacer()
            Button {
                refreshApplicationDetection()
            } label: {
                Label(L10n.t("重新检测", "Refresh", language: lang), systemImage: "arrow.clockwise")
            }
            .controlSize(.small)
        }
        .padding(.top, 4)
    }

    private func refreshApplicationDetection() {
        detectionRevision &+= 1
        AppLogger.log(
            .detailed,
            category: "handoff",
            "Refreshed NLE detection; Resolve=\(HandoffAppDetector.resolveAppURL()?.path ?? "not found"), FinalCut=\(HandoffAppDetector.finalCutAppURL()?.path ?? "not found")"
        )
    }

    private func statusRow(
        installed: Bool,
        installedLabel_zh: String,
        installedLabel_en: String,
        missingLabel_zh: String,
        missingLabel_en: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: installed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(installed ? colors.stateSuccess : colors.stateWarning)
            Text(L10n.t(
                installed ? installedLabel_zh : missingLabel_zh,
                installed ? installedLabel_en : missingLabel_en,
                language: lang
            ))
            .font(.system(size: 11))
            .foregroundStyle(colors.textSecondary)
        }
    }
}

private struct LabeledTextField: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors

    let title_zh: String
    let title_en: String
    var placeholder_zh: String = ""
    var placeholder_en: String = ""
    @Binding var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L10n.t(title_zh, title_en, language: store.settings.general.language))
                .font(.system(size: 11))
                .frame(width: 120, alignment: .leading)
            TextField(
                L10n.t(placeholder_zh, placeholder_en, language: store.settings.general.language),
                text: $text
            )
            .textFieldStyle(.roundedBorder)
        }
    }
}

private struct LabeledTimecodeField: View {
    @EnvironmentObject private var store: SettingsStore

    let title_zh: String
    let title_en: String
    var placeholder_zh: String = ""
    var placeholder_en: String = ""
    @Binding var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L10n.t(title_zh, title_en, language: store.settings.general.language))
                .font(.system(size: 11))
                .frame(width: 120, alignment: .leading)
            TimeInputField(
                text: $text,
                placeholder: L10n.t(placeholder_zh, placeholder_en, language: store.settings.general.language),
                mode: .timecode(framesPerSecond: framesPerSecond)
            )
        }
    }

    private var framesPerSecond: Int {
        let rational = store.settings.handoff.frameRate.rational
        return max(1, Int((Double(rational.numerator) / Double(rational.denominator)).rounded()))
    }
}

private struct AboutPane: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors
    @State private var ffmpegVersion: String = "—"
    @State private var openCodeVersion: String = "—"
    @State private var openCodeStatus: String?
    @State private var openCodeGoAPIKey = ""
    @State private var openCodeGoAPIKeyWasEdited = false
    @State private var hasSavedOpenCodeGoAPIKey = false
    @State private var openCodeGoStatus: String?
    @State private var customModelService = MiraCustomModelService()
    @State private var customModelAPIKey = ""
    @State private var customModelAPIKeyWasEdited = false
    @State private var customModelServiceStatus: String?

    private var lang: AppLanguage { store.settings.general.language.resolved }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PrefHeader(
                title_zh: "更新与关于", title_en: "Updates & About",
                subtitle_zh: "本工具完全免费，源代码开源",
                subtitle_en: "Free. Fully open source."
            )

            HStack(spacing: 14) {
                AppLogo(size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text("321Doit").font(.system(size: 22, weight: .semibold))
                    Text(L10n.t(UpdateSettings.licenseBlurb.0, UpdateSettings.licenseBlurb.1, language: lang))
                        .font(.system(size: 11))
                        .foregroundStyle(colors.textSecondary)
                    Button {
                        NotificationCenter.default.post(name: AppMenuCommand.contactSupport.notificationName, object: nil)
                    } label: {
                        Label(L10n.t("支持 321Doit 继续开发", "Support 321Doit Development", language: lang), systemImage: "heart")
                    }
                    .controlSize(.small)
                    .focusable(false)
                    .padding(.top, 4)
                }
            }

            PrefGroup(title_zh: "软件更新", title_en: "SOFTWARE UPDATE") {
                Toggle(
                    L10n.t("启动时自动检查更新", "Automatically check for updates on launch", language: lang),
                    isOn: store.binding(\.update.autoCheckForUpdates)
                )
                Toggle(
                    L10n.t("接收 Beta 版本", "Include beta releases", language: lang),
                    isOn: store.binding(\.update.receiveBeta)
                )
                Button {
                    UpdateChecker.shared.checkForUpdates(
                        receiveBeta: store.settings.update.receiveBeta,
                        presentNoUpdate: true
                    )
                } label: {
                    Label(L10n.t("立即检查更新", "Check for Updates Now", language: lang), systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
            }

            PrefGroup(title_zh: "Mira 与 OpenCode", title_en: "MIRA & OPENCODE") {
                VStack(alignment: .leading, spacing: 10) {
                    Row(label: "OpenCode", value: openCodeVersion)
                    Text(L10n.t(
                        "Mira 使用随 321Doit 签名发布的 OpenCode；检查 321Doit 更新时也会检查 OpenCode 更新。",
                        "Mira uses the signed OpenCode bundled with 321Doit; checking for 321Doit updates also checks OpenCode.",
                        language: lang
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(colors.textSecondary)
                    Button {
                        UpdateChecker.shared.checkForUpdates(
                            receiveBeta: store.settings.update.receiveBeta,
                            presentNoUpdate: true
                        )
                    } label: {
                        Label(L10n.t("检查 OpenCode 更新", "Check for OpenCode Updates", language: lang), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .controlSize(.small)

                    Divider()

                    Text(L10n.t(
                        "如果你已经在本机 OpenCode 中登录了 Go 或其他服务，可将登录信息同步给 Mira。不会上传凭据；同步后 Mira 会重新连接，并在模型菜单显示那些服务可用的模型。",
                        "If you have already signed in to OpenCode Go or other providers on this Mac, sync those credentials to Mira. They are not uploaded; Mira reconnects and then lists the models those providers make available.",
                        language: lang
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(colors.textSecondary)
                    Button {
                        do {
                            openCodeStatus = try OpenCodeBridge.syncExistingProviderCredentials(language: lang)
                        } catch {
                            openCodeStatus = error.localizedDescription
                        }
                    } label: {
                        Label(L10n.t("同步本机 OpenCode 登录", "Sync Local OpenCode Sign-in", language: lang), systemImage: "person.badge.key")
                    }
                    .controlSize(.small)
                    if let openCodeStatus {
                        Text(openCodeStatus)
                            .font(.system(size: 10))
                            .foregroundStyle(colors.textSecondary)
                    }

                    Divider()

                    Text("OpenCode Go")
                        .font(.system(size: 12, weight: .semibold))
                    Text(L10n.t(
                        "已有 Go API Key 时可直接粘贴在这里，不需要先打开终端。保存后 Mira 会重新连接，并在模型菜单显示 OpenCode Go 模型。",
                        "If you already have a Go API key, paste it here—no Terminal required. Mira reconnects after saving and shows OpenCode Go models in its model menu.",
                        language: lang
                    ))
                    .font(.system(size: 11))
                    .foregroundStyle(colors.textSecondary)
                    HStack {
                        Text("API Key")
                            .font(.system(size: 11))
                            .frame(width: 92, alignment: .leading)
                        SecureField(
                            openCodeGoAPIKeyWasEdited || !hasSavedOpenCodeGoAPIKey
                                ? L10n.t("粘贴 OpenCode Go API Key", "Paste OpenCode Go API Key", language: lang)
                                : L10n.t("已存储在 Keychain；输入可替换", "Stored in Keychain; type to replace", language: lang),
                            text: $openCodeGoAPIKey
                        )
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: openCodeGoAPIKey) { _ in openCodeGoAPIKeyWasEdited = true }
                    }
                    HStack(spacing: 10) {
                        Button {
                            saveOpenCodeGoAPIKey()
                        } label: {
                            Label(L10n.t("保存 Go API Key", "Save Go API Key", language: lang), systemImage: "key.fill")
                        }
                        .controlSize(.small)
                        Link(
                            L10n.t("获取或管理 API Key", "Get or Manage API Key", language: lang),
                            destination: URL(string: "https://opencode.ai/auth")!
                        )
                        .font(.system(size: 10))
                    }
                    if let openCodeGoStatus {
                        Text(openCodeGoStatus)
                            .font(.system(size: 10))
                            .foregroundStyle(colors.textSecondary)
                    }

                    Divider()

                    Text(L10n.t(
                        "自定义 OpenAI-compatible API",
                        "Custom OpenAI-compatible API",
                        language: lang
                    ))
                    .font(.system(size: 12, weight: .semibold))
                    Toggle(
                        L10n.t("启用此模型服务", "Enable this model service", language: lang),
                        isOn: $customModelService.isEnabled
                    )
                    modelServiceField(
                        L10n.t("服务标识", "Provider ID", language: lang),
                        text: $customModelService.providerID,
                        prompt: "my-provider"
                    )
                    modelServiceField(
                        L10n.t("显示名称", "Display Name", language: lang),
                        text: $customModelService.displayName,
                        prompt: L10n.t("我的模型服务", "My Model Service", language: lang)
                    )
                    modelServiceField(
                        L10n.t("API 地址", "API Base URL", language: lang),
                        text: $customModelService.baseURL,
                        prompt: "https://api.example.com/v1"
                    )
                    modelServiceField(
                        L10n.t("模型 ID", "Model ID", language: lang),
                        text: $customModelService.modelID,
                        prompt: "your-model-id"
                    )
                    modelServiceField(
                        L10n.t("模型显示名", "Model Display Name", language: lang),
                        text: $customModelService.modelName,
                        prompt: L10n.t("可留空", "Optional", language: lang)
                    )
                    HStack {
                        Text(L10n.t("接口", "API", language: lang))
                            .font(.system(size: 11))
                            .frame(width: 92, alignment: .leading)
                        Picker("", selection: $customModelService.usesResponsesAPI) {
                            Text("/v1/chat/completions").tag(false)
                            Text("/v1/responses").tag(true)
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    HStack {
                        Text(L10n.t("API Key", "API Key", language: lang))
                            .font(.system(size: 11))
                            .frame(width: 92, alignment: .leading)
                        SecureField(
                            customModelAPIKeyWasEdited || !hasSavedCustomModelAPIKey
                                ? L10n.t("可留空（本地服务）", "Optional for local servers", language: lang)
                                : L10n.t("已存储在 Keychain；输入可替换", "Stored in Keychain; type to replace", language: lang),
                            text: $customModelAPIKey
                        )
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customModelAPIKey) { _ in customModelAPIKeyWasEdited = true }
                    }
                    Text(L10n.t(
                        "API Key 仅保存到 macOS Keychain；运行时通过环境变量交给 OpenCode，不会写入 Mira 配置文件。保存后 Mira 会自动重新连接，模型菜单会出现这个服务。",
                        "The API key is saved only in macOS Keychain. It is passed to OpenCode through an environment variable at runtime, never written to Mira's config. Mira reconnects after saving and this service appears in the model menu.",
                        language: lang
                    ))
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)
                    Button {
                        saveCustomModelService()
                    } label: {
                        Label(L10n.t("保存模型服务", "Save Model Service", language: lang), systemImage: "externaldrive.badge.checkmark")
                    }
                    .controlSize(.small)
                    if let customModelServiceStatus {
                        Text(customModelServiceStatus)
                            .font(.system(size: 10))
                            .foregroundStyle(colors.textSecondary)
                    }
                }
            }

            originStory
            creditsSection

            PrefGroup(title_zh: "环境", title_en: "ENVIRONMENT") {
                VStack(alignment: .leading, spacing: 8) {
                    Row(label: "App Version", value: UpdateSettings.appVersion)
                    Row(label: "macOS", value: macOSVersionString)
                    Row(label: "FFmpeg", value: ffmpegVersion)
                }
            }

            VStack(alignment: .center, spacing: 4) {
                Text("© 2024-2026 · Licensed under MIT")
                    .font(.system(size: 9))
                    .foregroundStyle(colors.warm.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 10)
        }
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let version = detectFFmpegVersion()
                DispatchQueue.main.async {
                    ffmpegVersion = version
                }
            }
            openCodeVersion = OpenCodeBridge.embeddedOpenCodeVersion()
            hasSavedOpenCodeGoAPIKey = (try? MiraOpenCodeGoAPIKeyStore.read()) != nil
            customModelService = MiraCustomModelServiceStore.load()
            hasSavedCustomModelAPIKey = (try? MiraCustomModelAPIKeyStore.read()) != nil
        }
    }

    @State private var hasSavedCustomModelAPIKey = false

    private func modelServiceField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .frame(width: 92, alignment: .leading)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func saveOpenCodeGoAPIKey() {
        guard openCodeGoAPIKeyWasEdited else {
            openCodeGoStatus = L10n.t(
                "Go API Key 已经保存在 Keychain 中。",
                "The Go API key is already stored in Keychain.",
                language: lang
            )
            return
        }
        do {
            try MiraOpenCodeGoAPIKeyStore.save(openCodeGoAPIKey)
            hasSavedOpenCodeGoAPIKey = !openCodeGoAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            openCodeGoAPIKey = ""
            openCodeGoAPIKeyWasEdited = false
            openCodeGoStatus = hasSavedOpenCodeGoAPIKey
                ? L10n.t("Go API Key 已保存，Mira 正在重新连接。", "Go API key saved. Mira is reconnecting.", language: lang)
                : L10n.t("Go API Key 已移除。", "Go API key removed.", language: lang)
        } catch {
            openCodeGoStatus = error.localizedDescription
        }
    }

    private func saveCustomModelService() {
        let providerID = customModelService.providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = customModelService.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = customModelService.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if customModelService.isEnabled {
            let validID = !providerID.isEmpty
                && providerID.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.")).contains($0) }
            guard validID,
                  let url = URL(string: baseURL),
                  url.scheme == "https" || url.scheme == "http",
                  !modelID.isEmpty else {
                customModelServiceStatus = L10n.t(
                    "请填写有效的服务标识、http(s) API 地址和模型 ID。",
                    "Enter a valid provider ID, http(s) API URL, and model ID.",
                    language: lang
                )
                return
            }
        }
        do {
            if customModelAPIKeyWasEdited {
                try MiraCustomModelAPIKeyStore.save(customModelAPIKey)
                hasSavedCustomModelAPIKey = !customModelAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                customModelAPIKey = ""
                customModelAPIKeyWasEdited = false
            }
            try MiraCustomModelServiceStore.save(customModelService)
            customModelServiceStatus = L10n.t("模型服务已保存，Mira 正在重新连接。", "Model service saved. Mira is reconnecting.", language: lang)
        } catch {
            customModelServiceStatus = error.localizedDescription
        }
    }

    // MARK: - Credits section
    private var creditsSection: some View {
        PrefGroup(title_zh: "特别感谢 (按姓名首字母排序)", title_en: "SPECIAL THANKS (Sorted by initials)") {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.t("一款工具的诞生，往往不是从代码开始的。它也来自那些认真使用、认真反馈、认真相信它会变好的人。", 
                            "The birth of a tool rarely starts with code. It also comes from those who use it, feedback it, and believe it will get better.", 
                            language: lang))
                    .font(.system(size: 11))
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    let people = [
                        ("陈谓", "Chen Wei"),
                        ("克拉拉·霍夫曼", "Clara Hoffmann"),
                        ("董松松", "Dong Songsong"),
                        ("郝如在", "Hao Ruzai"),
                        ("严峻豪", "Yan Junhao"),
                        ("于谨宁", "Yu Jinning"),
                        ("赵瞬", "Zhao Shun")
                    ]
                    
                    ForEach(people, id: \.1) { name in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(colors.accent.opacity(0.5))
                                .frame(width: 4, height: 4)
                            Text(L10n.t(name.0, name.1, language: lang))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(colors.textPrimary)
                        }
                    }
                }
                .padding(.vertical, 4)
                
                Text(L10n.t("感谢你们在 321Doit 早期阶段给予的建议、测试、信任与耐心。这些名字，将和这个工具最初的光一起被记住。", 
                            "Thank you for your advice, testing, trust and patience in the early stages of 321Doit. These names will be remembered with the first light of this tool.", 
                            language: lang))
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Origin story
    private var originStory: some View {
        let storyZH = """
2017 年，一位 18 岁的少年为了正版 Final Cut Pro，
在横店的一家奶茶店捣了一整个夏天的柠檬。
彼时的他还不知道，自己的手将会因此脱臼，
但他深知——不该再有人为了一份工具而精疲力竭。

多年以后，321Doit 来到人间，
一如那年纯粹、简洁、满怀希望的我们。
"""
        let storyEN = """
In 2017, an 18-year-old spent a whole summer squeezing lemons \
at a milk-tea shop in Hengdian — for an honest copy of Final Cut Pro. \
He didn't yet know it would dislocate his hand, only that no one \
should have to wear themselves out for a tool.

Years later, 321Doit arrives — as pure, simple, and full of hope \
as we were back then.
"""
        let dedication = "致敬每一位余焰未熄的影视人。"
        let dedicationEN = "For every filmmaker whose ember still glows."
        let isZh = lang == .zh

        return PrefGroup(title_zh: "创作初衷", title_en: "ORIGIN") {
            HStack(alignment: .top, spacing: 14) {
                // Vertical accent stripe — gradient from blue to warm amber,
                // echoing the three bars in the brand mark.
                LinearGradient(
                    colors: [colors.accent, colors.accentDeep, colors.warm],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 2)
                .clipShape(Capsule())

                VStack(alignment: .leading, spacing: 14) {
                    Text(isZh ? storyZH : storyEN)
                        .font(.system(size: isZh ? 13 : 12))
                        .lineSpacing(isZh ? 5 : 4)
                        .foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(isZh ? dedication : dedicationEN)
                        .font(.system(size: isZh ? 12 : 11,
                                      weight: .semibold,
                                      design: isZh ? .default : .monospaced))
                        .tracking(isZh ? 0 : 1.2)
                        .foregroundStyle(colors.warm)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func detectFFmpegVersion() -> String {
        FFmpegLocator.versionString(configuredPath: store.settings.transcode.ffmpegPath, language: store.settings.general.language)
    }

    private var macOSVersionString: String { osVersionDisplay() }

    private struct Row: View {
        let label: String
        let value: String
        @Environment(\.themeColors) private var colors
        var body: some View {
            HStack(alignment: .firstTextBaseline) {
                Text(label).frame(width: 120, alignment: .leading)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                Text(value).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(colors.textPrimary)
                    .textSelection(.enabled)
                Spacer()
            }
        }
    }
}

// MARK: - FlowLayout helper for credits
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = makeRows(sizes: sizes, maxWidth: proposal.width ?? .greatestFiniteMagnitude)
        let width = proposal.width ?? rows.map(\.width).max() ?? 0
        let height = rows.enumerated().reduce(CGFloat.zero) { total, item in
            total + item.element.height + (item.offset == rows.count - 1 ? 0 : spacing)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = makeRows(sizes: sizes, maxWidth: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = sizes[index]
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct FlowRow {
        var indices: [Int]
        var width: CGFloat
        var height: CGFloat
    }

    private func makeRows(sizes: [CGSize], maxWidth: CGFloat) -> [FlowRow] {
        var rows: [FlowRow] = []
        var current = FlowRow(indices: [], width: 0, height: 0)

        for (index, size) in sizes.enumerated() {
            let proposedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty && proposedWidth > maxWidth {
                rows.append(current)
                current = FlowRow(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = proposedWidth
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
