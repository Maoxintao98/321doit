import AppKit
import SwiftUI

struct StoryboardSceneEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var store: StoryboardStore
    let scene: StoryboardScene
    let save: (StoryboardScene) -> Void
    let delete: () -> Void

    @State private var draft: StoryboardScene

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private func t(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: lang) }

    init(
        store: StoryboardStore,
        scene: StoryboardScene,
        save: @escaping (StoryboardScene) -> Void,
        delete: @escaping () -> Void
    ) {
        self.store = store
        self.scene = scene
        self.save = save
        self.delete = delete
        _draft = State(initialValue: scene)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("场次设置 · \(scene.sceneNumber)", "Scene Settings · \(scene.sceneNumber)"))
                        .font(.system(size: 16, weight: .semibold))
                }
                Spacer()
                lockMenu
            }
            .padding(.horizontal, 20)
            .frame(height: 66)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        field(t("场次编号", "Scene Number")) { TextField("", text: $draft.sceneNumber) }
                        field(t("标题", "Title")) { TextField("", text: $draft.title) }
                    }
                    HStack(spacing: 12) {
                        field(t("内 / 外景", "Interior / Exterior")) {
                            Picker("", selection: $draft.interiorExterior) {
                                Text(t("未设置", "Not Set")).tag(StoryboardInteriorExterior?.none)
                                Text(t("内景", "Interior")).tag(StoryboardInteriorExterior?.some(.interior))
                                Text(t("外景", "Exterior")).tag(StoryboardInteriorExterior?.some(.exterior))
                                Text(t("内外景", "Interior / Exterior")).tag(StoryboardInteriorExterior?.some(.interiorExterior))
                            }.labelsHidden()
                        }
                        field(t("时间", "Time")) { TextField(t("例如 夜", "e.g. Night"), text: $draft.timeOfDay) }
                        field(t("地点", "Location")) { TextField("", text: $draft.location) }
                    }
                    field(t("剧情摘要", "Synopsis")) {
                        sceneMultilineEditor(text: $draft.synopsis)
                    }
                    field(t("导演意图", "Director’s Intent")) {
                        sceneMultilineEditor(text: Binding(
                            get: { draft.directorIntent ?? "" },
                            set: { draft.directorIntent = $0 }
                        ))
                    }
                    field(t("目标时长（秒）", "Target Duration (s)")) {
                        TextField("", value: Binding(
                            get: { draft.targetDurationSeconds ?? 30 },
                            set: { draft.targetDurationSeconds = $0 }
                        ), format: .number.precision(.fractionLength(1)))
                        .frame(width: 140)
                    }
                    HStack {
                        Label(t("当前 \(scene.shots.count) 个镜头，共 \(String(format: "%.1f", scene.shots.reduce(0) { $0 + $1.durationSeconds })) 秒", "\(scene.shots.count) shots, \(String(format: "%.1f", scene.shots.reduce(0) { $0 + $1.durationSeconds })) seconds total"), systemImage: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(colors.textSecondary)
                        Spacer()
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                Button(role: .destructive) {
                    delete()
                    dismiss()
                } label: {
                    Label(t("删除场次", "Delete Scene"), systemImage: "trash")
                }
                Spacer()
                Button(t("取消", "Cancel")) { dismiss() }
                Button(t("保存", "Save")) {
                    save(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft == scene)
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
        }
        .frame(width: 680, height: 650)
        .suppressAutomaticFocusEffect()
    }

    private var lockMenu: some View {
        Menu {
            ForEach(["*", "order", "directorIntent", "space", "targetDuration"], id: \.self) { field in
                Button {
                    toggleLock(field)
                } label: {
                    Label(lockLabel(field), systemImage: isLocked(field) ? "lock.fill" : "lock.open")
                }
            }
        } label: {
            Label(t("锁定", "Lock"), systemImage: store.document.fieldLocks.contains(where: { $0.entityID == scene.id }) ? "lock.fill" : "lock.open")
        }
    }

    private func toggleLock(_ field: String) {
        let existing = store.document.fieldLocks.first { $0.entityID == scene.id && $0.field == field }
        let lock = existing ?? StoryboardFieldLock(entityID: scene.id, field: field)
        store.perform(title: existing == nil ? t("锁定场次字段", "Lock Scene Fields") : t("解锁场次字段", "Unlock Scene Fields"), mutations: [
            .setFieldLock(lock: lock, isLocked: existing == nil)
        ])
    }

    private func isLocked(_ field: String) -> Bool {
        store.document.fieldLocks.contains { $0.entityID == scene.id && $0.field == field }
    }

    private func lockLabel(_ field: String) -> String {
        switch field {
        case "*": return t("整个场次", "Entire Scene")
        case "order": return t("场次顺序", "Scene Order")
        case "directorIntent": return t("导演意图", "Director’s Intent")
        case "space": return t("场景空间", "Scene Space")
        case "targetDuration": return t("目标时长", "Target Duration")
        default: return field
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(colors.textSecondary)
            content().textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sceneMultilineEditor(text: Binding<String>) -> some View {
        TextEditor(text: text)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 104)
            .padding(7)
            .background(colors.inputBg)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(colors.hairline.opacity(0.95), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LegacyStoryboardBlockingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var store: StoryboardStore
    let sceneID: UUID
    let shot: StoryboardShot

    @State private var draft: StoryboardShot
    @State private var pathKind: StoryboardMovementPathKind = .character
    @State private var selectedSubjectID: UUID?
    @State private var currentPoints: [StoryboardPoint] = []
    @State private var selectedPathID: UUID?
    @State private var newCharacterName = ""

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private func t(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: lang) }

    init(store: StoryboardStore, sceneID: UUID, shot: StoryboardShot) {
        self.store = store
        self.sceneID = sceneID
        self.shot = shot
        _draft = State(initialValue: shot)
        _selectedSubjectID = State(initialValue: shot.characters.first?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("人物走位与摄影机路径 · \(shot.shotNumber)", "Blocking and Camera Paths · \(shot.shotNumber)"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(t("按住 Shift 在画面上绘制结构化路径；节点可单独拖动", "Hold Shift and drag to draw structured paths; drag nodes individually to adjust them."))
                        .font(.system(size: 10))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Picker("", selection: $pathKind) {
                    Text(t("人物走位", "Character Path")).tag(StoryboardMovementPathKind.character)
                    Text(t("摄影机路径", "Camera Path")).tag(StoryboardMovementPathKind.camera)
                    Text(t("道具路径", "Prop Path")).tag(StoryboardMovementPathKind.prop)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
                if pathKind == .character {
                    Menu {
                        ForEach(draft.characters) { character in
                            Button(character.name) { selectedSubjectID = character.id }
                        }
                    } label: {
                        Label(selectedCharacterName, systemImage: "person")
                    }
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 66)
            Divider()

            HStack(spacing: 0) {
                blockingCanvas
                Divider()
                pathSidebar.frame(width: 260)
            }

            Divider()
            HStack {
                TextField(t("人物名称", "Character Name"), text: $newCharacterName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                Button(t("添加人物", "Add Character")) { addCharacter() }
                Spacer()
                Button(t("取消", "Cancel")) { dismiss() }
                Button(t("保存", "Save")) {
                    if store.perform(title: t("更新人物与摄影机路径", "Update Blocking and Camera Paths"), mutations: [
                        .updateShot(sceneID: sceneID, shotID: shot.id, shot: draft)
                    ]) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft == shot)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
        }
        .frame(minWidth: 900, minHeight: 650)
    }

    private var blockingCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .textBackgroundColor)
                grid
                ForEach(draft.movementPaths) { path in
                    Path { drawing in
                        guard let first = path.points.first else { return }
                        drawing.move(to: CGPoint(x: first.x * geometry.size.width, y: first.y * geometry.size.height))
                        for point in path.points.dropFirst() {
                            drawing.addLine(to: CGPoint(x: point.x * geometry.size.width, y: point.y * geometry.size.height))
                        }
                    }
                    .stroke(pathColor(path), style: StrokeStyle(lineWidth: selectedPathID == path.id ? 5 : 3, lineCap: .round, lineJoin: .round, dash: path.kind == .camera ? [9, 5] : []))

                    if selectedPathID == path.id {
                        ForEach(Array(path.points.enumerated()), id: \.offset) { index, point in
                            Circle()
                                .fill(pathColor(path))
                                .frame(width: 13, height: 13)
                                .position(x: point.x * geometry.size.width, y: point.y * geometry.size.height)
                                .gesture(DragGesture().onChanged { value in
                                    updatePathPoint(pathID: path.id, index: index, location: value.location, size: geometry.size)
                                })
                        }
                    }
                }
                if currentPoints.count > 1 {
                    Path { drawing in
                        drawing.move(to: CGPoint(x: currentPoints[0].x * geometry.size.width, y: currentPoints[0].y * geometry.size.height))
                        for point in currentPoints.dropFirst() {
                            drawing.addLine(to: CGPoint(x: point.x * geometry.size.width, y: point.y * geometry.size.height))
                        }
                    }
                    .stroke(ToolAccent.storyboard.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [8, 4]))
                }
                ForEach(draft.characters) { character in
                    VStack(spacing: 3) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 25))
                        Text(character.name).font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(character.id == selectedSubjectID ? ToolAccent.storyboard.primary : colors.textPrimary)
                    .position(x: character.position.x * geometry.size.width, y: character.position.y * geometry.size.height)
                    .gesture(DragGesture().onChanged { value in
                        moveCharacter(character.id, location: value.location, size: geometry.size)
                    })
                    .onTapGesture { selectedSubjectID = character.id }
                }
                Image(systemName: "video.fill")
                    .font(.system(size: 25))
                    .foregroundStyle(Color.blue)
                    .position(x: geometry.size.width * 0.12, y: geometry.size.height * 0.85)
            }
            .contentShape(Rectangle())
            .gesture(pathGesture(size: geometry.size))
        }
        .padding(18)
        .background(Color.black.opacity(0.82))
    }

    private var grid: some View {
        Canvas { context, size in
            var path = Path()
            for index in 1..<10 {
                let x = size.width * CGFloat(index) / 10
                let y = size.height * CGFloat(index) / 10
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(Color.secondary.opacity(0.12)), lineWidth: 1)
        }
    }

    private var pathSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("路径", "PATHS")).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(colors.textSecondary)
            if draft.movementPaths.isEmpty {
                Text(t("按住 Shift 拖动创建第一条路径", "Hold Shift and drag to create the first path"))
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textTertiary)
            }
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(draft.movementPaths) { path in
                        Button {
                            selectedPathID = path.id
                        } label: {
                            HStack {
                                Image(systemName: path.kind == .camera ? "video" : "point.topleft.down.to.point.bottomright.curvepath")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pathTitle(path)).font(.system(size: 10, weight: .semibold))
                                    Text(t("\(path.points.count) 点 · \(String(format: "%.1f", path.durationSeconds ?? 0))s", "\(path.points.count) points · \(String(format: "%.1f", path.durationSeconds ?? 0))s"))
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundStyle(colors.textSecondary)
                                }
                                Spacer()
                                Button(role: .destructive) { deletePath(path.id) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                            }
                            .padding(9)
                            .background(selectedPathID == path.id ? ToolAccent.storyboard.primary.opacity(0.1) : colors.inputBg)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(colors.panelBg)
    }

    private var selectedCharacterName: String {
        draft.characters.first(where: { $0.id == selectedSubjectID })?.name ?? t("选择人物", "Select Character")
    }

    private func pathGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                guard NSEvent.modifierFlags.contains(.shift), size.width > 0, size.height > 0 else { return }
                let point = StoryboardPoint(
                    x: min(max(value.location.x / size.width, 0), 1),
                    y: min(max(value.location.y / size.height, 0), 1)
                )
                if currentPoints.last.map({ hypot(point.x - $0.x, point.y - $0.y) > 0.005 }) ?? true {
                    currentPoints.append(point)
                }
            }
            .onEnded { _ in
                guard currentPoints.count > 1 else { currentPoints = []; return }
                let path = StoryboardMovementPath(
                    subjectID: pathKind == .character ? selectedSubjectID : nil,
                    points: currentPoints,
                    kind: pathKind,
                    startSeconds: 0,
                    durationSeconds: shot.durationSeconds
                )
                draft.movementPaths.append(path)
                selectedPathID = path.id
                currentPoints = []
            }
    }

    private func addCharacter() {
        let character = StoryboardCharacterInstance(
            name: newCharacterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? t("人物", "Character") : newCharacterName,
            position: StoryboardPoint(x: 0.5, y: 0.5)
        )
        draft.characters.append(character)
        selectedSubjectID = character.id
    }

    private func moveCharacter(_ id: UUID, location: CGPoint, size: CGSize) {
        guard let index = draft.characters.firstIndex(where: { $0.id == id }) else { return }
        draft.characters[index].position = StoryboardPoint(
            x: min(max(location.x / size.width, 0), 1),
            y: min(max(location.y / size.height, 0), 1)
        )
    }

    private func updatePathPoint(pathID: UUID, index: Int, location: CGPoint, size: CGSize) {
        guard let pathIndex = draft.movementPaths.firstIndex(where: { $0.id == pathID }),
              draft.movementPaths[pathIndex].points.indices.contains(index) else { return }
        draft.movementPaths[pathIndex].points[index] = StoryboardPoint(
            x: min(max(location.x / size.width, 0), 1),
            y: min(max(location.y / size.height, 0), 1)
        )
    }

    private func deletePath(_ id: UUID) {
        draft.movementPaths.removeAll { $0.id == id }
        if selectedPathID == id { selectedPathID = nil }
    }

    private func pathColor(_ path: StoryboardMovementPath) -> Color {
        switch path.kind {
        case .camera: return .blue
        case .prop: return .orange
        default: return ToolAccent.storyboard.primary
        }
    }

    private func pathTitle(_ path: StoryboardMovementPath) -> String {
        switch path.kind {
        case .camera: return t("摄影机路径", "Camera Path")
        case .prop: return t("道具路径", "Prop Path")
        default: return draft.characters.first(where: { $0.id == path.subjectID })?.name ?? t("人物走位", "Character Path")
        }
    }
}

struct StoryboardFloorPlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var store: StoryboardStore
    let scene: StoryboardScene
    let selectedShot: StoryboardShot?

    @State private var draft: StoryboardScene
    @State private var selectedObjectID: UUID?

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private func t(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: lang) }

    init(store: StoryboardStore, scene: StoryboardScene, selectedShot: StoryboardShot?) {
        self.store = store
        self.scene = scene
        self.selectedShot = selectedShot
        var prepared = scene
        if prepared.space == nil { prepared.space = StoryboardSceneSpace() }
        _draft = State(initialValue: prepared)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("机位平面图 · 场 \(scene.sceneNumber)", "Floor Plan · Scene \(scene.sceneNumber)"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(t("空间对象、机位、人物、灯具、轴线和禁区均结构化保存", "Objects, cameras, characters, lights, axes, and restricted zones are saved as structured data."))
                        .font(.system(size: 10))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Menu(t("添加对象", "Add Object")) {
                    ForEach(StoryboardSceneObjectKind.allCases) { kind in
                        Button(objectLabel(kind)) { addObject(kind) }
                    }
                }
                if let selectedObjectID {
                    Button(role: .destructive) {
                        draft.space?.objects.removeAll { $0.id == selectedObjectID }
                        self.selectedObjectID = nil
                    } label: { Label(t("删除", "Delete"), systemImage: "trash") }
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 66)
            Divider()

            GeometryReader { geometry in
                ZStack {
                    Color(nsColor: .textBackgroundColor)
                    floorGrid
                    if let shot = selectedShot {
                        ForEach(shot.movementPaths) { path in
                            Path { drawing in
                                guard let first = path.points.first else { return }
                                drawing.move(to: CGPoint(x: first.x * geometry.size.width, y: first.y * geometry.size.height))
                                for point in path.points.dropFirst() {
                                    drawing.addLine(to: CGPoint(x: point.x * geometry.size.width, y: point.y * geometry.size.height))
                                }
                            }
                            .stroke(path.kind == .camera ? Color.blue : ToolAccent.storyboard.primary, style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
                        }
                    }
                    ForEach(draft.space?.objects ?? []) { object in
                        floorObject(object)
                            .frame(
                                width: max(34, object.size.width * geometry.size.width),
                                height: max(28, object.size.height * geometry.size.height)
                            )
                            .rotationEffect(.degrees(object.rotationDegrees))
                            .position(x: object.position.x * geometry.size.width, y: object.position.y * geometry.size.height)
                            .overlay(
                                selectedObjectID == object.id
                                    ? RoundedRectangle(cornerRadius: 6).stroke(ToolAccent.storyboard.primary, lineWidth: 2)
                                    : nil
                            )
                            .onTapGesture { selectedObjectID = object.id }
                            .gesture(DragGesture().onChanged { value in
                                moveObject(object.id, location: value.location, size: geometry.size)
                            })
                    }
                }
                .padding(20)
                .background(Color.black.opacity(0.82))
            }

            Divider()
            HStack {
                Text(t("选择镜头时会叠加显示人物与摄影机路径", "Selecting a shot overlays its character and camera paths."))
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)
                Spacer()
                Button(t("取消", "Cancel")) { dismiss() }
                Button(t("保存平面图", "Save Floor Plan")) {
                    if store.perform(title: t("更新机位平面图", "Update Floor Plan"), mutations: [
                        .updateScene(sceneID: scene.id, scene: draft)
                    ]) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft == scene)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
        }
        .frame(minWidth: 950, minHeight: 700)
    }

    private var floorGrid: some View {
        Canvas { context, size in
            var path = Path()
            for index in 1..<20 {
                let x = size.width * CGFloat(index) / 20
                let y = size.height * CGFloat(index) / 20
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(Color.secondary.opacity(0.1)), lineWidth: 1)
        }
    }

    private func floorObject(_ object: StoryboardSceneObject) -> some View {
        VStack(spacing: 2) {
            Image(systemName: objectIcon(object.kind)).font(.system(size: 17, weight: .semibold))
            Text(object.label).font(.system(size: 8, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(objectColor(object.kind))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(objectColor(object.kind).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func addObject(_ kind: StoryboardSceneObjectKind) {
        let object = StoryboardSceneObject(kind: kind, label: objectLabel(kind))
        if draft.space == nil { draft.space = StoryboardSceneSpace() }
        draft.space?.objects.append(object)
        selectedObjectID = object.id
    }

    private func moveObject(_ id: UUID, location: CGPoint, size: CGSize) {
        guard let index = draft.space?.objects.firstIndex(where: { $0.id == id }) else { return }
        draft.space?.objects[index].position = StoryboardPoint(
            x: min(max(location.x / size.width, 0), 1),
            y: min(max(location.y / size.height, 0), 1)
        )
    }

    private func objectLabel(_ kind: StoryboardSceneObjectKind) -> String {
        switch kind {
        case .wall: return t("墙体", "Wall")
        case .door: return t("门", "Door")
        case .window: return t("窗", "Window")
        case .furniture: return t("家具", "Furniture")
        case .character: return t("人物", "Character")
        case .camera: return t("摄影机", "Camera")
        case .light: return t("灯具", "Light")
        case .sound: return t("收音", "Sound")
        case .axis: return t("轴线", "Axis")
        case .forbiddenZone: return t("禁区", "Restricted Zone")
        }
    }

    private func objectIcon(_ kind: StoryboardSceneObjectKind) -> String {
        switch kind {
        case .wall: return "rectangle.split.3x1"
        case .door: return "door.left.hand.open"
        case .window: return "window.vertical.closed"
        case .furniture: return "sofa"
        case .character: return "person.fill"
        case .camera: return "video.fill"
        case .light: return "lightbulb.fill"
        case .sound: return "mic.fill"
        case .axis: return "line.diagonal"
        case .forbiddenZone: return "nosign"
        }
    }

    private func objectColor(_ kind: StoryboardSceneObjectKind) -> Color {
        switch kind {
        case .camera: return .blue
        case .character: return ToolAccent.storyboard.primary
        case .light: return .yellow
        case .sound: return .green
        case .axis: return .orange
        case .forbiddenZone: return .red
        default: return colors.textPrimary
        }
    }
}
