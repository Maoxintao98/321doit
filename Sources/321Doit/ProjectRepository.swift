import Foundation

enum ProjectRepository {

    static let projectFileExtension = "321doit"
    static let projectContentTypeIdentifier = "com.321doit.project"

    static func projectPackageURL(in parent: URL, projectName: String) -> URL {
        parent.appendingPathComponent(
            "\(sanitizedProjectName(projectName)).\(projectFileExtension)",
            isDirectory: true
        ).standardizedFileURL
    }

    static func normalizedProjectPackageURL(_ url: URL) -> URL {
        guard url.pathExtension.lowercased() != projectFileExtension else {
            return url.standardizedFileURL
        }
        return url.appendingPathExtension(projectFileExtension).standardizedFileURL
    }

    enum RepositoryError: LocalizedError {
        case unsupportedSchema(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedSchema(let version):
                return "This project was saved with unsupported project schema \(version)."
            }
        }
    }

    private struct ProjectStateEnvelope: Codable {
        var schemaVersion: Int = 1
        var savedAt: Date
        var project: Project
    }

    static func storageDirectory(for folder: URL) -> URL {
        folder.appendingPathComponent("_321Doit", isDirectory: true)
    }

    static func projectJSONURL(for folder: URL) -> URL {
        storageDirectory(for: folder).appendingPathComponent("project.json")
    }

    static func scriptLogJSONURL(for folder: URL) -> URL {
        storageDirectory(for: folder).appendingPathComponent("script_log.json")
    }

    static func projectStateJSONURL(for folder: URL) -> URL {
        storageDirectory(for: folder).appendingPathComponent("project_state.json")
    }

    static func reportsDirectory(for folder: URL) -> URL {
        storageDirectory(for: folder).appendingPathComponent("reports", isDirectory: true)
    }

    static func backupsDirectory(for folder: URL) -> URL {
        storageDirectory(for: folder).appendingPathComponent("backups/project", isDirectory: true)
    }

    static func load(from folder: URL) throws -> Project {
        let fm = FileManager.default
        let stateURL = projectStateJSONURL(for: folder)
        if fm.fileExists(atPath: stateURL.path) {
            let state: ProjectStateEnvelope
            do {
                state = try decodeState(at: stateURL)
            } catch let error as RepositoryError {
                // A newer schema is not corruption. Refuse to downgrade it
                // silently because doing so could discard fields this build
                // does not understand.
                throw error
            } catch {
                if let legacy = try? loadLegacy(from: folder, requireMatchingProjectID: true) {
                    AppLogger.log(.warning, category: "project", "Recovered a corrupt canonical project snapshot from its compatibility files")
                    return legacy
                }
                if let backup = try? loadNewestBackup(from: folder) {
                    AppLogger.log(.warning, category: "project", "Recovered a corrupt project from the newest valid local backup")
                    return backup
                }
                throw error
            }
            // If both legacy files are newer than the canonical snapshot, an
            // older 321Doit release edited the project after this version did.
            // Import that consistent pair instead of hiding the downgrade's
            // edits. A single newer legacy file is treated as a torn write.
            if legacyPairIsNewer(than: stateURL, folder: folder),
               let legacy = try? loadLegacy(from: folder, requireMatchingProjectID: true) {
                return legacy
            }
            return state.project
        }

        do {
            return try loadLegacy(from: folder, requireMatchingProjectID: false)
        } catch {
            if let backup = try? loadNewestBackup(from: folder) {
                AppLogger.log(.warning, category: "project", "Recovered an unreadable legacy project from the newest valid local backup")
                return backup
            }
            throw error
        }
    }

    private static func decodeState(at url: URL) throws -> ProjectStateEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(ProjectStateEnvelope.self, from: Data(contentsOf: url))
        guard state.schemaVersion == 1 else { throw RepositoryError.unsupportedSchema(state.schemaVersion) }
        return state
    }

    private static func loadNewestBackup(from folder: URL) throws -> Project {
        let directory = backupsDirectory(for: folder)
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "json" }
        let sorted = urls.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        var lastError: Error = CocoaError(.fileReadCorruptFile)
        for url in sorted {
            do { return try decodeState(at: url).project }
            catch { lastError = error }
        }
        throw lastError
    }

    private static func loadLegacy(from folder: URL, requireMatchingProjectID: Bool) throws -> Project {
        let fm = FileManager.default
        let storage = storageDirectory(for: folder)
        var loaded = Project()
        var metadataProjectID: UUID?

        let projectURL = storage.appendingPathComponent("project.json")
        if fm.fileExists(atPath: projectURL.path) {
            let data = try Data(contentsOf: projectURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let metadata = try decoder.decode(ProjectMetadata.self, from: data)
            metadataProjectID = metadata.id
            loaded = metadata.project(shootingDays: [])
        }

        let scriptURL = storage.appendingPathComponent("script_log.json")
        if fm.fileExists(atPath: scriptURL.path) {
            let data = try Data(contentsOf: scriptURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let document = try decoder.decode(ScriptLogDocument.self, from: data)
            if requireMatchingProjectID,
               let metadataProjectID,
               metadataProjectID != document.projectID {
                throw CocoaError(.fileReadCorruptFile)
            }
            loaded.id = document.projectID
            loaded.shootingDays = document.shootingDays
        }

        return loaded
    }

    private static func legacyPairIsNewer(than stateURL: URL, folder: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let stateDate = try? stateURL.resourceValues(forKeys: keys).contentModificationDate else {
            return false
        }
        let legacyURLs = [projectJSONURL(for: folder), scriptLogJSONURL(for: folder)]
        return legacyURLs.allSatisfy { url in
            guard let date = try? url.resourceValues(forKeys: keys).contentModificationDate else { return false }
            return date > stateDate
        }
    }

    static func save(_ project: Project, to folder: URL) throws {
        let fm = FileManager.default
        let storage = storageDirectory(for: folder)
        let reports = reportsDirectory(for: folder)
        try fm.createDirectory(at: storage, withIntermediateDirectories: true)
        try fm.createDirectory(at: reports, withIntermediateDirectories: true)

        try createBackupIfNeeded(for: folder)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        // Prepare the canonical all-in-one snapshot. It is committed only after
        // both compatibility files, so its atomic replacement is the revision
        // boundary readers trust.
        let state = ProjectStateEnvelope(savedAt: Date(), project: project)
        let stateData = try encoder.encode(state)

        let metadata = try encoder.encode(project.metadataOnly)
        try metadata.write(to: projectJSONURL(for: folder), options: .atomic)

        let document = ScriptLogDocument(projectID: project.id, shootingDays: project.shootingDays, updatedAt: Date())
        let scriptLog = try encoder.encode(document)
        try scriptLog.write(to: scriptLogJSONURL(for: folder), options: .atomic)
        try stateData.write(to: projectStateJSONURL(for: folder), options: .atomic)
    }

    private static func createBackupIfNeeded(for folder: URL) throws {
        let fm = FileManager.default
        let stateURL = projectStateJSONURL(for: folder)
        guard fm.fileExists(atPath: stateURL.path) else { return }
        // Never preserve a corrupt file as the recovery point.
        _ = try decodeState(at: stateURL)

        let directory = backupsDirectory(for: folder)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let newestDate = existing.compactMap {
            try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }.max()
        if let newestDate, Date().timeIntervalSince(newestDate) < 300 { return }

        let stamp = Int(Date().timeIntervalSince1970 * 1_000)
        let backupURL = directory.appendingPathComponent("project_state-\(stamp)-\(UUID().uuidString.lowercased()).json")
        try fm.copyItem(at: stateURL, to: backupURL)

        let retained = ((try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []).sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
        for expired in retained.dropFirst(20) {
            try? fm.removeItem(at: expired)
        }
    }

    static func isProjectFolder(_ url: URL) -> Bool {
        let fm = FileManager.default
        let storage = storageDirectory(for: url)
        return fm.fileExists(atPath: storage.appendingPathComponent("project_state.json").path)
            || fm.fileExists(atPath: storage.appendingPathComponent("project.json").path)
            || fm.fileExists(atPath: storage.appendingPathComponent("script_log.json").path)
    }

    private static func sanitizedProjectName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let name = trimmed.components(separatedBy: illegal).joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return name.isEmpty ? "Untitled" : name
    }
}
