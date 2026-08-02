import Foundation

enum ScriptWorkshopCommandSource: String, Codable {
    case ui
    case wheel
    case keyboard
    case agent
    case importer
    case migration
}

enum ScriptWorkshopMutation: Codable, Equatable {
    case setDocumentTitle(String)
    case setDocumentAuthor(String)
    case setWorkspace(ScriptWorkshopWorkspaceData)
    case addScene(scene: ScriptWorkshopScene, index: Int?)
    case updateScene(sceneID: UUID, scene: ScriptWorkshopScene)
    case removeScene(sceneID: UUID)
    case moveScene(sceneID: UUID, destination: Int)
    case addBlock(sceneID: UUID, block: ScriptWorkshopBlock, index: Int?)
    case updateBlock(sceneID: UUID, blockID: UUID, block: ScriptWorkshopBlock)
    case removeBlock(sceneID: UUID, blockID: UUID)
    case moveBlock(sceneID: UUID, blockID: UUID, destination: Int)
    case addSnapshot(ScriptWorkshopSnapshot)
    case setFieldLock(lock: ScriptWorkshopFieldLock, isLocked: Bool)
    case appendAgentChange(ScriptWorkshopAgentChange)
    case appendAgentReceipt(ScriptWorkshopAgentReceipt)

    var affectedEntityIDs: Set<UUID> {
        switch self {
        case .setDocumentTitle, .setDocumentAuthor, .setWorkspace,
             .appendAgentReceipt:
            return []
        case .addScene(let scene, _):
            return [scene.id]
        case .updateScene(let sceneID, _), .removeScene(let sceneID), .moveScene(let sceneID, _):
            return [sceneID]
        case .addBlock(let sceneID, let block, _):
            return [sceneID, block.id]
        case .updateBlock(let sceneID, let blockID, _),
             .removeBlock(let sceneID, let blockID),
             .moveBlock(let sceneID, let blockID, _):
            return [sceneID, blockID]
        case .addSnapshot(let snapshot):
            return [snapshot.id]
        case .setFieldLock(let lock, _):
            return [lock.entityID]
        case .appendAgentChange(let change):
            return Set(change.affectedSceneIDs + change.affectedBlockIDs)
        }
    }
}

struct ScriptWorkshopTransaction: Identifiable, Codable, Equatable {
    var id: UUID
    var baseRevision: Int
    var source: ScriptWorkshopCommandSource
    var title: String
    var createdAt: Date
    var coalescingKey: String?
    var mutations: [ScriptWorkshopMutation]

    init(
        id: UUID = UUID(),
        baseRevision: Int,
        source: ScriptWorkshopCommandSource,
        title: String,
        createdAt: Date = Date(),
        coalescingKey: String? = nil,
        mutations: [ScriptWorkshopMutation]
    ) {
        self.id = id
        self.baseRevision = baseRevision
        self.source = source
        self.title = title
        self.createdAt = createdAt
        self.coalescingKey = coalescingKey
        self.mutations = mutations
    }
}

struct ScriptWorkshopHistoryEntry {
    var transaction: ScriptWorkshopTransaction
    var before: ScriptWorkshopDocument
    var after: ScriptWorkshopDocument
}

struct ScriptWorkshopCommandBus {
    private(set) var document: ScriptWorkshopDocument
    private var undoStack: [ScriptWorkshopHistoryEntry] = []
    private var redoStack: [ScriptWorkshopHistoryEntry] = []
    private let historyLimit: Int

    init(document: ScriptWorkshopDocument, historyLimit: Int = 100) throws {
        var migrated = document
        migrated.migrateToCurrentSchema()
        try ScriptWorkshopValidator.validate(migrated)
        self.document = migrated
        self.historyLimit = max(1, historyLimit)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoTitle: String? { undoStack.last?.transaction.title }
    var redoTitle: String? { redoStack.last?.transaction.title }

    mutating func apply(_ transaction: ScriptWorkshopTransaction) throws {
        guard transaction.baseRevision == document.documentRevision else {
            throw ScriptWorkshopValidationError.staleRevision(
                expected: document.documentRevision,
                received: transaction.baseRevision
            )
        }
        try validateLocks(for: transaction)
        let before = document
        var working = document
        for mutation in transaction.mutations {
            try Self.apply(mutation, to: &working)
        }
        working.advanceDocumentRevision()
        try ScriptWorkshopValidator.validate(working)
        document = working
        if let key = transaction.coalescingKey,
           var latest = undoStack.last,
           latest.transaction.coalescingKey == key,
           transaction.createdAt.timeIntervalSince(latest.transaction.createdAt) <= 1.2 {
            latest.transaction = transaction
            latest.after = working
            undoStack[undoStack.count - 1] = latest
        } else {
            undoStack.append(.init(transaction: transaction, before: before, after: working))
        }
        if undoStack.count > historyLimit {
            undoStack.removeFirst(undoStack.count - historyLimit)
        }
        redoStack.removeAll()
    }

    @discardableResult
    mutating func undo() -> String? {
        guard let entry = undoStack.popLast() else { return nil }
        var restored = entry.before
        restored.workspace?.documentRevision = document.documentRevision + 1
        restored.updatedAt = Date()
        document = restored
        redoStack.append(entry)
        return entry.transaction.title
    }

    @discardableResult
    mutating func redo() -> String? {
        guard let entry = redoStack.popLast() else { return nil }
        var restored = entry.after
        restored.workspace?.documentRevision = document.documentRevision + 1
        restored.updatedAt = Date()
        document = restored
        undoStack.append(entry)
        return entry.transaction.title
    }

    private func validateLocks(for transaction: ScriptWorkshopTransaction) throws {
        guard transaction.source == .agent || transaction.source == .importer else { return }
        if transaction.mutations.contains(where: {
            if case .setWorkspace = $0 { return true }
            if case .setFieldLock = $0 { return true }
            return false
        }) {
            throw ScriptWorkshopValidationError.invalidMutation(
                "Agents and importers cannot replace the complete screenplay workspace or its safety locks."
            )
        }
        let affected = transaction.mutations.reduce(into: Set<UUID>()) {
            $0.formUnion($1.affectedEntityIDs)
        }
        let changesDocumentMetadata = transaction.mutations.contains {
            switch $0 {
            case .setDocumentTitle, .setDocumentAuthor, .addScene, .removeScene, .moveScene:
                return true
            default:
                return false
            }
        }
        if let lock = document.workspace?.fieldLocks.first(where: { lock in
            affected.contains(lock.entityID)
                || (changesDocumentMetadata && lock.entityID == document.id)
        }) {
            throw ScriptWorkshopValidationError.lockedEntity(lock.entityID)
        }
    }

    private static func apply(
        _ mutation: ScriptWorkshopMutation,
        to document: inout ScriptWorkshopDocument
    ) throws {
        switch mutation {
        case .setDocumentTitle(let value):
            document.title = value
        case .setDocumentAuthor(let value):
            document.author = value
        case .setWorkspace(let value):
            document.workspace = value
        case .addScene(let scene, let requestedIndex):
            let index = min(max(requestedIndex ?? document.scenes.count, 0), document.scenes.count)
            document.scenes.insert(scene, at: index)
        case .updateScene(let sceneID, let scene):
            guard let index = document.scenes.firstIndex(where: { $0.id == sceneID }),
                  scene.id == sceneID else {
                throw ScriptWorkshopValidationError.invalidMutation("The screenplay scene to update was not found.")
            }
            document.scenes[index] = scene
        case .removeScene(let sceneID):
            guard document.scenes.count > 1,
                  let index = document.scenes.firstIndex(where: { $0.id == sceneID }) else {
                throw ScriptWorkshopValidationError.invalidMutation("A screenplay must keep at least one scene.")
            }
            document.scenes.remove(at: index)
        case .moveScene(let sceneID, let destination):
            guard let source = document.scenes.firstIndex(where: { $0.id == sceneID }) else {
                throw ScriptWorkshopValidationError.invalidMutation("The screenplay scene to move was not found.")
            }
            let scene = document.scenes.remove(at: source)
            document.scenes.insert(scene, at: min(max(destination, 0), document.scenes.count))
        case .addBlock(let sceneID, let block, let requestedIndex):
            guard let sceneIndex = document.scenes.firstIndex(where: { $0.id == sceneID }) else {
                throw ScriptWorkshopValidationError.invalidMutation("The screenplay scene for the new block was not found.")
            }
            let index = min(
                max(requestedIndex ?? document.scenes[sceneIndex].blocks.count, 0),
                document.scenes[sceneIndex].blocks.count
            )
            document.scenes[sceneIndex].blocks.insert(block, at: index)
            document.scenes[sceneIndex].updatedAt = Date()
        case .updateBlock(let sceneID, let blockID, let block):
            guard let sceneIndex = document.scenes.firstIndex(where: { $0.id == sceneID }),
                  let blockIndex = document.scenes[sceneIndex].blocks.firstIndex(where: { $0.id == blockID }),
                  block.id == blockID else {
                throw ScriptWorkshopValidationError.invalidMutation("The screenplay block to update was not found.")
            }
            document.scenes[sceneIndex].blocks[blockIndex] = block
            document.scenes[sceneIndex].updatedAt = Date()
        case .removeBlock(let sceneID, let blockID):
            guard let sceneIndex = document.scenes.firstIndex(where: { $0.id == sceneID }),
                  document.scenes[sceneIndex].blocks.count > 1,
                  let blockIndex = document.scenes[sceneIndex].blocks.firstIndex(where: { $0.id == blockID }) else {
                throw ScriptWorkshopValidationError.invalidMutation("A scene must keep at least one screenplay block.")
            }
            document.scenes[sceneIndex].blocks.remove(at: blockIndex)
            document.scenes[sceneIndex].updatedAt = Date()
        case .moveBlock(let sceneID, let blockID, let destination):
            guard let sceneIndex = document.scenes.firstIndex(where: { $0.id == sceneID }),
                  let source = document.scenes[sceneIndex].blocks.firstIndex(where: { $0.id == blockID }) else {
                throw ScriptWorkshopValidationError.invalidMutation("The screenplay block to move was not found.")
            }
            let block = document.scenes[sceneIndex].blocks.remove(at: source)
            document.scenes[sceneIndex].blocks.insert(
                block,
                at: min(max(destination, 0), document.scenes[sceneIndex].blocks.count)
            )
            document.scenes[sceneIndex].updatedAt = Date()
        case .addSnapshot(let snapshot):
            document.snapshots.insert(snapshot, at: 0)
            if document.snapshots.count > 30 {
                document.snapshots.removeLast(document.snapshots.count - 30)
            }
        case .setFieldLock(let lock, let isLocked):
            if document.workspace == nil { document.workspace = ScriptWorkshopWorkspaceData() }
            document.workspace?.fieldLocks.removeAll {
                $0.entityID == lock.entityID && $0.field == lock.field
            }
            if isLocked {
                document.workspace?.fieldLocks.append(lock)
            }
        case .appendAgentChange(let change):
            if document.workspace == nil { document.workspace = ScriptWorkshopWorkspaceData() }
            document.workspace?.agentHistory.insert(change, at: 0)
            let excessHistory = max(0, (document.workspace?.agentHistory.count ?? 0) - 200)
            if excessHistory > 0 {
                document.workspace?.agentHistory.removeLast(excessHistory)
            }
        case .appendAgentReceipt(let receipt):
            if document.workspace == nil { document.workspace = ScriptWorkshopWorkspaceData() }
            document.workspace?.appliedAgentReceipts.removeAll {
                $0.idempotencyKey == receipt.idempotencyKey
            }
            document.workspace?.appliedAgentReceipts.insert(receipt, at: 0)
            let excessReceipts = max(
                0,
                (document.workspace?.appliedAgentReceipts.count ?? 0) - 500
            )
            if excessReceipts > 0 {
                document.workspace?.appliedAgentReceipts.removeLast(excessReceipts)
            }
        }
    }
}
