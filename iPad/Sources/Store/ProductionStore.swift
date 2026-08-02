import Foundation

@MainActor
final class ProductionStore: ObservableObject {
    @Published private(set) var storyboard: StoryboardDocument
    @Published var selectedSceneID: UUID?
    @Published var selectedShotID: UUID?
    @Published var lastSavedAt: Date?

    private let fileManager = FileManager.default

    init() {
        storyboard = Self.defaultDocument()
        load()
        normalizeSelection()
    }

    var selectedScene: StoryboardScene? {
        storyboard.scenes.first { $0.id == selectedSceneID }
    }

    var selectedShot: StoryboardShot? {
        selectedScene?.shots.first { $0.id == selectedShotID }
    }

    var shotCount: Int {
        storyboard.scenes.reduce(0) { $0 + $1.shots.count }
    }

    func renameDocument(_ title: String) {
        storyboard.title = title
        touch()
    }

    func newDocument(projectID: UUID, projectName: String) {
        storyboard = Self.defaultDocument()
        storyboard.linkedProjectID = projectID
        storyboard.title = projectName
        normalizeSelection()
        saveNow()
    }

    func prepareForProject(projectID: UUID, projectName: String) {
        guard storyboard.linkedProjectID != projectID else {
            if storyboard.title == "未命名分镜" || storyboard.title == "Untitled Storyboard" {
                storyboard.title = projectName
                saveNow()
            }
            return
        }

        let isUntouched = storyboard.revision == 0
            && storyboard.scenes.count == 1
            && storyboard.scenes.first?.shots.count == 1
            && storyboard.scenes.first?.shots.first?.annotations.isEmpty == true
            && storyboard.scenes.first?.shots.first?.description.isEmpty == true
        if storyboard.linkedProjectID == nil && isUntouched {
            storyboard.linkedProjectID = projectID
            storyboard.title = projectName
            saveNow()
        } else {
            newDocument(projectID: projectID, projectName: projectName)
        }
    }

    func addScene() {
        let sceneNumber = String(storyboard.scenes.count + 1)
        let shot = StoryboardShot(shotNumber: "1")
        let scene = StoryboardScene(sceneNumber: sceneNumber, shots: [shot])
        storyboard.scenes.append(scene)
        selectedSceneID = scene.id
        selectedShotID = shot.id
        touch()
    }

    func deleteScene(_ id: UUID) {
        storyboard.scenes.removeAll { $0.id == id }
        if storyboard.scenes.isEmpty {
            let shot = StoryboardShot(shotNumber: "1")
            let scene = StoryboardScene(sceneNumber: "1", shots: [shot])
            storyboard.scenes = [scene]
            selectedSceneID = scene.id
            selectedShotID = shot.id
        } else if selectedSceneID == id {
            selectedSceneID = storyboard.scenes.first?.id
            selectedShotID = storyboard.scenes.first?.shots.first?.id
        }
        touch()
    }

    func updateSelectedScene(_ mutate: (inout StoryboardScene) -> Void) {
        guard let id = selectedSceneID,
              let index = storyboard.scenes.firstIndex(where: { $0.id == id }) else { return }
        mutate(&storyboard.scenes[index])
        touch()
    }

    func addShot() {
        guard let sceneID = selectedSceneID,
              let sceneIndex = storyboard.scenes.firstIndex(where: { $0.id == sceneID }) else { return }
        let number = String(storyboard.scenes[sceneIndex].shots.count + 1)
        let shot = storyboard.scenes[sceneIndex].shots.last?.nextShotCopy(shotNumber: number)
            ?? StoryboardShot(shotNumber: number)
        storyboard.scenes[sceneIndex].shots.append(shot)
        selectedShotID = shot.id
        touch()
    }

    func deleteShot(_ id: UUID) {
        guard let sceneID = selectedSceneID,
              let sceneIndex = storyboard.scenes.firstIndex(where: { $0.id == sceneID }) else { return }
        storyboard.scenes[sceneIndex].shots.removeAll { $0.id == id }
        if storyboard.scenes[sceneIndex].shots.isEmpty {
            let shot = StoryboardShot(shotNumber: "1")
            storyboard.scenes[sceneIndex].shots = [shot]
        }
        if selectedShotID == id {
            selectedShotID = storyboard.scenes[sceneIndex].shots.first?.id
        }
        renumberShots(sceneIndex: sceneIndex)
        touch()
    }

    func updateSelectedShot(_ mutate: (inout StoryboardShot) -> Void) {
        guard let sceneID = selectedSceneID,
              let shotID = selectedShotID,
              let sceneIndex = storyboard.scenes.firstIndex(where: { $0.id == sceneID }),
              let shotIndex = storyboard.scenes[sceneIndex].shots.firstIndex(where: { $0.id == shotID })
        else { return }
        mutate(&storyboard.scenes[sceneIndex].shots[shotIndex])
        touch()
    }

    func appendStroke(_ points: [StoryboardPoint]) {
        guard points.count > 1 else { return }
        updateSelectedShot {
            $0.annotations.append(StoryboardAnnotation(kind: .freehand, points: points))
        }
    }

    func undoLastAnnotation() {
        updateSelectedShot {
            guard !$0.annotations.isEmpty else { return }
            $0.annotations.removeLast()
        }
    }

    func clearAnnotations() {
        updateSelectedShot { $0.annotations.removeAll() }
    }

    func importReferenceImage(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        let filename = "\(UUID().uuidString).\(url.pathExtension.isEmpty ? "jpg" : url.pathExtension)"
        let destination = assetsDirectory.appendingPathComponent(filename)
        try fileManager.copyItem(at: url, to: destination)
        let version = StoryboardAssetVersion(relativePath: filename, source: "iPad import")
        let asset = StoryboardAsset(name: url.deletingPathExtension().lastPathComponent,
                                    versions: [version], kind: .image)
        storyboard.assets.append(asset)
        updateSelectedShot { $0.frame.assetID = asset.id }
    }

    func imageURL(for shot: StoryboardShot) -> URL? {
        guard let assetID = shot.frame.assetID,
              let asset = storyboard.assets.first(where: { $0.id == assetID }),
              let versionID = asset.activeVersionID,
              let version = asset.versions.first(where: { $0.id == versionID })
        else { return nil }
        return assetsDirectory.appendingPathComponent(version.relativePath)
    }

    func exportDocument(to directory: URL) throws -> URL {
        let scoped = directory.startAccessingSecurityScopedResource()
        defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
        let safeTitle = storyboard.title.replacingOccurrences(of: "/", with: "-")
        let url = directory.appendingPathComponent("\(safeTitle).321storyboard")
        try JSONEncoder.prettyISO.encode(storyboard).write(to: url, options: .atomic)
        return url
    }

    func saveNow() {
        do {
            try JSONEncoder.prettyISO.encode(storyboard).write(to: stateURL, options: .atomic)
            lastSavedAt = Date()
        } catch {
            // The parent app reports user-facing export errors. Autosave remains
            // best-effort so drawing never becomes blocked by an alert loop.
        }
    }

    private var stateURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("storyboard_state.json")
    }

    private var assetsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StoryboardAssets", isDirectory: true)
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let value = try? JSONDecoder.iso.decode(StoryboardDocument.self, from: data)
        else { return }
        storyboard = value
    }

    private func touch() {
        storyboard.updatedAt = Date()
        storyboard.revision += 1
        saveNow()
    }

    private func normalizeSelection() {
        if storyboard.scenes.isEmpty {
            storyboard = Self.defaultDocument()
        }
        selectedSceneID = storyboard.scenes.first?.id
        selectedShotID = storyboard.scenes.first?.shots.first?.id
    }

    private func renumberShots(sceneIndex: Int) {
        for index in storyboard.scenes[sceneIndex].shots.indices {
            storyboard.scenes[sceneIndex].shots[index].shotNumber = String(index + 1)
        }
    }

    private static func defaultDocument() -> StoryboardDocument {
        let shot = StoryboardShot(shotNumber: "1")
        let scene = StoryboardScene(sceneNumber: "1", shots: [shot])
        return StoryboardDocument(title: "未命名分镜", scenes: [scene])
    }
}
