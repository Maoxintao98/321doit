import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct LegacyStoryboardFrameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var store: StoryboardStore
    let sceneID: UUID
    let shot: StoryboardShot

    @State private var selectedAssetID: UUID?
    @State private var annotations: [StoryboardAnnotation]
    @State private var pendingImageData: Data?
    @State private var pendingImageName = "frame"
    @State private var pendingImageExtension = "png"
    @State private var tool: StoryboardDrawingTool = .pen
    @State private var colorHex = "#FF3B30"
    @State private var currentPoints: [StoryboardPoint] = []
    @State private var isShiftDrawing = false
    @State private var isDropTarget = false

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private func t(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: lang) }

    init(store: StoryboardStore, sceneID: UUID, shot: StoryboardShot) {
        self.store = store
        self.sceneID = sceneID
        self.shot = shot
        _selectedAssetID = State(initialValue: shot.frame.assetID)
        _annotations = State(initialValue: shot.annotations)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            canvas
            Divider()
            footer
        }
        .frame(minWidth: 900, minHeight: 650)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(t("画面编辑 · \(shot.shotNumber)", "Frame Editor · \(shot.shotNumber)"))
                    .font(.system(size: 16, weight: .semibold))
                Text(t("导入、拖拽、粘贴、复制或空白绘制；原图永不被覆盖", "Import, drop, paste, copy, or draw on a blank frame; original media is never overwritten."))
                    .font(.system(size: 10))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            Button(action: chooseImage) {
                Label(t("上传图片", "Import Image"), systemImage: "photo.badge.plus")
            }
            Button(action: pasteImage) {
                Label(t("粘贴", "Paste"), systemImage: "doc.on.clipboard")
            }
            Menu {
                ForEach(store.document.assets) { asset in
                    Button(asset.name) {
                        selectedAssetID = asset.id
                        pendingImageData = nil
                    }
                }
                if store.document.assets.isEmpty {
                    Text(t("暂无可复制画面", "No frames available to copy"))
                }
            } label: {
                Label(t("复制已有", "Copy Existing"), systemImage: "square.on.square")
            }
            Button {
                selectedAssetID = nil
                pendingImageData = nil
            } label: {
                Label(t("空白", "Blank"), systemImage: "rectangle")
            }
            Divider().frame(height: 24)
            Picker("", selection: $tool) {
                Label(t("画笔", "Pen"), systemImage: "pencil.tip").tag(StoryboardDrawingTool.pen)
                Label(t("箭头", "Arrow"), systemImage: "arrow.up.right").tag(StoryboardDrawingTool.arrow)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 138)
            inkPalette
            Button {
                if !annotations.isEmpty { annotations.removeLast() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(annotations.isEmpty)
            .help(t("撤回上一笔", "Undo last stroke"))
        }
        .padding(.horizontal, 18)
        .frame(height: 68)
        .background(colors.panelBg)
    }

    private var inkPalette: some View {
        HStack(spacing: 5) {
            ForEach(["#FF3B30", "#FFCC00", "#34C759", "#0A84FF", "#FFFFFF", "#111111"], id: \.self) { hex in
                Button { colorHex = hex } label: {
                    Circle()
                        .fill(frameColor(hex))
                        .frame(width: 17, height: 17)
                        .overlay(
                            Circle().strokeBorder(
                                colorHex == hex ? ToolAccent.storyboard.primary : colors.hairline,
                                lineWidth: colorHex == hex ? 3 : 1
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var canvas: some View {
        ZStack {
            Color.black.opacity(0.9)
            GeometryReader { geometry in
                ZStack {
                    Color(nsColor: .textBackgroundColor)
                    if let image = displayedImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 34, weight: .light))
                            Text(t("拖入图片，或按住 Shift 在空白画面上绘制", "Drop an image, or hold Shift to draw on a blank frame"))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(colors.textTertiary)
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
                        .strokeBorder(
                            isDropTarget ? ToolAccent.storyboard.primary : Color.white.opacity(0.2),
                            lineWidth: isDropTarget ? 3 : 1
                        )
                )
                .contentShape(Rectangle())
                .gesture(shiftDrawingGesture(size: geometry.size))
                .onDrop(of: [UTType.image.identifier, UTType.fileURL.identifier], isTargeted: $isDropTarget) { providers in
                    acceptDrop(providers)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .padding(28)
        }
    }

    private var footer: some View {
        HStack {
            Label(t("Shift 是绘制开关；松开 Shift 结束当前笔画", "Hold Shift to draw; release it to finish the current stroke"), systemImage: "shift")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(colors.textSecondary)
            Spacer()
            if let assetID = selectedAssetID,
               let asset = store.document.assets.first(where: { $0.id == assetID }) {
                Text(t("素材版本 \(asset.versions.count)", "Asset versions \(asset.versions.count)"))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(colors.textTertiary)
            }
            Button(t("取消", "Cancel")) { dismiss() }
            Button(t("确定", "Done")) { commit() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(colors.panelBg)
    }

    private var displayedImage: NSImage? {
        if let pendingImageData { return NSImage(data: pendingImageData) }
        return store.image(for: selectedAssetID)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.title = t("选择分镜画面", "Choose Storyboard Frame")
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadImage(url: url)
    }

    private func pasteImage() {
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard), let data = image.storyboardPNGData {
            pendingImageData = data
            pendingImageName = t("粘贴画面", "Pasted Frame")
            pendingImageExtension = "png"
            selectedAssetID = nil
            return
        }
        store.errorMessage = t("剪贴板中没有可用图片。", "No usable image was found on the clipboard.")
    }

    private func loadImage(url: URL) {
        do {
            pendingImageData = try Data(contentsOf: url)
            pendingImageName = url.deletingPathExtension().lastPathComponent
            pendingImageExtension = url.pathExtension
            selectedAssetID = nil
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else { url = item as? URL }
                guard let url else { return }
                DispatchQueue.main.async { loadImage(url: url) }
            }
            return true
        }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            guard let data else { return }
            DispatchQueue.main.async {
                pendingImageData = data
                pendingImageName = t("拖入画面", "Dropped Frame")
                pendingImageExtension = "png"
                selectedAssetID = nil
            }
        }
        return true
    }

    private func shiftDrawingGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .onChanged { value in
                if !isShiftDrawing {
                    guard NSEvent.modifierFlags.contains(.shift) else { return }
                    isShiftDrawing = true
                    currentPoints = []
                }
                guard size.width > 0, size.height > 0 else { return }
                let point = StoryboardPoint(
                    x: min(max(value.location.x / size.width, 0), 1),
                    y: min(max(value.location.y / size.height, 0), 1)
                )
                if tool == .arrow {
                    if currentPoints.isEmpty { currentPoints = [point, point] }
                    else { currentPoints[currentPoints.count - 1] = point }
                } else if currentPoints.last.map({ hypot(point.x - $0.x, point.y - $0.y) > 0.002 }) ?? true {
                    currentPoints.append(point)
                }
            }
            .onEnded { _ in
                guard isShiftDrawing else { return }
                if currentPoints.count > 1 {
                    annotations.append(StoryboardAnnotation(
                        kind: tool == .pen ? .freehand : .arrow,
                        points: currentPoints,
                        colorHex: colorHex
                    ))
                }
                currentPoints = []
                isShiftDrawing = false
            }
    }

    private func commit() {
        var updated = shot
        updated.annotations = annotations
        updated.frame.assetID = selectedAssetID
        let succeeded: Bool
        if let pendingImageData {
            succeeded = store.importFrameImage(
                data: pendingImageData,
                fileExtension: pendingImageExtension,
                name: pendingImageName,
                source: "imported",
                sceneID: sceneID,
                shot: updated
            )
        } else {
            succeeded = store.perform(title: t("更新镜头画面", "Update Shot Frame"), mutations: [
                .updateShot(sceneID: sceneID, shotID: shot.id, shot: updated)
            ])
        }
        if succeeded { dismiss() }
    }

    private func frameColor(_ hex: String) -> Color {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        return Color(
            red: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255
        )
    }
}

private extension NSImage {
    var storyboardPNGData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
