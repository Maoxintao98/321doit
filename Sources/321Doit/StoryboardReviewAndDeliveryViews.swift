import AppKit
import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct StoryboardAnalysisView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    @EnvironmentObject private var settings: SettingsStore
    let scene: StoryboardScene

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private func t(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: lang) }
    let selectShot: (UUID) -> Void

    private var issues: [StoryboardAnalysisIssue] {
        StoryboardAnalysisEngine.analyze(scene: scene, language: lang).sorted { $0.severity.rawValue > $1.severity.rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("连续性与拍摄检查 · 场 \(scene.sceneNumber)", "Continuity and Production Check · Scene \(scene.sceneNumber)"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(t("本地确定性规则，不发送剧本或图片", "Deterministic local rules; no script or images are sent."))
                        .font(.system(size: 10))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                severitySummary
            }
            .padding(.horizontal, 20)
            .frame(height: 68)
            Divider()

            if issues.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.green)
                    Text(t("没有发现确定性风险", "No deterministic risks found")).font(.system(size: 15, weight: .semibold))
                    Text(t("这不替代导演判断，但数据、节奏和基础连续性检查已通过。", "This does not replace directorial judgment, but data, pacing, and baseline continuity checks passed."))
                        .font(.system(size: 10)).foregroundStyle(colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(issues) { issue in
                            Button {
                                if let id = issue.shotIDs.first { selectShot(id) }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: severityIcon(issue.severity))
                                        .font(.system(size: 18))
                                        .foregroundStyle(severityColor(issue.severity))
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(issue.title).font(.system(size: 12, weight: .semibold))
                                            Spacer()
                                            Text(categoryLabel(issue.category))
                                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(colors.textSecondary)
                                        }
                                        Text(issue.detail)
                                            .font(.system(size: 10))
                                            .foregroundStyle(colors.textSecondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .padding(14)
                                .background(colors.panelBg)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(colors.hairline.opacity(0.75), lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button(t("完成", "Done")) { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
        }
        .frame(width: 720, height: 650)
    }

    private var severitySummary: some View {
        HStack(spacing: 8) {
            ForEach(StoryboardIssueSeverity.allCases, id: \.rawValue) { severity in
                let count = issues.filter { $0.severity == severity }.count
                if count > 0 {
                    Label("\(count)", systemImage: severityIcon(severity))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(severityColor(severity))
                }
            }
        }
    }

    private func severityIcon(_ severity: StoryboardIssueSeverity) -> String {
        switch severity {
        case .information: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .severe: return "exclamationmark.octagon"
        case .blocking: return "xmark.octagon.fill"
        }
    }

    private func severityColor(_ severity: StoryboardIssueSeverity) -> Color {
        switch severity {
        case .information: return .blue
        case .warning: return .orange
        case .severe: return .red
        case .blocking: return .red
        }
    }

    private func categoryLabel(_ category: StoryboardIssueCategory) -> String {
        switch category {
        case .continuity: return t("连续性", "Continuity")
        case .timing: return t("节奏", "Timing")
        case .space: return t("空间", "Space")
        case .production: return t("拍摄", "Production")
        case .data: return t("数据", "Data")
        }
    }
}

struct StoryboardAnimaticView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @ObservedObject var store: StoryboardStore
    let scene: StoryboardScene

    @State private var playhead = 0.0
    @State private var isPlaying = false
    @State private var isExporting = false
    @State private var exportMessage: String?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var activeCueID: UUID?
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private func t(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: lang) }

    private var totalDuration: Double { scene.shots.reduce(0) { $0 + $1.durationSeconds } }
    private var current: (shot: StoryboardShot, progress: Double)? {
        var cursor = 0.0
        for shot in scene.shots {
            let end = cursor + shot.durationSeconds
            if playhead < end || shot.id == scene.shots.last?.id {
                return (shot, min(max((playhead - cursor) / shot.durationSeconds, 0), 1))
            }
            cursor = end
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("动态预演 · 场 \(scene.sceneNumber)", "Animatic · Scene \(scene.sceneNumber)"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(t("二维裁切、位移和缩放模拟结构化运镜", "Structured camera moves simulated with 2D crop, pan, and zoom."))
                        .font(.system(size: 10)).foregroundStyle(colors.textSecondary)
                }
                Spacer()
                if let exportMessage {
                    Text(exportMessage).font(.system(size: 10)).foregroundStyle(colors.textSecondary)
                }
                Button(action: exportVideo) {
                    Label(isExporting ? t("正在导出", "Exporting") : t("导出预演视频", "Export Animatic"), systemImage: "square.and.arrow.up")
                }
                .disabled(isExporting || scene.shots.isEmpty)
            }
            .padding(.horizontal, 20)
            .frame(height: 66)
            Divider()

            ZStack {
                Color.black
                if let current {
                    StoryboardFramePreview(
                        backgroundImage: store.image(for: current.shot.frame.assetID),
                        annotations: current.shot.annotations,
                        elements: current.shot.canvasElements ?? [],
                        annotationLayers: current.shot.annotationLayers ?? [],
                        layerOrder: current.shot.resolvedCanvasLayerOrder,
                        imageResolver: { store.image(for: $0) }
                    )
                    .scaleEffect(motionScale(current.shot, progress: current.progress))
                    .offset(motionOffset(current.shot, progress: current.progress))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipped()

                    VStack {
                        Spacer()
                        if let dialogue = current.shot.audioCues.first(where: { $0.kind == .dialogue })?.text,
                           !dialogue.isEmpty {
                            Text(dialogue)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                                .background(Color.black.opacity(0.68))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .padding(.bottom, 30)
                        }
                    }
                    VStack {
                        HStack {
                            (Text("\(current.shot.shotNumber) · ")
                                + Text(StoryboardMarkdownRendering.attributedString(from: current.shot.description)))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .padding(9)
                                .background(Color.black.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(16)
                } else {
                    Text(t("没有镜头", "No shots")).foregroundStyle(Color.white.opacity(0.6))
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .padding(24)
            .background(Color.black.opacity(0.9))

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        if playhead >= totalDuration { playhead = 0 }
                        isPlaying.toggle()
                        if !isPlaying { stopAudio() }
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .frame(width: 26)
                    }
                    Slider(value: $playhead, in: 0...max(totalDuration, 0.01))
                    Text("\(clock(playhead)) / \(clock(totalDuration))")
                        .font(.system(size: 10, design: .monospaced))
                        .frame(width: 98, alignment: .trailing)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(scene.shots) { shot in
                            Button {
                                playhead = startTime(of: shot.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(shot.shotNumber).font(.system(size: 9, weight: .bold, design: .monospaced))
                                    Text("\(String(format: "%.1f", shot.durationSeconds))s").font(.system(size: 8, design: .monospaced))
                                }
                                .foregroundStyle(current?.shot.id == shot.id ? Color.white : colors.textPrimary)
                                .padding(.horizontal, 9)
                                .frame(width: max(70, shot.durationSeconds * 30), height: 40, alignment: .leading)
                                .background(current?.shot.id == shot.id ? ToolAccent.storyboard.primary : colors.inputBg)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
            .background(colors.panelBg)

            Divider()
            HStack {
                Text(t("运镜、时长、对白和镜头顺序均读取当前结构化数据。", "Camera moves, durations, dialogue, and shot order all use the current structured data."))
                    .font(.system(size: 10)).foregroundStyle(colors.textSecondary)
                Spacer()
                Button(t("关闭", "Close")) { dismiss() }
            }
            .padding(.horizontal, 20)
            .frame(height: 54)
        }
        .frame(minWidth: 940, minHeight: 760)
        .onReceive(timer) { _ in
            guard isPlaying, totalDuration > 0 else { return }
            playhead += 0.05
            synchronizeAudio()
            if playhead >= totalDuration {
                playhead = totalDuration
                isPlaying = false
                stopAudio()
            }
        }
        .onDisappear(perform: stopAudio)
    }

    private func motionScale(_ shot: StoryboardShot, progress: Double) -> CGFloat {
        switch shot.cameraMotions.first?.kind ?? .locked {
        case .push, .dolly, .zoom: return 1 + CGFloat(progress) * 0.14
        case .pull: return 1.14 - CGFloat(progress) * 0.14
        default: return 1
        }
    }

    private func motionOffset(_ shot: StoryboardShot, progress: Double) -> CGSize {
        let value = CGFloat(progress - 0.5)
        switch shot.cameraMotions.first?.kind ?? .locked {
        case .pan, .truck, .follow: return CGSize(width: value * 100, height: 0)
        case .tilt, .crane, .rise: return CGSize(width: 0, height: value * 70)
        case .fall: return CGSize(width: 0, height: -value * 70)
        case .orbit: return CGSize(width: sin(CGFloat(progress) * .pi * 2) * 45, height: cos(CGFloat(progress) * .pi * 2) * 20)
        default: return .zero
        }
    }

    private func startTime(of shotID: UUID) -> Double {
        var value = 0.0
        for shot in scene.shots {
            if shot.id == shotID { return value }
            value += shot.durationSeconds
        }
        return value
    }

    private func clock(_ seconds: Double) -> String {
        String(format: "%02d:%05.2f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }

    private func synchronizeAudio() {
        guard let current else { stopAudio(); return }
        let localTime = max(0, playhead - startTime(of: current.shot.id))
        guard let cue = current.shot.audioCues.first(where: { cue in
            guard cue.assetID != nil else { return false }
            let duration = cue.durationSeconds > 0 ? cue.durationSeconds : current.shot.durationSeconds
            return localTime >= cue.startSeconds && localTime < cue.startSeconds + duration
        }), let url = store.assetURL(for: cue.assetID) else {
            stopAudio()
            return
        }
        let offset = max(0, localTime - cue.startSeconds)
        if activeCueID != cue.id {
            stopAudio()
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.currentTime = offset
                player.prepareToPlay()
                player.play()
                audioPlayer = player
                activeCueID = cue.id
            } catch {
                exportMessage = error.localizedDescription
            }
        } else if let audioPlayer, abs(audioPlayer.currentTime - offset) > 0.35 {
            audioPlayer.currentTime = offset
        }
    }

    private func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        activeCueID = nil
    }

    private func exportVideo() {
        let panel = NSSavePanel()
        panel.title = t("导出动态预演", "Export Animatic")
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(scene.sceneNumber)-animatic.mp4"
        guard panel.runModal() == .OK, let outputURL = panel.url else { return }
        guard let ffmpegURL = FFmpegLocator.executableURL(configuredPath: settings.settings.transcode.ffmpegPath) else {
            exportMessage = t("未找到 FFmpeg", "FFmpeg was not found")
            return
        }
        let imageMap: [UUID: NSImage?] = Dictionary(uniqueKeysWithValues: store.document.assets.map { ($0.id, store.image(for: $0.id)) })
        let audioPairs: [(UUID, URL)] = store.document.assets.compactMap { asset in
            guard asset.kind == .audio, let url = store.assetURL(for: asset.id) else { return nil }
            return (asset.id, url)
        }
        let audioMap: [UUID: URL] = Dictionary(uniqueKeysWithValues: audioPairs)
        isExporting = true
        exportMessage = nil
        Task.detached(priority: .userInitiated) {
            do {
                try StoryboardAnimaticExporter.export(
                    scene: scene,
                    to: outputURL,
                    ffmpegURL: ffmpegURL,
                    imageResolver: { id in id.flatMap { imageMap[$0] ?? nil } },
                    audioResolver: { id in id.flatMap { audioMap[$0] } }
                )
                await MainActor.run {
                    isExporting = false
                    exportMessage = t("已导出 \(outputURL.lastPathComponent)", "Exported \(outputURL.lastPathComponent)")
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportMessage = error.localizedDescription
                }
            }
        }
    }
}

struct StoryboardExportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var store: StoryboardStore
    @State private var message: String?

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private func t(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: lang) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("镜头表与后期交付", "Shot List and Post Handoff"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(t("同一份结构化数据输出至拍摄和剪辑流程", "The same structured data exports to production planning and editorial workflows."))
                        .font(.system(size: 10)).foregroundStyle(colors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 66)
            Divider()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                exportCard(.csv, title: t("CSV 镜头表", "CSV Shot List"), detail: t("拍摄统筹、制片与表格处理", "Planning, production, and spreadsheets"))
                exportCard(.json, title: t("JSON 完整数据", "Complete JSON Data"), detail: t("自动化、归档与系统联动", "Automation, archive, and system integration"))
                exportCard(.fcpxml, title: "Final Cut Pro XML", detail: t("以分镜时长建立占位时间线", "Placeholder timeline built from storyboard durations"))
                exportCard(.resolveXML, title: "DaVinci Resolve XML", detail: t("传统 xmeml 时间线交换", "Classic xmeml timeline interchange"))
                exportCard(.edl, title: "EDL", detail: t("25fps 非丢帧镜头顺序", "25 fps non-drop-frame shot order"))
                exportCard(.otio, title: "OpenTimelineIO", detail: t("开放时间线与镜头元数据", "Open timeline and shot metadata"))
                exportCard(.contactSheet, title: "Contact Sheet", detail: t("三列高清分镜联络表 PNG", "Three-column high-resolution storyboard contact sheet PNG"))
            }
            .padding(20)
            .frame(maxHeight: .infinity, alignment: .top)

            Divider()
            HStack {
                Text(message ?? t("导出不会修改项目数据。", "Exporting does not modify project data."))
                    .font(.system(size: 10)).foregroundStyle(colors.textSecondary)
                Spacer()
                Button(t("完成", "Done")) { dismiss() }
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
        }
        .frame(width: 720, height: 560)
    }

    private func exportCard(_ format: StoryboardExportFormat, title: String, detail: String) -> some View {
        Button { export(format) } label: {
            HStack(spacing: 12) {
                Image(systemName: exportIcon(format))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(ToolAccent.storyboard.primary)
                    .frame(width: 38, height: 38)
                    .background(ToolAccent.storyboard.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(detail).font(.system(size: 9)).foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up").foregroundStyle(colors.textSecondary)
            }
            .padding(13)
            .background(colors.panelBg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(colors.hairline.opacity(0.75), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private func export(_ format: StoryboardExportFormat) {
        let panel = NSSavePanel()
        panel.title = t("导出 \(format.rawValue)", "Export \(format.rawValue)")
        panel.nameFieldStringValue = "\(store.document.title).\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try StoryboardExporter.write(
                document: store.document,
                format: format,
                to: url,
                imageResolver: { store.image(for: $0) }
            )
            message = t("已导出 \(url.lastPathComponent)", "Exported \(url.lastPathComponent)")
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            message = error.localizedDescription
        }
    }

    private func exportIcon(_ format: StoryboardExportFormat) -> String {
        switch format {
        case .csv: return "tablecells"
        case .json: return "curlybraces"
        case .fcpxml: return "f.square"
        case .resolveXML: return "play.rectangle"
        case .edl: return "list.number"
        case .otio: return "timeline.selection"
        case .contactSheet: return "rectangle.grid.3x2"
        }
    }
}
