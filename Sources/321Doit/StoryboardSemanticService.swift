import Foundation

enum StoryboardSemanticResource: String, Codable, CaseIterable {
    case project = "storyboard://project"
    case scenes = "storyboard://scenes"
    case shots = "storyboard://shots"
    case locks = "storyboard://locks"
    case production = "storyboard://production"
    case workflowLinks = "storyboard://workflow-links"
}

enum StoryboardSemanticTool: String, Codable, CaseIterable {
    case readSnapshot = "storyboard_read_snapshot"
    case analyze = "storyboard_analyze"
    case previewPatch = "storyboard_preview_patch"
    case applyPatch = "storyboard_apply_patch"
    case undo = "storyboard_undo"
    case redo = "storyboard_redo"
}

struct StoryboardSemanticManifest: Codable, Equatable {
    var serviceVersion: Int
    var schemaVersion: Int
    var resources: [StoryboardSemanticResource]
    var tools: [StoryboardSemanticTool]
    var mutationContract: String

    static func current(schemaVersion: Int) -> StoryboardSemanticManifest {
        StoryboardSemanticManifest(
            serviceVersion: 1,
            schemaVersion: schemaVersion,
            resources: StoryboardSemanticResource.allCases,
            tools: StoryboardSemanticTool.allCases,
            mutationContract: "All writes require StoryboardPatch preview, current baseRevision, field-lock validation, explicit accepted operation IDs, and one atomic CommandBus transaction."
        )
    }
}

// This is the single boundary for a future local MCP/OpenCode adapter. It
// exposes semantic DTOs and guarded commands rather than paths to project files.
@MainActor
struct StoryboardSemanticService {
    let store: StoryboardStore

    var manifest: StoryboardSemanticManifest {
        .current(schemaVersion: store.document.schemaVersion)
    }

    func resource(_ resource: StoryboardSemanticResource) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        switch resource {
        case .project:
            return try encoder.encode(store.document)
        case .scenes:
            return try encoder.encode(store.document.scenes)
        case .shots:
            return try encoder.encode(store.document.scenes.flatMap(\.shots))
        case .locks:
            return try encoder.encode(store.document.fieldLocks)
        case .production:
            return try encoder.encode(store.document.production ?? StoryboardProductionData())
        case .workflowLinks:
            return try encoder.encode(store.document.production?.workflowLinks ?? [])
        }
    }

    func analyze(sceneID: UUID? = nil) throws -> [StoryboardAnalysisIssue] {
        if let sceneID {
            guard let scene = store.document.scene(id: sceneID) else {
                throw StoryboardCommandError.entityNotFound("场次")
            }
            return StoryboardAnalysisEngine.analyze(scene: scene)
        }
        return StoryboardAnalysisEngine.analyze(document: store.document)
    }

    func preview(_ patch: StoryboardPatch, accepted: Set<UUID>? = nil) throws -> StoryboardPatchPreview {
        try store.previewPatch(patch, accepting: accepted)
    }

    @discardableResult
    func apply(
        _ patch: StoryboardPatch,
        accepted: Set<UUID>,
        authorization: StoryboardAgentAuthorization
    ) -> Bool {
        store.applyPatch(
            patch,
            accepting: accepted,
            authorization: authorization
        )
    }

    func undo() { store.undo() }
    func redo() { store.redo() }
}

protocol StoryboardPatchProposalProvider {
    var providerName: String { get }
    func propose(
        instruction: String,
        manifest: StoryboardSemanticManifest,
        scene: StoryboardScene,
        locks: [StoryboardFieldLock],
        baseRevision: Int
    ) async throws -> StoryboardPatch
}

struct StoryboardExternalAgentRegistry {
    var patchProvider: StoryboardPatchProposalProvider?

    static let unconfigured = StoryboardExternalAgentRegistry(patchProvider: nil)
}
