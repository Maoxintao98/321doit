import AppKit
import CoreGraphics
import Foundation

enum ScriptLogExporter {
    static func writeCSV(project: Project, language: AppLanguage = .system, to url: URL) throws {
        var lines = [csvLine(csvHeaders(language: language))]
        for row in rows(project: project, language: language) {
            lines.append(csvLine(row))
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func writeJSON(project: Project, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        try data.write(to: url, options: .atomic)
    }

    static func writePDFPlaceholder(project: Project, language: AppLanguage = .system, to url: URL) throws {
        let t: (String, String) -> String = { zh, en in L10n.t(zh, en, language: language) }
        var mediaBox = CGRect(x: 0, y: 0, width: 842, height: 595)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw ExportError.couldNotCreatePDF
        }

        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 20),
            .foregroundColor: NSColor.labelColor
        ]
        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let secondaryAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let title = t("321Doit 场记单", "321Doit Script Log")
        NSString(string: title).draw(in: CGRect(x: 36, y: 540, width: 360, height: 28), withAttributes: titleAttributes)
        let days = t("\(project.shootingDays.count) 个拍摄日", "\(project.shootingDays.count) shooting day\(project.shootingDays.count == 1 ? "" : "s")")
        let takes = t("\(takeCount(project: project)) 条", "\(takeCount(project: project)) take\(takeCount(project: project) == 1 ? "" : "s")")
        NSString(string: "\(project.displayName)  |  \(days)  |  \(takes)")
            .draw(in: CGRect(x: 36, y: 516, width: 720, height: 18), withAttributes: secondaryAttributes)

        var y: CGFloat = 486
        let scLabel = t("场", "Sc")
        let shLabel = t("镜", "Sh")
        let tkLabel = t("条", "Tk")
        for row in rows(project: project, language: language).prefix(24) {
            let line = "\(row[1])  \(scLabel)\(row[2])  \(shLabel)\(row[3])  \(tkLabel)\(row[4])  \(row[5])  \(row[6])  \(row[17])"
            NSString(string: line).draw(in: CGRect(x: 36, y: y, width: 760, height: 14), withAttributes: bodyAttributes)
            y -= 17
        }

        if takeCount(project: project) > 24 {
            let footer = t("PDF 当前为 MVP 摘要版；完整数据请使用 CSV 或 JSON。", "This PDF is an MVP summary; use CSV or JSON for full data.")
            NSString(string: footer)
                .draw(in: CGRect(x: 36, y: 44, width: 760, height: 18), withAttributes: secondaryAttributes)
        }

        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
    }

    static func csvHeaders(language: AppLanguage = .system) -> [String] {
        let t: (String, String) -> String = { zh, en in L10n.t(zh, en, language: language) }
        return [
            t("项目", "Project"),
            t("拍摄日", "Shooting Day"),
            t("场次", "Scene"),
            t("镜头", "Shot"),
            t("条次", "Take"),
            t("主机位", "Camera"),
            t("状态", "Status"),
            t("优选条", "Circle Take"),
            t("画面可用", "Picture OK"),
            t("声音可用", "Sound OK"),
            t("表演评分", "Perf. Rating"),
            t("技术评分", "Tech. Rating"),
            t("表演备注", "Perf. Note"),
            t("技术备注", "Tech. Note"),
            t("通用备注", "General Note"),
            t("快速标签", "Quick Tags"),
            t("多机位记录", "Multi-Cam Log"),
            t("关联素材", "Linked Clips"),
            t("创建时间", "Created"),
            t("更新时间", "Updated")
        ]
    }

    static func rows(project: Project, language: AppLanguage = .system) -> [[String]] {
        let formatter = ISO8601DateFormatter()
        return project.shootingDays.flatMap { day in
            day.scenes.flatMap { scene in
                scene.shots.flatMap { shot in
                    shot.takes.map { take in
                        [
                            project.displayName,
                            day.label.isEmpty ? dayLabelFormatter.string(from: day.date) : day.label,
                            scene.sceneNumber,
                            shot.shotNumber,
                            "\(take.takeNumber)",
                            take.cameraLabel,
                            take.status.label(language: language),
                            yesNo(take.isCircleTake, language: language),
                            yesNo(take.pictureUsable, language: language),
                            yesNo(take.soundUsable, language: language),
                            "\(take.performanceRating)",
                            "\(take.technicalRating)",
                            take.performanceNote,
                            take.technicalNote,
                            take.generalNote,
                            take.quickTags.joined(separator: " | "),
                            take.cameraRecords.map { cameraRecordSummary($0, language: language) }.joined(separator: " | "),
                            take.linkedClips.map(\.fileName).joined(separator: " | "),
                            formatter.string(from: take.createdAt),
                            formatter.string(from: take.updatedAt)
                        ]
                    }
                }
            }
        }
    }

    private static let dayLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func csvLine(_ fields: [String]) -> String {
        fields.map { spreadsheetSafeCSVField($0) }.joined(separator: ",")
    }

    private static func yesNo(_ value: Bool, language: AppLanguage = .system) -> String {
        L10n.t(value ? "是" : "否", value ? "Yes" : "No", language: language)
    }

    private static func cameraRecordSummary(_ record: CameraRecord, language: AppLanguage = .system) -> String {
        let t: (String, String) -> String = { zh, en in L10n.t(zh, en, language: language) }
        let parts = [
            record.cameraLabel,
            record.status.label(language: language),
            record.clipName.isEmpty ? nil : "\(t("素材", "Clip")):\(record.clipName)",
            record.cardName.isEmpty ? nil : "\(t("卡", "Card")):\(record.cardName)",
            record.tcIn.isEmpty ? nil : "\(t("入点", "TC In")):\(record.tcIn)",
            record.tcOut.isEmpty ? nil : "\(t("出点", "TC Out")):\(record.tcOut)",
            "\(t("画面", "Pic")):\(yesNo(record.pictureAvailable, language: language))",
            "\(t("声音", "Snd")):\(yesNo(record.audioAvailable, language: language))",
            record.notes.isEmpty ? nil : "\(t("备注", "Note")):\(record.notes)"
        ]
        return parts.compactMap { $0 }.joined(separator: " ")
    }

    private static func takeCount(project: Project) -> Int {
        project.shootingDays.reduce(0) { dayTotal, day in
            dayTotal + day.scenes.reduce(0) { sceneTotal, scene in
                sceneTotal + scene.shots.reduce(0) { $0 + $1.takes.count }
            }
        }
    }

    enum ExportError: LocalizedError {
        case couldNotCreatePDF

        var errorDescription: String? {
            "Could not create script log PDF."
        }
    }
}
