import AppKit
import CoreGraphics
import Foundation

enum ScriptWorkshopPDFProfile: String, Codable, CaseIterable, Equatable {
    /// Clean reading copy: no production scene numbers or revision stars.
    case reader

    /// Shooting-script copy: scene numbers and revision marks are rendered.
    case production
}

enum ScriptWorkshopPDFDiagnosticSeverity: String, Codable, Equatable {
    case information
    case warning
}

struct ScriptWorkshopPDFDiagnostic: Codable, Equatable {
    var severity: ScriptWorkshopPDFDiagnosticSeverity
    var code: String
    var message: String
    var pageNumber: String?
    var sceneID: UUID?
    var blockID: UUID?
}

struct ScriptWorkshopPDFExportOptions: Codable, Equatable {
    var profile: ScriptWorkshopPDFProfile
    var screenplayFormat: ScriptWorkshopScreenplayFormat
    var fontName: String?
    var includeNotes: Bool
    var showFirstScriptPageNumber: Bool
    var showSceneNumbersOnBothSides: Bool
    var showRevisionMarks: Bool
    var watermark: String?

    init(
        profile: ScriptWorkshopPDFProfile = .reader,
        screenplayFormat: ScriptWorkshopScreenplayFormat = .international,
        fontName: String? = nil,
        includeNotes: Bool = false,
        showFirstScriptPageNumber: Bool = false,
        showSceneNumbersOnBothSides: Bool = true,
        showRevisionMarks: Bool? = nil,
        watermark: String? = nil
    ) {
        self.profile = profile
        self.screenplayFormat = screenplayFormat
        self.fontName = fontName
        self.includeNotes = includeNotes
        self.showFirstScriptPageNumber = showFirstScriptPageNumber
        self.showSceneNumbersOnBothSides = showSceneNumbersOnBothSides
        self.showRevisionMarks = showRevisionMarks ?? (profile == .production)
        self.watermark = watermark
    }
}

struct ScriptWorkshopPDFExportReport: Codable, Equatable {
    var profile: ScriptWorkshopPDFProfile
    var screenplayFormat: ScriptWorkshopScreenplayFormat
    var paperSize: ScriptWorkshopPaperSize
    var pageCount: Int
    var scriptPageCount: Int
    var byteCount: Int
    var fontName: String
    var diagnostics: [ScriptWorkshopPDFDiagnostic]

    var warningCount: Int {
        diagnostics.filter { $0.severity == .warning }.count
    }
}

struct ScriptWorkshopPDFExportResult {
    var data: Data
    var report: ScriptWorkshopPDFExportReport
}

enum ScriptWorkshopPDFExportError: Error, LocalizedError {
    case emptyPagination
    case mixedPaperSizes
    case invalidFontSize(Double)
    case unavailableFont(String)
    case unableToCreateDataConsumer
    case unableToCreatePDFContext
    case unableToFinalizePDF
    case writeFailed(path: String, message: String)

    var code: String {
        switch self {
        case .emptyPagination: return "empty-pagination"
        case .mixedPaperSizes: return "mixed-paper-sizes"
        case .invalidFontSize: return "invalid-font-size"
        case .unavailableFont: return "unavailable-font"
        case .unableToCreateDataConsumer: return "unable-to-create-data-consumer"
        case .unableToCreatePDFContext: return "unable-to-create-pdf-context"
        case .unableToFinalizePDF: return "unable-to-finalize-pdf"
        case .writeFailed: return "write-failed"
        }
    }

    var errorDescription: String? {
        switch self {
        case .emptyPagination:
            return "The pagination result contains no pages."
        case .mixedPaperSizes:
            return "A single export cannot contain mixed paper sizes."
        case let .invalidFontSize(size):
            return "The pagination result contains an invalid font size: \(size)."
        case let .unavailableFont(name):
            return "The requested PDF font “\(name)” is not installed."
        case .unableToCreateDataConsumer:
            return "Core Graphics could not create an in-memory PDF data consumer."
        case .unableToCreatePDFContext:
            return "Core Graphics could not create a PDF context."
        case .unableToFinalizePDF:
            return "The PDF context completed without producing PDF data."
        case let .writeFailed(path, message):
            return "Could not write PDF to \(path): \(message)"
        }
    }
}

enum ScriptWorkshopPDFExporter {
    static func makePDF(
        pagination: ScriptWorkshopPaginationResult,
        document: ScriptWorkshopDocument? = nil,
        options: ScriptWorkshopPDFExportOptions = ScriptWorkshopPDFExportOptions()
    ) throws -> ScriptWorkshopPDFExportResult {
        guard let firstPage = pagination.pages.first else {
            throw ScriptWorkshopPDFExportError.emptyPagination
        }
        guard pagination.pages.allSatisfy({ $0.paperSize == firstPage.paperSize }) else {
            throw ScriptWorkshopPDFExportError.mixedPaperSizes
        }

        let fontSize = pagination.configuration.fontSize
        guard fontSize.isFinite, fontSize > 0 else {
            throw ScriptWorkshopPDFExportError.invalidFontSize(fontSize)
        }
        let font: NSFont
        var preferredRegionalFontUnavailable = false
        if let requestedName = options.fontName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !requestedName.isEmpty {
            guard let requested = NSFont(name: requestedName, size: fontSize) else {
                throw ScriptWorkshopPDFExportError.unavailableFont(requestedName)
            }
            font = requested
        } else {
            let preferredNames = preferredFontNames(for: options.screenplayFormat)
            if let preferred = preferredNames.lazy.compactMap({
                NSFont(name: $0, size: fontSize)
            }).first {
                font = preferred
            } else if options.screenplayFormat.isChineseProductionFormat {
                font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
                preferredRegionalFontUnavailable = true
            } else {
                font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            }
        }

        var diagnostics = pagination.diagnostics.map {
            ScriptWorkshopPDFDiagnostic(
                severity: $0.severity == .warning ? .warning : .information,
                code: "pagination.\($0.code)",
                message: $0.message,
                pageNumber: nil,
                sceneID: $0.sceneID,
                blockID: $0.blockID
            )
        }
        diagnostics.append(
            ScriptWorkshopPDFDiagnostic(
                severity: .information,
                code: "font-embedding-not-verified",
                message: "This exporter creates vector text but does not certify PDF/A conformance or verify font embedding.",
                pageNumber: nil,
                sceneID: nil,
                blockID: nil
            )
        )
        if preferredRegionalFontUnavailable {
            diagnostics.append(
                ScriptWorkshopPDFDiagnostic(
                    severity: .warning,
                    code: "regional-font-fallback",
                    message: "The preferred regional CJK fonts were unavailable; the system font was used.",
                    pageNumber: nil,
                    sceneID: nil,
                    blockID: nil
                )
            )
        }
        if pagination.configuration.screenplayFormat != options.screenplayFormat {
            diagnostics.append(
                ScriptWorkshopPDFDiagnostic(
                    severity: .warning,
                    code: "screenplay-format-mismatch",
                    message: "PDF options and pagination used different screenplay formats; pagination layout was retained.",
                    pageNumber: nil,
                    sceneID: nil,
                    blockID: nil
                )
            )
        }

        let mutableData = NSMutableData()
        guard let consumer = CGDataConsumer(data: mutableData as CFMutableData) else {
            throw ScriptWorkshopPDFExportError.unableToCreateDataConsumer
        }
        var mediaBox = CGRect(
            x: 0,
            y: 0,
            width: firstPage.paperSize.widthPoints,
            height: firstPage.paperSize.heightPoints
        )
        var documentInfo: [CFString: Any] = [
            kCGPDFContextCreator: "321Doit 剧本工坊 0.8"
        ]
        if let document {
            let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let author = document.author.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                documentInfo[kCGPDFContextTitle] = title
            }
            if !author.isEmpty {
                documentInfo[kCGPDFContextAuthor] = author
            }
        }
        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &mediaBox,
            documentInfo as CFDictionary
        ) else {
            throw ScriptWorkshopPDFExportError.unableToCreatePDFContext
        }

        let blockIndex = document.map(blockMetadataIndex)
        let blockMetadata = blockIndex?.metadata ?? [:]
        let revisionIndex = revisionSetIndex(document?.workspace?.revisionSets ?? [])
        let revisionSets = revisionIndex.revisionSets
        if let duplicateCount = blockIndex?.duplicateIDs.count, duplicateCount > 0 {
            diagnostics.append(
                ScriptWorkshopPDFDiagnostic(
                    severity: .warning,
                    code: "duplicate-block-id",
                    message: "\(duplicateCount) duplicate block ID(s) were found; the first metadata record was used.",
                    pageNumber: nil,
                    sceneID: nil,
                    blockID: nil
                )
            )
        }
        if !revisionIndex.duplicateIDs.isEmpty {
            diagnostics.append(
                ScriptWorkshopPDFDiagnostic(
                    severity: .warning,
                    code: "duplicate-revision-set-id",
                    message: "\(revisionIndex.duplicateIDs.count) duplicate revision-set ID(s) were found; the first record was used.",
                    pageNumber: nil,
                    sceneID: nil,
                    blockID: nil
                )
            )
        }
        if options.profile == .production,
           options.showRevisionMarks,
           document == nil {
            diagnostics.append(
                ScriptWorkshopPDFDiagnostic(
                    severity: .warning,
                    code: "production-metadata-unavailable",
                    message: "Production profile was exported without a document; revision marks could not be resolved.",
                    pageNumber: nil,
                    sceneID: nil,
                    blockID: nil
                )
            )
        }

        var omittedNoteLines = 0
        var unresolvedRevisionBlocks = Set<UUID>()
        var unresolvedRevisionSetIDs = Set<UUID>()
        for (pageIndex, page) in pagination.pages.enumerated() {
            let pageInfo: [CFString: Any] = [
                kCGPDFContextMediaBox: CGRect(
                    x: 0,
                    y: 0,
                    width: page.paperSize.widthPoints,
                    height: page.paperSize.heightPoints
                )
            ]
            context.beginPDFPage(pageInfo as CFDictionary)
            drawWhiteBackground(page, in: context)

            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext

            for line in page.lines {
                if case .block(.note) = line.role, !options.includeNotes {
                    omittedNoteLines += 1
                    continue
                }
                let metadata = line.blockID.flatMap { blockMetadata[$0] }
                let color = textColor(for: line)
                drawLine(
                    line,
                    page: page,
                    font: font,
                    color: color
                )

                if options.profile == .production,
                   line.role == .sceneHeading,
                   line.sourceRange?.location == 0,
                   let sceneNumber = line.sceneNumber,
                   !sceneNumber.isEmpty {
                    drawSceneNumber(
                        sceneNumber,
                        line: line,
                        page: page,
                        font: font,
                        bothSides: options.showSceneNumbersOnBothSides,
                        leftMargin: pagination.configuration.leftMargin,
                        rightMargin: pagination.configuration.rightMargin
                    )
                }

                if options.profile == .production,
                   options.showRevisionMarks,
                   let blockID = line.blockID {
                    if let metadata,
                       let revisionSetID = metadata.revisionSetID {
                        if revisionSets[revisionSetID] == nil {
                            unresolvedRevisionSetIDs.insert(revisionSetID)
                        }
                        drawRevisionMark(
                            line: line,
                            page: page,
                            font: font,
                            color: .black,
                            rightMargin: pagination.configuration.rightMargin
                        )
                    } else if document != nil, blockMetadata[blockID] == nil {
                        unresolvedRevisionBlocks.insert(blockID)
                    }
                }
            }

            if let pageNumber = page.pageNumber,
               options.showFirstScriptPageNumber || pageNumber.base > 1 {
                drawPageNumber(
                    pageNumber.displayValue,
                    page: page,
                    font: font
                )
            }
            if let watermark = options.watermark?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !watermark.isEmpty {
                drawWatermark(watermark, page: page, font: font)
            }

            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()

            if pageIndex == pagination.pages.count - 1 {
                context.flush()
            }
        }
        context.closePDF()

        if omittedNoteLines > 0 {
            diagnostics.append(
                ScriptWorkshopPDFDiagnostic(
                    severity: .warning,
                    code: "note-lines-omitted",
                    message: "\(omittedNoteLines) note line(s) were intentionally omitted without repagination; their reserved vertical space remains.",
                    pageNumber: nil,
                    sceneID: nil,
                    blockID: nil
                )
            )
        }
        if !unresolvedRevisionBlocks.isEmpty {
            diagnostics.append(
                ScriptWorkshopPDFDiagnostic(
                    severity: .warning,
                    code: "block-metadata-not-found",
                    message: "Revision metadata could not be resolved for \(unresolvedRevisionBlocks.count) paginated block(s); pagination may be stale.",
                    pageNumber: nil,
                    sceneID: nil,
                    blockID: nil
                )
            )
        }
        if !unresolvedRevisionSetIDs.isEmpty {
            diagnostics.append(
                ScriptWorkshopPDFDiagnostic(
                    severity: .warning,
                    code: "revision-set-not-found",
                    message: "\(unresolvedRevisionSetIDs.count) referenced revision set(s) were not present in the document; revision marks were retained in black.",
                    pageNumber: nil,
                    sceneID: nil,
                    blockID: nil
                )
            )
        }
        if options.profile == .reader, options.showRevisionMarks {
            diagnostics.append(
                ScriptWorkshopPDFDiagnostic(
                    severity: .information,
                    code: "reader-profile-ignores-revision-marks",
                    message: "Reader profile does not draw production revision marks.",
                    pageNumber: nil,
                    sceneID: nil,
                    blockID: nil
                )
            )
        }

        let data = mutableData as Data
        guard !data.isEmpty else {
            throw ScriptWorkshopPDFExportError.unableToFinalizePDF
        }
        let report = ScriptWorkshopPDFExportReport(
            profile: options.profile,
            screenplayFormat: options.screenplayFormat,
            paperSize: firstPage.paperSize,
            pageCount: pagination.pages.count,
            scriptPageCount: pagination.scriptPageCount,
            byteCount: data.count,
            fontName: font.fontName,
            diagnostics: diagnostics
        )
        return ScriptWorkshopPDFExportResult(data: data, report: report)
    }

    @discardableResult
    static func writePDF(
        pagination: ScriptWorkshopPaginationResult,
        document: ScriptWorkshopDocument? = nil,
        to url: URL,
        options: ScriptWorkshopPDFExportOptions = ScriptWorkshopPDFExportOptions()
    ) throws -> ScriptWorkshopPDFExportReport {
        let result = try makePDF(
            pagination: pagination,
            document: document,
            options: options
        )
        do {
            try result.data.write(to: url, options: .atomic)
        } catch {
            throw ScriptWorkshopPDFExportError.writeFailed(
                path: url.path,
                message: error.localizedDescription
            )
        }
        return result.report
    }

    private static func preferredFontNames(
        for format: ScriptWorkshopScreenplayFormat
    ) -> [String] {
        switch format {
        case .international:
            return []
        case .mainlandChina:
            return ["Songti SC", "STSong", "PingFang SC"]
        case .hongKong:
            return ["Songti TC", "PingFang HK", "PingFang TC", "STSong"]
        }
    }

    private static func blockMetadataIndex(
        _ document: ScriptWorkshopDocument
    ) -> (
        metadata: [UUID: ScriptWorkshopBlockMetadata],
        duplicateIDs: Set<UUID>
    ) {
        var result: [UUID: ScriptWorkshopBlockMetadata] = [:]
        var seen = Set<UUID>()
        var duplicateIDs = Set<UUID>()
        for block in document.scenes.flatMap(\.blocks) {
            guard seen.insert(block.id).inserted else {
                duplicateIDs.insert(block.id)
                continue
            }
            if let metadata = block.metadata {
                result[block.id] = metadata
            }
        }
        return (result, duplicateIDs)
    }

    private static func revisionSetIndex(
        _ revisionSets: [ScriptWorkshopRevisionSet]
    ) -> (
        revisionSets: [UUID: ScriptWorkshopRevisionSet],
        duplicateIDs: Set<UUID>
    ) {
        var result: [UUID: ScriptWorkshopRevisionSet] = [:]
        var duplicateIDs = Set<UUID>()
        for revisionSet in revisionSets {
            if result[revisionSet.id] == nil {
                result[revisionSet.id] = revisionSet
            } else {
                duplicateIDs.insert(revisionSet.id)
            }
        }
        return (result, duplicateIDs)
    }

    private static func drawWhiteBackground(
        _ page: ScriptWorkshopPageLayout,
        in context: CGContext
    ) {
        context.saveGState()
        context.setFillColor(NSColor.white.cgColor)
        context.fill(
            CGRect(
                x: 0,
                y: 0,
                width: page.paperSize.widthPoints,
                height: page.paperSize.heightPoints
            )
        )
        context.restoreGState()
    }

    private static func drawLine(
        _ line: ScriptWorkshopLayoutLine,
        page: ScriptWorkshopPageLayout,
        font: NSFont,
        color: NSColor
    ) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byClipping
        switch line.alignment {
        case .left: style.alignment = .left
        case .center: style.alignment = .center
        case .right: style.alignment = .right
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style
        ]
        let attributed = NSAttributedString(string: line.text, attributes: attributes)
        attributed.draw(
            in: appKitRect(
                line.frame,
                pageHeight: page.paperSize.heightPoints,
                minimumHeight: ceil(font.ascender - font.descender)
            )
        )
    }

    private static func drawPageNumber(
        _ pageNumber: String,
        page: ScriptWorkshopPageLayout,
        font: NSFont
    ) {
        let frame = page.pageNumberFrame ?? ScriptWorkshopLayoutFrame(
            x: page.paperSize.widthPoints - 126,
            y: 36,
            width: 54,
            height: 18
        )
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        let text = NSAttributedString(
            string: "\(pageNumber).",
            attributes: [
                .font: font,
                .foregroundColor: NSColor.black,
                .paragraphStyle: style
            ]
        )
        text.draw(
            in: appKitRect(
                frame,
                pageHeight: page.paperSize.heightPoints,
                minimumHeight: ceil(font.ascender - font.descender)
            )
        )
    }

    private static func drawSceneNumber(
        _ sceneNumber: String,
        line: ScriptWorkshopLayoutLine,
        page: ScriptWorkshopPageLayout,
        font: NSFont,
        bothSides: Bool,
        leftMargin: Double,
        rightMargin: Double
    ) {
        let leftStyle = NSMutableParagraphStyle()
        leftStyle.alignment = .right
        let rightStyle = NSMutableParagraphStyle()
        rightStyle.alignment = .left
        let common: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let left = NSMutableAttributedString(string: sceneNumber, attributes: common)
        left.addAttribute(
            .paragraphStyle,
            value: leftStyle,
            range: NSRange(location: 0, length: left.length)
        )
        left.draw(
            in: appKitRect(
                ScriptWorkshopLayoutFrame(
                    x: 8,
                    y: line.frame.y,
                    width: max(1, leftMargin - 26),
                    height: line.frame.height
                ),
                pageHeight: page.paperSize.heightPoints,
                minimumHeight: ceil(font.ascender - font.descender)
            )
        )
        if bothSides {
            let right = NSMutableAttributedString(string: sceneNumber, attributes: common)
            right.addAttribute(
                .paragraphStyle,
                value: rightStyle,
                range: NSRange(location: 0, length: right.length)
            )
            right.draw(
                in: appKitRect(
                    ScriptWorkshopLayoutFrame(
                        x: page.paperSize.widthPoints - rightMargin + 18,
                        y: line.frame.y,
                        width: max(1, rightMargin - 26),
                        height: line.frame.height
                    ),
                    pageHeight: page.paperSize.heightPoints,
                    minimumHeight: ceil(font.ascender - font.descender)
                )
            )
        }
    }

    private static func drawRevisionMark(
        line: ScriptWorkshopLayoutLine,
        page: ScriptWorkshopPageLayout,
        font: NSFont,
        color: NSColor,
        rightMargin: Double
    ) {
        let mark = NSAttributedString(
            string: "*",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: font.pointSize),
                .foregroundColor: color
            ]
        )
        mark.draw(
            in: appKitRect(
                ScriptWorkshopLayoutFrame(
                    x: page.paperSize.widthPoints - rightMargin + 3,
                    y: line.frame.y,
                    width: 12,
                    height: line.frame.height
                ),
                pageHeight: page.paperSize.heightPoints,
                minimumHeight: ceil(font.ascender - font.descender)
            )
        )
    }

    private static func drawWatermark(
        _ watermark: String,
        page: ScriptWorkshopPageLayout,
        font: NSFont
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let watermarkFont = NSFont.systemFont(
            ofSize: max(24, font.pointSize * 3),
            weight: .bold
        )
        let attributed = NSAttributedString(
            string: watermark,
            attributes: [
                .font: watermarkFont,
                .foregroundColor: NSColor.black.withAlphaComponent(0.08),
                .paragraphStyle: style
            ]
        )
        attributed.draw(
            in: NSRect(
                x: 36,
                y: page.paperSize.heightPoints * 0.46,
                width: page.paperSize.widthPoints - 72,
                height: ceil(watermarkFont.ascender - watermarkFont.descender) + 8
            )
        )
    }

    private static func textColor(for line: ScriptWorkshopLayoutLine) -> NSColor {
        if case .block(.note) = line.role {
            return NSColor(calibratedWhite: 0.35, alpha: 1)
        }
        return .black
    }

    private static func appKitRect(
        _ frame: ScriptWorkshopLayoutFrame,
        pageHeight: Double,
        minimumHeight: CGFloat
    ) -> NSRect {
        let height = max(CGFloat(frame.height), minimumHeight)
        return NSRect(
            x: CGFloat(frame.x),
            y: CGFloat(pageHeight - frame.y) - height,
            width: CGFloat(frame.width),
            height: height
        )
    }
}
