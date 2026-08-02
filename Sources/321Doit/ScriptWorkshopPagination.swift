import Foundation

enum ScriptWorkshopScreenplayFormat: String, Codable, CaseIterable, Equatable {
    /// Existing US/international screenplay layout on Letter paper.
    case international

    /// Mainland Chinese production convention on A4 paper.
    case mainlandChina

    /// Hong Kong production convention with 時／景／人 scene headers.
    case hongKong

    var defaultPaperSize: ScriptWorkshopPaperSize {
        switch self {
        case .international: return .letter
        case .mainlandChina, .hongKong: return .a4
        }
    }

    var isChineseProductionFormat: Bool {
        self != .international
    }
}

enum ScriptWorkshopPaperSize: String, Codable, CaseIterable, Equatable {
    case letter
    case a4

    var widthPoints: Double {
        switch self {
        case .letter: return 612
        case .a4: return 595.275590551
        }
    }

    var heightPoints: Double {
        switch self {
        case .letter: return 792
        case .a4: return 841.88976378
        }
    }
}

struct ScriptWorkshopPageNumber: Codable, Hashable, Comparable {
    var base: Int
    var suffix: String

    init(base: Int, suffix: String = "") {
        self.base = max(1, base)
        self.suffix = suffix
    }

    var displayValue: String {
        "\(base)\(suffix)"
    }

    static func < (lhs: ScriptWorkshopPageNumber, rhs: ScriptWorkshopPageNumber) -> Bool {
        if lhs.base != rhs.base { return lhs.base < rhs.base }
        return lhs.suffix < rhs.suffix
    }
}

struct ScriptWorkshopLayoutFrame: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct ScriptWorkshopSourceRange: Codable, Equatable {
    /// Grapheme-cluster offset, not a UTF-8/UTF-16 byte offset.
    var location: Int
    var length: Int
}

enum ScriptWorkshopLayoutLineRole: Equatable {
    case title
    case author
    case sceneHeading
    case block(ScriptWorkshopBlockKind)
    case more
    case continuedCharacter
}

enum ScriptWorkshopLayoutAlignment: String, Codable, Equatable {
    case left
    case center
    case right
}

struct ScriptWorkshopLayoutLine: Equatable {
    var text: String
    var role: ScriptWorkshopLayoutLineRole
    var frame: ScriptWorkshopLayoutFrame
    var sceneID: UUID?
    var blockID: UUID?
    var sourceRange: ScriptWorkshopSourceRange?
    var sceneNumber: String?
    var isGenerated: Bool
    var alignment: ScriptWorkshopLayoutAlignment
}

enum ScriptWorkshopPageKind: String, Codable, Equatable {
    case titlePage
    case script
}

struct ScriptWorkshopPageLayout: Equatable {
    var kind: ScriptWorkshopPageKind
    var paperSize: ScriptWorkshopPaperSize
    var pageNumber: ScriptWorkshopPageNumber?
    var pageNumberFrame: ScriptWorkshopLayoutFrame?
    var lines: [ScriptWorkshopLayoutLine]
}

enum ScriptWorkshopPaginationDiagnosticSeverity: String, Codable, Equatable {
    case information
    case warning
}

struct ScriptWorkshopPaginationDiagnostic: Codable, Equatable {
    var severity: ScriptWorkshopPaginationDiagnosticSeverity
    var code: String
    var message: String
    var sceneID: UUID?
    var blockID: UUID?
}

struct ScriptWorkshopPaginationResult: Equatable {
    var configuration: ScriptWorkshopPaginationConfiguration
    var pages: [ScriptWorkshopPageLayout]
    var diagnostics: [ScriptWorkshopPaginationDiagnostic]

    var scriptPageCount: Int {
        pages.filter { $0.kind == .script }.count
    }
}

struct ScriptWorkshopPaginationConfiguration: Equatable {
    var screenplayFormat: ScriptWorkshopScreenplayFormat
    var paperSize: ScriptWorkshopPaperSize
    var includeTitlePage: Bool
    var fontSize: Double
    var lineHeight: Double
    var topMargin: Double
    var bottomMargin: Double
    var leftMargin: Double
    var rightMargin: Double
    var characterIndent: Double
    var dialogueIndent: Double
    var dialogueWidth: Double
    var parentheticalIndent: Double
    var parentheticalWidth: Double
    var paragraphSpacingLines: Int
    var minimumLinesAfterSceneHeading: Int
    var minimumDialogueLinesBeforeMore: Int
    var minimumDialogueLinesAfterContinued: Int
    var latinGlyphWidthFactor: Double
    var cjkGlyphWidthFactor: Double

    init(
        screenplayFormat: ScriptWorkshopScreenplayFormat = .international,
        paperSize: ScriptWorkshopPaperSize = .letter,
        includeTitlePage: Bool = true,
        fontSize: Double = 12,
        lineHeight: Double = 12,
        topMargin: Double = 72,
        bottomMargin: Double = 72,
        leftMargin: Double = 108,
        rightMargin: Double = 72,
        characterIndent: Double = 144,
        dialogueIndent: Double = 72,
        dialogueWidth: Double = 252,
        parentheticalIndent: Double = 108,
        parentheticalWidth: Double = 180,
        paragraphSpacingLines: Int = 1,
        minimumLinesAfterSceneHeading: Int = 1,
        minimumDialogueLinesBeforeMore: Int = 2,
        minimumDialogueLinesAfterContinued: Int = 2,
        latinGlyphWidthFactor: Double = 0.6,
        cjkGlyphWidthFactor: Double = 1.0
    ) {
        self.screenplayFormat = screenplayFormat
        self.paperSize = paperSize
        self.includeTitlePage = includeTitlePage
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.topMargin = topMargin
        self.bottomMargin = bottomMargin
        self.leftMargin = leftMargin
        self.rightMargin = rightMargin
        self.characterIndent = characterIndent
        self.dialogueIndent = dialogueIndent
        self.dialogueWidth = dialogueWidth
        self.parentheticalIndent = parentheticalIndent
        self.parentheticalWidth = parentheticalWidth
        self.paragraphSpacingLines = paragraphSpacingLines
        self.minimumLinesAfterSceneHeading = minimumLinesAfterSceneHeading
        self.minimumDialogueLinesBeforeMore = minimumDialogueLinesBeforeMore
        self.minimumDialogueLinesAfterContinued = minimumDialogueLinesAfterContinued
        self.latinGlyphWidthFactor = latinGlyphWidthFactor
        self.cjkGlyphWidthFactor = cjkGlyphWidthFactor
    }

    static func preset(
        for format: ScriptWorkshopScreenplayFormat,
        includeTitlePage: Bool = true,
        paperSize: ScriptWorkshopPaperSize? = nil
    ) -> ScriptWorkshopPaginationConfiguration {
        switch format {
        case .international:
            return ScriptWorkshopPaginationConfiguration(
                screenplayFormat: format,
                paperSize: paperSize ?? format.defaultPaperSize,
                includeTitlePage: includeTitlePage
            )
        case .mainlandChina, .hongKong:
            return ScriptWorkshopPaginationConfiguration(
                screenplayFormat: format,
                paperSize: paperSize ?? format.defaultPaperSize,
                includeTitlePage: includeTitlePage,
                fontSize: 12,
                lineHeight: 18,
                topMargin: 72,
                bottomMargin: 72,
                leftMargin: 72,
                rightMargin: 72,
                characterIndent: 0,
                dialogueIndent: 0,
                dialogueWidth: 451,
                parentheticalIndent: 0,
                parentheticalWidth: 451,
                paragraphSpacingLines: 1,
                minimumLinesAfterSceneHeading: 2,
                minimumDialogueLinesBeforeMore: 2,
                minimumDialogueLinesAfterContinued: 2,
                latinGlyphWidthFactor: 0.55,
                cjkGlyphWidthFactor: 1.0
            )
        }
    }
}

enum ScriptWorkshopPagination {
    static func paginate(
        _ document: ScriptWorkshopDocument,
        configuration: ScriptWorkshopPaginationConfiguration = ScriptWorkshopPaginationConfiguration(),
        sceneNumbers: [UUID: String] = [:]
    ) -> ScriptWorkshopPaginationResult {
        var diagnostics: [ScriptWorkshopPaginationDiagnostic] = []
        let normalized = normalize(configuration, diagnostics: &diagnostics)
        let engine = PaginationEngine(
            document: document,
            configuration: normalized,
            sceneNumbers: sceneNumbers,
            diagnostics: diagnostics
        )
        return engine.run()
    }

    /// Deterministic measurement used by wrapping and available to PDF clients
    /// that need to place auxiliary labels using the same metric.
    static func measuredWidth(
        of text: String,
        configuration: ScriptWorkshopPaginationConfiguration = ScriptWorkshopPaginationConfiguration()
    ) -> Double {
        text.reduce(0) { partial, character in
            partial + glyphWidth(character, configuration: configuration)
        }
    }

    private static func normalize(
        _ input: ScriptWorkshopPaginationConfiguration,
        diagnostics: inout [ScriptWorkshopPaginationDiagnostic]
    ) -> ScriptWorkshopPaginationConfiguration {
        var value = input
        func replaceIfInvalid(
            _ keyPath: WritableKeyPath<ScriptWorkshopPaginationConfiguration, Double>,
            fallback: Double,
            code: String
        ) {
            if !value[keyPath: keyPath].isFinite || value[keyPath: keyPath] <= 0 {
                value[keyPath: keyPath] = fallback
                diagnostics.append(
                    ScriptWorkshopPaginationDiagnostic(
                        severity: .warning,
                        code: code,
                        message: "An invalid pagination value was replaced with \(fallback).",
                        sceneID: nil,
                        blockID: nil
                    )
                )
            }
        }
        replaceIfInvalid(\.fontSize, fallback: 12, code: "invalid-font-size")
        replaceIfInvalid(\.lineHeight, fallback: 12, code: "invalid-line-height")
        replaceIfInvalid(\.latinGlyphWidthFactor, fallback: 0.6, code: "invalid-latin-width")
        replaceIfInvalid(\.cjkGlyphWidthFactor, fallback: 1.0, code: "invalid-cjk-width")
        value.topMargin = max(0, value.topMargin)
        value.bottomMargin = max(0, value.bottomMargin)
        value.leftMargin = max(0, value.leftMargin)
        value.rightMargin = max(0, value.rightMargin)
        value.characterIndent = max(0, value.characterIndent)
        value.dialogueIndent = max(0, value.dialogueIndent)
        value.parentheticalIndent = max(0, value.parentheticalIndent)
        value.paragraphSpacingLines = max(0, value.paragraphSpacingLines)
        value.minimumLinesAfterSceneHeading = max(1, value.minimumLinesAfterSceneHeading)
        value.minimumDialogueLinesBeforeMore = max(1, value.minimumDialogueLinesBeforeMore)
        value.minimumDialogueLinesAfterContinued = max(1, value.minimumDialogueLinesAfterContinued)

        let maximumWidth = max(
            72,
            value.paperSize.widthPoints - value.leftMargin - value.rightMargin
        )
        value.dialogueWidth = min(max(72, value.dialogueWidth), maximumWidth)
        value.parentheticalWidth = min(max(72, value.parentheticalWidth), maximumWidth)
        let minimumBodyHeight = value.lineHeight * 8
        let availableBodyHeight = value.paperSize.heightPoints
            - value.topMargin
            - value.bottomMargin
        if availableBodyHeight < minimumBodyHeight {
            value.topMargin = min(value.topMargin, 36)
            value.bottomMargin = max(
                0,
                value.paperSize.heightPoints
                    - value.topMargin
                    - minimumBodyHeight
            )
            diagnostics.append(
                ScriptWorkshopPaginationDiagnostic(
                    severity: .warning,
                    code: "margins-reduced-for-pagination",
                    message: "Page margins left fewer than eight script lines and were reduced deterministically.",
                    sceneID: nil,
                    blockID: nil
                )
            )
        }
        let normalizedSlots = max(
            8,
            Int(
                floor(
                    (
                        value.paperSize.heightPoints
                            - value.topMargin
                            - value.bottomMargin
                    ) / value.lineHeight
                )
            )
        )
        value.minimumLinesAfterSceneHeading = min(
            value.minimumLinesAfterSceneHeading,
            max(1, normalizedSlots - 1)
        )
        value.minimumDialogueLinesBeforeMore = min(
            value.minimumDialogueLinesBeforeMore,
            max(1, normalizedSlots - 3)
        )
        value.minimumDialogueLinesAfterContinued = min(
            value.minimumDialogueLinesAfterContinued,
            max(1, normalizedSlots - 2)
        )
        return value
    }

    fileprivate static func glyphWidth(
        _ character: Character,
        configuration: ScriptWorkshopPaginationConfiguration
    ) -> Double {
        if character == "\t" {
            return configuration.fontSize * configuration.latinGlyphWidthFactor * 4
        }
        if character.unicodeScalars.allSatisfy({
            CharacterSet.nonBaseCharacters.contains($0)
                || $0.value == 0x200D
                || (0xFE00...0xFE0F).contains($0.value)
        }) {
            return 0
        }
        let isWide = character.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x1100...0x115F).contains(value)
                || (0x2329...0x232A).contains(value)
                || (0x2E80...0xA4CF).contains(value)
                || (0xAC00...0xD7A3).contains(value)
                || (0xF900...0xFAFF).contains(value)
                || (0xFE10...0xFE19).contains(value)
                || (0xFE30...0xFE6F).contains(value)
                || (0xFF01...0xFF60).contains(value)
                || (0xFFE0...0xFFE6).contains(value)
                || (0x1F000...0x1FAFF).contains(value)
                || (0x20000...0x3FFFD).contains(value)
        }
        let factor = isWide
            ? configuration.cjkGlyphWidthFactor
            : configuration.latinGlyphWidthFactor
        return configuration.fontSize * factor
    }
}

private struct WrappedPaginationLine {
    var text: String
    var sourceRange: ScriptWorkshopSourceRange
}

private struct PendingPaginationLine {
    var text: String
    var role: ScriptWorkshopLayoutLineRole
    var sceneID: UUID
    var blockID: UUID?
    var sourceRange: ScriptWorkshopSourceRange?
    var x: Double
    var width: Double
    var sceneNumber: String?
    var isGenerated: Bool
    var alignment: ScriptWorkshopLayoutAlignment
}

private final class PaginationEngine {
    private let document: ScriptWorkshopDocument
    private let configuration: ScriptWorkshopPaginationConfiguration
    private let sceneNumbers: [UUID: String]
    private var diagnostics: [ScriptWorkshopPaginationDiagnostic]
    private var pages: [ScriptWorkshopPageLayout] = []
    private var currentLines: [ScriptWorkshopLayoutLine] = []
    private var usedLineSlots = 0
    private var nextScriptPage = 1

    private var contentWidth: Double {
        max(
            72,
            configuration.paperSize.widthPoints
                - configuration.leftMargin
                - configuration.rightMargin
        )
    }

    private var maximumLineSlots: Int {
        max(
            8,
            Int(
                floor(
                    (
                        configuration.paperSize.heightPoints
                            - configuration.topMargin
                            - configuration.bottomMargin
                    ) / configuration.lineHeight
                )
            )
        )
    }

    init(
        document: ScriptWorkshopDocument,
        configuration: ScriptWorkshopPaginationConfiguration,
        sceneNumbers: [UUID: String],
        diagnostics: [ScriptWorkshopPaginationDiagnostic]
    ) {
        self.document = document
        self.configuration = configuration
        self.sceneNumbers = sceneNumbers
        self.diagnostics = diagnostics
    }

    func run() -> ScriptWorkshopPaginationResult {
        if configuration.includeTitlePage {
            pages.append(makeTitlePage())
        }
        startScriptPage()

        for (sceneIndex, scene) in document.scenes.enumerated() {
            paginateScene(scene, fallbackNumber: String(sceneIndex + 1))
        }
        finishCurrentScriptPage()

        return ScriptWorkshopPaginationResult(
            configuration: configuration,
            pages: pages,
            diagnostics: diagnostics
        )
    }

    private func makeTitlePage() -> ScriptWorkshopPageLayout {
        let centerWidth = configuration.paperSize.widthPoints
            - configuration.leftMargin
            - configuration.rightMargin
        let centerX = configuration.leftMargin
        let titleY = configuration.paperSize.heightPoints * 0.33
        var titleLines: [ScriptWorkshopLayoutLine] = []
        let wrappedTitle = wrap(document.title.nonEmptyPagination ?? "未命名剧本", width: centerWidth)
        for (index, line) in wrappedTitle.enumerated() {
            titleLines.append(
                ScriptWorkshopLayoutLine(
                    text: line.text,
                    role: .title,
                    frame: ScriptWorkshopLayoutFrame(
                        x: centerX,
                        y: titleY + Double(index) * configuration.lineHeight,
                        width: centerWidth,
                        height: configuration.lineHeight
                    ),
                    sceneID: nil,
                    blockID: nil,
                    sourceRange: line.sourceRange,
                    sceneNumber: nil,
                    isGenerated: false,
                    alignment: .center
                )
            )
        }
        if !document.author.trimmedPagination.isEmpty {
            let authorY = titleY
                + Double(wrappedTitle.count + 2) * configuration.lineHeight
            titleLines.append(
                ScriptWorkshopLayoutLine(
                    text: authorCreditLabel,
                    role: .author,
                    frame: ScriptWorkshopLayoutFrame(
                        x: centerX,
                        y: authorY,
                        width: centerWidth,
                        height: configuration.lineHeight
                    ),
                    sceneID: nil,
                    blockID: nil,
                    sourceRange: nil,
                    sceneNumber: nil,
                    isGenerated: true,
                    alignment: .center
                )
            )
            for (index, line) in wrap(document.author, width: centerWidth).enumerated() {
                titleLines.append(
                    ScriptWorkshopLayoutLine(
                        text: line.text,
                        role: .author,
                        frame: ScriptWorkshopLayoutFrame(
                            x: centerX,
                            y: authorY + Double(index + 1) * configuration.lineHeight,
                            width: centerWidth,
                            height: configuration.lineHeight
                        ),
                        sceneID: nil,
                        blockID: nil,
                        sourceRange: line.sourceRange,
                        sceneNumber: nil,
                        isGenerated: false,
                        alignment: .center
                    )
                )
            }
        }
        return ScriptWorkshopPageLayout(
            kind: .titlePage,
            paperSize: configuration.paperSize,
            pageNumber: nil,
            pageNumberFrame: nil,
            lines: titleLines
        )
    }

    private func paginateScene(_ scene: ScriptWorkshopScene, fallbackNumber: String) {
        let sceneNumber = sceneNumbers[scene.id]?.trimmedPagination.nonEmptyPagination
            ?? scene.metadata?.sceneNumber.trimmedPagination.nonEmptyPagination
            ?? fallbackNumber
        let headingText = formattedSceneHeading(
            scene,
            sceneNumber: sceneNumber
        )
        let headingLines = wrap(headingText, width: contentWidth).map {
            PendingPaginationLine(
                text: $0.text,
                role: .sceneHeading,
                sceneID: scene.id,
                blockID: nil,
                sourceRange: $0.sourceRange,
                x: configuration.leftMargin,
                width: contentWidth,
                sceneNumber: sceneNumber,
                isGenerated: false,
                alignment: .left
            )
        }
        let headingSpacing = currentLines.isEmpty ? 0 : configuration.paragraphSpacingLines
        let requiredAfterHeading = max(
            1,
            min(
                configuration.minimumLinesAfterSceneHeading,
                max(1, previewFirstBodyLineCount(in: scene))
            )
        )
        paginateSceneHeading(
            headingLines,
            spacingBefore: headingSpacing,
            requiredFollowingLines: requiredAfterHeading,
            sceneID: scene.id
        )

        var blockIndex = 0
        while blockIndex < scene.blocks.count {
            let block = scene.blocks[blockIndex]
            if block.metadata?.explicitPageBreakBefore == true, !currentLines.isEmpty {
                finishCurrentScriptPage()
                startScriptPage()
            }
            if block.metadata?.omitted == true {
                diagnostics.append(
                    ScriptWorkshopPaginationDiagnostic(
                        severity: .information,
                        code: "omitted-block-excluded",
                        message: "An omitted block was excluded from rendered pagination.",
                        sceneID: scene.id,
                        blockID: block.id
                    )
                )
                blockIndex += 1
                continue
            }
            if block.kind == .character {
                let groupEnd = dialogueGroupEnd(in: scene.blocks, startingAt: blockIndex)
                let group = Array(scene.blocks[blockIndex..<groupEnd])
                if configuration.screenplayFormat.isChineseProductionFormat {
                    paginateChineseDialogueGroup(group, sceneID: scene.id)
                } else {
                    paginateDialogueGroup(group, sceneID: scene.id)
                }
                blockIndex = groupEnd
            } else {
                paginateOrdinaryBlock(block, sceneID: scene.id)
                blockIndex += 1
            }
        }
    }

    private func previewFirstBodyLineCount(in scene: ScriptWorkshopScene) -> Int {
        guard let block = scene.blocks.first(where: {
            !$0.text.trimmedPagination.isEmpty
        }) else {
            return 0
        }
        return min(
            configuration.minimumLinesAfterSceneHeading,
            max(1, pendingLines(for: block, sceneID: scene.id).count)
        )
    }

    private func dialogueGroupEnd(
        in blocks: [ScriptWorkshopBlock],
        startingAt index: Int
    ) -> Int {
        var cursor = index + 1
        while cursor < blocks.count {
            let kind = blocks[cursor].kind
            if blocks[cursor].metadata?.explicitPageBreakBefore == true
                || blocks[cursor].metadata?.omitted == true {
                break
            }
            guard kind == .parenthetical || kind == .dialogue else { break }
            cursor += 1
        }
        return cursor
    }

    private func paginateOrdinaryBlock(
        _ block: ScriptWorkshopBlock,
        sceneID: UUID
    ) {
        let lines = pendingLines(for: block, sceneID: sceneID)
        guard !lines.isEmpty else { return }
        var cursor = 0
        var firstFragment = true
        while cursor < lines.count {
            let spacing = firstFragment && !currentLines.isEmpty
                ? configuration.paragraphSpacingLines
                : 0
            if remainingSlots <= spacing {
                finishCurrentScriptPage()
                startScriptPage()
                continue
            }
            let capacity = remainingSlots - spacing
            let count = min(capacity, lines.count - cursor)
            place(
                lines: Array(lines[cursor..<(cursor + count)]),
                spacingBefore: spacing
            )
            cursor += count
            firstFragment = false
            if cursor < lines.count {
                finishCurrentScriptPage()
                startScriptPage()
            }
        }
    }

    private func paginateDialogueGroup(
        _ blocks: [ScriptWorkshopBlock],
        sceneID: UUID
    ) {
        guard let characterBlock = blocks.first else { return }
        let cueLines = pendingLines(for: characterBlock, sceneID: sceneID)
        let contentLines = blocks.dropFirst().flatMap {
            pendingLines(for: $0, sceneID: sceneID)
        }
        guard !cueLines.isEmpty else {
            for block in blocks {
                paginateOrdinaryBlock(block, sceneID: sceneID)
            }
            return
        }
        if cueLines.count
            + configuration.minimumDialogueLinesBeforeMore
            + 1 > maximumLineSlots {
            diagnostics.append(
                ScriptWorkshopPaginationDiagnostic(
                    severity: .warning,
                    code: "oversized-character-cue",
                    message: "An unusually long character cue was paginated as ordinary paragraphs so no text was lost.",
                    sceneID: sceneID,
                    blockID: characterBlock.id
                )
            )
            for block in blocks {
                paginateOrdinaryBlock(block, sceneID: sceneID)
            }
            return
        }

        let initialSpacing = currentLines.isEmpty ? 0 : configuration.paragraphSpacingLines
        let fullRequired = initialSpacing + cueLines.count + contentLines.count
        if fullRequired <= remainingSlots {
            place(lines: cueLines + contentLines, spacingBefore: initialSpacing)
            return
        }

        let minimumInitial = initialSpacing
            + cueLines.count
            + configuration.minimumDialogueLinesBeforeMore
            + 1
        if remainingSlots < minimumInitial, !currentLines.isEmpty {
            finishCurrentScriptPage()
            startScriptPage()
        }

        var remaining = contentLines
        var isFirstPageOfGroup = true
        let cueText = characterBlock.text.trimmedPagination.nonEmptyPagination ?? "CHARACTER"

        while true {
            let activeCue: [PendingPaginationLine]
            let spacing: Int
            if isFirstPageOfGroup {
                activeCue = cueLines
                spacing = currentLines.isEmpty ? 0 : configuration.paragraphSpacingLines
            } else {
                activeCue = [
                    generatedContinuedCue(
                        cueText,
                        sceneID: sceneID,
                        blockID: characterBlock.id
                    )
                ]
                spacing = 0
            }

            let minimumContent = isFirstPageOfGroup
                ? configuration.minimumDialogueLinesBeforeMore
                : configuration.minimumDialogueLinesAfterContinued
            if remainingSlots < spacing + activeCue.count + minimumContent,
               !currentLines.isEmpty {
                finishCurrentScriptPage()
                startScriptPage()
                continue
            }
            place(lines: activeCue, spacingBefore: spacing)

            if remaining.count <= remainingSlots {
                place(lines: remaining, spacingBefore: 0)
                return
            }

            let capacityBeforeMore = max(0, remainingSlots - 1)
            if capacityBeforeMore < minimumContent {
                finishCurrentScriptPage()
                startScriptPage()
                isFirstPageOfGroup = false
                continue
            }

            var takeCount = min(capacityBeforeMore, remaining.count)
            let remainderAfterSplit = remaining.count - takeCount
            if remainderAfterSplit > 0,
               remainderAfterSplit < configuration.minimumDialogueLinesAfterContinued {
                let adjustment = configuration.minimumDialogueLinesAfterContinued
                    - remainderAfterSplit
                if takeCount - adjustment >= minimumContent {
                    takeCount -= adjustment
                }
            }
            guard takeCount > 0 else {
                diagnostics.append(
                    ScriptWorkshopPaginationDiagnostic(
                        severity: .warning,
                        code: "dialogue-pagination-fallback",
                        message: "A dialogue block could not satisfy minimum continuation-line rules and was split at the available boundary.",
                        sceneID: sceneID,
                        blockID: characterBlock.id
                    )
                )
                finishCurrentScriptPage()
                startScriptPage()
                isFirstPageOfGroup = false
                continue
            }

            place(lines: Array(remaining.prefix(takeCount)), spacingBefore: 0)
            remaining.removeFirst(takeCount)
            place(
                lines: [generatedMoreLine(sceneID: sceneID)],
                spacingBefore: 0
            )
            finishCurrentScriptPage()
            startScriptPage()
            isFirstPageOfGroup = false
        }
    }

    private func paginateChineseDialogueGroup(
        _ blocks: [ScriptWorkshopBlock],
        sceneID: UUID
    ) {
        guard let character = blocks.first else { return }
        let cue = character.text.trimmedPagination.nonEmptyPagination ?? "人物"
        var parentheticals: [String] = []
        var emittedDialogue = false

        for block in blocks.dropFirst() {
            switch block.kind {
            case .parenthetical:
                let text = block.text.trimmedPagination
                if !text.isEmpty {
                    parentheticals.append(normalizedChineseParenthetical(text))
                }
            case .dialogue:
                let dialogue = block.text.trimmedPagination
                guard !dialogue.isEmpty else { continue }
                let prefix = parentheticals.joined()
                parentheticals.removeAll(keepingCapacity: true)
                var rendered = block
                rendered.kind = .dialogue
                rendered.text = "\(cue)：\(prefix)\(dialogue)"
                paginateOrdinaryBlock(rendered, sceneID: sceneID)
                emittedDialogue = true
            default:
                paginateOrdinaryBlock(block, sceneID: sceneID)
            }
        }

        if !emittedDialogue || !parentheticals.isEmpty {
            var rendered = character
            rendered.kind = .dialogue
            rendered.text = "\(cue)：\(parentheticals.joined())"
            paginateOrdinaryBlock(rendered, sceneID: sceneID)
        }
    }

    private func pendingLines(
        for block: ScriptWorkshopBlock,
        sceneID: UUID
    ) -> [PendingPaginationLine] {
        let placement = placementForBlock(block.kind)
        let displayText = formattedBlockText(block)
        let trimmed = displayText.trimmedPagination
        guard !trimmed.isEmpty else { return [] }
        return wrap(displayText, width: placement.width).map {
            PendingPaginationLine(
                text: $0.text,
                role: .block(block.kind),
                sceneID: sceneID,
                blockID: block.id,
                sourceRange: $0.sourceRange,
                x: placement.x,
                width: placement.width,
                sceneNumber: nil,
                isGenerated: false,
                alignment: placement.alignment
            )
        }
    }

    private func paginateSceneHeading(
        _ lines: [PendingPaginationLine],
        spacingBefore: Int,
        requiredFollowingLines: Int,
        sceneID: UUID
    ) {
        guard !lines.isEmpty else { return }
        let required = spacingBefore + lines.count + requiredFollowingLines
        if required <= remainingSlots {
            place(lines: lines, spacingBefore: spacingBefore)
            return
        }
        if required <= maximumLineSlots, !currentLines.isEmpty {
            finishCurrentScriptPage()
            startScriptPage()
            place(lines: lines, spacingBefore: 0)
            return
        }

        diagnostics.append(
            ScriptWorkshopPaginationDiagnostic(
                severity: .warning,
                code: "scene-heading-spans-pages",
                message: "An unusually long scene heading was wrapped across pages without dropping text.",
                sceneID: sceneID,
                blockID: nil
            )
        )
        if !currentLines.isEmpty {
            finishCurrentScriptPage()
            startScriptPage()
        }
        var cursor = 0
        var firstFragment = true
        while cursor < lines.count {
            let spacing = firstFragment && !currentLines.isEmpty ? spacingBefore : 0
            let isFinalFragment = lines.count - cursor
                <= max(0, remainingSlots - spacing - requiredFollowingLines)
            let reserved = isFinalFragment ? requiredFollowingLines : 0
            let capacity = max(0, remainingSlots - spacing - reserved)
            if capacity == 0 {
                finishCurrentScriptPage()
                startScriptPage()
                firstFragment = false
                continue
            }
            let count = min(capacity, lines.count - cursor)
            place(
                lines: Array(lines[cursor..<(cursor + count)]),
                spacingBefore: spacing
            )
            cursor += count
            firstFragment = false
            if cursor < lines.count {
                finishCurrentScriptPage()
                startScriptPage()
            }
        }
    }

    private func placementForBlock(
        _ kind: ScriptWorkshopBlockKind
    ) -> (x: Double, width: Double, alignment: ScriptWorkshopLayoutAlignment) {
        if configuration.screenplayFormat.isChineseProductionFormat {
            return (configuration.leftMargin, contentWidth, .left)
        }
        switch kind {
        case .character:
            return (
                configuration.leftMargin + configuration.characterIndent,
                max(72, contentWidth - configuration.characterIndent),
                .left
            )
        case .dialogue:
            return (
                configuration.leftMargin + configuration.dialogueIndent,
                min(configuration.dialogueWidth, contentWidth),
                .left
            )
        case .parenthetical:
            return (
                configuration.leftMargin + configuration.parentheticalIndent,
                min(configuration.parentheticalWidth, contentWidth),
                .left
            )
        case .transition:
            return (configuration.leftMargin, contentWidth, .right)
        case .action, .shot, .note:
            return (configuration.leftMargin, contentWidth, .left)
        }
    }

    private var authorCreditLabel: String {
        switch configuration.screenplayFormat {
        case .international: return "Written by"
        case .mainlandChina: return "编剧"
        case .hongKong: return "編劇"
        }
    }

    private func formattedSceneHeading(
        _ scene: ScriptWorkshopScene,
        sceneNumber: String
    ) -> String {
        let fallback = scene.heading.trimmedPagination.nonEmptyPagination ?? "未命名场景"
        guard configuration.screenplayFormat.isChineseProductionFormat else {
            return fallback
        }
        let parts = ChineseSceneHeadingParts(fallback)
        switch configuration.screenplayFormat {
        case .international:
            return fallback
        case .mainlandChina:
            return "\(sceneNumber). [\(parts.simplifiedInterior)] \(parts.time) \(parts.location)"
        case .hongKong:
            let people = scene.characterNames.isEmpty
                ? "—"
                : scene.characterNames.joined(separator: "、")
            return [
                "場 \(sceneNumber)",
                "時：\(parts.time)",
                "景：\(parts.location)（\(parts.traditionalInterior)）",
                "人：\(people)"
            ].joined(separator: "\n")
        }
    }

    private func formattedBlockText(_ block: ScriptWorkshopBlock) -> String {
        let text = block.text
        guard configuration.screenplayFormat == .hongKong else { return text }
        switch block.kind {
        case .action, .shot:
            return text.trimmedPagination.hasPrefix("△") ? text : "△ \(text)"
        case .note:
            return text.trimmedPagination.hasPrefix("※") ? text : "※ \(text)"
        case .transition:
            return text.trimmedPagination.hasPrefix("△") ? text : "△ \(text)"
        case .character, .dialogue, .parenthetical:
            return text
        }
    }

    private func normalizedChineseParenthetical(_ value: String) -> String {
        let trimmed = value.trimmedPagination
        guard !trimmed.isEmpty else { return "" }
        if (trimmed.hasPrefix("（") && trimmed.hasSuffix("）"))
            || (trimmed.hasPrefix("(") && trimmed.hasSuffix(")")) {
            return trimmed
        }
        return "（\(trimmed)）"
    }

    private func generatedMoreLine(sceneID: UUID) -> PendingPaginationLine {
        PendingPaginationLine(
            text: "(MORE)",
            role: .more,
            sceneID: sceneID,
            blockID: nil,
            sourceRange: nil,
            x: configuration.leftMargin + configuration.characterIndent,
            width: max(72, contentWidth - configuration.characterIndent),
            sceneNumber: nil,
            isGenerated: true,
            alignment: .left
        )
    }

    private func generatedContinuedCue(
        _ cue: String,
        sceneID: UUID,
        blockID: UUID
    ) -> PendingPaginationLine {
        let upper = cue.uppercased()
        let text = upper.contains("CONT'D") || upper.contains("CONT’D")
            ? cue
            : "\(cue) (CONT'D)"
        return PendingPaginationLine(
            text: text,
            role: .continuedCharacter,
            sceneID: sceneID,
            blockID: blockID,
            sourceRange: nil,
            x: configuration.leftMargin + configuration.characterIndent,
            width: max(72, contentWidth - configuration.characterIndent),
            sceneNumber: nil,
            isGenerated: true,
            alignment: .left
        )
    }

    private func place(
        lines: [PendingPaginationLine],
        spacingBefore: Int
    ) {
        guard !lines.isEmpty else { return }
        usedLineSlots += min(spacingBefore, remainingSlots)
        for line in lines {
            guard remainingSlots > 0 else { break }
            let y = configuration.topMargin
                + Double(usedLineSlots) * configuration.lineHeight
            currentLines.append(
                ScriptWorkshopLayoutLine(
                    text: line.text,
                    role: line.role,
                    frame: ScriptWorkshopLayoutFrame(
                        x: line.x,
                        y: y,
                        width: line.width,
                        height: configuration.lineHeight
                    ),
                    sceneID: line.sceneID,
                    blockID: line.blockID,
                    sourceRange: line.sourceRange,
                    sceneNumber: line.sceneNumber,
                    isGenerated: line.isGenerated,
                    alignment: line.alignment
                )
            )
            usedLineSlots += 1
        }
    }

    private var remainingSlots: Int {
        max(0, maximumLineSlots - usedLineSlots)
    }

    private func startScriptPage() {
        currentLines = []
        usedLineSlots = 0
    }

    private func finishCurrentScriptPage() {
        guard !currentLines.isEmpty else { return }
        let number = ScriptWorkshopPageNumber(base: nextScriptPage)
        pages.append(
            ScriptWorkshopPageLayout(
                kind: .script,
                paperSize: configuration.paperSize,
                pageNumber: number,
                pageNumberFrame: ScriptWorkshopLayoutFrame(
                    x: configuration.paperSize.widthPoints
                        - configuration.rightMargin
                        - 54,
                    y: 36,
                    width: 54,
                    height: configuration.lineHeight
                ),
                lines: currentLines
            )
        )
        nextScriptPage += 1
        currentLines = []
        usedLineSlots = 0
    }

    private func wrap(_ text: String, width: Double) -> [WrappedPaginationLine] {
        let characters = Array(text)
        guard !characters.isEmpty else {
            return [
                WrappedPaginationLine(
                    text: "",
                    sourceRange: ScriptWorkshopSourceRange(location: 0, length: 0)
                )
            ]
        }
        let maximumWidth = max(
            configuration.fontSize * configuration.latinGlyphWidthFactor,
            width
        )
        var result: [WrappedPaginationLine] = []
        var paragraphStart = 0

        while paragraphStart <= characters.count {
            let newline = characters[paragraphStart...].firstIndex(of: "\n")
                ?? characters.count
            let paragraphEnd = newline
            if paragraphStart == paragraphEnd {
                result.append(
                    WrappedPaginationLine(
                        text: "",
                        sourceRange: ScriptWorkshopSourceRange(
                            location: paragraphStart,
                            length: 0
                        )
                    )
                )
            } else {
                var lineStart = paragraphStart
                while lineStart < paragraphEnd {
                    var cursor = lineStart
                    var measured = 0.0
                    var lastBreak: Int?
                    while cursor < paragraphEnd {
                        let character = characters[cursor]
                        let characterWidth = ScriptWorkshopPagination.glyphWidth(
                            character,
                            configuration: configuration
                        )
                        if measured + characterWidth > maximumWidth, cursor > lineStart {
                            break
                        }
                        measured += characterWidth
                        cursor += 1
                        if isPreferredBreakCharacter(character) {
                            lastBreak = cursor
                        }
                        if measured > maximumWidth {
                            break
                        }
                    }
                    if cursor < paragraphEnd,
                       let lastBreak,
                       lastBreak > lineStart {
                        cursor = lastBreak
                    }
                    if cursor == lineStart {
                        cursor = min(lineStart + 1, paragraphEnd)
                    }

                    var visibleEnd = cursor
                    while visibleEnd > lineStart,
                          characters[visibleEnd - 1].isWhitespace {
                        visibleEnd -= 1
                    }
                    var visibleStart = lineStart
                    while visibleStart < visibleEnd,
                          characters[visibleStart].isWhitespace {
                        visibleStart += 1
                    }
                    result.append(
                        WrappedPaginationLine(
                            text: String(characters[visibleStart..<visibleEnd]),
                            sourceRange: ScriptWorkshopSourceRange(
                                location: visibleStart,
                                length: max(0, visibleEnd - visibleStart)
                            )
                        )
                    )
                    lineStart = cursor
                    while lineStart < paragraphEnd, characters[lineStart].isWhitespace {
                        lineStart += 1
                    }
                }
            }
            if newline == characters.count { break }
            paragraphStart = newline + 1
            if paragraphStart == characters.count {
                result.append(
                    WrappedPaginationLine(
                        text: "",
                        sourceRange: ScriptWorkshopSourceRange(
                            location: paragraphStart,
                            length: 0
                        )
                    )
                )
                break
            }
        }
        return result
    }

    private func isPreferredBreakCharacter(_ character: Character) -> Bool {
        if character.isWhitespace { return true }
        if character.unicodeScalars.contains(where: {
            let value = $0.value
            return (0x2E80...0xA4CF).contains(value)
                || (0xAC00...0xD7A3).contains(value)
                || (0xF900...0xFAFF).contains(value)
                || (0x20000...0x3FFFD).contains(value)
        }) {
            return true
        }
        return ",.;:!?，。；：！？、—-)]}）】》」』".contains(character)
    }
}

private struct ChineseSceneHeadingParts {
    var location: String
    var time: String
    var simplifiedInterior: String
    var traditionalInterior: String

    init(_ heading: String) {
        let normalized = heading
            .replacingOccurrences(of: "—", with: "·")
            .replacingOccurrences(of: "-", with: "·")
        let rawTokens = normalized
            .components(separatedBy: CharacterSet(charactersIn: "·•|"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var interior: String?
        var timeValue: String?
        var locationTokens: [String] = []
        let timeTokens: Set<String> = [
            "日", "夜", "晨", "午", "清晨", "早", "早晨", "上午",
            "中午", "下午", "傍晚", "黄昏", "黃昏", "深夜"
        ]

        for rawToken in rawTokens {
            let token = rawToken
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .replacingOccurrences(of: "（", with: "")
                .replacingOccurrences(of: "）", with: "")
                .uppercased()
            if interior == nil {
                if token == "内" || token == "內" || token == "内景"
                    || token == "內景" || token == "INT" || token == "INT." {
                    interior = "内"
                    continue
                }
                if token == "外" || token == "外景" || token == "EXT"
                    || token == "EXT." {
                    interior = "外"
                    continue
                }
            }
            if timeValue == nil, timeTokens.contains(rawToken) {
                timeValue = rawToken
                continue
            }
            locationTokens.append(rawToken)
        }

        let resolvedInterior = interior ?? "内"
        location = locationTokens.joined(separator: " · ")
            .trimmedPagination
            .nonEmptyPagination ?? heading.trimmedPagination
        time = timeValue ?? "日"
        simplifiedInterior = resolvedInterior
        traditionalInterior = resolvedInterior == "内" ? "內" : resolvedInterior
    }
}

private extension String {
    var trimmedPagination: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nonEmptyPagination: String? {
        isEmpty ? nil : self
    }
}
