import AppKit
import Foundation

extension ScriptLogStore {

    /// Folder created at each destination root to hold copied script logs.
    static let offloadScriptLogFolderName = "_ScriptLog"

    /// Self-contained `.321log` payload written alongside the offload. Mirrors the
    /// iPad export so the same file can be re-imported on any Mac.
    private struct OffloadScriptLogDocument: Codable {
        var schemaVersion: Int = 1
        var app: String = "321Doit (Mac)"
        var projectID: UUID
        var projectName: String
        var shootingDays: [ShootingDay]
        var updatedAt: Date
        var exportedAt: Date
    }

    /// Copies the current script log into `<root>/_ScriptLog/` for every
    /// destination root produced by a successful offload. Writes a `.321log`
    /// (JSON, re-importable) plus a CSV for quick reference. Best-effort:
    /// failures surface via `alertMessage` but never interrupt the offload.
    func copyScriptLog(toTargetRoots roots: [URL]) {
        guard !roots.isEmpty, !project.shootingDays.isEmpty else { return }

        let base = OutputFileNamer.fileName(
            projectName: project.displayName,
            date: Date(),
            attribute: L10n.t("场记", "ScriptLog", language: language),
            extension: ""
        )
        let safeBase = base.isEmpty ? "ScriptLog" : base

        let doc = OffloadScriptLogDocument(
            projectID: project.id,
            projectName: project.displayName,
            shootingDays: project.shootingDays,
            updatedAt: Date(),
            exportedAt: Date())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        var failures: [String] = []
        var firstDir: URL?

        for root in roots {
            let needsScope = root.startAccessingSecurityScopedResource()
            defer { if needsScope { root.stopAccessingSecurityScopedResource() } }

            let dir = root.appendingPathComponent(Self.offloadScriptLogFolderName, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

                let logURL = dir.appendingPathComponent("\(safeBase).321log")
                try encoder.encode(doc).write(to: logURL, options: .atomic)

                let csvURL = dir.appendingPathComponent("\(safeBase).csv")
                do {
                    try ScriptLogExporter.writeCSV(project: project, language: language, to: csvURL)
                } catch {
                    failures.append("\(root.lastPathComponent) CSV: \(error.localizedDescription)")
                    AppLogger.log(.warning, category: "script-log", "Could not write offload CSV copy: \(error.localizedDescription)")
                }

                if firstDir == nil { firstDir = dir }
            } catch {
                failures.append("\(root.lastPathComponent): \(error.localizedDescription)")
                AppLogger.log(.warning, category: "script-log", "Could not write offload script-log copy: \(error.localizedDescription)")
            }
        }

        if failures.isEmpty {
            lastExportURL = firstDir
        } else {
            alertMessage = L10n.t(
                "场记随拷盘复制部分失败：\(failures.joined(separator: "；"))",
                "Some script-log copies failed during offload: \(failures.joined(separator: "; "))",
                language: language)
        }
    }
}
