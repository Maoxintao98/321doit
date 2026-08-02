import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

enum ScriptWorkshopFDXDiagnosticSeverity: String, Codable, Equatable {
    case information
    case warning
    case error
}

struct ScriptWorkshopFDXDiagnostic: Codable, Equatable {
    var severity: ScriptWorkshopFDXDiagnosticSeverity
    var code: String
    var message: String
    var paragraphIndex: Int?
    var paragraphType: String?

    init(
        severity: ScriptWorkshopFDXDiagnosticSeverity,
        code: String,
        message: String,
        paragraphIndex: Int? = nil,
        paragraphType: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.paragraphIndex = paragraphIndex
        self.paragraphType = paragraphType
    }
}

struct ScriptWorkshopFDXImportResult {
    var document: ScriptWorkshopDocument

    /// A convenient stable-ID index for clients that need production labels
    /// without traversing scene metadata.
    var sceneNumbers: [UUID: String]
    var diagnostics: [ScriptWorkshopFDXDiagnostic]
}

enum ScriptWorkshopFDXNoteParagraphType: String, Codable, Equatable {
    case general = "General"
    case note = "Note"
}

struct ScriptWorkshopFDXExportOptions: Equatable {
    var sceneNumbers: [UUID: String]
    var noteParagraphType: ScriptWorkshopFDXNoteParagraphType
    var includeSynopses: Bool
    var includeEmptyParagraphs: Bool

    init(
        sceneNumbers: [UUID: String] = [:],
        noteParagraphType: ScriptWorkshopFDXNoteParagraphType = .general,
        includeSynopses: Bool = true,
        includeEmptyParagraphs: Bool = false
    ) {
        self.sceneNumbers = sceneNumbers
        self.noteParagraphType = noteParagraphType
        self.includeSynopses = includeSynopses
        self.includeEmptyParagraphs = includeEmptyParagraphs
    }
}

struct ScriptWorkshopFDXExportResult {
    var data: Data
    var diagnostics: [ScriptWorkshopFDXDiagnostic]

    var utf8XML: String {
        String(data: data, encoding: .utf8) ?? ""
    }
}

enum ScriptWorkshopFDXError: Error, LocalizedError {
    case malformedXML(message: String, line: Int, column: Int)
    case unsupportedRoot(String)
    case inputTooLarge(Int)
    case resourceLimit(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case let .malformedXML(message, line, column):
            return "Malformed FDX XML at \(line):\(column): \(message)"
        case let .unsupportedRoot(root):
            return "Expected a FinalDraft root element, found \(root.isEmpty ? "none" : root)."
        case let .inputTooLarge(bytes):
            return "The FDX file is \(bytes) bytes, above the safe 25 MB import limit."
        case let .resourceLimit(message):
            return "The FDX import was stopped by a safety limit: \(message)"
        case .encodingFailed:
            return "The FDX document could not be encoded as UTF-8."
        }
    }
}

enum ScriptWorkshopFDX {
    static func decode(
        _ data: Data,
        linkedProjectID: UUID? = nil
    ) throws -> ScriptWorkshopFDXImportResult {
        guard data.count <= 25 * 1_024 * 1_024 else {
            throw ScriptWorkshopFDXError.inputTooLarge(data.count)
        }
        let collector = FDXCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            if let limitFailure = collector.limitFailure {
                throw ScriptWorkshopFDXError.resourceLimit(limitFailure)
            }
            throw ScriptWorkshopFDXError.malformedXML(
                message: parser.parserError?.localizedDescription ?? "Unknown XML parser error",
                line: parser.lineNumber,
                column: parser.columnNumber
            )
        }
        guard collector.rootName.caseInsensitiveCompare("FinalDraft") == .orderedSame else {
            throw ScriptWorkshopFDXError.unsupportedRoot(collector.rootName)
        }

        var diagnostics = collector.diagnostics
        let titleMetadata = collector.documentTitle?.trimmedForFDX
        let authorMetadata = collector.documentAuthor?.trimmedForFDX
        let titlePage = interpretTitlePage(
            collector.titleParagraphs,
            metadataTitle: titleMetadata,
            metadataAuthor: authorMetadata,
            diagnostics: &diagnostics
        )

        var importedScenes: [ScriptWorkshopScene] = []
        var sceneNumbers: [UUID: String] = [:]
        var currentHeading: String?
        var currentSceneNumber: String?
        var currentSynopsis = ""
        var currentBlocks: [ScriptWorkshopBlock] = []
        var hasContentBeforeFirstHeading = false

        func finishScene() {
            guard currentHeading != nil || !currentBlocks.isEmpty else { return }
            let sceneID = UUID()
            var scene = ScriptWorkshopScene(
                id: sceneID,
                heading: currentHeading?.trimmedForFDX.nonEmptyFDX ?? "开场",
                synopsis: currentSynopsis,
                blocks: currentBlocks.isEmpty
                    ? [ScriptWorkshopBlock(kind: .action)]
                    : currentBlocks,
                metadata: ScriptWorkshopSceneMetadata(
                    sceneNumber: currentSceneNumber?.trimmedForFDX ?? ""
                )
            )
            // The initializer protects normal UI construction from empty scenes,
            // while an imported non-empty block list should remain byte-for-byte
            // in the same semantic order.
            scene.blocks = currentBlocks.isEmpty
                ? [ScriptWorkshopBlock(kind: .action)]
                : currentBlocks
            importedScenes.append(scene)
            if let number = currentSceneNumber?.trimmedForFDX, !number.isEmpty {
                sceneNumbers[sceneID] = number
            }
            currentHeading = nil
            currentSceneNumber = nil
            currentSynopsis = ""
            currentBlocks = []
        }

        for (paragraphIndex, paragraph) in collector.bodyParagraphs.enumerated() {
            let rawText = paragraph.text.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            let trimmed = rawText.trimmedForFDX
            let normalizedType = normalizedParagraphType(paragraph.type)

            if paragraph.hasInlineStyle {
                diagnostics.append(
                    ScriptWorkshopFDXDiagnostic(
                        severity: .information,
                        code: "inline-style-not-represented",
                        message: "Inline FDX styling was flattened while preserving its text.",
                        paragraphIndex: paragraphIndex,
                        paragraphType: paragraph.type
                    )
                )
            }
            if paragraph.hasTextOutsideTextElement {
                diagnostics.append(
                    ScriptWorkshopFDXDiagnostic(
                        severity: .warning,
                        code: "non-text-run-content-flattened",
                        message: "Text outside a standard FDX Text run was preserved but its original container is not represented.",
                        paragraphIndex: paragraphIndex,
                        paragraphType: paragraph.type
                    )
                )
            }
            if paragraph.isInsideDualDialogue {
                diagnostics.appendOnceFDX(
                    ScriptWorkshopFDXDiagnostic(
                        severity: .warning,
                        code: "dual-dialogue-flattened",
                        message: "The current workshop model has no dual-dialogue container; both sides were preserved in document order."
                    )
                )
            }
            if trimmed.isEmpty {
                if !paragraph.type.trimmedForFDX.isEmpty {
                    diagnostics.append(
                        ScriptWorkshopFDXDiagnostic(
                            severity: .information,
                            code: "empty-paragraph-ignored",
                            message: "An empty formatted paragraph was ignored.",
                            paragraphIndex: paragraphIndex,
                            paragraphType: paragraph.type
                        )
                    )
                }
                continue
            }

            switch normalizedType {
            case "sceneheading":
                finishScene()
                currentHeading = trimmed
                currentSceneNumber = paragraph.number

            case "action":
                if currentHeading == nil, importedScenes.isEmpty {
                    hasContentBeforeFirstHeading = true
                }
                currentBlocks.append(importedBlock(.action, rawText, paragraph: paragraph))

            case "character":
                if currentHeading == nil, importedScenes.isEmpty {
                    hasContentBeforeFirstHeading = true
                }
                currentBlocks.append(importedBlock(.character, rawText, paragraph: paragraph))

            case "parenthetical":
                if currentHeading == nil, importedScenes.isEmpty {
                    hasContentBeforeFirstHeading = true
                }
                currentBlocks.append(importedBlock(.parenthetical, rawText, paragraph: paragraph))

            case "dialogue":
                if currentHeading == nil, importedScenes.isEmpty {
                    hasContentBeforeFirstHeading = true
                }
                currentBlocks.append(importedBlock(.dialogue, rawText, paragraph: paragraph))

            case "transition":
                if currentHeading == nil, importedScenes.isEmpty {
                    hasContentBeforeFirstHeading = true
                }
                currentBlocks.append(importedBlock(.transition, rawText, paragraph: paragraph))

            case "shot":
                if currentHeading == nil, importedScenes.isEmpty {
                    hasContentBeforeFirstHeading = true
                }
                currentBlocks.append(importedBlock(.shot, rawText, paragraph: paragraph))

            case "general", "generaltext", "note", "scriptnote":
                if paragraph.scriptWorkshopRole.caseInsensitiveCompare("Synopsis") == .orderedSame,
                   currentHeading != nil {
                    if currentSynopsis.isEmpty {
                        currentSynopsis = rawText
                    } else {
                        currentSynopsis += "\n\(rawText)"
                    }
                } else {
                    if currentHeading == nil, importedScenes.isEmpty {
                        hasContentBeforeFirstHeading = true
                    }
                    currentBlocks.append(importedBlock(.note, rawText, paragraph: paragraph))
                    if normalizedType == "general" || normalizedType == "generaltext" {
                        diagnostics.append(
                            ScriptWorkshopFDXDiagnostic(
                                severity: .information,
                                code: "general-mapped-to-note",
                                message: "A General paragraph was preserved as a workshop note.",
                                paragraphIndex: paragraphIndex,
                                paragraphType: paragraph.type
                            )
                        )
                    }
                }

            default:
                if currentHeading == nil, importedScenes.isEmpty {
                    hasContentBeforeFirstHeading = true
                }
                currentBlocks.append(importedBlock(.note, rawText, paragraph: paragraph))
                diagnostics.append(
                    ScriptWorkshopFDXDiagnostic(
                        severity: .warning,
                        code: "unsupported-paragraph-mapped-to-note",
                        message: "Unsupported FDX paragraph type “\(paragraph.type.nonEmptyFDX ?? "unknown")” was preserved as a note.",
                        paragraphIndex: paragraphIndex,
                        paragraphType: paragraph.type
                    )
                )
            }
        }
        finishScene()

        if hasContentBeforeFirstHeading {
            diagnostics.appendOnceFDX(
                ScriptWorkshopFDXDiagnostic(
                    severity: .warning,
                    code: "content-before-first-scene",
                    message: "Content before the first Scene Heading was preserved in a synthetic “开场” scene."
                )
            )
        }
        if importedScenes.isEmpty {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .warning,
                    code: "no-script-content",
                    message: "The FDX file contained no mappable script paragraphs; a blank scene was created."
                )
            )
        }

        let document = ScriptWorkshopDocument(
            linkedProjectID: linkedProjectID,
            title: titlePage.title.nonEmptyFDX ?? "未命名剧本",
            author: titlePage.author,
            scenes: importedScenes.isEmpty ? [ScriptWorkshopScene()] : importedScenes
        )
        return ScriptWorkshopFDXImportResult(
            document: document,
            sceneNumbers: sceneNumbers,
            diagnostics: diagnostics
        )
    }

    static func decode(
        utf8XML: String,
        linkedProjectID: UUID? = nil
    ) throws -> ScriptWorkshopFDXImportResult {
        guard let data = utf8XML.data(using: .utf8) else {
            throw ScriptWorkshopFDXError.encodingFailed
        }
        return try decode(data, linkedProjectID: linkedProjectID)
    }

    static func encode(
        _ document: ScriptWorkshopDocument,
        options: ScriptWorkshopFDXExportOptions = ScriptWorkshopFDXExportOptions()
    ) throws -> ScriptWorkshopFDXExportResult {
        var diagnostics: [ScriptWorkshopFDXDiagnostic] = []
        var lines: [String] = []
        lines.append(#"<?xml version="1.0" encoding="UTF-8" standalone="no"?>"#)
        lines.append(#"<FinalDraft DocumentType="Script" Template="No" Version="1">"#)
        lines.append("  <Content>")

        for (sceneIndex, scene) in document.scenes.enumerated() {
            var heading = scene.heading.trimmedForFDX
            if heading.isEmpty {
                heading = "UNTITLED SCENE"
                diagnostics.append(
                    ScriptWorkshopFDXDiagnostic(
                        severity: .warning,
                        code: "empty-scene-heading-replaced",
                        message: "Scene \(sceneIndex + 1) had an empty heading and was exported as UNTITLED SCENE."
                    )
                )
            }
            let number = options.sceneNumbers[scene.id]?.trimmedForFDX.nonEmptyFDX
                ?? scene.metadata?.sceneNumber.trimmedForFDX.nonEmptyFDX
                ?? String(sceneIndex + 1)
            appendParagraphXML(
                to: &lines,
                type: "Scene Heading",
                text: heading,
                number: number,
                extraAttributes: [:],
                paragraphIndex: nil,
                diagnostics: &diagnostics
            )

            if options.includeSynopses, !scene.synopsis.trimmedForFDX.isEmpty {
                appendParagraphXML(
                    to: &lines,
                    type: "General",
                    text: scene.synopsis,
                    number: nil,
                    extraAttributes: ["ScriptWorkshopRole": "Synopsis"],
                    paragraphIndex: nil,
                    diagnostics: &diagnostics
                )
            } else if !options.includeSynopses, !scene.synopsis.trimmedForFDX.isEmpty {
                diagnostics.append(
                    ScriptWorkshopFDXDiagnostic(
                        severity: .warning,
                        code: "synopsis-not-exported",
                        message: "The synopsis for scene \(number) was excluded by export options."
                    )
                )
            }

            for (blockIndex, block) in scene.blocks.enumerated() {
                if block.text.isEmpty, !options.includeEmptyParagraphs {
                    continue
                }
                var extraAttributes: [String: String] = [:]
                if block.metadata?.explicitPageBreakBefore == true {
                    extraAttributes["StartsNewPage"] = "Yes"
                }
                appendMetadataDiagnostics(
                    for: block,
                    sceneNumber: number,
                    blockIndex: blockIndex,
                    diagnostics: &diagnostics
                )
                appendParagraphXML(
                    to: &lines,
                    type: fdxParagraphType(
                        for: block.kind,
                        noteParagraphType: options.noteParagraphType
                    ),
                    text: block.text,
                    number: nil,
                    extraAttributes: extraAttributes,
                    paragraphIndex: blockIndex,
                    diagnostics: &diagnostics
                )
            }
            appendSceneMetadataDiagnostics(
                for: scene,
                sceneNumber: number,
                diagnostics: &diagnostics
            )
        }
        lines.append("  </Content>")
        lines.append("  <TitlePage>")
        lines.append("    <Content>")
        appendTitleParagraphXML(
            to: &lines,
            text: document.title.nonEmptyFDX ?? "未命名剧本",
            attributes: ["Alignment": "Center", "SpaceBefore": "240", "Spacing": "1"],
            diagnostics: &diagnostics
        )
        appendTitleParagraphXML(
            to: &lines,
            text: "Written by",
            attributes: ["Alignment": "Center", "SpaceBefore": "24", "Spacing": "1"],
            diagnostics: &diagnostics
        )
        if !document.author.trimmedForFDX.isEmpty {
            appendTitleParagraphXML(
                to: &lines,
                text: document.author,
                attributes: ["Alignment": "Center", "Spacing": "1"],
                diagnostics: &diagnostics
            )
        }
        lines.append("    </Content>")
        lines.append("  </TitlePage>")
        lines.append("</FinalDraft>")
        lines.append("")

        if !document.snapshots.isEmpty {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .warning,
                    code: "snapshots-not-represented",
                    message: "FDX does not carry the workshop’s \(document.snapshots.count) local snapshot(s); the current draft was exported."
                )
            )
        }
        appendWorkspaceDiagnostics(document.workspace, diagnostics: &diagnostics)

        guard let data = lines.joined(separator: "\n").data(using: .utf8) else {
            throw ScriptWorkshopFDXError.encodingFailed
        }
        return ScriptWorkshopFDXExportResult(data: data, diagnostics: diagnostics)
    }

    private static func normalizedParagraphType(_ value: String) -> String {
        value.lowercased().filter(\.isLetter)
    }

    private static func fdxParagraphType(
        for kind: ScriptWorkshopBlockKind,
        noteParagraphType: ScriptWorkshopFDXNoteParagraphType
    ) -> String {
        switch kind {
        case .action: return "Action"
        case .character: return "Character"
        case .dialogue: return "Dialogue"
        case .parenthetical: return "Parenthetical"
        case .transition: return "Transition"
        case .shot: return "Shot"
        case .note: return noteParagraphType.rawValue
        }
    }

    private static func importedBlock(
        _ kind: ScriptWorkshopBlockKind,
        _ text: String,
        paragraph: FDXParagraph
    ) -> ScriptWorkshopBlock {
        ScriptWorkshopBlock(
            kind: kind,
            text: text,
            metadata: ScriptWorkshopBlockMetadata(
                provenance: .imported,
                dualDialogue: paragraph.isInsideDualDialogue,
                explicitPageBreakBefore: paragraph.startsNewPage
            )
        )
    }

    private static func appendMetadataDiagnostics(
        for block: ScriptWorkshopBlock,
        sceneNumber: String,
        blockIndex: Int,
        diagnostics: inout [ScriptWorkshopFDXDiagnostic]
    ) {
        guard let metadata = block.metadata else { return }
        if metadata.revisionSetID != nil {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .warning,
                    code: "block-revision-metadata-not-represented",
                    message: "Revision-set metadata on scene \(sceneNumber), block \(blockIndex + 1) is not represented in this structural FDX export.",
                    paragraphIndex: blockIndex,
                    paragraphType: fdxParagraphType(for: block.kind, noteParagraphType: .general)
                )
            )
        }
        if metadata.omitted {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .warning,
                    code: "omitted-state-not-represented",
                    message: "The omitted state on scene \(sceneNumber), block \(blockIndex + 1) was not representable; its text was preserved.",
                    paragraphIndex: blockIndex
                )
            )
        }
        if metadata.dualDialogue {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .warning,
                    code: "dual-dialogue-exported-sequentially",
                    message: "Dual-dialogue metadata on scene \(sceneNumber), block \(blockIndex + 1) was flattened to sequential paragraphs.",
                    paragraphIndex: blockIndex
                )
            )
        }
        if !metadata.productionTags.isEmpty {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .warning,
                    code: "production-tags-not-represented",
                    message: "Production tags on scene \(sceneNumber), block \(blockIndex + 1) were not represented in FDX.",
                    paragraphIndex: blockIndex
                )
            )
        }
    }

    private static func appendSceneMetadataDiagnostics(
        for scene: ScriptWorkshopScene,
        sceneNumber: String,
        diagnostics: inout [ScriptWorkshopFDXDiagnostic]
    ) {
        guard let metadata = scene.metadata else { return }
        if metadata.status != .draft {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .warning,
                    code: "scene-status-not-represented",
                    message: "Workshop status “\(metadata.status.rawValue)” for scene \(sceneNumber) is not represented in structural FDX."
                )
            )
        }
        if metadata.isNumberLocked {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .information,
                    code: "scene-number-lock-state-not-represented",
                    message: "Scene \(sceneNumber)’s number was exported, but its workshop-only per-scene lock flag is not represented in FDX."
                )
            )
        }
        if metadata.act != .unassigned
            || !metadata.beatIDs.isEmpty
            || !metadata.tags.isEmpty
            || !metadata.storylines.isEmpty {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .warning,
                    code: "scene-development-metadata-not-represented",
                    message: "Act, beat, tag, or storyline metadata for scene \(sceneNumber) is not represented in FDX."
                )
            )
        }
    }

    private static func appendWorkspaceDiagnostics(
        _ workspace: ScriptWorkshopWorkspaceData?,
        diagnostics: inout [ScriptWorkshopFDXDiagnostic]
    ) {
        guard let workspace else { return }
        if !workspace.revisionSets.isEmpty {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .warning,
                    code: "revision-sets-not-represented",
                    message: "\(workspace.revisionSets.count) workshop revision set(s) are not represented by this structural FDX exporter."
                )
            )
        }
        if !workspace.beats.isEmpty {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .warning,
                    code: "beats-not-represented",
                    message: "\(workspace.beats.count) linked story beat(s) remain workshop project data and were not embedded in FDX."
                )
            )
        }
        if !workspace.branches.isEmpty {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .warning,
                    code: "branches-not-represented",
                    message: "\(workspace.branches.count) private branch(es) were not embedded; only the current draft was exported."
                )
            )
        }
        if !workspace.boneyard.isEmpty {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .warning,
                    code: "boneyard-not-represented",
                    message: "\(workspace.boneyard.count) boneyard item(s) were not embedded in FDX."
                )
            )
        }
        if !workspace.characterProfiles.isEmpty {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .information,
                    code: "character-profiles-not-represented",
                    message: "Workshop character-profile details were not embedded in FDX; character cues in the script were preserved."
                )
            )
        }
    }

    private static func appendParagraphXML(
        to lines: inout [String],
        type: String,
        text: String,
        number: String?,
        extraAttributes: [String: String],
        paragraphIndex: Int?,
        diagnostics: inout [ScriptWorkshopFDXDiagnostic]
    ) {
        let sanitized = sanitizeXMLText(text)
        if sanitized.removedInvalidScalars {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .warning,
                    code: "invalid-xml-control-removed",
                    message: "Characters forbidden by XML 1.0 were removed from an exported paragraph.",
                    paragraphIndex: paragraphIndex,
                    paragraphType: type
                )
            )
        }
        var attributes = ["Type": type]
        if let number, !number.isEmpty {
            attributes["Number"] = number
        }
        for (key, value) in extraAttributes {
            attributes[key] = value
        }
        let attributeText = attributes.keys.sorted().map {
            #"\#($0)="\#(escapeXMLAttribute(attributes[$0] ?? ""))""#
        }.joined(separator: " ")
        lines.append(
            #"    <Paragraph \#(attributeText)><Text>\#(escapeXMLText(sanitized.text))</Text></Paragraph>"#
        )
    }

    private static func appendTitleParagraphXML(
        to lines: inout [String],
        text: String,
        attributes: [String: String],
        diagnostics: inout [ScriptWorkshopFDXDiagnostic]
    ) {
        let attributeText = attributes.keys.sorted().map {
            #"\#($0)="\#(escapeXMLAttribute(attributes[$0] ?? ""))""#
        }.joined(separator: " ")
        let sanitized = sanitizeXMLText(text)
        if sanitized.removedInvalidScalars {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .warning,
                    code: "invalid-title-page-xml-control-removed",
                    message: "Characters forbidden by XML 1.0 were removed from title-page content."
                )
            )
        }
        lines.append(
            #"      <Paragraph \#(attributeText)><Text>\#(escapeXMLText(sanitized.text))</Text></Paragraph>"#
        )
    }

    private static func escapeXMLText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeXMLAttribute(_ value: String) -> String {
        escapeXMLText(value)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func sanitizeXMLText(_ value: String) -> (text: String, removedInvalidScalars: Bool) {
        var scalars = String.UnicodeScalarView()
        var removed = false
        for scalar in value.unicodeScalars {
            let code = scalar.value
            if code == 0x9 || code == 0xA || code == 0xD
                || (0x20...0xD7FF).contains(code)
                || (0xE000...0xFFFD).contains(code)
                || (0x10000...0x10FFFF).contains(code) {
                scalars.append(scalar)
            } else {
                removed = true
            }
        }
        return (String(scalars), removed)
    }

    private static func interpretTitlePage(
        _ paragraphs: [FDXParagraph],
        metadataTitle: String?,
        metadataAuthor: String?,
        diagnostics: inout [ScriptWorkshopFDXDiagnostic]
    ) -> (title: String, author: String) {
        let entries = paragraphs.map(\.text).map(\.trimmedForFDX).filter { !$0.isEmpty }
        var consumed = Set<Int>()
        var title = metadataTitle?.nonEmptyFDX ?? ""
        var author = metadataAuthor?.nonEmptyFDX ?? ""

        if title.isEmpty, let titleIndex = entries.indices.first(where: {
            !isTitleCredit(entries[$0]) && !looksLikeTitlePageMetadata(entries[$0])
        }) {
            title = entries[titleIndex]
            consumed.insert(titleIndex)
        }

        if author.isEmpty,
           let creditIndex = entries.indices.first(where: { isTitleCredit(entries[$0]) }) {
            consumed.insert(creditIndex)
            let nextIndex = entries.index(after: creditIndex)
            if entries.indices.contains(nextIndex) {
                author = entries[nextIndex]
                consumed.insert(nextIndex)
            } else {
                diagnostics.append(
                    ScriptWorkshopFDXDiagnostic(
                        severity: .warning,
                        code: "title-page-credit-without-author",
                        message: "The title page contains a writing credit but no following author name."
                    )
                )
            }
        }

        if author.isEmpty {
            let candidates = entries.indices.filter {
                !consumed.contains($0)
                    && !isTitleCredit(entries[$0])
                    && !looksLikeTitlePageMetadata(entries[$0])
            }
            if let candidate = candidates.first {
                author = entries[candidate]
                consumed.insert(candidate)
            }
        }

        if !title.isEmpty, let matching = entries.firstIndex(of: title) {
            consumed.insert(matching)
        }
        if !author.isEmpty, let matching = entries.firstIndex(of: author) {
            consumed.insert(matching)
        }

        let unmapped = entries.indices.filter {
            !consumed.contains($0) && !isTitleCredit(entries[$0])
        }.map { entries[$0] }
        if !unmapped.isEmpty {
            diagnostics.append(
                ScriptWorkshopFDXDiagnostic(
                    severity: .warning,
                    code: "unmapped-title-page-content",
                    message: "Title-page content not represented by the current model was not imported: \(unmapped.joined(separator: " | "))"
                )
            )
        }
        return (title, author)
    }

    private static func isTitleCredit(_ value: String) -> Bool {
        let normalized = value.lowercased()
            .replacingOccurrences(of: "：", with: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "written by", "screenplay by", "teleplay by", "story by",
            "created by", "编剧", "编剧:", "作者", "作者:"
        ].contains(normalized)
    }

    private static func looksLikeTitlePageMetadata(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.contains("@")
            || normalized.hasPrefix("draft")
            || normalized.hasPrefix("contact")
            || normalized.hasPrefix("copyright")
            || normalized.hasPrefix("修订")
            || normalized.hasPrefix("联系")
    }
}

private struct FDXParagraph {
    var type: String
    var number: String?
    var text: String
    var hasInlineStyle: Bool
    var isInsideDualDialogue: Bool
    var scriptWorkshopRole: String
    var startsNewPage: Bool
    var hasTextOutsideTextElement: Bool
}

private final class FDXCollector: NSObject, XMLParserDelegate {
    var rootName = ""
    var bodyParagraphs: [FDXParagraph] = []
    var titleParagraphs: [FDXParagraph] = []
    var diagnostics: [ScriptWorkshopFDXDiagnostic] = []
    var documentTitle: String?
    var documentAuthor: String?
    var limitFailure: String?

    private var elementStack: [String] = []
    private var currentParagraph: FDXParagraph?
    private var paragraphDepth: Int?
    private var textElementDepth = 0
    private var dualDialogueDepth = 0
    private var metadataField: String?
    private var metadataBuffer = ""
    private var paragraphCount = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard limitFailure == nil else { return }
        if elementStack.count >= 128 {
            limitFailure = "XML nesting exceeds 128 levels."
            parser.abortParsing()
            return
        }
        if rootName.isEmpty {
            rootName = elementName
        }
        elementStack.append(elementName)

        if elementName.caseInsensitiveCompare("DualDialogue") == .orderedSame {
            dualDialogueDepth += 1
        }
        if elementName.caseInsensitiveCompare("Paragraph") == .orderedSame,
           currentParagraph == nil {
            paragraphCount += 1
            if paragraphCount > 100_000 {
                limitFailure = "The document contains more than 100,000 paragraphs."
                parser.abortParsing()
                return
            }
            currentParagraph = FDXParagraph(
                type: attributeValue("Type", in: attributeDict) ?? "",
                number: attributeValue("Number", in: attributeDict),
                text: "",
                hasInlineStyle: false,
                isInsideDualDialogue: dualDialogueDepth > 0,
                scriptWorkshopRole: attributeValue("ScriptWorkshopRole", in: attributeDict) ?? "",
                startsNewPage: {
                    let value = attributeValue("StartsNewPage", in: attributeDict)?.lowercased()
                    return value == "yes" || value == "true" || value == "1"
                }(),
                hasTextOutsideTextElement: false
            )
            paragraphDepth = elementStack.count
        } else if elementName.caseInsensitiveCompare("Text") == .orderedSame,
                  currentParagraph != nil {
            textElementDepth += 1
            if !attributeDict.isEmpty {
                currentParagraph?.hasInlineStyle = true
            }
        }

        if currentParagraph == nil,
           isInsideDocumentProperties,
           elementName.caseInsensitiveCompare("Title") == .orderedSame
            || currentParagraph == nil
                && isInsideDocumentProperties
                && elementName.caseInsensitiveCompare("Author") == .orderedSame {
            metadataField = elementName
            metadataBuffer = ""
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName.caseInsensitiveCompare("Text") == .orderedSame,
           currentParagraph != nil {
            textElementDepth = max(0, textElementDepth - 1)
        }

        if elementName.caseInsensitiveCompare("Paragraph") == .orderedSame,
           let paragraphDepth,
           paragraphDepth == elementStack.count,
           let paragraph = currentParagraph {
            if isInsideTitlePage {
                titleParagraphs.append(paragraph)
            } else if isInsideBodyContent {
                bodyParagraphs.append(paragraph)
            } else if !paragraph.text.trimmedForFDX.isEmpty {
                diagnostics.append(
                    ScriptWorkshopFDXDiagnostic(
                        severity: .warning,
                        code: "paragraph-outside-content",
                        message: "A paragraph outside FinalDraft Content/TitlePage was not imported.",
                        paragraphType: paragraph.type
                    )
                )
            }
            currentParagraph = nil
            self.paragraphDepth = nil
            textElementDepth = 0
        }

        if let metadataField,
           elementName.caseInsensitiveCompare(metadataField) == .orderedSame {
            if metadataField.caseInsensitiveCompare("Title") == .orderedSame {
                documentTitle = metadataBuffer
            } else {
                documentAuthor = metadataBuffer
            }
            self.metadataField = nil
            metadataBuffer = ""
        }

        if elementName.caseInsensitiveCompare("DualDialogue") == .orderedSame {
            dualDialogueDepth = max(0, dualDialogueDepth - 1)
        }
        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentParagraph != nil, textElementDepth > 0 {
            currentParagraph?.text += string
        } else if currentParagraph != nil, !string.trimmedForFDX.isEmpty {
            currentParagraph?.text += string
            currentParagraph?.hasTextOutsideTextElement = true
        } else if metadataField != nil {
            metadataBuffer += string
        }
    }

    private var isInsideTitlePage: Bool {
        elementStack.contains { $0.caseInsensitiveCompare("TitlePage") == .orderedSame }
    }

    private var isInsideBodyContent: Bool {
        !isInsideTitlePage
            && elementStack.contains { $0.caseInsensitiveCompare("Content") == .orderedSame }
    }

    private var isInsideDocumentProperties: Bool {
        elementStack.contains {
            $0.caseInsensitiveCompare("DocumentProperties") == .orderedSame
        }
    }

    private func attributeValue(_ name: String, in attributes: [String: String]) -> String? {
        if let exact = attributes[name] {
            return exact
        }
        return attributes.first {
            $0.key.caseInsensitiveCompare(name) == .orderedSame
        }?.value
    }
}

private extension String {
    var trimmedForFDX: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmptyFDX: String? {
        isEmpty ? nil : self
    }
}

private extension Array where Element == ScriptWorkshopFDXDiagnostic {
    mutating func appendOnceFDX(_ diagnostic: ScriptWorkshopFDXDiagnostic) {
        guard !contains(where: { $0.code == diagnostic.code }) else { return }
        append(diagnostic)
    }
}
