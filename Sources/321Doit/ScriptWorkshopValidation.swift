import Foundation

enum ScriptWorkshopValidationError: LocalizedError, Equatable {
    case futureSchema(Int)
    case duplicateID(UUID)
    case missingScene
    case emptyScene(UUID)
    case danglingBeatScene(UUID)
    case danglingRevision(UUID)
    case duplicateSceneNumber(String)
    case staleRevision(expected: Int, received: Int)
    case lockedEntity(UUID)
    case invalidMutation(String)

    var errorDescription: String? {
        switch self {
        case .futureSchema(let version):
            return "This screenplay uses schema \(version), newer than this version of 321Doit."
        case .duplicateID(let id):
            return "The screenplay contains a duplicate stable ID: \(id.uuidString.lowercased())."
        case .missingScene:
            return "A screenplay must contain at least one scene."
        case .emptyScene(let id):
            return "Scene \(id.uuidString.lowercased()) contains no screenplay blocks."
        case .danglingBeatScene(let id):
            return "A story beat links to a missing scene: \(id.uuidString.lowercased())."
        case .danglingRevision(let id):
            return "A block refers to a missing revision set: \(id.uuidString.lowercased())."
        case .duplicateSceneNumber(let value):
            return "Locked scene number \(value) is used more than once."
        case .staleRevision(let expected, let received):
            return "The screenplay changed. Expected revision \(expected), received \(received)."
        case .lockedEntity(let id):
            return "The requested screenplay entity is locked: \(id.uuidString.lowercased())."
        case .invalidMutation(let message):
            return message
        }
    }
}

enum ScriptWorkshopValidator {
    static func validate(_ source: ScriptWorkshopDocument) throws {
        guard source.schemaVersion <= ScriptWorkshopDocument.currentSchemaVersion else {
            throw ScriptWorkshopValidationError.futureSchema(source.schemaVersion)
        }
        guard !source.scenes.isEmpty else {
            throw ScriptWorkshopValidationError.missingScene
        }

        var ids = Set<UUID>()
        try insert(source.id, into: &ids)
        let revisionIDs = Set(source.workspace?.revisionSets.map(\.id) ?? [])
        for revision in source.workspace?.revisionSets ?? [] {
            try insert(revision.id, into: &ids)
        }

        let sceneIDs = Set(source.scenes.map(\.id))
        var lockedNumbers = Set<String>()
        for scene in source.scenes {
            try insert(scene.id, into: &ids)
            guard !scene.blocks.isEmpty else {
                throw ScriptWorkshopValidationError.emptyScene(scene.id)
            }
            if scene.metadata?.isNumberLocked == true {
                let value = scene.metadata?.sceneNumber
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !value.isEmpty, !lockedNumbers.insert(value.uppercased()).inserted {
                    throw ScriptWorkshopValidationError.duplicateSceneNumber(value)
                }
            }
            for block in scene.blocks {
                try insert(block.id, into: &ids)
                if let revisionID = block.metadata?.revisionSetID,
                   !revisionIDs.contains(revisionID) {
                    throw ScriptWorkshopValidationError.danglingRevision(revisionID)
                }
            }
        }

        for beat in source.workspace?.beats ?? [] {
            try insert(beat.id, into: &ids)
            for sceneID in beat.sceneIDs where !sceneIDs.contains(sceneID) {
                throw ScriptWorkshopValidationError.danglingBeatScene(sceneID)
            }
        }
        for profile in source.workspace?.characterProfiles ?? [] {
            try insert(profile.id, into: &ids)
        }
        for item in source.workspace?.boneyard ?? [] {
            try insert(item.id, into: &ids)
        }
        for branch in source.workspace?.branches ?? [] {
            try insert(branch.id, into: &ids)
        }
        for lock in source.workspace?.fieldLocks ?? [] {
            try insert(lock.id, into: &ids)
        }
    }

    private static func insert(_ id: UUID, into ids: inout Set<UUID>) throws {
        guard ids.insert(id).inserted else {
            throw ScriptWorkshopValidationError.duplicateID(id)
        }
    }
}
