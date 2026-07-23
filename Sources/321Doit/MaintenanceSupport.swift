import Foundation

struct CacheCleanupResult {
    var fileCount: Int
    var byteCount: Int64
}

enum CacheMaintenance {
    static var verifiedUpdatesDirectoryURL: URL {
        let fm = FileManager.default
        let caches = (try? fm.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        return caches.appendingPathComponent("321Doit/VerifiedUpdates", isDirectory: true)
    }

    /// Removes only artifacts downloaded and cryptographically verified by
    /// UpdateChecker. Project files, reports, logs and in-progress tasks are
    /// intentionally outside this maintenance operation.
    static func clearVerifiedUpdateCache() throws -> CacheCleanupResult {
        let fm = FileManager.default
        let directory = verifiedUpdatesDirectoryURL.standardizedFileURL
        guard fm.fileExists(atPath: directory.path) else {
            return CacheCleanupResult(fileCount: 0, byteCount: 0)
        }

        let entries = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        var result = CacheCleanupResult(fileCount: 0, byteCount: 0)
        for entry in entries {
            let values = try entry.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isSymbolicLink != true else { continue }
            if values.isRegularFile == true {
                result.fileCount += 1
                result.byteCount += Int64(values.fileSize ?? 0)
            }
            try fm.removeItem(at: entry)
        }
        AppLogger.log(
            .info,
            category: "maintenance",
            "Cleared verified update cache: \(result.fileCount) files, \(result.byteCount) bytes"
        )
        return result
    }
}

enum DiagnosticBundleError: LocalizedError {
    case archiveFailed(String)

    var errorDescription: String? {
        switch self {
        case .archiveFailed(let detail):
            return "Could not create the diagnostic archive: \(detail)"
        }
    }
}

enum DiagnosticBundleExporter {
    private static let maximumLogBytes: Int64 = 20 * 1_024 * 1_024

    /// Creates a support archive containing app/runtime metadata and recent
    /// application logs only. It never copies media, projects, reports,
    /// bookmarks, pending-task payloads or Keychain webhook credentials.
    static func export(to destination: URL, settings: AppSettings) throws {
        let fm = FileManager.default
        let stagingRoot = fm.temporaryDirectory
            .appendingPathComponent("321Doit-Diagnostics-\(UUID().uuidString.lowercased())", isDirectory: true)
        defer { try? fm.removeItem(at: stagingRoot) }

        try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try diagnosticsText(settings: settings).write(
            to: stagingRoot.appendingPathComponent("diagnostics.txt"),
            atomically: true,
            encoding: .utf8
        )
        try privacyNotice.write(
            to: stagingRoot.appendingPathComponent("README-PRIVACY.txt"),
            atomically: true,
            encoding: .utf8
        )
        try writeRedactedSettings(settings, to: stagingRoot.appendingPathComponent("settings-redacted.json"))
        try copyRecentLogs(
            from: AppLogger.directoryURL(customPath: settings.logs.logFolder),
            to: stagingRoot.appendingPathComponent("Logs", isDirectory: true)
        )
        try copyInstallerDiagnostics(to: stagingRoot.appendingPathComponent("Installer", isDirectory: true))

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", stagingRoot.path, destination.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "ditto exited with status \(process.terminationStatus)"
            throw DiagnosticBundleError.archiveFailed(detail)
        }
        AppLogger.log(.info, category: "diagnostics", "Exported diagnostic bundle")
    }

    private static func diagnosticsText(settings: AppSettings) -> String {
        """
        321Doit Diagnostics
        Generated: \(iso8601String(Date()))
        App Version: \(UpdateSettings.appVersion) (\(UpdateSettings.buildNumber))
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Language: \(settings.general.language.rawValue)
        Log Level: \(settings.logs.level.rawValue)
        Text Logs: \(settings.logs.exportText)
        JSONL Logs: \(settings.logs.exportJSON)
        Log Retention Days: \(settings.logs.retentionDays)
        Update Channel: \(settings.update.receiveBeta ? "beta" : "stable")
        Automatic Update Check: \(settings.update.autoCheckForUpdates)
        """
    }

    private static var privacyNotice: String {
        """
        321Doit diagnostic bundle / 诊断包隐私说明

        This archive does not include media files, project contents, reports,
        Security-Scoped Bookmarks, pending-task payloads, or webhook secrets
        stored in Keychain. Application logs can contain local file paths and
        operational error messages. Please review the archive before sharing it.

        此压缩包不包含素材文件、项目内容、报告、安全作用域书签、待恢复任务数据，
        也不包含钥匙串中的 Webhook 密钥。应用日志可能包含本机文件路径和错误信息；
        对外发送前请自行检查压缩包内容。
        """
    }

    private static func writeRedactedSettings(_ settings: AppSettings, to url: URL) throws {
        let object: [String: Any] = [
            "settingsSchemaVersion": settings.version,
            "appearance": settings.general.appearance.rawValue,
            "language": settings.general.language.rawValue,
            "checksumAlgorithm": settings.checksum.algorithm.rawValue,
            "logLevel": settings.logs.level.rawValue,
            "logRetentionDays": settings.logs.retentionDays,
            "automaticUpdateCheck": settings.update.autoCheckForUpdates,
            "receiveBeta": settings.update.receiveBeta
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: [.atomic])
    }

    private static func copyRecentLogs(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        let files = try fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard ["log", "jsonl"].contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: keys) else { return false }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }

        var copiedBytes: Int64 = 0
        var createdDestination = false
        for file in files {
            let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            guard copiedBytes == 0 || copiedBytes + size <= maximumLogBytes else { continue }
            if !createdDestination {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                createdDestination = true
            }
            try fm.copyItem(at: file, to: destination.appendingPathComponent(file.lastPathComponent))
            copiedBytes += size
        }
    }

    private static func copyInstallerDiagnostics(to destination: URL) throws {
        let fm = FileManager.default
        let sourceDirectory = URL(fileURLWithPath: "/Library/Application Support/321Doit", isDirectory: true)
        let names = ["install-status.txt", "install.log"]
        var createdDestination = false
        for name in names {
            let source = sourceDirectory.appendingPathComponent(name)
            guard fm.isReadableFile(atPath: source.path),
                  let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else { continue }
            if !createdDestination {
                try fm.createDirectory(at: destination, withIntermediateDirectories: true)
                createdDestination = true
            }
            try fm.copyItem(at: source, to: destination.appendingPathComponent(name))
        }
    }
}
