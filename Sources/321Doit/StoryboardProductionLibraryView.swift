import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum StoryboardLibrarySection: String, CaseIterable, Identifiable {
    case script
    case characters
    case props
    case locations
    case references

    var id: String { rawValue }
}

struct StoryboardProductionLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var store: StoryboardStore

    @State private var section: StoryboardLibrarySection = .characters
    @State private var draft: StoryboardProductionData

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private func t(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: lang) }

    init(store: StoryboardStore) {
        self.store = store
        _draft = State(initialValue: store.document.production ?? StoryboardProductionData())
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("项目资料库", "Production Library")).font(.system(size: 16, weight: .semibold))
                    Text(t("剧本、角色、道具、场景与视觉参考统一进入结构化项目数据", "Scripts, characters, props, locations, and visual references live in structured project data."))
                        .font(.system(size: 10)).foregroundStyle(colors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(height: 70)
            Divider()

            HStack(spacing: 0) {
                List(StoryboardLibrarySection.allCases, selection: $section) { item in
                    Label(label(item), systemImage: icon(item)).tag(item)
                }
                .listStyle(.sidebar)
                .frame(width: 180)
                Divider()
                content
            }

            Divider()
            HStack {
                Text(t("参考图只存项目内副本，不会覆盖原始文件。", "Reference images are copied into the project and never overwrite their source files."))
                    .font(.system(size: 10)).foregroundStyle(colors.textSecondary)
                Spacer()
                Button(t("取消", "Cancel")) { dismiss() }
                Button(t("保存资料库", "Save Library")) {
                    if store.perform(title: t("更新项目资料库", "Update Production Library"), mutations: [.updateProduction(draft)]) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .frame(height: 58)
        }
        .frame(minWidth: 980, minHeight: 700)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .script: scriptSection
        case .characters: characterSection
        case .props: propSection
        case .locations: locationSection
        case .references: referenceSection
        }
    }

    private var scriptSection: some View {
        VStack(spacing: 14) {
            HStack {
                TextField(t("剧本标题", "Script Title"), text: Binding(
                    get: { draft.script?.title ?? "" },
                    set: { ensureScript(); draft.script?.title = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                Button(action: importScript) { Label(t("导入 TXT / Fountain", "Import TXT / Fountain"), systemImage: "doc.badge.plus") }
            }
            TextEditor(text: Binding(
                get: { draft.script?.text ?? "" },
                set: { ensureScript(); draft.script?.text = $0 }
            ))
            .font(.system(size: 12, design: .monospaced))
            .padding(10)
            .background(colors.inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            if let source = draft.script?.sourcePath {
                Text(t("来源：\(source)", "Source: \(source)")).font(.system(size: 9)).foregroundStyle(colors.textTertiary).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
    }

    private var characterSection: some View {
        entityList(
            addTitle: t("新增角色", "Add Character"),
            add: { draft.characters.append(StoryboardCharacter(name: t("新角色", "New Character"))) }
        ) {
            ForEach(Array(draft.characters.indices), id: \.self) { index in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        TextField(t("角色名", "Character Name"), text: $draft.characters[index].name).font(.system(size: 13, weight: .semibold))
                        referenceButton { importReference { draft.characters[index].referenceAssetIDs.append($0) } }
                        deleteButton { draft.characters.remove(at: index) }
                    }
                    TextField(t("外形、服装、年龄与辨识特征", "Appearance, wardrobe, age, and identifying features"), text: $draft.characters[index].visualDescription)
                    TextField(t("导演备注与连续性要求", "Director notes and continuity requirements"), text: $draft.characters[index].directorNote)
                    referenceStrip(ids: draft.characters[index].referenceAssetIDs)
                }
                .entityCard(colors: colors)
            }
        }
    }

    private var propSection: some View {
        entityList(addTitle: t("新增道具", "Add Prop"), add: { draft.props.append(StoryboardProp(name: t("新道具", "New Prop"))) }) {
            ForEach(Array(draft.props.indices), id: \.self) { index in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        TextField(t("道具名", "Prop Name"), text: $draft.props[index].name).font(.system(size: 13, weight: .semibold))
                        referenceButton { importReference { draft.props[index].referenceAssetIDs.append($0) } }
                        deleteButton { draft.props.remove(at: index) }
                    }
                    TextField(t("连续性、状态变化和特殊要求", "Continuity, state changes, and special requirements"), text: $draft.props[index].continuityNote)
                    referenceStrip(ids: draft.props[index].referenceAssetIDs)
                }
                .entityCard(colors: colors)
            }
        }
    }

    private var locationSection: some View {
        entityList(addTitle: t("新增场景", "Add Location"), add: { draft.locations.append(StoryboardLocation(name: t("新场景", "New Location"))) }) {
            ForEach(Array(draft.locations.indices), id: \.self) { index in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        TextField(t("场景名", "Location Name"), text: $draft.locations[index].name).font(.system(size: 13, weight: .semibold))
                        referenceButton { importReference { draft.locations[index].referenceAssetIDs.append($0) } }
                        deleteButton { draft.locations.remove(at: index) }
                    }
                    TextField(t("空间、光线、材质和氛围", "Space, lighting, materials, and atmosphere"), text: $draft.locations[index].description)
                    TextField(t("尺寸、出入口与机位限制", "Dimensions, access, and camera-position limits"), text: $draft.locations[index].dimensionsNote)
                    referenceStrip(ids: draft.locations[index].referenceAssetIDs)
                }
                .entityCard(colors: colors)
            }
        }
    }

    private var referenceSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text(t("视觉参考", "Visual References")).font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { importReference { _ in } } label: { Label(t("导入参考图", "Import Reference Image"), systemImage: "photo.badge.plus") }
            }
            .padding(.horizontal, 20).frame(height: 54)
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                    ForEach(referenceAssets) { asset in
                        VStack(alignment: .leading, spacing: 8) {
                            Group {
                                if let image = store.image(for: asset.id) {
                                    Image(nsImage: image).resizable().scaledToFill()
                                } else {
                                    Color.gray.opacity(0.12).overlay(Image(systemName: "photo"))
                                }
                            }
                            .frame(height: 120).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(asset.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                            Text(t("\(asset.versions.count) 个版本", "\(asset.versions.count) versions"))
                                .font(.system(size: 8)).foregroundStyle(colors.textTertiary)
                        }
                        .padding(10)
                        .background(colors.panelBg)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                    }
                }
                .padding(18)
            }
        }
    }

    private func entityList<Rows: View>(addTitle: String, add: @escaping () -> Void, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label(section)).font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: add) { Label(addTitle, systemImage: "plus") }
            }
            .padding(.horizontal, 20).frame(height: 54)
            Divider()
            ScrollView {
                LazyVStack(spacing: 12) { rows() }.padding(18)
            }
        }
    }

    private func referenceStrip(ids: [UUID]) -> some View {
        HStack(spacing: 6) {
            ForEach(ids.prefix(6), id: \.self) { id in
                if let image = store.image(for: id) {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: 48, height: 34).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            if ids.isEmpty { Text(t("无参考图", "No reference images")).font(.system(size: 8)).foregroundStyle(colors.textTertiary) }
        }
    }

    private func referenceButton(action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "photo.badge.plus") }.buttonStyle(.borderless).help(t("添加参考图", "Add reference image"))
    }

    private func deleteButton(action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) { Image(systemName: "trash") }.buttonStyle(.borderless)
    }

    private var referenceAssets: [StoryboardAsset] {
        store.document.assets.filter { $0.kind == .reference }
    }

    private func importReference(attach: (UUID) -> Void) {
        let panel = NSOpenPanel()
        panel.title = t("导入视觉参考", "Import Visual Reference")
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let id = store.importReferenceImage(from: url) else { return }
        attach(id)
    }

    private func importScript() {
        let panel = NSOpenPanel()
        panel.title = t("导入剧本", "Import Script")
        panel.allowedContentTypes = [.plainText, UTType(filenameExtension: "fountain") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        draft.script = StoryboardScript(
            title: url.deletingPathExtension().lastPathComponent,
            text: text,
            sourcePath: url.path
        )
    }

    private func ensureScript() {
        if draft.script == nil { draft.script = StoryboardScript(title: t("未命名剧本", "Untitled Script"), text: "") }
    }

    private func label(_ item: StoryboardLibrarySection) -> String {
        switch item {
        case .script: return t("剧本", "Script")
        case .characters: return t("角色", "Characters")
        case .props: return t("道具", "Props")
        case .locations: return t("场景", "Locations")
        case .references: return t("视觉参考", "Visual References")
        }
    }

    private func icon(_ item: StoryboardLibrarySection) -> String {
        switch item {
        case .script: return "doc.text"
        case .characters: return "person.2"
        case .props: return "shippingbox"
        case .locations: return "building.2"
        case .references: return "photo.stack"
        }
    }
}

private extension View {
    func entityCard(colors: ThemeColors) -> some View {
        padding(14)
            .background(colors.panelBg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(colors.hairline.opacity(0.8), lineWidth: 0.8))
    }
}
