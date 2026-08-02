import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum ScriptWorkshopMode: String, CaseIterable, Identifiable {
    case page
    case cards
    case outline
    case dialogue

    var id: String { rawValue }
}

private struct ScriptWorkshopPendingCharacterCreation: Equatable {
    var sceneID: UUID
    var blockID: UUID
}

private enum ScriptWorkshopWheelResolvedSelection: Equatable {
    case element(ScriptWorkshopBlockKind)
    case character(ScriptWorkshopWheelCharacterChoice)
}

struct ScriptWorkshopView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: ScriptWorkshopStore
    @StateObject private var wheelCoordinates = ScriptWorkshopWheelCoordinateConverter()

    @State private var mode: ScriptWorkshopMode = .page
    @State private var scenePendingDeletion: UUID?
    @State private var snapshotConfirmation = false
    @State private var creationWheel: ScriptWorkshopWheelOverlayState?
    @State private var pendingCharacterCreation: ScriptWorkshopPendingCharacterCreation?
    @State private var newCharacterName = ""
    @State private var searchQuery = ""
    @State private var searchIsPresented = false
    @FocusState private var searchIsFocused: Bool
    @State private var newRevisionIsPresented = false
    @State private var newRevisionName = ""
    @State private var exportNotice: String?
    @State private var dialogueCharacter = ""
    @State private var sceneTagsDraft = ""
    @State private var analysisIsExpanded = false
    @State private var workshopSize: CGSize = .zero
    @State private var sceneSidebarIsVisible = true
    @State private var inspectorSidebarIsVisible = true

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private var accent: ToolAccent { .scriptWorkshop }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ScriptWorkshopWheelCoordinateReader(converter: wheelCoordinates)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    toolbar
                    Divider()
                    HStack(spacing: 0) {
                        if sceneSidebarIsVisible {
                            sceneNavigator
                                .frame(width: 238)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            Divider()
                        }
                        Group {
                            switch mode {
                            case .page:
                                pageWorkspace
                            case .cards:
                                cardsWorkspace
                            case .outline:
                                outlineWorkspace
                            case .dialogue:
                                dialogueWorkspace
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if inspectorSidebarIsVisible {
                            Divider()
                            inspector
                                .frame(width: 276)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }

                if let creationWheel {
                    ScriptWorkshopCreationWheel(
                        highlightedKind: creationWheel.highlightedKind,
                        characterChoices: wheelCharacterChoices,
                        showsCharacterRing: creationWheel.showsCharacterRing,
                        highlightedCharacterID: creationWheel.highlightedCharacterID,
                        language: lang
                    )
                    .frame(width: 500, height: 500)
                    .position(creationWheel.origin)
                    .transition(creationWheelTransition)
                    .zIndex(20)
                }
            }
            .onAppear {
                workshopSize = geometry.size
            }
            .onChange(of: geometry.size) { workshopSize = $0 }
        }
        .background(colors.surfaceBg)
        .onAppear {
            if store.selectedSceneID == nil {
                store.selectedSceneID = store.document.scenes.first?.id
            }
            dialogueCharacter = store.document.allCharacters.first ?? ""
            syncSceneTagsDraft()
        }
        .onChange(of: store.selectedSceneID) { _ in syncSceneTagsDraft() }
        .onDisappear { store.flushPendingSave() }
        .alert(
            L10n.t("剧本工坊", "Script Workshop", language: lang),
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert(
            L10n.t("交付提示", "Delivery Note", language: lang),
            isPresented: Binding(
                get: { exportNotice != nil },
                set: { if !$0 { exportNotice = nil } }
            )
        ) {
            Button("OK", role: .cancel) { exportNotice = nil }
        } message: {
            Text(exportNotice ?? "")
        }
        .alert(
            L10n.t("新增人物", "New Character", language: lang),
            isPresented: Binding(
                get: { pendingCharacterCreation != nil },
                set: {
                    if !$0 {
                        pendingCharacterCreation = nil
                        newCharacterName = ""
                    }
                }
            )
        ) {
            TextField(
                L10n.t("人物姓名", "Character name", language: lang),
                text: $newCharacterName
            )
            Button(L10n.t("创建并插入", "Create & Insert", language: lang)) {
                commitNewWheelCharacter()
            }
            .disabled(newCharacterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(L10n.t("取消", "Cancel", language: lang), role: .cancel) {
                pendingCharacterCreation = nil
                newCharacterName = ""
            }
        } message: {
            Text(L10n.t(
                "人物会加入当前项目的人物库，并插入为人物提示。",
                "The character will be added to this project and inserted as a character cue.",
                language: lang
            ))
        }
        .confirmationDialog(
            L10n.t("删除这个场景？", "Delete this scene?", language: lang),
            isPresented: Binding(
                get: { scenePendingDeletion != nil },
                set: { if !$0 { scenePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.t("删除场景", "Delete Scene", language: lang), role: .destructive) {
                if let scenePendingDeletion {
                    store.deleteScene(scenePendingDeletion)
                }
                scenePendingDeletion = nil
            }
            Button(L10n.t("取消", "Cancel", language: lang), role: .cancel) {}
        } message: {
            Text(L10n.t(
                "场景和其中的正文会从当前剧本中删除。你可以先创建一个版本快照。",
                "The scene and its text will be removed from the current script. You can create a version snapshot first.",
                language: lang
            ))
        }
    }

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField(
                    L10n.t("剧本名称", "Script Title", language: lang),
                    text: Binding(
                        get: { store.document.title },
                        set: store.updateTitle
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 250)
                .accessibilityIdentifier("scriptWorkshop.title")

                saveState

                HStack(spacing: 2) {
                    Button(action: store.undo) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!store.canUndo)
                    .help(L10n.t("撤销", "Undo", language: lang))
                    .keyboardShortcut("z", modifiers: .command)

                    Button(action: store.redo) {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!store.canRedo)
                    .help(L10n.t("重做", "Redo", language: lang))
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                }
                .buttonStyle(.borderless)

                HStack(spacing: 6) {
                    Button {
                        searchIsFocused = true
                        searchIsPresented = !searchQuery.isEmpty
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("f", modifiers: .command)
                    .help(L10n.t("全局搜索", "Search screenplay", language: lang))

                    TextField(
                        L10n.t("搜索人物、场景、对白", "Search scenes, characters, dialogue", language: lang),
                        text: $searchQuery
                    )
                    .textFieldStyle(.plain)
                    .focused($searchIsFocused)
                    .onSubmit {
                        if let first = searchResults.first {
                            focusSearchResult(first)
                        }
                    }

                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                            searchIsPresented = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .frame(width: 238, height: 28)
                .background(colors.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(searchIsFocused ? accent.primary.opacity(0.55) : colors.hairline, lineWidth: 1)
                )
                .onChange(of: searchQuery) { value in
                    searchIsPresented = !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                .popover(isPresented: $searchIsPresented, arrowEdge: .top) {
                    searchResultsPopover
                }

                Spacer(minLength: 10)

                Menu {
                    Button {
                        store.setActiveRevision(nil)
                    } label: {
                        Label(
                            L10n.t("暂停修订标记", "Pause Revision Marking", language: lang),
                            systemImage: store.activeRevisionSet == nil ? "checkmark" : "circle"
                        )
                    }

                    if let revisions = store.document.workspace?.revisionSets, !revisions.isEmpty {
                        Divider()
                        ForEach(revisions) { revision in
                            Button {
                                store.setActiveRevision(revision.id)
                            } label: {
                                Label(
                                    revision.name,
                                    systemImage: store.activeRevisionSet?.id == revision.id ? "checkmark.circle.fill" : "circle.fill"
                                )
                            }
                        }
                    }

                    Divider()
                    Button {
                        newRevisionName = suggestedRevisionName
                        newRevisionIsPresented = true
                    } label: {
                        Label(L10n.t("新建修订集…", "New Revision Set…", language: lang), systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(activeRevisionColor)
                            .frame(width: 8, height: 8)
                        Text(store.activeRevisionSet?.name ?? L10n.t("未开启修订", "Revisions Off", language: lang))
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(colors.inputBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .popover(isPresented: $newRevisionIsPresented, arrowEdge: .top) {
                    newRevisionPopover
                }

                Button {
                    store.addScene(after: store.selectedSceneID)
                } label: {
                    Label(L10n.t("新场景", "New Scene", language: lang), systemImage: "plus")
                }
                .accessibilityIdentifier("scriptWorkshop.addScene")

                HStack(spacing: 2) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            sceneSidebarIsVisible.toggle()
                        }
                    } label: {
                        Image(systemName: sceneSidebarIsVisible ? "sidebar.left" : "sidebar.leading")
                    }
                    .help(L10n.t(
                        sceneSidebarIsVisible ? "隐藏场景侧栏" : "显示场景侧栏",
                        sceneSidebarIsVisible ? "Hide Scene Sidebar" : "Show Scene Sidebar",
                        language: lang
                    ))
                    .accessibilityIdentifier("scriptWorkshop.toggleSceneSidebar")

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            inspectorSidebarIsVisible.toggle()
                        }
                    } label: {
                        Image(systemName: inspectorSidebarIsVisible ? "sidebar.right" : "sidebar.trailing")
                    }
                    .help(L10n.t(
                        inspectorSidebarIsVisible ? "隐藏资料侧栏" : "显示资料侧栏",
                        inspectorSidebarIsVisible ? "Hide Inspector Sidebar" : "Show Inspector Sidebar",
                        language: lang
                    ))
                    .accessibilityIdentifier("scriptWorkshop.toggleInspectorSidebar")
                }
                .buttonStyle(.borderless)

                deliveryMenu
            }
            .padding(.horizontal, 16)
            .frame(height: 46)

            Divider().opacity(0.6)

            HStack(spacing: 12) {
                Picker("", selection: $mode) {
                    Label(L10n.t("写作", "Write", language: lang), systemImage: "doc.text")
                        .tag(ScriptWorkshopMode.page)
                    Label(L10n.t("场景卡", "Cards", language: lang), systemImage: "rectangle.grid.2x2")
                        .tag(ScriptWorkshopMode.cards)
                    Label(L10n.t("大纲", "Outline", language: lang), systemImage: "point.3.connected.trianglepath.dotted")
                        .tag(ScriptWorkshopMode.outline)
                    Label(L10n.t("对白", "Dialogue", language: lang), systemImage: "quote.bubble")
                        .tag(ScriptWorkshopMode.dialogue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 400)

                Label(
                    L10n.t("长按 Tab 召唤创作轮", "Hold Tab for the Creation Wheel", language: lang),
                    systemImage: "circle.hexagongrid.fill"
                )
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accent.primary)
                .help(L10n.t(
                    "短按 Tab 切换当前段落类型；长按 Tab，指向剧本元素后松开。",
                    "Tap Tab to cycle the current element. Hold Tab, point, then release.",
                    language: lang
                ))

                Spacer()

                Text(L10n.t(
                    "\(professionalPageCount) 页 · 目标 \(store.document.workspace?.targetPageCount ?? 110) 页",
                    "\(professionalPageCount) pages · Target \(store.document.workspace?.targetPageCount ?? 110)",
                    language: lang
                ))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(colors.textSecondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 38)
        }
        .background(colors.panelBg)
    }

    @ViewBuilder
    private var saveState: some View {
        switch store.saveState {
        case .saved:
            Label(L10n.t("已保存", "Saved", language: lang), systemImage: "checkmark.circle")
                .foregroundStyle(colors.textSecondary)
        case .unsaved:
            Label(L10n.t("正在保存", "Saving", language: lang), systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(colors.textSecondary)
        case .failed:
            Label(L10n.t("保存失败", "Save Failed", language: lang), systemImage: "exclamationmark.triangle")
                .foregroundStyle(colors.stateFail)
        }
    }

    private var deliveryMenu: some View {
        Menu {
            Section(L10n.t("导入", "Import", language: lang)) {
                Button(action: importFountain) {
                    Label("Fountain…", systemImage: "square.and.arrow.down")
                }
                Button(action: importFDX) {
                    Label(
                        L10n.t("FDX 核心兼容 · Beta…", "FDX Core Compatible · Beta…", language: lang),
                        systemImage: "square.and.arrow.down"
                    )
                }
                Button {} label: {
                    Label(L10n.t("PDF · Beta（待接入）", "PDF · Beta (Coming Soon)", language: lang), systemImage: "square.and.arrow.down")
                }
                .disabled(true)
            }

            Section(L10n.t("导出", "Export", language: lang)) {
                Button(action: exportFountain) {
                    Label("Fountain…", systemImage: "square.and.arrow.up")
                }
                Button(action: exportFDX) {
                    Label(
                        L10n.t("FDX 核心兼容 · Beta…", "FDX Core Compatible · Beta…", language: lang),
                        systemImage: "square.and.arrow.up"
                    )
                }

                Menu {
                    Menu(L10n.t("中文剧本（中国大陆）", "Chinese Screenplay (Mainland China)", language: lang)) {
                        Button(L10n.t("阅读版 · A4…", "Reader Copy · A4…", language: lang)) {
                            exportPDF(profile: .reader, screenplayFormat: .mainlandChina)
                        }
                        Button(L10n.t("制片版 · A4…", "Production Copy · A4…", language: lang)) {
                            exportPDF(profile: .production, screenplayFormat: .mainlandChina)
                        }
                    }
                    Menu(L10n.t("中文剧本（中国香港）", "Chinese Screenplay (Hong Kong)", language: lang)) {
                        Button(L10n.t("阅读版 · A4…", "Reader Copy · A4…", language: lang)) {
                            exportPDF(profile: .reader, screenplayFormat: .hongKong)
                        }
                        Button(L10n.t("拍摄版 · A4…", "Shooting Copy · A4…", language: lang)) {
                            exportPDF(profile: .production, screenplayFormat: .hongKong)
                        }
                    }
                    Divider()
                    Menu(L10n.t("国际标准（Letter）", "International (Letter)", language: lang)) {
                        Button(L10n.t("阅读版…", "Reader Copy…", language: lang)) {
                            exportPDF(profile: .reader, screenplayFormat: .international)
                        }
                        Button(L10n.t("制片版…", "Production Copy…", language: lang)) {
                            exportPDF(profile: .production, screenplayFormat: .international)
                        }
                    }
                } label: {
                    Label(L10n.t("专业 PDF", "Production PDF", language: lang), systemImage: "square.and.arrow.up")
                }
            }

            Divider()

            Button {
                store.createSnapshot(name: snapshotName)
                snapshotConfirmation = true
            } label: {
                Label(L10n.t("创建版本快照", "Create Version Snapshot", language: lang), systemImage: "clock.arrow.circlepath")
            }
        } label: {
            Label(L10n.t("交付", "Deliver", language: lang), systemImage: "shippingbox")
        }
        .popover(isPresented: $snapshotConfirmation) {
            Label(
                L10n.t("版本快照已保存", "Version snapshot saved", language: lang),
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(colors.stateSuccess)
            .padding(16)
        }
    }

    private var searchResults: [ScriptWorkshopSearchResult] {
        store.search(searchQuery)
    }

    private var searchResultsPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.t("全剧搜索", "SEARCH SCRIPT", language: lang))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.8)
                Spacer()
                Text("\(searchResults.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textTertiary)
            }
            .padding(12)

            Divider()

            if searchResults.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 22, weight: .light))
                    Text(L10n.t("没有找到匹配内容", "No matches found", language: lang))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(searchResults) { result in
                            Button {
                                focusSearchResult(result)
                            } label: {
                                HStack(alignment: .top, spacing: 9) {
                                    Image(systemName: result.kind == nil ? "film" : "text.alignleft")
                                        .foregroundStyle(accent.primary)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(result.sceneHeading.isEmpty
                                                 ? L10n.t("未命名场景", "Untitled Scene", language: lang)
                                                 : result.sceneHeading)
                                                .font(.system(size: 10, weight: .semibold))
                                                .lineLimit(1)
                                            if let kind = result.kind {
                                                Text(blockKindLabel(kind))
                                                    .font(.system(size: 8, weight: .medium))
                                                    .foregroundStyle(colors.textTertiary)
                                            }
                                        }
                                        Text(result.excerpt)
                                            .font(.system(size: 10))
                                            .foregroundStyle(colors.textSecondary)
                                            .lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(colors.inputBg.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 340)
            }
        }
        .frame(width: 390)
        .background(colors.panelBg)
    }

    private var newRevisionPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                L10n.t("开始一个新的修订集", "Start a new revision set", language: lang),
                systemImage: "pencil.and.outline"
            )
            .font(.system(size: 12, weight: .semibold))

            TextField(
                L10n.t("例如：蓝页修订 7/30", "e.g. Blue Revision 7/30", language: lang),
                text: $newRevisionName
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 260)

            HStack {
                Spacer()
                Button(L10n.t("取消", "Cancel", language: lang)) {
                    newRevisionIsPresented = false
                }
                Button(L10n.t("开始修订", "Start Revision", language: lang)) {
                    let trimmed = newRevisionName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    store.startRevision(name: trimmed)
                    newRevisionIsPresented = false
                    newRevisionName = ""
                }
                .buttonStyle(.borderedProminent)
                .tint(accent.primary)
                .disabled(newRevisionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
    }

    private var suggestedRevisionName: String {
        let next = (store.document.workspace?.revisionSets.count ?? 0) + 1
        return L10n.t("修订 \(next)", "Revision \(next)", language: lang)
    }

    private var activeRevisionColor: Color {
        guard let color = store.activeRevisionSet?.color else {
            return colors.textTertiary
        }
        return revisionColor(color)
    }

    private var professionalPageCount: Int {
        var configuration = ScriptWorkshopPaginationConfiguration()
        configuration.includeTitlePage = false
        return ScriptWorkshopPagination.paginate(
            store.document,
            configuration: configuration
        ).scriptPageCount
    }

    private var sceneNavigator: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("场景", "SCENES", language: lang))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(colors.textSecondary)
                Spacer()
                Text("\(store.document.scenes.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)

            Divider()

            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(Array(store.document.scenes.enumerated()), id: \.element.id) { index, scene in
                        sceneNavigationRow(scene, index: index)
                    }
                }
                .padding(9)
            }

            Divider()
            Button {
                store.addScene(after: store.document.scenes.last?.id)
            } label: {
                Label(L10n.t("添加场景", "Add Scene", language: lang), systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
        .background(colors.panelBg)
    }

    private func sceneNavigationRow(_ scene: ScriptWorkshopScene, index: Int) -> some View {
        let selected = scene.id == store.selectedSceneID
        return Button {
            store.selectScene(scene.id)
        } label: {
            HStack(spacing: 9) {
                Text(scene.metadata?.sceneNumber.isEmpty == false
                     ? scene.metadata!.sceneNumber
                     : "\(index + 1)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? Color.white : accent.primary)
                    .frame(width: 24, height: 24)
                    .background(selected ? accent.primary : accent.primary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) {
                    Text(scene.heading.isEmpty ? L10n.t("未命名场景", "Untitled Scene", language: lang) : scene.heading)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(2)
                    Text(scene.synopsis.isEmpty
                         ? L10n.t("\(scene.blocks.count) 个段落", "\(scene.blocks.count) blocks", language: lang)
                         : scene.synopsis)
                        .font(.system(size: 9))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Circle()
                    .fill(sceneStatusColor(scene.status))
                    .frame(width: 7, height: 7)
                    .help(sceneStatusLabel(scene.status))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? accent.primary.opacity(0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(L10n.t("上移", "Move Up", language: lang)) {
                store.moveScene(scene.id, offset: -1)
            }
            .disabled(index == 0)
            Button(L10n.t("下移", "Move Down", language: lang)) {
                store.moveScene(scene.id, offset: 1)
            }
            .disabled(index == store.document.scenes.count - 1)
            Divider()
            Button(L10n.t("删除场景", "Delete Scene", language: lang), role: .destructive) {
                scenePendingDeletion = scene.id
            }
        }
        .accessibilityIdentifier("scriptWorkshop.scene.\(scene.id.uuidString)")
    }

    @ViewBuilder
    private var pageWorkspace: some View {
        if let scene = store.selectedScene {
            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: 34, height: 1)
                            scenePage(scene)
                            Color.clear.frame(width: 34, height: 1)
                        }
                        .frame(
                            minWidth: viewport.size.width,
                            minHeight: viewport.size.height,
                            alignment: .top
                        )
                        .padding(.vertical, 34)
                    }
                    .background(colors.surfaceBg)
                    .onChange(of: store.selectedBlockID) { blockID in
                        guard let blockID else { return }
                        withAnimation(.easeOut(duration: 0.16)) {
                            proxy.scrollTo(blockID, anchor: .center)
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(colors.textTertiary)
                Text(L10n.t("没有场景", "No Scene", language: lang))
                    .font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func scenePage(_ scene: ScriptWorkshopScene) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t(
                    "场景 \(scene.metadata?.sceneNumber.isEmpty == false ? scene.metadata!.sceneNumber : String(sceneNumber(scene.id)))",
                    "SCENE \(scene.metadata?.sceneNumber.isEmpty == false ? scene.metadata!.sceneNumber : String(sceneNumber(scene.id)))",
                    language: lang
                ))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(colors.textTertiary)
                Circle()
                    .fill(sceneStatusColor(scene.status))
                    .frame(width: 7, height: 7)
                Text(sceneStatusLabel(scene.status))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(colors.textTertiary)
                Spacer()
                Text(L10n.t(
                    "回车创建下一段 · 短按 Tab 切换类型 · 长按 Tab 召唤创作轮",
                    "Return next block · Tap Tab to cycle · Hold Tab for the wheel",
                    language: lang
                ))
                .font(.system(size: 9))
                .foregroundStyle(colors.textTertiary)
            }
            .padding(.bottom, 24)

            TextField(
                L10n.t("内景 · 地点 · 日", "INT. LOCATION - DAY", language: lang),
                text: Binding(
                    get: { store.selectedScene?.heading ?? "" },
                    set: { store.updateSceneHeading(scene.id, value: $0) }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .textCase(.uppercase)
            .padding(.bottom, 16)
            .accessibilityIdentifier("scriptWorkshop.sceneHeading")

            ForEach(scene.blocks) { block in
                ScriptWorkshopBlockRow(
                    block: block,
                    isFocused: store.selectedBlockID == block.id,
                    language: lang,
                    colors: colors,
                    accent: accent,
                    updateText: { store.updateBlockText(sceneID: scene.id, blockID: block.id, value: $0) },
                    updateKind: { store.updateBlockKind(sceneID: scene.id, blockID: block.id, kind: $0) },
                    focus: { store.selectBlock(block.id) },
                    advance: { trigger, utf16Offset in
                        if trigger == .returnKey {
                            store.splitBlock(
                                sceneID: scene.id,
                                blockID: block.id,
                                utf16Offset: utf16Offset,
                                trigger: trigger
                            )
                        } else {
                            store.advance(sceneID: scene.id, from: block.id, trigger: .tab)
                        }
                    },
                    wheelEvent: {
                        handleWheelEvent(
                            $0,
                            targetSceneID: scene.id,
                            targetBlockID: block.id,
                            workspaceSize: workshopSize
                        )
                    },
                    wheelCoordinates: wheelCoordinates,
                    undo: store.undo,
                    redo: store.redo,
                    mergeBackward: {
                        store.mergeBlockBackward(sceneID: scene.id, blockID: block.id)
                    },
                    delete: { store.deleteBlock(sceneID: scene.id, blockID: block.id) }
                )
                .id(block.id)
            }

            Menu {
                ForEach(ScriptWorkshopBlockKind.allCases) { kind in
                    Button(blockKindLabel(kind)) {
                        store.addBlock(sceneID: scene.id, kind: kind)
                    }
                }
            } label: {
                Label(L10n.t("添加段落", "Add Block", language: lang), systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
        }
        .padding(.horizontal, 66)
        .padding(.vertical, 48)
        .frame(width: 790)
        .frame(minHeight: 980, alignment: .top)
        .background(scriptPaperColor)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .shadow(color: Color.black.opacity(0.14), radius: 18, y: 7)
    }

    private var cardsWorkspace: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 248, maximum: 320), spacing: 16)],
                spacing: 16
            ) {
                ForEach(Array(store.document.scenes.enumerated()), id: \.element.id) { index, scene in
                    sceneCard(scene, index: index)
                }
            }
            .padding(24)
        }
        .background(colors.surfaceBg)
    }

    private func sceneCard(_ scene: ScriptWorkshopScene, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(scene.metadata?.sceneNumber.isEmpty == false
                     ? scene.metadata!.sceneNumber
                     : "\(index + 1)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent.primary)
                Text(sceneStatusLabel(scene.status))
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(sceneStatusColor(scene.status))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(sceneStatusColor(scene.status).opacity(0.10))
                    .clipShape(Capsule())
                Spacer()
                HStack(spacing: 2) {
                    Button { store.moveScene(scene.id, offset: -1) } label: {
                        Image(systemName: "arrow.left")
                    }
                    .disabled(index == 0)
                    Button { store.moveScene(scene.id, offset: 1) } label: {
                        Image(systemName: "arrow.right")
                    }
                    .disabled(index == store.document.scenes.count - 1)
                }
                .buttonStyle(.borderless)
            }

            TextField(
                L10n.t("场景标题", "Scene Heading", language: lang),
                text: Binding(
                    get: { scene.heading },
                    set: { store.updateSceneHeading(scene.id, value: $0) }
                )
            )
            .font(.system(size: 12, weight: .bold, design: .monospaced))

            TextEditor(text: Binding(
                get: { scene.synopsis },
                set: { store.updateSceneSynopsis(scene.id, value: $0) }
            ))
            .font(.system(size: 11))
            .scrollContentBackground(.hidden)
            .padding(7)
            .frame(height: 92)
            .background(colors.inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Label(
                    L10n.t("\(scene.blocks.count) 段", "\(scene.blocks.count) blocks", language: lang),
                    systemImage: "text.alignleft"
                )
                Spacer()
                Button(L10n.t("进入写作", "Write", language: lang)) {
                    store.selectScene(scene.id)
                    mode = .page
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .font(.system(size: 9))
            .foregroundStyle(colors.textSecondary)
        }
        .padding(16)
        .background(scene.id == store.selectedSceneID ? accent.primary.opacity(0.10) : colors.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    scene.id == store.selectedSceneID ? accent.primary.opacity(0.55) : colors.hairline,
                    lineWidth: 1
                )
        )
        .onTapGesture { store.selectedSceneID = scene.id }
    }

    private var outlineWorkspace: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.t("三幕大纲", "THREE-ACT OUTLINE", language: lang))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .tracking(0.8)
                        Text(L10n.t(
                            "节拍关联的是稳定场景，不会因场景移动而断开。",
                            "Beats stay linked by stable scene identity, even when scenes move.",
                            language: lang
                        ))
                        .font(.system(size: 10))
                        .foregroundStyle(colors.textSecondary)
                    }
                    Spacer()
                    let unassigned = store.document.scenes.filter {
                        ($0.metadata?.act ?? .unassigned) == .unassigned
                    }.count
                    if unassigned > 0 {
                        Label(
                            L10n.t("\(unassigned) 场待分幕", "\(unassigned) unassigned", language: lang),
                            systemImage: "tray"
                        )
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(colors.stateWarning)
                    }
                }
                .frame(width: 932)

                HStack(alignment: .top, spacing: 14) {
                    outlineActColumn(.actOne, number: 1)
                    outlineActColumn(.actTwo, number: 2)
                    outlineActColumn(.actThree, number: 3)
                }
            }
            .padding(24)
        }
        .background(colors.surfaceBg)
    }

    private func outlineActColumn(_ act: ScriptWorkshopAct, number: Int) -> some View {
        let beats = (store.document.workspace?.beats ?? [])
            .filter { $0.act == act }
            .sorted { lhs, rhs in
                lhs.order == rhs.order
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : lhs.order < rhs.order
            }
        let sceneCount = store.document.scenes.filter {
            ($0.metadata?.act ?? .unassigned) == act
        }.count

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    Circle()
                        .fill(accent.gradient)
                    Text("\(number)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .frame(width: 27, height: 27)

                VStack(alignment: .leading, spacing: 1) {
                    Text(actLabel(act))
                        .font(.system(size: 11, weight: .semibold))
                    Text(L10n.t("\(sceneCount) 个场景", "\(sceneCount) scenes", language: lang))
                        .font(.system(size: 9))
                        .foregroundStyle(colors.textTertiary)
                }
                Spacer()
                Text("\(beats.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(colors.textTertiary)
            }

            if beats.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                        .font(.system(size: 22, weight: .light))
                    Text(L10n.t("还没有节拍", "No beats yet", language: lang))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(colors.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 96)
            } else {
                ForEach(beats) { beat in
                    outlineBeatCard(beat)
                }
            }

            Button {
                store.addBeat(act: act)
            } label: {
                Label(L10n.t("添加节拍", "Add Beat", language: lang), systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .padding(.vertical, 6)
        }
        .padding(14)
        .frame(width: 300, alignment: .top)
        .background(colors.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(colors.hairline, lineWidth: 1)
        )
    }

    private func outlineBeatCard(_ beat: ScriptWorkshopBeat) -> some View {
        let isLinked = store.selectedSceneID.map(beat.sceneIDs.contains) ?? false
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent.primary.opacity(0.85))
                    .frame(width: 4, height: 18)

                TextField(
                    L10n.t("节拍标题", "Beat title", language: lang),
                    text: beatTextBinding(beat.id, keyPath: \.title)
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .semibold))

                Button {
                    store.deleteBeat(beat.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(colors.textTertiary)
                .help(L10n.t("删除节拍", "Delete Beat", language: lang))
            }

            TextEditor(text: beatTextBinding(beat.id, keyPath: \.synopsis))
                .font(.system(size: 10))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 64)
                .background(colors.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            if !beat.sceneIDs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(beat.sceneIDs, id: \.self) { sceneID in
                        if let scene = store.document.scenes.first(where: { $0.id == sceneID }) {
                            Button {
                                store.selectScene(sceneID)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(scene.metadata?.sceneNumber.isEmpty == false
                                         ? scene.metadata!.sceneNumber
                                         : "\(sceneNumber(sceneID))")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(accent.primary)
                                    Text(scene.heading.isEmpty
                                         ? L10n.t("未命名场景", "Untitled Scene", language: lang)
                                         : scene.heading)
                                        .font(.system(size: 9, weight: .medium))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(sceneID == store.selectedSceneID
                                            ? accent.primary.opacity(0.11)
                                            : colors.inputBg.opacity(0.75))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Button {
                store.linkSelectedScene(to: beat.id)
            } label: {
                Label(
                    isLinked
                        ? L10n.t("取消关联当前场景", "Unlink Current Scene", language: lang)
                        : L10n.t("关联当前场景", "Link Current Scene", language: lang),
                    systemImage: isLinked ? "link.badge.minus" : "link.badge.plus"
                )
                .font(.system(size: 9, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(store.selectedSceneID == nil)
        }
        .padding(10)
        .background(colors.surfaceBg.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(colors.hairline.opacity(0.8), lineWidth: 1)
        )
    }

    private var dialogueWorkspace: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text(L10n.t("人物", "CHARACTERS", language: lang))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                    Spacer()
                    Text("\(store.document.allCharacters.count)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(colors.textTertiary)
                }
                .padding(.horizontal, 12)
                .frame(height: 42)
                Divider()

                if store.document.allCharacters.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 26, weight: .light))
                        Text(L10n.t("写下人物对白后\n这里会自动出现", "Characters appear here\nafter you write dialogue", language: lang))
                            .multilineTextAlignment(.center)
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(colors.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(store.document.allCharacters, id: \.self) { character in
                                let selected = effectiveDialogueCharacter == character
                                Button {
                                    dialogueCharacter = character
                                } label: {
                                    HStack {
                                        Image(systemName: "person.fill")
                                            .foregroundStyle(selected ? .white : accent.primary)
                                        Text(character)
                                            .font(.system(size: 10, weight: .semibold))
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(store.dialogueLines(for: character).count)")
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(selected ? Color.white.opacity(0.78) : colors.textTertiary)
                                    }
                                    .padding(.horizontal, 9)
                                    .frame(height: 32)
                                    .background(selected ? accent.primary : Color.clear)
                                    .foregroundStyle(selected ? .white : colors.textPrimary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .frame(width: 184)
            .background(colors.panelBg)

            Divider()

            if effectiveDialogueCharacter.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 34, weight: .light))
                    Text(L10n.t("对白调校台", "Dialogue Tuner", language: lang))
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.t("选择一个人物，集中检查他的全部台词。", "Choose a character to review every line in one place.", language: lang))
                        .font(.system(size: 10))
                        .foregroundStyle(colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                dialogueLinesWorkspace(for: effectiveDialogueCharacter)
            }
        }
        .background(colors.surfaceBg)
    }

    private func dialogueLinesWorkspace(for character: String) -> some View {
        let lines = store.dialogueLines(for: character)
        return VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(character)
                        .font(.system(size: 13, weight: .semibold))
                    Text(L10n.t("\(lines.count) 句对白", "\(lines.count) dialogue lines", language: lang))
                        .font(.system(size: 9))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Label(
                    L10n.t("集中调校会直接更新原剧本", "Edits update the screenplay directly", language: lang),
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.system(size: 9))
                .foregroundStyle(colors.textTertiary)
            }
            .padding(.horizontal, 18)
            .frame(height: 52)

            Divider()

            if lines.isEmpty {
                Text(L10n.t("这个人物还没有对白。", "This character has no dialogue yet.", language: lang))
                    .font(.system(size: 11))
                    .foregroundStyle(colors.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(lines) { line in
                                dialogueLineCard(line)
                                    .id(line.blockID)
                            }
                        }
                        .padding(18)
                    }
                    .onChange(of: store.selectedBlockID) { blockID in
                        guard let blockID else { return }
                        withAnimation(.easeOut(duration: 0.16)) {
                            proxy.scrollTo(blockID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func dialogueLineCard(_ line: ScriptWorkshopDialogueLine) -> some View {
        let selected = store.selectedBlockID == line.blockID
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(line.sceneNumber)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent.primary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(accent.primary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(line.sceneHeading.isEmpty
                     ? L10n.t("未命名场景", "Untitled Scene", language: lang)
                     : line.sceneHeading)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    store.selectedSceneID = line.sceneID
                    store.selectedBlockID = line.blockID
                    mode = .page
                } label: {
                    Label(L10n.t("回到原文", "Open in Script", language: lang), systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 9))
            }

            TextEditor(text: dialogueTextBinding(line))
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(7)
                .frame(height: dialogueEditorHeight(line.text))
                .background(scriptPaperColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(11)
        .background(selected ? accent.primary.opacity(0.09) : colors.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(selected ? accent.primary.opacity(0.5) : colors.hairline, lineWidth: 1)
        )
        .onTapGesture {
            store.selectedSceneID = line.sceneID
            store.selectedBlockID = line.blockID
        }
    }

    private var inspector: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.t("文稿资料", "DOCUMENT", language: lang))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.9)
                    .foregroundStyle(colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 15)
            .frame(height: 42)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    inspectorSection(L10n.t("故事定位", "STORY", language: lang)) {
                        TextEditor(text: Binding(
                            get: { store.document.workspace?.logline ?? "" },
                            set: store.updateLogline
                        ))
                        .font(.system(size: 10.5))
                        .scrollContentBackground(.hidden)
                        .padding(7)
                        .frame(height: 76)
                        .background(colors.inputBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .topLeading) {
                            if (store.document.workspace?.logline ?? "").isEmpty {
                                Text(L10n.t("一句话说清主角、目标与阻力", "Protagonist, goal, and obstacle in one line", language: lang))
                                    .font(.system(size: 10))
                                    .foregroundStyle(colors.textTertiary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 13)
                                    .allowsHitTesting(false)
                            }
                        }

                        TextField(
                            L10n.t("类型，例如：犯罪 / 悬疑", "Genre, e.g. Crime / Thriller", language: lang),
                            text: Binding(
                                get: { store.document.workspace?.genre ?? "" },
                                set: store.updateGenre
                            )
                        )

                        Stepper(
                            value: Binding(
                                get: { store.document.workspace?.targetPageCount ?? 110 },
                                set: store.updateTargetPageCount
                            ),
                            in: 1...999
                        ) {
                            HStack {
                                Text(L10n.t("目标页数", "Target Pages", language: lang))
                                    .foregroundStyle(colors.textSecondary)
                                Spacer()
                                Text("\(store.document.workspace?.targetPageCount ?? 110)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            }
                            .font(.system(size: 10))
                        }
                    }

                    inspectorSection(L10n.t("作者", "AUTHOR", language: lang)) {
                        TextField(
                            L10n.t("作者姓名", "Writer Name", language: lang),
                            text: Binding(
                                get: { store.document.author },
                                set: store.updateAuthor
                            )
                        )
                    }

                    if let scene = store.selectedScene {
                        inspectorSection(L10n.t("当前场景", "CURRENT SCENE", language: lang)) {
                            HStack(spacing: 8) {
                                Picker(
                                    L10n.t("幕", "Act", language: lang),
                                    selection: Binding(
                                        get: { scene.metadata?.act ?? .unassigned },
                                        set: { store.updateSceneAct(scene.id, act: $0) }
                                    )
                                ) {
                                    ForEach(ScriptWorkshopAct.allCases) { act in
                                        Text(actLabel(act)).tag(act)
                                    }
                                }
                                .pickerStyle(.menu)

                                Picker(
                                    L10n.t("状态", "Status", language: lang),
                                    selection: Binding(
                                        get: { scene.status },
                                        set: { store.updateSceneStatus(scene.id, status: $0) }
                                    )
                                ) {
                                    ForEach(ScriptWorkshopSceneStatus.allCases) { status in
                                        Text(sceneStatusLabel(status)).tag(status)
                                    }
                                }
                                .pickerStyle(.menu)
                            }

                            TextEditor(text: Binding(
                                get: { scene.synopsis },
                                set: { store.updateSceneSynopsis(scene.id, value: $0) }
                            ))
                            .font(.system(size: 11))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(height: 112)
                            .background(colors.inputBg)
                            .clipShape(RoundedRectangle(cornerRadius: 9))

                            HStack(spacing: 6) {
                                TextField(
                                    L10n.t("标签，用逗号分隔", "Tags, separated by commas", language: lang),
                                    text: $sceneTagsDraft
                                )
                                .onSubmit(commitSceneTags)
                                Button(action: commitSceneTags) {
                                    Image(systemName: "checkmark")
                                }
                                .buttonStyle(.borderless)
                                .disabled(sceneTagsDraft == (scene.metadata?.tags ?? []).joined(separator: ", "))
                                .help(L10n.t("应用标签", "Apply Tags", language: lang))
                            }

                            if !(scene.metadata?.tags ?? []).isEmpty {
                                FlowingTagLayout(spacing: 5) {
                                    ForEach(scene.metadata?.tags ?? [], id: \.self) { tag in
                                        Text(tag)
                                            .font(.system(size: 8, weight: .medium))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 4)
                                            .background(colors.inputBg)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }

                    inspectorSection(L10n.t("人物", "CHARACTERS", language: lang)) {
                        if store.document.allCharacters.isEmpty {
                            Text(L10n.t(
                                "输入人物段落后自动建立人物索引。",
                                "Character cues automatically build this index.",
                                language: lang
                            ))
                            .font(.system(size: 10))
                            .foregroundStyle(colors.textSecondary)
                        } else {
                            FlowingTagLayout(spacing: 6) {
                                ForEach(store.document.allCharacters, id: \.self) { name in
                                    Text(name)
                                        .font(.system(size: 9, weight: .medium))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(accent.primary.opacity(0.10))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    inspectorSection(L10n.t("统计", "STATS", language: lang)) {
                        statRow(L10n.t("场景", "Scenes", language: lang), "\(store.document.scenes.count)")
                        statRow(L10n.t("专业分页", "Script Pages", language: lang), "\(professionalPageCount)")
                        statRow(L10n.t("目标页数", "Target Pages", language: lang), "\(store.document.workspace?.targetPageCount ?? 110)")
                        statRow(L10n.t("词语", "Words", language: lang), "\(store.document.wordCount)")
                        statRow(L10n.t("版本快照", "Snapshots", language: lang), "\(store.document.snapshots.count)")
                    }

                    screenplayHealth

                    inspectorSection(L10n.t("修订", "REVISIONS", language: lang)) {
                        HStack {
                            Circle()
                                .fill(activeRevisionColor)
                                .frame(width: 8, height: 8)
                            Text(store.activeRevisionSet?.name
                                 ?? L10n.t("当前未标记修订", "Revision marking is off", language: lang))
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(2)
                            Spacer()
                        }
                        Text(L10n.t(
                            "新编辑会记录到当前修订集；修订色不会改变工坊主题色。",
                            "New edits join the active revision set. Revision colors remain independent from the workspace theme.",
                            language: lang
                        ))
                        .font(.system(size: 9))
                        .foregroundStyle(colors.textTertiary)
                    }
                }
                .padding(15)
            }
        }
        .background(colors.panelBg)
    }

    private var screenplayHealth: some View {
        let pagination = store.pagination(includeTitlePage: false)
        let report = ScriptWorkshopAnalysis.analyze(store.document, pagination: pagination)
        let visibleIssueIndices = Array(report.issues.indices.prefix(5))

        return inspectorSection(L10n.t("剧本体检", "SCRIPT HEALTH", language: lang)) {
            DisclosureGroup(isExpanded: $analysisIsExpanded) {
                if report.issues.isEmpty {
                    Label(
                        L10n.t("没有发现需要处理的问题", "No issues need attention", language: lang),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(colors.stateSuccess)
                    .padding(.top, 4)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(visibleIssueIndices, id: \.self) { index in
                            let issue = report.issues[index]
                            Button {
                                focusAnalysisIssue(issue)
                            } label: {
                                HStack(alignment: .top, spacing: 6) {
                                    Circle()
                                        .fill(analysisIssueColor(issue.severity))
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 3)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(localizedAnalysisMessage(issue, report: report))
                                            .font(.system(size: 9))
                                            .foregroundStyle(colors.textPrimary)
                                            .lineLimit(2)
                                        if !issue.fixHint.isEmpty {
                                            Text(localizedAnalysisFixHint(issue))
                                                .font(.system(size: 8))
                                                .foregroundStyle(colors.textTertiary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                                .background(colors.inputBg.opacity(0.72))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            }
                            .buttonStyle(.plain)
                            .disabled(issue.sceneID == nil)
                        }

                        if report.issues.count > visibleIssueIndices.count {
                            Text(L10n.t(
                                "另有 \(report.issues.count - visibleIssueIndices.count) 条",
                                "\(report.issues.count - visibleIssueIndices.count) more",
                                language: lang
                            ))
                            .font(.system(size: 8))
                            .foregroundStyle(colors.textTertiary)
                        }
                    }
                    .padding(.top, 6)
                }
            } label: {
                HStack(spacing: 7) {
                    Label(
                        L10n.t("\(report.errorCount) 项错误", "\(report.errorCount) errors", language: lang),
                        systemImage: "xmark.octagon.fill"
                    )
                    .foregroundStyle(report.errorCount > 0 ? colors.stateFail : colors.textTertiary)

                    Label(
                        L10n.t("\(report.warningCount) 项提醒", "\(report.warningCount) warnings", language: lang),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(report.warningCount > 0 ? colors.stateWarning : colors.textTertiary)
                }
                .font(.system(size: 9, weight: .medium))
            }
        }
    }

    private func focusAnalysisIssue(_ issue: ScriptWorkshopAnalysisIssue) {
        guard let sceneID = issue.sceneID else { return }
        store.selectScene(sceneID)
        if let blockID = issue.blockID {
            store.selectBlock(blockID)
        }
        mode = .page
    }

    private func analysisIssueColor(_ severity: ScriptWorkshopAnalysisSeverity) -> Color {
        switch severity {
        case .information: return accent.primary
        case .warning: return colors.stateWarning
        case .error: return colors.stateFail
        }
    }

    private func localizedAnalysisMessage(
        _ issue: ScriptWorkshopAnalysisIssue,
        report: ScriptWorkshopAnalysisReport
    ) -> String {
        let scene = issue.sceneID.flatMap { id in
            store.document.scenes.first { $0.id == id }
        }
        let block = scene?.blocks.first { $0.id == issue.blockID }
        let sceneName = scene?.heading.trimmingCharacters(in: .whitespacesAndNewlines)
        let cueName = block?.text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch issue.code {
        case "empty-scene":
            return L10n.t(
                "场景“\(sceneName?.isEmpty == false ? sceneName! : "未命名场景")”没有剧本正文。",
                issue.message,
                language: lang
            )
        case "invalid-scene-heading":
            return L10n.t("场景标题没有以可识别的内景／外景标记开头。", issue.message, language: lang)
        case "character-without-dialogue":
            return L10n.t(
                "人物“\(cueName?.isEmpty == false ? cueName! : "未命名人物")”之后没有对白。",
                issue.message,
                language: lang
            )
        case "orphan-parenthetical":
            return L10n.t("括号说明前没有对应的人物。", issue.message, language: lang)
        case "orphan-dialogue":
            return L10n.t("这段对白前没有正在说话的人物。", issue.message, language: lang)
        case "long-action-block":
            return L10n.t(
                "动作段过长（约 \(block?.text.count ?? 0) 个字符）。",
                issue.message,
                language: lang
            )
        case "empty-script-block":
            let kind = block.map { blockKindLabel($0.kind) } ?? L10n.t("正文", "script", language: lang)
            return L10n.t("场景中仍有一个空的\(kind)段。", issue.message, language: lang)
        case "locked-scene-missing-number":
            return L10n.t("已锁定的场景没有制作场号。", issue.message, language: lang)
        case "duplicate-locked-scene-number":
            let number = scene?.productionNumber.isEmpty == false ? scene!.productionNumber : "—"
            return L10n.t("已锁定的场号“\(number)”发生重复。", issue.message, language: lang)
        case "scene-without-beat":
            return L10n.t(
                "场景“\(sceneName?.isEmpty == false ? sceneName! : "未命名场景")”尚未关联大纲节拍。",
                issue.message,
                language: lang
            )
        case "dangling-scene-beat-link":
            return L10n.t("场景关联了一个已经不存在的大纲节拍。", issue.message, language: lang)
        case "beat-without-scene":
            return L10n.t("有一个大纲节拍尚未关联剧本场景。", issue.message, language: lang)
        case "dangling-beat-scene-link":
            return L10n.t("大纲节拍关联了一个已经不存在的场景。", issue.message, language: lang)
        case "target-page-count-large-deviation", "target-page-count-deviation":
            let actual = report.stats.pageCount
            let target = report.stats.targetPageCount ?? 0
            let difference = abs(actual - target)
            let direction = actual < target ? "少" : "多"
            return L10n.t(
                "剧本共 \(actual) 页，比 \(target) 页目标\(direction) \(difference) 页。",
                issue.message,
                language: lang
            )
        case "pagination.invalid-font-size", "pagination.invalid-line-height",
             "pagination.invalid-latin-width", "pagination.invalid-cjk-width":
            return L10n.t("分页参数无效，已使用安全默认值。", issue.message, language: lang)
        case "pagination.margins-reduced-for-pagination":
            return L10n.t("页边距不足以容纳正文，分页时已自动收窄。", issue.message, language: lang)
        case "pagination.omitted-block-excluded":
            return L10n.t("一个标记为省略的段落没有进入分页结果。", issue.message, language: lang)
        case "pagination.oversized-character-cue":
            return L10n.t("人物提示过长，已按普通段落分页以避免丢字。", issue.message, language: lang)
        case "pagination.dialogue-pagination-fallback":
            return L10n.t("这段对白无法满足续页规则，已在可用边界安全拆分。", issue.message, language: lang)
        case "pagination.scene-heading-spans-pages":
            return L10n.t("场景标题过长，已经跨页排版。", issue.message, language: lang)
        default:
            return L10n.t("剧本检查发现一项需要处理的问题。", issue.message, language: lang)
        }
    }

    private func localizedAnalysisFixHint(_ issue: ScriptWorkshopAnalysisIssue) -> String {
        let chinese: String
        switch issue.code {
        case "empty-scene": chinese = "添加动作或对白，或者删除这个未使用的场景。"
        case "invalid-scene-heading": chinese = "使用“内景 · 地点 · 日”一类场景标题。"
        case "character-without-dialogue": chinese = "在人物后添加对白，或把人物段改成正确的段落类型。"
        case "orphan-parenthetical": chinese = "把括号说明移到人物后，或改成动作段。"
        case "orphan-dialogue": chinese = "在对白前插入或恢复正在说话的人物。"
        case "long-action-block": chinese = "在镜头、主体或戏剧动作变化处拆成更短的视觉段落。"
        case "empty-script-block": chinese = "如果它不是当前输入位置，请删除这个空段。"
        case "locked-scene-missing-number": chinese = "发布或导出制片稿前，为它指定唯一场号。"
        case "duplicate-locked-scene-number": chinese = "使用唯一锁定场号或 A/B 后缀，避免重排已发布场次。"
        case "scene-without-beat": chinese = "关联已有节拍，或从这个场景新建节拍。"
        case "dangling-scene-beat-link", "dangling-beat-scene-link": chinese = "移除失效关联，或重新连接现有场景与节拍。"
        case "beat-without-scene": chinese = "写到对应场景后建立关联，或明确标记为暂未分配。"
        case "target-page-count-large-deviation": chinese = "检查场景长度；如果当前规模合理，就更新目标页数。"
        case "target-page-count-deviation": chinese = "检查节奏与尚未完成的大纲节拍。"
        default:
            chinese = issue.code.hasPrefix("pagination.")
                ? "导出前检查受影响内容与分页设置。"
                : "根据提示检查对应场景或段落。"
        }
        return L10n.t(chinese, issue.fixHint, language: lang)
    }

    private func inspectorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.7)
                .foregroundStyle(colors.textTertiary)
            content()
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(colors.textSecondary)
            Spacer()
            Text(value).font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .font(.system(size: 10))
    }

    private func sceneNumber(_ id: UUID) -> Int {
        (store.document.scenes.firstIndex { $0.id == id } ?? 0) + 1
    }

    private func blockKindLabel(_ kind: ScriptWorkshopBlockKind) -> String {
        switch kind {
        case .action: return L10n.t("动作", "Action", language: lang)
        case .character: return L10n.t("人物", "Character", language: lang)
        case .dialogue: return L10n.t("对白", "Dialogue", language: lang)
        case .parenthetical: return L10n.t("括号说明", "Parenthetical", language: lang)
        case .transition: return L10n.t("转场", "Transition", language: lang)
        case .shot: return L10n.t("镜头提示", "Shot", language: lang)
        case .note: return L10n.t("作者笔记", "Note", language: lang)
        }
    }

    private func handleWheelEvent(
        _ event: ScriptWorkshopWheelEvent,
        targetSceneID: UUID,
        targetBlockID: UUID,
        workspaceSize: CGSize
    ) {
        guard mode == .page else {
            creationWheel = nil
            return
        }
        switch event {
        case .began(let point):
            let margin: CGFloat = 254
            let origin = CGPoint(
                x: min(max(point.x, margin), max(margin, workspaceSize.width - margin)),
                y: min(max(point.y, margin), max(margin, workspaceSize.height - margin))
            )
            withAnimation(.spring(response: 0.28, dampingFraction: 0.70)) {
                creationWheel = ScriptWorkshopWheelOverlayState(
                    origin: origin,
                    highlightedKind: nil,
                    showsCharacterRing: false,
                    highlightedCharacterID: nil,
                    targetSceneID: targetSceneID,
                    targetBlockID: targetBlockID
                )
            }
        case .moved(let point):
            guard var overlay = creationWheel else { return }
            updateWheelHighlight(&overlay, at: point)
            creationWheel = overlay
        case .ended(let point):
            guard var overlay = creationWheel else { return }
            updateWheelHighlight(&overlay, at: point)
            let selection = resolvedWheelSelection(from: overlay)
            withAnimation(.easeOut(duration: 0.11)) {
                creationWheel = nil
            }
            switch selection {
            case .element(let kind):
                store.applyWheelSelection(
                    kind,
                    sceneID: overlay.targetSceneID,
                    blockID: overlay.targetBlockID
                )
            case .character(let choice):
                if choice.isAdd {
                    newCharacterName = ""
                    pendingCharacterCreation = .init(
                        sceneID: overlay.targetSceneID,
                        blockID: overlay.targetBlockID
                    )
                } else if let name = choice.name {
                    store.applyWheelSelection(
                        .character,
                        text: name,
                        ensureCharacterProfile: true,
                        sceneID: overlay.targetSceneID,
                        blockID: overlay.targetBlockID
                    )
                }
            case nil:
                break
            }
        case .cancelled:
            withAnimation(.easeOut(duration: 0.11)) {
                creationWheel = nil
            }
        }
    }

    private var wheelCharacterChoices: [ScriptWorkshopWheelCharacterChoice] {
        ScriptWorkshopWheelCharacterChoice.choices(from: store.document.projectCharacterNames)
    }

    private var creationWheelTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.22).combined(with: .opacity),
            removal: .scale(scale: 0.70).combined(with: .opacity)
        )
    }

    private func updateWheelHighlight(
        _ overlay: inout ScriptWorkshopWheelOverlayState,
        at point: CGPoint
    ) {
        let dx = point.x - overlay.origin.x
        let dy = point.y - overlay.origin.y
        let currentSecondaryIndex = overlay.highlightedCharacterID.flatMap { id in
            wheelCharacterChoices.firstIndex(where: { $0.id == id })
        }
        let current = ScriptWorkshopWheelDirectionalState(
            primaryKind: overlay.highlightedKind,
            submenu: overlay.showsCharacterRing ? .projectCharacters : nil,
            secondaryIndex: currentSecondaryIndex
        )
        let resolved = ScriptWorkshopWheelInteraction.resolve(
            dx: dx,
            dy: dy,
            current: current,
            secondaryCount: wheelCharacterChoices.count
        )
        overlay.highlightedKind = resolved.primaryKind
        overlay.showsCharacterRing = resolved.submenu == .projectCharacters
        overlay.highlightedCharacterID = resolved.secondaryIndex.flatMap { index in
            wheelCharacterChoices.indices.contains(index)
                ? wheelCharacterChoices[index].id
                : nil
        }
    }

    private func resolvedWheelSelection(
        from overlay: ScriptWorkshopWheelOverlayState
    ) -> ScriptWorkshopWheelResolvedSelection? {
        if overlay.showsCharacterRing {
            guard let id = overlay.highlightedCharacterID,
                  let choice = wheelCharacterChoices.first(where: { $0.id == id }) else {
                return nil
            }
            return .character(choice)
        }
        return overlay.highlightedKind.map(ScriptWorkshopWheelResolvedSelection.element)
    }

    private func commitNewWheelCharacter() {
        guard let context = pendingCharacterCreation else { return }
        let name = newCharacterName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.applyWheelSelection(
            .character,
            text: name,
            ensureCharacterProfile: true,
            sceneID: context.sceneID,
            blockID: context.blockID
        )
        pendingCharacterCreation = nil
        newCharacterName = ""
    }

    private func importFountain() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("导入 Fountain 剧本", "Import Fountain Screenplay", language: lang)
        panel.allowedContentTypes = [
            UTType(filenameExtension: "fountain") ?? .plainText,
            .plainText
        ]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.errorMessage = nil
        store.importFountain(from: url)
        if store.errorMessage == nil {
            exportNotice = L10n.t("Fountain 剧本已导入", "Fountain screenplay imported", language: lang)
        }
    }

    private func exportFountain() {
        let panel = NSSavePanel()
        panel.title = L10n.t("导出 Fountain 剧本", "Export Fountain Screenplay", language: lang)
        panel.allowedContentTypes = [UTType(filenameExtension: "fountain") ?? .plainText]
        panel.nameFieldStringValue = "\(safeFileName(store.document.title)).fountain"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.errorMessage = nil
        store.exportFountain(to: url)
        showDeliveryResult(L10n.t("Fountain 已导出", "Fountain export complete", language: lang))
    }

    private func importFDX() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("导入 Final Draft FDX", "Import Final Draft FDX", language: lang)
        panel.allowedContentTypes = [UTType(filenameExtension: "fdx") ?? .xml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.errorMessage = nil
        store.importFDX(from: url)
        showDeliveryResult(L10n.t("FDX 已导入", "FDX import complete", language: lang))
    }

    private func exportFDX() {
        let panel = NSSavePanel()
        panel.title = L10n.t("导出 Final Draft FDX", "Export Final Draft FDX", language: lang)
        panel.allowedContentTypes = [UTType(filenameExtension: "fdx") ?? .xml]
        panel.nameFieldStringValue = "\(safeFileName(store.document.title)).fdx"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.errorMessage = nil
        store.exportFDX(to: url)
        showDeliveryResult(L10n.t("FDX 已导出", "FDX export complete", language: lang))
    }

    private func exportPDF(
        profile: ScriptWorkshopPDFProfile,
        screenplayFormat: ScriptWorkshopScreenplayFormat
    ) {
        let panel = NSSavePanel()
        let formatName: String
        switch screenplayFormat {
        case .international:
            formatName = L10n.t("国际标准", "International", language: lang)
        case .mainlandChina:
            formatName = L10n.t("中国大陆", "Mainland China", language: lang)
        case .hongKong:
            formatName = L10n.t("中国香港", "Hong Kong", language: lang)
        }
        let copyName = profile == .reader
            ? L10n.t("阅读版", "Reader Copy", language: lang)
            : L10n.t("制片版", "Production Copy", language: lang)
        panel.title = L10n.t(
            "导出\(formatName)剧本 · \(copyName)",
            "Export \(formatName) Screenplay · \(copyName)",
            language: lang
        )
        panel.allowedContentTypes = [.pdf]
        let formatSuffix: String
        switch screenplayFormat {
        case .international: formatSuffix = L10n.t("国际", "international", language: lang)
        case .mainlandChina: formatSuffix = L10n.t("中国大陆", "mainland-cn", language: lang)
        case .hongKong: formatSuffix = L10n.t("中国香港", "hong-kong", language: lang)
        }
        let copySuffix = profile == .reader
            ? L10n.t("阅读版", "reader", language: lang)
            : L10n.t("制片版", "production", language: lang)
        panel.nameFieldStringValue = "\(safeFileName(store.document.title))-\(formatSuffix)-\(copySuffix).pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.errorMessage = nil
        store.exportPDF(
            to: url,
            profile: profile,
            screenplayFormat: screenplayFormat
        )
        showDeliveryResult(L10n.t("PDF 已导出", "PDF export complete", language: lang))
    }

    private func showDeliveryResult(_ successMessage: String) {
        guard store.errorMessage == nil else { return }
        let warnings = store.exportWarnings
        guard !warnings.isEmpty else {
            exportNotice = successMessage
            return
        }
        let preview = warnings.prefix(3).joined(separator: "\n")
        let remainder = max(0, warnings.count - 3)
        let remainderText = remainder == 0
            ? ""
            : L10n.t("\n另有 \(remainder) 条提醒", "\n\(remainder) more notes", language: lang)
        exportNotice = L10n.t(
            "\(successMessage)，有 \(warnings.count) 条兼容性提醒：\n\(preview)\(remainderText)",
            "\(successMessage) with \(warnings.count) compatibility notes:\n\(preview)\(remainderText)",
            language: lang
        )
    }

    private func focusSearchResult(_ result: ScriptWorkshopSearchResult) {
        store.focus(result)
        mode = .page
        searchIsPresented = false
    }

    private func revisionColor(_ color: ScriptWorkshopRevisionColor) -> Color {
        switch color {
        case .white: return Color(white: 0.90)
        case .blue: return Color(red: 0.36, green: 0.61, blue: 0.92)
        case .pink: return Color(red: 0.94, green: 0.48, blue: 0.67)
        case .yellow: return Color(red: 0.95, green: 0.78, blue: 0.23)
        case .green: return Color(red: 0.31, green: 0.70, blue: 0.43)
        case .goldenrod: return Color(red: 0.80, green: 0.57, blue: 0.15)
        case .buff: return Color(red: 0.76, green: 0.65, blue: 0.43)
        case .salmon: return Color(red: 0.93, green: 0.45, blue: 0.37)
        case .cherry: return Color(red: 0.72, green: 0.20, blue: 0.34)
        case .tan: return Color(red: 0.63, green: 0.50, blue: 0.38)
        }
    }

    private func sceneStatusColor(_ status: ScriptWorkshopSceneStatus) -> Color {
        switch status {
        case .idea: return colors.textTertiary
        case .outline: return Color(red: 0.31, green: 0.56, blue: 0.89)
        case .draft: return Color(red: 0.41, green: 0.48, blue: 0.60)
        case .revised: return Color(red: 0.90, green: 0.54, blue: 0.20)
        case .locked: return Color(red: 0.25, green: 0.67, blue: 0.43)
        case .omitted: return Color(red: 0.78, green: 0.28, blue: 0.31)
        }
    }

    private func sceneStatusLabel(_ status: ScriptWorkshopSceneStatus) -> String {
        switch status {
        case .idea: return L10n.t("想法", "Idea", language: lang)
        case .outline: return L10n.t("大纲", "Outline", language: lang)
        case .draft: return L10n.t("草稿", "Draft", language: lang)
        case .revised: return L10n.t("已修订", "Revised", language: lang)
        case .locked: return L10n.t("已锁定", "Locked", language: lang)
        case .omitted: return L10n.t("已省略", "Omitted", language: lang)
        }
    }

    private func actLabel(_ act: ScriptWorkshopAct) -> String {
        switch act {
        case .unassigned: return L10n.t("待分幕", "Unassigned", language: lang)
        case .actOne: return L10n.t("第一幕", "Act One", language: lang)
        case .actTwo: return L10n.t("第二幕", "Act Two", language: lang)
        case .actThree: return L10n.t("第三幕", "Act Three", language: lang)
        case .epilogue: return L10n.t("尾声", "Epilogue", language: lang)
        }
    }

    private var scriptPaperColor: Color {
        Color(nsColor: .textBackgroundColor)
    }

    private func beatTextBinding(
        _ beatID: UUID,
        keyPath: WritableKeyPath<ScriptWorkshopBeat, String>
    ) -> Binding<String> {
        Binding(
            get: {
                store.document.workspace?.beats
                    .first(where: { $0.id == beatID })?[keyPath: keyPath] ?? ""
            },
            set: { value in
                guard var beat = store.document.workspace?.beats.first(where: { $0.id == beatID }) else {
                    return
                }
                beat[keyPath: keyPath] = value
                store.updateBeat(beat)
            }
        )
    }

    private var effectiveDialogueCharacter: String {
        if store.document.allCharacters.contains(dialogueCharacter) {
            return dialogueCharacter
        }
        return store.document.allCharacters.first ?? ""
    }

    private func dialogueTextBinding(_ line: ScriptWorkshopDialogueLine) -> Binding<String> {
        Binding(
            get: {
                store.document.scenes
                    .first(where: { $0.id == line.sceneID })?
                    .blocks.first(where: { $0.id == line.blockID })?
                    .text ?? line.text
            },
            set: {
                store.updateBlockText(sceneID: line.sceneID, blockID: line.blockID, value: $0)
            }
        )
    }

    private func dialogueEditorHeight(_ text: String) -> CGFloat {
        let explicitLines = text.components(separatedBy: .newlines).count
        let wrappedLines = text.count / 62
        return CGFloat(max(3, explicitLines + wrappedLines)) * 20 + 16
    }

    private func syncSceneTagsDraft() {
        sceneTagsDraft = (store.selectedScene?.metadata?.tags ?? []).joined(separator: ", ")
    }

    private func commitSceneTags() {
        guard let sceneID = store.selectedSceneID else { return }
        let separators = CharacterSet(charactersIn: ",，\n")
        let tags = sceneTagsDraft.components(separatedBy: separators)
        store.updateSceneTags(sceneID, tags: tags)
        syncSceneTagsDraft()
    }

    private var snapshotName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return L10n.t("版本 \(formatter.string(from: Date()))", "Version \(formatter.string(from: Date()))", language: lang)
    }

    private func safeFileName(_ value: String) -> String {
        let sanitized = value.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:"))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? L10n.t("未命名剧本", "Untitled Screenplay", language: lang) : sanitized
    }
}

private struct ScriptWorkshopBlockRow: View {
    @State private var isComposing = false
    @State private var measuredEditorHeight: CGFloat = 0

    let block: ScriptWorkshopBlock
    let isFocused: Bool
    let language: AppLanguage
    let colors: ThemeColors
    let accent: ToolAccent
    let updateText: (String) -> Void
    let updateKind: (ScriptWorkshopBlockKind) -> Void
    let focus: () -> Void
    let advance: (ScriptWorkshopAdvanceTrigger, Int) -> Void
    let wheelEvent: (ScriptWorkshopWheelEvent) -> Void
    let wheelCoordinates: ScriptWorkshopWheelCoordinateConverter
    let undo: () -> Void
    let redo: () -> Void
    let mergeBackward: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Menu {
                ForEach(ScriptWorkshopBlockKind.allCases) { kind in
                    Button(label(kind)) { updateKind(kind) }
                }
                Divider()
                Button(L10n.t("删除段落", "Delete Block", language: language), role: .destructive, action: delete)
            } label: {
                Text(shortLabel(block.kind))
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isFocused ? Color.white : colors.textTertiary)
                    .frame(width: 34, height: 22)
                    .background(isFocused ? accent.primary : colors.inputBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 36)

            HStack {
                if leadingIndent > 0 { Spacer().frame(width: leadingIndent) }
                ZStack(alignment: .topLeading) {
                    if block.text.isEmpty, !isComposing {
                        Text(placeholder)
                            .font(editorFont)
                            .foregroundStyle(colors.textTertiary.opacity(0.75))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 7)
                            .allowsHitTesting(false)
                    }
                    ScriptWorkshopBlockTextView(
                        text: block.text,
                        kind: block.kind,
                        isFocused: isFocused,
                        focus: focus,
                        update: updateText,
                        advance: advance,
                        wheelEvent: wheelEvent,
                        wheelCoordinates: wheelCoordinates,
                        undo: undo,
                        redo: redo,
                        mergeBackward: mergeBackward,
                        compositionChanged: { isComposing = $0 },
                        measuredHeightChanged: { measuredEditorHeight = $0 }
                    )
                    .frame(height: editorHeight)
                }
                .frame(width: editorWidth)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 5)
            .background(isFocused ? accent.primary.opacity(0.055) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(.vertical, block.kind == .character ? 6 : 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: focus)
    }

    private var leadingIndent: CGFloat {
        switch block.kind {
        case .character: return 205
        case .dialogue: return 142
        case .parenthetical: return 184
        case .transition: return 340
        default: return 0
        }
    }

    private var editorWidth: CGFloat {
        switch block.kind {
        case .character: return 300
        case .dialogue: return 385
        case .parenthetical: return 320
        case .transition: return 280
        default: return 650
        }
    }

    private var editorHeight: CGFloat {
        let minimum: CGFloat = block.kind == .character ? 38 : 28
        return max(minimum, measuredEditorHeight)
    }

    private var editorFont: Font {
        .system(size: 13.5, weight: block.kind == .character || block.kind == .transition ? .semibold : .regular, design: .monospaced)
    }

    private var placeholder: String {
        switch block.kind {
        case .action: return L10n.t("描述可见、可听见的动作……", "Describe visible, audible action…", language: language)
        case .character: return L10n.t("人物名", "CHARACTER", language: language)
        case .dialogue: return L10n.t("对白……", "Dialogue…", language: language)
        case .parenthetical: return L10n.t("（语气或动作）", "(delivery or action)", language: language)
        case .transition: return L10n.t("切至：", "CUT TO:", language: language)
        case .shot: return L10n.t("镜头提示", "SHOT", language: language)
        case .note: return L10n.t("仅作者可见，不进入正式输出", "Writer note, excluded from final output", language: language)
        }
    }

    private func label(_ kind: ScriptWorkshopBlockKind) -> String {
        switch kind {
        case .action: return L10n.t("动作", "Action", language: language)
        case .character: return L10n.t("人物", "Character", language: language)
        case .dialogue: return L10n.t("对白", "Dialogue", language: language)
        case .parenthetical: return L10n.t("括号说明", "Parenthetical", language: language)
        case .transition: return L10n.t("转场", "Transition", language: language)
        case .shot: return L10n.t("镜头提示", "Shot", language: language)
        case .note: return L10n.t("作者笔记", "Note", language: language)
        }
    }

    private func shortLabel(_ kind: ScriptWorkshopBlockKind) -> String {
        switch kind {
        case .action: return L10n.t("动作", "ACT", language: language)
        case .character: return L10n.t("人物", "CHAR", language: language)
        case .dialogue: return L10n.t("对白", "DIA", language: language)
        case .parenthetical: return L10n.t("括号", "PAR", language: language)
        case .transition: return L10n.t("转场", "TRANS", language: language)
        case .shot: return L10n.t("镜头", "SHOT", language: language)
        case .note: return L10n.t("笔记", "NOTE", language: language)
        }
    }
}

private struct ScriptWorkshopBlockTextView: NSViewRepresentable {
    let text: String
    let kind: ScriptWorkshopBlockKind
    let isFocused: Bool
    let focus: () -> Void
    let update: (String) -> Void
    let advance: (ScriptWorkshopAdvanceTrigger, Int) -> Void
    let wheelEvent: (ScriptWorkshopWheelEvent) -> Void
    let wheelCoordinates: ScriptWorkshopWheelCoordinateConverter
    let undo: () -> Void
    let redo: () -> Void
    let mergeBackward: () -> Void
    let compositionChanged: (Bool) -> Void
    let measuredHeightChanged: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = ScriptWorkshopNativeTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 3, height: 5)
        textView.string = text
        textView.identifier = ScriptWorkshopEditorIdentity.blockEditor
        textView.onFocus = focus
        textView.onAdvance = advance
        textView.onWheelEvent = wheelEvent
        textView.wheelCoordinates = wheelCoordinates
        textView.onUndo = undo
        textView.onRedo = redo
        textView.onMergeBackward = mergeBackward
        textView.onCompositionChanged = compositionChanged
        applyStyle(to: textView)
        scrollView.documentView = textView
        context.coordinator.scheduleMeasurement(of: textView, in: scrollView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ScriptWorkshopNativeTextView else { return }
        context.coordinator.parent = self
        textView.onFocus = focus
        textView.onAdvance = advance
        textView.onWheelEvent = wheelEvent
        textView.wheelCoordinates = wheelCoordinates
        textView.onUndo = undo
        textView.onRedo = redo
        textView.onMergeBackward = mergeBackward
        textView.onCompositionChanged = compositionChanged
        applyStyle(to: textView)

        if textView.string != text, !textView.hasMarkedText() {
            let previousText = textView.string
            let range = textView.selectedRange()
            textView.string = text
            let location = ScriptWorkshopCaretPolicy.locationAfterExternalUpdate(
                previousText: previousText,
                newText: text,
                currentUTF16Location: range.location,
                isFocused: isFocused
            )
            textView.setSelectedRange(NSRange(location: location, length: 0))
        }
        context.coordinator.scheduleMeasurement(of: textView, in: scrollView)
        if !isFocused {
            context.coordinator.hasRequestedFocus = false
        } else if !context.coordinator.hasRequestedFocus,
           textView.window != nil,
           textView.window?.firstResponder !== textView,
           !textView.hasMarkedText() {
            context.coordinator.hasRequestedFocus = true
            DispatchQueue.main.async { [weak textView] in
                guard let textView else { return }
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: textView.string.utf16.count, length: 0))
            }
        }
    }

    private func applyStyle(to textView: NSTextView) {
        textView.font = .monospacedSystemFont(
            ofSize: 13.5,
            weight: kind == .character || kind == .transition ? .semibold : .regular
        )
        textView.textColor = kind == .note ? .secondaryLabelColor : .labelColor
        textView.alignment = kind == .transition ? .right : .left
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScriptWorkshopBlockTextView
        var hasRequestedFocus = false
        private var lastMeasuredHeight: CGFloat = 0

        init(parent: ScriptWorkshopBlockTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.focus()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let isComposing = textView.hasMarkedText()
            parent.compositionChanged(isComposing)
            if let scrollView = textView.enclosingScrollView {
                scheduleMeasurement(of: textView, in: scrollView)
            }
            guard !isComposing else { return }
            parent.update(textView.string)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.compositionChanged(false)
            guard let textView = notification.object as? NSTextView,
                  !textView.hasMarkedText(),
                  textView.string != parent.text else { return }
            parent.update(textView.string)
        }

        func scheduleMeasurement(of textView: NSTextView, in scrollView: NSScrollView) {
            DispatchQueue.main.async { [weak self, weak textView, weak scrollView] in
                guard let self, let textView, let scrollView else { return }
                self.measure(textView, in: scrollView)
            }
        }

        private func measure(_ textView: NSTextView, in scrollView: NSScrollView) {
            let width = scrollView.contentSize.width
            guard width > 20 else { return }
            if abs(textView.frame.width - width) > 0.5 {
                textView.setFrameSize(NSSize(width: width, height: max(1, textView.frame.height)))
            }
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            let measured = ceil(max(28, usedHeight + textView.textContainerInset.height * 2))
            if abs(textView.frame.height - measured) > 0.5 {
                textView.setFrameSize(NSSize(width: width, height: measured))
            }
            guard abs(lastMeasuredHeight - measured) > 0.5 else { return }
            lastMeasuredHeight = measured
            parent.measuredHeightChanged(measured)
        }
    }
}

private final class ScriptWorkshopNativeTextView: NSTextView {
    var onFocus: (() -> Void)?
    var onAdvance: ((ScriptWorkshopAdvanceTrigger, Int) -> Void)?
    var onWheelEvent: ((ScriptWorkshopWheelEvent) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onMergeBackward: (() -> Void)?
    var onCompositionChanged: ((Bool) -> Void)?
    weak var wheelCoordinates: ScriptWorkshopWheelCoordinateConverter?

    private var tabGesture = ScriptWorkshopTabHoldGesture()
    private var tabHoldWork: DispatchWorkItem?
    private var pointerMonitor: Any?

    deinit {
        tabHoldWork?.cancel()
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
        }
    }

    override func mouseDown(with event: NSEvent) {
        cancelTabTracking()
        super.mouseDown(with: event)
        onFocus?()
    }

    override func resignFirstResponder() -> Bool {
        cancelTabTracking()
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelTabTracking()
        } else {
            window?.acceptsMouseMovedEvents = true
        }
    }

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        super.setMarkedText(
            string,
            selectedRange: selectedRange,
            replacementRange: replacementRange
        )
        onCompositionChanged?(hasMarkedText())
    }

    override func unmarkText() {
        super.unmarkText()
        onCompositionChanged?(false)
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(insertTab(_:))
            || selector == #selector(insertBacktab(_:)) {
            // Key events are handled by the native Tab hold state machine.
            // NSTextView must never insert a literal tab through the text-input
            // command path.
            return
        }
        super.doCommand(by: selector)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 {
            guard !hasDisallowedTabModifiers(event) else {
                cancelTabTracking()
                return
            }
            switch tabGesture.keyDown(
                isRepeat: event.isARepeat,
                hasMarkedText: hasMarkedText()
            ) {
            case .armHold:
                armTabHold()
            case .cancelWheelAndConsume:
                cancelPendingTabWork()
                stopPointerMonitor()
                onWheelEvent?(.cancelled)
            case .passThrough, .consume:
                break
            }
            return
        }

        if tabGesture.phase != .idle {
            cancelTabTracking()
        }

        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            if modifiers.contains(.shift) {
                onRedo?()
            } else {
                onUndo?()
            }
            return
        }

        if event.keyCode == 51 {
            let selection = selectedRange()
            if selection.location == 0, selection.length == 0 {
                onMergeBackward?()
                return
            }
        }

        if event.keyCode == 36 || event.keyCode == 76 {
            if modifiers.contains(.shift) {
                insertNewlineIgnoringFieldEditor(self)
            } else {
                onAdvance?(.returnKey, selectedRange().location)
            }
            return
        }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        guard event.keyCode == 48 else {
            super.keyUp(with: event)
            return
        }
        guard !hasDisallowedTabModifiers(event) else {
            cancelTabTracking()
            return
        }

        let disposition = tabGesture.keyUp(hasMarkedText: hasMarkedText())
        cancelPendingTabWork()
        stopPointerMonitor()
        switch disposition {
        case .shortPress:
            onAdvance?(.tab, selectedRange().location)
        case .endWheel:
            onWheelEvent?(.ended(currentWheelPoint()))
        case .cancelWheelAndConsume:
            onWheelEvent?(.cancelled)
        case .passThrough, .consume:
            break
        }
    }

    override func flagsChanged(with event: NSEvent) {
        if tabGesture.phase != .idle, hasDisallowedTabModifiers(event) {
            cancelTabTracking()
        }
        super.flagsChanged(with: event)
    }

    private func armTabHold() {
        cancelPendingTabWork()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.tabHoldWork = nil
            if self.tabGesture.holdThresholdReached(
                hasMarkedText: self.hasMarkedText()
            ) == .beginWheel {
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .alignment,
                    performanceTime: .now
                )
                self.startPointerMonitor()
                self.onWheelEvent?(.began(self.currentWheelPoint()))
            }
        }
        tabHoldWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + ScriptWorkshopTabHoldGesture.holdDuration,
            execute: work
        )
    }

    private func startPointerMonitor() {
        stopPointerMonitor()
        pointerMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .mouseMoved,
                .leftMouseDragged,
                .rightMouseDragged,
                .leftMouseDown,
                .rightMouseDown
            ]
        ) { [weak self] incoming in
            guard let self, incoming.window === self.window else { return incoming }
            switch incoming.type {
            case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
                guard self.tabGesture.phase == .wheel, !self.hasMarkedText() else {
                    self.cancelTabTracking()
                    return incoming
                }
                self.onWheelEvent?(.moved(self.currentWheelPoint()))
            case .leftMouseDown, .rightMouseDown:
                self.cancelTabTracking()
            default:
                break
            }
            return incoming
        }
    }

    private func stopPointerMonitor() {
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
        }
        pointerMonitor = nil
    }

    private func cancelPendingTabWork() {
        tabHoldWork?.cancel()
        tabHoldWork = nil
    }

    private func cancelTabTracking() {
        cancelPendingTabWork()
        stopPointerMonitor()
        if tabGesture.cancel() {
            onWheelEvent?(.cancelled)
        }
    }

    private func currentWheelPoint() -> CGPoint {
        guard let window else { return .zero }
        let windowPoint = window.mouseLocationOutsideOfEventStream
        if let point = wheelCoordinates?.localPoint(from: windowPoint, in: window) {
            return point
        }
        guard let contentView = window.contentView else { return .zero }
        return contentView.convert(windowPoint, from: nil)
    }

    private func hasDisallowedTabModifiers(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return !modifiers.intersection([.command, .control, .option]).isEmpty
    }
}

private struct FlowingTagLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 240
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
