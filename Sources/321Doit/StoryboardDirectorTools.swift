import AppKit
import SwiftUI

enum StoryboardDrawingTool: String, CaseIterable, Identifiable {
    case pen
    case arrow

    var id: String { rawValue }
}

enum StoryboardDirectorWheelCategory: String, CaseIterable, Identifiable {
    case shotSize
    case cameraAngle
    case cameraMotion

    var id: String { rawValue }
}

private enum StoryboardInk {
    static let palette = ["#FF3B30", "#FFCC00", "#34C759", "#0A84FF", "#FFFFFF", "#111111"]

    static func color(hex: String) -> Color {
        let normalized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard normalized.count == 6, let value = Int(normalized, radix: 16) else {
            return .red
        }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

struct StoryboardFramePreview: View {
    @EnvironmentObject private var settings: SettingsStore
    var backgroundImage: NSImage?
    let annotations: [StoryboardAnnotation]
    var elements: [StoryboardCanvasElement] = []
    var annotationLayers: [StoryboardAnnotationLayer] = []
    var layerOrder: [StoryboardCanvasLayerReference] = []
    var imageResolver: ((UUID) -> NSImage?)?
    var allowsShiftDrawing = false
    var addShiftDrawing: (([StoryboardPoint]) -> Void)?

    @State private var currentPoints: [StoryboardPoint] = []
    @State private var isShiftDrawing = false
    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))

                if let backgroundImage {
                    Image(nsImage: backgroundImage)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }

                ForEach(resolvedLayerOrder) { reference in
                    previewLayer(reference, size: geometry.size)
                }

                if backgroundImage == nil && elements.isEmpty && annotations.isEmpty && currentPoints.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 28, weight: .light))
                        Text(allowsShiftDrawing
                            ? L10n.t("SHIFT + 拖动 · 导演笔", "SHIFT + DRAG · DIRECTOR PEN", language: lang)
                            : L10n.t("画面素材", "FRAME ASSET", language: lang))
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundStyle(Color.secondary.opacity(0.58))
                }

                StoryboardAnnotationArtwork(
                    annotations: unassignedAnnotations,
                    draftKind: .freehand,
                    draftPoints: currentPoints,
                    draftColorHex: "#FF3B30"
                )
                .padding(1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(shiftDrawingGesture(size: geometry.size))
        }
    }

    private var resolvedLayerOrder: [StoryboardCanvasLayerReference] {
        let imageIDs = Set(elements.map(\.id))
        let drawingIDs = Set(annotationLayers.map(\.id))
        var seen = Set<UUID>()
        var result = layerOrder.filter { reference in
            let exists = reference.kind == .image ? imageIDs.contains(reference.id) : drawingIDs.contains(reference.id)
            return exists && seen.insert(reference.id).inserted
        }
        result.append(contentsOf: elements.compactMap { element in
            seen.insert(element.id).inserted ? StoryboardCanvasLayerReference(id: element.id, kind: .image) : nil
        })
        result.append(contentsOf: annotationLayers.compactMap { layer in
            seen.insert(layer.id).inserted ? StoryboardCanvasLayerReference(id: layer.id, kind: .drawing) : nil
        })
        return result
    }

    private var unassignedAnnotations: [StoryboardAnnotation] {
        let assigned = Set(annotationLayers.flatMap(\.annotationIDs))
        return annotations.filter { !assigned.contains($0.id) }
    }

    @ViewBuilder
    private func previewLayer(_ reference: StoryboardCanvasLayerReference, size: CGSize) -> some View {
        switch reference.kind {
        case .image:
            if let element = elements.first(where: { $0.id == reference.id }) {
                previewElement(element, size: size)
            }
        case .drawing:
            if let layer = annotationLayers.first(where: { $0.id == reference.id }) {
                let ids = Set(layer.annotationIDs)
                StoryboardAnnotationArtwork(
                    annotations: annotations.filter { ids.contains($0.id) },
                    draftKind: .freehand,
                    draftPoints: [],
                    draftColorHex: "#FF3B30"
                )
                .padding(1)
            }
        }
    }

    @ViewBuilder
    private func previewElement(_ element: StoryboardCanvasElement, size: CGSize) -> some View {
        if let image = imageResolver?(element.assetID) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(
                    x: element.flippedHorizontally ? -1 : 1,
                    y: element.flippedVertically ? -1 : 1
                )
                .opacity(element.opacity)
                .frame(
                    width: max(1, element.size.width * size.width),
                    height: max(1, element.size.height * size.height)
                )
                .rotationEffect(.degrees(element.rotationDegrees))
                .position(
                    x: element.position.x * size.width,
                    y: element.position.y * size.height
                )
        }
    }

    private func shiftDrawingGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                guard allowsShiftDrawing else { return }
                if !isShiftDrawing {
                    guard NSEvent.modifierFlags.contains(.shift) else { return }
                    isShiftDrawing = true
                    currentPoints = []
                }
                appendNormalized(value.location, size: size)
            }
            .onEnded { _ in
                guard isShiftDrawing else { return }
                if currentPoints.count > 1 {
                    addShiftDrawing?(currentPoints)
                }
                currentPoints = []
                isShiftDrawing = false
            }
    }

    private func appendNormalized(_ location: CGPoint, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let point = StoryboardPoint(
            x: min(max(location.x / size.width, 0), 1),
            y: min(max(location.y / size.height, 0), 1)
        )
        if let last = currentPoints.last {
            let distance = hypot(point.x - last.x, point.y - last.y)
            guard distance > 0.003 else { return }
        }
        currentPoints.append(point)
    }
}

struct StoryboardDrawingEditor: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    let shot: StoryboardShot
    var backgroundImage: NSImage?
    let save: ([StoryboardAnnotation]) -> Void

    @State private var annotations: [StoryboardAnnotation]
    @State private var tool: StoryboardDrawingTool = .pen
    @State private var colorHex = "#FF3B30"
    @State private var currentPoints: [StoryboardPoint] = []
    private var lang: AppLanguage { settings.settings.general.language.resolved }

    init(
        shot: StoryboardShot,
        backgroundImage: NSImage? = nil,
        save: @escaping ([StoryboardAnnotation]) -> Void
    ) {
        self.shot = shot
        self.backgroundImage = backgroundImage
        self.save = save
        _annotations = State(initialValue: shot.annotations)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(L10n.t("导演笔", "Director Pen", language: lang)) · \(shot.shotNumber)")
                        .font(.system(size: 16, weight: .semibold))
                    Text(L10n.t("在画面上标出演员、运镜与构图意图", "Mark performance, camera movement, and composition directly on the frame", language: lang))
                        .font(.system(size: 10))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Picker("", selection: $tool) {
                    Label(L10n.t("画笔", "Pen", language: lang), systemImage: "pencil.tip").tag(StoryboardDrawingTool.pen)
                    Label(L10n.t("箭头", "Arrow", language: lang), systemImage: "arrow.up.right").tag(StoryboardDrawingTool.arrow)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 150)

                HStack(spacing: 7) {
                    ForEach(StoryboardInk.palette, id: \.self) { hex in
                        Button {
                            colorHex = hex
                        } label: {
                            Circle()
                                .fill(StoryboardInk.color(hex: hex))
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            colorHex == hex ? ToolAccent.storyboard.primary : colors.hairline,
                                            lineWidth: colorHex == hex ? 3 : 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    if !annotations.isEmpty { annotations.removeLast() }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(annotations.isEmpty)
                .help(L10n.t("撤回上一笔", "Undo Last Stroke", language: lang))

                Button(role: .destructive) {
                    annotations.removeAll()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(annotations.isEmpty)
                .help(L10n.t("清空绘画", "Clear Drawing", language: lang))
            }
            .padding(.horizontal, 20)
            .frame(height: 66)
            .background(colors.panelBg)

            Divider()

            ZStack {
                Color.black.opacity(0.88)
                GeometryReader { geometry in
                    ZStack {
                        Color(nsColor: .textBackgroundColor)
                        if let backgroundImage {
                            Image(nsImage: backgroundImage)
                                .resizable()
                                .scaledToFit()
                        }
                        StoryboardAnnotationArtwork(
                            annotations: annotations,
                            draftKind: tool == .pen ? .freehand : .arrow,
                            draftPoints: currentPoints,
                            draftColorHex: colorHex
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .gesture(drawingGesture(size: geometry.size))
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .padding(28)
            }

            Divider()

            HStack {
                Label(L10n.t("拖动画笔；箭头工具从起点拖到终点", "Drag to draw; drag the arrow tool from start to end", language: lang), systemImage: "cursorarrow.motionlines")
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)
                Spacer()
                Button(L10n.t("取消", "Cancel", language: lang)) { dismiss() }
                Button(L10n.t("保存到镜头", "Save to Shot", language: lang)) {
                    save(annotations)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(annotations == shot.annotations)
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
            .background(colors.panelBg)
        }
        .frame(minWidth: 820, minHeight: 590)
    }

    private func drawingGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                let point = StoryboardPoint(
                    x: min(max(value.location.x / size.width, 0), 1),
                    y: min(max(value.location.y / size.height, 0), 1)
                )
                switch tool {
                case .pen:
                    if let last = currentPoints.last,
                       hypot(point.x - last.x, point.y - last.y) <= 0.002 {
                        return
                    }
                    currentPoints.append(point)
                case .arrow:
                    if currentPoints.isEmpty {
                        currentPoints = [point, point]
                    } else {
                        currentPoints[currentPoints.count - 1] = point
                    }
                }
            }
            .onEnded { _ in
                guard currentPoints.count > 1 else {
                    currentPoints = []
                    return
                }
                annotations.append(StoryboardAnnotation(
                    kind: tool == .pen ? .freehand : .arrow,
                    points: currentPoints,
                    colorHex: colorHex
                ))
                currentPoints = []
            }
    }
}

struct StoryboardAnnotationArtwork: View {
    let annotations: [StoryboardAnnotation]
    var draftKind: StoryboardAnnotationKind?
    var draftPoints: [StoryboardPoint] = []
    var draftColorHex = "#FF3B30"

    var body: some View {
        Canvas { context, size in
            for annotation in annotations {
                draw(
                    annotation.kind,
                    points: annotation.points,
                    color: StoryboardInk.color(hex: annotation.colorHex),
                    in: &context,
                    size: size
                )
            }
            if let draftKind, !draftPoints.isEmpty {
                draw(
                    draftKind,
                    points: draftPoints,
                    color: StoryboardInk.color(hex: draftColorHex),
                    in: &context,
                    size: size
                )
            }
        }
    }

    private func draw(
        _ kind: StoryboardAnnotationKind,
        points: [StoryboardPoint],
        color: Color,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let scale = min(size.width / 900, size.height / (900 * 9 / 16))
        let lineWidth = max(1, min(4, 4 * scale))
        let arrowHeadLength = max(5, min(17, 17 * scale))
        let cornerRadius = max(1, min(3, 3 * scale))
        let converted = points.map {
            CGPoint(x: $0.x * size.width, y: $0.y * size.height)
        }
        guard let first = converted.first else { return }

        switch kind {
        case .freehand:
            var path = Path()
            path.move(to: first)
            for point in converted.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )

        case .arrow:
            guard let end = converted.last, converted.count > 1 else { return }
            var path = Path()
            path.move(to: first)
            path.addLine(to: end)
            let angle = atan2(end.y - first.y, end.x - first.x)
            path.move(to: end)
            path.addLine(to: CGPoint(
                x: end.x - arrowHeadLength * cos(angle - .pi / 6),
                y: end.y - arrowHeadLength * sin(angle - .pi / 6)
            ))
            path.move(to: end)
            path.addLine(to: CGPoint(
                x: end.x - arrowHeadLength * cos(angle + .pi / 6),
                y: end.y - arrowHeadLength * sin(angle + .pi / 6)
            ))
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )

        case .rectangle:
            guard let end = converted.last else { return }
            let rect = CGRect(
                x: min(first.x, end.x),
                y: min(first.y, end.y),
                width: abs(first.x - end.x),
                height: abs(first.y - end.y)
            )
            context.stroke(
                Path(roundedRect: rect, cornerRadius: cornerRadius),
                with: .color(color),
                lineWidth: lineWidth
            )

        case .text:
            break
        }
    }
}

struct StoryboardDirectorWheel: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    let shot: StoryboardShot
    let apply: (StoryboardShot) -> Void

    @State private var draft: StoryboardShot
    @State private var category: StoryboardDirectorWheelCategory = .shotSize
    private var lang: AppLanguage { settings.settings.general.language.resolved }

    init(shot: StoryboardShot, apply: @escaping (StoryboardShot) -> Void) {
        self.shot = shot
        self.apply = apply
        _draft = State(initialValue: shot)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(L10n.t("导演轮盘", "Director Wheel", language: lang)) · \(shot.shotNumber)")
                        .font(.system(size: 16, weight: .semibold))
                    Text(L10n.t("转动拍摄语言，不离开镜头上下文", "Change visual language without leaving the shot", language: lang))
                        .font(.system(size: 10))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Picker("", selection: $category) {
                    Text(L10n.t("景别", "Size", language: lang)).tag(StoryboardDirectorWheelCategory.shotSize)
                    Text(L10n.t("角度", "Angle", language: lang)).tag(StoryboardDirectorWheelCategory.cameraAngle)
                    Text(L10n.t("运动", "Move", language: lang)).tag(StoryboardDirectorWheelCategory.cameraMotion)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 230)
            }
            .padding(.horizontal, 20)
            .frame(height: 66)

            Divider()

            DirectorWheelControl(
                options: options,
                selectedID: selectedOptionID,
                centerTitle: categoryTitle,
                centerValue: selectedOptionLabel,
                choose: choose
            )
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Text(L10n.t("选择先进入草稿，确认后写入，可完整撤销", "Selections stay in draft until applied and remain fully undoable", language: lang))
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)
                Spacer()
                Button(L10n.t("取消", "Cancel", language: lang)) { dismiss() }
                Button(L10n.t("应用到镜头", "Apply to Shot", language: lang)) {
                    apply(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft == shot)
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
        }
        .frame(width: 580, height: 650)
        .background(colors.panelBg)
    }

    private var options: [DirectorWheelOption] {
        switch category {
        case .shotSize:
            return StoryboardShotSize.allCases.map {
                DirectorWheelOption(id: $0.rawValue, label: shotSizeLabel($0), systemImage: shotSizeIcon($0))
            }
        case .cameraAngle:
            return StoryboardCameraAngle.allCases.map {
                DirectorWheelOption(id: $0.rawValue, label: angleLabel($0), systemImage: angleIcon($0))
            }
        case .cameraMotion:
            return StoryboardCameraMotionKind.directorWheelCases.map {
                DirectorWheelOption(id: $0.rawValue, label: motionLabel($0), systemImage: motionIcon($0))
            }
        }
    }

    private var selectedOptionID: String {
        switch category {
        case .shotSize: return draft.shotSize.rawValue
        case .cameraAngle: return draft.cameraAngle.rawValue
        case .cameraMotion: return (draft.cameraMotions.first?.kind ?? .locked).rawValue
        }
    }

    private var categoryTitle: String {
        switch category {
        case .shotSize: return L10n.t("景别", "Shot Size", language: lang)
        case .cameraAngle: return L10n.t("角度", "Angle", language: lang)
        case .cameraMotion: return L10n.t("运动", "Movement", language: lang)
        }
    }

    private var selectedOptionLabel: String {
        options.first(where: { $0.id == selectedOptionID })?.label ?? "—"
    }

    private func choose(_ option: DirectorWheelOption) {
        switch category {
        case .shotSize:
            if let value = StoryboardShotSize(rawValue: option.id) {
                draft.shotSize = value
            }
        case .cameraAngle:
            if let value = StoryboardCameraAngle(rawValue: option.id) {
                draft.cameraAngle = value
            }
        case .cameraMotion:
            guard let value = StoryboardCameraMotionKind(rawValue: option.id) else { return }
            if draft.cameraMotions.isEmpty {
                draft.cameraMotions = [StoryboardCameraMotion(kind: value)]
            } else {
                draft.cameraMotions[0].kind = value
            }
        }
    }

    private func shotSizeLabel(_ value: StoryboardShotSize) -> String {
        switch value {
        case .extremeWide: return L10n.t("大远景", "Extreme Wide", language: lang)
        case .wide: return L10n.t("远景", "Wide", language: lang)
        case .full: return L10n.t("全景", "Full", language: lang)
        case .medium: return L10n.t("中景", "Medium", language: lang)
        case .mediumCloseUp: return L10n.t("中近景", "Medium Close-up", language: lang)
        case .closeUp: return L10n.t("近景", "Close-up", language: lang)
        case .extremeCloseUp: return L10n.t("特写", "Extreme Close-up", language: lang)
        }
    }

    private func shotSizeIcon(_ value: StoryboardShotSize) -> String {
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

    private func angleLabel(_ value: StoryboardCameraAngle) -> String {
        switch value {
        case .eyeLevel: return L10n.t("平视", "Eye Level", language: lang)
        case .high: return L10n.t("俯拍", "High Angle", language: lang)
        case .low: return L10n.t("仰拍", "Low Angle", language: lang)
        case .overhead: return L10n.t("顶拍", "Overhead", language: lang)
        case .dutch: return L10n.t("荷兰角", "Dutch Angle", language: lang)
        case .pointOfView: return L10n.t("主观", "POV", language: lang)
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

    private func motionLabel(_ value: StoryboardCameraMotionKind) -> String {
        switch value {
        case .locked: return L10n.t("固定", "Locked", language: lang)
        case .push: return L10n.t("推", "Push", language: lang)
        case .pull: return L10n.t("拉", "Pull", language: lang)
        case .pan: return L10n.t("摇", "Pan", language: lang)
        case .tilt: return L10n.t("俯仰", "Tilt", language: lang)
        case .dolly: return L10n.t("推拉", "Dolly", language: lang)
        case .truck: return L10n.t("横移", "Truck", language: lang)
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

    private func motionIcon(_ value: StoryboardCameraMotionKind) -> String {
        switch value {
        case .locked: return "lock"
        case .push: return "arrow.up.left"
        case .pull: return "arrow.down.right"
        case .pan: return "arrow.left.and.right"
        case .tilt: return "arrow.up.and.down"
        case .dolly: return "arrow.up.left.and.arrow.down.right"
        case .truck: return "arrow.left.arrow.right"
        case .crane: return "arrow.up.to.line"
        case .handheld: return "hand.raised"
        case .steadicam: return "figure.walk.motion"
        case .zoom: return "plus.magnifyingglass"
        case .follow: return "figure.walk.motion"
        case .rise: return "arrow.up.to.line"
        case .fall: return "arrow.down.to.line"
        case .orbit: return "arrow.triangle.2.circlepath"
        }
    }
}

struct StoryboardDirectorCellPicker: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    let category: StoryboardDirectorWheelCategory
    let shot: StoryboardShot
    let apply: (StoryboardShot) -> Void
    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(title) · \(shot.shotNumber)")
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.t("点选后直接写入分镜表，可撤销", "Choose an option to update the shot; the change is undoable", language: lang))
                        .font(.system(size: 9)).foregroundStyle(colors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 15).frame(height: 52)
            Divider()
            DirectorWheelControl(
                options: options,
                selectedID: selectedID,
                centerTitle: title,
                centerValue: selectedLabel,
                choose: choose
            )
            .padding(14)
        }
        .frame(width: 360, height: 410)
        .background(colors.panelBg)
    }

    private var title: String {
        switch category {
        case .shotSize: return L10n.t("景别", "Shot Size", language: lang)
        case .cameraAngle: return L10n.t("角度", "Angle", language: lang)
        case .cameraMotion: return L10n.t("运镜", "Movement", language: lang)
        }
    }

    private var selectedID: String {
        switch category {
        case .shotSize: return shot.shotSize.rawValue
        case .cameraAngle: return shot.cameraAngle.rawValue
        case .cameraMotion: return (shot.cameraMotions.first?.kind ?? .locked).rawValue
        }
    }

    private var selectedLabel: String {
        options.first(where: { $0.id == selectedID })?.label ?? "—"
    }

    private var options: [DirectorWheelOption] {
        switch category {
        case .shotSize:
            return StoryboardShotSize.allCases.map { DirectorWheelOption(id: $0.rawValue, label: sizeLabel($0), systemImage: sizeIcon($0)) }
        case .cameraAngle:
            return StoryboardCameraAngle.allCases.map { DirectorWheelOption(id: $0.rawValue, label: angleLabel($0), systemImage: angleIcon($0)) }
        case .cameraMotion:
            return StoryboardCameraMotionKind.directorWheelCases.map { DirectorWheelOption(id: $0.rawValue, label: motionLabel($0), systemImage: motionIcon($0)) }
        }
    }

    private func choose(_ option: DirectorWheelOption) {
        var updated = shot
        switch category {
        case .shotSize:
            guard let value = StoryboardShotSize(rawValue: option.id) else { return }
            updated.shotSize = value
        case .cameraAngle:
            guard let value = StoryboardCameraAngle(rawValue: option.id) else { return }
            updated.cameraAngle = value
        case .cameraMotion:
            guard let value = StoryboardCameraMotionKind(rawValue: option.id) else { return }
            if updated.cameraMotions.isEmpty { updated.cameraMotions = [StoryboardCameraMotion(kind: value)] }
            else { updated.cameraMotions[0].kind = value }
        }
        apply(updated)
        dismiss()
    }

    private func sizeLabel(_ value: StoryboardShotSize) -> String {
        switch value { case .extremeWide: return L10n.t("大远景", "Extreme Wide", language: lang); case .wide: return L10n.t("远景", "Wide", language: lang); case .full: return L10n.t("全景", "Full", language: lang); case .medium: return L10n.t("中景", "Medium", language: lang); case .mediumCloseUp: return L10n.t("中近景", "Medium Close-up", language: lang); case .closeUp: return L10n.t("近景", "Close-up", language: lang); case .extremeCloseUp: return L10n.t("特写", "Extreme Close-up", language: lang) }
    }
    private func sizeIcon(_ value: StoryboardShotSize) -> String {
        switch value { case .extremeWide: return "mountain.2"; case .wide: return "rectangle.expand.vertical"; case .full: return "figure.stand"; case .medium: return "person.crop.rectangle"; case .mediumCloseUp: return "person.crop.square"; case .closeUp: return "person.crop.circle"; case .extremeCloseUp: return "eye" }
    }
    private func angleLabel(_ value: StoryboardCameraAngle) -> String {
        switch value { case .eyeLevel: return L10n.t("平视", "Eye Level", language: lang); case .high: return L10n.t("俯拍", "High Angle", language: lang); case .low: return L10n.t("仰拍", "Low Angle", language: lang); case .overhead: return L10n.t("顶拍", "Overhead", language: lang); case .dutch: return L10n.t("荷兰角", "Dutch Angle", language: lang); case .pointOfView: return L10n.t("主观", "POV", language: lang) }
    }
    private func angleIcon(_ value: StoryboardCameraAngle) -> String {
        switch value { case .eyeLevel: return "arrow.left.and.right"; case .high: return "arrow.down.forward"; case .low: return "arrow.up.forward"; case .overhead: return "arrow.down"; case .dutch: return "rotate.right"; case .pointOfView: return "eye.fill" }
    }
    private func motionLabel(_ value: StoryboardCameraMotionKind) -> String {
        switch value { case .locked: return L10n.t("定", "Lock", language: lang); case .push: return L10n.t("推", "Push", language: lang); case .pull: return L10n.t("拉", "Pull", language: lang); case .pan: return L10n.t("摇", "Pan", language: lang); case .tilt: return L10n.t("俯仰", "Tilt", language: lang); case .dolly: return L10n.t("推拉", "Dolly", language: lang); case .truck: return L10n.t("移", "Truck", language: lang); case .crane: return L10n.t("升降", "Crane", language: lang); case .handheld: return L10n.t("手持", "Handheld", language: lang); case .steadicam: return L10n.t("稳定器", "Steadicam", language: lang); case .zoom: return L10n.t("变焦", "Zoom", language: lang); case .follow: return L10n.t("跟", "Follow", language: lang); case .rise: return L10n.t("升", "Rise", language: lang); case .fall: return L10n.t("降", "Fall", language: lang); case .orbit: return L10n.t("环绕", "Orbit", language: lang) }
    }
    private func motionIcon(_ value: StoryboardCameraMotionKind) -> String {
        switch value { case .locked: return "lock"; case .push: return "arrow.up.left"; case .pull: return "arrow.down.right"; case .pan: return "arrow.left.and.right"; case .tilt: return "arrow.up.and.down"; case .dolly: return "arrow.up.left.and.arrow.down.right"; case .truck: return "arrow.left.arrow.right"; case .crane: return "arrow.up.to.line"; case .handheld: return "hand.raised"; case .steadicam: return "figure.walk.motion"; case .zoom: return "plus.magnifyingglass"; case .follow: return "figure.walk.motion"; case .rise: return "arrow.up.to.line"; case .fall: return "arrow.down.to.line"; case .orbit: return "arrow.triangle.2.circlepath" }
    }
}

struct StoryboardPressDirectorWheel: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    let category: StoryboardDirectorWheelCategory
    let highlightedID: String?
    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(spacing: 0) {
            DirectorWheelControl(
                options: options,
                selectedID: highlightedID ?? "",
                centerTitle: title,
                centerValue: highlightedLabel,
                choose: { _ in }
            )
            .animation(.easeOut(duration: 0.12), value: highlightedID)
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(Circle())
        .shadow(color: Color.black.opacity(0.22), radius: 22, y: 10)
        .overlay(Circle().strokeBorder(colors.hairline.opacity(0.7), lineWidth: 0.8))
        .allowsHitTesting(false)
    }

    private var title: String {
        switch category { case .shotSize: return L10n.t("景别", "Shot Size", language: lang); case .cameraAngle: return L10n.t("角度", "Angle", language: lang); case .cameraMotion: return L10n.t("运镜", "Movement", language: lang) }
    }

    private var highlightedLabel: String {
        guard let highlightedID else { return L10n.t("松开取消", "Release to cancel", language: lang) }
        return options.first(where: { $0.id == highlightedID })?.label ?? L10n.t("松开取消", "Release to cancel", language: lang)
    }

    private var options: [DirectorWheelOption] {
        switch category {
        case .shotSize:
            return StoryboardShotSize.allCases.map { DirectorWheelOption(id: $0.rawValue, label: sizeLabel($0), systemImage: sizeIcon($0)) }
        case .cameraAngle:
            return StoryboardCameraAngle.allCases.map { DirectorWheelOption(id: $0.rawValue, label: angleLabel($0), systemImage: angleIcon($0)) }
        case .cameraMotion:
            return StoryboardCameraMotionKind.directorWheelCases.map { DirectorWheelOption(id: $0.rawValue, label: motionLabel($0), systemImage: motionIcon($0)) }
        }
    }

    private func sizeLabel(_ value: StoryboardShotSize) -> String {
        switch value { case .extremeWide: return L10n.t("大远景", "Extreme Wide", language: lang); case .wide: return L10n.t("远景", "Wide", language: lang); case .full: return L10n.t("全景", "Full", language: lang); case .medium: return L10n.t("中景", "Medium", language: lang); case .mediumCloseUp: return L10n.t("中近景", "Medium Close-up", language: lang); case .closeUp: return L10n.t("近景", "Close-up", language: lang); case .extremeCloseUp: return L10n.t("特写", "Extreme Close-up", language: lang) }
    }
    private func sizeIcon(_ value: StoryboardShotSize) -> String {
        switch value { case .extremeWide: return "mountain.2"; case .wide: return "rectangle.expand.vertical"; case .full: return "figure.stand"; case .medium: return "person.crop.rectangle"; case .mediumCloseUp: return "person.crop.square"; case .closeUp: return "person.crop.circle"; case .extremeCloseUp: return "eye" }
    }
    private func angleLabel(_ value: StoryboardCameraAngle) -> String {
        switch value { case .eyeLevel: return L10n.t("平视", "Eye Level", language: lang); case .high: return L10n.t("俯拍", "High Angle", language: lang); case .low: return L10n.t("仰拍", "Low Angle", language: lang); case .overhead: return L10n.t("顶拍", "Overhead", language: lang); case .dutch: return L10n.t("荷兰角", "Dutch Angle", language: lang); case .pointOfView: return L10n.t("主观", "POV", language: lang) }
    }
    private func angleIcon(_ value: StoryboardCameraAngle) -> String {
        switch value { case .eyeLevel: return "arrow.left.and.right"; case .high: return "arrow.down.forward"; case .low: return "arrow.up.forward"; case .overhead: return "arrow.down"; case .dutch: return "rotate.right"; case .pointOfView: return "eye.fill" }
    }
    private func motionLabel(_ value: StoryboardCameraMotionKind) -> String {
        switch value { case .locked: return L10n.t("定", "Lock", language: lang); case .push: return L10n.t("推", "Push", language: lang); case .pull: return L10n.t("拉", "Pull", language: lang); case .pan: return L10n.t("摇", "Pan", language: lang); case .tilt: return L10n.t("俯仰", "Tilt", language: lang); case .dolly: return L10n.t("推拉", "Dolly", language: lang); case .truck: return L10n.t("移", "Truck", language: lang); case .crane: return L10n.t("升降", "Crane", language: lang); case .handheld: return L10n.t("手持", "Handheld", language: lang); case .steadicam: return L10n.t("稳定器", "Steadicam", language: lang); case .zoom: return L10n.t("变焦", "Zoom", language: lang); case .follow: return L10n.t("跟", "Follow", language: lang); case .rise: return L10n.t("升", "Rise", language: lang); case .fall: return L10n.t("降", "Fall", language: lang); case .orbit: return L10n.t("环绕", "Orbit", language: lang) }
    }
    private func motionIcon(_ value: StoryboardCameraMotionKind) -> String {
        switch value { case .locked: return "lock"; case .push: return "arrow.up.left"; case .pull: return "arrow.down.right"; case .pan: return "arrow.left.and.right"; case .tilt: return "arrow.up.and.down"; case .dolly: return "arrow.up.left.and.arrow.down.right"; case .truck: return "arrow.left.arrow.right"; case .crane: return "arrow.up.to.line"; case .handheld: return "hand.raised"; case .steadicam: return "figure.walk.motion"; case .zoom: return "plus.magnifyingglass"; case .follow: return "figure.walk.motion"; case .rise: return "arrow.up.to.line"; case .fall: return "arrow.down.to.line"; case .orbit: return "arrow.triangle.2.circlepath" }
    }
}

private struct DirectorWheelOption: Identifiable {
    let id: String
    let label: String
    let systemImage: String
}

private struct DirectorWheelControl: View {
    @Environment(\.themeColors) private var colors
    let options: [DirectorWheelOption]
    let selectedID: String
    let centerTitle: String
    let centerValue: String
    let choose: (DirectorWheelOption) -> Void

    private let accent = ToolAccent.storyboard

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let diameter = side * 0.92
            let radius = diameter / 2
            let count = max(options.count, 1)
            let step = 360.0 / Double(count)

            ZStack {
                Circle()
                    .fill(colors.inputBg.opacity(0.72))
                    .frame(width: diameter, height: diameter)
                    .position(center)
                    .shadow(color: Color.black.opacity(0.12), radius: 24, y: 12)

                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    let start = Angle.degrees(-90 - step / 2 + Double(index) * step)
                    let end = Angle.degrees(-90 - step / 2 + Double(index + 1) * step)
                    let mid = Angle.degrees(-90 + Double(index) * step)
                    let selected = option.id == selectedID
                    let segment = DirectorWheelSegment(startAngle: start, endAngle: end, innerRatio: 0.39)

                    Button {
                        choose(option)
                    } label: {
                        ZStack {
                            segment
                                .fill(selected ? accent.primary : colors.panelBg)
                            segment
                                .strokeBorder(
                                    selected ? Color.white.opacity(0.5) : colors.hairline.opacity(0.85),
                                    lineWidth: selected ? 1.5 : 0.8
                                )
                            VStack(spacing: 5) {
                                Image(systemName: option.systemImage)
                                    .font(.system(size: 16, weight: .semibold))
                                Text(option.label)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(selected ? Color.white : colors.textPrimary)
                            .position(
                                x: diameter / 2 + cos(CGFloat(mid.radians)) * radius * 0.68,
                                y: diameter / 2 + sin(CGFloat(mid.radians)) * radius * 0.68
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: diameter, height: diameter)
                    .position(center)
                    .accessibilityLabel(option.label)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }

                Circle()
                    .fill(colors.panelBg)
                    .frame(width: diameter * 0.34, height: diameter * 0.34)
                    .overlay(
                        VStack(spacing: 5) {
                            Text(centerTitle)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(colors.textSecondary)
                            Text(centerValue)
                                .font(.system(size: centerValue.count > 2 ? 12 : 17, weight: .bold))
                                .foregroundStyle(accent.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(accent.primary.opacity(0.28), lineWidth: 1)
                    )
                    .position(center)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct DirectorWheelSegment: InsettableShape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRatio: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2 - insetAmount
        let innerRadius = outerRadius * innerRatio
        var path = Path()
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> DirectorWheelSegment {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
