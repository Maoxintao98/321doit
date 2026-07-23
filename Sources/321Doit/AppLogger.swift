import Foundation

enum AppLogLevel: Int, Codable, Comparable {
    case debug = 0
    case detailed = 1
    case info = 2
    case warning = 3
    case error = 4

    static func < (lhs: AppLogLevel, rhs: AppLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .detailed: return "DETAIL"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

/// Persistent, local application diagnostics. Task-specific evidence remains
/// beside each offload/conversion; this logger captures the cross-tool app
/// timeline needed when a user reports that something went wrong.
enum AppLogger {
    private struct Configuration {
        var directory: URL
        var retentionDays: Int
        var minimumLevel: AppLogLevel
        var writeText: Bool
        var writeJSON: Bool
    }

    private static let queue = DispatchQueue(label: "com.321doit.application-log")
    private static var configuration = Configuration(
        directory: defaultDirectoryURL,
        retentionDays: 30,
        minimumLevel: .info,
        writeText: true,
        writeJSON: false
    )
    private static let sessionID = UUID().uuidString.lowercased()

    static var defaultDirectoryURL: URL {
        let fm = FileManager.default
        let support = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        return support.appendingPathComponent("321Doit/Logs", isDirectory: true)
    }

    static func directoryURL(customPath: String) -> URL {
        let trimmed = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultDirectoryURL : URL(fileURLWithPath: trimmed, isDirectory: true)
    }

    static func configure(
        folderPath: String,
        retentionDays: Int,
        minimumLevel: AppLogLevel,
        writeText: Bool,
        writeJSON: Bool
    ) {
        queue.sync {
            configuration = Configuration(
                directory: directoryURL(customPath: folderPath),
                retentionDays: max(1, retentionDays),
                minimumLevel: minimumLevel,
                writeText: writeText || !writeJSON,
                writeJSON: writeJSON
            )
            prepareDirectoryLocked()
            pruneExpiredFilesLocked(now: Date())
        }
    }

    static func log(_ level: AppLogLevel = .info, category: String, _ message: String) {
        queue.sync {
            guard level >= configuration.minimumLevel else { return }
            prepareDirectoryLocked()
            let now = Date()
            let cleaned = sanitized(message)
            if configuration.writeText {
                let line = "[\(timestamp(now))] [\(level.label)] [\(category)] \(cleaned)\n"
                appendLocked(Data(line.utf8), to: fileURLLocked(for: now, extension: "log"))
            }
            if configuration.writeJSON {
                let object: [String: Any] = [
                    "timestamp": timestamp(now),
                    "level": level.label.lowercased(),
                    "category": category,
                    "message": cleaned,
                    "sessionID": sessionID,
                    "appVersion": appVersionString,
                    "appBuild": appBuildNumberString
                ]
                if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
                    var line = data
                    line.append(0x0A)
                    appendLocked(line, to: fileURLLocked(for: now, extension: "jsonl"))
                }
            }
        }
    }

    static func logSessionStart() {
        log(.info, category: "lifecycle", "Started 321Doit \(appVersionString) build \(appBuildNumberString); macOS \(osVersionDisplay())")
    }

    private static func prepareDirectoryLocked() {
        do {
            try FileManager.default.createDirectory(at: configuration.directory, withIntermediateDirectories: true)
        } catch {
            NSLog("[321Doit] could not create log directory: %@", error.localizedDescription)
        }
    }

    private static func pruneExpiredFilesLocked(now: Date) {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let files = try? fm.contentsOfDirectory(
            at: configuration.directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = now.addingTimeInterval(-TimeInterval(configuration.retentionDays) * 86_400)
        for file in files where file.lastPathComponent.hasPrefix("321Doit-")
            && ["log", "jsonl"].contains(file.pathExtension.lowercased()) {
            guard let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified < cutoff else { continue }
            try? fm.removeItem(at: file)
        }
    }

    private static func fileURLLocked(for date: Date, extension ext: String) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return configuration.directory.appendingPathComponent("321Doit-\(formatter.string(from: date)).\(ext)")
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func sanitized(_ message: String) -> String {
        let oneLine = message
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
        return String(oneLine.prefix(32_768))
    }

    private static func appendLocked(_ data: Data, to url: URL) {
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url, options: .atomic)
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            NSLog("[321Doit] could not append application log: %@", error.localizedDescription)
        }
    }
}
