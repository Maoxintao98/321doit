import SwiftUI
import UniformTypeIdentifiers

private enum StoryboardWorkspaceMode: String, CaseIterable, Identifiable {
    case table
    case board

    var id: String { rawValue }
}

struct StoryboardWorkspaceView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @ObservedObject var store: StoryboardStore
    @ObservedObject var workflowStore: ScriptLogStore
    @State private var selectedSceneID: UUID?
    @State private var selectedShotID: UUID?
    @State private var isFrameEditorPresented = false
    @State private var isSceneEditorPresented = false
    @State private var isBlockingEditorPresented = false
    @State private var isFloorPlanPresented = false
    @State private var draggedShotID: UUID?
    @State private var isAnimaticPresented = false
    @State private var isAnalysisPresented = false
    @State private var isExportPresented = false
    @State private var isLibraryPresented = false
    @State private var isWorkflowPresented = false
    @State private var directorWheelOverlay: StoryboardDirectorWheelOverlayState?
    @State private var workspaceMode: StoryboardWorkspaceMode = .table

    private let accent = ToolAccent.storyboard
    private var lang: AppLanguage { settings.settings.general.language.resolved }

    private var selectedScene: StoryboardScene? {
        store.document.scenes.first { $0.id == selectedSceneID }
    }

    private var selectedShot: StoryboardShot? {
        selectedScene?.shots.first { $0.id == selectedShotID }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                workspaceToolbar
                Divider()

                HStack(spacing: 0) {
                    sceneSidebar
                        .frame(width: 230)
                    Divider()
                    shotWorkspace
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Divider()
                timeline
                    .frame(height: 104)
            }

            if let overlay = directorWheelOverlay {
                StoryboardPressDirectorWheel(
                    category: overlay.category,
                    highlightedID: overlay.highlightedID
                )
                .frame(width: 224, height: 224)
                .position(overlay.origin)
                .transition(.scale(scale: 0.78).combined(with: .opacity))
                .zIndex(1_000)
                .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "storyboardDirectorGesture")
        .background(colors.surfaceBg)
        .onAppear {
            repairSelection()
            normalizeLivingStoryboardIfNeeded()
        }
        .onChange(of: store.document) { _ in
            repairSelection()
            DispatchQueue.main.async {
                normalizeLivingStoryboardIfNeeded()
            }
        }
        .sheet(isPresented: $isFrameEditorPresented) {
            if let scene = selectedScene, let shot = selectedShot {
                StoryboardFrameEditor(store: store, sceneID: scene.id, shot: shot)
                    .environmentObject(settings)
            }
        }
        .sheet(isPresented: $isSceneEditorPresented) {
            if let scene = selectedScene {
                StoryboardSceneEditor(
                    store: store,
                    scene: scene,
                    save: { updated in
                        store.perform(title: L10n.t("修改场次", "Edit Scene", language: lang), mutations: [
                            .updateScene(sceneID: scene.id, scene: updated)
                        ])
                    },
                    delete: { removeScene(scene.id) }
                )
                .environmentObject(settings)
            }
        }
        .sheet(isPresented: $isBlockingEditorPresented) {
            if let scene = selectedScene, let shot = selectedShot {
                StoryboardBlockingEditor(store: store, sceneID: scene.id, shot: shot)
                    .environmentObject(settings)
            }
        }
        .sheet(isPresented: $isFloorPlanPresented) {
            if let scene = selectedScene {
                StoryboardFloorPlanEditor(store: store, scene: scene, selectedShot: selectedShot)
                    .environmentObject(settings)
            }
        }
        .sheet(isPresented: $isAnimaticPresented) {
            if let scene = selectedScene {
                StoryboardAnimaticView(store: store, scene: scene)
                    .environmentObject(settings)
            }
        }
        .sheet(isPresented: $isAnalysisPresented) {
            if let scene = selectedScene {
                StoryboardAnalysisView(scene: scene) { shotID in
                    selectedShotID = shotID
                }
                .environmentObject(settings)
            }
        }
        .sheet(isPresented: $isExportPresented) {
            StoryboardExportView(store: store)
                .environmentObject(settings)
        }
        .sheet(isPresented: $isLibraryPresented) {
            StoryboardProductionLibraryView(store: store)
                .environmentObject(settings)
        }
        .sheet(isPresented: $isWorkflowPresented) {
            if let scene = selectedScene {
                StoryboardWorkflowView(
                    storyboardStore: store,
                    workflowStore: workflowStore,
                    scene: scene
                )
                .environmentObject(settings)
            }
        }
        .alert(
            L10n.t("灵动分镜", "Living Storyboard", language: lang),
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .suppressAutomaticFocusEffect()
    }

    private var workspaceToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.document.title)
                    .font(.system(size: 15, weight: .semibold))
                Text(L10n.t(
                    "版本 \(store.document.revision) · \(store.document.scenes.count) 场 · \(shotCount) 镜",
                    "Revision \(store.document.revision) · \(store.document.scenes.count) scenes · \(shotCount) shots",
                    language: lang
                ))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            Button { store.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!store.canUndo)
            .accessibilityIdentifier("storyboard.undo")
            .help(L10n.t("撤销", "Undo", language: lang))
            Button { store.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!store.canRedo)
            .accessibilityIdentifier("storyboard.redo")
            .help(L10n.t("重做", "Redo", language: lang))
            Menu {
                Button {
                    isLibraryPresented = true
                } label: {
                    Label(L10n.t("项目资料库", "Production Library", language: lang), systemImage: "books.vertical")
                }
                Button {
                    isWorkflowPresented = true
                } label: {
                    Label(L10n.t("片场工作流", "On-set Workflow", language: lang), systemImage: "arrow.triangle.branch")
                }
                .disabled(selectedScene == nil)
                Button {
                    isSceneEditorPresented = true
                } label: {
                    Label(L10n.t("场次设置", "Scene Settings", language: lang), systemImage: "slider.horizontal.3")
                }
                Button {
                    isFloorPlanPresented = true
                } label: {
                    Label(L10n.t("机位平面图", "Camera Floor Plan", language: lang), systemImage: "map")
                }
            } label: {
                Label(L10n.t("场景", "Scene", language: lang), systemImage: "square.3.layers.3d")
            }
            .disabled(selectedScene == nil)
            .accessibilityIdentifier("storyboard.sceneMenu")
            Button {
                isAnimaticPresented = true
            } label: {
                Label(L10n.t("预演", "Animatic", language: lang), systemImage: "play.rectangle")
            }
            .disabled(selectedScene == nil)
            .accessibilityIdentifier("storyboard.animatic")
            Menu {
                Button {
                    isAnalysisPresented = true
                } label: {
                    Label(L10n.t("连续性检查", "Continuity Check", language: lang), systemImage: "checkmark.seal")
                }
                Button {
                    isExportPresented = true
                } label: {
                    Label(L10n.t("导出与交付", "Export & Delivery", language: lang), systemImage: "square.and.arrow.up")
                }
            } label: {
                Label(L10n.t("检查与导出", "Review", language: lang), systemImage: "checklist")
            }
            .accessibilityIdentifier("storyboard.review")
            Button(action: addShot) {
                Label(L10n.t("新增镜头", "New Shot", language: lang), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedScene == nil)
            .accessibilityIdentifier("storyboard.addShot")
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .background(colors.panelBg)
    }

    private var sceneSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("场次", "SCENES", language: lang))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(colors.textSecondary)
                Spacer()
                Button(action: addScene) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("storyboard.addScene")
                .help(L10n.t("新增场次", "New Scene", language: lang))
            }
            .padding(.horizontal, 15)
            .frame(height: 44)

            if store.document.scenes.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(accent.primary)
                    Text(L10n.t("先建立第一个场次", "Create the first scene", language: lang))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(colors.textSecondary)
                    Button(L10n.t("新增场次", "New Scene", language: lang), action: addScene)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("storyboard.addFirstScene")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.document.scenes) { scene in
                            Button {
                                selectedSceneID = scene.id
                                selectedShotID = scene.shots.first?.id
                            } label: {
                                HStack(spacing: 10) {
                                    Text(scene.sceneNumber)
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundStyle(selectedSceneID == scene.id ? Color.white : accent.primary)
                                        .frame(width: 34, height: 34)
                                        .background(
                                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                .fill(selectedSceneID == scene.id ? accent.primary : accent.primary.opacity(0.1))
                                        )
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(scene.title.isEmpty
                                            ? L10n.t("未命名场次", "Untitled Scene", language: lang)
                                            : scene.title)
                                            .font(.system(size: 12, weight: .semibold))
                                            .lineLimit(1)
                                        Text("\(scene.shots.count) \(L10n.t("个镜头", "shots", language: lang))")
                                            .font(.system(size: 9))
                                            .foregroundStyle(colors.textSecondary)
                                    }
                                    Spacer()
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(selectedSceneID == scene.id ? accent.primary.opacity(0.1) : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    selectedSceneID = scene.id
                                    selectedShotID = scene.shots.first?.id
                                    isSceneEditorPresented = true
                                }
                            )
                            .contextMenu {
                                Button(L10n.t("编辑场次", "Edit Scene", language: lang)) {
                                    selectedSceneID = scene.id
                                    isSceneEditorPresented = true
                                }
                                Button(L10n.t("上移", "Move Up", language: lang)) { moveScene(scene.id, offset: -1) }
                                Button(L10n.t("下移", "Move Down", language: lang)) { moveScene(scene.id, offset: 1) }
                                Divider()
                                Button(L10n.t("删除场次", "Delete Scene", language: lang), role: .destructive) {
                                    removeScene(scene.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .background(colors.panelBg)
    }

    @ViewBuilder
    private var shotWorkspace: some View {
        if let scene = selectedScene {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(L10n.t("场", "Scene", language: lang)) \(scene.sceneNumber) · \(scene.title)")
                            .font(.system(size: 17, weight: .semibold))
                        if !scene.synopsis.isEmpty {
                            Text(scene.synopsis)
                                .font(.system(size: 10))
                                .foregroundStyle(colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Text([scene.location, scene.timeOfDay].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(colors.textSecondary)
                    Picker("", selection: $workspaceMode) {
                        Text(L10n.t("分镜表", "Shot List", language: lang)).tag(StoryboardWorkspaceMode.table)
                        Text(L10n.t("故事板", "Storyboard", language: lang)).tag(StoryboardWorkspaceMode.board)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 154)
                }
                .padding(.horizontal, 20)
                .frame(height: 58)

                if scene.shots.isEmpty {
                    emptyShotState
                } else if workspaceMode == .table {
                    shotTable(scene)
                } else {
                    shotCardGrid(scene)
                }
            }
        } else {
            emptyShotState
        }
    }

    private var emptyShotState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(accent.primary)
            Text(L10n.t("把文字拆成第一个镜头", "Turn the scene into its first shot", language: lang))
                .font(.system(size: 15, weight: .semibold))
            Text(L10n.t(
                "新增镜头，开始安排画面、景别和节奏。",
                "Add a shot and start shaping the frame, scale, and rhythm.",
                language: lang
            ))
            .font(.system(size: 11))
            .foregroundStyle(colors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 430)
            Button(action: addShot) {
                Label(L10n.t("新增镜头", "New Shot", language: lang), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedScene == nil)
            .accessibilityIdentifier("storyboard.addFirstShot")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shotCardGrid(_ scene: StoryboardScene) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                ForEach(scene.shots) { shot in
                    Button {
                        selectedShotID = shot.id
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            StoryboardFramePreview(
                                backgroundImage: store.image(for: shot.frame.assetID),
                                annotations: shot.annotations,
                                elements: shot.canvasElements ?? [],
                                annotationLayers: shot.annotationLayers ?? [],
                                layerOrder: shot.resolvedCanvasLayerOrder,
                                imageResolver: { store.image(for: $0) },
                                allowsShiftDrawing: true,
                                addShiftDrawing: { points in
                                    selectedShotID = shot.id
                                    var updated = shot
                                    updated.annotations.append(StoryboardAnnotation(
                                        kind: .freehand,
                                        points: points,
                                        colorHex: "#FF3B30"
                                    ))
                                    updateShot(
                                        updated,
                                        in: scene.id,
                                        title: L10n.t("Shift 导演笔", "Shift Director Pen", language: lang),
                                        source: .keyboard
                                    )
                                }
                            )
                            .onTapGesture {
                                selectedShotID = shot.id
                                isFrameEditorPresented = true
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .clipped()
                            .padding(8)

                            HStack(alignment: .top, spacing: 10) {
                                Text(shot.shotNumber)
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(accent.primary)
                                VStack(alignment: .leading, spacing: 4) {
                                    if shot.description.isEmpty {
                                        Text(L10n.t("未填写镜头描述", "No shot description", language: lang))
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(colors.textPrimary)
                                            .lineLimit(2)
                                    } else {
                                        Text(StoryboardMarkdownRendering.attributedString(from: shot.description))
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(colors.textPrimary)
                                            .lineLimit(2)
                                    }
                                    Text("\(shotSizeLabel(shot.shotSize)) · \(formattedDuration(shot.durationSeconds))")
                                        .font(.system(size: 9))
                                        .foregroundStyle(colors.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(colors.panelBg)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    selectedShotID == shot.id ? accent.primary : colors.hairline.opacity(0.75),
                                    lineWidth: selectedShotID == shot.id ? 1.5 : 0.8
                                )
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(draggedShotID == shot.id ? 0.24 : 1)
                    .onDrag {
                        draggedShotID = shot.id
                        return NSItemProvider(object: shot.id.uuidString as NSString)
                    } preview: {
                        StoryboardShotDragPreview(shot: shot)
                    }
                    .onDrop(
                        of: [UTType.text.identifier],
                        delegate: StoryboardShotDropDelegate(
                            targetShotID: shot.id,
                            sceneID: scene.id,
                            store: store,
                            draggedShotID: $draggedShotID,
                            language: lang
                        )
                    )
                }
            }
            .padding(20)
        }
    }

    private func shotTable(_ scene: StoryboardScene) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                StoryboardTableHeader()
                Divider()
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(scene.shots) { shot in
                            StoryboardShotTableRow(
                                sceneID: scene.id,
                                shot: shot,
                                store: store,
                                isSelected: selectedShotID == shot.id,
                                select: { selectedShotID = shot.id },
                                openFrame: {
                                    selectedShotID = shot.id
                                    isFrameEditorPresented = true
                                },
                                openBlocking: {
                                    selectedShotID = shot.id
                                    isBlockingEditorPresented = true
                                },
                                updateDirectorWheel: { category, origin, highlightedID in
                                    let next = StoryboardDirectorWheelOverlayState(
                                        category: category,
                                        origin: origin,
                                        highlightedID: highlightedID
                                    )
                                    if directorWheelOverlay == nil {
                                        withAnimation(.spring(response: 0.16, dampingFraction: 0.84)) {
                                            directorWheelOverlay = next
                                        }
                                    } else {
                                        directorWheelOverlay = next
                                    }
                                },
                                dismissDirectorWheel: {
                                    withAnimation(.easeOut(duration: 0.1)) {
                                        directorWheelOverlay = nil
                                    }
                                }
                            )
                            .opacity(draggedShotID == shot.id ? 0.2 : 1)
                            .onDrag {
                                draggedShotID = shot.id
                                return NSItemProvider(object: shot.id.uuidString as NSString)
                            } preview: {
                                StoryboardShotDragPreview(shot: shot)
                            }
                            .onDrop(
                                of: [UTType.text.identifier],
                                delegate: StoryboardShotDropDelegate(
                                    targetShotID: shot.id,
                                    sceneID: scene.id,
                                    store: store,
                                    draggedShotID: $draggedShotID,
                                    language: lang
                                )
                            )
                            Divider()
                        }
                    }
                }
            }
            .frame(width: StoryboardTableMetrics.totalWidth)
        }
        .background(colors.surfaceBg)
    }

    @ViewBuilder
    private var inspector: some View {
        if let scene = selectedScene, let shot = selectedShot {
            StoryboardShotInspector(
                sceneID: scene.id,
                shot: shot,
                store: store,
                delete: { removeShot(sceneID: scene.id, shotID: shot.id) }
            )
            .id("\(shot.id.uuidString)-\(store.document.revision)")
        } else {
            VStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 24))
                    .foregroundStyle(colors.textTertiary)
                Text(L10n.t("选择镜头后编辑", "Select a shot to edit", language: lang))
                    .font(.system(size: 11))
                    .foregroundStyle(colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colors.panelBg)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.t("动态分镜时间线", "Animatic Timeline", language: lang), systemImage: "timeline.selection")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(formattedDuration(totalDuration)) · \(shotCount) \(L10n.t("镜", "shots", language: lang))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(selectedScene?.shots ?? []) { shot in
                        Button {
                            selectedShotID = shot.id
                        } label: {
                            Text(shot.shotNumber)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(selectedShotID == shot.id ? Color.white : colors.textPrimary)
                                .frame(width: max(58, shot.durationSeconds * 22), height: 32)
                                .background(selectedShotID == shot.id ? accent.primary : colors.inputBg)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .opacity(draggedShotID == shot.id ? 0.24 : 1)
                        .onDrag {
                            draggedShotID = shot.id
                            return NSItemProvider(object: shot.id.uuidString as NSString)
                        } preview: {
                            StoryboardShotDragPreview(shot: shot, compact: true)
                        }
                        .onDrop(
                            of: [UTType.text.identifier],
                            delegate: StoryboardShotDropDelegate(
                                targetShotID: shot.id,
                                sceneID: selectedScene?.id ?? UUID(),
                                store: store,
                                draggedShotID: $draggedShotID,
                                language: lang
                            )
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colors.panelBg)
    }

    private var shotCount: Int {
        store.document.scenes.reduce(0) { $0 + $1.shots.count }
    }

    private var totalDuration: Double {
        selectedScene?.shots.reduce(0) { $0 + $1.durationSeconds } ?? 0
    }

    private func addScene() {
        let nextNumber = "\(store.document.scenes.count + 1)"
        let scene = StoryboardScene(
            sceneNumber: nextNumber,
            title: L10n.t("新场次", "New Scene", language: lang)
        )
        store.perform(title: L10n.t("新增场次", "Add Scene", language: lang), mutations: [
            .addScene(scene: scene, index: nil)
        ])
        selectedSceneID = scene.id
        selectedShotID = nil
    }

    private func addShot() {
        guard let scene = selectedScene else { return }
        let shotNumber = String(scene.shots.count + 1)
        let shot = scene.shots.last?.nextShotCopy(shotNumber: shotNumber)
            ?? StoryboardShot(shotNumber: shotNumber)
        var mutations = normalizationMutations(for: scene)
        mutations.append(.addShot(sceneID: scene.id, shot: shot, index: nil))
        store.perform(title: L10n.t("新增镜头", "Add Shot", language: lang), mutations: mutations)
        selectedShotID = shot.id
    }

    private func removeScene(_ sceneID: UUID) {
        store.perform(title: L10n.t("删除场次", "Delete Scene", language: lang), mutations: [
            .removeScene(sceneID: sceneID)
        ])
        selectedSceneID = store.document.scenes.first?.id
        selectedShotID = selectedScene?.shots.first?.id
    }

    private func moveScene(_ sceneID: UUID, offset: Int) {
        guard let index = store.document.scenes.firstIndex(where: { $0.id == sceneID }) else { return }
        let destination = min(max(index + offset, 0), max(store.document.scenes.count - 1, 0))
        guard destination != index else { return }
        store.perform(title: L10n.t("调整场次顺序", "Move Scene", language: lang), mutations: [
            .moveScene(sceneID: sceneID, destination: destination)
        ])
    }

    private func removeShot(sceneID: UUID, shotID: UUID) {
        guard var scene = store.document.scene(id: sceneID) else { return }
        scene.shots.removeAll { $0.id == shotID }
        var mutations: [StoryboardMutation] = [.removeShot(sceneID: sceneID, shotID: shotID)]
        mutations.append(contentsOf: normalizationMutations(for: scene))
        store.perform(title: L10n.t("删除镜头", "Delete Shot", language: lang), mutations: mutations)
        selectedShotID = store.document.scene(id: sceneID)?.shots.first?.id
    }

    private func normalizeLivingStoryboardIfNeeded() {
        let mutations = store.document.scenes.flatMap(normalizationMutations(for:))
        guard !mutations.isEmpty else { return }
        store.perform(
            title: L10n.t("整理镜号与内容", "Normalize Shot Numbers and Content", language: lang),
            mutations: mutations
        )
    }

    private func normalizationMutations(for scene: StoryboardScene) -> [StoryboardMutation] {
        zip(scene.shots, scene.livingStoryboardNormalizedShots).compactMap { current, normalized in
            guard current != normalized else { return nil }
            return .updateShot(sceneID: scene.id, shotID: current.id, shot: normalized)
        }
    }

    private func updateShot(
        _ shot: StoryboardShot,
        in sceneID: UUID,
        title: String,
        source: StoryboardCommandSource
    ) {
        store.perform(title: title, source: source, mutations: [
            .updateShot(sceneID: sceneID, shotID: shot.id, shot: shot)
        ])
    }

    private func repairSelection() {
        if selectedSceneID == nil || store.document.scene(id: selectedSceneID!) == nil {
            selectedSceneID = store.document.scenes.first?.id
        }
        guard let scene = selectedScene else {
            selectedShotID = nil
            return
        }
        if selectedShotID == nil || !scene.shots.contains(where: { $0.id == selectedShotID }) {
            selectedShotID = scene.shots.first?.id
        }
    }

    private func formattedDuration(_ seconds: Double) -> String {
        String(format: "%.1fs", seconds)
    }

    private func shotSizeLabel(_ size: StoryboardShotSize) -> String {
        switch size {
        case .extremeWide: return L10n.t("大远景", "EWS", language: lang)
        case .wide: return L10n.t("远景", "Wide", language: lang)
        case .full: return L10n.t("全景", "Full", language: lang)
        case .medium: return L10n.t("中景", "Medium", language: lang)
        case .mediumCloseUp: return L10n.t("中近景", "MCU", language: lang)
        case .closeUp: return L10n.t("近景", "Close-up", language: lang)
        case .extremeCloseUp: return L10n.t("特写", "ECU", language: lang)
        }
    }

    private func angleLabel(_ angle: StoryboardCameraAngle) -> String {
        switch angle {
        case .eyeLevel: return L10n.t("平视", "Eye", language: lang)
        case .high: return L10n.t("俯拍", "High", language: lang)
        case .low: return L10n.t("仰拍", "Low", language: lang)
        case .overhead: return L10n.t("顶拍", "Top", language: lang)
        case .dutch: return L10n.t("荷兰角", "Dutch", language: lang)
        case .pointOfView: return "POV"
        }
    }
}

private struct StoryboardShotDragPreview: View {
    let shot: StoryboardShot
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            Text(shot.shotNumber)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(ToolAccent.storyboard.primary)
            if !compact {
                Text(StoryboardMarkdownRendering.attributedString(from: shot.description))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: compact ? 70 : 240, height: 44, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(ToolAccent.storyboard.primary.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 8, y: 4)
    }
}

private enum StoryboardTableMetrics {
    static let drag: CGFloat = 28
    static let shot: CGFloat = 70
    static let content: CGFloat = 230
    static let frame: CGFloat = 190
    static let size: CGFloat = 90
    static let angle: CGFloat = 84
    static let motion: CGFloat = 92
    static let duration: CGFloat = 72
    static let sound: CGFloat = 132
    static let cameraMap: CGFloat = 150
    static let notes: CGFloat = 178
    static let actions: CGFloat = 44
    static let totalWidth = drag + shot + content + frame + size + angle + motion + duration + sound + cameraMap + notes + actions
}

private struct StoryboardDirectorWheelOverlayState: Equatable {
    let category: StoryboardDirectorWheelCategory
    let origin: CGPoint
    let highlightedID: String?
}

private struct StoryboardTableHeader: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        HStack(spacing: 0) {
            header("", width: StoryboardTableMetrics.drag)
            header(L10n.t("镜号", "Shot", language: lang), width: StoryboardTableMetrics.shot)
            header(L10n.t("内容", "Content", language: lang), width: StoryboardTableMetrics.content)
            header(L10n.t("画面", "Frame", language: lang), width: StoryboardTableMetrics.frame)
            header(L10n.t("景别", "Size", language: lang), width: StoryboardTableMetrics.size)
            header(L10n.t("角度", "Angle", language: lang), width: StoryboardTableMetrics.angle)
            header(L10n.t("运镜", "Move", language: lang), width: StoryboardTableMetrics.motion)
            header(L10n.t("时长", "Time", language: lang), width: StoryboardTableMetrics.duration)
            header(L10n.t("声音", "Sound", language: lang), width: StoryboardTableMetrics.sound)
            header(L10n.t("机位图", "Blocking", language: lang), width: StoryboardTableMetrics.cameraMap)
            header(L10n.t("备注", "Notes", language: lang), width: StoryboardTableMetrics.notes)
            header("", width: StoryboardTableMetrics.actions)
        }
        .frame(height: 38)
        .background(colors.panelBg)
    }

    private func header(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(colors.textSecondary)
            .padding(.leading, title.isEmpty ? 0 : 9)
            .frame(width: width, height: 38, alignment: .leading)
            .overlay(alignment: .trailing) { Divider() }
    }
}

private struct StoryboardBlockingThumbnail: View {
    @EnvironmentObject private var settings: SettingsStore
    let shot: StoryboardShot
    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Canvas { context, size in
                    drawGrid(in: &context, size: size)
                    for camera in shot.cameraPlacements ?? [] {
                        drawCamera(camera, in: &context, size: size)
                    }
                    for path in shot.movementPaths {
                        drawPath(path, in: &context, size: size)
                    }
                    for character in shot.characters {
                        let point = screenPoint(character.position, size: size)
                        context.fill(
                            Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)),
                            with: .color(ToolAccent.storyboard.primary)
                        )
                    }
                }
                if (shot.cameraPlacements ?? []).isEmpty && shot.characters.isEmpty && shot.movementPaths.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "video.badge.plus")
                        Text(L10n.t("设置机位图", "Set Blocking", language: lang)).font(.system(size: 8, weight: .medium))
                    }
                    .foregroundStyle(Color.secondary.opacity(0.7))
                }
            }
            .contentShape(Rectangle())
        }
    }

    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        var grid = Path()
        for index in 1..<4 {
            let x = size.width * CGFloat(index) / 4
            let y = size.height * CGFloat(index) / 4
            grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(Color.secondary.opacity(0.09)), lineWidth: 0.6)
    }

    private func drawCamera(_ camera: StoryboardCameraPlacement, in context: inout GraphicsContext, size: CGSize) {
        let apex = screenPoint(camera.position, size: size)
        let angle = camera.rotationDegrees * .pi / 180
        let focalLength = camera.equivalentFocalLengthMM ?? max(18 / tan(max(camera.fieldOfViewDegrees, 1) * .pi / 360), 1)
        let half = atan(36 / (2 * max(focalLength, 1)))
        let length = max(24, camera.range * min(size.width, size.height) * 1.45)
        let left = CGPoint(x: apex.x + cos(angle - half) * length, y: apex.y + sin(angle - half) * length)
        let right = CGPoint(x: apex.x + cos(angle + half) * length, y: apex.y + sin(angle + half) * length)
        var cone = Path()
        cone.move(to: apex); cone.addLine(to: left); cone.addLine(to: right); cone.closeSubpath()
        context.fill(cone, with: .color(Color.blue.opacity(0.13)))
        context.fill(
            Path(ellipseIn: CGRect(x: apex.x - 5, y: apex.y - 5, width: 10, height: 10)),
            with: .color(Color.blue)
        )
    }

    private func drawPath(_ model: StoryboardMovementPath, in context: inout GraphicsContext, size: CGSize) {
        guard let first = model.points.first else { return }
        var path = Path()
        if model.kind == .prop,
           let last = model.points.last,
           model.note == "blocking-shape:rectangle" || model.note == "blocking-shape:ellipse" {
            let start = screenPoint(first, size: size)
            let end = screenPoint(last, size: size)
            let rect = CGRect(
                x: min(start.x, end.x), y: min(start.y, end.y),
                width: abs(end.x - start.x), height: abs(end.y - start.y)
            )
            if model.note == "blocking-shape:rectangle" { path.addRect(rect) }
            else { path.addEllipse(in: rect) }
        } else {
            path.move(to: screenPoint(first, size: size))
            for point in model.points.dropFirst() { path.addLine(to: screenPoint(point, size: size)) }
        }
        let color: Color = model.kind == .camera ? .blue : model.kind == .prop ? .indigo : ToolAccent.storyboard.primary
        context.stroke(path, with: .color(color.opacity(0.75)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    private func screenPoint(_ point: StoryboardPoint, size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}

private struct StoryboardShotTableRow: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    let sceneID: UUID
    let shot: StoryboardShot
    @ObservedObject var store: StoryboardStore
    let isSelected: Bool
    let select: () -> Void
    let openFrame: () -> Void
    let openBlocking: () -> Void
    let updateDirectorWheel: (StoryboardDirectorWheelCategory, CGPoint, String?) -> Void
    let dismissDirectorWheel: () -> Void

    @State private var draft: StoryboardShot
    @State private var activeDirectorCell: StoryboardDirectorWheelCategory?
    @State private var wheelOrigin: CGPoint = .zero
    @State private var highlightedDirectorOptionID: String?
    private var lang: AppLanguage { settings.settings.general.language.resolved }
    init(
        sceneID: UUID,
        shot: StoryboardShot,
        store: StoryboardStore,
        isSelected: Bool,
        select: @escaping () -> Void,
        openFrame: @escaping () -> Void,
        openBlocking: @escaping () -> Void,
        updateDirectorWheel: @escaping (StoryboardDirectorWheelCategory, CGPoint, String?) -> Void,
        dismissDirectorWheel: @escaping () -> Void
    ) {
        self.sceneID = sceneID
        self.shot = shot
        self.store = store
        self.isSelected = isSelected
        self.select = select
        self.openFrame = openFrame
        self.openBlocking = openBlocking
        self.updateDirectorWheel = updateDirectorWheel
        self.dismissDirectorWheel = dismissDirectorWheel
        _draft = State(initialValue: shot)
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(colors.textTertiary)
                .frame(width: StoryboardTableMetrics.drag, height: 112)
                .overlay(alignment: .trailing) { Divider() }

            Text(draft.shotNumber)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(ToolAccent.storyboard.primary)
                .padding(.horizontal, 8)
                .frame(width: StoryboardTableMetrics.shot, height: 112)
                .overlay(alignment: .trailing) { Divider() }

            StoryboardMarkdownField(
                text: $draft.description,
                editorTitle: L10n.t("镜头内容", "Shot Content", language: lang),
                isSelected: isSelected,
                fontSize: 10,
                minimumHeight: 88
            )
            .padding(8)
            .frame(width: StoryboardTableMetrics.content, height: 112)
            .overlay(alignment: .trailing) { Divider() }

            Button(action: openFrame) {
                StoryboardFramePreview(
                    backgroundImage: store.image(for: draft.frame.assetID),
                    annotations: draft.annotations,
                    elements: draft.canvasElements ?? [],
                    annotationLayers: draft.annotationLayers ?? [],
                    layerOrder: draft.resolvedCanvasLayerOrder,
                    imageResolver: { store.image(for: $0) }
                )
                .frame(width: 168, height: 94)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 11)
            .frame(width: StoryboardTableMetrics.frame, height: 112)
            .overlay(alignment: .trailing) { Divider() }

            directorCell(
                category: .shotSize,
                title: sizeLabel(draft.shotSize),
                icon: sizeIcon(draft.shotSize),
                width: StoryboardTableMetrics.size
            )
            directorCell(
                category: .cameraAngle,
                title: angleLabel(draft.cameraAngle),
                icon: angleIcon(draft.cameraAngle),
                width: StoryboardTableMetrics.angle
            )
            directorCell(
                category: .cameraMotion,
                title: motionLabel(draft.cameraMotions.first?.kind ?? .locked),
                icon: motionPreviewIcon(draft.cameraMotions.first?.kind ?? .locked),
                width: StoryboardTableMetrics.motion
            )

            TextField(L10n.t("秒", "sec", language: lang), value: $draft.durationSeconds, format: .number.precision(.fractionLength(1)))
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
                .frame(width: StoryboardTableMetrics.duration, height: 112)
                .overlay(alignment: .trailing) { Divider() }

            StoryboardMarkdownField(
                text: Binding(
                    get: { draft.soundDescription ?? "" },
                    set: { draft.soundDescription = $0 }
                ),
                editorTitle: L10n.t("声音", "Sound", language: lang),
                isSelected: isSelected,
                fontSize: 9,
                minimumHeight: 88
            )
            .padding(8)
            .frame(width: StoryboardTableMetrics.sound, height: 112)
            .overlay(alignment: .trailing) { Divider() }

            Button(action: openBlocking) {
                StoryboardBlockingThumbnail(shot: draft)
                    .frame(width: StoryboardTableMetrics.cameraMap - 16, height: 88)
                    .background(colors.inputBg.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .padding(8)
            .frame(width: StoryboardTableMetrics.cameraMap, height: 112)
            .overlay(alignment: .trailing) { Divider() }

            StoryboardMarkdownField(
                text: $draft.notes,
                editorTitle: L10n.t("备注", "Notes", language: lang),
                isSelected: isSelected,
                fontSize: 9,
                minimumHeight: 88
            )
            .padding(8)
            .frame(width: StoryboardTableMetrics.notes, height: 112)
            .overlay(alignment: .trailing) { Divider() }

            Button(action: save) {
                Image(systemName: draft == shot ? "ellipsis" : "checkmark.circle.fill")
                    .foregroundStyle(draft == shot ? colors.textTertiary : ToolAccent.storyboard.primary)
            }
            .buttonStyle(.plain)
            .disabled(draft == shot)
            .help(draft != shot
                ? L10n.t("立即保存", "Save Now", language: lang)
                : L10n.t("已自动保存", "Autosaved", language: lang))
            .frame(width: StoryboardTableMetrics.actions, height: 112)
        }
        .background(isSelected ? ToolAccent.storyboard.primary.opacity(0.14) : colors.panelBg)
        .overlay {
            Rectangle()
                .strokeBorder(
                    isSelected ? ToolAccent.storyboard.primary.opacity(0.42) : Color.clear,
                    lineWidth: 1
                )
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(isSelected ? ToolAccent.storyboard.primary : Color.clear).frame(width: 3)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded(select))
        .zIndex(activeDirectorCell == nil ? 0 : 20)
        .onChange(of: shot) { updated in
            draft = updated
        }
        .onChange(of: draft) { updated in
            persistIfNeeded(updated)
        }
    }

    private func directorCell(
        category: StoryboardDirectorWheelCategory,
        title: String,
        icon: String,
        width: CGFloat
    ) -> some View {
        ZStack {
            VStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium))
                Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                Text(L10n.t("按住拖选", "Hold and drag", language: lang)).font(.system(size: 7, weight: .medium)).opacity(0.5)
            }
            .foregroundStyle(colors.textPrimary)
            .frame(width: width - 12, height: 86)
            .background(colors.inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .contentShape(Rectangle())
        .frame(width: width, height: 112)
        .overlay(alignment: .trailing) { Divider() }
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("storyboardDirectorGesture"))
                .onChanged { value in
                    if activeDirectorCell != category {
                        select()
                        wheelOrigin = value.startLocation
                        highlightedDirectorOptionID = nil
                        activeDirectorCell = category
                        updateDirectorWheel(category, wheelOrigin, nil)
                    }
                    let highlighted = wheelOption(
                        category: category,
                        vector: CGSize(
                            width: value.location.x - wheelOrigin.x,
                            height: value.location.y - wheelOrigin.y
                        )
                    )
                    if highlighted != highlightedDirectorOptionID {
                        highlightedDirectorOptionID = highlighted
                        updateDirectorWheel(category, wheelOrigin, highlighted)
                    }
                }
                .onEnded { _ in
                    let selection = highlightedDirectorOptionID
                    activeDirectorCell = nil
                    highlightedDirectorOptionID = nil
                    dismissDirectorWheel()
                    if let selection {
                        applyWheelSelection(category: category, optionID: selection)
                    }
                }
        )
        .accessibilityLabel("\(title), \(L10n.t("按住并拖动选择", "hold and drag to choose", language: lang))")
        .accessibilityAddTraits(.isButton)
    }

    private func wheelOption(
        category: StoryboardDirectorWheelCategory,
        vector: CGSize
    ) -> String? {
        let radius = hypot(vector.width, vector.height)
        guard radius >= 34, radius <= 126 else { return nil }
        let options = wheelOptionIDs(category)
        guard !options.isEmpty else { return nil }
        let angle = atan2(vector.height, vector.width) * 180 / .pi
        let step = 360 / Double(options.count)
        var normalized = (angle + 90 + step / 2).truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        let index = min(Int(normalized / step), options.count - 1)
        return options[index]
    }

    private func wheelOptionIDs(_ category: StoryboardDirectorWheelCategory) -> [String] {
        switch category {
        case .shotSize: return StoryboardShotSize.allCases.map(\.rawValue)
        case .cameraAngle: return StoryboardCameraAngle.allCases.map(\.rawValue)
        case .cameraMotion: return StoryboardCameraMotionKind.directorWheelCases.map(\.rawValue)
        }
    }

    private func applyWheelSelection(
        category: StoryboardDirectorWheelCategory,
        optionID: String
    ) {
        var updated = draft
        switch category {
        case .shotSize:
            guard let value = StoryboardShotSize(rawValue: optionID) else { return }
            updated.shotSize = value
        case .cameraAngle:
            guard let value = StoryboardCameraAngle(rawValue: optionID) else { return }
            updated.cameraAngle = value
        case .cameraMotion:
            guard let value = StoryboardCameraMotionKind(rawValue: optionID) else { return }
            if updated.cameraMotions.isEmpty { updated.cameraMotions = [StoryboardCameraMotion(kind: value)] }
            else { updated.cameraMotions[0].kind = value }
        }
        draft = updated
        _ = store.perform(title: L10n.t("导演轮选择", "Director Wheel Selection", language: lang), source: .wheel, mutations: [
            .updateShot(sceneID: sceneID, shotID: shot.id, shot: updated)
        ])
    }

    private func save() {
        persistIfNeeded(draft)
    }

    private var storedShot: StoryboardShot? {
        store.document.scenes
            .first(where: { $0.id == sceneID })?
            .shots.first(where: { $0.id == shot.id })
    }

    private func persistIfNeeded(_ candidate: StoryboardShot) {
        guard storedShot != candidate else { return }
        _ = store.perform(title: L10n.t("保存分镜表行", "Save Storyboard Row", language: lang), mutations: [
            .updateShot(sceneID: sceneID, shotID: shot.id, shot: candidate)
        ])
    }

    private func sizeLabel(_ value: StoryboardShotSize) -> String {
        switch value {
        case .extremeWide: return L10n.t("大远景", "EWS", language: lang)
        case .wide: return L10n.t("远景", "Wide", language: lang)
        case .full: return L10n.t("全景", "Full", language: lang)
        case .medium: return L10n.t("中景", "Medium", language: lang)
        case .mediumCloseUp: return L10n.t("中近景", "MCU", language: lang)
        case .closeUp: return L10n.t("近景", "Close-up", language: lang)
        case .extremeCloseUp: return L10n.t("特写", "ECU", language: lang)
        }
    }
    private func angleLabel(_ value: StoryboardCameraAngle) -> String {
        switch value {
        case .eyeLevel: return L10n.t("平视", "Eye", language: lang)
        case .high: return L10n.t("俯拍", "High", language: lang)
        case .low: return L10n.t("仰拍", "Low", language: lang)
        case .overhead: return L10n.t("顶拍", "Top", language: lang)
        case .dutch: return L10n.t("荷兰角", "Dutch", language: lang)
        case .pointOfView: return L10n.t("主观", "POV", language: lang)
        }
    }
    private func motionLabel(_ value: StoryboardCameraMotionKind) -> String {
        switch value {
        case .locked: return L10n.t("定", "Lock", language: lang)
        case .push: return L10n.t("推", "Push", language: lang)
        case .pull: return L10n.t("拉", "Pull", language: lang)
        case .pan: return L10n.t("摇", "Pan", language: lang)
        case .tilt: return L10n.t("俯仰", "Tilt", language: lang)
        case .dolly: return L10n.t("推拉", "Dolly", language: lang)
        case .truck: return L10n.t("移", "Truck", language: lang)
        case .crane: return L10n.t("升降", "Crane", language: lang)
        case .handheld: return L10n.t("手持", "Handheld", language: lang)
        case .steadicam: return L10n.t("稳定器", "Steadicam", language: lang)
        case .zoom: return L10n.t("变焦", "Zoom", language: lang)
        case .follow: return L10n.t("跟", "Follow", language: lang)
        case .rise: return L10n.t("升", "Rise", language: lang)
        case .fall: return L10n.t("降", "Fall", language: lang)
        case .orbit: return L10n.t("环绕", "Orbit", language: lang)
        }
    }

    private func sizeIcon(_ value: StoryboardShotSize) -> String {
        switch value {
        case .extremeWide: return "mountain.2"
        case .wide: return "rectangle.expand.vertical"
        case .full: return "figure.stand"
        case .medium: return "person.crop.rectangle"
        case .mediumCloseUp: return "person.crop.square"
        case .closeUp: return "person.crop.circle"
        case .extremeCloseUp: return "eye"
        }
    }

    private func angleIcon(_ value: StoryboardCameraAngle) -> String {
        switch value {
        case .eyeLevel: return "arrow.left.and.right"
        case .high: return "arrow.down.forward"
        case .low: return "arrow.up.forward"
        case .overhead: return "arrow.down"
        case .dutch: return "rotate.right"
        case .pointOfView: return "eye.fill"
        }
    }

    private func motionPreviewIcon(_ value: StoryboardCameraMotionKind) -> String {
        switch value {
        case .push: return "arrow.up.left"
        case .pull: return "arrow.down.right"
        case .pan: return "arrow.left.and.right"
        case .truck: return "arrow.left.arrow.right"
        case .follow: return "figure.walk.motion"
        case .rise: return "arrow.up.to.line"
        case .fall: return "arrow.down.to.line"
        case .orbit: return "arrow.triangle.2.circlepath"
        case .locked: return "lock"
        case .tilt: return "arrow.up.and.down"
        case .dolly: return "arrow.up.left.and.arrow.down.right"
        case .crane: return "arrow.up.to.line"
        case .handheld: return "hand.raised"
        case .steadicam: return "figure.walk.motion"
        case .zoom: return "plus.magnifyingglass"
        }
    }
}

private struct StoryboardShotInspector: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    let sceneID: UUID
    let shot: StoryboardShot
    @ObservedObject var store: StoryboardStore
    let delete: () -> Void

    @State private var draft: StoryboardShot
    private let accent = ToolAccent.storyboard
    private var lang: AppLanguage { settings.settings.general.language.resolved }

    init(
        sceneID: UUID,
        shot: StoryboardShot,
        store: StoryboardStore,
        delete: @escaping () -> Void
    ) {
        self.sceneID = sceneID
        self.shot = shot
        self.store = store
        self.delete = delete
        _draft = State(initialValue: shot)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(L10n.t("镜头属性", "SHOT INSPECTOR", language: lang))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(colors.textSecondary)
                    Spacer()
                    lockMenu
                }

                field(L10n.t("镜头号", "Shot Number", language: lang)) {
                    Text(draft.shotNumber)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                field(L10n.t("描述", "Description", language: lang)) {
                    StoryboardMarkdownField(
                        text: $draft.description,
                        editorTitle: L10n.t("镜头内容", "Shot Content", language: lang),
                        minimumHeight: 64
                    )
                }
                field(L10n.t("时长（秒）", "Duration (seconds)", language: lang)) {
                    TextField("", value: $draft.durationSeconds, format: .number.precision(.fractionLength(1)))
                }
                field(L10n.t("景别", "Shot Size", language: lang)) {
                    Picker("", selection: $draft.shotSize) {
                        ForEach(StoryboardShotSize.allCases) { size in
                            Text(sizeLabel(size)).tag(size)
                        }
                    }
                    .labelsHidden()
                }
                field(L10n.t("机位角度", "Camera Angle", language: lang)) {
                    Picker("", selection: $draft.cameraAngle) {
                        ForEach(StoryboardCameraAngle.allCases) { angle in
                            Text(angleLabel(angle)).tag(angle)
                        }
                    }
                    .labelsHidden()
                }
                field(L10n.t("镜头 / 焦段", "Lens", language: lang)) {
                    TextField(L10n.t("请输入文本", "Enter text", language: lang), text: $draft.lens)
                }
                field(L10n.t("摄影机运动", "Camera Motion", language: lang)) {
                    Picker("", selection: cameraMotionBinding) {
                        ForEach(StoryboardCameraMotionKind.directorWheelCases) { motion in
                            Text(motionLabel(motion)).tag(motion)
                        }
                    }
                    .labelsHidden()
                }
                field(L10n.t("屏幕方向", "Screen Direction", language: lang)) {
                    Picker("", selection: $draft.screenDirection) {
                        Text(L10n.t("未设置", "Not Set", language: lang)).tag(StoryboardScreenDirection?.none)
                        ForEach(StoryboardScreenDirection.allCases) { direction in
                            Text(directionLabel(direction)).tag(StoryboardScreenDirection?.some(direction))
                        }
                    }
                    .labelsHidden()
                }
                field(L10n.t("转场", "Transition", language: lang)) {
                    Picker("", selection: $draft.transition) {
                        ForEach(StoryboardTransitionKind.allCases) { transition in
                            Text(transitionLabel(transition)).tag(StoryboardTransitionKind?.some(transition))
                        }
                    }
                    .labelsHidden()
                }
                field(L10n.t("对白", "Dialogue", language: lang)) {
                    StoryboardMarkdownField(
                        text: dialogueBinding,
                        editorTitle: L10n.t("对白", "Dialogue", language: lang),
                        minimumHeight: 54
                    )
                }
                field(L10n.t("声音备注", "Sound Notes", language: lang)) {
                    StoryboardMarkdownField(
                        text: Binding(
                            get: { draft.soundDescription ?? "" },
                            set: { draft.soundDescription = $0 }
                        ),
                        editorTitle: L10n.t("声音", "Sound", language: lang),
                        minimumHeight: 64
                    )
                }
                field(L10n.t("导演意图", "Director Intent", language: lang)) {
                    StoryboardMarkdownField(
                        text: Binding(
                            get: { draft.directorIntent ?? "" },
                            set: { draft.directorIntent = $0 }
                        ),
                        editorTitle: L10n.t("导演意图", "Director Intent", language: lang),
                        minimumHeight: 70
                    )
                }
                HStack(spacing: 10) {
                    field(L10n.t("预计条次", "Expected Takes", language: lang)) {
                        TextField("", value: Binding(
                            get: { draft.expectedTakes ?? 1 },
                            set: { draft.expectedTakes = max(1, $0) }
                        ), format: .number)
                    }
                    field(L10n.t("拍摄难度 1-5", "Difficulty 1-5", language: lang)) {
                        TextField("", value: Binding(
                            get: { draft.productionDifficulty ?? 1 },
                            set: { draft.productionDifficulty = min(max($0, 1), 5) }
                        ), format: .number)
                    }
                }
                field(L10n.t("特殊设备（逗号分隔）", "Special Equipment", language: lang)) {
                    TextField(L10n.t("请输入文本", "Enter text", language: lang), text: Binding(
                        get: { (draft.specialEquipment ?? []).joined(separator: ", ") },
                        set: { draft.specialEquipment = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
                    ))
                }
                field(L10n.t("备注", "Notes", language: lang)) {
                    StoryboardMarkdownField(
                        text: $draft.notes,
                        editorTitle: L10n.t("备注", "Notes", language: lang),
                        minimumHeight: 54
                    )
                }

                Button(action: save) {
                    Label(L10n.t("保存镜头修改", "Save Shot Changes", language: lang), systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft == shot)

                Divider()

                Button(role: .destructive, action: delete) {
                    Label(L10n.t("删除这个镜头", "Delete This Shot", language: lang), systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
            .padding(16)
        }
        .background(colors.panelBg)
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(colors.textSecondary)
            content()
                .textFieldStyle(.roundedBorder)
        }
    }

    private func save() {
        store.perform(title: L10n.t("修改镜头", "Edit Shot", language: lang), mutations: [
            .updateShot(sceneID: sceneID, shotID: shot.id, shot: draft)
        ])
    }

    private var cameraMotionBinding: Binding<StoryboardCameraMotionKind> {
        Binding(
            get: { draft.cameraMotions.first?.kind ?? .locked },
            set: { value in
                if draft.cameraMotions.isEmpty { draft.cameraMotions = [StoryboardCameraMotion(kind: value)] }
                else { draft.cameraMotions[0].kind = value }
            }
        )
    }

    private var dialogueBinding: Binding<String> {
        Binding(
            get: { draft.audioCues.first(where: { $0.kind == .dialogue })?.text ?? "" },
            set: { value in
                if let index = draft.audioCues.firstIndex(where: { $0.kind == .dialogue }) {
                    draft.audioCues[index].text = value
                } else if !value.isEmpty {
                    draft.audioCues.append(StoryboardAudioCue(kind: .dialogue, text: value, durationSeconds: draft.durationSeconds))
                }
            }
        )
    }

    private var lockMenu: some View {
        Menu {
            ForEach(["*", "order", "frame", "shotSize", "cameraAngle", "cameraMotion", "duration", "dialogue", "characters", "movementPaths", "directorIntent"], id: \.self) { field in
                Button {
                    toggleLock(field)
                } label: {
                    Label(lockLabel(field), systemImage: isLocked(field) ? "lock.fill" : "lock.open")
                }
            }
        } label: {
            Image(systemName: store.document.fieldLocks.contains(where: { $0.entityID == shot.id }) ? "lock.fill" : "lock.open")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
        .help(L10n.t("镜头字段锁定", "Shot Field Locks", language: lang))
    }

    private func toggleLock(_ field: String) {
        let existing = store.document.fieldLocks.first { $0.entityID == shot.id && $0.field == field }
        let lock = existing ?? StoryboardFieldLock(entityID: shot.id, field: field)
        store.perform(title: existing == nil
            ? L10n.t("锁定镜头字段", "Lock Shot Field", language: lang)
            : L10n.t("解锁镜头字段", "Unlock Shot Field", language: lang), mutations: [
            .setFieldLock(lock: lock, isLocked: existing == nil)
        ])
    }

    private func isLocked(_ field: String) -> Bool {
        store.document.fieldLocks.contains { $0.entityID == shot.id && $0.field == field }
    }

    private func lockLabel(_ field: String) -> String {
        switch field {
        case "*": return L10n.t("整个镜头", "Entire Shot", language: lang)
        case "order": return L10n.t("镜头顺序", "Shot Order", language: lang)
        case "frame": return L10n.t("关键画面", "Key Frame", language: lang)
        case "shotSize": return L10n.t("景别", "Shot Size", language: lang)
        case "cameraAngle": return L10n.t("角度", "Angle", language: lang)
        case "cameraMotion": return L10n.t("运镜", "Movement", language: lang)
        case "duration": return L10n.t("时长", "Duration", language: lang)
        case "dialogue": return L10n.t("台词", "Dialogue", language: lang)
        case "characters": return L10n.t("人物位置", "Character Positions", language: lang)
        case "movementPaths": return L10n.t("走位路径", "Movement Paths", language: lang)
        case "directorIntent": return L10n.t("导演意图", "Director Intent", language: lang)
        default: return field
        }
    }

    private func motionLabel(_ motion: StoryboardCameraMotionKind) -> String {
        switch motion {
        case .locked: return L10n.t("固定", "Locked", language: lang)
        case .push: return L10n.t("推", "Push", language: lang)
        case .pull: return L10n.t("拉", "Pull", language: lang)
        case .pan: return L10n.t("摇", "Pan", language: lang)
        case .tilt: return L10n.t("俯仰", "Tilt", language: lang)
        case .dolly: return L10n.t("推拉", "Dolly", language: lang)
        case .truck: return L10n.t("移", "Truck", language: lang)
        case .crane: return L10n.t("升降", "Crane", language: lang)
        case .handheld: return L10n.t("手持", "Handheld", language: lang)
        case .steadicam: return L10n.t("稳定器", "Steadicam", language: lang)
        case .zoom: return L10n.t("变焦", "Zoom", language: lang)
        case .follow: return L10n.t("跟", "Follow", language: lang)
        case .rise: return L10n.t("升", "Rise", language: lang)
        case .fall: return L10n.t("降", "Fall", language: lang)
        case .orbit: return L10n.t("环绕", "Orbit", language: lang)
        }
    }

    private func directionLabel(_ direction: StoryboardScreenDirection) -> String {
        switch direction {
        case .leftToRight: return L10n.t("左 → 右", "Left → Right", language: lang)
        case .rightToLeft: return L10n.t("右 → 左", "Right → Left", language: lang)
        case .towardCamera: return L10n.t("朝向镜头", "Toward Camera", language: lang)
        case .awayFromCamera: return L10n.t("远离镜头", "Away from Camera", language: lang)
        case .neutral: return L10n.t("中性", "Neutral", language: lang)
        }
    }

    private func transitionLabel(_ transition: StoryboardTransitionKind) -> String {
        switch transition {
        case .cut: return L10n.t("切", "Cut", language: lang)
        case .dissolve: return L10n.t("叠化", "Dissolve", language: lang)
        case .fadeIn: return L10n.t("淡入", "Fade In", language: lang)
        case .fadeOut: return L10n.t("淡出", "Fade Out", language: lang)
        case .dipToBlack: return L10n.t("黑场过渡", "Dip to Black", language: lang)
        }
    }

    private func sizeLabel(_ size: StoryboardShotSize) -> String {
        switch size {
        case .extremeWide: return L10n.t("大远景", "Extreme Wide", language: lang)
        case .wide: return L10n.t("远景", "Wide", language: lang)
        case .full: return L10n.t("全景", "Full", language: lang)
        case .medium: return L10n.t("中景", "Medium", language: lang)
        case .mediumCloseUp: return L10n.t("中近景", "Medium Close-up", language: lang)
        case .closeUp: return L10n.t("近景", "Close-up", language: lang)
        case .extremeCloseUp: return L10n.t("特写", "Extreme Close-up", language: lang)
        }
    }

    private func angleLabel(_ angle: StoryboardCameraAngle) -> String {
        switch angle {
        case .eyeLevel: return L10n.t("平视", "Eye Level", language: lang)
        case .high: return L10n.t("俯拍", "High Angle", language: lang)
        case .low: return L10n.t("仰拍", "Low Angle", language: lang)
        case .overhead: return L10n.t("顶拍", "Overhead", language: lang)
        case .dutch: return L10n.t("荷兰角", "Dutch Angle", language: lang)
        case .pointOfView: return L10n.t("主观视角", "Point of View", language: lang)
        }
    }
}

private struct StoryboardShotDropDelegate: DropDelegate {
    let targetShotID: UUID
    let sceneID: UUID
    @ObservedObject var store: StoryboardStore
    @Binding var draggedShotID: UUID?
    let language: AppLanguage

    func dropEntered(info: DropInfo) {
        guard let draggedShotID,
              draggedShotID != targetShotID,
              let scene = store.document.scene(id: sceneID),
              let sourceIndex = scene.shots.firstIndex(where: { $0.id == draggedShotID }),
              let targetIndex = scene.shots.firstIndex(where: { $0.id == targetShotID }),
              scene.shots.contains(where: { $0.id == draggedShotID }) else { return }

        var reordered = scene
        let movedShot = reordered.shots.remove(at: sourceIndex)
        reordered.shots.insert(movedShot, at: min(targetIndex, reordered.shots.count))
        var mutations: [StoryboardMutation] = [
            .moveShot(sceneID: sceneID, shotID: draggedShotID, destination: targetIndex)
        ]
        mutations.append(contentsOf:
            zip(reordered.shots, reordered.livingStoryboardNormalizedShots).compactMap { current, normalized in
                guard current != normalized else { return nil }
                return .updateShot(sceneID: sceneID, shotID: current.id, shot: normalized)
            }
        )
        store.perform(
            title: L10n.t("拖拽调整镜头顺序", "Reorder Shots", language: language),
            mutations: mutations
        )
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        DispatchQueue.main.async { draggedShotID = nil }
        return true
    }
}
