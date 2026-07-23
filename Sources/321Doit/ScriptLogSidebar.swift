import Foundation
import SwiftUI

private enum SidebarDeleteTarget {
    case day(UUID)
    case scene(dayID: UUID, sceneID: UUID)
    case shot(dayID: UUID, sceneID: UUID, shotID: UUID)
    case take(dayID: UUID, sceneID: UUID, shotID: UUID, takeID: UUID)
}

struct ScriptLogSidebar: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @ObservedObject var store: ScriptLogStore
    @State private var focusedDeleteTarget: SidebarDeleteTarget?

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    dayCards
                    Divider()
                    allDaysBreakdown
                }
                .padding(.bottom, 14)
            }
        }
        .padding(14)
        .background(colors.panelBg)
        .onDeleteCommand(perform: deleteFocusedSidebarItem)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("拍摄日", "Shooting Days", language: lang))
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(store.project.shootingDays.count) \(L10n.t("天", "days", language: lang)) · \(store.takeCount) \(L10n.t("条", "takes", language: lang))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()

                Button(action: store.toggleBatchMode) {
                    Image(systemName: store.isBatchMode ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(store.isBatchMode ? colors.toolAccent(.scriptLog) : colors.textSecondary)
                .accessibilityIdentifier("scriptLog.batchMode")
                .help(L10n.t("批量编辑模式", "Batch Edit Mode", language: lang))

                Button(action: store.importScripterFile) {
                    Image(systemName: "ipad.and.arrow.forward")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.toolAccent(.scriptLog))
                .accessibilityIdentifier("scriptLog.import")
                .help(L10n.t("导入 iPad 场记（.321log）", "Import iPad Script Log (.321log)", language: lang))

                Button(action: store.addShootingDay) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.toolAccent(.scriptLog))
                .accessibilityIdentifier("scriptLog.addShootingDay")
                .help(L10n.t("新增拍摄日", "Add Shooting Day", language: lang))
            }
        }
    }

    private var dayCards: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.project.shootingDays) { day in
                let isSelected = store.selectedShootingDayID == day.id
                let isExpanded = store.expandedDayIDs.contains(day.id)

                Button {
                    focusedDeleteTarget = .day(day.id)
                    if isSelected {
                        store.toggleDayExpanded(day.id)
                    } else {
                        store.selectShootingDay(day.id)
                    }
                } label: {
                    HStack(spacing: 9) {
                        disclosureIcon(isExpanded: isExpanded)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(dayTitle(day))
                                .font(.system(size: 13, weight: .semibold))
                            Text(dayFormatter.string(from: day.date))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(colors.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(day.scenes.count) \(L10n.t("场", "scenes", language: lang))")
                            Text("\(shotCount(in: day)) \(L10n.t("镜", "shots", language: lang)) · \(takeCount(in: day)) \(L10n.t("条", "takes", language: lang))")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(colors.textSecondary)
                    }
                    .padding(10)
                    .background(isSelected ? colors.toolAccent(.scriptLog).opacity(0.16) : colors.inputBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isSelected ? colors.toolAccent(.scriptLog).opacity(0.6) : colors.hairline, lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var allDaysBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("拍摄日明细", "Day Details", language: lang))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            ForEach(store.project.shootingDays) { day in
                dayBreakdownBlock(day)
            }
        }
    }

    private func dayBreakdownBlock(_ day: ShootingDay) -> some View {
        let isSelected = store.selectedShootingDayID == day.id
        let isExpanded = store.expandedDayIDs.contains(day.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    focusedDeleteTarget = .day(day.id)
                    if isSelected {
                        store.toggleDayExpanded(day.id)
                    } else {
                        store.selectShootingDay(day.id)
                    }
                } label: {
                    HStack(spacing: 7) {
                        disclosureIcon(isExpanded: isExpanded)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedDisplay.dayTitle(day, language: lang))
                                .font(.system(size: 12, weight: .semibold))
                            Text(dayFormatter.string(from: day.date))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(colors.textSecondary)
                        }
                        Spacer()
                        Text("\(day.scenes.count) \(L10n.t("场", "scenes", language: lang)) · \(shotCount(in: day)) \(L10n.t("镜", "shots", language: lang)) · \(takeCount(in: day)) \(L10n.t("条", "takes", language: lang))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(colors.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    store.selectShootingDay(day.id)
                    store.newNextScene()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(colors.toolAccent(.scriptLog))
                .help(L10n.t("新增场次", "Add Scene", language: lang))
            }

            if isExpanded {
                ForEach(day.scenes) { scene in
                    sceneBlock(scene, day: day)
                }
            }
        }
    }

    private func sceneBlock(_ scene: ScriptScene, day: ShootingDay) -> some View {
        let isSelected = store.selectedSceneID == scene.id
        let isExpanded = store.expandedSceneIDs.contains(scene.id)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    disclosureIcon(isExpanded: isExpanded)
                    EditableSceneTitle(scene: scene, store: store, lang: lang)
                    Spacer()
                    Text("\(scene.shots.count) \(L10n.t("镜", "shots", language: lang)) · \(sceneTakeCount(scene)) \(L10n.t("条", "takes", language: lang))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(isSelected ? colors.toolAccent(.scriptLog).opacity(0.13) : colors.surfaceBg)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedDeleteTarget = .scene(dayID: day.id, sceneID: scene.id)
                    if isSelected {
                        store.toggleSceneExpanded(scene.id)
                    } else {
                        store.selectShootingDay(day.id)
                        store.selectScene(scene.id)
                    }
                }

                if isSelected {
                    Button {
                        store.selectShootingDay(day.id)
                        store.selectScene(scene.id)
                        store.newNextShot()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(colors.toolAccent(.scriptLog))
                    .help(L10n.t("新增镜头", "Add Shot", language: lang))
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(scene.shots) { shot in
                        shotBlock(shot, scene: scene, day: day)
                    }
                }
                .padding(.leading, 8)
            }
        }
    }

    private func shotBlock(_ shot: Shot, scene: ScriptScene, day: ShootingDay) -> some View {
        let isSelected = store.selectedShotID == shot.id
        let isExpanded = store.expandedShotIDs.contains(shot.id)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    disclosureIcon(isExpanded: isExpanded)
                    Text(shotTitle(shot))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(isSelected ? colors.toolAccent(.scriptLog).opacity(0.12) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedDeleteTarget = .shot(dayID: day.id, sceneID: scene.id, shotID: shot.id)
                    if isSelected {
                        store.toggleShotExpanded(shot.id)
                    } else {
                        store.selectShootingDay(day.id)
                        store.selectScene(scene.id)
                        store.selectShot(shot.id)
                    }
                }

                if isSelected {
                    Button {
                        store.selectShootingDay(day.id)
                        store.selectScene(scene.id)
                        store.selectShot(shot.id)
                        store.newNextTake()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(colors.toolAccent(.scriptLog))
                    .help(L10n.t("新增条次", "Add Take", language: lang))
                }
            }

            if isExpanded {
                takeStripBlock(shot, scene: scene, day: day)
                    .padding(.leading, 26)
            }
        }
    }

    private func takeStripBlock(_ shot: Shot, scene: ScriptScene, day: ShootingDay) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(shot.takes) { take in
                    Text(take.recordType == .faultEvent ? "X" : "\(take.takeNumber)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .frame(width: 28, height: 24)
                        .background(takeBackground(for: take))
                        .foregroundStyle(take.isCircleTake ? colors.stateWarning : (take.recordType == .faultEvent ? colors.stateFail : statusColor(take.status)))
                        .overlay(
                            store.isBatchMode && store.selectedTakeIDs.contains(take.id) ?
                            RoundedRectangle(cornerRadius: 5).strokeBorder(colors.toolAccent(.scriptLog), lineWidth: 1.5) : nil
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .onTapGesture {
                            let isShift = NSEvent.modifierFlags.contains(.shift)
                            let isCmd = NSEvent.modifierFlags.contains(.command)
                            focusedDeleteTarget = .take(dayID: day.id, sceneID: scene.id, shotID: shot.id, takeID: take.id)
                            store.selectShootingDay(day.id)
                            store.selectScene(scene.id)
                            store.selectShot(shot.id)
                            store.selectTake(take.id, isShift: isShift, isCommand: isCmd)
                        }
                        .contextMenu {
                            Button {
                                store.selectShootingDay(day.id)
                                store.selectScene(scene.id)
                                store.selectShot(shot.id)
                                store.selectTake(take.id)
                                store.duplicateCurrentTake()
                            } label: {
                                Label(L10n.t("复制此条", "Duplicate Take", language: lang), systemImage: "plus.square.on.square")
                            }
                            Divider()
                            Button(role: .destructive) {
                                store.selectShootingDay(day.id)
                                store.selectScene(scene.id)
                                store.selectShot(shot.id)
                                store.selectTake(take.id)
                                store.deleteCurrentTake()
                            } label: {
                                Label(L10n.t("删除此条", "Delete Take", language: lang), systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func deleteFocusedSidebarItem() {
        guard let focusedDeleteTarget else {
            store.deleteSelectedHierarchyItem()
            return
        }

        switch focusedDeleteTarget {
        case .day(let dayID):
            store.selectShootingDay(dayID)
            store.deleteCurrentDay()
        case .scene(let dayID, let sceneID):
            store.selectShootingDay(dayID)
            store.selectScene(sceneID)
            store.deleteCurrentScene()
        case .shot(let dayID, let sceneID, let shotID):
            store.selectShootingDay(dayID)
            store.selectScene(sceneID)
            store.selectShot(shotID)
            store.deleteCurrentShot()
        case .take(let dayID, let sceneID, let shotID, let takeID):
            store.selectShootingDay(dayID)
            store.selectScene(sceneID)
            store.selectShot(shotID)
            store.selectTake(takeID)
            store.deleteCurrentTake()
        }
        self.focusedDeleteTarget = nil
    }

    private func shotTitle(_ shot: Shot) -> String {
        let rawShot = shot.shotNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawShot.isEmpty {
            return L10n.t("未填镜", "No shot", language: lang)
        }
        if lang.resolved == .zh {
            return "\(rawShot)镜"
        } else {
            return "Shot \(rawShot)"
        }
    }

    private func disclosureIcon(isExpanded: Bool) -> some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(colors.toolAccent(.scriptLog))
            .frame(width: 14, alignment: .center)
    }

    private func shotCount(in day: ShootingDay) -> Int {
        day.scenes.reduce(0) { $0 + $1.shots.count }
    }

    private func takeCount(in day: ShootingDay) -> Int {
        day.scenes.reduce(0) { sceneTotal, scene in
            sceneTotal + scene.shots.reduce(0) { $0 + $1.takes.count }
        }
    }

    private func sceneTakeCount(_ scene: ScriptScene) -> Int {
        scene.shots.reduce(0) { $0 + $1.takes.count }
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

    private func takeBackground(for take: Take) -> Color {
        if store.selectedTakeID == take.id {
            return colors.toolAccent(.scriptLog).opacity(0.28)
        }
        if store.isBatchMode && store.selectedTakeIDs.contains(take.id) {
            return colors.toolAccent(.scriptLog).opacity(0.16)
        }
        return colors.inputBg
    }

    private func dayTitle(_ day: ShootingDay) -> String {
        LocalizedDisplay.dayTitle(day, language: lang)
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

private struct EditableSceneTitle: View {
    @Environment(\.themeColors) private var colors
    let scene: ScriptScene
    @ObservedObject var store: ScriptLogStore
    var lang: AppLanguage
    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField(L10n.t("场号", "Scene #", language: lang), text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .focused($isFieldFocused)
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
                    .onAppear {
                        draft = scene.sceneNumber
                        isFieldFocused = true
                    }
                    .onChange(of: isFieldFocused) { focused in
                        if !focused {
                            commit()
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(width: 118, alignment: .leading)
                    .background(colors.inputBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(colors.toolAccent(.scriptLog).opacity(0.45), lineWidth: 0.8)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                Text(LocalizedDisplay.sceneTitle(scene.sceneNumber, language: lang))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                    .help(L10n.t("双击编辑场号", "Double-click to edit scene #", language: lang))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2, perform: beginEditing)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isEditing)
    }

    private func beginEditing() {
        draft = scene.sceneNumber
        isEditing = true
    }

    private func commit() {
        guard isEditing else { return }
        store.updateSceneNumber(id: scene.id, value: draft.trimmingCharacters(in: .whitespacesAndNewlines))
        isEditing = false
    }

    private func cancel() {
        isEditing = false
        draft = scene.sceneNumber
    }
}
