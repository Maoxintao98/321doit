import SwiftUI

struct TakeEditorColumn: View {
    @EnvironmentObject private var store: ScripterStore
    @Environment(\.palette) private var palette

    private var lang: AppLanguage { store.language }
    private var take: Take? { store.currentTake }

    var body: some View {
        Form {
            if let take {
                headerSection(take)
                statusSection(take)
                ratingSection(take)
                notesSection(take)
                cameraSection(take)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(take.map { "T\($0.takeNumber)" } ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Header

    private func headerSection(_ take: Take) -> some View {
        Section {
            LabeledContent(L10n.t("场 / 镜 / 条", "Scene / Shot / Take", language: lang)) {
                Text("\(take.sceneNumber) · \(take.shotNumber) · T\(take.takeNumber)")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
            }
        }
    }

    // MARK: Status

    private func statusSection(_ take: Take) -> some View {
        Section(L10n.t("状态", "Status", language: lang)) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 88), spacing: 8)],
                spacing: 8
            ) {
                ForEach(TakeStatus.selectable) { status in
                    Button {
                        store.updateCurrentTake {
                            $0.status = ($0.status == status) ? .unset : status
                        }
                    } label: {
                        Text(status.label(language: lang))
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(take.status == status ? status.tint(palette) : palette.field)
                            .foregroundStyle(take.status == status ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

            Toggle(isOn: Binding(
                get: { take.isCircleTake },
                set: { v in store.updateCurrentTake { $0.isCircleTake = v } }
            )) {
                Label(L10n.t("圈选", "Circle Take", language: lang), systemImage: "circle.circle")
            }
            .tint(palette.circle)

            Toggle(isOn: Binding(
                get: { take.pictureUsable },
                set: { v in store.updateCurrentTake { $0.pictureUsable = v } }
            )) {
                Label(L10n.t("画面可用", "Picture Usable", language: lang), systemImage: "photo")
            }

            Toggle(isOn: Binding(
                get: { take.soundUsable },
                set: { v in store.updateCurrentTake { $0.soundUsable = v } }
            )) {
                Label(L10n.t("声音可用", "Sound Usable", language: lang), systemImage: "waveform")
            }
        }
    }

    // MARK: Ratings

    private func ratingSection(_ take: Take) -> some View {
        Section(L10n.t("评分", "Ratings", language: lang)) {
            ratingRow(L10n.t("表演", "Performance", language: lang),
                      value: take.performanceRating) { v in
                store.updateCurrentTake { $0.performanceRating = v }
            }
            ratingRow(L10n.t("技术", "Technical", language: lang),
                      value: take.technicalRating) { v in
                store.updateCurrentTake { $0.technicalRating = v }
            }
        }
    }

    private func ratingRow(_ title: String, value: Int, set: @escaping (Int) -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 14))
            Spacer()
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        set(i)
                    } label: {
                        Image(systemName: i <= value ? "star.fill" : "star")
                            .foregroundStyle(i <= value ? palette.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Notes

    private func notesSection(_ take: Take) -> some View {
        Section(L10n.t("备注", "Notes", language: lang)) {
            noteEditor(L10n.t("通用备注", "General Note", language: lang),
                       text: Binding(
                        get: { take.generalNote },
                        set: { v in store.updateCurrentTake { $0.generalNote = v } }))
            noteEditor(L10n.t("表演备注", "Performance Note", language: lang),
                       text: Binding(
                        get: { take.performanceNote },
                        set: { v in store.updateCurrentTake { $0.performanceNote = v } }))
            noteEditor(L10n.t("技术备注", "Technical Note", language: lang),
                       text: Binding(
                        get: { take.technicalNote },
                        set: { v in store.updateCurrentTake { $0.technicalNote = v } }))
        }
    }

    private func noteEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(title, text: text, axis: .vertical)
                .lineLimit(2...5)
                .font(.system(size: 14))
        }
    }

    // MARK: Camera records

    private func cameraSection(_ take: Take) -> some View {
        Section(L10n.t("机位记录", "Camera Records", language: lang)) {
            ForEach(take.cameraRecords) { rec in
                CameraRecordEditor(record: rec)
            }
        }
    }
}

private struct CameraRecordEditor: View {
    @EnvironmentObject private var store: ScripterStore
    @Environment(\.palette) private var palette
    let record: CameraRecord
    private var lang: AppLanguage { store.language }

    private func update(_ mutate: @escaping (inout CameraRecord) -> Void) {
        store.updateCurrentTake { take in
            if let i = take.cameraRecords.firstIndex(where: { $0.id == record.id }) {
                mutate(&take.cameraRecords[i])
            }
        }
    }

    var body: some View {
        DisclosureGroup {
            VStack(spacing: 8) {
                Picker(L10n.t("状态", "Roll", language: lang), selection: Binding(
                    get: { record.rollState },
                    set: { v in update { $0.rollState = v } }
                )) {
                    ForEach(CameraRollState.allCases, id: \.self) { s in
                        Text(s.label(language: lang)).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                field(L10n.t("Clip 名", "Clip name", language: lang),
                      text: Binding(get: { record.clipName }, set: { v in update { $0.clipName = v } }))
                field(L10n.t("卡号", "Card", language: lang),
                      text: Binding(get: { record.cardName }, set: { v in update { $0.cardName = v } }))
                HStack(spacing: 8) {
                    field("TC In", text: Binding(get: { record.tcIn }, set: { v in update { $0.tcIn = v } }))
                    field("TC Out", text: Binding(get: { record.tcOut }, set: { v in update { $0.tcOut = v } }))
                }
                VStack(spacing: 0) {
                    Toggle(isOn: Binding(
                        get: { record.pictureAvailable }, set: { v in update { $0.pictureAvailable = v } })) {
                        Text(L10n.t("有画面", "Picture", language: lang)).font(.system(size: 14))
                    }
                    .frame(minHeight: 40)
                    Divider()
                    Toggle(isOn: Binding(
                        get: { record.audioAvailable }, set: { v in update { $0.audioAvailable = v } })) {
                        Text(L10n.t("有声音", "Audio", language: lang)).font(.system(size: 14))
                    }
                    .frame(minHeight: 40)
                }
                field(L10n.t("备注", "Notes", language: lang),
                      text: Binding(get: { record.notes }, set: { v in update { $0.notes = v } }))
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Text(record.cameraLabel)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(record.clipName.isEmpty ? record.rollState.label(language: lang) : record.clipName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .font(.system(size: 13))
            .textFieldStyle(.roundedBorder)
    }
}
