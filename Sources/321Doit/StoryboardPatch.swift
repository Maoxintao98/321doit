import Foundation

enum StoryboardPatchRisk: String, Codable, CaseIterable {
    case low
    case medium
    case high
}

enum StoryboardPatchOperationKind: Codable, Equatable {
    case createShot(sceneID: UUID, afterShotID: UUID?, shot: StoryboardShot)
    case updateShot(sceneID: UUID, shotID: UUID, replacement: StoryboardShot)
    case deleteShot(sceneID: UUID, shotID: UUID)
    case moveShot(sceneID: UUID, shotID: UUID, destination: Int)
    case updateScene(sceneID: UUID, replacement: StoryboardScene)
}

struct StoryboardPatchOperation: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: StoryboardPatchOperationKind
    var reason: String
    var risk: StoryboardPatchRisk

    init(
        id: UUID = UUID(),
        kind: StoryboardPatchOperationKind,
        reason: String,
        risk: StoryboardPatchRisk
    ) {
        self.id = id
        self.kind = kind
        self.reason = reason
        self.risk = risk
    }
}

struct StoryboardPatchConstraints: Codable, Equatable {
    var maximumDurationSeconds: Double?
    var preserveScreenDirection: Bool
    var lockedShotIDs: [UUID]

    init(
        maximumDurationSeconds: Double? = nil,
        preserveScreenDirection: Bool = false,
        lockedShotIDs: [UUID] = []
    ) {
        self.maximumDurationSeconds = maximumDurationSeconds
        self.preserveScreenDirection = preserveScreenDirection
        self.lockedShotIDs = lockedShotIDs
    }
}

struct StoryboardPatch: Identifiable, Codable, Equatable {
    var id: UUID
    var projectID: UUID
    var sceneID: UUID
    var baseRevision: Int
    var description: String
    var createdAt: Date
    var operations: [StoryboardPatchOperation]
    var constraints: StoryboardPatchConstraints
    var agentName: String
    var model: String
    var userInstruction: String

    init(
        id: UUID = UUID(),
        projectID: UUID,
        sceneID: UUID,
        baseRevision: Int,
        description: String,
        createdAt: Date = Date(),
        operations: [StoryboardPatchOperation],
        constraints: StoryboardPatchConstraints = StoryboardPatchConstraints(),
        agentName: String,
        model: String,
        userInstruction: String
    ) {
        self.id = id
        self.projectID = projectID
        self.sceneID = sceneID
        self.baseRevision = baseRevision
        self.description = description
        self.createdAt = createdAt
        self.operations = operations
        self.constraints = constraints
        self.agentName = agentName
        self.model = model
        self.userInstruction = userInstruction
    }
}

enum StoryboardPatchChangeKind: String, Codable {
    case created
    case updated
    case deleted
    case moved
}

struct StoryboardPatchDiff: Identifiable, Codable, Equatable {
    var id: UUID
    var operationID: UUID
    var kind: StoryboardPatchChangeKind
    var shotID: UUID?
    var title: String
    var before: String
    var after: String
    var reason: String
    var risk: StoryboardPatchRisk
}

struct StoryboardPatchPreview: Codable, Equatable {
    var patch: StoryboardPatch
    var acceptedOperationIDs: Set<UUID>
    var beforeShotCount: Int
    var afterShotCount: Int
    var beforeDurationSeconds: Double
    var afterDurationSeconds: Double
    var diffs: [StoryboardPatchDiff]
    var issues: [StoryboardAnalysisIssue]
    var resultingDocument: StoryboardDocument
}

enum StoryboardPatchEngine {
    static func preview(
        _ patch: StoryboardPatch,
        in document: StoryboardDocument,
        accepting acceptedOperationIDs: Set<UUID>? = nil,
        language: AppLanguage = .system
    ) throws -> StoryboardPatchPreview {
        guard patch.projectID == document.id else {
            throw StoryboardCommandError.invalidValue(t("Patch 项目ID与当前分镜不一致。", "The patch project ID does not match the current storyboard.", language))
        }
        guard patch.baseRevision == document.revision else {
            throw StoryboardCommandError.staleRevision(expected: document.revision, received: patch.baseRevision)
        }
        guard let beforeScene = document.scene(id: patch.sceneID) else {
            throw StoryboardCommandError.entityNotFound(t("Patch 场次", "Patch scene", language))
        }
        let accepted = acceptedOperationIDs ?? Set(patch.operations.map(\.id))
        let selected = patch.operations.filter { accepted.contains($0.id) }
        let mutations = try selected.map { try mutation(for: $0, in: document) }
        var bus = try StoryboardCommandBus(document: document)
        if !mutations.isEmpty {
            try bus.apply(StoryboardTransaction(
                baseRevision: document.revision,
                source: .agent,
                title: patch.description,
                mutations: mutations
            ))
        }
        guard let afterScene = bus.document.scene(id: patch.sceneID) else {
            throw StoryboardCommandError.entityNotFound(t("Patch执行后的场次", "Scene after applying the patch", language))
        }
        let afterDuration = afterScene.shots.reduce(0) { $0 + $1.durationSeconds }
        if let maximum = patch.constraints.maximumDurationSeconds, afterDuration > maximum + 0.001 {
            throw StoryboardCommandError.invalidValue(t("Patch 执行后场次时长 \(format(afterDuration)) 秒，仍超过约束 \(format(maximum)) 秒。", "After applying the patch, the scene is \(format(afterDuration))s and still exceeds the \(format(maximum))s constraint.", language))
        }
        if !Set(patch.constraints.lockedShotIDs).isSubset(of: Set(afterScene.shots.map(\.id))) {
            throw StoryboardCommandError.invalidValue(t("Patch 删除了约束中要求保留的镜头。", "The patch removes a shot that the constraints require to be preserved.", language))
        }
        return StoryboardPatchPreview(
            patch: patch,
            acceptedOperationIDs: accepted,
            beforeShotCount: beforeScene.shots.count,
            afterShotCount: afterScene.shots.count,
            beforeDurationSeconds: beforeScene.shots.reduce(0) { $0 + $1.durationSeconds },
            afterDurationSeconds: afterDuration,
            diffs: selected.map { diff(for: $0, in: document, language: language) },
            issues: StoryboardAnalysisEngine.analyze(scene: afterScene, language: language),
            resultingDocument: bus.document
        )
    }

    static func mutations(
        for patch: StoryboardPatch,
        in document: StoryboardDocument,
        accepting acceptedOperationIDs: Set<UUID>
    ) throws -> [StoryboardMutation] {
        try patch.operations
            .filter { acceptedOperationIDs.contains($0.id) }
            .map { try mutation(for: $0, in: document) }
    }

    private static func mutation(
        for operation: StoryboardPatchOperation,
        in document: StoryboardDocument
    ) throws -> StoryboardMutation {
        switch operation.kind {
        case .createShot(let sceneID, let afterShotID, let shot):
            guard let scene = document.scene(id: sceneID) else { throw StoryboardCommandError.entityNotFound("场次") }
            let index = afterShotID.flatMap { id in scene.shots.firstIndex(where: { $0.id == id }).map { $0 + 1 } }
            return .addShot(sceneID: sceneID, shot: shot, index: index)
        case .updateShot(let sceneID, let shotID, let replacement):
            return .updateShot(sceneID: sceneID, shotID: shotID, shot: replacement)
        case .deleteShot(let sceneID, let shotID):
            return .removeShot(sceneID: sceneID, shotID: shotID)
        case .moveShot(let sceneID, let shotID, let destination):
            return .moveShot(sceneID: sceneID, shotID: shotID, destination: destination)
        case .updateScene(let sceneID, let replacement):
            return .updateScene(sceneID: sceneID, scene: replacement)
        }
    }

    private static func diff(for operation: StoryboardPatchOperation, in document: StoryboardDocument, language: AppLanguage) -> StoryboardPatchDiff {
        switch operation.kind {
        case .createShot(_, _, let shot):
            return StoryboardPatchDiff(id: UUID(), operationID: operation.id, kind: .created, shotID: shot.id, title: t("新增 \(shot.shotNumber)", "Add \(shot.shotNumber)", language), before: "—", after: summary(shot), reason: operation.reason, risk: operation.risk)
        case .updateShot(_, let shotID, let replacement):
            return StoryboardPatchDiff(id: UUID(), operationID: operation.id, kind: .updated, shotID: shotID, title: t("修改 \(replacement.shotNumber)", "Update \(replacement.shotNumber)", language), before: document.shot(id: shotID).map(summary) ?? t("不存在", "Missing", language), after: summary(replacement), reason: operation.reason, risk: operation.risk)
        case .deleteShot(_, let shotID):
            let old = document.shot(id: shotID)
            return StoryboardPatchDiff(id: UUID(), operationID: operation.id, kind: .deleted, shotID: shotID, title: t("删除 \(old?.shotNumber ?? "镜头")", "Delete \(old?.shotNumber ?? "shot")", language), before: old.map(summary) ?? t("不存在", "Missing", language), after: "—", reason: operation.reason, risk: operation.risk)
        case .moveShot(_, let shotID, let destination):
            let old = document.shot(id: shotID)
            return StoryboardPatchDiff(id: UUID(), operationID: operation.id, kind: .moved, shotID: shotID, title: t("移动 \(old?.shotNumber ?? "镜头")", "Move \(old?.shotNumber ?? "shot")", language), before: t("原顺序", "Original order", language), after: t("第 \(destination + 1) 位", "Position \(destination + 1)", language), reason: operation.reason, risk: operation.risk)
        case .updateScene(_, let replacement):
            return StoryboardPatchDiff(id: UUID(), operationID: operation.id, kind: .updated, shotID: nil, title: t("修改场次 \(replacement.sceneNumber)", "Update scene \(replacement.sceneNumber)", language), before: t("场次属性", "Scene properties", language), after: replacement.directorIntent ?? replacement.synopsis, reason: operation.reason, risk: operation.risk)
        }
    }

    private static func summary(_ shot: StoryboardShot) -> String {
        "\(shot.shotSize.rawValue) · \(shot.cameraAngle.rawValue) · \(shot.cameraMotions.first?.kind.rawValue ?? "locked") · \(format(shot.durationSeconds))s · \(StoryboardMarkdownRendering.plainText(from: shot.description))"
    }

    private static func format(_ value: Double) -> String { String(format: "%.1f", value) }
    private static func t(_ zh: String, _ en: String, _ language: AppLanguage) -> String { L10n.t(zh, en, language: language) }
}

enum StoryboardLocalAgent {
    static func propose(
        instruction: String,
        document: StoryboardDocument,
        scene: StoryboardScene,
        language: AppLanguage = .system
    ) throws -> StoryboardPatch {
        let lockedShotIDs = Set(document.fieldLocks.filter { $0.field == "*" }.map(\.entityID))
        let instructionProtectedIDs = Set(
            (instruction.contains("最后") || instruction.localizedCaseInsensitiveContains("final") || instruction.localizedCaseInsensitiveContains("last")) ? scene.shots.last.map { [$0.id] } ?? [] : []
        )
        let protectedShotIDs = lockedShotIDs.union(instructionProtectedIDs)
        var operations: [StoryboardPatchOperation] = []
        let desiredCount = extractShotCount(instruction)
        let desiredDuration = extractDuration(instruction) ?? scene.targetDurationSeconds
        let wantsIsolation = instruction.contains("孤独") || instruction.localizedCaseInsensitiveContains("isolat")
        let budgetLimited = instruction.contains("预算") || instruction.contains("轨道") || instruction.contains("摇臂") || instruction.localizedCaseInsensitiveContains("budget") || instruction.localizedCaseInsensitiveContains("track") || instruction.localizedCaseInsensitiveContains("crane")

        var simulatedShots = scene.shots
        if let desiredCount, desiredCount < simulatedShots.count {
            let candidates = simulatedShots
                .enumerated()
                .filter { !protectedShotIDs.contains($0.element.id) }
                .sorted { informationScore($0.element) < informationScore($1.element) }
            let removeCount = min(simulatedShots.count - desiredCount, candidates.count)
            for candidate in candidates.prefix(removeCount) {
                operations.append(StoryboardPatchOperation(
                    kind: .deleteShot(sceneID: scene.id, shotID: candidate.element.id),
                    reason: t("该镜头信息增量较低；删除后仍保留锁定内容和主要动作。", "This shot adds relatively little information; removing it preserves locked content and primary action.", language),
                    risk: .high
                ))
                simulatedShots.removeAll { $0.id == candidate.element.id }
            }
        }

        let durationScale: Double? = desiredDuration.flatMap { target in
            let current = simulatedShots.reduce(0) { $0 + $1.durationSeconds }
            return current > 0 ? target / current : nil
        }
        for (index, shot) in simulatedShots.enumerated() {
            guard !protectedShotIDs.contains(shot.id) else { continue }
            var changed = shot
            var reasons: [String] = []
            if let durationScale, abs(durationScale - 1) > 0.02 {
                changed.durationSeconds = max(0.6, shot.durationSeconds * durationScale)
                reasons.append(t("按目标总时长同比调整镜头节奏", "Scale shot pacing to the target total duration", language))
            }
            if wantsIsolation, index % 2 == 0 {
                changed.shotSize = .wide
                changed.cameraAngle = .high
                reasons.append(t("用更大的负空间和俯拍增强孤独感", "Use more negative space and a high angle to increase isolation", language))
            }
            if budgetLimited,
               let motion = changed.cameraMotions.first?.kind,
               [.push, .pull, .dolly, .crane, .rise, .fall, .orbit].contains(motion) {
                changed.cameraMotions[0].kind = .locked
                reasons.append(t("移除需要轨道或摇臂的运动", "Remove movement that requires a track or crane", language))
            }
            if changed != shot {
                operations.append(StoryboardPatchOperation(
                    kind: .updateShot(sceneID: scene.id, shotID: shot.id, replacement: changed),
                    reason: reasons.joined(separator: t("；", "; ", language)),
                    risk: reasons.count > 1 ? .medium : .low
                ))
            }
        }

        if operations.isEmpty {
            throw StoryboardCommandError.invalidValue(t("没有找到可安全自动执行的修改。可以明确镜头数量、目标秒数、情绪或预算限制。", "No safely executable edits were found. Specify a shot count, target duration, mood, or budget constraint.", language))
        }
        return StoryboardPatch(
            projectID: document.id,
            sceneID: scene.id,
            baseRevision: document.revision,
            description: t("根据导演指令生成场次修改方案", "Scene edit plan generated from direction", language),
            operations: operations,
            constraints: StoryboardPatchConstraints(
                maximumDurationSeconds: desiredDuration,
                preserveScreenDirection: instruction.contains("方向") || instruction.contains("越轴") || instruction.localizedCaseInsensitiveContains("direction") || instruction.localizedCaseInsensitiveContains("axis"),
                lockedShotIDs: Array(lockedShotIDs)
            ),
            agentName: t("灵动本地规划器", "Mira Local Planner", language),
            model: "deterministic-v1",
            userInstruction: instruction
        )
    }

    private static func extractShotCount(_ text: String) -> Int? {
        if let match = text.range(of: #"\d+\s*(?:个?镜头|shots?)"#, options: [.regularExpression, .caseInsensitive]) {
            return Int(text[match].filter(\.isNumber))
        }
        let chinese: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        for (key, value) in chinese where text.contains("\(key)个镜头") || text.contains("\(key)镜") { return value }
        return nil
    }

    private static func extractDuration(_ text: String) -> Double? {
        guard let match = text.range(of: #"\d+(?:\.\d+)?\s*(?:秒|seconds?|secs?)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return Double(text[match].filter { $0.isNumber || $0 == "." })
    }

    private static func informationScore(_ shot: StoryboardShot) -> Int {
        var score = 0
        if !shot.description.isEmpty { score += 2 }
        if shot.frame.assetID != nil || !shot.annotations.isEmpty { score += 1 }
        if !(shot.directorIntent ?? "").isEmpty { score += 4 }
        if shot.shotSize == .closeUp || shot.shotSize == .extremeCloseUp { score += 2 }
        if !shot.audioCues.isEmpty { score += 2 }
        return score
    }

    private static func t(_ zh: String, _ en: String, _ language: AppLanguage) -> String {
        L10n.t(zh, en, language: language)
    }
}
