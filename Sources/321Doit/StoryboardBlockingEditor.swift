import AppKit
import SwiftUI

private enum StoryboardBlockingDrawingTool: String, CaseIterable, Identifiable {
    case freehand
    case rectangle
    case ellipse
    case text
    case move

    var id: String { rawValue }
}

private enum StoryboardBlockingSelection: Equatable {
    case character(UUID)
    case camera(UUID)
    case path(UUID)
}

struct StoryboardBlockingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var store: StoryboardStore
    let sceneID: UUID
    let shot: StoryboardShot

    @State private var draft: StoryboardShot
    @State private var pathKind: StoryboardMovementPathKind = .character
    @State private var selectedCharacterID: UUID?
    @State private var selectedCameraID: UUID?
    @State private var selectedPathID: UUID?
    @State private var currentPoints: [StoryboardPoint] = []
    @State private var newSubjectName = ""
    @State private var undoStack: [StoryboardShot] = []
    @State private var redoStack: [StoryboardShot] = []
    @State private var interactionSnapshot: StoryboardShot?
    @State private var shiftPressed = false
    @State private var modifierMonitor: Any?
    @State private var drawingTool: StoryboardBlockingDrawingTool = .freehand
    @State private var selectedMovable: StoryboardBlockingSelection?
    @FocusState private var isTextEditorFocused: Bool

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private func t(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: lang) }

    init(store: StoryboardStore, sceneID: UUID, shot: StoryboardShot) {
        self.store = store
        self.sceneID = sceneID
        self.shot = shot
        var prepared = shot
        if prepared.cameraPlacements?.isEmpty != false {
            prepared.cameraPlacements = [StoryboardCameraPlacement(name: "A Cam")]
        }
        _draft = State(initialValue: prepared)
        _pathKind = State(initialValue: prepared.characters.isEmpty ? .camera : .character)
        _selectedCharacterID = State(initialValue: prepared.characters.first?.id)
        _selectedCameraID = State(initialValue: prepared.cameraPlacements?.first?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                canvas
                Divider()
                inspector
                    .frame(width: 286)
            }
            Divider()
            footer
        }
        .frame(minWidth: 1020, minHeight: 720)
        .onChange(of: pathKind) { _ in
            selectedPathID = nil
            selectedMovable = nil
            currentPoints = []
            newSubjectName = pathKind == .camera ? t("机位", "Camera") : t("人物", "Character")
        }
        .onChange(of: drawingTool) { _ in
            currentPoints = []
            if drawingTool != .text { isTextEditorFocused = false }
        }
        .onChange(of: isTextEditorFocused) { focused in
            if !focused { commitInteraction() }
        }
        .onExitCommand(perform: cancelTransientInteraction)
        .onAppear(perform: installModifierMonitor)
        .onDisappear(perform: removeModifierMonitor)
        .suppressAutomaticFocusEffect()
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(t("平面调度 · \(shot.shotNumber)", "Blocking Layout · \(shot.shotNumber)"))
                    .font(.system(size: 17, weight: .semibold))
                Text(t("拖动主体调整位置 · 方向点旋转机位 · Shift 绘制调度路径 · 自由画笔直接绘制", "Drag subjects to position them · use the direction handle to rotate cameras · hold Shift to draw movement paths · draw directly with the freehand tool"))
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            HStack(spacing: 2) {
                compactButton("arrow.uturn.backward", help: t("撤销 ⌘Z", "Undo ⌘Z"), enabled: !undoStack.isEmpty, action: undoLocal)
                    .keyboardShortcut("z", modifiers: .command)
                compactButton("arrow.uturn.forward", help: t("重做 ⇧⌘Z", "Redo ⇧⌘Z"), enabled: !redoStack.isEmpty, action: redoLocal)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            .padding(3)
            .background(colors.inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            Picker("", selection: $pathKind) {
                Label(t("人物调度", "Character Blocking"), systemImage: "person.2").tag(StoryboardMovementPathKind.character)
                Label(t("摄影机调度", "Camera Blocking"), systemImage: "video").tag(StoryboardMovementPathKind.camera)
                Label(t("自由画笔", "Freehand"), systemImage: "pencil.and.scribble").tag(StoryboardMovementPathKind.prop)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 330)
        }
        .padding(.horizontal, 20)
        .frame(height: 72)
        .background(colors.panelBg)
    }

    private var canvas: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .textBackgroundColor)
                grid
                cameraCoverage(size: geometry.size)
                movementPaths(size: geometry.size)
                draftPath(size: geometry.size)
                characters(size: geometry.size)
                cameras(size: geometry.size)
            }
            .coordinateSpace(name: "blockingCanvas")
            .contentShape(Rectangle())
            .gesture(pathGesture(size: geometry.size))
            .simultaneousGesture(
                SpatialTapGesture(count: 2, coordinateSpace: .named("blockingCanvas"))
                    .onEnded { value in
                        addPointText(at: value.location, size: geometry.size)
                    }
            )
            .overlay(alignment: .topLeading) {
                Label(t("俯视平面", "Top View"), systemImage: "square.grid.3x3")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(colors.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.72))
    }

    private var grid: some View {
        Canvas { context, size in
            var minor = Path()
            for index in 1..<20 {
                let x = size.width * CGFloat(index) / 20
                let y = size.height * CGFloat(index) / 20
                minor.move(to: CGPoint(x: x, y: 0)); minor.addLine(to: CGPoint(x: x, y: size.height))
                minor.move(to: CGPoint(x: 0, y: y)); minor.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(minor, with: .color(Color.secondary.opacity(0.07)), lineWidth: 0.7)
            var major = Path()
            for index in 1..<4 {
                let x = size.width * CGFloat(index) / 4
                let y = size.height * CGFloat(index) / 4
                major.move(to: CGPoint(x: x, y: 0)); major.addLine(to: CGPoint(x: x, y: size.height))
                major.move(to: CGPoint(x: 0, y: y)); major.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(major, with: .color(Color.secondary.opacity(0.13)), lineWidth: 1)
        }
    }

    private func cameraCoverage(size: CGSize) -> some View {
        Canvas { context, _ in
            for camera in camerasValue {
                let apex = screenPoint(camera.position, size: size)
                let angle = camera.rotationDegrees * .pi / 180
                let half = horizontalFieldOfView(for: camera) * .pi / 360
                let length = max(70, camera.range * min(size.width, size.height) * 1.5)
                let left = CGPoint(
                    x: apex.x + cos(angle - half) * length,
                    y: apex.y + sin(angle - half) * length
                )
                let right = CGPoint(
                    x: apex.x + cos(angle + half) * length,
                    y: apex.y + sin(angle + half) * length
                )
                let end = CGPoint(x: apex.x + cos(angle) * length, y: apex.y + sin(angle) * length)
                var cone = Path()
                cone.move(to: apex)
                cone.addLine(to: left)
                cone.addLine(to: right)
                cone.closeSubpath()
                let selected = selectedCameraID == camera.id
                context.fill(
                    cone,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.blue.opacity(selected ? 0.24 : 0.14),
                            Color.cyan.opacity(selected ? 0.10 : 0.05),
                            Color.blue.opacity(0.01)
                        ]),
                        startPoint: apex,
                        endPoint: end
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func movementPaths(size: CGSize) -> some View {
        ZStack {
            ForEach(draft.movementPaths) { path in
                if path.displayText != nil {
                    blockingTextElement(path, size: size)
                } else {
                    drawingPath(points: path.points, tool: drawingTool(for: path), size: size)
                        .stroke(
                            pathColor(path),
                            style: StrokeStyle(
                                lineWidth: isPathSelected(path.id) ? 4.5 : 2.5,
                                lineCap: .round,
                                lineJoin: .round,
                                dash: path.kind == .camera ? [10, 6] : []
                            )
                        )

                    drawingPath(points: path.points, tool: drawingTool(for: path), size: size)
                        .stroke(Color.black.opacity(0.001), lineWidth: 18)
                        .onTapGesture { selectPath(path.id) }
                        .gesture(pathMoveGesture(pathID: path.id, size: size))
                }

                if path.kind != .prop, let end = path.points.last {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(pathColor(path))
                        .position(screenPoint(end, size: size))
                }

                if isPathSelected(path.id), !isUniversalMoveMode, path.displayText == nil {
                    ForEach(Array(path.points.enumerated()), id: \.offset) { index, point in
                        Circle()
                            .fill(Color.white)
                            .frame(width: 13, height: 13)
                            .overlay(Circle().stroke(pathColor(path), lineWidth: 3))
                            .position(screenPoint(point, size: size))
                            .gesture(
                                DragGesture(coordinateSpace: .named("blockingCanvas"))
                                    .onChanged { value in
                                        beginInteraction()
                                        updatePathPoint(pathID: path.id, index: index, location: value.location, size: size)
                                    }
                                    .onEnded { _ in commitInteraction() }
                            )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func blockingTextElement(_ path: StoryboardMovementPath, size: CGSize) -> some View {
        let text = path.displayText ?? ""
        let fontSize = path.fontSize ?? 24
        let selected = isPathSelected(path.id)

        if let first = path.points.first {
            if path.points.count > 1, let last = path.points.last {
                let start = screenPoint(first, size: size)
                let end = screenPoint(last, size: size)
                let width = max(abs(end.x - start.x), 36)
                let height = max(abs(end.y - start.y), fontSize * 1.5)
                Text(text)
                    .font(.system(size: fontSize))
                    .foregroundStyle(colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(width: width, height: height, alignment: .topLeading)
                    .padding(6)
                    .background(selected ? Color.accentColor.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(selected ? Color.accentColor : Color.clear, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    )
                    .position(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
                    .contentShape(Rectangle())
                    .onTapGesture { selectPath(path.id) }
                    .gesture(pathMoveGesture(pathID: path.id, size: size))
            } else {
                Text(text)
                    .font(.system(size: fontSize))
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(selected ? Color.accentColor.opacity(0.08) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
                    .position(screenPoint(first, size: size))
                    .contentShape(Rectangle())
                    .onTapGesture { selectPath(path.id) }
                    .gesture(pathMoveGesture(pathID: path.id, size: size))
            }
        }
    }

    private func draftPath(size: CGSize) -> some View {
        drawingPath(
            points: currentPoints,
            tool: pathKind == .prop ? drawingTool : .freehand,
            size: size
        )
        .stroke(
            activePathColor,
            style: StrokeStyle(lineWidth: pathKind == .prop ? 3 : 4, lineCap: .round, lineJoin: .round, dash: pathKind == .prop ? [] : [8, 4])
        )
        .allowsHitTesting(false)
    }

    private func characters(size: CGSize) -> some View {
        ZStack {
            ForEach(draft.characters) { character in
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(character.id == selectedCharacterID ? ToolAccent.storyboard.primary : colors.panelBg)
                            .frame(width: 38, height: 38)
                            .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
                        Image(systemName: "person.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(character.id == selectedCharacterID ? Color.white : ToolAccent.storyboard.primary)
                    }
                    Text(character.name)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colors.panelBg.opacity(0.88))
                        .clipShape(Capsule())
                }
                .position(screenPoint(character.position, size: size))
                .onTapGesture {
                    selectedCharacterID = character.id
                    if isUniversalMoveMode {
                        selectedMovable = .character(character.id)
                    } else {
                        pathKind = .character
                    }
                }
                .gesture(
                    DragGesture(coordinateSpace: .named("blockingCanvas"))
                        .onChanged { value in
                            beginInteraction()
                            if isUniversalMoveMode { selectedMovable = .character(character.id) }
                            moveCharacter(character.id, location: value.location, size: size)
                        }
                        .onEnded { _ in commitInteraction() }
                )
            }
        }
    }

    private func cameras(size: CGSize) -> some View {
        ZStack {
            ForEach(camerasValue) { camera in
                let center = screenPoint(camera.position, size: size)
                let angle = camera.rotationDegrees * .pi / 180
                let handle = CGPoint(x: center.x + cos(angle) * 58, y: center.y + sin(angle) * 58)

                if camera.id == selectedCameraID, !isUniversalMoveMode {
                    Path { path in
                        path.move(to: center)
                        path.addLine(to: handle)
                    }
                    .stroke(Color.blue.opacity(0.65), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    Circle()
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                        .overlay(Image(systemName: "rotate.right.fill").font(.system(size: 10)).foregroundStyle(Color.blue))
                        .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                        .position(handle)
                        .gesture(
                            DragGesture(coordinateSpace: .named("blockingCanvas"))
                                .onChanged { value in
                                    beginInteraction()
                                    rotateCamera(camera.id, toward: value.location, size: size)
                                }
                                .onEnded { _ in commitInteraction() }
                        )
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(camera.id == selectedCameraID ? Color.blue : colors.panelBg)
                        .frame(width: 44, height: 36)
                        .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                    Image(systemName: "video.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(camera.id == selectedCameraID ? Color.white : Color.blue)
                }
                .rotationEffect(.degrees(camera.rotationDegrees))
                .position(center)
                .onTapGesture {
                    selectedCameraID = camera.id
                    if isUniversalMoveMode {
                        selectedMovable = .camera(camera.id)
                    } else {
                        pathKind = .camera
                    }
                }
                .gesture(
                    DragGesture(coordinateSpace: .named("blockingCanvas"))
                        .onChanged { value in
                            beginInteraction()
                            if isUniversalMoveMode { selectedMovable = .camera(camera.id) }
                            moveCamera(camera.id, location: value.location, size: size)
                        }
                        .onEnded { _ in commitInteraction() }
                )

                Text(camera.name)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colors.panelBg.opacity(0.92))
                    .clipShape(Capsule())
                    .position(x: center.x, y: center.y + 31)
                    .allowsHitTesting(false)
            }
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 0) {
            if pathKind == .camera { cameraInspector }
            else if pathKind == .character { characterInspector }
            else { propInspector }
            Divider()
            pathList
        }
        .background(colors.panelBg)
    }

    private var cameraInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(t("当前机位", "Selected Camera"), icon: "video.fill")
            subjectMenu(
                title: selectedCameraName,
                icon: "video",
                items: camerasValue.map { ($0.id, $0.name) },
                selection: { selectedCameraID = $0 }
            )
            if let camera = selectedCamera {
                sliderRow(t("全画幅等效焦段", "Full-Frame Equivalent Focal Length"), value: effectiveFocalLength(for: camera), range: 12...200, suffix: "mm") { value in
                    updateSelectedCamera {
                        $0.equivalentFocalLengthMM = value
                        $0.fieldOfViewDegrees = horizontalFieldOfView(focalLength: value)
                    }
                }
                sliderRow(t("摄影范围", "Camera Range"), value: camera.range, range: 0.18...0.9, suffix: "") { value in
                    updateSelectedCamera { $0.range = value }
                }
                HStack {
                    Text(t("水平视角", "Horizontal Field of View"))
                    Spacer()
                    Text("\(Int(horizontalFieldOfView(for: camera).rounded()))°")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                }
                .font(.system(size: 10, weight: .medium))
                HStack {
                    Text(t("方向", "Direction"))
                    Spacer()
                    Text("\(Int(camera.rotationDegrees.rounded()))°")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                }
                .font(.system(size: 10, weight: .medium))
            }
            Label(t("拖动蓝色方向点旋转机位；视锥会实时更新", "Drag the blue direction handle to rotate the camera; its coverage updates live."), systemImage: "light.beacon.max")
                .font(.system(size: 9))
                .foregroundStyle(colors.textSecondary)
        }
        .padding(16)
    }

    private var characterInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(t("当前人物", "Selected Character"), icon: "person.fill")
            subjectMenu(
                title: selectedCharacterName,
                icon: "person",
                items: draft.characters.map { ($0.id, $0.name) },
                selection: { selectedCharacterID = $0 }
            )
            Label(t("拖动人物调整站位；按住 Shift 拖动绘制其走位", "Drag a character to position them; hold Shift and drag to draw their path."), systemImage: "figure.walk.motion")
                .font(.system(size: 9))
                .foregroundStyle(colors.textSecondary)
        }
        .padding(16)
    }

    private var propInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(t("自由画笔", "Freehand"), icon: "pencil.and.scribble")
            Picker("", selection: $drawingTool) {
                Label(t("线条", "Line"), systemImage: "pencil.and.scribble").tag(StoryboardBlockingDrawingTool.freehand)
                Label(t("矩形", "Rectangle"), systemImage: "rectangle").tag(StoryboardBlockingDrawingTool.rectangle)
                Label(t("椭圆", "Ellipse"), systemImage: "circle").tag(StoryboardBlockingDrawingTool.ellipse)
                Label(t("文字", "Text"), systemImage: "textformat").tag(StoryboardBlockingDrawingTool.text)
                Label(t("移动", "Move"), systemImage: "arrow.up.and.down.and.arrow.left.and.right").tag(StoryboardBlockingDrawingTool.move)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            if let textPath = selectedTextPath {
                TextEditor(text: selectedTextBinding)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 72)
                    .background(colors.inputBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .focused($isTextEditorFocused)
                sliderRow(
                    t("文字大小", "Text Size"),
                    value: textPath.fontSize ?? 24,
                    range: 10...96,
                    suffix: " pt",
                    update: updateSelectedTextSize
                )
            }
            Text(drawingToolHint)
                .font(.system(size: 9))
                .foregroundStyle(colors.textSecondary)
        }
        .padding(16)
    }

    private var pathList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle(t("调度路径", "Blocking Paths"), icon: "point.topleft.down.to.point.bottomright.curvepath")
                Spacer()
                Text("\(draft.movementPaths.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
            }
            if draft.movementPaths.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "scribble.variable")
                        .font(.system(size: 24, weight: .light))
                    Text(pathKind == .prop ? t("直接拖动绘制环境草图", "Drag directly to sketch the environment") : t("按住 Shift 拖动创建路径", "Hold Shift and drag to create a path"))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(colors.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(draft.movementPaths) { path in
                            HStack(spacing: 9) {
                                Circle().fill(pathColor(path)).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pathTitle(path)).font(.system(size: 10, weight: .semibold))
                                    Text(t("\(path.points.count) 个节点 · \(String(format: "%.1f", path.durationSeconds ?? 0)) 秒", "\(path.points.count) nodes · \(String(format: "%.1f", path.durationSeconds ?? 0))s"))
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundStyle(colors.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(9)
                            .background(selectedPathID == path.id ? pathColor(path).opacity(0.11) : colors.inputBg)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .contentShape(Rectangle())
                            .onTapGesture { selectedPathID = path.id }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if pathKind != .prop {
                TextField(pathKind == .camera ? t("机位名称", "Camera Name") : t("人物名称", "Character Name"), text: $newSubjectName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                Button(pathKind == .camera ? t("添加机位", "Add Camera") : t("添加人物", "Add Character")) {
                    pathKind == .camera ? addCamera() : addCharacter()
                }
            } else {
                Label(propFooterHint, systemImage: propFooterIcon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
            }
            if canDeleteSelection {
                Button(role: .destructive, action: deleteSelection) {
                    Label(t("删除所选", "Delete Selected"), systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [])
            }
            Spacer()
            Text(t("⌘Z 撤销 · ⇧⌘Z 重做 · Delete 删除 · Esc 取消", "⌘Z Undo · ⇧⌘Z Redo · Delete Remove · Esc Cancel"))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(colors.textTertiary)
            Button(t("取消", "Cancel")) { dismiss() }
            Button(t("保存调度", "Save Blocking")) {
                if store.perform(title: t("更新人物与摄影机调度", "Update Character and Camera Blocking"), mutations: [
                    .updateShot(sceneID: sceneID, shotID: shot.id, shot: draft)
                ]) { dismiss() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(draft == shot)
        }
        .padding(.horizontal, 20)
        .frame(height: 62)
        .background(colors.panelBg)
    }

    private var camerasValue: [StoryboardCameraPlacement] { draft.cameraPlacements ?? [] }
    private var selectedCamera: StoryboardCameraPlacement? { camerasValue.first { $0.id == selectedCameraID } }
    private var selectedCameraName: String { selectedCamera?.name ?? t("选择机位", "Select Camera") }
    private var selectedCharacterName: String { draft.characters.first { $0.id == selectedCharacterID }?.name ?? t("选择人物", "Select Character") }
    private var activePathColor: Color { pathKind == .camera ? .blue : pathKind == .prop ? Color(nsColor: .systemIndigo) : ToolAccent.storyboard.primary }
    private var isUniversalMoveMode: Bool { pathKind == .prop && drawingTool == .move }
    private var selectedTextPath: StoryboardMovementPath? {
        guard let selectedPathID else { return nil }
        return draft.movementPaths.first { $0.id == selectedPathID && $0.displayText != nil }
    }
    private var selectedTextBinding: Binding<String> {
        Binding(
            get: { selectedTextPath?.displayText ?? "" },
            set: { value in
                guard let index = draft.movementPaths.firstIndex(where: { $0.id == selectedPathID }) else { return }
                beginInteraction()
                draft.movementPaths[index].displayText = value
            }
        )
    }
    private var canDeleteSelection: Bool {
        if let selectedMovable {
            switch selectedMovable {
            case .character(let id): return draft.characters.contains { $0.id == id }
            case .camera(let id): return camerasValue.contains { $0.id == id }
            case .path(let id): return draft.movementPaths.contains { $0.id == id }
            }
        }
        return selectedPathID != nil || (pathKind == .camera ? selectedCameraID != nil : pathKind == .character ? selectedCharacterID != nil : false)
    }
    private var drawingToolHint: String {
        switch drawingTool {
        case .freehand: return t("直接拖动绘制环境轮廓、墙线和布景草图。", "Drag directly to sketch environment outlines, walls, and set dressing.")
        case .rectangle: return t("按下确定一个角，拖动确定矩形范围。", "Press to set one corner, then drag to define the rectangle.")
        case .ellipse: return t("按下确定外框起点，拖动绘制圆形或椭圆区域。", "Press to set the bounds, then drag to draw a circle or ellipse.")
        case .text: return t("双击新建文字；拖动框选文字区域。", "Double-click to add text; drag to define its bounds.")
        case .move: return t("拖动任意人物、机位、线条、图形或文字。", "Drag any character, camera, line, shape, or text.")
        }
    }
    private var propFooterHint: String {
        switch drawingTool {
        case .text: return t("双击新建文字，拖动创建文本框", "Double-click to add text, then drag to create its box")
        case .move: return t("拖动任意画布元素调整位置", "Drag any canvas element to reposition it")
        default: return t("直接拖动画布绘制环境与布景", "Drag directly on the canvas to sketch the environment and set")
        }
    }
    private var propFooterIcon: String {
        switch drawingTool {
        case .text: return "textformat"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        default: return "pencil.and.scribble"
        }
    }

    private func compactButton(_ icon: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 24, height: 24) }
            .buttonStyle(.plain)
            .foregroundStyle(enabled ? colors.textPrimary : colors.textTertiary)
            .disabled(!enabled)
            .help(help)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(colors.textSecondary)
    }

    private func subjectMenu(title: String, icon: String, items: [(UUID, String)], selection: @escaping (UUID) -> Void) -> some View {
        Menu {
            ForEach(items, id: \.0) { item in Button(item.1) { selection(item.0) } }
        } label: {
            HStack {
                Image(systemName: icon)
                Text(title)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(colors.inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
    }

    private func sliderRow(_ title: String, value: Double, range: ClosedRange<Double>, suffix: String, update: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text("\(String(format: "%.0f", value))\(suffix)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
            }
            .font(.system(size: 10, weight: .medium))
            Slider(
                value: Binding(get: { value }, set: update),
                in: range,
                onEditingChanged: { editing in editing ? beginInteraction() : commitInteraction() }
            )
            .tint(.blue)
        }
    }

    private func pathGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("blockingCanvas"))
            .onChanged { value in
                let canDraw = pathKind == .prop || shiftPressed || NSEvent.modifierFlags.contains(.shift)
                guard canDraw, !isUniversalMoveMode, size.width > 0, size.height > 0 else { return }
                let point = normalizedPoint(value.location, size: size)
                if pathKind == .prop, drawingTool != .freehand {
                    if currentPoints.isEmpty { currentPoints = [point, point] }
                    else { currentPoints[currentPoints.count - 1] = point }
                } else if currentPoints.last.map({ hypot(point.x - $0.x, point.y - $0.y) > 0.005 }) ?? true {
                    currentPoints.append(point)
                }
            }
            .onEnded { _ in
                guard currentPoints.count > 1 else { currentPoints = []; return }
                if pathKind == .character, selectedCharacterID == nil { currentPoints = []; return }
                if pathKind == .camera, selectedCameraID == nil { currentPoints = []; return }
                let isText = pathKind == .prop && drawingTool == .text
                let path = StoryboardMovementPath(
                    subjectID: pathKind == .camera ? selectedCameraID : pathKind == .character ? selectedCharacterID : nil,
                    points: currentPoints,
                    note: pathKind == .prop ? drawingNote(for: drawingTool) : "",
                    kind: pathKind,
                    startSeconds: 0,
                    durationSeconds: shot.durationSeconds,
                    displayText: isText ? t("文字", "Text") : nil,
                    fontSize: isText ? 24 : nil
                )
                mutate { $0.movementPaths.append(path) }
                selectPath(path.id)
                if isText { isTextEditorFocused = true }
                currentPoints = []
            }
    }

    private func addPointText(at location: CGPoint, size: CGSize) {
        guard pathKind == .prop, drawingTool == .text, size.width > 0, size.height > 0 else { return }
        let path = StoryboardMovementPath(
            points: [normalizedPoint(location, size: size)],
            note: drawingNote(for: .text),
            kind: .prop,
            startSeconds: 0,
            durationSeconds: shot.durationSeconds,
            displayText: t("文字", "Text"),
            fontSize: 24
        )
        mutate { $0.movementPaths.append(path) }
        selectPath(path.id)
        isTextEditorFocused = true
    }

    private func selectPath(_ id: UUID) {
        selectedPathID = id
        if isUniversalMoveMode { selectedMovable = .path(id) }
    }

    private func isPathSelected(_ id: UUID) -> Bool {
        selectedPathID == id || selectedMovable == .path(id)
    }

    private func pathMoveGesture(pathID: UUID, size: CGSize) -> some Gesture {
        DragGesture(coordinateSpace: .named("blockingCanvas"))
            .onChanged { value in
                guard isUniversalMoveMode else { return }
                beginInteraction()
                selectedPathID = pathID
                selectedMovable = .path(pathID)
                movePath(pathID, translation: value.translation, size: size)
            }
            .onEnded { _ in
                if isUniversalMoveMode { commitInteraction() }
            }
    }

    private func movePath(_ id: UUID, translation: CGSize, size: CGSize) {
        guard size.width > 0, size.height > 0,
              let base = interactionSnapshot?.movementPaths.first(where: { $0.id == id }),
              let index = draft.movementPaths.firstIndex(where: { $0.id == id }) else { return }
        let deltaX = translation.width / size.width
        let deltaY = translation.height / size.height
        draft.movementPaths[index].points = base.points.map {
            StoryboardPoint(
                x: min(max($0.x + deltaX, 0), 1),
                y: min(max($0.y + deltaY, 0), 1)
            )
        }
    }

    private func updateSelectedTextSize(_ value: Double) {
        guard let index = draft.movementPaths.firstIndex(where: { $0.id == selectedPathID }) else { return }
        draft.movementPaths[index].fontSize = value
    }

    private func addCharacter() {
        let trimmed = newSubjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let character = StoryboardCharacterInstance(
            name: trimmed.isEmpty ? "人物 \(draft.characters.count + 1)" : trimmed,
            position: StoryboardPoint(x: 0.5, y: 0.5)
        )
        mutate { $0.characters.append(character) }
        selectedCharacterID = character.id
        pathKind = .character
    }

    private func addCamera() {
        let trimmed = newSubjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let camera = StoryboardCameraPlacement(
            name: trimmed.isEmpty ? "机位 \(camerasValue.count + 1)" : trimmed,
            position: StoryboardPoint(x: 0.18 + Double(camerasValue.count % 3) * 0.1, y: 0.82)
        )
        mutate {
            if $0.cameraPlacements == nil { $0.cameraPlacements = [] }
            $0.cameraPlacements?.append(camera)
        }
        selectedCameraID = camera.id
        pathKind = .camera
    }

    private func moveCharacter(_ id: UUID, location: CGPoint, size: CGSize) {
        guard let index = draft.characters.firstIndex(where: { $0.id == id }) else { return }
        draft.characters[index].position = normalizedPoint(location, size: size)
    }

    private func moveCamera(_ id: UUID, location: CGPoint, size: CGSize) {
        guard let index = draft.cameraPlacements?.firstIndex(where: { $0.id == id }) else { return }
        draft.cameraPlacements?[index].position = normalizedPoint(location, size: size)
    }

    private func rotateCamera(_ id: UUID, toward location: CGPoint, size: CGSize) {
        guard let index = draft.cameraPlacements?.firstIndex(where: { $0.id == id }),
              let camera = draft.cameraPlacements?[index] else { return }
        let center = screenPoint(camera.position, size: size)
        draft.cameraPlacements?[index].rotationDegrees = atan2(location.y - center.y, location.x - center.x) * 180 / .pi
    }

    private func updateSelectedCamera(_ update: (inout StoryboardCameraPlacement) -> Void) {
        guard let index = draft.cameraPlacements?.firstIndex(where: { $0.id == selectedCameraID }) else { return }
        update(&draft.cameraPlacements![index])
    }

    private func updatePathPoint(pathID: UUID, index: Int, location: CGPoint, size: CGSize) {
        guard let pathIndex = draft.movementPaths.firstIndex(where: { $0.id == pathID }),
              draft.movementPaths[pathIndex].points.indices.contains(index) else { return }
        draft.movementPaths[pathIndex].points[index] = normalizedPoint(location, size: size)
    }

    private func deleteSelection() {
        if let selectedMovable {
            switch selectedMovable {
            case .path(let id):
                mutate { $0.movementPaths.removeAll { $0.id == id } }
                selectedPathID = nil
            case .camera(let id):
                mutate {
                    $0.cameraPlacements?.removeAll { $0.id == id }
                    $0.movementPaths.removeAll { $0.kind == .camera && $0.subjectID == id }
                }
                selectedCameraID = camerasValue.first?.id
            case .character(let id):
                mutate {
                    $0.characters.removeAll { $0.id == id }
                    $0.movementPaths.removeAll { $0.kind == .character && $0.subjectID == id }
                }
                selectedCharacterID = draft.characters.first?.id
            }
            self.selectedMovable = nil
            return
        }
        if let selectedPathID {
            mutate { $0.movementPaths.removeAll { $0.id == selectedPathID } }
            self.selectedPathID = nil
            return
        }
        if pathKind == .camera, let selectedCameraID {
            mutate {
                $0.cameraPlacements?.removeAll { $0.id == selectedCameraID }
                $0.movementPaths.removeAll { $0.kind == .camera && $0.subjectID == selectedCameraID }
            }
            self.selectedCameraID = camerasValue.first?.id
        } else if let selectedCharacterID {
            mutate {
                $0.characters.removeAll { $0.id == selectedCharacterID }
                $0.movementPaths.removeAll { $0.kind == .character && $0.subjectID == selectedCharacterID }
            }
            self.selectedCharacterID = draft.characters.first?.id
        }
    }

    private func cancelTransientInteraction() {
        currentPoints = []
        selectedPathID = nil
        selectedMovable = nil
        isTextEditorFocused = false
        interactionSnapshot = nil
    }

    private func mutate(_ change: (inout StoryboardShot) -> Void) {
        let before = draft
        change(&draft)
        guard before != draft else { return }
        undoStack.append(before)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func beginInteraction() {
        if interactionSnapshot == nil { interactionSnapshot = draft }
    }

    private func commitInteraction() {
        guard let before = interactionSnapshot else { return }
        interactionSnapshot = nil
        guard before != draft else { return }
        undoStack.append(before)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func undoLocal() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(draft)
        draft = previous
        repairSelections()
    }

    private func redoLocal() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(draft)
        draft = next
        repairSelections()
    }

    private func repairSelections() {
        if !draft.characters.contains(where: { $0.id == selectedCharacterID }) { selectedCharacterID = draft.characters.first?.id }
        if !camerasValue.contains(where: { $0.id == selectedCameraID }) { selectedCameraID = camerasValue.first?.id }
        if !draft.movementPaths.contains(where: { $0.id == selectedPathID }) { selectedPathID = nil }
        if let selectedMovable {
            let exists: Bool
            switch selectedMovable {
            case .character(let id): exists = draft.characters.contains { $0.id == id }
            case .camera(let id): exists = camerasValue.contains { $0.id == id }
            case .path(let id): exists = draft.movementPaths.contains { $0.id == id }
            }
            if !exists { self.selectedMovable = nil }
        }
        currentPoints = []
    }

    private func normalizedPoint(_ point: CGPoint, size: CGSize) -> StoryboardPoint {
        StoryboardPoint(
            x: min(max(point.x / max(size.width, 1), 0), 1),
            y: min(max(point.y / max(size.height, 1), 0), 1)
        )
    }

    private func screenPoint(_ point: StoryboardPoint, size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }

    private func drawingPath(
        points: [StoryboardPoint],
        tool: StoryboardBlockingDrawingTool,
        size: CGSize
    ) -> Path {
        Path { drawing in
            guard let first = points.first else { return }
            if tool == .rectangle || tool == .ellipse || tool == .text, let last = points.last {
                let start = screenPoint(first, size: size)
                let end = screenPoint(last, size: size)
                let rect = CGRect(
                    x: min(start.x, end.x),
                    y: min(start.y, end.y),
                    width: abs(end.x - start.x),
                    height: abs(end.y - start.y)
                )
                if tool == .ellipse { drawing.addEllipse(in: rect) }
                else { drawing.addRect(rect) }
                return
            }
            guard tool != .move else { return }
            drawing.move(to: screenPoint(first, size: size))
            for point in points.dropFirst() { drawing.addLine(to: screenPoint(point, size: size)) }
        }
    }

    private func drawingTool(for path: StoryboardMovementPath) -> StoryboardBlockingDrawingTool {
        if path.displayText != nil { return .text }
        switch path.note {
        case "blocking-shape:rectangle": return .rectangle
        case "blocking-shape:ellipse": return .ellipse
        default: return .freehand
        }
    }

    private func drawingNote(for tool: StoryboardBlockingDrawingTool) -> String {
        switch tool {
        case .freehand: return ""
        case .rectangle: return "blocking-shape:rectangle"
        case .ellipse: return "blocking-shape:ellipse"
        case .text: return "blocking-text"
        case .move: return ""
        }
    }

    private func pathColor(_ path: StoryboardMovementPath) -> Color {
        switch path.kind {
        case .camera: return .blue
        case .prop: return Color(nsColor: .systemIndigo)
        default: return ToolAccent.storyboard.primary
        }
    }

    private func pathTitle(_ path: StoryboardMovementPath) -> String {
        switch path.kind {
        case .camera: return camerasValue.first(where: { $0.id == path.subjectID })?.name ?? t("摄影机路径", "Camera Path")
        case .prop:
            switch drawingTool(for: path) {
            case .rectangle: return t("环境矩形", "Environment Rectangle")
            case .ellipse: return t("环境椭圆", "Environment Ellipse")
            case .freehand: return t("环境草图", "Environment Sketch")
            case .text:
                let trimmed = path.displayText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? t("文字", "Text") : trimmed
            case .move: return t("环境元素", "Environment Element")
            }
        default: return draft.characters.first(where: { $0.id == path.subjectID })?.name ?? t("人物走位", "Character Path")
        }
    }

    private func effectiveFocalLength(for camera: StoryboardCameraPlacement) -> Double {
        if let focalLength = camera.equivalentFocalLengthMM { return focalLength }
        let radians = max(camera.fieldOfViewDegrees, 1) * .pi / 180
        return 18 / tan(radians / 2)
    }

    private func horizontalFieldOfView(for camera: StoryboardCameraPlacement) -> Double {
        guard let focalLength = camera.equivalentFocalLengthMM else { return camera.fieldOfViewDegrees }
        return horizontalFieldOfView(focalLength: focalLength)
    }

    private func horizontalFieldOfView(focalLength: Double) -> Double {
        2 * atan(36 / (2 * max(focalLength, 1))) * 180 / .pi
    }

    private func installModifierMonitor() {
        guard modifierMonitor == nil else { return }
        modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            shiftPressed = event.modifierFlags.contains(.shift)
            return event
        }
    }

    private func removeModifierMonitor() {
        if let modifierMonitor { NSEvent.removeMonitor(modifierMonitor) }
        modifierMonitor = nil
        shiftPressed = false
    }
}
