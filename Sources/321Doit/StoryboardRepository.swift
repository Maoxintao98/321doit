import Foundation

enum StoryboardRepository {
    static func storyboardJSONURL(for projectFolder: URL) -> URL {
        ProjectRepository.storageDirectory(for: projectFolder)
            .appendingPathComponent("storyboard.json")
    }

    static func load(from url: URL) throws -> StoryboardDocument {
        do {
            return try decode(from: url, storyboardURL: url)
        } catch {
            if let backup = try? loadNewestBackup(for: url) {
                AppLogger.log(.warning, category: "storyboard", "Recovered an unreadable storyboard from the newest valid local backup")
                return backup
            }
            throw error
        }
    }

    private static func decode(from sourceURL: URL, storyboardURL: URL) throws -> StoryboardDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(StoryboardDocument.self, from: Data(contentsOf: sourceURL))
        try StoryboardCommandBus.validate(document)
        try validateAssetPaths(in: document, storyboardURL: storyboardURL)
        return document
    }

    static func loadProjectStoryboard(from projectFolder: URL) throws -> StoryboardDocument {
        try load(from: storyboardJSONURL(for: projectFolder))
    }

    static func save(_ document: StoryboardDocument, to url: URL) throws {
        try StoryboardCommandBus.validate(document)
        try validateAssetPaths(in: document, storyboardURL: url)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try createBackupIfNeeded(for: url)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(document).write(to: url, options: .atomic)
    }

    static func backupsDirectory(for storyboardURL: URL) -> URL {
        storyboardURL.deletingLastPathComponent().appendingPathComponent("backups/storyboard", isDirectory: true)
    }

    private static func createBackupIfNeeded(for storyboardURL: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storyboardURL.path) else { return }
        _ = try decode(from: storyboardURL, storyboardURL: storyboardURL)
        let directory = backupsDirectory(for: storyboardURL)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let newest = existing.compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }.max()
        if let newest, Date().timeIntervalSince(newest) < 300 { return }

        let stamp = Int(Date().timeIntervalSince1970 * 1_000)
        let backupURL = directory.appendingPathComponent("storyboard-\(stamp)-\(UUID().uuidString.lowercased()).json")
        try fm.copyItem(at: storyboardURL, to: backupURL)
        let retained = ((try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []).sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        for expired in retained.dropFirst(20) { try? fm.removeItem(at: expired) }
    }

    private static func loadNewestBackup(for storyboardURL: URL) throws -> StoryboardDocument {
        let directory = backupsDirectory(for: storyboardURL)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }
        let sorted = urls.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        var lastError: Error = CocoaError(.fileReadCorruptFile)
        for backup in sorted {
            do { return try decode(from: backup, storyboardURL: storyboardURL) }
            catch { lastError = error }
        }
        throw lastError
    }

    static func saveProjectStoryboard(
        _ document: StoryboardDocument,
        to projectFolder: URL
    ) throws {
        try save(document, to: storyboardJSONURL(for: projectFolder))
    }

    static func resolveAssetURL(relativePath: String, storyboardURL: URL) throws -> URL {
        let normalizedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPath.isEmpty,
              !NSString(string: normalizedPath).isAbsolutePath else {
            throw StoryboardCommandError.invalidValue("分镜资产路径必须是项目内的相对路径。")
        }

        let root = storyboardURL.deletingLastPathComponent().standardizedFileURL
        let candidate = root.appendingPathComponent(normalizedPath).standardizedFileURL
        guard contains(candidate, in: root) else {
            throw StoryboardCommandError.invalidValue("分镜资产路径超出了项目目录。")
        }

        try validateSymlinkContainment(candidate: candidate, root: root)
        return candidate
    }

    private static func validateAssetPaths(in document: StoryboardDocument, storyboardURL: URL) throws {
        for asset in document.assets {
            for version in asset.versions {
                _ = try resolveAssetURL(relativePath: version.relativePath, storyboardURL: storyboardURL)
            }
        }
    }

    private static func contains(_ candidate: URL, in root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path.hasPrefix(rootPath)
    }

    private static func validateSymlinkContainment(candidate: URL, root: URL) throws {
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let relativePath = String(candidate.path.dropFirst(rootPrefix.count))
        var current = resolvedRoot

        for component in relativePath.split(separator: "/").map(String.init) {
            current = current.appendingPathComponent(component)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            guard current == resolvedRoot || contains(current, in: resolvedRoot) else {
                throw StoryboardCommandError.invalidValue("分镜资产路径通过符号链接超出了项目目录。")
            }
        }
    }
}
