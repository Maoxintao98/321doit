import AppKit
import SwiftUI

struct LinkedClipsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @ObservedObject var store: ScriptLogStore

    @State private var manualFileName = ""
    @State private var manualFilePath = ""
    @State private var manualCameraCard = ""
    @State private var manualChecksum = ""

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private var clips: [ClipReference] { store.currentTake?.linkedClips ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    futureMatchPanel
                    manualBindPanel
                    clipList
                }
                .padding(.bottom, 18)
            }
        }
        .padding(14)
        .background(colors.panelBg)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("关联素材", "Linked Clips", language: lang))
                    .font(.system(size: 14, weight: .semibold))
                Text("\(clips.count) \(L10n.t("个素材", "clip(s)", language: lang))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            Button(action: store.bindClipFiles) {
                Image(systemName: "paperclip")
            }
            .disabled(store.currentTake == nil)
            .help(L10n.t("手动绑定素材文件", "Bind clip files manually", language: lang))
        }
    }

    private var futureMatchPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L10n.t("自动匹配入口预留", "Auto-match Reserved", language: lang), systemImage: "wand.and.stars")
                .font(.system(size: 11, weight: .semibold))
            Text(L10n.t(
                "后续可基于 DIT 下盘结果、卡号、文件名、checksum、timecode 匹配素材。当前 MVP 不执行自动匹配。",
                "Future versions can match against offload results, card labels, file names, checksums and timecode. The MVP does not run matching yet.",
                language: lang
            ))
            .font(.system(size: 10))
            .foregroundStyle(colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(colors.inputBg)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var manualBindPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(L10n.t("手动素材记录", "Manual Clip", language: lang), systemImage: "plus.square")
                .font(.system(size: 11, weight: .semibold))

            TextField(L10n.t("文件名", "File Name", language: lang), text: $manualFileName)
                .textFieldStyle(.roundedBorder)
            TextField(L10n.t("文件路径", "File Path", language: lang), text: $manualFilePath)
                .textFieldStyle(.roundedBorder)
            HStack {
                TextField(L10n.t("卡号", "Card ID", language: lang), text: $manualCameraCard)
                    .textFieldStyle(.roundedBorder)
                TextField("Checksum", text: $manualChecksum)
                    .textFieldStyle(.roundedBorder)
            }
            Button {
                addManualClip()
            } label: {
                Label(L10n.t("加入当前条次", "Add to Current Take", language: lang), systemImage: "plus")
            }
            .disabled(store.currentTake == nil || manualFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(colors.surfaceBg)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(colors.hairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var clipList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(L10n.t("已绑定素材", "Bound Clips", language: lang), systemImage: "link")
                .font(.system(size: 11, weight: .semibold))

            if clips.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "film")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(colors.textSecondary)
                    Text(L10n.t("当前 Take 尚未绑定素材", "No clips linked to this Take", language: lang))
                        .font(.system(size: 11))
                        .foregroundStyle(colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(colors.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                ForEach(clips) { clip in
                    clipCard(clip)
                }
            }
        }
    }

    private func clipCard(_ clip: ClipReference) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "film")
                    .foregroundStyle(colors.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(clip.fileName.isEmpty ? L10n.t("未命名素材", "Untitled clip", language: lang) : clip.fileName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(clip.filePath)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button {
                    reveal(clip)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                }
                .disabled(clip.filePath.isEmpty)
                Button(role: .destructive) {
                    store.removeClipReference(id: clip.id)
                } label: {
                    Image(systemName: "trash")
                }
            }

            TextField(L10n.t("卡号", "Card ID", language: lang), text: Binding(
                get: { clip.cameraCard },
                set: { value in store.updateClipReference(id: clip.id) { $0.cameraCard = value } }
            ))
            .textFieldStyle(.roundedBorder)
            TextField("Checksum", text: Binding(
                get: { clip.checksum },
                set: { value in store.updateClipReference(id: clip.id) { $0.checksum = value } }
            ))
            .textFieldStyle(.roundedBorder)
            TextField(L10n.t("代理路径", "Proxy Path", language: lang), text: Binding(
                get: { clip.proxyPath },
                set: { value in store.updateClipReference(id: clip.id) { $0.proxyPath = value } }
            ))
            .textFieldStyle(.roundedBorder)
            TextField(L10n.t("下盘 sessionId", "Offload Session ID", language: lang), text: Binding(
                get: { clip.offloadSessionId },
                set: { value in store.updateClipReference(id: clip.id) { $0.offloadSessionId = value } }
            ))
            .textFieldStyle(.roundedBorder)
        }
        .padding(10)
        .background(colors.inputBg)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func addManualClip() {
        store.addClipReference(
            ClipReference(
                fileName: manualFileName.trimmingCharacters(in: .whitespacesAndNewlines),
                filePath: manualFilePath.trimmingCharacters(in: .whitespacesAndNewlines),
                cameraCard: manualCameraCard.trimmingCharacters(in: .whitespacesAndNewlines),
                checksum: manualChecksum.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
        manualFileName = ""
        manualFilePath = ""
        manualCameraCard = ""
        manualChecksum = ""
    }

    private func reveal(_ clip: ClipReference) {
        let url = URL(fileURLWithPath: clip.filePath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
