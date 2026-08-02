import Foundation

enum ScriptWorkshopSceneStatus: String, Codable, CaseIterable, Identifiable {
    case idea
    case outline
    case draft
    case revised
    case locked
    case omitted

    var id: String { rawValue }
}

enum ScriptWorkshopAct: String, Codable, CaseIterable, Identifiable {
    case unassigned
    case actOne
    case actTwo
    case actThree
    case epilogue

    var id: String { rawValue }
}

enum ScriptWorkshopProvenance: String, Codable {
    case human
    case ai
    case imported
    case system
}

enum ScriptWorkshopRevisionColor: String, Codable, CaseIterable, Identifiable {
    case white
    case blue
    case pink
    case yellow
    case green
    case goldenrod
    case buff
    case salmon
    case cherry
    case tan

    var id: String { rawValue }

    var hex: String {
        switch self {
        case .white: return "#FFFFFF"
        case .blue: return "#DDEEFF"
        case .pink: return "#FFDCE8"
        case .yellow: return "#FFF3B0"
        case .green: return "#DDF4DF"
        case .goldenrod: return "#E9C46A"
        case .buff: return "#F0DCB0"
        case .salmon: return "#FFB5A7"
        case .cherry: return "#E8A0B2"
        case .tan: return "#D7C0A8"
        }
    }
}

struct ScriptWorkshopRevisionSet: Identifiable, Codable, Equatable {
    var id: UUID
    var ordinal: Int
    var name: String
    var color: ScriptWorkshopRevisionColor
    var author: String
    var createdAt: Date
    var issuedAt: Date?
    var isIssued: Bool

    init(
        id: UUID = UUID(),
        ordinal: Int,
        name: String,
        color: ScriptWorkshopRevisionColor,
        author: String = "",
        createdAt: Date = Date(),
        issuedAt: Date? = nil,
        isIssued: Bool = false
    ) {
        self.id = id
        self.ordinal = ordinal
        self.name = name
        self.color = color
        self.author = author
        self.createdAt = createdAt
        self.issuedAt = issuedAt
        self.isIssued = isIssued
    }
}

struct ScriptWorkshopBlockMetadata: Codable, Equatable {
    var revisionSetID: UUID?
    var provenance: ScriptWorkshopProvenance
    var omitted: Bool
    var dualDialogue: Bool
    var explicitPageBreakBefore: Bool
    var productionTags: [String]

    init(
        revisionSetID: UUID? = nil,
        provenance: ScriptWorkshopProvenance = .human,
        omitted: Bool = false,
        dualDialogue: Bool = false,
        explicitPageBreakBefore: Bool = false,
        productionTags: [String] = []
    ) {
        self.revisionSetID = revisionSetID
        self.provenance = provenance
        self.omitted = omitted
        self.dualDialogue = dualDialogue
        self.explicitPageBreakBefore = explicitPageBreakBefore
        self.productionTags = productionTags
    }
}

struct ScriptWorkshopSceneMetadata: Codable, Equatable {
    var sceneNumber: String
    var status: ScriptWorkshopSceneStatus
    var act: ScriptWorkshopAct
    var beatIDs: [UUID]
    var tags: [String]
    var storylines: [String]
    var isNumberLocked: Bool

    init(
        sceneNumber: String = "",
        status: ScriptWorkshopSceneStatus = .draft,
        act: ScriptWorkshopAct = .unassigned,
        beatIDs: [UUID] = [],
        tags: [String] = [],
        storylines: [String] = [],
        isNumberLocked: Bool = false
    ) {
        self.sceneNumber = sceneNumber
        self.status = status
        self.act = act
        self.beatIDs = beatIDs
        self.tags = tags
        self.storylines = storylines
        self.isNumberLocked = isNumberLocked
    }
}

struct ScriptWorkshopBeat: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var synopsis: String
    var act: ScriptWorkshopAct
    var colorHex: String
    var sceneIDs: [UUID]
    var storylines: [String]
    var order: Int

    init(
        id: UUID = UUID(),
        title: String = "New Beat",
        synopsis: String = "",
        act: ScriptWorkshopAct = .unassigned,
        colorHex: String = "#5267B8",
        sceneIDs: [UUID] = [],
        storylines: [String] = [],
        order: Int = 0
    ) {
        self.id = id
        self.title = title
        self.synopsis = synopsis
        self.act = act
        self.colorHex = colorHex
        self.sceneIDs = sceneIDs
        self.storylines = storylines
        self.order = order
    }
}

struct ScriptWorkshopCharacterProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var aliases: [String]
    var summary: String
    var want: String
    var need: String
    var conflict: String
    var arc: String
    var notes: String
    var colorHex: String

    init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        summary: String = "",
        want: String = "",
        need: String = "",
        conflict: String = "",
        arc: String = "",
        notes: String = "",
        colorHex: String = "#5267B8"
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.summary = summary
        self.want = want
        self.need = need
        self.conflict = conflict
        self.arc = arc
        self.notes = notes
        self.colorHex = colorHex
    }
}

struct ScriptWorkshopBoneyardItem: Identifiable, Codable, Equatable {
    var id: UUID
    var sourceSceneID: UUID?
    var sourceSceneHeading: String
    var block: ScriptWorkshopBlock
    var note: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        sourceSceneID: UUID? = nil,
        sourceSceneHeading: String = "",
        block: ScriptWorkshopBlock,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sourceSceneID = sourceSceneID
        self.sourceSceneHeading = sourceSceneHeading
        self.block = block
        self.note = note
        self.createdAt = createdAt
    }
}

struct ScriptWorkshopBranch: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var baseRevision: Int
    var scenes: [ScriptWorkshopScene]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        baseRevision: Int,
        scenes: [ScriptWorkshopScene],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseRevision = baseRevision
        self.scenes = scenes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ScriptWorkshopAgentChange: Identifiable, Codable, Equatable {
    var id: UUID
    var agentName: String
    var tool: String
    var summary: String
    var affectedSceneIDs: [UUID]
    var affectedBlockIDs: [UUID]
    var beforeSnapshotID: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        agentName: String,
        tool: String,
        summary: String,
        affectedSceneIDs: [UUID] = [],
        affectedBlockIDs: [UUID] = [],
        beforeSnapshotID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.agentName = agentName
        self.tool = tool
        self.summary = summary
        self.affectedSceneIDs = affectedSceneIDs
        self.affectedBlockIDs = affectedBlockIDs
        self.beforeSnapshotID = beforeSnapshotID
        self.createdAt = createdAt
    }
}

struct ScriptWorkshopFieldLock: Identifiable, Codable, Equatable {
    var id: UUID
    var entityID: UUID
    var field: String
    var owner: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        entityID: UUID,
        field: String = "*",
        owner: String = "user",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.entityID = entityID
        self.field = field
        self.owner = owner
        self.createdAt = createdAt
    }
}

struct ScriptWorkshopAgentReceipt: Codable, Equatable {
    var idempotencyKey: String
    var tool: String
    var sceneID: UUID?
    var blockID: UUID?
    var resultKind: String
    var createdAt: Date

    init(
        idempotencyKey: String,
        tool: String,
        sceneID: UUID? = nil,
        blockID: UUID? = nil,
        resultKind: String = "",
        createdAt: Date = Date()
    ) {
        self.idempotencyKey = idempotencyKey
        self.tool = tool
        self.sceneID = sceneID
        self.blockID = blockID
        self.resultKind = resultKind
        self.createdAt = createdAt
    }
}

struct ScriptWorkshopWorkspaceData: Codable, Equatable {
    var documentRevision: Int
    var logline: String
    var genre: String
    var targetPageCount: Int
    var sceneNumbersLocked: Bool
    var activeRevisionSetID: UUID?
    var revisionSets: [ScriptWorkshopRevisionSet]
    var beats: [ScriptWorkshopBeat]
    var characterProfiles: [ScriptWorkshopCharacterProfile]
    var boneyard: [ScriptWorkshopBoneyardItem]
    var branches: [ScriptWorkshopBranch]
    var agentHistory: [ScriptWorkshopAgentChange]
    var fieldLocks: [ScriptWorkshopFieldLock]
    var appliedAgentReceipts: [ScriptWorkshopAgentReceipt]

    init(
        documentRevision: Int = 0,
        logline: String = "",
        genre: String = "",
        targetPageCount: Int = 110,
        sceneNumbersLocked: Bool = false,
        activeRevisionSetID: UUID? = nil,
        revisionSets: [ScriptWorkshopRevisionSet] = [],
        beats: [ScriptWorkshopBeat] = [],
        characterProfiles: [ScriptWorkshopCharacterProfile] = [],
        boneyard: [ScriptWorkshopBoneyardItem] = [],
        branches: [ScriptWorkshopBranch] = [],
        agentHistory: [ScriptWorkshopAgentChange] = [],
        fieldLocks: [ScriptWorkshopFieldLock] = [],
        appliedAgentReceipts: [ScriptWorkshopAgentReceipt] = []
    ) {
        self.documentRevision = documentRevision
        self.logline = logline
        self.genre = genre
        self.targetPageCount = targetPageCount
        self.sceneNumbersLocked = sceneNumbersLocked
        self.activeRevisionSetID = activeRevisionSetID
        self.revisionSets = revisionSets
        self.beats = beats
        self.characterProfiles = characterProfiles
        self.boneyard = boneyard
        self.branches = branches
        self.agentHistory = agentHistory
        self.fieldLocks = fieldLocks
        self.appliedAgentReceipts = appliedAgentReceipts
    }
}

extension ScriptWorkshopDocument {
    static let currentSchemaVersion = 2

    var documentRevision: Int { workspace?.documentRevision ?? 0 }

    var activeRevisionSet: ScriptWorkshopRevisionSet? {
        guard let id = workspace?.activeRevisionSetID else { return nil }
        return workspace?.revisionSets.first { $0.id == id }
    }

    mutating func migrateToCurrentSchema() {
        schemaVersion = Self.currentSchemaVersion
        if workspace == nil {
            workspace = ScriptWorkshopWorkspaceData()
        }
        for index in scenes.indices {
            if scenes[index].metadata == nil {
                scenes[index].metadata = ScriptWorkshopSceneMetadata(
                    sceneNumber: String(index + 1)
                )
            } else if scenes[index].metadata?.sceneNumber.isEmpty == true {
                scenes[index].metadata?.sceneNumber = String(index + 1)
            }
            for blockIndex in scenes[index].blocks.indices
            where scenes[index].blocks[blockIndex].metadata == nil {
                scenes[index].blocks[blockIndex].metadata = ScriptWorkshopBlockMetadata()
            }
        }
        let indexed = Set(workspace?.characterProfiles.map { $0.name.uppercased() } ?? [])
        let discovered = allCharacters.filter { !indexed.contains($0.uppercased()) }
        workspace?.characterProfiles.append(contentsOf: discovered.map {
            ScriptWorkshopCharacterProfile(name: $0)
        })
    }

    mutating func advanceDocumentRevision() {
        if workspace == nil { workspace = ScriptWorkshopWorkspaceData() }
        workspace?.documentRevision += 1
        updatedAt = Date()
    }
}

extension ScriptWorkshopScene {
    var productionNumber: String { metadata?.sceneNumber ?? "" }
    var status: ScriptWorkshopSceneStatus { metadata?.status ?? .draft }

    var headingLocation: String {
        let normalized = heading
            .replacingOccurrences(of: "内景", with: "")
            .replacingOccurrences(of: "外景", with: "")
            .replacingOccurrences(of: "INT.", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "EXT.", with: "", options: .caseInsensitive)
        let parts = normalized.components(separatedBy: CharacterSet(charactersIn: "·-—"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.first ?? normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var headingTimeOfDay: String {
        let upper = heading.uppercased()
        for value in ["黎明", "清晨", "早", "日", "午", "黄昏", "傍晚", "夜", "连续", "DAY", "NIGHT", "DAWN", "DUSK", "CONTINUOUS"] {
            if upper.contains(value.uppercased()) { return value }
        }
        return ""
    }
}
