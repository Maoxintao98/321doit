import SwiftUI

struct SceneShotColumn: View {
    @EnvironmentObject private var store: ScripterStore
    @Environment(\.palette) private var palette

    private var lang: AppLanguage { store.language }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let day = store.currentDay {
                        ForEach(day.scenes) { scene in
                            SceneCard(scene: scene)
                                .id(scene.id)
                        }
                    }
                    Button {
                        store.addScene()
                    } label: {
                        Label(L10n.t("新建场", "Add Scene", language: lang), systemImage: "plus.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
                .padding(16)
            }
            // Follow newly added / selected takes into view.
            .onChange(of: store.selectedTakeID) { _, newID in
                guard let newID else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
            // Follow a newly added scene into view (new scene has no takes yet,
            // so selectedTakeID stays nil — track the scene selection instead).
            .onChange(of: store.selectedSceneID) { _, newID in
                guard let newID, store.selectedTakeID == nil else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
        .background(palette.background)
        .navigationTitle(store.currentDay?.label ?? "")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SceneCard: View {
    @EnvironmentObject private var store: ScripterStore
    @Environment(\.palette) private var palette
    let scene: ScriptScene
    private var lang: AppLanguage { store.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(L10n.t("场", "SC", language: lang))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                TextField(L10n.t("场号", "Scene #", language: lang), text: Binding(
                    get: { scene.sceneNumber },
                    set: { v in store.updateScene(scene.id) { $0.sceneNumber = v } }
                ))
                .font(.system(size: 18, weight: .bold))
                .frame(width: 90)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)

                TextField(L10n.t("场景描述", "Scene description", language: lang), text: Binding(
                    get: { scene.description },
                    set: { v in store.updateScene(scene.id) { $0.description = v } }
                ))
                .font(.system(size: 14))
                .textFieldStyle(.roundedBorder)

                Menu {
                    Button(role: .destructive) {
                        store.deleteScene(scene.id)
                    } label: {
                        Label(L10n.t("删除此场", "Delete Scene", language: lang), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18))
                }
            }

            ForEach(scene.shots) { shot in
                ShotBlock(scene: scene, shot: shot)
            }

            Button {
                store.addShot(toScene: scene.id)
            } label: {
                Label(L10n.t("新建镜头", "Add Shot", language: lang), systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct DeleteRequest: Identifiable {
    let scene: UUID
    let shot: UUID
    let take: UUID
    let takeNumber: Int
    var id: UUID { take }
}

private struct ShotBlock: View {
    @EnvironmentObject private var store: ScripterStore
    @Environment(\.palette) private var palette
    let scene: ScriptScene
    let shot: Shot
    @State private var deleteRequest: DeleteRequest?
    private var lang: AppLanguage { store.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.t("镜", "SH", language: lang))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                TextField("#", text: Binding(
                    get: { shot.shotNumber },
                    set: { v in store.updateShot(scene: scene.id, shot: shot.id) { $0.shotNumber = v } }
                ))
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 64)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numbersAndPunctuation)

                Spacer()

                Menu {
                    Button(role: .destructive) {
                        store.deleteShot(scene: scene.id, shot: shot.id)
                    } label: {
                        Label(L10n.t("删除此镜头", "Delete Shot", language: lang), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
            }

            // Takes
            ForEach(shot.takes) { take in
                TakeRow(
                    take: take,
                    isSelected: store.selectedTakeID == take.id,
                    lang: lang,
                    palette: palette,
                    onSelect: {
                        store.selectedSceneID = scene.id
                        store.selectedShotID = shot.id
                        store.selectedTakeID = take.id
                    },
                    onSetStatus: { newStatus in
                        store.updateTake(scene: scene.id, shot: shot.id, take: take.id) {
                            $0.status = newStatus
                        }
                    },
                    onRequestDelete: {
                        if store.skipDeleteTakeConfirm {
                            store.deleteTake(scene: scene.id, shot: shot.id, take: take.id)
                        } else {
                            deleteRequest = DeleteRequest(scene: scene.id, shot: shot.id, take: take.id,
                                                          takeNumber: take.takeNumber)
                        }
                    }
                )
                .equatable()
                .id(take.id)
            }

            Button {
                store.addTake(scene: scene.id, shot: shot.id)
            } label: {
                Label(L10n.t("加一条 Take", "Add Take", language: lang), systemImage: "plus.circle")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .controlSize(.small)
        }
        .padding(12)
        .background(palette.field.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .confirmationDialog(
            L10n.t("删除这条 Take？", "Delete this take?", language: lang),
            isPresented: Binding(
                get: { deleteRequest != nil },
                set: { if !$0 { deleteRequest = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleteRequest
        ) { req in
            Button(L10n.t("删除", "Delete", language: lang), role: .destructive) {
                store.deleteTake(scene: req.scene, shot: req.shot, take: req.take)
            }
            Button(L10n.t("删除且不再提示", "Delete & don't ask again", language: lang),
                   role: .destructive) {
                store.skipDeleteTakeConfirm = true
                store.deleteTake(scene: req.scene, shot: req.shot, take: req.take)
            }
            Button(L10n.t("取消", "Cancel", language: lang), role: .cancel) {}
        } message: { req in
            Text(L10n.t("T\(req.takeNumber)：删除后无法恢复（可用撤销）。",
                        "T\(req.takeNumber): this cannot be undone except via Undo.",
                        language: lang))
        }
    }
}

/// Pure value-type row: it does NOT observe the store, so a keystroke elsewhere
/// won't invalidate it. SwiftUI compares via Equatable and only re-renders the
/// row whose `take`/`isSelected`/`lang` actually changed.
private struct TakeRow: View, Equatable {
    let take: Take
    let isSelected: Bool
    let lang: AppLanguage
    let palette: Palette
    let onSelect: () -> Void
    let onSetStatus: (TakeStatus) -> Void
    let onRequestDelete: () -> Void

    static func == (a: TakeRow, b: TakeRow) -> Bool {
        a.take == b.take && a.isSelected == b.isSelected && a.lang == b.lang
    }

    // Manual swipe-to-reveal-trash (SwiftUI .swipeActions only works inside a
    // List; this column is a custom VStack, so we drive it with a drag gesture).
    @State private var offsetX: CGFloat = 0
    private let trashWidth: CGFloat = 72

    /// Camera clip numbers shown under the take row, e.g. "A机 A0001 · B机 B0001".
    private var clipSummary: [(label: String, clip: String)] {
        take.cameraRecords
            .filter { !$0.clipName.isEmpty }
            .map { ($0.cameraLabel, $0.clipName) }
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Trash button revealed underneath when swiped left. It stretches to
            // the full row height (matches the take row, including the clip line).
            Button {
                onRequestDelete()
                resetOffset()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: trashWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color.red)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .opacity(offsetX < -4 ? 1 : 0)

            rowContent
                .offset(x: offsetX)
                .gesture(swipeGesture)
        }
        .fixedSize(horizontal: false, vertical: true)
        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: offsetX)
    }

    private var rowContent: some View {
        Button {
            if offsetX != 0 { resetOffset(); return }   // tap closes an open swipe
            onSelect()
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text("T\(take.takeNumber)")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .frame(width: 42, alignment: .leading)

                    // Always show an indicator so every row has the same height;
                    // unset takes get a neutral gray dot.
                    statusBadge(take.status)

                    if take.isCircleTake {
                        Image(systemName: "circle.circle.fill")
                            .foregroundStyle(palette.circle)
                    }

                    if !take.generalNote.isEmpty {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Text(take.generalNote)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Quick status buttons for fast on-set logging (OK · KP · NG).
                    quickButton(.good, "OK")
                    quickButton(.hold, "KP")
                    quickButton(.ng, "NG")
                }

                if !clipSummary.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(clipSummary, id: \.label) { item in
                            HStack(spacing: 3) {
                                Text(item.label)
                                    .foregroundStyle(.secondary)
                                Text(item.clip)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(palette.accent)
                            }
                            .font(.system(size: 11, design: .monospaced))
                        }
                    }
                    .padding(.leading, 52)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? palette.accent.opacity(0.18) : palette.card)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? palette.accent : .clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var swipeGesture: some Gesture {
        // Only claim horizontal-dominant drags; vertical drags fall through to
        // the ScrollView so the whole column still scrolls when you drag on a row.
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 {
                    offsetX = max(value.translation.width, -trashWidth - 12)
                } else if offsetX < 0 {
                    offsetX = min(0, -trashWidth + value.translation.width)
                }
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -trashWidth / 2 {
                    offsetX = -trashWidth          // snap open
                } else {
                    resetOffset()                  // snap closed
                }
            }
    }

    private func resetOffset() { offsetX = 0 }

    @ViewBuilder
    private func statusBadge(_ status: TakeStatus) -> some View {
        if status.hasStatus {
            Text(status.label(language: lang))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(status.tint(palette))
                .clipShape(Capsule())
        } else {
            // Neutral gray indicator for an unmarked take (keeps row height
            // consistent with marked rows).
            Circle()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 14, height: 14)
        }
    }

    private func quickButton(_ status: TakeStatus, _ title: String) -> some View {
        Button {
            // Tapping the active status again clears it back to unmarked.
            onSetStatus(take.status == status ? .unset : status)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 38, height: 28)
                .background(take.status == status ? status.tint(palette) : palette.field)
                .foregroundStyle(take.status == status ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
