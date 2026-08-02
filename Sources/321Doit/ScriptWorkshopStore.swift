import Combine
import Foundation

enum ScriptWorkshopSaveState: Equatable {
    case saved(Date)
    case unsaved
    case failed(String)
}

struct ScriptWorkshopSearchResult: Identifiable, Equatable {
    var id: String
    var sceneID: UUID
    var blockID: UUID?
    var sceneHeading: String
    var excerpt: String
    var kind: ScriptWorkshopBlockKind?
}

struct ScriptWorkshopDialogueLine: Identifiable, Equatable {
    var id: UUID { blockID }
    var sceneID: UUID
    var blockID: UUID
    var sceneNumber: String
    var sceneHeading: String
    var text: String
}

@MainActor
final class ScriptWorkshopStore: ObservableObject {
    @Published private(set) var document: ScriptWorkshopDocument
    @Published var selectedSceneID: UUID?
    @Published var selectedBlockID: UUID?
    @Published private(set) var saveState: ScriptWorkshopSaveState = .saved(Date())
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var exportWarnings: [String] = []
    @Published var errorMessage: String?

    private var commandBus: ScriptWorkshopCommandBus
    private var destinationURL: URL?
    private var pendingSave: DispatchWorkItem?
    private var lastPersistedRevision = 0
    private var lastLinkedProjectTitle: String?

    init() {
        var initial = ScriptWorkshopDocument()
        initial.migrateToCurrentSchema()
        document = initial
        commandBus = try! ScriptWorkshopCommandBus(document: initial)
        selectedSceneID = initial.scenes.first?.id
        selectedBlockID = initial.scenes.first?.blocks.first?.id
    }

    var selectedScene: ScriptWorkshopScene? {
        document.scenes.first { $0.id == selectedSceneID }
    }

    var activeRevisionSet: ScriptWorkshopRevisionSet? {
        document.activeRevisionSet
    }

    func configure(linkedProjectID: UUID?, projectFolderURL: URL?, title: String?) {
        let destination: URL
        if let projectFolderURL {
            destination = ScriptWorkshopRepository.documentURL(for: projectFolderURL)
        } else {
            destination = IndependentWorkspacePersistence.scriptWorkshopFolderURL
                .appendingPathComponent("script_workshop.json")
        }
        if destinationURL?.standardizedFileURL == destination.standardizedFileURL {
            if projectFolderURL != nil {
                synchronizeLinkedProjectTitle(title)
            }
            return
        }
        flushPendingSave()
        destinationURL = destination

        do {
            var loaded: ScriptWorkshopDocument
            if FileManager.default.fileExists(atPath: destination.path) {
                loaded = try ScriptWorkshopRepository.load(from: destination)
                var identityChanged = false
                if let linkedProjectID, loaded.linkedProjectID != linkedProjectID {
                    loaded.linkedProjectID = linkedProjectID
                    identityChanged = true
                }
                if let linkedTitle = normalizedLinkedProjectTitle(title),
                   isPlaceholderTitle(loaded.title) {
                    loaded.title = linkedTitle
                    identityChanged = true
                }
                if identityChanged {
                    loaded.advanceDocumentRevision()
                    try ScriptWorkshopRepository.save(loaded, to: destination)
                }
            } else {
                loaded = ScriptWorkshopDocument(
                    linkedProjectID: linkedProjectID,
                    title: normalizedTitle(title)
                )
                try ScriptWorkshopRepository.save(loaded, to: destination)
            }
            lastLinkedProjectTitle = projectFolderURL == nil
                ? nil
                : normalizedLinkedProjectTitle(title)
            commandBus = try ScriptWorkshopCommandBus(document: loaded)
            lastPersistedRevision = commandBus.document.documentRevision
            publish()
            repairSelection()
        } catch {
            // Never replace a damaged screenplay with an empty one. Keep the
            // current in-memory document read-only until the user resolves it.
            saveState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func synchronizeLinkedProjectTitle(_ title: String?) {
        guard destinationURL != nil, document.linkedProjectID != nil else { return }
        guard let linkedTitle = normalizedLinkedProjectTitle(title) else { return }
        let previousLinkedTitle = lastLinkedProjectTitle
        lastLinkedProjectTitle = linkedTitle
        let current = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isPlaceholderTitle(current) || current == previousLinkedTitle else { return }
        guard current != linkedTitle else { return }
        _ = perform(
            title: "Sync screenplay title from project",
            coalescingKey: "document.title.projectSync",
            mutations: [.setDocumentTitle(linkedTitle)]
        )
    }

    func reload() {
        guard let destinationURL else { return }
        guard saveState != .unsaved else {
            errorMessage = "Local screenplay edits are still pending. Save or undo them before reloading an external change."
            return
        }
        do {
            let loaded = try ScriptWorkshopRepository.load(from: destinationURL)
            commandBus = try ScriptWorkshopCommandBus(document: loaded)
            lastPersistedRevision = loaded.documentRevision
            publish()
            repairSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTitle(_ title: String) {
        perform(
            title: "Edit screenplay title",
            coalescingKey: "document.title",
            mutations: [.setDocumentTitle(title)]
        )
    }

    func updateAuthor(_ author: String) {
        perform(
            title: "Edit screenplay author",
            coalescingKey: "document.author",
            mutations: [.setDocumentAuthor(author)]
        )
    }

    func updateLogline(_ value: String) {
        updateWorkspace(title: "Edit logline", coalescingKey: "document.logline") {
            $0.logline = value
        }
    }

    func updateGenre(_ value: String) {
        updateWorkspace(title: "Edit genre", coalescingKey: "document.genre") {
            $0.genre = value
        }
    }

    func updateTargetPageCount(_ value: Int) {
        updateWorkspace(title: "Set target page count") {
            $0.targetPageCount = min(max(value, 1), 999)
        }
    }

    func addScene(after sceneID: UUID? = nil) {
        let scene = ScriptWorkshopScene()
        let index = sceneID.flatMap { target in
            document.scenes.firstIndex(where: { $0.id == target }).map { $0 + 1 }
        } ?? document.scenes.count
        guard perform(title: "Add scene", mutations: [.addScene(scene: scene, index: index)]) else {
            return
        }
        selectedSceneID = scene.id
        selectedBlockID = scene.blocks.first?.id
        renumberUnlockedScenes()
    }

    func deleteScene(_ sceneID: UUID) {
        guard let scene = document.scenes.first(where: { $0.id == sceneID }) else { return }
        var workspace = document.workspace ?? ScriptWorkshopWorkspaceData()
        workspace.boneyard.append(contentsOf: scene.blocks.map {
            ScriptWorkshopBoneyardItem(
                sourceSceneID: scene.id,
                sourceSceneHeading: scene.heading,
                block: $0,
                note: "Deleted with scene"
            )
        })
        let mutations: [ScriptWorkshopMutation]
        if document.scenes.count == 1 {
            let replacement = ScriptWorkshopScene()
            mutations = [
                .setWorkspace(workspace),
                .updateScene(sceneID: sceneID, scene: replacementWithID(replacement, id: sceneID))
            ]
        } else {
            mutations = [.setWorkspace(workspace), .removeScene(sceneID: sceneID)]
        }
        guard perform(title: "Delete scene", mutations: mutations) else { return }
        repairSelection()
        renumberUnlockedScenes()
    }

    func moveScene(fromOffsets: IndexSet, toOffset: Int) {
        guard let source = fromOffsets.first,
              document.scenes.indices.contains(source) else { return }
        moveScene(document.scenes[source].id, to: toOffset > source ? toOffset - 1 : toOffset)
    }

    func moveScene(_ sceneID: UUID, offset: Int) {
        guard let source = document.scenes.firstIndex(where: { $0.id == sceneID }) else { return }
        moveScene(sceneID, to: min(max(0, source + offset), document.scenes.count - 1))
    }

    func moveScene(_ sceneID: UUID, to destination: Int) {
        guard perform(
            title: "Move scene",
            mutations: [.moveScene(sceneID: sceneID, destination: destination)]
        ) else { return }
        renumberUnlockedScenes()
    }

    func updateSceneHeading(_ sceneID: UUID, value: String) {
        updateScene(
            sceneID,
            title: "Edit scene heading",
            coalescingKey: "scene.\(sceneID).heading"
        ) { $0.heading = value }
    }

    func updateSceneSynopsis(_ sceneID: UUID, value: String) {
        updateScene(
            sceneID,
            title: "Edit scene synopsis",
            coalescingKey: "scene.\(sceneID).synopsis"
        ) { $0.synopsis = value }
    }

    func updateSceneStatus(_ sceneID: UUID, status: ScriptWorkshopSceneStatus) {
        updateScene(sceneID, title: "Change scene status") {
            if $0.metadata == nil { $0.metadata = ScriptWorkshopSceneMetadata() }
            $0.metadata?.status = status
        }
    }

    func updateSceneAct(_ sceneID: UUID, act: ScriptWorkshopAct) {
        updateScene(sceneID, title: "Move scene to act") {
            if $0.metadata == nil { $0.metadata = ScriptWorkshopSceneMetadata() }
            $0.metadata?.act = act
        }
    }

    func updateSceneTags(_ sceneID: UUID, tags: [String]) {
        updateScene(sceneID, title: "Edit scene tags") {
            if $0.metadata == nil { $0.metadata = ScriptWorkshopSceneMetadata() }
            $0.metadata?.tags = Array(Set(tags.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty })).sorted()
        }
    }

    func selectScene(_ sceneID: UUID) {
        selectedSceneID = sceneID
        selectedBlockID = document.scenes.first(where: { $0.id == sceneID })?.blocks.first?.id
    }

    func selectBlock(_ blockID: UUID) {
        selectedBlockID = blockID
    }

    func updateBlockText(sceneID: UUID, blockID: UUID, value: String) {
        updateBlock(
            sceneID: sceneID,
            blockID: blockID,
            title: "Edit screenplay text",
            coalescingKey: "block.\(blockID).text"
        ) {
            $0.text = value
            markActiveRevision(on: &$0)
        }
    }

    func updateBlockKind(sceneID: UUID, blockID: UUID, kind: ScriptWorkshopBlockKind) {
        updateBlock(sceneID: sceneID, blockID: blockID, title: "Change screenplay element") {
            $0.kind = kind
            markActiveRevision(on: &$0)
        }
    }

    func advance(sceneID: UUID, from blockID: UUID, trigger: ScriptWorkshopAdvanceTrigger) {
        guard let sceneIndex = document.scenes.firstIndex(where: { $0.id == sceneID }),
              let blockIndex = document.scenes[sceneIndex].blocks.firstIndex(where: { $0.id == blockID }) else {
            return
        }
        let current = document.scenes[sceneIndex].blocks[blockIndex]
        let kind = current.kind.nextKind(for: trigger)
        if trigger == .tab,
           current.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updateBlockKind(sceneID: sceneID, blockID: blockID, kind: kind)
            selectedBlockID = blockID
            return
        }
        var block = ScriptWorkshopBlock(kind: kind)
        markActiveRevision(on: &block)
        guard perform(
            title: "Add screenplay block",
            source: .keyboard,
            mutations: [.addBlock(sceneID: sceneID, block: block, index: blockIndex + 1)]
        ) else { return }
        selectedBlockID = block.id
    }

    func splitBlock(
        sceneID: UUID,
        blockID: UUID,
        utf16Offset: Int,
        trigger: ScriptWorkshopAdvanceTrigger
    ) {
        guard let sceneIndex = document.scenes.firstIndex(where: { $0.id == sceneID }),
              let blockIndex = document.scenes[sceneIndex].blocks.firstIndex(where: { $0.id == blockID }) else {
            return
        }
        var current = document.scenes[sceneIndex].blocks[blockIndex]
        if let nextKind = ScriptWorkshopEmptyAdvancePolicy.replacementKind(
            currentKind: current.kind,
            text: current.text,
            trigger: trigger
        ) {
            if current.kind != nextKind {
                updateBlockKind(
                    sceneID: sceneID,
                    blockID: blockID,
                    kind: nextKind
                )
            }
            selectedBlockID = blockID
            return
        }
        let source = current.text as NSString
        let safeOffset = min(max(utf16Offset, 0), source.length)
        let before = source.substring(with: NSRange(location: 0, length: safeOffset))
        let after = source.substring(from: safeOffset)
        current.text = before
        current.updatedAt = Date()
        markActiveRevision(on: &current)
        var following = ScriptWorkshopBlock(
            kind: current.kind.nextKind(for: trigger),
            text: after.trimmingCharacters(in: .newlines)
        )
        markActiveRevision(on: &following)
        guard perform(
            title: "Split screenplay block",
            source: .keyboard,
            mutations: [
                .updateBlock(sceneID: sceneID, blockID: blockID, block: current),
                .addBlock(sceneID: sceneID, block: following, index: blockIndex + 1)
            ]
        ) else { return }
        selectedBlockID = following.id
    }

    func mergeBlockBackward(sceneID: UUID, blockID: UUID) {
        guard let sceneIndex = document.scenes.firstIndex(where: { $0.id == sceneID }),
              let blockIndex = document.scenes[sceneIndex].blocks.firstIndex(where: {
                  $0.id == blockID
              }),
              blockIndex > 0 else {
            return
        }
        let current = document.scenes[sceneIndex].blocks[blockIndex]
        var previous = document.scenes[sceneIndex].blocks[blockIndex - 1]
        let separator = previous.text.isEmpty || current.text.isEmpty ? "" : "\n"
        previous.text += separator + current.text
        previous.updatedAt = Date()
        markActiveRevision(on: &previous)
        guard perform(
            title: "Merge screenplay blocks",
            source: .keyboard,
            mutations: [
                .updateBlock(
                    sceneID: sceneID,
                    blockID: previous.id,
                    block: previous
                ),
                .removeBlock(sceneID: sceneID, blockID: current.id)
            ]
        ) else {
            return
        }
        selectedBlockID = previous.id
    }

    func addBlock(sceneID: UUID, kind: ScriptWorkshopBlockKind) {
        var block = ScriptWorkshopBlock(kind: kind)
        markActiveRevision(on: &block)
        guard perform(
            title: "Add screenplay block",
            mutations: [.addBlock(sceneID: sceneID, block: block, index: nil)]
        ) else { return }
        selectedBlockID = block.id
    }

    func applyWheelSelection(
        _ kind: ScriptWorkshopBlockKind,
        text: String? = nil,
        ensureCharacterProfile: Bool = false,
        sceneID requestedSceneID: UUID? = nil,
        blockID requestedBlockID: UUID? = nil
    ) {
        guard let sceneID = requestedSceneID ?? selectedSceneID,
              let sceneIndex = document.scenes.firstIndex(where: { $0.id == sceneID }) else {
            return
        }

        let targetBlockID = requestedBlockID
            ?? (sceneID == selectedSceneID ? selectedBlockID : nil)
        let placement = ScriptWorkshopWheelSafety.placement(
            in: document.scenes[sceneIndex],
            targetBlockID: targetBlockID
        )

        let normalizedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        var sharedMutations: [ScriptWorkshopMutation] = []
        if ensureCharacterProfile,
           kind == .character,
           let normalizedText,
           !normalizedText.isEmpty {
            var workspace = document.workspace ?? ScriptWorkshopWorkspaceData()
            let key = normalizedCharacterName(normalizedText)
            if !workspace.characterProfiles.contains(where: {
                normalizedCharacterName($0.name) == key
            }) {
                workspace.characterProfiles.append(
                    ScriptWorkshopCharacterProfile(name: normalizedText)
                )
                sharedMutations.append(.setWorkspace(workspace))
            }
        }

        switch placement {
        case .append:
            var block = ScriptWorkshopBlock(kind: kind, text: normalizedText ?? "")
            markActiveRevision(on: &block)
            guard perform(
                title: "Insert screenplay element from creation wheel",
                source: .wheel,
                mutations: sharedMutations + [
                    .addBlock(sceneID: sceneID, block: block, index: nil)
                ]
            ) else { return }
            selectedBlockID = block.id

        case .changeEmpty(let blockID, let blockIndex):
            var current = document.scenes[sceneIndex].blocks[blockIndex]
            let nextText = normalizedText ?? current.text
            guard current.kind != kind
                    || current.text != nextText
                    || !sharedMutations.isEmpty else { return }
            current.kind = kind
            current.text = nextText
            current.updatedAt = Date()
            markActiveRevision(on: &current)
            guard perform(
                title: "Change empty screenplay element from creation wheel",
                source: .wheel,
                mutations: sharedMutations + [
                    .updateBlock(sceneID: sceneID, blockID: blockID, block: current)
                ]
            ) else { return }
            selectedBlockID = blockID

        case .insertAfter(_, let insertionIndex):
            // A radial-menu gesture must never silently reinterpret written
            // text. Insert a fresh element after the captured target instead.
            var inserted = ScriptWorkshopBlock(kind: kind, text: normalizedText ?? "")
            markActiveRevision(on: &inserted)
            guard perform(
                title: "Insert screenplay element from creation wheel",
                source: .wheel,
                mutations: sharedMutations + [
                    .addBlock(sceneID: sceneID, block: inserted, index: insertionIndex)
                ]
            ) else { return }
            selectedBlockID = inserted.id
        }
    }

    func deleteBlock(sceneID: UUID, blockID: UUID) {
        guard let scene = document.scenes.first(where: { $0.id == sceneID }),
              let deletedIndex = scene.blocks.firstIndex(where: { $0.id == blockID }) else { return }
        let block = scene.blocks[deletedIndex]
        var workspace = document.workspace ?? ScriptWorkshopWorkspaceData()
        workspace.boneyard.append(ScriptWorkshopBoneyardItem(
            sourceSceneID: sceneID,
            sourceSceneHeading: scene.heading,
            block: block
        ))
        let mutations: [ScriptWorkshopMutation]
        if scene.blocks.count == 1 {
            var replacement = ScriptWorkshopBlock(kind: .action)
            replacement.id = blockID
            mutations = [
                .setWorkspace(workspace),
                .updateBlock(sceneID: sceneID, blockID: blockID, block: replacement)
            ]
        } else {
            mutations = [
                .setWorkspace(workspace),
                .removeBlock(sceneID: sceneID, blockID: blockID)
            ]
        }
        guard perform(title: "Move block to boneyard", mutations: mutations) else { return }
        guard let remaining = document.scenes.first(where: { $0.id == sceneID })?.blocks else {
            selectedBlockID = nil
            return
        }
        selectedBlockID = remaining[min(deletedIndex, remaining.count - 1)].id
    }

    func restoreBoneyardItem(_ itemID: UUID, to sceneID: UUID) {
        guard var workspace = document.workspace,
              let index = workspace.boneyard.firstIndex(where: { $0.id == itemID }) else { return }
        var block = workspace.boneyard.remove(at: index).block
        if document.scenes.flatMap(\.blocks).contains(where: { $0.id == block.id }) {
            block.id = UUID()
        }
        guard perform(
            title: "Restore block from boneyard",
            mutations: [.setWorkspace(workspace), .addBlock(sceneID: sceneID, block: block, index: nil)]
        ) else { return }
        selectedSceneID = sceneID
        selectedBlockID = block.id
    }

    func createSnapshot(name: String) {
        let snapshot = ScriptWorkshopSnapshot(
            name: name,
            title: document.title,
            scenes: document.scenes,
            workspace: document.workspace
        )
        if perform(title: "Create version snapshot", mutations: [.addSnapshot(snapshot)]) {
            saveNow()
        }
    }

    func createBranch(name: String) {
        updateWorkspace(title: "Create writing branch") {
            $0.branches.insert(
                ScriptWorkshopBranch(
                    name: name,
                    baseRevision: document.documentRevision,
                    scenes: document.scenes
                ),
                at: 0
            )
        }
    }

    func startRevision(name: String, author: String = "") {
        updateWorkspace(title: "Start revision set") { workspace in
            let ordinal = workspace.revisionSets.count + 1
            let palette = ScriptWorkshopRevisionColor.allCases
            let color = palette[(ordinal - 1) % palette.count]
            let revision = ScriptWorkshopRevisionSet(
                ordinal: ordinal,
                name: name,
                color: color,
                author: author
            )
            workspace.revisionSets.append(revision)
            workspace.activeRevisionSetID = revision.id
        }
    }

    func setActiveRevision(_ id: UUID?) {
        updateWorkspace(title: "Change active revision") {
            $0.activeRevisionSetID = id
        }
    }

    func addBeat(act: ScriptWorkshopAct) {
        updateWorkspace(title: "Add story beat") { workspace in
            let nextOrder = (workspace.beats.filter { $0.act == act }.map(\.order).max() ?? -1) + 1
            workspace.beats.append(ScriptWorkshopBeat(act: act, order: nextOrder))
        }
    }

    func updateBeat(_ beat: ScriptWorkshopBeat) {
        updateWorkspace(title: "Edit story beat") { workspace in
            guard let index = workspace.beats.firstIndex(where: { $0.id == beat.id }) else { return }
            workspace.beats[index] = beat
        }
    }

    func deleteBeat(_ beatID: UUID) {
        updateWorkspace(title: "Delete story beat") { workspace in
            workspace.beats.removeAll { $0.id == beatID }
            for index in workspace.beats.indices {
                workspace.beats[index].sceneIDs.removeAll { sceneID in
                    !document.scenes.contains(where: { $0.id == sceneID })
                }
            }
        }
    }

    func linkSelectedScene(to beatID: UUID) {
        guard let sceneID = selectedSceneID else { return }
        updateWorkspace(title: "Link beat and scene") { workspace in
            guard let index = workspace.beats.firstIndex(where: { $0.id == beatID }) else { return }
            if workspace.beats[index].sceneIDs.contains(sceneID) {
                workspace.beats[index].sceneIDs.removeAll { $0 == sceneID }
            } else {
                workspace.beats[index].sceneIDs.append(sceneID)
            }
        }
    }

    func renameCharacter(from oldName: String, to newName: String) {
        let source = normalizedCharacterName(oldName)
        let target = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, !target.isEmpty else { return }
        var mutations: [ScriptWorkshopMutation] = []
        for scene in document.scenes {
            for original in scene.blocks where original.kind == .character {
                guard normalizedCharacterName(original.text) == source else { continue }
                var block = original
                block.text = target
                block.updatedAt = Date()
                markActiveRevision(on: &block)
                mutations.append(.updateBlock(sceneID: scene.id, blockID: block.id, block: block))
            }
        }
        var workspace = document.workspace ?? ScriptWorkshopWorkspaceData()
        if let index = workspace.characterProfiles.firstIndex(where: {
            normalizedCharacterName($0.name) == source
        }) {
            workspace.characterProfiles[index].name = target
        }
        mutations.append(.setWorkspace(workspace))
        _ = perform(title: "Rename character \(oldName) to \(target)", mutations: mutations)
    }

    func dialogueLines(for character: String) -> [ScriptWorkshopDialogueLine] {
        let key = normalizedCharacterName(character)
        var result: [ScriptWorkshopDialogueLine] = []
        for (sceneIndex, scene) in document.scenes.enumerated() {
            var activeCharacter = ""
            for block in scene.blocks {
                if block.kind == .character {
                    activeCharacter = normalizedCharacterName(block.text)
                } else if block.kind == .dialogue, activeCharacter == key {
                    result.append(ScriptWorkshopDialogueLine(
                        sceneID: scene.id,
                        blockID: block.id,
                        sceneNumber: scene.metadata?.sceneNumber.isEmpty == false
                            ? scene.metadata!.sceneNumber
                            : String(sceneIndex + 1),
                        sceneHeading: scene.heading,
                        text: block.text
                    ))
                } else if block.kind != .parenthetical && block.kind != .dialogue {
                    activeCharacter = ""
                }
            }
        }
        return result
    }

    func search(_ query: String) -> [ScriptWorkshopSearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var result: [ScriptWorkshopSearchResult] = []
        for scene in document.scenes {
            if scene.heading.localizedCaseInsensitiveContains(needle)
                || scene.synopsis.localizedCaseInsensitiveContains(needle) {
                result.append(.init(
                    id: "scene-\(scene.id.uuidString)",
                    sceneID: scene.id,
                    blockID: nil,
                    sceneHeading: scene.heading,
                    excerpt: scene.synopsis.isEmpty ? scene.heading : scene.synopsis,
                    kind: nil
                ))
            }
            for block in scene.blocks where block.text.localizedCaseInsensitiveContains(needle) {
                result.append(.init(
                    id: "block-\(block.id.uuidString)",
                    sceneID: scene.id,
                    blockID: block.id,
                    sceneHeading: scene.heading,
                    excerpt: block.text.replacingOccurrences(of: "\n", with: " "),
                    kind: block.kind
                ))
            }
        }
        return Array(result.prefix(100))
    }

    func focus(_ result: ScriptWorkshopSearchResult) {
        selectedSceneID = result.sceneID
        selectedBlockID = result.blockID
            ?? document.scenes.first(where: { $0.id == result.sceneID })?.blocks.first?.id
    }

    func importFountain(from url: URL) {
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            let imported = ScriptWorkshopFountain.parse(
                source,
                linkedProjectID: document.linkedProjectID
            )
            try replaceWithImportedDocument(imported, sourceName: url.lastPathComponent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportFountain(to url: URL) {
        do {
            let result = ScriptWorkshopFountain.renderWithReport(document)
            try result.source.write(to: url, atomically: true, encoding: .utf8)
            exportWarnings = result.diagnostics.map(\.message)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importFDX(from url: URL) {
        do {
            let result = try ScriptWorkshopFDX.decode(
                Data(contentsOf: url),
                linkedProjectID: document.linkedProjectID
            )
            try replaceWithImportedDocument(result.document, sourceName: url.lastPathComponent)
            exportWarnings = result.diagnostics.map(\.message)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportFDX(to url: URL) {
        do {
            let result = try ScriptWorkshopFDX.encode(document)
            try result.data.write(to: url, options: .atomic)
            exportWarnings = result.diagnostics.map(\.message)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportPDF(
        to url: URL,
        profile: ScriptWorkshopPDFProfile = .reader,
        screenplayFormat: ScriptWorkshopScreenplayFormat = .international,
        paperSize: ScriptWorkshopPaperSize? = nil
    ) {
        do {
            let layout = pagination(
                screenplayFormat: screenplayFormat,
                paperSize: paperSize,
                includeTitlePage: true
            )
            let report = try ScriptWorkshopPDFExporter.writePDF(
                pagination: layout,
                document: document,
                to: url,
                options: ScriptWorkshopPDFExportOptions(
                    profile: profile,
                    screenplayFormat: screenplayFormat,
                    showSceneNumbersOnBothSides: screenplayFormat == .international
                )
            )
            exportWarnings = report.diagnostics.map(\.message)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pagination(
        screenplayFormat: ScriptWorkshopScreenplayFormat = .international,
        paperSize: ScriptWorkshopPaperSize? = nil,
        includeTitlePage: Bool = true
    ) -> ScriptWorkshopPaginationResult {
        ScriptWorkshopPagination.paginate(
            document,
            configuration: ScriptWorkshopPaginationConfiguration.preset(
                for: screenplayFormat,
                includeTitlePage: includeTitlePage,
                paperSize: paperSize
            )
        )
    }

    func undo() {
        guard commandBus.undo() != nil else { return }
        publish()
        repairSelection()
        markChanged()
    }

    func redo() {
        guard commandBus.redo() != nil else { return }
        publish()
        repairSelection()
        markChanged()
    }

    func flushPendingSave() {
        pendingSave?.cancel()
        pendingSave = nil
        if saveState == .unsaved {
            saveNow()
        }
    }

    func saveCopy(toProjectFolder projectFolder: URL, linkedProjectID: UUID? = nil) throws {
        var copy = document
        copy.linkedProjectID = linkedProjectID
        copy.updatedAt = Date()
        try ScriptWorkshopRepository.save(
            copy,
            to: ScriptWorkshopRepository.documentURL(for: projectFolder)
        )
    }

    @discardableResult
    private func perform(
        title: String,
        source: ScriptWorkshopCommandSource = .ui,
        coalescingKey: String? = nil,
        mutations: [ScriptWorkshopMutation]
    ) -> Bool {
        var next = commandBus
        do {
            try next.apply(ScriptWorkshopTransaction(
                baseRevision: commandBus.document.documentRevision,
                source: source,
                title: title,
                coalescingKey: coalescingKey,
                mutations: mutations
            ))
            commandBus = next
            publish()
            markChanged()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func updateScene(
        _ sceneID: UUID,
        title: String,
        coalescingKey: String? = nil,
        change: (inout ScriptWorkshopScene) -> Void
    ) {
        guard var scene = document.scenes.first(where: { $0.id == sceneID }) else { return }
        change(&scene)
        scene.updatedAt = Date()
        _ = perform(
            title: title,
            coalescingKey: coalescingKey,
            mutations: [.updateScene(sceneID: sceneID, scene: scene)]
        )
    }

    private func updateBlock(
        sceneID: UUID,
        blockID: UUID,
        title: String,
        coalescingKey: String? = nil,
        change: (inout ScriptWorkshopBlock) -> Void
    ) {
        guard let scene = document.scenes.first(where: { $0.id == sceneID }),
              var block = scene.blocks.first(where: { $0.id == blockID }) else { return }
        change(&block)
        block.updatedAt = Date()
        _ = perform(
            title: title,
            coalescingKey: coalescingKey,
            mutations: [.updateBlock(sceneID: sceneID, blockID: blockID, block: block)]
        )
    }

    private func updateWorkspace(
        title: String,
        coalescingKey: String? = nil,
        change: (inout ScriptWorkshopWorkspaceData) -> Void
    ) {
        var workspace = document.workspace ?? ScriptWorkshopWorkspaceData()
        change(&workspace)
        _ = perform(
            title: title,
            coalescingKey: coalescingKey,
            mutations: [.setWorkspace(workspace)]
        )
    }

    private func replaceWithImportedDocument(
        _ source: ScriptWorkshopDocument,
        sourceName: String
    ) throws {
        let beforeImport = ScriptWorkshopSnapshot(
            name: "Before importing \(sourceName)",
            title: document.title,
            scenes: document.scenes,
            workspace: document.workspace
        )
        var imported = source
        imported.id = document.id
        imported.linkedProjectID = document.linkedProjectID
        imported.createdAt = document.createdAt
        imported.snapshots = [beforeImport] + document.snapshots
        if imported.snapshots.count > 30 {
            imported.snapshots.removeLast(imported.snapshots.count - 30)
        }
        imported.migrateToCurrentSchema()
        imported.workspace?.documentRevision = document.documentRevision + 1
        commandBus = try ScriptWorkshopCommandBus(document: imported)
        publish()
        repairSelection()
        markChanged()
        saveNow()
    }

    private func renumberUnlockedScenes() {
        var mutations: [ScriptWorkshopMutation] = []
        for (index, original) in document.scenes.enumerated() {
            guard original.metadata?.isNumberLocked != true else { continue }
            var scene = original
            if scene.metadata == nil { scene.metadata = ScriptWorkshopSceneMetadata() }
            let value = String(index + 1)
            guard scene.metadata?.sceneNumber != value else { continue }
            scene.metadata?.sceneNumber = value
            mutations.append(.updateScene(sceneID: scene.id, scene: scene))
        }
        if !mutations.isEmpty {
            _ = perform(title: "Renumber draft scenes", mutations: mutations)
        }
    }

    private func markActiveRevision(on block: inout ScriptWorkshopBlock) {
        if block.metadata == nil { block.metadata = ScriptWorkshopBlockMetadata() }
        block.metadata?.revisionSetID = document.workspace?.activeRevisionSetID
        block.metadata?.provenance = .human
    }

    private func saveNow() {
        guard let destinationURL else { return }
        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try ScriptWorkshopRepository.compareAndSwap(
                    document,
                    expectedRevision: lastPersistedRevision,
                    to: destinationURL
                )
            } else {
                try ScriptWorkshopRepository.save(document, to: destinationURL)
            }
            lastPersistedRevision = document.documentRevision
            saveState = .saved(Date())
        } catch {
            saveState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    private func markChanged() {
        saveState = .unsaved
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
    }

    private func publish() {
        document = commandBus.document
        canUndo = commandBus.canUndo
        canRedo = commandBus.canRedo
    }

    private func repairSelection() {
        if !document.scenes.contains(where: { $0.id == selectedSceneID }) {
            selectedSceneID = document.scenes.first?.id
        }
        guard let scene = selectedScene else {
            selectedBlockID = nil
            return
        }
        if !scene.blocks.contains(where: { $0.id == selectedBlockID }) {
            selectedBlockID = scene.blocks.first?.id
        }
    }

    private func replacementWithID(_ source: ScriptWorkshopScene, id: UUID) -> ScriptWorkshopScene {
        var copy = source
        copy.id = id
        return copy
    }

    private func normalizedTitle(_ value: String?) -> String {
        normalizedLinkedProjectTitle(value) ?? "未命名剧本"
    }

    private func normalizedLinkedProjectTitle(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty,
              trimmed != "Untitled",
              trimmed != "Untitled Project",
              trimmed != "未命名项目",
              trimmed != "未命名剧本" else {
            return nil
        }
        return trimmed
    }

    private func isPlaceholderTitle(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            || trimmed == "Untitled"
            || trimmed == "Untitled Project"
            || trimmed == "Untitled Screenplay"
            || trimmed == "未命名项目"
            || trimmed == "未命名剧本"
    }

    private func normalizedCharacterName(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\s*[\(（].*?[\)）]\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }
}
