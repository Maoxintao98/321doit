import AppKit
import SwiftUI

struct StoryboardAgentPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var store: StoryboardStore
    let scene: StoryboardScene

    @State private var instruction = ""
    @State private var preview: StoryboardPatchPreview?
    @State private var acceptedOperationIDs = Set<UUID>()
    @State private var isWorking = false
    @State private var panelMessage: String?
    @State private var showsLogs = false

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private func t(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: lang) }

    var body: some View {
        HStack(spacing: 0) {
            assistantColumn.frame(width: 340)
            Divider()
            previewColumn
        }
        .frame(minWidth: 1060, minHeight: 720)
    }

    private var assistantColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label(t("灵动助手", "Storyboard Assistant"), systemImage: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button { showsLogs.toggle() } label: { Image(systemName: "clock.arrow.circlepath") }
                        .buttonStyle(.borderless)
                        .help(t("助手操作记录", "Assistant activity"))
                }
                Text(t("根据当前场次生成可预览的修改建议", "Generate previewable edit suggestions for the current scene."))
                    .font(.system(size: 10)).foregroundStyle(colors.textSecondary)
            }
            .padding(18)

            Divider()

            if showsLogs {
                agentLogs
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(t("权限模式", "Permission Mode")).font(.system(size: 10, weight: .medium)).foregroundStyle(colors.textSecondary)
                        Spacer()
                        Picker("", selection: permissionBinding) {
                            Text(t("建议", "Suggest")).tag(StoryboardAgentPermissionMode.suggest)
                            Text(t("协作", "Collaborate")).tag(StoryboardAgentPermissionMode.collaborate)
                            Text(t("代理", "Agent")).tag(StoryboardAgentPermissionMode.proxy)
                        }
                        .labelsHidden()
                        .frame(width: 160)
                        .accessibilityIdentifier("storyboard.agent.permission")
                    }

                    TextEditor(text: $instruction)
                        .font(.system(size: 12))
                        .frame(minHeight: 170)
                        .padding(8)
                        .background(colors.inputBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(colors.hairline.opacity(0.8), lineWidth: 0.8))
                        .accessibilityIdentifier("storyboard.agent.instruction")

                    VStack(alignment: .leading, spacing: 7) {
                        Text(t("示例", "EXAMPLES")).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(colors.textSecondary)
                        suggestion(t("压缩到6个镜头、30秒内，最后一个镜头不能修改。", "Reduce to six shots within 30 seconds; do not change the final shot."))
                        suggestion(t("让人物显得更孤独，但不要修改锁定内容。", "Make the character feel more isolated without changing locked content."))
                        suggestion(t("预算有限，去掉需要轨道和摇臂的镜头运动。", "Budget is limited; remove moves that require a track or crane."))
                    }

                    Button(action: generateLocalPatch) {
                        Label(isWorking ? t("正在分析", "Analyzing") : t("生成安全修改方案", "Generate Safe Edit Plan"), systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("storyboard.agent.generate")

                    Text(t("修改会先预览，锁定的内容不会被更改。", "Edits are previewed first; locked content will not be changed."))
                        .font(.system(size: 9))
                        .foregroundStyle(colors.textTertiary)

                    if let panelMessage {
                        Text(panelMessage)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.orange)
                    }
                    Spacer()
                }
                .padding(18)
            }
        }
        .background(colors.panelBg)
    }

    @ViewBuilder
    private var previewColumn: some View {
        if let preview {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preview.patch.description).font(.system(size: 16, weight: .semibold))
                    }
                    Spacer()
                    metric(t("镜头", "Shots"), "\(preview.beforeShotCount) → \(preview.afterShotCount)")
                    metric(t("时长", "Duration"), "\(format(preview.beforeDurationSeconds)) → \(format(preview.afterDurationSeconds))")
                }
                .padding(.horizontal, 20)
                .frame(height: 74)
                Divider()

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(preview.diffs) { diff in
                            diffCard(diff)
                        }
                        if !preview.issues.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(t("模拟执行后的检查结果", "Post-Edit Validation"), systemImage: "checkmark.shield")
                                    .font(.system(size: 11, weight: .semibold))
                                ForEach(preview.issues.prefix(8)) { issue in
                                    Text("• \(issue.title)：\(issue.detail)")
                                        .font(.system(size: 9)).foregroundStyle(colors.textSecondary)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(colors.inputBg)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(18)
                }

                Divider()
                HStack {
                    Button(t("全部拒绝", "Reject All")) { acceptedOperationIDs.removeAll() }
                    Button(t("全部接受", "Accept All")) { acceptedOperationIDs = Set(preview.patch.operations.map(\.id)) }
                    Spacer()
                    Text(t("已选择 \(acceptedOperationIDs.count) / \(preview.patch.operations.count)", "Selected \(acceptedOperationIDs.count) / \(preview.patch.operations.count)"))
                        .font(.system(size: 10)).foregroundStyle(colors.textSecondary)
                    Button(t("关闭", "Close")) { dismiss() }
                    Button(t("应用所选修改", "Apply Selected Edits")) { applyPatch() }
                        .buttonStyle(.borderedProminent)
                        .disabled(acceptedOperationIDs.isEmpty || currentPermission == .suggest)
                        .accessibilityIdentifier("storyboard.agent.apply")
                }
                .padding(.horizontal, 20)
                .frame(height: 60)
            }
        } else {
            VStack(spacing: 14) {
                Image(systemName: "rectangle.2.swap")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(ToolAccent.storyboard.primary)
                Text(t("修改方案会先显示在这里", "Your edit plan will appear here")).font(.system(size: 16, weight: .semibold))
                Text(t("原方案、新方案、顺序、属性、时长、风险与修改原因都会在提交前展示。", "Before applying, you can review the original and proposed values, order, properties, duration, risk, and reason for every change."))
                    .font(.system(size: 10)).foregroundStyle(colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var agentLogs: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                let logs = (store.document.production?.agentLogs ?? []).reversed()
                if logs.isEmpty {
                    Text(t("暂无助手操作记录", "No assistant activity yet"))
                        .font(.system(size: 10)).foregroundStyle(colors.textSecondary)
                        .padding(.top, 30)
                }
                ForEach(Array(logs)) { log in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(log.agentName).font(.system(size: 10, weight: .semibold))
                            Spacer()
                            Text(log.createdAt.formatted(date: .numeric, time: .shortened))
                                .font(.system(size: 8)).foregroundStyle(colors.textTertiary)
                        }
                        Text(log.userInstruction).font(.system(size: 9)).lineLimit(3)
                        Text(log.result).font(.system(size: 9)).foregroundStyle(colors.textSecondary)
                    }
                    .padding(10)
                    .background(colors.inputBg)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }
            }
            .padding(14)
        }
    }

    private func diffCard(_ diff: StoryboardPatchDiff) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { acceptedOperationIDs.contains(diff.operationID) },
                set: { enabled in
                    if enabled { acceptedOperationIDs.insert(diff.operationID) }
                    else { acceptedOperationIDs.remove(diff.operationID) }
                    refreshPreview()
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(diff.title).font(.system(size: 12, weight: .semibold))
                    riskBadge(diff.risk)
                    Spacer()
                    Text(changeLabel(diff.kind)).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(colors.textSecondary)
                }
                HStack(alignment: .top, spacing: 10) {
                    comparison(t("原方案", "Before"), diff.before, color: .red.opacity(0.08))
                    Image(systemName: "arrow.right").foregroundStyle(colors.textTertiary)
                    comparison(t("新方案", "After"), diff.after, color: .green.opacity(0.08))
                }
                Label(diff.reason, systemImage: "text.bubble")
                    .font(.system(size: 9)).foregroundStyle(colors.textSecondary)
            }
        }
        .padding(14)
        .background(colors.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(colors.hairline.opacity(0.75), lineWidth: 0.8))
    }

    private func comparison(_ title: String, _ text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(colors.textSecondary)
            Text(text).font(.system(size: 9)).lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .background(color)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func suggestion(_ value: String) -> some View {
        Button {
            instruction = value
        } label: {
            Text(value)
                .font(.system(size: 9))
                .foregroundStyle(colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(colors.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 8, weight: .medium)).foregroundStyle(colors.textSecondary)
            Text(value).font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(colors.inputBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func riskBadge(_ risk: StoryboardPatchRisk) -> some View {
        Text(risk == .high ? t("高风险", "High Risk") : risk == .medium ? t("中风险", "Medium Risk") : t("低风险", "Low Risk"))
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(risk == .high ? Color.red : risk == .medium ? Color.orange : Color.green)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background((risk == .high ? Color.red : risk == .medium ? Color.orange : Color.green).opacity(0.1))
            .clipShape(Capsule())
    }

    private var permissionBinding: Binding<StoryboardAgentPermissionMode> {
        Binding(get: { currentPermission }, set: { value in
            var production = store.document.production ?? StoryboardProductionData()
            production.agentPermissionMode = value
            store.perform(title: t("修改Agent权限", "Change Assistant Permission"), mutations: [.updateProduction(production)])
        })
    }

    private var currentPermission: StoryboardAgentPermissionMode {
        store.document.production?.agentPermissionMode ?? .collaborate
    }

    private func generateLocalPatch() {
        isWorking = true
        defer { isWorking = false }
        do {
            let patch = try StoryboardLocalAgent.propose(instruction: instruction, document: store.document, scene: scene, language: lang)
            let defaultAcceptedOperationIDs = Set(
                patch.operations
                    .filter { $0.risk != .high }
                    .map(\.id)
            )
            let generated = try store.previewPatch(
                patch,
                accepting: defaultAcceptedOperationIDs,
                language: lang
            )
            preview = generated
            acceptedOperationIDs = defaultAcceptedOperationIDs
            panelMessage = nil
        } catch {
            panelMessage = error.localizedDescription
        }
    }

    private func refreshPreview() {
        guard let patch = preview?.patch else { return }
        do {
            preview = try store.previewPatch(patch, accepting: acceptedOperationIDs, language: lang)
            panelMessage = nil
        } catch {
            panelMessage = error.localizedDescription
        }
    }

    private func applyPatch() {
        guard let patch = preview?.patch else { return }
        if store.applyPatch(
            patch,
            accepting: acceptedOperationIDs,
            authorization: .appUserConfirmed(),
            language: lang
        ) {
            panelMessage = t("修改已作为一个事务应用，可在工作台一键撤销。", "Edits were applied as one transaction and can be undone from the workspace.")
            preview = nil
        } else {
            panelMessage = store.errorMessage
        }
    }

    private func format(_ seconds: Double) -> String { String(format: "%.1fs", seconds) }
    private func changeLabel(_ kind: StoryboardPatchChangeKind) -> String {
        switch kind { case .created: return t("新增", "Added"); case .updated: return t("修改", "Changed"); case .deleted: return t("删除", "Deleted"); case .moved: return t("重排", "Reordered") }
    }
}
