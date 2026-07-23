import Combine
import Foundation
import AppKit
import AVFoundation

struct StoryboardCanvasImageImport {
    var assetID: UUID
    var data: Data
    var fileExtension: String
    var name: String
}

@MainActor
final class StoryboardStore: ObservableObject {
    @Published private(set) var document: StoryboardDocument
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published var errorMessage: String?

    private var commandBus: StoryboardCommandBus
    private(set) var storageURL: URL?

    init() {
        let initial = StoryboardDocument()
        document = initial
        commandBus = try! StoryboardCommandBus(document: initial)
    }

    func configure(
        linkedProjectID: UUID?,
        projectFolderURL: URL?,
        title: String?
    ) {
        let destination: URL
        if let projectFolderURL {
            destination = StoryboardRepository.storyboardJSONURL(for: projectFolderURL)
        } else {
            let support = (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? FileManager.default.temporaryDirectory
            destination = support
                .appendingPathComponent("321Doit/Storyboard", isDirectory: true)
                .appendingPathComponent("independent-storyboard.json")
        }

        guard destination != storageURL else { return }

        do {
            let loaded: StoryboardDocument
            if FileManager.default.fileExists(atPath: destination.path) {
                loaded = try StoryboardRepository.load(from: destination)
            } else {
                let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
                loaded = StoryboardDocument(
                    linkedProjectID: linkedProjectID,
                    title: normalizedTitle?.isEmpty == false ? "\(normalizedTitle!) · 分镜" : "未命名分镜"
                )
            }
            commandBus = try StoryboardCommandBus(document: loaded)
            storageURL = destination
            publish()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() {
        guard let storageURL else { return }
        do {
            let loaded = try StoryboardRepository.load(from: storageURL)
            commandBus = try StoryboardCommandBus(document: loaded)
            publish()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func perform(
        title: String,
        source: StoryboardCommandSource = .ui,
        mutations: [StoryboardMutation]
    ) -> Bool {
        let previous = commandBus
        do {
            try commandBus.apply(StoryboardTransaction(
                baseRevision: commandBus.document.revision,
                source: source,
                title: title,
                mutations: mutations
            ))
            try persist()
            publish()
            return true
        } catch {
            commandBus = previous
            errorMessage = error.localizedDescription
            return false
        }
    }

    func assetURL(for assetID: UUID?) -> URL? {
        guard let assetID,
              let asset = document.assets.first(where: { $0.id == assetID }),
              let versionID = asset.activeVersionID,
              let version = asset.versions.first(where: { $0.id == versionID }),
              let storageURL else { return nil }
        return try? StoryboardRepository.resolveAssetURL(
            relativePath: version.relativePath,
            storyboardURL: storageURL
        )
    }

    func imageURL(for assetID: UUID?) -> URL? { assetURL(for: assetID) }

    func image(for assetID: UUID?) -> NSImage? {
        guard let url = imageURL(for: assetID) else { return nil }
        return NSImage(contentsOf: url)
    }

    func assetVersionURL(assetID: UUID, versionID: UUID) -> URL? {
        guard let storageURL,
              let version = document.assets.first(where: { $0.id == assetID })?
                .versions.first(where: { $0.id == versionID }) else { return nil }
        return try? StoryboardRepository.resolveAssetURL(
            relativePath: version.relativePath,
            storyboardURL: storageURL
        )
    }

    func image(assetID: UUID, versionID: UUID) -> NSImage? {
        assetVersionURL(assetID: assetID, versionID: versionID).flatMap(NSImage.init(contentsOf:))
    }

    func saveCopy(toProjectFolder projectFolder: URL) throws {
        guard let sourceStoryboardURL = storageURL else { return }
        let destinationStoryboardURL = StoryboardRepository.storyboardJSONURL(for: projectFolder)
        let sourceRoot = sourceStoryboardURL.deletingLastPathComponent().standardizedFileURL
        let destinationRoot = destinationStoryboardURL.deletingLastPathComponent().standardizedFileURL

        if sourceRoot != destinationRoot {
            for asset in document.assets {
                for version in asset.versions {
                    let sourceURL = try StoryboardRepository.resolveAssetURL(
                        relativePath: version.relativePath,
                        storyboardURL: sourceStoryboardURL
                    )
                    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                        throw StoryboardCommandError.invalidValue("分镜中的一张图片已丢失，无法保留项目。")
                    }
                    let destinationURL = try StoryboardRepository.resolveAssetURL(
                        relativePath: version.relativePath,
                        storyboardURL: destinationStoryboardURL
                    )
                    try FileManager.default.createDirectory(
                        at: destinationURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try Data(contentsOf: sourceURL).write(to: destinationURL, options: .atomic)
                }
            }
        }

        try StoryboardRepository.saveProjectStoryboard(document, to: projectFolder)
    }

    @discardableResult
    func commitCanvasEdits(
        sceneID: UUID,
        shot: StoryboardShot,
        imports: [StoryboardCanvasImageImport]
    ) -> Bool {
        guard let storageURL else {
            errorMessage = "分镜项目尚未配置保存位置。"
            return false
        }
        guard imports.allSatisfy({ NSImage(data: $0.data) != nil }) else {
            errorMessage = "有图片无法读取。"
            return false
        }

        var writtenURLs: [URL] = []
        var mutations: [StoryboardMutation] = []
        do {
            for item in imports {
                let versionID = UUID()
                let fileExtension = normalizedImageExtension(item.fileExtension)
                let relativePath = "storyboard_assets/\(item.assetID.uuidString)/\(versionID.uuidString).\(fileExtension)"
                let fileURL = storageURL.deletingLastPathComponent().appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try item.data.write(to: fileURL, options: .atomic)
                writtenURLs.append(fileURL)
                let version = StoryboardAssetVersion(
                    id: versionID,
                    relativePath: relativePath,
                    source: "canvas-import",
                    createdBy: StoryboardCreatedBy.imported.rawValue
                )
                mutations.append(.addAsset(asset: StoryboardAsset(
                    id: item.assetID,
                    name: item.name,
                    versions: [version],
                    activeVersionID: versionID,
                    kind: .image
                )))
            }
            mutations.append(.updateShot(sceneID: sceneID, shotID: shot.id, shot: shot))
            let succeeded = perform(title: "更新分层画面", source: imports.isEmpty ? .ui : .importer, mutations: mutations)
            if !succeeded { writtenURLs.forEach { try? FileManager.default.removeItem(at: $0) } }
            return succeeded
        } catch {
            writtenURLs.forEach { try? FileManager.default.removeItem(at: $0) }
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func importFrameImage(
        data: Data,
        fileExtension: String,
        name: String,
        source: String,
        prompt: String? = nil,
        sceneID: UUID,
        shot: StoryboardShot
    ) -> Bool {
        guard NSImage(data: data) != nil else {
            errorMessage = "无法读取这张图片。"
            return false
        }
        guard let storageURL else {
            errorMessage = "分镜项目尚未配置保存位置。"
            return false
        }

        let assetID = shot.frame.assetID ?? UUID()
        let versionID = UUID()
        let safeExtension = normalizedImageExtension(fileExtension)
        let relativePath = "storyboard_assets/\(assetID.uuidString)/\(versionID.uuidString).\(safeExtension)"
        let fileURL = storageURL.deletingLastPathComponent().appendingPathComponent(relativePath)

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)

            let parentVersionID = document.assets
                .first(where: { $0.id == assetID })?
                .activeVersionID
            let version = StoryboardAssetVersion(
                id: versionID,
                relativePath: relativePath,
                source: source,
                parentVersionID: parentVersionID,
                prompt: prompt,
                createdBy: source
            )
            var updatedShot = shot
            updatedShot.frame.assetID = assetID

            let assetMutation: StoryboardMutation
            if document.assets.contains(where: { $0.id == assetID }) {
                assetMutation = .addAssetVersion(assetID: assetID, version: version)
            } else {
                assetMutation = .addAsset(asset: StoryboardAsset(
                    id: assetID,
                    name: name,
                    versions: [version],
                    activeVersionID: versionID,
                    kind: .image
                ))
            }

            let succeeded = perform(
                title: "更新镜头画面",
                source: source == "imported" ? .importer : .ui,
                mutations: [
                    assetMutation,
                    .updateShot(sceneID: sceneID, shotID: shot.id, shot: updatedShot)
                ]
            )
            if !succeeded { try? FileManager.default.removeItem(at: fileURL) }
            return succeeded
        } catch {
            errorMessage = error.localizedDescription
            try? FileManager.default.removeItem(at: fileURL)
            return false
        }
    }

    @discardableResult
    func importAudio(
        from sourceURL: URL,
        cueKind: StoryboardAudioCueKind,
        sceneID: UUID,
        shot: StoryboardShot
    ) -> Bool {
        guard let storageURL else {
            errorMessage = "分镜项目尚未配置保存位置。"
            return false
        }
        let assetID = UUID()
        let versionID = UUID()
        let rawExtension = sourceURL.pathExtension.lowercased()
        let allowed = ["wav", "aif", "aiff", "mp3", "m4a", "aac", "caf", "flac"]
        let fileExtension = allowed.contains(rawExtension) ? rawExtension : "wav"
        let relativePath = "storyboard_audio/\(assetID.uuidString)/\(versionID.uuidString).\(fileExtension)"
        let targetURL = storageURL.deletingLastPathComponent().appendingPathComponent(relativePath)

        do {
            try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: targetURL)
            let audioFile = try? AVAudioFile(forReading: sourceURL)
            let measured = audioFile.map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
            let duration = measured.isFinite && measured > 0 ? min(measured, max(shot.durationSeconds, 0.1)) : max(shot.durationSeconds, 0.1)
            let version = StoryboardAssetVersion(
                id: versionID,
                relativePath: relativePath,
                source: "audio-import",
                createdBy: StoryboardCreatedBy.imported.rawValue
            )
            let asset = StoryboardAsset(
                id: assetID,
                name: sourceURL.lastPathComponent,
                versions: [version],
                activeVersionID: versionID,
                kind: .audio
            )
            var updatedShot = shot
            updatedShot.audioCues.append(StoryboardAudioCue(
                kind: cueKind,
                text: sourceURL.deletingPathExtension().lastPathComponent,
                startSeconds: 0,
                durationSeconds: duration,
                assetID: assetID
            ))
            let succeeded = perform(title: "导入临时声音", mutations: [
                .addAsset(asset: asset),
                .updateShot(sceneID: sceneID, shotID: shot.id, shot: updatedShot)
            ])
            if !succeeded { try? FileManager.default.removeItem(at: targetURL) }
            return succeeded
        } catch {
            errorMessage = error.localizedDescription
            try? FileManager.default.removeItem(at: targetURL)
            return false
        }
    }

    @discardableResult
    func importReferenceImage(from sourceURL: URL) -> UUID? {
        guard let data = try? Data(contentsOf: sourceURL), NSImage(data: data) != nil else {
            errorMessage = "无法读取参考图片。"
            return nil
        }
        guard let storageURL else {
            errorMessage = "分镜项目尚未配置保存位置。"
            return nil
        }
        let assetID = UUID()
        let versionID = UUID()
        let fileExtension = normalizedImageExtension(sourceURL.pathExtension)
        let relativePath = "storyboard_references/\(assetID.uuidString)/\(versionID.uuidString).\(fileExtension)"
        let targetURL = storageURL.deletingLastPathComponent().appendingPathComponent(relativePath)
        do {
            try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: targetURL, options: .atomic)
            let version = StoryboardAssetVersion(
                id: versionID,
                relativePath: relativePath,
                source: "reference-import",
                createdBy: StoryboardCreatedBy.imported.rawValue
            )
            let asset = StoryboardAsset(
                id: assetID,
                name: sourceURL.lastPathComponent,
                versions: [version],
                activeVersionID: versionID,
                kind: .reference
            )
            guard perform(title: "导入视觉参考", mutations: [.addAsset(asset: asset)]) else {
                try? FileManager.default.removeItem(at: targetURL)
                return nil
            }
            return assetID
        } catch {
            errorMessage = error.localizedDescription
            try? FileManager.default.removeItem(at: targetURL)
            return nil
        }
    }

    private func normalizedImageExtension(_ value: String) -> String {
        let candidate = value.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        return ["png", "jpg", "jpeg", "heic", "tif", "tiff"].contains(candidate) ? candidate : "png"
    }

    func undo() {
        let previous = commandBus
        guard commandBus.undo() != nil else { return }
        do {
            try persist()
            publish()
        } catch {
            commandBus = previous
            errorMessage = error.localizedDescription
        }
    }

    func redo() {
        let previous = commandBus
        guard commandBus.redo() != nil else { return }
        do {
            try persist()
            publish()
        } catch {
            commandBus = previous
            errorMessage = error.localizedDescription
        }
    }

    func previewPatch(
        _ patch: StoryboardPatch,
        accepting operationIDs: Set<UUID>? = nil,
        language: AppLanguage = .system
    ) throws -> StoryboardPatchPreview {
        try StoryboardPatchEngine.preview(patch, in: commandBus.document, accepting: operationIDs, language: language)
    }

    @discardableResult
    func applyPatch(
        _ patch: StoryboardPatch,
        accepting operationIDs: Set<UUID>,
        authorization: StoryboardAgentAuthorization,
        language: AppLanguage = .system
    ) -> Bool {
        let previous = commandBus
        do {
            let permissionMode = commandBus.document.production?.agentPermissionMode ?? .collaborate
            try StoryboardAgentAuthorizationPolicy.validate(
                permissionMode: permissionMode,
                authorization: authorization,
                operationIDs: operationIDs
            )
            _ = try StoryboardPatchEngine.preview(patch, in: commandBus.document, accepting: operationIDs, language: language)
            var mutations = try StoryboardPatchEngine.mutations(
                for: patch,
                in: commandBus.document,
                accepting: operationIDs
            )
            guard !mutations.isEmpty else {
                throw StoryboardCommandError.emptyTransaction
            }
            var production = commandBus.document.production ?? StoryboardProductionData()
            let affected = Set(patch.operations
                .filter { operationIDs.contains($0.id) }
                .flatMap { operation -> [UUID] in
                    switch operation.kind {
                    case .createShot(_, _, let shot): return [shot.id]
                    case .updateShot(_, let shotID, _), .deleteShot(_, let shotID), .moveShot(_, let shotID, _): return [shotID]
                    case .updateScene(let sceneID, _): return [sceneID]
                    }
                })
            production.agentLogs.append(StoryboardAgentLogEntry(
                agentName: patch.agentName,
                model: patch.model,
                userInstruction: patch.userInstruction,
                tools: ["storyboard_create_patch", "storyboard_preview_patch", "storyboard_apply_patch"],
                affectedEntityIDs: Array(affected),
                patchID: patch.id,
                confirmed: authorization.confirmedByUser,
                result: "应用 \(operationIDs.count) 项修改"
            ))
            mutations.append(.updateProduction(production))
            try commandBus.apply(StoryboardTransaction(
                id: patch.id,
                baseRevision: patch.baseRevision,
                source: .agent,
                title: patch.description,
                mutations: mutations
            ))
            try persist()
            publish()
            return true
        } catch {
            commandBus = previous
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func persist() throws {
        guard let storageURL else { return }
        try StoryboardRepository.save(commandBus.document, to: storageURL)
    }

    private func publish() {
        document = commandBus.document
        canUndo = commandBus.canUndo
        canRedo = commandBus.canRedo
    }
}
