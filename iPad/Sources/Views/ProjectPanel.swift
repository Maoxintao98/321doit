import SwiftUI

/// Project configuration page: project name, language, and the camera/card setup
/// that drives clip-number auto-fill in the script log.
struct ProjectPanel: View {
    @EnvironmentObject private var store: ScripterStore
    @Environment(\.palette) private var palette
    private var lang: AppLanguage { store.language }

    var body: some View {
            Form {
                Section(L10n.t("项目", "Project", language: lang)) {
                    TextField(L10n.t("项目名称", "Project name", language: lang), text: Binding(
                        get: { store.projectName },
                        set: { store.projectName = $0; store.save() }))
                }

                Section {
                    Picker(L10n.t("语言", "Language", language: lang), selection: Binding(
                        get: { store.language },
                        set: { store.language = $0; store.relocalizeDefaultCameraNames(); store.save() }
                    )) {
                        Text(L10n.t("跟随系统", "System", language: lang)).tag(AppLanguage.system)
                        Text("中文").tag(AppLanguage.zh)
                        Text("English").tag(AppLanguage.en)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(L10n.t("语言", "Language", language: lang))
                }

                Section {
                    ForEach(store.cameras) { cam in
                        CameraRow(camera: cam)
                    }
                    Button {
                        store.addCamera()
                    } label: {
                        Label(L10n.t("添加机位", "Add Camera", language: lang), systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text(L10n.t("机位与卡", "Cameras & Cards", language: lang))
                } footer: {
                    Text(L10n.t(
                        "每个机位配置当前卡号与起始素材号。新建 Take 会按各机位自动 +1 生成素材号，可在场记里手动修改。",
                        "Each camera has a current card and a starting clip number. New takes auto-increment each camera's clip; you can edit it in the script log.",
                        language: lang))
                }

                Section {
                    LabeledContent(L10n.t("拍摄日", "Shooting Days", language: lang),
                                   value: "\(store.days.count)")
                    LabeledContent(L10n.t("Take 总数", "Total Takes", language: lang),
                                   value: "\(store.totalTakeCount)")
                    LabeledContent(L10n.t("版本", "Version", language: lang), value: AppInfo.version)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct CameraRow: View {
    @EnvironmentObject private var store: ScripterStore
    let camera: ScripterCamera
    private var lang: AppLanguage { store.language }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(L10n.t("机位名", "Camera", language: lang), text: Binding(
                    get: { camera.label },
                    set: { v in store.updateCamera(camera.id) { $0.label = v } }))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if store.cameras.count > 1 {
                    Button(role: .destructive) {
                        store.deleteCamera(camera.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack(spacing: 10) {
                labeledField(L10n.t("卡号", "Card", language: lang), text: Binding(
                    get: { camera.cardName },
                    set: { v in store.updateCamera(camera.id) { $0.cardName = v } }))
                labeledField(L10n.t("起始素材号", "Start Clip", language: lang), text: Binding(
                    get: { camera.startClip },
                    set: { v in store.updateCamera(camera.id) { $0.startClip = v } }))
            }
        }
        .padding(.vertical, 4)
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.roundedBorder)
        }
    }
}
