import Foundation

enum ScriptWorkshopBlockKind: String, Codable, CaseIterable, Identifiable {
    case action
    case character
    case dialogue
    case parenthetical
    case transition
    case shot
    case note

    var id: String { rawValue }

    func nextKind(for trigger: ScriptWorkshopAdvanceTrigger) -> ScriptWorkshopBlockKind {
        switch (self, trigger) {
        case (.action, .tab):
            return .character
        case (.character, .tab):
            return .parenthetical
        case (.character, .returnKey), (.parenthetical, .returnKey):
            return .dialogue
        case (.dialogue, .returnKey):
            return .character
        case (.dialogue, .tab):
            return .parenthetical
        default:
            return .action
        }
    }
}

enum ScriptWorkshopAdvanceTrigger {
    case returnKey
    case tab
}

enum ScriptWorkshopEmptyAdvancePolicy {
    /// Empty screenplay elements are reused instead of leaving a visible blank
    /// block behind. A nil result means the block contains text and should be
    /// split normally at the caret.
    static func replacementKind(
        currentKind: ScriptWorkshopBlockKind,
        text: String,
        trigger: ScriptWorkshopAdvanceTrigger
    ) -> ScriptWorkshopBlockKind? {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return currentKind.nextKind(for: trigger)
    }
}

struct ScriptWorkshopBlock: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: ScriptWorkshopBlockKind
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var metadata: ScriptWorkshopBlockMetadata?

    init(
        id: UUID = UUID(),
        kind: ScriptWorkshopBlockKind,
        text: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: ScriptWorkshopBlockMetadata? = ScriptWorkshopBlockMetadata()
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }
}

struct ScriptWorkshopScene: Identifiable, Codable, Equatable {
    var id: UUID
    var heading: String
    var synopsis: String
    var colorHex: String
    var blocks: [ScriptWorkshopBlock]
    var createdAt: Date
    var updatedAt: Date
    var metadata: ScriptWorkshopSceneMetadata?

    init(
        id: UUID = UUID(),
        heading: String = "内景 · 未命名场景 · 日",
        synopsis: String = "",
        colorHex: String = "#5267B8",
        blocks: [ScriptWorkshopBlock] = [
            ScriptWorkshopBlock(kind: .action)
        ],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        metadata: ScriptWorkshopSceneMetadata? = ScriptWorkshopSceneMetadata()
    ) {
        self.id = id
        self.heading = heading
        self.synopsis = synopsis
        self.colorHex = colorHex
        self.blocks = blocks.isEmpty ? [ScriptWorkshopBlock(kind: .action)] : blocks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadata = metadata
    }

    var characterNames: [String] {
        var seen = Set<String>()
        return blocks.compactMap { block in
            guard block.kind == .character else { return nil }
            let name = block.text
                .replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let key = name.uppercased()
            return seen.insert(key).inserted ? name : nil
        }
    }
}

struct ScriptWorkshopSnapshot: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var title: String
    var scenes: [ScriptWorkshopScene]
    var workspace: ScriptWorkshopWorkspaceData?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        title: String,
        scenes: [ScriptWorkshopScene],
        workspace: ScriptWorkshopWorkspaceData? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.title = title
        self.scenes = scenes
        self.workspace = workspace
    }
}

struct ScriptWorkshopDocument: Identifiable, Codable, Equatable {
    var schemaVersion: Int
    var id: UUID
    var linkedProjectID: UUID?
    var title: String
    var author: String
    var draftDate: Date
    var scenes: [ScriptWorkshopScene]
    var snapshots: [ScriptWorkshopSnapshot]
    var createdAt: Date
    var updatedAt: Date
    var workspace: ScriptWorkshopWorkspaceData?

    init(
        schemaVersion: Int = ScriptWorkshopDocument.currentSchemaVersion,
        id: UUID = UUID(),
        linkedProjectID: UUID? = nil,
        title: String = "未命名剧本",
        author: String = "",
        draftDate: Date = Date(),
        scenes: [ScriptWorkshopScene] = [ScriptWorkshopScene()],
        snapshots: [ScriptWorkshopSnapshot] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        workspace: ScriptWorkshopWorkspaceData? = ScriptWorkshopWorkspaceData()
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.linkedProjectID = linkedProjectID
        self.title = title
        self.author = author
        self.draftDate = draftDate
        self.scenes = scenes.isEmpty ? [ScriptWorkshopScene()] : scenes
        self.snapshots = snapshots
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.workspace = workspace
    }

    var allCharacters: [String] {
        var seen = Set<String>()
        return scenes.flatMap(\.characterNames).filter { seen.insert($0.uppercased()).inserted }
    }

    /// Characters available to writer-facing project controls. Script cues lead
    /// the list in first-appearance order; profile-only characters follow.
    var projectCharacterNames: [String] {
        var seen = Set<String>()
        let profileNames = workspace?.characterProfiles.map(\.name) ?? []
        return (allCharacters + profileNames).compactMap { rawName in
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return seen.insert(name.uppercased()).inserted ? name : nil
        }
    }

    var estimatedPageCount: Int {
        ScriptWorkshopPagination.paginate(
            self,
            configuration: ScriptWorkshopPaginationConfiguration(
                includeTitlePage: false
            )
        ).scriptPageCount
    }

    var wordCount: Int {
        scenes.reduce(0) { partial, scene in
            partial + scene.blocks.reduce(0) { blockPartial, block in
                blockPartial + block.text.split(whereSeparator: \.isWhitespace).count
            }
        }
    }
}
