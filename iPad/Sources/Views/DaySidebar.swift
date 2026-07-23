import SwiftUI

struct DaySidebar: View {
    @EnvironmentObject private var store: ScripterStore
    @Environment(\.palette) private var palette
    @State private var editingDayID: UUID?
    @State private var deleteRequest: DayDeleteRequest?

    private var lang: AppLanguage { store.language }

    private func requestDelete(_ day: ShootingDay) {
        let takes = day.scenes.reduce(0) { $0 + $1.shots.reduce(0) { $0 + $1.takes.count } }
        deleteRequest = DayDeleteRequest(id: day.id, label: day.label,
                                         sceneCount: day.scenes.count, takeCount: takes)
    }

    var body: some View {
        List(selection: Binding(
            get: { store.selectedDayID },
            set: { newID in
                store.selectedDayID = newID
                store.selectedSceneID = store.currentDay?.scenes.first?.id
                store.selectedShotID = store.currentScene?.shots.first?.id
                store.selectedTakeID = nil
            }
        )) {
            Section {
                ForEach(store.days) { day in
                    DayRow(day: day)
                        .tag(day.id)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                requestDelete(day)
                            } label: {
                                Label(L10n.t("删除", "Delete", language: lang), systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                editingDayID = day.id
                            } label: {
                                Label(L10n.t("编辑拍摄日", "Edit Day", language: lang), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                requestDelete(day)
                            } label: {
                                Label(L10n.t("删除", "Delete", language: lang), systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text(store.projectName)
                    .font(.headline)
                    .textCase(nil)
            } footer: {
                Text(L10n.t("共 \(store.totalTakeCount) 条 Take",
                            "\(store.totalTakeCount) takes total", language: lang))
            }
        }
        .sheet(item: Binding(
            get: { editingDayID.map { IDBox(id: $0) } },
            set: { editingDayID = $0?.id }
        )) { box in
            DayEditSheet(dayID: box.id)
        }
        .confirmationDialog(
            L10n.t("删除这个拍摄日？", "Delete this shooting day?", language: lang),
            isPresented: Binding(
                get: { deleteRequest != nil },
                set: { if !$0 { deleteRequest = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteRequest
        ) { req in
            Button(L10n.t("删除拍摄日", "Delete Day", language: lang), role: .destructive) {
                store.deleteDay(req.id)
            }
            Button(L10n.t("取消", "Cancel", language: lang), role: .cancel) {}
        } message: { req in
            let name = req.label.isEmpty ? L10n.t("未命名拍摄日", "Untitled Day", language: lang) : req.label
            Text(L10n.t(
                "“\(name)”：将删除 \(req.sceneCount) 场、\(req.takeCount) 条 Take，删除后无法恢复（可用撤销）。",
                "“\(name)”: removes \(req.sceneCount) scene\(req.sceneCount == 1 ? "" : "s") and \(req.takeCount) take\(req.takeCount == 1 ? "" : "s"). This cannot be undone except via Undo.",
                language: lang))
        }
    }
}

private struct DayDeleteRequest: Identifiable {
    let id: UUID
    let label: String
    let sceneCount: Int
    let takeCount: Int
}

private struct IDBox: Identifiable { let id: UUID }

private struct DayEditSheet: View {
    @EnvironmentObject private var store: ScripterStore
    @Environment(\.dismiss) private var dismiss
    let dayID: UUID
    private var lang: AppLanguage { store.language }

    private var day: ShootingDay? { store.days.first { $0.id == dayID } }

    var body: some View {
        NavigationStack {
            Form {
                if let day {
                    TextField(L10n.t("拍摄日名称", "Day label", language: lang), text: Binding(
                        get: { day.label },
                        set: { store.renameDay(dayID, label: $0) }))
                    DatePicker(L10n.t("日期", "Date", language: lang), selection: Binding(
                        get: { day.date },
                        set: { store.setDayDate(dayID, date: $0) }
                    ), displayedComponents: .date)
                }
            }
            .navigationTitle(L10n.t("编辑拍摄日", "Edit Day", language: lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("完成", "Done", language: lang)) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct DayRow: View {
    @EnvironmentObject private var store: ScripterStore
    let day: ShootingDay
    private var lang: AppLanguage { store.language }

    private var takeCount: Int {
        day.scenes.reduce(0) { $0 + $1.shots.reduce(0) { $0 + $1.takes.count } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(day.label.isEmpty ? L10n.t("未命名拍摄日", "Untitled Day", language: lang) : day.label)
                .font(.system(size: 15, weight: .semibold))
            HStack(spacing: 8) {
                Text(day.date.formatted(date: .abbreviated, time: .omitted))
                Text("·")
                Text(L10n.t("\(day.scenes.count) 场", "\(day.scenes.count) sc", language: lang))
                Text("·")
                Text(L10n.t("\(takeCount) 条", "\(takeCount) tk", language: lang))
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
