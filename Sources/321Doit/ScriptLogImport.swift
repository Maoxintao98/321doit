import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - iPad export payload

/// Mirror of the `.321log` document produced by the iPad Scripter app. It is a
/// superset of `ScriptLogDocument`; only the fields the Mac side needs are
/// declared, and every key is optional-tolerant so future iPad versions stay
/// importable.
struct ScripterImportDocument: Codable {
    var schemaVersion: Int?
    var app: String?
    var appVersion: String?
    var projectID: UUID?
    var projectName: String?
    var shootingDays: [ShootingDay]
    var updatedAt: Date?
    var exportedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, app, appVersion, projectID, projectName, shootingDays, updatedAt, exportedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion)
        app = try c.decodeIfPresent(String.self, forKey: .app)
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
        projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
        projectName = try c.decodeIfPresent(String.self, forKey: .projectName)
        shootingDays = try c.decodeIfPresent([ShootingDay].self, forKey: .shootingDays) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt)
    }
}

struct ScripterImportSummary {
    var addedDays: Int = 0
    var mergedDays: Int = 0
    var addedScenes: Int = 0
    var addedShots: Int = 0
    var addedTakes: Int = 0
    var updatedTakes: Int = 0
}

extension ScriptLogStore {

    /// Presents an open panel and imports the chosen `.321log` (or `.json`) file,
    /// merging it into the current project by shooting day.
    func importScripterFile() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("导入 iPad 场记", "Import iPad Script Log", language: language)
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let scriptLog = UTType("com.321doit.scriptlog") {
            panel.allowedContentTypes = [scriptLog, .json]
        } else {
            panel.allowedContentTypes = [.json]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importScripterFile(at: url)
    }

    /// Imports a `.321log` file at a known URL (also used by document-open and
    /// drag-drop entry points).
    @discardableResult
    func importScripterFile(at url: URL) -> Bool {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let doc = try decoder.decode(ScripterImportDocument.self, from: data)
            guard !doc.shootingDays.isEmpty else {
                alertMessage = L10n.t("导入文件不包含任何拍摄日数据。", "The imported file contains no shooting-day data.", language: language)
                return false
            }

            // Ask the user how to apply the imported data.
            let alert = NSAlert()
            alert.messageText = L10n.t("导入 iPad 场记", "Import iPad Script Log", language: language)
            alert.informativeText = L10n.t(
                "选择导入方式：\n• 合并：按拍摄日合并，保留并更新已有数据。\n• 覆盖：用导入数据完全替换当前场记（原有场记将被清空）。",
                "Choose how to apply:\n• Merge: combine by shooting day, keeping and updating existing data.\n• Overwrite: replace the current script log entirely (existing days are cleared).",
                language: language)
            alert.addButton(withTitle: L10n.t("合并", "Merge", language: language))      // .alertFirstButtonReturn
            alert.addButton(withTitle: L10n.t("覆盖", "Overwrite", language: language))   // .alertSecondButtonReturn
            alert.addButton(withTitle: L10n.t("取消", "Cancel", language: language))      // .alertThirdButtonReturn
            let choice = alert.runModal()
            guard choice != .alertThirdButtonReturn else { return false }

            let summary: ScripterImportSummary
            if choice == .alertSecondButtonReturn {
                summary = overwriteWithImportedDays(doc.shootingDays)
            } else {
                summary = mergeImportedDays(doc.shootingDays)
            }
            presentImportSummary(summary, projectName: doc.projectName)
            return true
        } catch {
            alertMessage = L10n.t("导入失败：\(error.localizedDescription)", "Import failed: \(error.localizedDescription)", language: language)
            return false
        }
    }

    /// Replaces the project's shooting days entirely with the imported set.
    @discardableResult
    func overwriteWithImportedDays(_ importedDays: [ShootingDay]) -> ScripterImportSummary {
        var summary = ScripterImportSummary()
        summary.addedDays = importedDays.count
        summary.addedScenes = importedDays.reduce(0) { $0 + $1.scenes.count }
        summary.addedShots = importedDays.reduce(0) { $0 + $1.scenes.reduce(0) { $0 + $1.shots.count } }
        summary.addedTakes = importedDays.reduce(0) {
            $0 + $1.scenes.reduce(0) { $0 + $1.shots.reduce(0) { $0 + $1.takes.count } }
        }
        mutateProject { project in
            project.shootingDays = importedDays.sorted { $0.date < $1.date }
        }
        return summary
    }

    /// Merges imported shooting days into the project. A day is considered the
    /// same when its calendar date matches an existing day; otherwise it is
    /// appended. Within a matched day, scenes/shots/takes are merged by their
    /// natural keys (scene number, shot number, take number) so re-importing an
    /// updated export refreshes existing takes instead of duplicating them.
    @discardableResult
    func mergeImportedDays(_ importedDays: [ShootingDay]) -> ScripterImportSummary {
        var summary = ScripterImportSummary()
        let calendar = Calendar.current

        mutateProject { project in
            for incoming in importedDays {
                if let idx = project.shootingDays.firstIndex(where: {
                    calendar.isDate($0.date, inSameDayAs: incoming.date)
                }) {
                    summary.mergedDays += 1
                    Self.mergeDay(into: &project.shootingDays[idx], from: incoming, summary: &summary)
                } else {
                    summary.addedDays += 1
                    summary.addedScenes += incoming.scenes.count
                    summary.addedShots += incoming.scenes.reduce(0) { $0 + $1.shots.count }
                    summary.addedTakes += incoming.scenes.reduce(0) {
                        $0 + $1.shots.reduce(0) { $0 + $1.takes.count }
                    }
                    project.shootingDays.append(incoming)
                }
            }
            project.shootingDays.sort { $0.date < $1.date }
        }
        return summary
    }

    private static func mergeDay(into existing: inout ShootingDay,
                                 from incoming: ShootingDay,
                                 summary: inout ScripterImportSummary) {
        for incomingScene in incoming.scenes {
            if let si = existing.scenes.firstIndex(where: {
                $0.sceneNumber.caseInsensitiveCompare(incomingScene.sceneNumber) == .orderedSame
            }) {
                if !incomingScene.description.isEmpty {
                    existing.scenes[si].description = incomingScene.description
                }
                mergeScene(into: &existing.scenes[si], from: incomingScene, summary: &summary)
            } else {
                summary.addedScenes += 1
                summary.addedShots += incomingScene.shots.count
                summary.addedTakes += incomingScene.shots.reduce(0) { $0 + $1.takes.count }
                existing.scenes.append(incomingScene)
            }
        }
    }

    private static func mergeScene(into existing: inout ScriptScene,
                                   from incoming: ScriptScene,
                                   summary: inout ScripterImportSummary) {
        for incomingShot in incoming.shots {
            if let shi = existing.shots.firstIndex(where: {
                $0.shotNumber.caseInsensitiveCompare(incomingShot.shotNumber) == .orderedSame
            }) {
                mergeShot(into: &existing.shots[shi], from: incomingShot, summary: &summary)
            } else {
                summary.addedShots += 1
                summary.addedTakes += incomingShot.takes.count
                existing.shots.append(incomingShot)
            }
        }
    }

    private static func mergeShot(into existing: inout Shot,
                                  from incoming: Shot,
                                  summary: inout ScripterImportSummary) {
        for incomingTake in incoming.takes {
            if let ti = existing.takes.firstIndex(where: { $0.takeNumber == incomingTake.takeNumber }) {
                // Keep the most recently edited version of the take.
                if incomingTake.updatedAt >= existing.takes[ti].updatedAt {
                    let preservedID = existing.takes[ti].id
                    var merged = incomingTake
                    merged.id = preservedID
                    existing.takes[ti] = merged
                    summary.updatedTakes += 1
                }
            } else {
                summary.addedTakes += 1
                existing.takes.append(incomingTake)
            }
        }
        existing.takes.sort { $0.takeNumber < $1.takeNumber }
    }

    private func presentImportSummary(_ s: ScripterImportSummary, projectName: String?) {
        save()
        let header = L10n.t("iPad 场记导入完成", "iPad Script Log Imported", language: language)
        var lines: [String] = []
        if let name = projectName, !name.isEmpty {
            lines.append(L10n.t("来源项目：\(name)", "Source project: \(name)", language: language))
        }
        lines.append(L10n.t(
            "新增拍摄日 \(s.addedDays) · 合并拍摄日 \(s.mergedDays)",
            "Days added \(s.addedDays) · merged \(s.mergedDays)", language: language))
        lines.append(L10n.t(
            "新增场景 \(s.addedScenes) · 镜头 \(s.addedShots)",
            "Scenes added \(s.addedScenes) · shots \(s.addedShots)", language: language))
        lines.append(L10n.t(
            "新增 Take \(s.addedTakes) · 更新 Take \(s.updatedTakes)",
            "Takes added \(s.addedTakes) · updated \(s.updatedTakes)", language: language))

        let alert = NSAlert()
        alert.messageText = header
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: L10n.t("好", "OK", language: language))
        alert.runModal()
    }
}
