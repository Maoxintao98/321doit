import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var store: ScripterStore
    @State private var section: ScheduleSection = .overview

    private var lang: AppLanguage { store.language }

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedDayID) {
                ForEach(store.days) { day in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(day.label).font(.body.weight(.semibold))
                        Text(day.date, style: .date).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(day.id)
                }
            }
            .navigationTitle(L10n.t("拍摄日", "Shooting Days", language: lang))
            .toolbar {
                Button { store.addDay() } label: { Image(systemName: "plus") }
            }
        } detail: {
            if store.currentDay != nil {
                VStack(spacing: 0) {
                    ScheduleSectionBar(selection: $section)
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    Group {
                        switch section {
                        case .overview: CallSheetOverview()
                        case .timeline: TimelineEditor()
                        case .people: PeopleEditor()
                        case .dit: DITPlanEditor()
                        }
                    }
                }
            } else {
                ContentUnavailableView(L10n.t("选择拍摄日", "Select a shooting day", language: lang),
                                       systemImage: "calendar")
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct ScheduleSectionBar: View {
    @EnvironmentObject private var store: ScripterStore
    @Binding var selection: ScheduleSection

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ScheduleSection.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { selection = item }
                } label: {
                    Text(item.title(store.language))
                        .font(.subheadline.weight(selection == item ? .semibold : .regular))
                        .foregroundStyle(selection == item ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                        .background {
                            if selection == item {
                                Capsule()
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color(uiColor: .secondarySystemFill), in: Capsule())
    }
}

private enum ScheduleSection: String, CaseIterable, Identifiable {
    case overview, timeline, people, dit
    var id: String { rawValue }
    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .overview: return L10n.t("概览", "Overview", language: lang)
        case .timeline: return L10n.t("时间表", "Timeline", language: lang)
        case .people: return L10n.t("人员", "People", language: lang)
        case .dit: return "DIT"
        }
    }
}

private struct CallSheetOverview: View {
    @EnvironmentObject private var store: ScripterStore
    private var lang: AppLanguage { store.language }

    var body: some View {
        Form {
            Section(L10n.t("通告", "Call Sheet", language: lang)) {
                TextField(L10n.t("标题", "Title", language: lang), text: callSheet(\.title))
                Picker(L10n.t("类型", "Type", language: lang), selection: callSheet(\.type)) {
                    ForEach(ShootingDayType.allCases) { Text($0.label(language: lang)).tag($0) }
                }
                Picker(L10n.t("状态", "Status", language: lang), selection: callSheet(\.status)) {
                    ForEach(ShootingDayCallSheetStatus.allCases) { Text($0.label(language: lang)).tag($0) }
                }
            }
            Section(L10n.t("时间", "Time", language: lang)) {
                TextField(L10n.t("集合", "Crew call", language: lang), text: callSheet(\.callTime))
                TextField(L10n.t("预计开机", "Estimated start", language: lang), text: callSheet(\.estimatedStartTime))
                TextField(L10n.t("预计收工", "Estimated wrap", language: lang), text: callSheet(\.estimatedWrapTime))
            }
            Section(L10n.t("地点与天气", "Location & Weather", language: lang)) {
                TextField(L10n.t("主拍摄地", "Main location", language: lang), text: callSheet(\.mainLocation))
                TextField(L10n.t("集合点", "Meeting point", language: lang), text: location(\.meetingPoint))
                TextField(L10n.t("停车位置", "Parking", language: lang), text: location(\.parkingLocation))
                TextField(L10n.t("最近医院", "Nearest hospital", language: lang), text: location(\.nearestHospital))
                TextField(L10n.t("天气备注", "Weather note", language: lang), text: callSheet(\.weatherNote), axis: .vertical)
            }
            Section(L10n.t("现场备注", "On-set notes", language: lang)) {
                TextField(L10n.t("需要全组知道的内容", "What everyone needs to know", language: lang),
                          text: callSheet(\.generalNote), axis: .vertical)
                    .lineLimit(3...8)
            }
        }
    }

    private func callSheet<Value>(_ keyPath: WritableKeyPath<ShootingDayCallSheet, Value>) -> Binding<Value> {
        Binding(
            get: { store.currentCallSheet?[keyPath: keyPath] ?? fallback(keyPath) },
            set: { value in store.updateCurrentCallSheet { $0[keyPath: keyPath] = value } })
    }

    private func location(_ keyPath: WritableKeyPath<LocationInfo, String>) -> Binding<String> {
        Binding(
            get: { store.currentCallSheet?.locationInfo[keyPath: keyPath] ?? "" },
            set: { value in store.updateCurrentCallSheet { $0.locationInfo[keyPath: keyPath] = value } })
    }

    private func fallback<Value>(_ keyPath: WritableKeyPath<ShootingDayCallSheet, Value>) -> Value {
        ShootingDayCallSheet()[keyPath: keyPath]
    }
}

private struct TimelineEditor: View {
    @EnvironmentObject private var store: ScripterStore
    private var lang: AppLanguage { store.language }

    var body: some View {
        List {
            ForEach(store.currentCallSheet?.timeline ?? []) { item in
                HStack(spacing: 12) {
                    TextField("00:00", text: field(item.id, \.time))
                        .frame(width: 72)
                        .font(.body.monospacedDigit())
                    TextField(L10n.t("事项", "Item", language: lang), text: field(item.id, \.title))
                    Toggle("", isOn: boolField(item.id, \.isKeyMilestone))
                        .labelsHidden()
                }
            }
            .onDelete { indexes in
                store.updateCurrentCallSheet { sheet in
                    sheet.timeline.remove(atOffsets: indexes)
                }
            }

            Button {
                store.updateCurrentCallSheet { $0.timeline.append(DayTimelineItem()) }
            } label: {
                Label(L10n.t("添加事项", "Add item", language: lang), systemImage: "plus")
            }
        }
    }

    private func field(_ id: UUID, _ keyPath: WritableKeyPath<DayTimelineItem, String>) -> Binding<String> {
        Binding(
            get: { store.currentCallSheet?.timeline.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { value in
                store.updateCurrentCallSheet { sheet in
                    guard let index = sheet.timeline.firstIndex(where: { $0.id == id }) else { return }
                    sheet.timeline[index][keyPath: keyPath] = value
                }
            })
    }

    private func boolField(_ id: UUID, _ keyPath: WritableKeyPath<DayTimelineItem, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.currentCallSheet?.timeline.first(where: { $0.id == id })?[keyPath: keyPath] ?? false },
            set: { value in
                store.updateCurrentCallSheet { sheet in
                    guard let index = sheet.timeline.firstIndex(where: { $0.id == id }) else { return }
                    sheet.timeline[index][keyPath: keyPath] = value
                }
            })
    }
}

private struct PeopleEditor: View {
    @EnvironmentObject private var store: ScripterStore
    private var lang: AppLanguage { store.language }

    var body: some View {
        Form {
            Section(L10n.t("演员", "Cast", language: lang)) {
                ForEach(store.currentCallSheet?.castCalls ?? []) { call in
                    HStack {
                        TextField(L10n.t("演员", "Performer", language: lang), text: castField(call.id, \.performerName))
                        TextField(L10n.t("角色", "Character", language: lang), text: castField(call.id, \.characterName))
                        TextField(L10n.t("到场", "Call", language: lang), text: castField(call.id, \.callTime))
                            .frame(width: 80)
                    }
                }
                Button {
                    store.updateCurrentCallSheet { $0.castCalls.append(CastCall()) }
                } label: { Label(L10n.t("添加演员", "Add cast", language: lang), systemImage: "plus") }
            }

            Section(L10n.t("部门", "Departments", language: lang)) {
                ForEach(store.currentCallSheet?.departmentCalls ?? []) { call in
                    HStack {
                        TextField(L10n.t("部门", "Department", language: lang), text: departmentField(call.id, \.departmentName))
                        TextField(L10n.t("负责人", "Lead", language: lang), text: departmentField(call.id, \.leadName))
                        TextField(L10n.t("到场", "Call", language: lang), text: departmentField(call.id, \.callTime))
                            .frame(width: 80)
                    }
                }
                Button {
                    store.updateCurrentCallSheet { $0.departmentCalls.append(DepartmentCall()) }
                } label: { Label(L10n.t("添加部门", "Add department", language: lang), systemImage: "plus") }
            }
        }
    }

    private func castField(_ id: UUID, _ keyPath: WritableKeyPath<CastCall, String>) -> Binding<String> {
        Binding(
            get: { store.currentCallSheet?.castCalls.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { value in store.updateCurrentCallSheet { sheet in
                guard let index = sheet.castCalls.firstIndex(where: { $0.id == id }) else { return }
                sheet.castCalls[index][keyPath: keyPath] = value
            }})
    }

    private func departmentField(_ id: UUID, _ keyPath: WritableKeyPath<DepartmentCall, String>) -> Binding<String> {
        Binding(
            get: { store.currentCallSheet?.departmentCalls.first(where: { $0.id == id })?[keyPath: keyPath] ?? "" },
            set: { value in store.updateCurrentCallSheet { sheet in
                guard let index = sheet.departmentCalls.firstIndex(where: { $0.id == id }) else { return }
                sheet.departmentCalls[index][keyPath: keyPath] = value
            }})
    }
}

private struct DITPlanEditor: View {
    @EnvironmentObject private var store: ScripterStore
    private var lang: AppLanguage { store.language }

    var body: some View {
        Form {
            Section("DIT") {
                TextField(L10n.t("负责人", "DIT", language: lang), text: field(\.ditName))
                Picker(L10n.t("校验", "Checksum", language: lang), selection: field(\.checksumAlgorithm)) {
                    Text("SHA-256").tag("SHA-256")
                    Text("xxHash64").tag("xxHash64")
                }
                TextField(L10n.t("主备份盘", "Primary destination", language: lang), text: field(\.primaryDestinationName))
                TextField(L10n.t("第二备份盘", "Backup destination", language: lang), text: field(\.backupDestinationName))
            }
            Section(L10n.t("交接", "Handoff", language: lang)) {
                Toggle(L10n.t("生成校验报告", "Generate verification report", language: lang),
                       isOn: boolField(\.shouldGeneratePDFReport))
                Toggle(L10n.t("生成后期交接包", "Generate handoff package", language: lang),
                       isOn: boolField(\.shouldGenerateHandoffPackage))
                TextField(L10n.t("备注", "Notes", language: lang), text: field(\.note), axis: .vertical)
            }
        }
    }

    private func field(_ keyPath: WritableKeyPath<DITPlan, String>) -> Binding<String> {
        Binding(
            get: { store.currentCallSheet?.ditPlan[keyPath: keyPath] ?? "" },
            set: { value in store.updateCurrentCallSheet { $0.ditPlan[keyPath: keyPath] = value } })
    }

    private func boolField(_ keyPath: WritableKeyPath<DITPlan, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.currentCallSheet?.ditPlan[keyPath: keyPath] ?? false },
            set: { value in store.updateCurrentCallSheet { $0.ditPlan[keyPath: keyPath] = value } })
    }
}
