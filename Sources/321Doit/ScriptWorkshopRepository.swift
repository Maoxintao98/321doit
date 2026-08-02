import Darwin
import Foundation

enum ScriptWorkshopRepositoryError: LocalizedError {
    case lockUnavailable
    case noRecoverableDocument

    var errorDescription: String? {
        switch self {
        case .lockUnavailable:
            return "The screenplay is busy in another process. Try again after refreshing."
        case .noRecoverableDocument:
            return "The screenplay is damaged and no valid local backup could be recovered."
        }
    }
}

enum ScriptWorkshopRepository {
    static func documentURL(for projectFolder: URL) -> URL {
        ProjectRepository.storageDirectory(for: projectFolder)
            .appendingPathComponent("script_workshop.json")
    }

    static func load(from url: URL) throws -> ScriptWorkshopDocument {
        do {
            return try decode(Data(contentsOf: url))
        } catch {
            for backup in backupURLs(for: url) {
                if let recovered = try? decode(Data(contentsOf: backup)) {
                    return recovered
                }
            }
            if FileManager.default.fileExists(atPath: url.path) {
                throw ScriptWorkshopRepositoryError.noRecoverableDocument
            }
            throw error
        }
    }

    static func loadProjectDocument(from projectFolder: URL) throws -> ScriptWorkshopDocument {
        try load(from: documentURL(for: projectFolder))
    }

    static func save(_ source: ScriptWorkshopDocument, to url: URL) throws {
        try withExclusiveLock(for: url) {
            try writeValidated(source, to: url, expectedRevision: nil)
        }
    }

    static func compareAndSwap(
        _ source: ScriptWorkshopDocument,
        expectedRevision: Int,
        to url: URL
    ) throws {
        try withExclusiveLock(for: url) {
            try writeValidated(source, to: url, expectedRevision: expectedRevision)
        }
    }

    static func saveProjectDocument(
        _ document: ScriptWorkshopDocument,
        to projectFolder: URL
    ) throws {
        try save(document, to: documentURL(for: projectFolder))
    }

    /// Performs one cross-process, revision-checked read/modify/write. Agent
    /// receipts can be added inside `change`, making content and idempotency
    /// one atomic screenplay commit.
    static func update<T>(
        at url: URL,
        expectedRevision: Int?,
        create: () throws -> ScriptWorkshopDocument,
        change: (inout ScriptWorkshopDocument) throws -> T
    ) throws -> (document: ScriptWorkshopDocument, result: T) {
        try withExclusiveLock(for: url) {
            var document: ScriptWorkshopDocument
            if FileManager.default.fileExists(atPath: url.path) {
                document = try load(from: url)
            } else {
                document = try create()
                document.migrateToCurrentSchema()
            }
            if let expectedRevision,
               document.documentRevision != expectedRevision {
                throw ScriptWorkshopValidationError.staleRevision(
                    expected: document.documentRevision,
                    received: expectedRevision
                )
            }
            let result = try change(&document)
            try writeValidated(document, to: url, expectedRevision: nil)
            return (document, result)
        }
    }

    private static func decode(_ data: Data) throws -> ScriptWorkshopDocument {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let version = root["schemaVersion"] as? Int,
           version > ScriptWorkshopDocument.currentSchemaVersion {
            throw ScriptWorkshopValidationError.futureSchema(version)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var document = try decoder.decode(ScriptWorkshopDocument.self, from: data)
        document.migrateToCurrentSchema()
        try ScriptWorkshopValidator.validate(document)
        return document
    }

    private static func writeValidated(
        _ source: ScriptWorkshopDocument,
        to url: URL,
        expectedRevision: Int?
    ) throws {
        var document = source
        document.migrateToCurrentSchema()
        try ScriptWorkshopValidator.validate(document)

        if let expectedRevision,
           FileManager.default.fileExists(atPath: url.path) {
            let current = try load(from: url)
            guard current.documentRevision == expectedRevision else {
                throw ScriptWorkshopValidationError.staleRevision(
                    expected: current.documentRevision,
                    received: expectedRevision
                )
            }
        }

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

    private static func withExclusiveLock<T>(
        for documentURL: URL,
        operation: () throws -> T
    ) throws -> T {
        let lockURL = documentURL.appendingPathExtension("lock")
        try FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw ScriptWorkshopRepositoryError.lockUnavailable
        }
        defer {
            _ = flock(descriptor, LOCK_UN)
            _ = Darwin.close(descriptor)
        }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw ScriptWorkshopRepositoryError.lockUnavailable
        }
        return try operation()
    }

    private static func backupDirectory(for url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent("backups/script-workshop", isDirectory: true)
    }

    private static func backupURLs(for url: URL) -> [URL] {
        let directory = backupDirectory(for: url)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
    }

    private static func createBackupIfNeeded(for url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path),
              (try? decode(Data(contentsOf: url))) != nil else {
            return
        }
        let directory = backupDirectory(for: url)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let latest = backupURLs(for: url).first,
           let modified = try? latest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
           Date().timeIntervalSince(modified) < 300 {
            return
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = directory.appendingPathComponent("\(stamp)-script-workshop.json")
        try FileManager.default.copyItem(at: url, to: backup)
        let backups = backupURLs(for: url)
        if backups.count > 20 {
            for expired in backups.dropFirst(20) {
                try? FileManager.default.removeItem(at: expired)
            }
        }
    }
}
