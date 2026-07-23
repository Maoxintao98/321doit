import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum StoryboardCanvasTool: String, CaseIterable, Identifiable {
    case select
    case pen
    case arrow

    var id: String { rawValue }
}

private enum StoryboardCanvasImportMode {
    case background
    case element
}

struct StoryboardFrameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var store: StoryboardStore
    let sceneID: UUID
    let shot: StoryboardShot

    @State private var draft: StoryboardShot
    @State private var tool: StoryboardCanvasTool = .select
    @State private var colorHex = "#FF3B30"
    @State private var currentPoints: [StoryboardPoint] = []
    @State private var selectedElementID: UUID?
    @State private var selectedAnnotationLayerID: UUID?
    @State private var draggedLayerID: UUID?
    @State private var draggedLayerOffset: CGSize = .zero
    @State private var layerRowFrames: [UUID: CGRect] = [:]
    @State private var pendingImports: [UUID: StoryboardCanvasImageImport] = [:]
    @State private var isDropTarget = false
    @State private var undoStack: [StoryboardShot] = []
    @State private var redoStack: [StoryboardShot] = []
    @State private var interactionSnapshot: StoryboardShot?
    @State private var zoom: Double = 0.9

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private func t(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: lang) }

    init(store: StoryboardStore, sceneID: UUID, shot: StoryboardShot) {
        self.store = store
        self.sceneID = sceneID
        self.shot = shot
        var initialDraft = shot
        let hasBaseArtwork = initialDraft.frame.assetID != nil || !(initialDraft.canvasElements ?? []).isEmpty
        if hasBaseArtwork,
           !initialDraft.annotations.isEmpty,
           (initialDraft.annotationLayers ?? []).isEmpty {
            initialDraft.annotationLayers = [StoryboardAnnotationLayer(
                name: "Drawing 1",
                annotationIDs: initialDraft.annotations.map(\.id)
            )]
        }
        if var canvasElements = initialDraft.canvasElements {
            for index in canvasElements.indices {
                if let image = store.image(for: canvasElements[index].assetID) {
                    canvasElements[index].size = Self.aspectFittedSize(
                        container: canvasElements[index].size,
                        imageSize: image.size
                    )
                }
            }
            initialDraft.canvasElements = canvasElements
        }
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                toolRail
                Divider()
                workspace
                Divider()
                inspector
                    .frame(width: 252)
            }
            Divider()
            footer
        }
        .frame(minWidth: 1080, minHeight: 720)
        .onExitCommand(perform: cancelTransient)
        .suppressAutomaticFocusEffect()
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(t("分镜画板 · \(shot.shotNumber)", "Storyboard Canvas · \(shot.shotNumber)"))
                    .font(.system(size: 17, weight: .semibold))
                Text(t("16:9 · 分层画布 · 原始素材不会被覆盖", "16:9 · layered canvas · original media is never overwritten"))
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            Menu {
                Button(t("作为背景…", "Use as Background…")) { chooseImage(mode: .background) }
                Button(t("作为画布元素…", "Use as Canvas Element…")) { chooseImage(mode: .element) }
            } label: {
                Label(t("导入图片", "Import Image"), systemImage: "plus.rectangle.on.rectangle")
            }
            .menuStyle(.borderlessButton)
            .focusable(false)

            Button(action: pasteAsElement) {
                Label(t("粘贴元素", "Paste Element"), systemImage: "doc.on.clipboard")
            }
            .keyboardShortcut("v", modifiers: .command)
            .focusable(false)

            Menu {
                ForEach(store.document.assets.filter { $0.kind == .image || $0.kind == .reference }) { asset in
                    Menu(asset.name) {
                        Button(t("设为背景", "Set as Background")) { useExistingAsset(asset.id, mode: .background) }
                        Button(t("添加为元素", "Add as Element")) { useExistingAsset(asset.id, mode: .element) }
                    }
                }
                if store.document.assets.allSatisfy({ $0.kind != .image && $0.kind != .reference }) {
                    Text(t("暂无图片素材", "No image assets yet"))
                }
            } label: {
                Label(t("素材库", "Asset Library"), systemImage: "photo.stack")
            }
            .menuStyle(.borderlessButton)
            .focusable(false)

            Divider().frame(height: 24)
            HStack(spacing: 2) {
                iconButton("arrow.uturn.backward", help: t("撤销 ⌘Z", "Undo ⌘Z"), enabled: !undoStack.isEmpty, action: undoLocal)
                    .keyboardShortcut("z", modifiers: .command)
                iconButton("arrow.uturn.forward", help: t("重做 ⇧⌘Z", "Redo ⇧⌘Z"), enabled: !redoStack.isEmpty, action: redoLocal)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            .padding(3)
            .background(colors.inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .padding(.horizontal, 20)
        .frame(height: 72)
        .background(colors.panelBg)
    }

    private var toolRail: some View {
        VStack(spacing: 8) {
            railButton(.select, icon: "cursorarrow", title: t("选择", "Select"))
            railButton(.pen, icon: "pencil.tip", title: t("画笔", "Pen"))
            railButton(.arrow, icon: "arrow.up.right", title: t("箭头", "Arrow"))
            Divider().padding(.vertical, 4)
            Menu {
                Button(t("作为背景…", "Use as Background…")) { chooseImage(mode: .background) }
                Button(t("作为元素…", "Use as Element…")) { chooseImage(mode: .element) }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 17))
                    Text(t("图片", "Image")).font(.system(size: 8, weight: .medium))
                }
                .frame(width: 46, height: 42)
            }
            .menuStyle(.borderlessButton)
            Spacer()
        }
        .padding(.vertical, 14)
        .frame(width: 64)
        .background(colors.panelBg)
    }

    private func railButton(_ value: StoryboardCanvasTool, icon: String, title: String) -> some View {
        Button {
            tool = value
            if value != .select {
                selectedElementID = nil
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 17, weight: .medium))
                Text(title).font(.system(size: 8, weight: .medium))
            }
            .foregroundStyle(tool == value ? Color.white : colors.textSecondary)
            .frame(width: 46, height: 44)
            .background(tool == value ? ToolAccent.storyboard.primary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var workspace: some View {
        GeometryReader { workspaceGeometry in
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    canvasSurface
                        .frame(
                            width: min(max(workspaceGeometry.size.width - 88, 640), 1120) * zoom,
                            height: min(max(workspaceGeometry.size.width - 88, 640), 1120) * zoom * 9 / 16
                        )
                        .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
                        .padding(44)
                }
                .frame(
                    minWidth: workspaceGeometry.size.width,
                    minHeight: workspaceGeometry.size.height
                )
            }
        }
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Canvas { context, size in
                    var dots = Path()
                    stride(from: 16.0, through: size.width, by: 24).forEach { x in
                        stride(from: 16.0, through: size.height, by: 24).forEach { y in
                            dots.addEllipse(in: CGRect(x: x, y: y, width: 1.2, height: 1.2))
                        }
                    }
                    context.fill(dots, with: .color(Color.secondary.opacity(0.10)))
                }
            }
        )
    }

    private var canvasSurface: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white
                if let backgroundImage {
                    Image(nsImage: backgroundImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else if tool == .select && elements.isEmpty && draft.annotations.isEmpty {
                    emptyCanvasState
                }

                ForEach(draft.resolvedCanvasLayerOrder) { reference in
                    canvasLayerArtwork(reference, size: geometry.size)
                }

                StoryboardAnnotationArtwork(
                    annotations: unassignedAnnotations,
                    draftKind: tool == .arrow ? .arrow : .freehand,
                    draftPoints: selectedAnnotationLayerID == nil ? currentPoints : [],
                    draftColorHex: colorHex
                )
                .allowsHitTesting(false)
            }
            .coordinateSpace(name: "frameCanvas")
            .contentShape(Rectangle())
            .gesture(drawingGesture(size: geometry.size))
            .onTapGesture {
                if tool == .select {
                    selectedElementID = nil
                    selectedAnnotationLayerID = nil
                }
            }
            .onDrop(of: [UTType.image.identifier, UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers in
                acceptDrop(providers)
            }
            .overlay(
                Rectangle().strokeBorder(isDropTarget ? ToolAccent.storyboard.primary : colors.hairline, lineWidth: isDropTarget ? 3 : 1)
            )
            .clipped()
        }
    }

    private var emptyCanvasState: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(ToolAccent.storyboard.primary.opacity(0.08))
                    .frame(width: 70, height: 70)
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(ToolAccent.storyboard.primary)
            }
            VStack(spacing: 5) {
                Text(t("开始构建镜头画面", "Start building the shot"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.textPrimary)
                Text(t("拖入图片会作为可编辑元素，也可从上方选择设为背景", "Drop an image to add it as an editable element, or choose a background above."))
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)
            }
        }
    }

    private func canvasElement(_ element: StoryboardCanvasElement, size: CGSize) -> some View {
        let width = max(1, element.size.width * size.width)
        let height = max(1, element.size.height * size.height)
        let isSelected = selectedElementID == element.id
        return ZStack(alignment: .bottomTrailing) {
            if let image = image(for: element.assetID) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(x: element.flippedHorizontally ? -1 : 1, y: element.flippedVertically ? -1 : 1)
                    .opacity(element.opacity)
                    .frame(width: width, height: height)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12))
                    .overlay(Image(systemName: "exclamationmark.triangle").foregroundStyle(Color.secondary))
                    .frame(width: width, height: height)
            }
            if isSelected {
                Rectangle()
                    .strokeBorder(ToolAccent.storyboard.primary, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                    .frame(width: width, height: height)
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 8, weight: .bold)).foregroundStyle(ToolAccent.storyboard.primary))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    .offset(x: 8, y: 8)
                    .gesture(
                        DragGesture(coordinateSpace: .named("frameCanvas"))
                            .onChanged { value in
                                beginInteraction()
                                resizeElement(element.id, toward: value.location, canvasSize: size)
                            }
                            .onEnded { _ in commitInteraction() }
                    )
            }
        }
        .frame(width: width, height: height)
        .rotationEffect(.degrees(element.rotationDegrees))
        .position(x: element.position.x * size.width, y: element.position.y * size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            guard tool == .select else { return }
            selectedElementID = element.id
            selectedAnnotationLayerID = nil
        }
        .gesture(
            DragGesture(coordinateSpace: .named("frameCanvas"))
                .onChanged { value in
                    guard tool == .select else { return }
                    selectedElementID = element.id
                    beginInteraction()
                    moveElement(element.id, to: value.location, canvasSize: size)
                }
                .onEnded { _ in commitInteraction() }
        )
        // Image layers must not swallow canvas drawing gestures. They only
        // participate in hit testing while the selection tool is active.
        .allowsHitTesting(tool == .select)
    }

    @ViewBuilder
    private func canvasLayerArtwork(_ reference: StoryboardCanvasLayerReference, size: CGSize) -> some View {
        switch reference.kind {
        case .image:
            if let element = elements.first(where: { $0.id == reference.id }) {
                canvasElement(element, size: size)
            }
        case .drawing:
            if let layer = annotationLayers.first(where: { $0.id == reference.id }) {
                let ids = Set(layer.annotationIDs)
                StoryboardAnnotationArtwork(
                    annotations: draft.annotations.filter { ids.contains($0.id) },
                    draftKind: tool == .arrow ? .arrow : .freehand,
                    draftPoints: selectedAnnotationLayerID == layer.id ? currentPoints : [],
                    draftColorHex: colorHex
                )
                .allowsHitTesting(false)
            }
        }
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            if let selectedElement { elementInspector(selectedElement) }
            else { canvasInspector }
            Divider()
            layersPanel
        }
        .background(colors.panelBg)
    }

    private var canvasInspector: some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorTitle(t("画布", "Canvas"), icon: "rectangle.inset.filled")
            HStack {
                Text(t("比例", "Aspect Ratio")).foregroundStyle(colors.textSecondary)
                Spacer()
                Text("16 : 9").font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .font(.system(size: 10))
            Button {
                mutate {
                    $0.frame.assetID = nil
                    demoteAnnotationLayersIfCanvasIsInkOnly(in: &$0)
                }
            } label: {
                Label(t("移除背景", "Remove Background"), systemImage: "rectangle.slash")
            }
            .disabled(draft.frame.assetID == nil)
            Text(t("背景会铺满画幅；图片元素可独立移动、缩放和镜像。", "The background fills the frame; image elements can be moved, scaled, and mirrored independently."))
                .font(.system(size: 9))
                .foregroundStyle(colors.textSecondary)
        }
        .padding(16)
    }

    private func elementInspector(_ element: StoryboardCanvasElement) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            inspectorTitle(t("图片元素", "Image Element"), icon: "photo")
            HStack(spacing: 8) {
                transformButton(t("水平镜像", "Flip Horizontal"), icon: "arrow.left.and.right") {
                    mutateElement(element.id) { $0.flippedHorizontally.toggle() }
                }
                transformButton(t("垂直镜像", "Flip Vertical"), icon: "arrow.up.and.down") {
                    mutateElement(element.id) { $0.flippedVertically.toggle() }
                }
            }
            valueSlider(t("缩放", "Scale"), value: element.size.width, range: 0.08...1.2) { newValue in
                let ratio = max(element.size.height / max(element.size.width, 0.001), 0.1)
                updateElement(element.id) {
                    $0.size.width = newValue
                    $0.size.height = min(1.2, newValue * ratio)
                }
            }
            valueSlider(t("旋转", "Rotation"), value: element.rotationDegrees, range: -180...180) { value in
                updateElement(element.id) { $0.rotationDegrees = value }
            }
            valueSlider(t("不透明度", "Opacity"), value: element.opacity, range: 0.05...1) { value in
                updateElement(element.id) { $0.opacity = value }
            }
            Label(t("在下方图层列表中拖拽调整前后关系", "Drag layers below to change their stacking order."), systemImage: "line.3.horizontal")
                .font(.system(size: 9))
                .foregroundStyle(colors.textSecondary)
        }
        .padding(16)
    }

    private var layersPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                inspectorTitle(t("图层", "Layers"), icon: "square.3.layers.3d")
                Spacer()
                Text("\(visibleLayerCount)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
                Button(action: createDrawingLayer) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(ToolAccent.storyboard.primary.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ToolAccent.storyboard.primary)
                .help(t("新建绘画图层", "Add drawing layer"))
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(displayedLayerOrder) { reference in
                        canvasLayerRow(reference)
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: StoryboardCanvasLayerFramePreferenceKey.self,
                                        value: [reference.id: proxy.frame(in: .named("canvasLayerStack"))]
                                    )
                                }
                            }
                            .offset(y: draggedLayerID == reference.id ? draggedLayerOffset.height : 0)
                            .zIndex(draggedLayerID == reference.id ? 2 : 0)
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 4, coordinateSpace: .named("canvasLayerStack"))
                                    .onChanged { value in updateLayerDrag(reference.id, translation: value.translation) }
                                    .onEnded { value in finishLayerDrag(reference.id, translation: value.translation) }
                            )
                    }
                    if let backgroundID = draft.frame.assetID {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.fill.on.rectangle.fill").foregroundStyle(colors.textSecondary)
                            Text(t("背景 · \(assetName(backgroundID))", "Background · \(assetName(backgroundID))")).lineLimit(1)
                            Spacer()
                            Image(systemName: "lock.fill").font(.system(size: 8))
                        }
                        .font(.system(size: 10, weight: .medium))
                        .padding(9)
                        .background(colors.inputBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .coordinateSpace(name: "canvasLayerStack")
                .onPreferenceChange(StoryboardCanvasLayerFramePreferenceKey.self) { layerRowFrames = $0 }
            }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if tool == .pen || tool == .arrow { inkPalette }
            Text(toolHint)
                .font(.system(size: 9))
                .foregroundStyle(colors.textSecondary)
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "minus.magnifyingglass").foregroundStyle(colors.textSecondary)
                Slider(value: $zoom, in: 0.55...1.35).frame(width: 110)
                Text("\(Int(zoom * 100))%")
                    .font(.system(size: 9, design: .monospaced))
                    .frame(width: 34, alignment: .trailing)
            }
            Button(role: .destructive, action: deleteSelection) {
                Label(deleteButtonTitle, systemImage: "trash")
            }
            .disabled(!hasCanvasContent)
            .keyboardShortcut(.delete, modifiers: [])
            Button(t("取消", "Cancel")) { dismiss() }
            Button(t("保存画面", "Save Frame"), action: commit)
                .buttonStyle(.borderedProminent)
                .disabled(draft == shot && pendingImports.isEmpty)
        }
        .padding(.horizontal, 20)
        .frame(height: 62)
        .background(colors.panelBg)
    }

    private var inkPalette: some View {
        HStack(spacing: 6) {
            ForEach(["#FF3B30", "#FFCC00", "#34C759", "#0A84FF", "#FFFFFF", "#111111"], id: \.self) { hex in
                Button { colorHex = hex } label: {
                    Circle()
                        .fill(canvasColor(hex))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(colorHex == hex ? ToolAccent.storyboard.primary : colors.hairline, lineWidth: colorHex == hex ? 3 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var elements: [StoryboardCanvasElement] { draft.canvasElements ?? [] }
    private var annotationLayers: [StoryboardAnnotationLayer] { draft.annotationLayers ?? [] }
    private var displayedLayerOrder: [StoryboardCanvasLayerReference] { Array(draft.resolvedCanvasLayerOrder.reversed()) }
    private var unassignedAnnotations: [StoryboardAnnotation] {
        let assigned = Set(annotationLayers.flatMap(\.annotationIDs))
        return draft.annotations.filter { !assigned.contains($0.id) }
    }
    private var selectedElement: StoryboardCanvasElement? { elements.first { $0.id == selectedElementID } }
    private var backgroundImage: NSImage? { image(for: draft.frame.assetID) }
    private var hasCanvasContent: Bool {
        draft.frame.assetID != nil || !elements.isEmpty || !draft.annotations.isEmpty || !annotationLayers.isEmpty || !currentPoints.isEmpty
    }
    private var visibleLayerCount: Int {
        elements.count + annotationLayers.count + (draft.frame.assetID == nil ? 0 : 1)
    }
    private var deleteButtonTitle: String {
        if selectedAnnotationLayerID != nil { return t("删除绘画层", "Delete Drawing Layer") }
        if selectedElementID != nil { return t("删除元素", "Delete Element") }
        return t("清空画布", "Clear Canvas")
    }
    private var toolHint: String {
        switch tool {
        case .select: return t("拖动图片移动 · 角点缩放 · Delete 删除 · Esc 取消选择", "Drag images to move them · drag corners to scale · Delete removes · Esc deselects")
        case .pen: return t("直接拖动绘制画笔", "Drag directly to draw")
        case .arrow: return t("拖动起点到终点绘制箭头", "Drag from start to end to draw an arrow")
        }
    }

    private func iconButton(_ icon: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 24, height: 24) }
            .buttonStyle(.plain)
            .foregroundStyle(enabled ? colors.textPrimary : colors.textTertiary)
            .disabled(!enabled)
            .help(help)
    }

    private func inspectorTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(colors.textSecondary)
    }

    @ViewBuilder
    private func canvasLayerRow(_ reference: StoryboardCanvasLayerReference) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(colors.textTertiary)
            if reference.kind == .drawing,
               let layer = annotationLayers.first(where: { $0.id == reference.id }) {
                Image(systemName: "pencil.and.scribble")
                    .foregroundStyle(ToolAccent.storyboard.primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(displayLayerName(layer.name)).lineLimit(1)
                    Text(t("\(layer.annotationIDs.count) 笔", "\(layer.annotationIDs.count) strokes"))
                        .font(.system(size: 8))
                        .foregroundStyle(colors.textSecondary)
                }
            } else if let element = elements.first(where: { $0.id == reference.id }) {
                Image(systemName: "photo").foregroundStyle(ToolAccent.storyboard.primary)
                Text(assetName(element.assetID)).lineLimit(1)
                if element.flippedHorizontally || element.flippedVertically {
                    Image(systemName: "arrow.left.and.right").font(.system(size: 8))
                }
            }
            Spacer()
        }
        .font(.system(size: 10, weight: .medium))
        .padding(9)
        .background(isSelected(reference) ? ToolAccent.storyboard.primary.opacity(0.11) : colors.inputBg)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(draggedLayerID == reference.id ? ToolAccent.storyboard.primary.opacity(0.55) : .clear, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { selectLayer(reference) }
        .help(t("拖拽调整图层顺序", "Drag to reorder layers"))
    }

    private func isSelected(_ reference: StoryboardCanvasLayerReference) -> Bool {
        switch reference.kind {
        case .image: return selectedElementID == reference.id
        case .drawing: return selectedAnnotationLayerID == reference.id
        }
    }

    private func selectLayer(_ reference: StoryboardCanvasLayerReference) {
        switch reference.kind {
        case .image:
            selectedElementID = reference.id
            selectedAnnotationLayerID = nil
        case .drawing:
            selectedAnnotationLayerID = reference.id
            selectedElementID = nil
        }
        tool = .select
    }

    private func transformButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 15))
                Text(title).font(.system(size: 8, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(colors.inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func valueSlider(_ title: String, value: Double, range: ClosedRange<Double>, update: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(sliderValueLabel(title: title, value: value))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
            }
            .font(.system(size: 10, weight: .medium))
            Slider(
                value: Binding(get: { value }, set: update),
                in: range,
                onEditingChanged: { editing in editing ? beginInteraction() : commitInteraction() }
            )
            .tint(ToolAccent.storyboard.primary)
        }
    }

    private func chooseImage(mode: StoryboardCanvasImportMode) {
        let panel = NSOpenPanel()
        panel.title = mode == .background ? t("选择背景图片", "Choose Background Image") : t("选择画布元素", "Choose Canvas Element")
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = mode == .element
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            addImportedImage(data: data, name: url.deletingPathExtension().lastPathComponent, fileExtension: url.pathExtension, mode: mode)
        }
    }

    private func sliderValueLabel(title: String, value: Double) -> String {
        if title == t("缩放", "Scale") || title == t("不透明度", "Opacity") {
            return "\(Int((value * 100).rounded()))%"
        }
        if title == t("旋转", "Rotation") { return "\(Int(value.rounded()))°" }
        return String(format: "%.1f", value)
    }

    private func pasteAsElement() {
        guard let pasted = pastedImage() else {
            store.errorMessage = t("剪贴板中没有可用图片。", "No usable image was found on the clipboard.")
            return
        }
        addImportedImage(
            data: pasted.data,
            name: pasted.name,
            fileExtension: pasted.fileExtension,
            mode: .element
        )
    }

    private func pastedImage() -> (data: Data, name: String, fileExtension: String)? {
        let pasteboard = NSPasteboard.general

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] {
            for value in urls {
                let url = value as URL
                guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
                      let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { continue }
                return (
                    data,
                    url.deletingPathExtension().lastPathComponent,
                    url.pathExtension.isEmpty ? "png" : url.pathExtension
                )
            }
        }

        let imageTypes: [NSPasteboard.PasteboardType] = [
            .init(UTType.png.identifier),
            .init(UTType.jpeg.identifier),
            .tiff,
            .init("public.heic")
        ]
        for type in imageTypes {
            guard let source = pasteboard.data(forType: type),
                  let image = NSImage(data: source),
                  let data = image.layeredCanvasPNGData else { continue }
            return (data, t("粘贴图片", "Pasted Image"), "png")
        }

        if let image = NSImage(pasteboard: pasteboard), let data = image.layeredCanvasPNGData {
            return (data, t("粘贴图片", "Pasted Image"), "png")
        }
        return nil
    }

    private func addImportedImage(data: Data, name: String, fileExtension: String, mode: StoryboardCanvasImportMode) {
        guard NSImage(data: data) != nil else { store.errorMessage = t("无法读取这张图片。", "This image could not be read."); return }
        let assetID = UUID()
        pendingImports[assetID] = StoryboardCanvasImageImport(assetID: assetID, data: data, fileExtension: fileExtension, name: name)
        useAsset(assetID, mode: mode)
    }

    private func useExistingAsset(_ assetID: UUID, mode: StoryboardCanvasImportMode) {
        useAsset(assetID, mode: mode)
    }

    private func useAsset(_ assetID: UUID, mode: StoryboardCanvasImportMode) {
        if mode == .background {
            mutate {
                $0.frame.assetID = assetID
                promoteAnnotationsToTopLayer(in: &$0)
            }
            selectedElementID = nil
            selectedAnnotationLayerID = nil
        } else {
            let count = elements.count
            let fittedSize = image(for: assetID).map {
                Self.aspectFittedSize(
                    container: StoryboardSize(width: 0.38, height: 0.38),
                    imageSize: $0.size
                )
            } ?? StoryboardSize(width: 0.38, height: 0.38)
            let element = StoryboardCanvasElement(
                assetID: assetID,
                position: StoryboardPoint(x: 0.5 + Double(count % 4) * 0.025, y: 0.5 + Double(count % 4) * 0.025),
                size: fittedSize
            )
            mutate {
                if $0.canvasElements == nil { $0.canvasElements = [] }
                $0.canvasElements?.append(element)
                promoteAnnotationsToTopLayer(in: &$0)
                $0.canvasLayerOrder = $0.resolvedCanvasLayerOrder
            }
            selectedElementID = element.id
            selectedAnnotationLayerID = nil
            tool = .select
        }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) } ?? item as? URL
                guard let url, let data = try? Data(contentsOf: url) else { return }
                DispatchQueue.main.async {
                    addImportedImage(data: data, name: url.deletingPathExtension().lastPathComponent, fileExtension: url.pathExtension, mode: .element)
                }
            }
            return true
        }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data else { return }
            DispatchQueue.main.async { addImportedImage(data: data, name: t("拖入图片", "Dropped Image"), fileExtension: "png", mode: .element) }
        }
        return true
    }

    private func drawingGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("frameCanvas"))
            .onChanged { value in
                guard tool != .select else { return }
                let point = normalized(value.location, size: size)
                if tool == .arrow {
                    if currentPoints.isEmpty { currentPoints = [point, point] }
                    else { currentPoints[currentPoints.count - 1] = point }
                } else if currentPoints.last.map({ hypot(point.x - $0.x, point.y - $0.y) > 0.002 }) ?? true {
                    currentPoints.append(point)
                }
            }
            .onEnded { _ in
                guard tool != .select, currentPoints.count > 1 else { currentPoints = []; return }
                let annotation = StoryboardAnnotation(
                    kind: tool == .arrow ? .arrow : .freehand,
                    points: currentPoints,
                    colorHex: colorHex
                )
                mutate {
                    $0.annotations.append(annotation)
                    if let selectedAnnotationLayerID,
                       let index = $0.annotationLayers?.firstIndex(where: { $0.id == selectedAnnotationLayerID }) {
                        $0.annotationLayers?[index].annotationIDs.append(annotation.id)
                    } else if $0.frame.assetID != nil || !($0.canvasElements ?? []).isEmpty {
                        promoteAnnotationsToTopLayer(in: &$0)
                    }
                }
                if selectedAnnotationLayerID == nil {
                    selectedAnnotationLayerID = draft.annotationLayers?.last?.id
                }
                currentPoints = []
            }
    }

    private func moveElement(_ id: UUID, to location: CGPoint, canvasSize: CGSize) {
        updateElement(id) { $0.position = normalized(location, size: canvasSize) }
    }

    private func resizeElement(_ id: UUID, toward location: CGPoint, canvasSize: CGSize) {
        guard let element = elements.first(where: { $0.id == id }) else { return }
        let center = CGPoint(x: element.position.x * canvasSize.width, y: element.position.y * canvasSize.height)
        let desiredWidth = abs(location.x - center.x) * 2 / max(canvasSize.width, 1)
        let desiredHeight = abs(location.y - center.y) * 2 / max(canvasSize.height, 1)
        guard let image = image(for: element.assetID), image.size.width > 0, image.size.height > 0 else {
            updateElement(id) {
                $0.size = StoryboardSize(
                    width: min(max(desiredWidth, 0.08), 1.5),
                    height: min(max(desiredHeight, 0.08), 1.5)
                )
            }
            return
        }

        let imageAspect = image.size.width / image.size.height
        let canvasAspect = 16.0 / 9.0
        var width = max(desiredWidth, desiredHeight * imageAspect / canvasAspect)
        var height = width * canvasAspect / imageAspect
        let maximumDimension = max(width, height)
        if maximumDimension > 1.5 {
            width *= 1.5 / maximumDimension
            height *= 1.5 / maximumDimension
        } else if maximumDimension < 0.08 {
            width *= 0.08 / max(maximumDimension, 0.001)
            height *= 0.08 / max(maximumDimension, 0.001)
        }
        updateElement(id) { $0.size = StoryboardSize(width: width, height: height) }
    }

    private static func aspectFittedSize(container: StoryboardSize, imageSize: CGSize) -> StoryboardSize {
        guard container.width > 0, container.height > 0, imageSize.width > 0, imageSize.height > 0 else {
            return container
        }
        let canvasAspect = 16.0 / 9.0
        let imageAspect = imageSize.width / imageSize.height
        let containerPixelAspect = container.width * canvasAspect / container.height
        if imageAspect >= containerPixelAspect {
            return StoryboardSize(
                width: container.width,
                height: container.width * canvasAspect / imageAspect
            )
        }
        return StoryboardSize(
            width: container.height * imageAspect / canvasAspect,
            height: container.height
        )
    }

    private func mutateElement(_ id: UUID, change: (inout StoryboardCanvasElement) -> Void) {
        mutate { shot in
            guard let index = shot.canvasElements?.firstIndex(where: { $0.id == id }) else { return }
            change(&shot.canvasElements![index])
        }
    }

    private func updateElement(_ id: UUID, change: (inout StoryboardCanvasElement) -> Void) {
        guard let index = draft.canvasElements?.firstIndex(where: { $0.id == id }) else { return }
        change(&draft.canvasElements![index])
    }

    private func moveDisplayedLayers(from source: Int, to destination: Int) {
        var displayed = displayedLayerOrder
        guard displayed.indices.contains(source), displayed.indices.contains(destination), source != destination else { return }
        let item = displayed.remove(at: source)
        displayed.insert(item, at: destination)
        draft.canvasLayerOrder = Array(displayed.reversed())
    }

    private func updateLayerDrag(_ id: UUID, translation: CGSize) {
        if draggedLayerID == nil {
            beginInteraction()
            draggedLayerID = id
        }
        guard draggedLayerID == id else { return }
        draggedLayerOffset = translation
    }

    private func finishLayerDrag(_ id: UUID, translation: CGSize) {
        defer {
            draggedLayerID = nil
            draggedLayerOffset = .zero
            commitInteraction()
        }
        let ids = displayedLayerOrder.map(\.id)
        guard let source = ids.firstIndex(of: id), let sourceFrame = layerRowFrames[id] else { return }
        let destinationY = sourceFrame.midY + translation.height
        guard let targetID = layerRowFrames.min(by: {
            abs($0.value.midY - destinationY) < abs($1.value.midY - destinationY)
        })?.key,
        let destination = ids.firstIndex(of: targetID), destination != source else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            moveDisplayedLayers(from: source, to: destination)
        }
    }

    private func createDrawingLayer() {
        let names = Set(annotationLayers.map(\.name))
        var nextNumber = 1
        while names.contains("绘画 \(nextNumber)") { nextNumber += 1 }
        let layer = StoryboardAnnotationLayer(name: "绘画 \(nextNumber)")
        mutate {
            if $0.annotationLayers == nil { $0.annotationLayers = [] }
            $0.annotationLayers?.append(layer)
            $0.canvasLayerOrder = $0.resolvedCanvasLayerOrder
        }
        selectedAnnotationLayerID = layer.id
        selectedElementID = nil
        tool = .pen
    }

    private func deleteSelection() {
        if let selectedAnnotationLayerID {
            mutate { shot in
                guard let layer = shot.annotationLayers?.first(where: { $0.id == selectedAnnotationLayerID }) else { return }
                let annotationIDs = Set(layer.annotationIDs)
                shot.annotations.removeAll { annotationIDs.contains($0.id) }
                shot.annotationLayers?.removeAll { $0.id == selectedAnnotationLayerID }
                shot.canvasLayerOrder?.removeAll { $0.id == selectedAnnotationLayerID }
                shot.canvasLayerOrder = shot.resolvedCanvasLayerOrder
            }
            self.selectedAnnotationLayerID = nil
        } else if let selectedElementID {
            mutate {
                $0.canvasElements?.removeAll { $0.id == selectedElementID }
                $0.canvasLayerOrder?.removeAll { $0.id == selectedElementID }
                demoteAnnotationLayersIfCanvasIsInkOnly(in: &$0)
                $0.canvasLayerOrder = $0.resolvedCanvasLayerOrder
            }
            self.selectedElementID = nil
        } else {
            currentPoints = []
            mutate {
                $0.frame.assetID = nil
                $0.canvasElements = []
                $0.annotations = []
                $0.annotationLayers = []
                $0.canvasLayerOrder = []
            }
        }
    }

    private func cancelTransient() {
        currentPoints = []
        selectedElementID = nil
        selectedAnnotationLayerID = nil
        interactionSnapshot = nil
        tool = .select
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
        repairSelection()
    }

    private func redoLocal() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(draft)
        draft = next
        repairSelection()
    }

    private func repairSelection() {
        if !elements.contains(where: { $0.id == selectedElementID }) { selectedElementID = nil }
        if !annotationLayers.contains(where: { $0.id == selectedAnnotationLayerID }) { selectedAnnotationLayerID = nil }
        currentPoints = []
    }

    private func promoteAnnotationsToTopLayer(in shot: inout StoryboardShot) {
        guard !shot.annotations.isEmpty else { return }
        var layers = shot.annotationLayers ?? []
        let assigned = Set(layers.flatMap(\.annotationIDs))
        let unassigned = shot.annotations.map(\.id).filter { !assigned.contains($0) }
        guard !unassigned.isEmpty else { return }
        if layers.isEmpty {
            layers.append(StoryboardAnnotationLayer(name: t("绘画 1", "Drawing 1"), annotationIDs: unassigned))
        } else {
            layers[layers.count - 1].annotationIDs.append(contentsOf: unassigned)
        }
        shot.annotationLayers = layers
        shot.canvasLayerOrder = shot.resolvedCanvasLayerOrder
    }

    private func demoteAnnotationLayersIfCanvasIsInkOnly(in shot: inout StoryboardShot) {
        guard shot.frame.assetID == nil, (shot.canvasElements ?? []).isEmpty else { return }
        shot.annotationLayers = []
        shot.canvasLayerOrder?.removeAll { $0.kind == .drawing }
    }

    private func commit() {
        let referenced = Set(([draft.frame.assetID].compactMap { $0 }) + elements.map(\.assetID))
        let imports = pendingImports.values.filter { referenced.contains($0.assetID) }
        if store.commitCanvasEdits(sceneID: sceneID, shot: draft, imports: Array(imports)) { dismiss() }
    }

    private func image(for assetID: UUID?) -> NSImage? {
        guard let assetID else { return nil }
        if let pending = pendingImports[assetID] { return NSImage(data: pending.data) }
        return store.image(for: assetID)
    }

    private func assetName(_ assetID: UUID) -> String {
        pendingImports[assetID]?.name ?? store.document.assets.first(where: { $0.id == assetID })?.name ?? t("图片", "Image")
    }

    private func displayLayerName(_ name: String) -> String {
        name == "绘画 1" ? t("绘画 1", "Drawing 1") : name
    }

    private func normalized(_ point: CGPoint, size: CGSize) -> StoryboardPoint {
        StoryboardPoint(
            x: min(max(point.x / max(size.width, 1), 0), 1),
            y: min(max(point.y / max(size.height, 1), 0), 1)
        )
    }

    private func canvasColor(_ hex: String) -> Color {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        return Color(
            red: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255
        )
    }
}

private struct StoryboardCanvasLayerFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension NSImage {
    var layeredCanvasPNGData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
