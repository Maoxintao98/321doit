import Foundation

enum StoryboardCommandSource: String, Codable {
    case ui
    case wheel
    case keyboard
    case agent
    case importer
}

enum StoryboardMutation: Codable, Equatable {
    case setDocumentTitle(String)
    case updateProduction(StoryboardProductionData)
    case addScene(scene: StoryboardScene, index: Int?)
    case updateScene(sceneID: UUID, scene: StoryboardScene)
    case removeScene(sceneID: UUID)
    case moveScene(sceneID: UUID, destination: Int)
    case addShot(sceneID: UUID, shot: StoryboardShot, index: Int?)
    case updateShot(sceneID: UUID, shotID: UUID, shot: StoryboardShot)
    case removeShot(sceneID: UUID, shotID: UUID)
    case moveShot(sceneID: UUID, shotID: UUID, destination: Int)
    case addAsset(asset: StoryboardAsset)
    case addAssetVersion(assetID: UUID, version: StoryboardAssetVersion)
    case setActiveAssetVersion(assetID: UUID, versionID: UUID)
    case setFieldLock(lock: StoryboardFieldLock, isLocked: Bool)

    fileprivate var affectedEntityIDs: Set<UUID> {
        switch self {
        case .setDocumentTitle, .updateProduction:
            return []
        case .addScene(let scene, _):
            return [scene.id]
        case .updateScene(let sceneID, _), .removeScene(let sceneID), .moveScene(let sceneID, _):
            return [sceneID]
        case .addShot(let sceneID, let shot, _):
            return [sceneID, shot.id]
        case .updateShot(let sceneID, let shotID, _),
             .removeShot(let sceneID, let shotID),
             .moveShot(let sceneID, let shotID, _):
            return [sceneID, shotID]
        case .addAsset(let asset):
            return [asset.id]
        case .addAssetVersion(let assetID, let version):
            return [assetID, version.id]
        case .setActiveAssetVersion(let assetID, let versionID):
            return [assetID, versionID]
        case .setFieldLock(let lock, _):
            return [lock.entityID]
        }
    }
}

struct StoryboardTransaction: Identifiable, Codable, Equatable {
    var id: UUID
    var baseRevision: Int
    var source: StoryboardCommandSource
    var title: String
    var createdAt: Date
    var mutations: [StoryboardMutation]

    init(
        id: UUID = UUID(),
        baseRevision: Int,
        source: StoryboardCommandSource,
        title: String,
        createdAt: Date = Date(),
        mutations: [StoryboardMutation]
    ) {
        self.id = id
        self.baseRevision = baseRevision
        self.source = source
        self.title = title
        self.createdAt = createdAt
        self.mutations = mutations
    }
}

enum StoryboardCommandError: LocalizedError, Equatable {
    case staleRevision(expected: Int, received: Int)
    case emptyTransaction
    case entityNotFound(String)
    case duplicateIdentifier(UUID)
    case invalidValue(String)
    case lockedEntity(UUID)
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .staleRevision(let expected, let received):
            return "分镜已被更新（当前版本 \(expected)，操作基于版本 \(received)），请刷新后重试。"
        case .emptyTransaction:
            return "这次操作没有包含任何修改。"
        case .entityNotFound(let label):
            return "找不到要修改的\(label)。"
        case .duplicateIdentifier:
            return "新增内容与现有项目数据发生冲突，请重试。"
        case .invalidValue(let message):
            return message
        case .lockedEntity:
            return "该内容已锁定，Agent 或导入操作不能覆盖它。"
        case .unsupportedSchema(let version):
            return "该分镜文件版本（\(version)）暂不受支持。"
        }
    }
}

struct StoryboardCommandBus {
    private struct HistoryEntry {
        let transaction: StoryboardTransaction
        let before: StoryboardDocument
        let after: StoryboardDocument
    }

    private(set) var document: StoryboardDocument
    private var undoStack: [HistoryEntry] = []
    private var redoStack: [HistoryEntry] = []
    private let historyLimit: Int

    init(document: StoryboardDocument, historyLimit: Int = 100) throws {
        guard document.schemaVersion == StoryboardDocument.currentSchemaVersion else {
            throw StoryboardCommandError.unsupportedSchema(document.schemaVersion)
        }
        try Self.validate(document)
        self.document = document
        self.historyLimit = max(1, historyLimit)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoTitle: String? { undoStack.last?.transaction.title }
    var redoTitle: String? { redoStack.last?.transaction.title }

    @discardableResult
    mutating func apply(
        _ transaction: StoryboardTransaction,
        now: Date = Date()
    ) throws -> StoryboardDocument {
        guard !transaction.mutations.isEmpty else {
            throw StoryboardCommandError.emptyTransaction
        }
        guard transaction.baseRevision == document.revision else {
            throw StoryboardCommandError.staleRevision(
                expected: document.revision,
                received: transaction.baseRevision
            )
        }

        try enforceLocks(for: transaction)

        let before = document
        var working = document
        for mutation in transaction.mutations {
            try Self.apply(mutation, to: &working)
        }
        try Self.validate(working)
        working.revision = document.revision + 1
        working.updatedAt = now
        document = working

        undoStack.append(HistoryEntry(transaction: transaction, before: before, after: working))
        if undoStack.count > historyLimit {
            undoStack.removeFirst(undoStack.count - historyLimit)
        }
        redoStack.removeAll()
        return document
    }

    @discardableResult
    mutating func undo(now: Date = Date()) -> StoryboardDocument? {
        guard let entry = undoStack.popLast() else { return nil }
        var restored = entry.before
        restored.revision = document.revision + 1
        restored.updatedAt = now
        document = restored
        redoStack.append(entry)
        return document
    }

    @discardableResult
    mutating func redo(now: Date = Date()) -> StoryboardDocument? {
        guard let entry = redoStack.popLast() else { return nil }
        var restored = entry.after
        restored.revision = document.revision + 1
        restored.updatedAt = now
        document = restored
        undoStack.append(entry)
        return document
    }

    private func enforceLocks(for transaction: StoryboardTransaction) throws {
        for mutation in transaction.mutations {
            if case .setFieldLock = mutation {
                if transaction.source == .agent || transaction.source == .importer {
                    throw StoryboardCommandError.invalidValue("Agent 或导入操作不能修改用户锁。")
                }
                continue
            }
            let impacts = impactedFields(for: mutation)
            for lock in document.fieldLocks {
                guard let fields = impacts[lock.entityID] else { continue }
                if lock.field == "*" || fields.contains("*") || fields.contains(lock.field) {
                    throw StoryboardCommandError.lockedEntity(lock.entityID)
                }
            }
        }
    }

    private func impactedFields(for mutation: StoryboardMutation) -> [UUID: Set<String>] {
        switch mutation {
        case .setDocumentTitle:
            return [document.id: ["title"]]
        case .updateProduction:
            return [document.id: ["production"]]
        case .addScene:
            return [document.id: ["scenes", "order"]]
        case .updateScene(let sceneID, let updated):
            guard let current = document.scene(id: sceneID) else { return [sceneID: ["*"]] }
            var fields = Set<String>()
            if current.sceneNumber != updated.sceneNumber { fields.insert("sceneNumber") }
            if current.title != updated.title { fields.insert("title") }
            if current.synopsis != updated.synopsis { fields.insert("synopsis") }
            if current.location != updated.location || current.locationID != updated.locationID { fields.insert("location") }
            if current.timeOfDay != updated.timeOfDay { fields.insert("timeOfDay") }
            if current.interiorExterior != updated.interiorExterior { fields.insert("interiorExterior") }
            if current.directorIntent != updated.directorIntent { fields.insert("directorIntent") }
            if current.targetDurationSeconds != updated.targetDurationSeconds { fields.insert("targetDuration") }
            if current.space != updated.space { fields.insert("space") }
            return [sceneID: fields]
        case .removeScene(let sceneID):
            var impacts: [UUID: Set<String>] = [sceneID: ["*"]]
            for shot in document.scene(id: sceneID)?.shots ?? [] { impacts[shot.id] = ["*"] }
            return impacts
        case .moveScene(let sceneID, _):
            return [document.id: ["order"], sceneID: ["order"]]
        case .addShot(let sceneID, _, _):
            return [sceneID: ["shots", "order"]]
        case .updateShot(let sceneID, let shotID, let updated):
            guard let current = document.shot(id: shotID) else { return [shotID: ["*"]] }
            var fields = Set<String>()
            if current.shotNumber != updated.shotNumber { fields.insert("shotNumber") }
            if current.title != updated.title { fields.insert("title") }
            if current.description != updated.description { fields.insert("description") }
            if current.durationSeconds != updated.durationSeconds { fields.insert("duration") }
            if current.shotSize != updated.shotSize { fields.insert("shotSize") }
            if current.cameraAngle != updated.cameraAngle { fields.insert("cameraAngle") }
            if current.lens != updated.lens { fields.insert("lens") }
            if current.frame != updated.frame { fields.insert("frame") }
            if current.canvasElements != updated.canvasElements { fields.insert("frameElements") }
            if current.characters != updated.characters { fields.insert("characters") }
            if current.cameraPlacements != updated.cameraPlacements { fields.insert("cameraPlacement") }
            if current.cameraMotions != updated.cameraMotions { fields.insert("cameraMotion") }
            if current.movementPaths != updated.movementPaths { fields.insert("movementPaths") }
            if current.annotations != updated.annotations { fields.insert("annotations") }
            if current.annotationLayers != updated.annotationLayers { fields.insert("annotationLayers") }
            if current.canvasLayerOrder != updated.canvasLayerOrder { fields.insert("canvasLayerOrder") }
            if current.audioCues != updated.audioCues { fields.insert("dialogue") }
            if current.notes != updated.notes { fields.insert("notes") }
            if current.directorIntent != updated.directorIntent { fields.insert("directorIntent") }
            if current.soundDescription != updated.soundDescription { fields.insert("sound") }
            if current.transition != updated.transition { fields.insert("transition") }
            if current.screenDirection != updated.screenDirection { fields.insert("screenDirection") }
            if current.expectedTakes != updated.expectedTakes { fields.insert("expectedTakes") }
            if current.productionDifficulty != updated.productionDifficulty { fields.insert("productionDifficulty") }
            if current.propIDs != updated.propIDs { fields.insert("props") }
            if current.specialEquipment != updated.specialEquipment { fields.insert("equipment") }
            return [sceneID: ["shots"], shotID: fields]
        case .removeShot(let sceneID, let shotID):
            return [sceneID: ["shots", "order"], shotID: ["*"]]
        case .moveShot(let sceneID, let shotID, _):
            return [sceneID: ["order"], shotID: ["order"]]
        case .addAsset(let asset):
            return [document.id: ["assets"], asset.id: ["*"]]
        case .addAssetVersion(let assetID, let version):
            return [assetID: ["versions"], version.id: ["*"]]
        case .setActiveAssetVersion(let assetID, _):
            return [assetID: ["activeVersion"]]
        case .setFieldLock:
            return [:]
        }
    }

    private static func apply(
        _ mutation: StoryboardMutation,
        to document: inout StoryboardDocument
    ) throws {
        switch mutation {
        case .setDocumentTitle(let title):
            document.title = title

        case .updateProduction(let production):
            document.production = production

        case .addScene(let scene, let index):
            guard !document.scenes.contains(where: { $0.id == scene.id }) else {
                throw StoryboardCommandError.duplicateIdentifier(scene.id)
            }
            document.scenes.insert(scene, at: bounded(index, count: document.scenes.count))

        case .updateScene(let sceneID, var scene):
            guard let index = document.scenes.firstIndex(where: { $0.id == sceneID }) else {
                throw StoryboardCommandError.entityNotFound("场次")
            }
            scene.id = sceneID
            scene.shots = document.scenes[index].shots
            document.scenes[index] = scene

        case .removeScene(let sceneID):
            guard let index = document.scenes.firstIndex(where: { $0.id == sceneID }) else {
                throw StoryboardCommandError.entityNotFound("场次")
            }
            let removedShotIDs = Set(document.scenes[index].shots.map(\.id))
            document.scenes.remove(at: index)
            document.fieldLocks.removeAll {
                $0.entityID == sceneID || removedShotIDs.contains($0.entityID)
            }

        case .moveScene(let sceneID, let destination):
            guard let source = document.scenes.firstIndex(where: { $0.id == sceneID }) else {
                throw StoryboardCommandError.entityNotFound("场次")
            }
            let scene = document.scenes.remove(at: source)
            document.scenes.insert(scene, at: bounded(destination, count: document.scenes.count))

        case .addShot(let sceneID, let shot, let index):
            guard let sceneIndex = document.scenes.firstIndex(where: { $0.id == sceneID }) else {
                throw StoryboardCommandError.entityNotFound("场次")
            }
            guard document.shot(id: shot.id) == nil else {
                throw StoryboardCommandError.duplicateIdentifier(shot.id)
            }
            document.scenes[sceneIndex].shots.insert(
                shot,
                at: bounded(index, count: document.scenes[sceneIndex].shots.count)
            )

        case .updateShot(let sceneID, let shotID, var shot):
            guard let sceneIndex = document.scenes.firstIndex(where: { $0.id == sceneID }),
                  let shotIndex = document.scenes[sceneIndex].shots.firstIndex(where: { $0.id == shotID }) else {
                throw StoryboardCommandError.entityNotFound("镜头")
            }
            shot.id = shotID
            document.scenes[sceneIndex].shots[shotIndex] = shot

        case .removeShot(let sceneID, let shotID):
            guard let sceneIndex = document.scenes.firstIndex(where: { $0.id == sceneID }),
                  let shotIndex = document.scenes[sceneIndex].shots.firstIndex(where: { $0.id == shotID }) else {
                throw StoryboardCommandError.entityNotFound("镜头")
            }
            document.scenes[sceneIndex].shots.remove(at: shotIndex)
            document.fieldLocks.removeAll { $0.entityID == shotID }

        case .moveShot(let sceneID, let shotID, let destination):
            guard let sceneIndex = document.scenes.firstIndex(where: { $0.id == sceneID }),
                  let shotIndex = document.scenes[sceneIndex].shots.firstIndex(where: { $0.id == shotID }) else {
                throw StoryboardCommandError.entityNotFound("镜头")
            }
            let shot = document.scenes[sceneIndex].shots.remove(at: shotIndex)
            document.scenes[sceneIndex].shots.insert(
                shot,
                at: bounded(destination, count: document.scenes[sceneIndex].shots.count)
            )

        case .addAsset(let asset):
            guard !document.assets.contains(where: { $0.id == asset.id }) else {
                throw StoryboardCommandError.duplicateIdentifier(asset.id)
            }
            document.assets.append(asset)

        case .addAssetVersion(let assetID, let version):
            guard let assetIndex = document.assets.firstIndex(where: { $0.id == assetID }) else {
                throw StoryboardCommandError.entityNotFound("素材")
            }
            guard !document.assets[assetIndex].versions.contains(where: { $0.id == version.id }) else {
                throw StoryboardCommandError.duplicateIdentifier(version.id)
            }
            document.assets[assetIndex].versions.append(version)
            document.assets[assetIndex].activeVersionID = version.id

        case .setActiveAssetVersion(let assetID, let versionID):
            guard let assetIndex = document.assets.firstIndex(where: { $0.id == assetID }) else {
                throw StoryboardCommandError.entityNotFound("素材")
            }
            guard document.assets[assetIndex].versions.contains(where: { $0.id == versionID }) else {
                throw StoryboardCommandError.entityNotFound("素材版本")
            }
            document.assets[assetIndex].activeVersionID = versionID

        case .setFieldLock(let lock, let isLocked):
            document.fieldLocks.removeAll {
                $0.entityID == lock.entityID && $0.field == lock.field
            }
            if isLocked {
                document.fieldLocks.append(lock)
            }
        }
    }

    private static func bounded(_ requested: Int?, count: Int) -> Int {
        min(max(requested ?? count, 0), count)
    }

    static func validate(_ document: StoryboardDocument) throws {
        guard document.schemaVersion == StoryboardDocument.currentSchemaVersion else {
            throw StoryboardCommandError.unsupportedSchema(document.schemaVersion)
        }
        guard document.revision >= 0 else {
            throw StoryboardCommandError.invalidValue("分镜版本号不能小于 0。")
        }

        var ids = Set<UUID>()
        try register(document.id, in: &ids)
        for scene in document.scenes {
            try register(scene.id, in: &ids)
            guard !scene.sceneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StoryboardCommandError.invalidValue("场次编号不能为空。")
            }
            if let target = scene.targetDurationSeconds, (!target.isFinite || target <= 0) {
                throw StoryboardCommandError.invalidValue("场次目标时长必须大于 0 秒。")
            }
            if let space = scene.space {
                guard space.metersWide > 0, space.metersHigh > 0 else {
                    throw StoryboardCommandError.invalidValue("场景空间尺寸必须大于 0。")
                }
                for object in space.objects { try register(object.id, in: &ids) }
            }
            for shot in scene.shots {
                try register(shot.id, in: &ids)
                guard !shot.shotNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw StoryboardCommandError.invalidValue("镜头编号不能为空。")
                }
                guard shot.durationSeconds.isFinite, shot.durationSeconds > 0 else {
                    throw StoryboardCommandError.invalidValue("镜头时长必须大于 0 秒。")
                }
                guard shot.frame.cropScale.isFinite, shot.frame.cropScale > 0 else {
                    throw StoryboardCommandError.invalidValue("画面缩放比例必须大于 0。")
                }
                for element in shot.canvasElements ?? [] {
                    try register(element.id, in: &ids)
                    guard element.size.width > 0,
                          element.size.height > 0,
                          element.opacity.isFinite,
                          (0...1).contains(element.opacity) else {
                        throw StoryboardCommandError.invalidValue("画布元素的尺寸或透明度无效。")
                    }
                }
                for character in shot.characters { try register(character.id, in: &ids) }
                for camera in shot.cameraPlacements ?? [] {
                    try register(camera.id, in: &ids)
                    guard camera.fieldOfViewDegrees.isFinite,
                          (10...160).contains(camera.fieldOfViewDegrees),
                          camera.equivalentFocalLengthMM.map({ $0.isFinite && (8...800).contains($0) }) ?? true,
                          camera.range.isFinite,
                          camera.range > 0 else {
                        throw StoryboardCommandError.invalidValue("机位视角或摄影范围无效。")
                    }
                }
                for motion in shot.cameraMotions { try register(motion.id, in: &ids) }
                for path in shot.movementPaths { try register(path.id, in: &ids) }
                for annotation in shot.annotations { try register(annotation.id, in: &ids) }
                let annotationIDs = Set(shot.annotations.map(\.id))
                var assignedAnnotationIDs = Set<UUID>()
                for layer in shot.annotationLayers ?? [] {
                    try register(layer.id, in: &ids)
                    let layerAnnotationIDs = Set(layer.annotationIDs)
                    guard layerAnnotationIDs.count == layer.annotationIDs.count else {
                        throw StoryboardCommandError.invalidValue("绘画图层包含重复笔画。")
                    }
                    guard layerAnnotationIDs.isSubset(of: annotationIDs) else {
                        throw StoryboardCommandError.invalidValue("绘画图层引用了不存在的笔画。")
                    }
                    guard assignedAnnotationIDs.isDisjoint(with: layerAnnotationIDs) else {
                        throw StoryboardCommandError.invalidValue("同一笔画不能同时属于多个绘画图层。")
                    }
                    assignedAnnotationIDs.formUnion(layerAnnotationIDs)
                }
                let imageLayerIDs = Set((shot.canvasElements ?? []).map(\.id))
                let drawingLayerIDs = Set((shot.annotationLayers ?? []).map(\.id))
                var orderedLayerIDs = Set<UUID>()
                for reference in shot.canvasLayerOrder ?? [] {
                    let exists = reference.kind == .image
                        ? imageLayerIDs.contains(reference.id)
                        : drawingLayerIDs.contains(reference.id)
                    guard exists else {
                        throw StoryboardCommandError.invalidValue("画布图层顺序引用了不存在的图层。")
                    }
                    guard orderedLayerIDs.insert(reference.id).inserted else {
                        throw StoryboardCommandError.invalidValue("画布图层顺序包含重复图层。")
                    }
                }
                for cue in shot.audioCues {
                    try register(cue.id, in: &ids)
                    guard cue.startSeconds >= 0, cue.durationSeconds >= 0 else {
                        throw StoryboardCommandError.invalidValue("声音提示的时间不能小于 0。")
                    }
                }
                if let difficulty = shot.productionDifficulty, !(1...5).contains(difficulty) {
                    throw StoryboardCommandError.invalidValue("拍摄难度必须在 1 到 5 之间。")
                }
                for path in shot.movementPaths {
                    if let start = path.startSeconds, start < 0 {
                        throw StoryboardCommandError.invalidValue("路径开始时间不能小于 0。")
                    }
                    if let duration = path.durationSeconds, duration < 0 {
                        throw StoryboardCommandError.invalidValue("路径时长不能小于 0。")
                    }
                }
            }
        }

        let assetIDs = Set(document.assets.map(\.id))
        for asset in document.assets {
            try register(asset.id, in: &ids)
            for version in asset.versions { try register(version.id, in: &ids) }
            if let activeVersionID = asset.activeVersionID,
               !asset.versions.contains(where: { $0.id == activeVersionID }) {
                throw StoryboardCommandError.invalidValue("素材的当前版本不存在。")
            }
        }
        for scene in document.scenes {
            for shot in scene.shots {
                if let assetID = shot.frame.assetID, !assetIDs.contains(assetID) {
                    throw StoryboardCommandError.invalidValue("镜头引用了不存在的画面素材。")
                }
                for element in shot.canvasElements ?? [] where !assetIDs.contains(element.assetID) {
                    throw StoryboardCommandError.invalidValue("画布元素引用了不存在的图片素材。")
                }
            }
        }
        for lock in document.fieldLocks {
            try register(lock.id, in: &ids)
        }
        if let production = document.production {
            if let script = production.script { try register(script.id, in: &ids) }
            for character in production.characters { try register(character.id, in: &ids) }
            for prop in production.props { try register(prop.id, in: &ids) }
            for location in production.locations { try register(location.id, in: &ids) }
            for log in production.agentLogs { try register(log.id, in: &ids) }
            for link in production.workflowLinks { try register(link.id, in: &ids) }
        }
    }

    private static func register(_ id: UUID, in ids: inout Set<UUID>) throws {
        guard ids.insert(id).inserted else {
            throw StoryboardCommandError.duplicateIdentifier(id)
        }
    }
}
