import Foundation

enum ScriptWorkshopCommandError: LocalizedError {
    case sceneNotFound
    case blockNotFound

    var errorDescription: String? {
        switch self {
        case .sceneNotFound:
            return "The requested script scene was not found."
        case .blockNotFound:
            return "The requested script block was not found."
        }
    }
}

/// The shared command behind both the on-screen creation wheel and AI tools.
///
/// Supplying a block ID changes that block's screenplay element. Omitting it
/// appends a new block, which lets an agent use the same vocabulary as a writer
/// without reaching around the document model.
struct ScriptWorkshopWheelCommand: Equatable {
    var sceneID: UUID
    var blockID: UUID?
    var kind: ScriptWorkshopBlockKind
    var text: String?
}

struct ScriptWorkshopWheelCommandResult: Equatable {
    var sceneID: UUID
    var blockID: UUID
    var kind: ScriptWorkshopBlockKind
    var created: Bool
}

enum ScriptWorkshopWheelPlacement: Equatable {
    case append
    case changeEmpty(blockID: UUID, index: Int)
    case insertAfter(blockID: UUID, index: Int)
}

/// Defines the non-destructive default for the in-app radial gesture.
///
/// AI commands may explicitly target and replace a block after preview and user
/// confirmation. The direct-manipulation wheel is intentionally safer: it only
/// changes an empty target and otherwise inserts a fresh element after it.
enum ScriptWorkshopWheelSafety {
    static func placement(
        in scene: ScriptWorkshopScene,
        targetBlockID: UUID?
    ) -> ScriptWorkshopWheelPlacement {
        guard let targetBlockID,
              let index = scene.blocks.firstIndex(where: { $0.id == targetBlockID }) else {
            return .append
        }
        let block = scene.blocks[index]
        if block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .changeEmpty(blockID: targetBlockID, index: index)
        }
        return .insertAfter(blockID: targetBlockID, index: index + 1)
    }
}

enum ScriptWorkshopCommandEngine {
    static func apply(
        _ command: ScriptWorkshopWheelCommand,
        to document: inout ScriptWorkshopDocument,
        now: Date = Date()
    ) throws -> ScriptWorkshopWheelCommandResult {
        guard let scene = document.scenes.first(where: { $0.id == command.sceneID }) else {
            throw ScriptWorkshopCommandError.sceneNotFound
        }

        let blockID: UUID
        let created: Bool
        let mutation: ScriptWorkshopMutation
        if let requestedBlockID = command.blockID {
            guard var block = scene.blocks.first(where: { $0.id == requestedBlockID }) else {
                throw ScriptWorkshopCommandError.blockNotFound
            }
            block.kind = command.kind
            if let text = command.text {
                block.text = text
            }
            block.updatedAt = now
            if block.metadata == nil {
                block.metadata = ScriptWorkshopBlockMetadata()
            }
            block.metadata?.provenance = .human
            blockID = requestedBlockID
            created = false
            mutation = .updateBlock(
                sceneID: command.sceneID,
                blockID: requestedBlockID,
                block: block
            )
        } else {
            let block = ScriptWorkshopBlock(
                kind: command.kind,
                text: command.text ?? "",
                createdAt: now,
                updatedAt: now,
                metadata: ScriptWorkshopBlockMetadata(provenance: .human)
            )
            blockID = block.id
            created = true
            mutation = .addBlock(
                sceneID: command.sceneID,
                block: block,
                index: nil
            )
        }

        var bus = try ScriptWorkshopCommandBus(document: document)
        try bus.apply(
            ScriptWorkshopTransaction(
                baseRevision: document.documentRevision,
                source: .wheel,
                title: "Apply creation wheel",
                createdAt: now,
                mutations: [mutation]
            )
        )
        document = bus.document
        return ScriptWorkshopWheelCommandResult(
            sceneID: command.sceneID,
            blockID: blockID,
            kind: command.kind,
            created: created
        )
    }
}
