import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct StoryboardSoundEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var store: StoryboardStore
    let sceneID: UUID
    let shot: StoryboardShot

    @State private var draft: StoryboardShot
    @State private var importKind: StoryboardAudioCueKind = .dialogue
    @State private var player: AVAudioPlayer?
    @State private var playingCueID: UUID?

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private func t(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: lang) }

    init(store: StoryboardStore, sceneID: UUID, shot: StoryboardShot) {
        self.store = store
        self.sceneID = sceneID
        self.shot = shot
        _draft = State(initialValue: shot)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("声音设计 · \(shot.shotNumber)", "Sound Design · \(shot.shotNumber)"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(t("对白、旁白、环境、音效和临时音乐会随预演与 MP4 导出", "Dialogue, narration, ambience, effects, and temporary music accompany animatic and MP4 exports."))
                        .font(.system(size: 10))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Picker(t("导入类型", "Import Type"), selection: $importKind) {
                    ForEach(StoryboardAudioCueKind.allCases) { kind in
                        Text(label(kind)).tag(kind)
                    }
                }
                .frame(width: 150)
                Button(action: importAudio) {
                    Label(t("导入声音", "Import Audio"), systemImage: "waveform.badge.plus")
                }
                Button(action: addTextCue) {
                    Label(t("文字提示", "Text Cue"), systemImage: "text.badge.plus")
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 72)
            Divider()

            if draft.audioCues.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(ToolAccent.storyboard.primary)
                    Text(t("还没有声音条目", "No sound cues yet")).font(.system(size: 15, weight: .semibold))
                    Text(t("可只写对白/音效提示，也可导入临时音频进行预演。", "Add dialogue or sound-effect notes, or import temporary audio for the animatic."))
                        .font(.system(size: 10)).foregroundStyle(colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(draft.audioCues.enumerated()), id: \.element.id) { index, cue in
                            cueRow(index: index, cue: cue)
                        }
                    }
                    .padding(18)
                }
            }

            Divider()
            HStack {
                Text(t("声音文件复制到项目内；删除条目不会影响源文件。", "Audio files are copied into the project; deleting a cue never affects the source file."))
                    .font(.system(size: 10)).foregroundStyle(colors.textSecondary)
                Spacer()
                Button(t("取消", "Cancel")) { dismiss() }
                Button(t("保存", "Save")) {
                    stopPlayback()
                    if store.perform(title: t("修改镜头声音", "Edit Shot Sound"), mutations: [
                        .updateShot(sceneID: sceneID, shotID: draft.id, shot: draft)
                    ]) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
        }
        .frame(minWidth: 860, minHeight: 600)
        .onDisappear(perform: stopPlayback)
    }

    private func cueRow(index: Int, cue: StoryboardAudioCue) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Picker("", selection: $draft.audioCues[index].kind) {
                    ForEach(StoryboardAudioCueKind.allCases) { kind in
                        Text(label(kind)).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 112)

                TextField(cue.kind == .dialogue ? t("对白 / 旁白内容", "Dialogue / narration") : t("声音说明", "Sound description"), text: $draft.audioCues[index].text)
                    .textFieldStyle(.roundedBorder)

                if cue.assetID != nil {
                    Button {
                        togglePlayback(cue)
                    } label: {
                        Image(systemName: playingCueID == cue.id ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(t("试听临时音频", "Preview temporary audio"))
                }

                Button(role: .destructive) {
                    if playingCueID == cue.id { stopPlayback() }
                    draft.audioCues.remove(at: index)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }

            HStack(spacing: 14) {
                field(t("镜头内起点", "Start in Shot"), value: $draft.audioCues[index].startSeconds, range: 0...max(draft.durationSeconds, 0.1))
                field(t("使用时长", "Duration"), value: $draft.audioCues[index].durationSeconds, range: 0...max(draft.durationSeconds, 0.1))
                Spacer()
                if let assetID = cue.assetID,
                   let asset = store.document.assets.first(where: { $0.id == assetID }) {
                    Label(asset.name, systemImage: "waveform")
                        .font(.system(size: 9))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                } else {
                    Text(t("仅文字提示", "Text cue only"))
                        .font(.system(size: 9)).foregroundStyle(colors.textTertiary)
                }
            }
        }
        .padding(14)
        .background(colors.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(colors.hairline.opacity(0.8), lineWidth: 0.8))
    }

    private func field(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 7) {
            Text(title).font(.system(size: 9)).foregroundStyle(colors.textSecondary)
            TextField("0.0", value: value, format: .number.precision(.fractionLength(1)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
            Stepper("", value: value, in: range, step: 0.1)
                .labelsHidden()
        }
    }

    private func importAudio() {
        let panel = NSOpenPanel()
        panel.title = t("导入临时声音", "Import Temporary Audio")
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if store.importAudio(from: url, cueKind: importKind, sceneID: sceneID, shot: draft),
           let updated = store.document.scene(id: sceneID)?.shots.first(where: { $0.id == draft.id }) {
            draft = updated
        }
    }

    private func addTextCue() {
        draft.audioCues.append(StoryboardAudioCue(
            kind: importKind,
            text: "",
            startSeconds: 0,
            durationSeconds: min(2, max(draft.durationSeconds, 0.1))
        ))
    }

    private func togglePlayback(_ cue: StoryboardAudioCue) {
        if playingCueID == cue.id { stopPlayback(); return }
        stopPlayback()
        guard let url = store.assetURL(for: cue.assetID) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.currentTime = 0
            player.prepareToPlay()
            player.play()
            self.player = player
            playingCueID = cue.id
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        playingCueID = nil
    }

    private func label(_ kind: StoryboardAudioCueKind) -> String {
        switch kind {
        case .dialogue: return t("对白 / 旁白", "Dialogue / Narration")
        case .music: return t("临时音乐", "Temporary Music")
        case .soundEffect: return t("音效", "Sound Effect")
        case .ambience: return t("环境声", "Ambience")
        }
    }
}
