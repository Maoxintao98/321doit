import SwiftUI

struct TakeEditorView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @ObservedObject var store: ScriptLogStore

    private let quickTags = ["表演好", "虚焦", "穿帮", "收音问题", "笑场", "后半段可用", "导演喜欢"]
    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(spacing: 0) {
            if store.selectedTakeIDs.count > 1 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        batchControls
                        batchQuickTagsPanel()
                    }
                    .padding(20)
                    .padding(.bottom, 12)
                }
            } else if let take = store.currentTake {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        takeControls(take)
                        quickTagsPanel(take)
                        cameraRecordsPanel(take)
                        notesPanel(take)
                        takeStrip
                    }
                    .padding(20)
                    .padding(.bottom, 12)
                }
            } else {
                emptyState
            }
        }
        .background(colors.surfaceBg)
        .background {
            let shortcuts = settings.settings.shortcuts
            shortcutButton(shortcuts.nextTake, action: store.newNextTake)
            shortcutButton(shortcuts.nextShot, action: store.newNextShot)
            shortcutButton(shortcuts.nextScene, action: store.newNextScene)
            shortcutButton(shortcuts.markOK) { store.markStatus(.good) }
            shortcutButton(shortcuts.markKP) { store.markStatus(.hold) }
            shortcutButton(shortcuts.markNG) { store.markStatus(.ng) }
            shortcutButton(shortcuts.circleTake, action: store.toggleCircleTake)
            shortcutButton(shortcuts.faultEvent, action: store.toggleCurrentFaultEvent)
        }
    }

    private func shortcutButton(_ command: ShortcutCommand, action: @escaping () -> Void) -> some View {
        Button("", action: action)
            .keyboardShortcut(command.key.keyEquivalent, modifiers: command.modifiers)
            .opacity(0)
    }

    // MARK: - Batch Mode Views

    private var batchControls: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.t("批量编辑模式", "Batch Edit Mode", language: lang))
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Text(L10n.t("已选中 \(store.selectedTakeIDs.count) 个条次", "\(store.selectedTakeIDs.count) takes selected", language: lang))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(colors.toolAccent(.scriptLog))
            }

            VStack(alignment: .leading, spacing: 9) {
                panelLabel(L10n.t("将所选条次状态统一修改为：", "Set status for selected takes:", language: lang))
                HStack(spacing: 12) {
                    batchStatusAction(.good)
                    batchStatusAction(.hold)
                    batchStatusAction(.ng)
                }
            }
        }
        .padding(18)
        .background(colors.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(colors.hairline, lineWidth: 1)
        )
    }

    private func batchStatusAction(_ status: TakeStatus) -> some View {
        Button {
            store.batchMarkStatus(status)
        } label: {
            Text(status.label(language: lang))
                .font(.system(size: 12, weight: .bold))
                .frame(minWidth: 58)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(colors.textSecondary)
    }

    @ViewBuilder    private func actionButtons(add: @escaping () -> Void, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: remove) {
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Divider().frame(height: 12)

            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(colors.textSecondary)
        .background(colors.surfaceBg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(colors.hairline, lineWidth: 1))
    }

    private func statusToken<V: View>(title: String, value: String, @ViewBuilder controls: () -> V = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(colors.textTertiary)
            HStack(spacing: 8) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                controls()
            }
        }
        .frame(minWidth: 80, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(colors.inputBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func takeControls(_ take: Take) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.t("当前条次记录", "Current Take Record", language: lang))
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Text(LocalizedDisplay.projectName(store.project, language: lang))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer().frame(width: 16)
                Button(action: store.duplicateCurrentTake) {
                    Label(L10n.t("复制上一条", "Copy from Previous", language: lang), systemImage: "doc.on.doc")
                }
            }

            HStack(spacing: 12) {
                statusToken(title: L10n.t("拍摄日", "Day", language: lang), value: dayTitle(store.currentShootingDay)) {
                    actionButtons(add: store.addShootingDay, remove: store.deleteCurrentDay)
                }
                statusToken(title: L10n.t("日期", "Date", language: lang), value: dateLabel(store.currentShootingDay?.date))
                statusToken(title: L10n.t("场次", "Scene", language: lang), value: sceneDisplayTitle(store.currentScene?.sceneNumber ?? "")) {
                    actionButtons(add: store.newNextScene, remove: store.deleteCurrentScene)
                }
                statusToken(title: L10n.t("镜头", "Shot", language: lang), value: store.currentShot?.shotNumber ?? "-") {
                    actionButtons(add: store.newNextShot, remove: store.deleteCurrentShot)
                }
                statusToken(title: L10n.t("条次", "Take", language: lang), value: take.recordType == .faultEvent ? "X" : String(take.takeNumber)) {
                    actionButtons(add: store.newNextTake, remove: store.deleteCurrentTake)
                }
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    panelLabel(L10n.t("Take 状态", "Take Status", language: lang))
                    HStack(spacing: 12) {
                        statusAction(.good, take: take)
                        statusAction(.hold, take: take)
                        statusAction(.ng, take: take)
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    panelLabel(L10n.t("标记", "Flags", language: lang))
                    HStack(spacing: 12) {
                        Button {
                            store.toggleCircleTake()
                        } label: {
                            Label(L10n.t("优选条", "Circle Take", language: lang), systemImage: take.isCircleTake ? "circle.inset.filled" : "circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(take.isCircleTake ? colors.stateWarning : colors.toolAccent(.scriptLog))

                        Button {
                            store.toggleCurrentFaultEvent()
                        } label: {
                            Label(L10n.t("故障条", "Fault Event", language: lang), systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(take.recordType == .faultEvent ? colors.textSecondary : colors.stateFail)
                    }
                }
            }
        }
        .padding(18)
        .background(colors.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(colors.hairline, lineWidth: 1)
        )
    }

    private var combinedQuickTags: [String] {
        let base = ["Good Performance", "Soft Focus", "Boom in Shot", "Audio Issue", "Break Character", "Tail Only", "Director's Pick"]
        return base + settings.settings.general.customQuickTags
    }

    private func localizeTag(_ tag: String) -> String {
        switch tag {
        case "Good Performance", "表演好": return L10n.t("表演好", "Good Performance", language: lang)
        case "Soft Focus", "虚焦": return L10n.t("虚焦", "Soft Focus", language: lang)
        case "Boom in Shot", "穿帮": return L10n.t("穿帮", "Boom in Shot", language: lang)
        case "Audio Issue", "收音问题": return L10n.t("收音问题", "Audio Issue", language: lang)
        case "Break Character", "笑场": return L10n.t("笑场", "Break Character", language: lang)
        case "Tail Only", "后半段可用": return L10n.t("后半段可用", "Tail Only", language: lang)
        case "Director's Pick", "导演喜欢": return L10n.t("导演喜欢", "Director's Pick", language: lang)
        default: return tag
        }
    }

    private func quickTagsPanel(_ take: Take) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                panelLabel(L10n.t("快速标签", "Quick Tags", language: lang))
                Spacer()
                Button(action: addCustomTag) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.toolAccent(.scriptLog))
            }

            FlowLayout(spacing: 8) {
                ForEach(combinedQuickTags, id: \.self) { tag in
                    quickTagButton(tag, take: take)
                }
            }
        }
        .scriptPanel(colors: colors)
    }

    private func batchQuickTagsPanel() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                panelLabel(L10n.t("将标签应用到所有选中条次", "Apply tag to all selected takes", language: lang))
                Spacer()
                Button(action: addCustomTag) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.toolAccent(.scriptLog))
            }

            FlowLayout(spacing: 8) {
                ForEach(combinedQuickTags, id: \.self) { tag in
                    batchQuickTagButton(tag)
                }
            }
        }
        .scriptPanel(colors: colors)
    }

    private func batchQuickTagButton(_ tag: String) -> some View {
        Button {
            store.batchToggleQuickTag(tag)
        } label: {
            Text(localizeTag(tag))
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(colors.inputBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(colors.hairline, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !["Good Performance", "Soft Focus", "Boom in Shot", "Audio Issue", "Break Character", "Tail Only", "Director's Pick", "表演好", "虚焦", "穿帮", "收音问题", "笑场", "后半段可用", "导演喜欢"].contains(tag) {
                Button(L10n.t("删除标签", "Remove Tag", language: lang)) {
                    settings.settings.general.customQuickTags.removeAll(where: { $0 == tag })
                }
            }
        }
    }
    
    private func quickTagButton(_ tag: String, take: Take) -> some View {
        Button {
            store.toggleQuickTag(tag)
        } label: {
            Text(localizeTag(tag))
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(take.quickTags.contains(tag) ? colors.toolAccent(.scriptLog).opacity(0.2) : colors.inputBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(take.quickTags.contains(tag) ? colors.toolAccent(.scriptLog).opacity(0.7) : colors.hairline, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !["Good Performance", "Soft Focus", "Boom in Shot", "Audio Issue", "Break Character", "Tail Only", "Director's Pick", "表演好", "虚焦", "穿帮", "收音问题", "笑场", "后半段可用", "导演喜欢"].contains(tag) {
                Button(L10n.t("删除标签", "Remove Tag", language: lang)) {
                    settings.settings.general.customQuickTags.removeAll(where: { $0 == tag })
                }
            }
        }
    }

    private func addCustomTag() {
        let alert = NSAlert()
        alert.messageText = L10n.t("添加自定义标签", "Add Custom Tag", language: lang)
        alert.informativeText = L10n.t("输入新的快速标签名称：", "Enter new tag name:", language: lang)
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = input
        alert.addButton(withTitle: L10n.t("添加", "Add", language: lang))
        alert.addButton(withTitle: L10n.t("取消", "Cancel", language: lang))
        if alert.runModal() == .alertFirstButtonReturn {
            let newTag = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newTag.isEmpty && !combinedQuickTags.contains(newTag) {
                settings.settings.general.customQuickTags.append(newTag)
            }
        }
    }

    private func notesPanel(_ take: Take) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            panelLabel(L10n.t("备注", "Notes", language: lang))
            TextEditor(text: Binding(
                get: { store.currentTake?.generalNote ?? take.generalNote },
                set: { value in store.updateCurrentTake { $0.generalNote = value } }
            ))
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(minHeight: 76)
            .background(colors.inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .scriptPanel(colors: colors)
    }

    private func cameraRecordsPanel(_ take: Take) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                panelLabel(L10n.t("多机位记录", "Camera Records", language: lang))
                Spacer()
                Button(action: store.addCameraRecord) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.toolAccent(.scriptLog))
                .help(L10n.t("新增机位记录", "Add Camera Record", language: lang))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(take.cameraRecords) { record in
                        CameraRecordCard(record: record, store: store)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .scriptPanel(colors: colors)
    }

    private var takeStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            panelLabel(L10n.t("本镜条次", "Takes in This Shot", language: lang))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(store.currentShot?.takes ?? []) { take in
                        Button {
                            store.selectTake(take.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(take.recordType == .faultEvent ? L10n.t("条 X", "Take X", language: lang) : L10n.t("条 \(take.takeNumber)", "Take \(take.takeNumber)", language: lang))
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    if take.isCircleTake {
                                        Image(systemName: "circle.inset.filled")
                                            .font(.system(size: 10))
                                            .foregroundStyle(colors.stateWarning)
                                    }
                                }
                                Text(take.status.label(language: lang))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(statusColor(take.status))
                            }
                            .frame(width: 86, height: 52, alignment: .leading)
                            .padding(.horizontal, 8)
                            .background(store.selectedTakeID == take.id ? colors.toolAccent(.scriptLog).opacity(0.16) : colors.inputBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(store.selectedTakeID == take.id ? colors.toolAccent(.scriptLog).opacity(0.65) : colors.hairline, lineWidth: 0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .scriptPanel(colors: colors)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(colors.textSecondary)
            Text(L10n.t("还没有可编辑的条次", "No takes are available to edit", language: lang))
                .font(.system(size: 13, weight: .semibold))
            Button(L10n.t("新建条次", "New Take", language: lang), action: store.newNextTake)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusAction(_ status: TakeStatus, take: Take) -> some View {
        Button {
            store.markStatus(status)
        } label: {
            Text(status.label(language: lang))
                .font(.system(size: 12, weight: .semibold))
                .frame(minWidth: 58)
        }
        .buttonStyle(.bordered)
        .tint(take.status == status ? statusColor(status) : colors.toolAccent(.scriptLog))
    }

    private func availabilityButtons(isAvailable: Bool, set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 6) {
            availabilityButton(title: "可用", selected: isAvailable) { set(true) }
            availabilityButton(title: "不可用", selected: !isAvailable) { set(false) }
        }
    }

    private func availabilityButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selected ? colors.toolAccent(.scriptLog).opacity(0.18) : colors.inputBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(selected ? colors.toolAccent(.scriptLog).opacity(0.7) : colors.hairline, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func smallNoteEditor(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            TextEditor(text: text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 86)
                .background(colors.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func panelLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(colors.textSecondary)
    }

    private func statusColor(_ status: TakeStatus) -> Color {
        switch status {
        case .unset: return colors.textSecondary
        case .good: return colors.stateSuccess
        case .ng: return colors.stateFail
        case .hold: return colors.stateWarning
        case .reset: return colors.textSecondary
        case .wildTrack: return colors.toolAccent(.scriptLog)
        case .rehearsal: return colors.textTertiary
        }
    }

    private func dayTitle(_ day: ShootingDay?) -> String {
        LocalizedDisplay.dayTitle(day, language: lang)
    }

    private func sceneDisplayTitle(_ raw: String) -> String {
        LocalizedDisplay.sceneTitle(raw, language: lang)
    }

    private func dateLabel(_ date: Date?) -> String {
        guard let date else { return "-" }
        return dateFormatter.string(from: date)
    }

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter
    }
}

private struct CameraRecordCard: View {
    @Environment(\.themeColors) private var colors
    @EnvironmentObject private var settings: SettingsStore
    let record: CameraRecord
    @ObservedObject var store: ScriptLogStore

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private var registeredCards: [String] {
        store.project.cameraRegistry.flatMap(\.cardNames).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private var currentRecord: CameraRecord? {
        store.currentTake?.cameraRecords.first(where: { $0.id == record.id })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            clipField
            statusSection
            timingSection
            notesSection
        }
        .padding(18)
        .frame(width: 370, alignment: .topLeading)
        .background(colors.surfaceBg)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(colors.hairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(LocalizedDisplay.cameraLabel(record.cameraLabel, language: lang)) · \(clipDisplay)")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(L10n.t("卡号", "Card", language: lang)) \(cardDisplay)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                rollStatePicker
                moreMenu
            }
        }
    }

    private var clipField: some View {
        field(
            L10n.t("素材号", "Clip ID", language: lang),
            placeholder: L10n.t("未记录", "Not recorded", language: lang),
            text: Binding(
                get: { record.clipName },
                set: { value in update { $0.clipName = value } }
            )
        )
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.t("状态", "Status", language: lang))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            statusPicker
        }
    }

    private var timingSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            if registeredCards.isEmpty {
                field(
                    L10n.t("卡号", "Card", language: lang),
                    placeholder: L10n.t("未记录", "Not recorded", language: lang),
                    text: Binding(
                        get: { record.cardName },
                        set: { value in update { $0.cardName = value } }
                    )
                )
            } else {
                cardPicker
            }

            HStack(spacing: 10) {
                timecodeField(
                    L10n.t("入点", "In", language: lang),
                    text: Binding(
                        get: { record.tcIn },
                        set: { value in update { $0.tcIn = value } }
                    )
                )
                timecodeField(
                    L10n.t("出点", "Out", language: lang),
                    text: Binding(
                        get: { record.tcOut },
                        set: { value in update { $0.tcOut = value } }
                    )
                )
            }
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        let binding = Binding(
            get: { currentRecord?.notes ?? record.notes },
            set: { value in update { $0.notes = value } }
        )
        let currentNotes = currentRecord?.notes ?? record.notes
        let isLong = currentNotes.count > 30 || currentNotes.contains("\n")

        if isLong {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.t("备注", "Notes", language: lang))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                TextEditor(text: binding)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(height: 54)
                    .background(colors.inputBg)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(colors.hairline, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        } else {
            HStack(spacing: 6) {
                Text("\(L10n.t("备注", "Notes", language: lang))：")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                TextField(L10n.t("未记录", "Not recorded", language: lang), text: binding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(colors.inputBg)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(colors.hairline, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var rollStatePicker: some View {
        Picker("", selection: Binding(
            get: { record.rollState },
            set: { value in update { $0.rollState = value } }
        )) {
            ForEach(CameraRollState.allCases, id: \.self) { state in
                Text(state.label(language: lang)).tag(state)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 112)
    }

    private var moreMenu: some View {
        Menu {
            Button(L10n.t("删除此机位", "Remove Camera", language: lang), role: .destructive) {
                store.removeCameraRecord(id: record.id)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(colors.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var statusPicker: some View {
        Picker("", selection: Binding(
            get: { record.status },
            set: { value in update { $0.status = value } }
        )) {
            Text("OK").tag(TakeStatus.good)
            Text("KP").tag(TakeStatus.hold)
            Text("NG").tag(TakeStatus.ng)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 154)
    }

    private var cardPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("卡号", "Card", language: lang))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            Picker("", selection: Binding(
                get: { record.cardName },
                set: { value in update { $0.cardName = value } }
            )) {
                if record.cardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L10n.t("请选择", "Select", language: lang)).tag("")
                }
                ForEach(registeredCards, id: \.self) { card in
                    Text(card).tag(card)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 142, alignment: .leading)
        }
    }

    private func field(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(colors.inputBg)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(colors.hairline, lineWidth: 0.5))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func timecodeField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            TimeInputField(text: text, placeholder: "--:--:--:--", mode: .timecode(framesPerSecond: timecodeFramesPerSecond))
        }
    }

    private var timecodeFramesPerSecond: Int {
        if let planFrameRate = store.currentShootingDay?.callSheet.cameraPlans.first(where: { plan in
            Self.normalizedCameraLabel(plan.unitName) == Self.normalizedCameraLabel(record.cameraLabel)
        })?.frameRate,
           let fps = Self.nominalFramesPerSecond(from: planFrameRate) {
            return fps
        }
        let rational = settings.settings.handoff.frameRate.rational
        return max(1, Int((Double(rational.numerator) / Double(rational.denominator)).rounded()))
    }

    private static func nominalFramesPerSecond(from value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/", maxSplits: 1)
            if parts.count == 2,
               let numerator = Double(parts[0].filter { $0.isNumber || $0 == "." }),
               let denominator = Double(parts[1].filter { $0.isNumber || $0 == "." }),
               denominator > 0 {
                return Self.validFrameRate(Int((numerator / denominator).rounded()))
            }
        }
        var number = ""
        for character in trimmed {
            if character.isNumber || character == "." || character == "," {
                number.append(character == "," ? "." : character)
            } else if !number.isEmpty {
                break
            }
        }
        guard let fps = Double(number) else { return nil }
        return Self.validFrameRate(Int(fps.rounded()))
    }

    private static func validFrameRate(_ value: Int) -> Int? {
        (1...240).contains(value) ? value : nil
    }

    private static func normalizedCameraLabel(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func update(_ change: @escaping (inout CameraRecord) -> Void) {
        store.updateCameraRecord(id: record.id, update: change)
    }

    private var clipDisplay: String {
        let value = record.clipName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "--" : value
    }

    private var cardDisplay: String {
        let value = record.cardName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? L10n.t("未记录", "Not recorded", language: lang) : value
    }
}

private extension View {
    func scriptPanel(colors: ThemeColors) -> some View {
        self
            .padding(14)
            .background(colors.panelBg)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(colors.hairline, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
