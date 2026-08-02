import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct StoryboardWorkspaceView: View {
    @EnvironmentObject private var store: ScripterStore
    @EnvironmentObject private var production: ProductionStore
    @State private var imageImporter = false

    private var lang: AppLanguage { store.language }

    var body: some View {
        NavigationSplitView {
            List(selection: $production.selectedSceneID) {
                ForEach(production.storyboard.scenes) { scene in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("场 \(scene.sceneNumber)", "Scene \(scene.sceneNumber)", language: lang))
                            .fontWeight(.semibold)
                        Text(scene.title.isEmpty
                             ? L10n.t("\(scene.shots.count) 个镜头", "\(scene.shots.count) shots", language: lang)
                             : scene.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(scene.id)
                }
                .onDelete { indexes in
                    for index in indexes.sorted(by: >) {
                        production.deleteScene(production.storyboard.scenes[index].id)
                    }
                }
            }
            .navigationTitle(L10n.t("分镜", "Storyboard", language: lang))
            .toolbar { Button { production.addScene() } label: { Image(systemName: "plus") } }
        } content: {
            List(selection: $production.selectedShotID) {
                ForEach(production.selectedScene?.shots ?? []) { shot in
                    HStack(spacing: 12) {
                        StoryboardThumbnail(shot: shot)
                            .frame(width: 88, height: 52)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.t("镜头 \(shot.shotNumber)", "Shot \(shot.shotNumber)", language: lang))
                                .fontWeight(.semibold)
                            Text(shot.description.isEmpty
                                 ? L10n.t("未填写描述", "No description", language: lang)
                                 : shot.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .tag(shot.id)
                }
                .onDelete { indexes in
                    guard let shots = production.selectedScene?.shots else { return }
                    for index in indexes.sorted(by: >) {
                        production.deleteShot(shots[index].id)
                    }
                }
            }
            .navigationTitle(production.selectedScene.map {
                L10n.t("场 \($0.sceneNumber)", "Scene \($0.sceneNumber)", language: lang)
            } ?? "")
            .toolbar { Button { production.addShot() } label: { Image(systemName: "plus") } }
        } detail: {
            if let shot = production.selectedShot {
                StoryboardShotEditor(shot: shot, showImageImporter: $imageImporter)
            } else {
                ContentUnavailableView(L10n.t("选择镜头", "Select a shot", language: lang),
                                       systemImage: "rectangle.3.group")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .fileImporter(isPresented: $imageImporter, allowedContentTypes: [.image]) { result in
            do {
                try production.importReferenceImage(from: result.get())
            } catch {
                store.alertMessage = L10n.t("无法导入图片：\(error.localizedDescription)",
                                            "Could not import image: \(error.localizedDescription)",
                                            language: lang)
            }
        }
    }
}

private struct StoryboardShotEditor: View {
    @EnvironmentObject private var store: ScripterStore
    @EnvironmentObject private var production: ProductionStore
    let shot: StoryboardShot
    @Binding var showImageImporter: Bool

    private var lang: AppLanguage { store.language }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("镜头 \(shot.shotNumber)", "Shot \(shot.shotNumber)", language: lang))
                            .font(.title2.bold())
                        Text(L10n.t("用手指或 Apple Pencil 直接批注", "Annotate with a finger or Apple Pencil", language: lang))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { showImageImporter = true } label: {
                        Label(L10n.t("参考图", "Reference", language: lang), systemImage: "photo.badge.plus")
                    }
                    Button { production.undoLastAnnotation() } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(shot.annotations.isEmpty)
                    Button(role: .destructive) { production.clearAnnotations() } label: {
                        Image(systemName: "eraser")
                    }
                    .disabled(shot.annotations.isEmpty)
                }

                StoryboardDrawingCanvas(shot: shot)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 12) {
                    Picker(L10n.t("景别", "Size", language: lang), selection: shotBinding(\.shotSize)) {
                        ForEach(StoryboardShotSize.allCases) { Text($0.shortLabel(lang)).tag($0) }
                    }
                    Picker(L10n.t("机位", "Angle", language: lang), selection: shotBinding(\.cameraAngle)) {
                        ForEach(StoryboardCameraAngle.allCases) { Text($0.shortLabel(lang)).tag($0) }
                    }
                    TextField(L10n.t("镜头 / 焦段", "Lens", language: lang), text: shotBinding(\.lens))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 160)
                    TextField(L10n.t("秒", "Seconds", language: lang),
                              value: shotBinding(\.durationSeconds), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }

                TextField(L10n.t("画面与动作描述", "Picture and action", language: lang),
                          text: shotBinding(\.description), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...8)

                TextField(L10n.t("导演意图", "Director intent", language: lang),
                          text: optionalShotBinding(\.directorIntent), axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                TextField(L10n.t("声音与对白", "Sound and dialogue", language: lang),
                          text: optionalShotBinding(\.soundDescription), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(20)
        }
    }

    private func shotBinding<Value>(_ keyPath: WritableKeyPath<StoryboardShot, Value>) -> Binding<Value> {
        Binding(
            get: { production.selectedShot?[keyPath: keyPath] ?? shot[keyPath: keyPath] },
            set: { value in production.updateSelectedShot { $0[keyPath: keyPath] = value } })
    }

    private func optionalShotBinding(_ keyPath: WritableKeyPath<StoryboardShot, String?>) -> Binding<String> {
        Binding(
            get: { production.selectedShot?[keyPath: keyPath] ?? "" },
            set: { value in production.updateSelectedShot { $0[keyPath: keyPath] = value.isEmpty ? nil : value } })
    }
}

private struct StoryboardDrawingCanvas: View {
    @EnvironmentObject private var production: ProductionStore
    let shot: StoryboardShot
    @State private var activeStroke: [CGPoint] = []

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let url = production.imageURL(for: shot),
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color(uiColor: .secondarySystemGroupedBackground)
                    if shot.annotations.isEmpty && activeStroke.isEmpty {
                        Image(systemName: "pencil.and.outline")
                            .font(.system(size: 42))
                            .foregroundStyle(.tertiary)
                    }
                }

                StoryboardInkLayer(
                    annotations: shot.annotations,
                    activeStroke: activeStroke,
                    lineWidth: 3)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard let last = activeStroke.last else {
                                activeStroke.append(value.location)
                                return
                            }
                            let dx = value.location.x - last.x
                            let dy = value.location.y - last.y
                            if dx * dx + dy * dy >= 2.25 {
                                activeStroke.append(value.location)
                            }
                        }
                        .onEnded { _ in
                            let size = geometry.size
                            let points = activeStroke.map {
                                StoryboardPoint(
                                    x: min(1, max(0, $0.x / max(size.width, 1))),
                                    y: min(1, max(0, $0.y / max(size.height, 1))))
                            }
                            production.appendStroke(points)
                            activeStroke.removeAll(keepingCapacity: true)
                        }
                )
            }
        }
    }
}

private struct StoryboardThumbnail: View {
    @EnvironmentObject private var production: ProductionStore
    let shot: StoryboardShot

    var body: some View {
        ZStack {
            if let url = production.imageURL(for: shot),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Color(uiColor: .tertiarySystemGroupedBackground)
                if shot.annotations.isEmpty {
                    Image(systemName: "rectangle.and.pencil.and.ellipsis")
                        .foregroundStyle(.secondary)
                }
            }

            StoryboardInkLayer(
                annotations: shot.annotations,
                activeStroke: [],
                lineWidth: 1.5)
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct StoryboardInkLayer: View {
    let annotations: [StoryboardAnnotation]
    let activeStroke: [CGPoint]
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            for annotation in annotations where annotation.kind == .freehand {
                draw(
                    annotation.points.map {
                        CGPoint(x: $0.x * size.width, y: $0.y * size.height)
                    },
                    context: &context)
            }
            draw(activeStroke, context: &context)
        }
    }

    private func draw(_ points: [CGPoint], context: inout GraphicsContext) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        context.stroke(
            path,
            with: .color(.red),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}

private extension StoryboardShotSize {
    func shortLabel(_ lang: AppLanguage) -> String {
        switch self {
        case .extremeWide: return L10n.t("大远景", "Extreme wide", language: lang)
        case .wide: return L10n.t("远景", "Wide", language: lang)
        case .full: return L10n.t("全景", "Full", language: lang)
        case .medium: return L10n.t("中景", "Medium", language: lang)
        case .mediumCloseUp: return L10n.t("中近景", "Medium close", language: lang)
        case .closeUp: return L10n.t("近景", "Close-up", language: lang)
        case .extremeCloseUp: return L10n.t("特写", "Extreme close", language: lang)
        }
    }
}

private extension StoryboardCameraAngle {
    func shortLabel(_ lang: AppLanguage) -> String {
        switch self {
        case .eyeLevel: return L10n.t("平视", "Eye level", language: lang)
        case .high: return L10n.t("俯拍", "High", language: lang)
        case .low: return L10n.t("仰拍", "Low", language: lang)
        case .overhead: return L10n.t("顶拍", "Overhead", language: lang)
        case .dutch: return L10n.t("荷兰角", "Dutch", language: lang)
        case .pointOfView: return L10n.t("主观", "POV", language: lang)
        }
    }
}
