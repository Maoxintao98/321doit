import Foundation

enum StoryboardInteriorExterior: String, Codable, CaseIterable, Identifiable {
    case interior
    case exterior
    case interiorExterior

    var id: String { rawValue }
}

enum StoryboardCreatedBy: String, Codable {
    case user
    case agent
    case imported
}

enum StoryboardMotionEasing: String, Codable, CaseIterable, Identifiable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    var id: String { rawValue }
}

enum StoryboardMovementPathKind: String, Codable, CaseIterable, Identifiable {
    case character
    case camera
    case prop

    var id: String { rawValue }
}

enum StoryboardTransitionKind: String, Codable, CaseIterable, Identifiable {
    case cut
    case dissolve
    case fadeIn
    case fadeOut
    case dipToBlack

    var id: String { rawValue }
}

enum StoryboardScreenDirection: String, Codable, CaseIterable, Identifiable {
    case leftToRight
    case rightToLeft
    case towardCamera
    case awayFromCamera
    case neutral

    var id: String { rawValue }
}

struct StoryboardScript: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var text: String
    var sourcePath: String?
    var importedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        text: String,
        sourcePath: String? = nil,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.sourcePath = sourcePath
        self.importedAt = importedAt
    }
}

struct StoryboardCharacter: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var visualDescription: String
    var directorNote: String
    var referenceAssetIDs: [UUID]

    init(
        id: UUID = UUID(),
        name: String,
        visualDescription: String = "",
        directorNote: String = "",
        referenceAssetIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.visualDescription = visualDescription
        self.directorNote = directorNote
        self.referenceAssetIDs = referenceAssetIDs
    }
}

struct StoryboardProp: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var continuityNote: String
    var referenceAssetIDs: [UUID]

    init(
        id: UUID = UUID(),
        name: String,
        continuityNote: String = "",
        referenceAssetIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.continuityNote = continuityNote
        self.referenceAssetIDs = referenceAssetIDs
    }
}

struct StoryboardLocation: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var description: String
    var dimensionsNote: String
    var referenceAssetIDs: [UUID]

    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        dimensionsNote: String = "",
        referenceAssetIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.dimensionsNote = dimensionsNote
        self.referenceAssetIDs = referenceAssetIDs
    }
}

enum StoryboardSceneObjectKind: String, Codable, CaseIterable, Identifiable {
    case wall
    case door
    case window
    case furniture
    case character
    case camera
    case light
    case sound
    case axis
    case forbiddenZone

    var id: String { rawValue }
}

struct StoryboardSize: Codable, Equatable {
    var width: Double
    var height: Double

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

struct StoryboardSceneObject: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: StoryboardSceneObjectKind
    var label: String
    var position: StoryboardPoint
    var size: StoryboardSize
    var rotationDegrees: Double
    var linkedEntityID: UUID?
    var note: String

    init(
        id: UUID = UUID(),
        kind: StoryboardSceneObjectKind,
        label: String,
        position: StoryboardPoint = StoryboardPoint(x: 0.5, y: 0.5),
        size: StoryboardSize = StoryboardSize(width: 0.12, height: 0.08),
        rotationDegrees: Double = 0,
        linkedEntityID: UUID? = nil,
        note: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.position = position
        self.size = size
        self.rotationDegrees = rotationDegrees
        self.linkedEntityID = linkedEntityID
        self.note = note
    }
}

struct StoryboardSceneSpace: Codable, Equatable {
    var objects: [StoryboardSceneObject]
    var metersWide: Double
    var metersHigh: Double
    var note: String

    init(
        objects: [StoryboardSceneObject] = [],
        metersWide: Double = 10,
        metersHigh: Double = 10,
        note: String = ""
    ) {
        self.objects = objects
        self.metersWide = metersWide
        self.metersHigh = metersHigh
        self.note = note
    }
}

enum StoryboardAgentPermissionMode: String, Codable, CaseIterable, Identifiable {
    case suggest
    case collaborate
    case proxy

    var id: String { rawValue }
}

enum StoryboardAgentAuthorizationOrigin: String, Codable, Equatable {
    case appUserConfirmation
    case externalClientConfirmation
    case delegatedProxyGrant
}

struct StoryboardAgentAuthorization: Codable, Equatable {
    var origin: StoryboardAgentAuthorizationOrigin
    var confirmedByUser: Bool
    var source: String
    var idempotencyKey: String?
    var grantedOperationIDs: Set<UUID>
    var expiresAt: Date?

    static func appUserConfirmed(source: String = "321Doit UI") -> StoryboardAgentAuthorization {
        StoryboardAgentAuthorization(
            origin: .appUserConfirmation,
            confirmedByUser: true,
            source: source,
            idempotencyKey: nil,
            grantedOperationIDs: [],
            expiresAt: nil
        )
    }

    static func externalUserConfirmed(
        source: String,
        idempotencyKey: String
    ) -> StoryboardAgentAuthorization {
        StoryboardAgentAuthorization(
            origin: .externalClientConfirmation,
            confirmedByUser: true,
            source: source,
            idempotencyKey: idempotencyKey,
            grantedOperationIDs: [],
            expiresAt: nil
        )
    }

    static func delegatedProxyGrant(
        source: String,
        idempotencyKey: String,
        operationIDs: Set<UUID>,
        expiresAt: Date
    ) -> StoryboardAgentAuthorization {
        StoryboardAgentAuthorization(
            origin: .delegatedProxyGrant,
            confirmedByUser: false,
            source: source,
            idempotencyKey: idempotencyKey,
            grantedOperationIDs: operationIDs,
            expiresAt: expiresAt
        )
    }
}

enum StoryboardAgentAuthorizationError: LocalizedError, Equatable {
    case suggestModeIsReadOnly
    case confirmationRequired
    case invalidIdempotencyKey
    case invalidProxyGrant

    var errorDescription: String? {
        switch self {
        case .suggestModeIsReadOnly:
            return "当前为建议模式，Agent 只能读取和预览，不能应用修改。"
        case .confirmationRequired:
            return "应用 Agent 修改前需要用户明确确认。"
        case .invalidIdempotencyKey:
            return "外部 Agent 写操作必须提供非空幂等键。"
        case .invalidProxyGrant:
            return "代理授权已过期，或没有覆盖本次修改的全部操作。"
        }
    }
}

enum StoryboardAgentAuthorizationPolicy {
    static func validate(
        permissionMode: StoryboardAgentPermissionMode,
        authorization: StoryboardAgentAuthorization,
        operationIDs: Set<UUID>,
        now: Date = Date()
    ) throws {
        guard permissionMode != .suggest else {
            throw StoryboardAgentAuthorizationError.suggestModeIsReadOnly
        }

        if authorization.origin != .appUserConfirmation {
            let key = authorization.idempotencyKey?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !key.isEmpty else {
                throw StoryboardAgentAuthorizationError.invalidIdempotencyKey
            }
        }

        switch authorization.origin {
        case .appUserConfirmation, .externalClientConfirmation:
            guard authorization.confirmedByUser else {
                throw StoryboardAgentAuthorizationError.confirmationRequired
            }
        case .delegatedProxyGrant:
            guard permissionMode == .proxy,
                  let expiresAt = authorization.expiresAt,
                  expiresAt > now,
                  operationIDs.isSubset(of: authorization.grantedOperationIDs) else {
                throw StoryboardAgentAuthorizationError.invalidProxyGrant
            }
        }
    }
}

struct StoryboardAgentLogEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var createdAt: Date
    var agentName: String
    var model: String
    var userInstruction: String
    var tools: [String]
    var affectedEntityIDs: [UUID]
    var patchID: UUID?
    var confirmed: Bool
    var result: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        agentName: String,
        model: String,
        userInstruction: String,
        tools: [String] = [],
        affectedEntityIDs: [UUID] = [],
        patchID: UUID? = nil,
        confirmed: Bool = false,
        result: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.agentName = agentName
        self.model = model
        self.userInstruction = userInstruction
        self.tools = tools
        self.affectedEntityIDs = affectedEntityIDs
        self.patchID = patchID
        self.confirmed = confirmed
        self.result = result
    }
}

struct StoryboardWorkflowLink: Identifiable, Codable, Equatable {
    var id: UUID
    var shotID: UUID
    var scriptLogShotID: UUID?
    var shootingDayID: UUID?
    var takeIDs: [UUID]
    var mediaPaths: [String]
    var bestTakeID: UUID?

    init(
        id: UUID = UUID(),
        shotID: UUID,
        scriptLogShotID: UUID? = nil,
        shootingDayID: UUID? = nil,
        takeIDs: [UUID] = [],
        mediaPaths: [String] = [],
        bestTakeID: UUID? = nil
    ) {
        self.id = id
        self.shotID = shotID
        self.scriptLogShotID = scriptLogShotID
        self.shootingDayID = shootingDayID
        self.takeIDs = takeIDs
        self.mediaPaths = mediaPaths
        self.bestTakeID = bestTakeID
    }
}

struct StoryboardProductionData: Codable, Equatable {
    var script: StoryboardScript?
    var characters: [StoryboardCharacter]
    var props: [StoryboardProp]
    var locations: [StoryboardLocation]
    var agentPermissionMode: StoryboardAgentPermissionMode
    var agentLogs: [StoryboardAgentLogEntry]
    var workflowLinks: [StoryboardWorkflowLink]

    init(
        script: StoryboardScript? = nil,
        characters: [StoryboardCharacter] = [],
        props: [StoryboardProp] = [],
        locations: [StoryboardLocation] = [],
        agentPermissionMode: StoryboardAgentPermissionMode = .collaborate,
        agentLogs: [StoryboardAgentLogEntry] = [],
        workflowLinks: [StoryboardWorkflowLink] = []
    ) {
        self.script = script
        self.characters = characters
        self.props = props
        self.locations = locations
        self.agentPermissionMode = agentPermissionMode
        self.agentLogs = agentLogs
        self.workflowLinks = workflowLinks
    }
}
