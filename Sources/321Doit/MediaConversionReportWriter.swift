import Foundation

enum MediaConversionReportWriter {
    static func write(
        _ report: MediaConversionReport,
        beside outputURL: URL,
        linkedProjectFolderURL: URL? = nil
    ) throws -> URL {
        let portableDirectory = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".321doit", isDirectory: true)
            .appendingPathComponent("conversion", isDirectory: true)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            let portableURL = try write(data, taskID: report.taskID, directory: portableDirectory)
            if let projectFolder = linkedProjectFolderURL {
                let projectDirectory = projectFolder
                    .appendingPathComponent(".321doit", isDirectory: true)
                    .appendingPathComponent("conversion", isDirectory: true)
                if projectDirectory.standardizedFileURL != portableDirectory.standardizedFileURL {
                    _ = try write(data, taskID: report.taskID, directory: projectDirectory)
                }
            }
            return portableURL
        } catch {
            throw MediaConversionError.reportFailed
        }
    }

    private static func write(_ data: Data, taskID: UUID, directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let finalURL = directory.appendingPathComponent("\(taskID.uuidString.lowercased()).json")
        let temporaryURL = directory.appendingPathComponent(".\(taskID.uuidString).tmp")
        try data.write(to: temporaryURL, options: .atomic)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: finalURL)
        return finalURL
    }
}
