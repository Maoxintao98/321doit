import Foundation

enum ScriptWorkshopAnalysisSeverity: String, Codable, CaseIterable, Equatable {
    case information
    case warning
    case error
}

struct ScriptWorkshopAnalysisIssue: Codable, Equatable {
    var severity: ScriptWorkshopAnalysisSeverity
    var code: String
    var message: String
    var sceneID: UUID?
    var blockID: UUID?
    var fixHint: String

    init(
        severity: ScriptWorkshopAnalysisSeverity,
        code: String,
        message: String,
        sceneID: UUID? = nil,
        blockID: UUID? = nil,
        fixHint: String = ""
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.sceneID = sceneID
        self.blockID = blockID
        self.fixHint = fixHint
    }
}

struct ScriptWorkshopCharacterDialogueStats: Codable, Equatable {
    var character: String
    var dialogueBlockCount: Int
    var sourceLineCount: Int
    var renderedLineCount: Int
    var wordCount: Int
    var characterCount: Int
    var sceneCount: Int
}

struct ScriptWorkshopAnalysisStats: Codable, Equatable {
    /// Script pages only. The unnumbered title page is reported separately.
    var pageCount: Int
    var totalPDFPageCount: Int
    var hasTitlePage: Bool
    var sceneCount: Int
    var nonEmptySceneCount: Int
    var blockCount: Int
    /// Words in non-omitted block text. Each CJK letter counts as one word;
    /// adjacent Latin letters/numbers count as one word. Scene headings are excluded.
    var wordCount: Int
    var characterCount: Int
    var actionCharacterCount: Int
    var dialogueCharacterCount: Int
    var actionRenderedLineCount: Int
    var dialogueRenderedLineCount: Int
    /// Dialogue characters divided by action plus dialogue characters.
    var dialogueShare: Double
    /// Action characters divided by dialogue characters, or nil without dialogue.
    var actionToDialogueRatio: Double?
    var averageScriptPagesPerScene: Double
    var targetPageCount: Int?
    var targetPageDeviation: Int?
    var characterDialogue: [ScriptWorkshopCharacterDialogueStats]
}

struct ScriptWorkshopAnalysisOptions: Codable, Equatable {
    var longActionCharacterThreshold: Int
    var longActionRenderedLineThreshold: Int
    var targetPageWarningFraction: Double
    var targetPageInformationFraction: Double
    var requireBeatLinks: Bool
    var countNotesAsWords: Bool

    init(
        longActionCharacterThreshold: Int = 500,
        longActionRenderedLineThreshold: Int = 8,
        targetPageWarningFraction: Double = 0.25,
        targetPageInformationFraction: Double = 0.15,
        requireBeatLinks: Bool = true,
        countNotesAsWords: Bool = false
    ) {
        self.longActionCharacterThreshold = max(1, longActionCharacterThreshold)
        self.longActionRenderedLineThreshold = max(1, longActionRenderedLineThreshold)
        self.targetPageWarningFraction = max(0, targetPageWarningFraction)
        self.targetPageInformationFraction = max(
            0,
            min(targetPageInformationFraction, targetPageWarningFraction)
        )
        self.requireBeatLinks = requireBeatLinks
        self.countNotesAsWords = countNotesAsWords
    }
}

struct ScriptWorkshopAnalysisReport: Codable, Equatable {
    var stats: ScriptWorkshopAnalysisStats
    var issues: [ScriptWorkshopAnalysisIssue]

    var errorCount: Int {
        issues.filter { $0.severity == .error }.count
    }

    var warningCount: Int {
        issues.filter { $0.severity == .warning }.count
    }
}

enum ScriptWorkshopAnalysis {
    static func analyze(
        _ document: ScriptWorkshopDocument,
        pagination: ScriptWorkshopPaginationResult? = nil,
        paginationConfiguration: ScriptWorkshopPaginationConfiguration = ScriptWorkshopPaginationConfiguration(),
        sceneNumbers: [UUID: String] = [:],
        options: ScriptWorkshopAnalysisOptions = ScriptWorkshopAnalysisOptions()
    ) -> ScriptWorkshopAnalysisReport {
        let paginationResult = pagination ?? ScriptWorkshopPagination.paginate(
            document,
            configuration: paginationConfiguration,
            sceneNumbers: sceneNumbers
        )
        var issues: [ScriptWorkshopAnalysisIssue] = paginationResult.diagnostics.map {
            ScriptWorkshopAnalysisIssue(
                severity: $0.severity == .warning ? .warning : .information,
                code: "pagination.\($0.code)",
                message: $0.message,
                sceneID: $0.sceneID,
                blockID: $0.blockID,
                fixHint: "Review the affected content and pagination settings before export."
            )
        }

        let renderedLineCounts = renderedLineCountsByBlock(paginationResult)
        var characterAccumulators: [String: CharacterAccumulator] = [:]
        var actionCharacterCount = 0
        var dialogueCharacterCount = 0
        var actionRenderedLineCount = 0
        var dialogueRenderedLineCount = 0
        var totalWords = 0
        var totalCharacters = 0
        var totalBlocks = 0
        var nonEmptySceneCount = 0

        for scene in document.scenes {
            let scriptBlocks = scene.blocks.filter {
                $0.metadata?.omitted != true && $0.kind != .note
            }
            let hasScriptContent = scriptBlocks.contains {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if hasScriptContent {
                nonEmptySceneCount += 1
            } else {
                issues.append(
                    ScriptWorkshopAnalysisIssue(
                        severity: .warning,
                        code: "empty-scene",
                        message: "Scene “\(scene.heading.analysisNonEmpty ?? "Untitled")” has no script content.",
                        sceneID: scene.id,
                        fixHint: "Add an action or dialogue block, or remove the unused scene."
                    )
                )
            }

            if !isValidSceneHeading(scene.heading) {
                issues.append(
                    ScriptWorkshopAnalysisIssue(
                        severity: .warning,
                        code: "invalid-scene-heading",
                        message: "The scene heading does not begin with a recognized INT/EXT or Chinese interior/exterior marker.",
                        sceneID: scene.id,
                        fixHint: "Use a heading such as “INT. LOCATION - DAY” or “内景 · 地点 · 日”."
                    )
                )
            }

            analyzeSceneFormatting(
                scene,
                renderedLineCounts: renderedLineCounts,
                options: options,
                issues: &issues
            )

            var activeCharacter: String?
            var characterSpokeInScene = Set<String>()
            for block in scene.blocks where block.metadata?.omitted != true {
                let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if block.kind != .note || options.countNotesAsWords {
                    let units = countTextUnits(block.text)
                    totalWords += units.words
                    totalCharacters += units.characters
                }
                totalBlocks += 1

                switch block.kind {
                case .character:
                    activeCharacter = normalizedCharacterName(trimmed)

                case .parenthetical:
                    break

                case .dialogue:
                    let units = countTextUnits(block.text)
                    dialogueCharacterCount += units.characters
                    dialogueRenderedLineCount += renderedLineCounts[block.id, default: 0]
                    guard let activeCharacter, !activeCharacter.isEmpty else {
                        continue
                    }
                    let key = activeCharacter.uppercased()
                    var accumulator = characterAccumulators[key]
                        ?? CharacterAccumulator(displayName: activeCharacter)
                    accumulator.dialogueBlockCount += 1
                    accumulator.sourceLineCount += max(
                        1,
                        block.text.components(separatedBy: .newlines)
                            .filter { !$0.isEmpty }.count
                    )
                    accumulator.renderedLineCount += renderedLineCounts[block.id, default: 0]
                    accumulator.wordCount += units.words
                    accumulator.characterCount += units.characters
                    if characterSpokeInScene.insert(key).inserted {
                        accumulator.sceneCount += 1
                    }
                    characterAccumulators[key] = accumulator

                case .action:
                    let units = countTextUnits(block.text)
                    actionCharacterCount += units.characters
                    actionRenderedLineCount += renderedLineCounts[block.id, default: 0]
                    activeCharacter = nil

                case .transition, .shot:
                    activeCharacter = nil

                case .note:
                    break
                }
            }
        }

        analyzeSceneNumbers(
            document,
            explicitNumbers: sceneNumbers,
            issues: &issues
        )
        analyzeBeatLinks(document, options: options, issues: &issues)

        let targetPageCount = document.workspace?.targetPageCount
        let actualPageCount = paginationResult.scriptPageCount
        let deviation = targetPageCount.flatMap {
            $0 > 0 ? actualPageCount - $0 : nil
        }
        if let targetPageCount, targetPageCount > 0, let deviation, deviation != 0 {
            let fraction = Double(abs(deviation)) / Double(targetPageCount)
            if fraction >= options.targetPageWarningFraction {
                issues.append(
                    ScriptWorkshopAnalysisIssue(
                        severity: .warning,
                        code: "target-page-count-large-deviation",
                        message: "The script is \(actualPageCount) pages, \(abs(deviation)) \(deviation < 0 ? "under" : "over") the \(targetPageCount)-page target.",
                        fixHint: "Review scene lengths or update the project target if the current scope is intentional."
                    )
                )
            } else if fraction >= options.targetPageInformationFraction {
                issues.append(
                    ScriptWorkshopAnalysisIssue(
                        severity: .information,
                        code: "target-page-count-deviation",
                        message: "The script is \(actualPageCount) pages versus a \(targetPageCount)-page target.",
                        fixHint: "Check pacing and remaining outline beats before the next draft."
                    )
                )
            }
        }

        let characterStats = characterAccumulators.values.map {
            ScriptWorkshopCharacterDialogueStats(
                character: $0.displayName,
                dialogueBlockCount: $0.dialogueBlockCount,
                sourceLineCount: $0.sourceLineCount,
                renderedLineCount: $0.renderedLineCount,
                wordCount: $0.wordCount,
                characterCount: $0.characterCount,
                sceneCount: $0.sceneCount
            )
        }.sorted {
            if $0.renderedLineCount != $1.renderedLineCount {
                return $0.renderedLineCount > $1.renderedLineCount
            }
            return $0.character.localizedCaseInsensitiveCompare($1.character)
                == .orderedAscending
        }

        let actionAndDialogue = actionCharacterCount + dialogueCharacterCount
        let dialogueShare = actionAndDialogue > 0
            ? Double(dialogueCharacterCount) / Double(actionAndDialogue)
            : 0
        let ratio = dialogueCharacterCount > 0
            ? Double(actionCharacterCount) / Double(dialogueCharacterCount)
            : nil
        let stats = ScriptWorkshopAnalysisStats(
            pageCount: actualPageCount,
            totalPDFPageCount: paginationResult.pages.count,
            hasTitlePage: paginationResult.pages.contains { $0.kind == .titlePage },
            sceneCount: document.scenes.count,
            nonEmptySceneCount: nonEmptySceneCount,
            blockCount: totalBlocks,
            wordCount: totalWords,
            characterCount: totalCharacters,
            actionCharacterCount: actionCharacterCount,
            dialogueCharacterCount: dialogueCharacterCount,
            actionRenderedLineCount: actionRenderedLineCount,
            dialogueRenderedLineCount: dialogueRenderedLineCount,
            dialogueShare: dialogueShare,
            actionToDialogueRatio: ratio,
            averageScriptPagesPerScene: document.scenes.isEmpty
                ? 0
                : Double(actualPageCount) / Double(document.scenes.count),
            targetPageCount: targetPageCount,
            targetPageDeviation: deviation,
            characterDialogue: characterStats
        )
        return ScriptWorkshopAnalysisReport(stats: stats, issues: issues)
    }

    private static func analyzeSceneFormatting(
        _ scene: ScriptWorkshopScene,
        renderedLineCounts: [UUID: Int],
        options: ScriptWorkshopAnalysisOptions,
        issues: inout [ScriptWorkshopAnalysisIssue]
    ) {
        var activeCharacterBlock: ScriptWorkshopBlock?
        var characterHasDialogue = false

        func finishCharacterCue() {
            guard let cue = activeCharacterBlock, !characterHasDialogue else {
                activeCharacterBlock = nil
                characterHasDialogue = false
                return
            }
            issues.append(
                ScriptWorkshopAnalysisIssue(
                    severity: .warning,
                    code: "character-without-dialogue",
                    message: "Character cue “\(cue.text.analysisNonEmpty ?? "Unnamed")” is not followed by dialogue.",
                    sceneID: scene.id,
                    blockID: cue.id,
                    fixHint: "Add dialogue after the cue or change the cue to the intended element type."
                )
            )
            activeCharacterBlock = nil
            characterHasDialogue = false
        }

        for block in scene.blocks where block.metadata?.omitted != true {
            let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch block.kind {
            case .character:
                finishCharacterCue()
                activeCharacterBlock = trimmed.isEmpty ? nil : block
                characterHasDialogue = false

            case .parenthetical:
                if activeCharacterBlock == nil {
                    issues.append(
                        ScriptWorkshopAnalysisIssue(
                            severity: .warning,
                            code: "orphan-parenthetical",
                            message: "A parenthetical is not attached to a character cue.",
                            sceneID: scene.id,
                            blockID: block.id,
                            fixHint: "Move it after a character cue or convert it to action."
                        )
                    )
                }

            case .dialogue:
                if activeCharacterBlock == nil {
                    issues.append(
                        ScriptWorkshopAnalysisIssue(
                            severity: .error,
                            code: "orphan-dialogue",
                            message: "Dialogue appears without an active character cue.",
                            sceneID: scene.id,
                            blockID: block.id,
                            fixHint: "Insert or restore the speaking character immediately before this dialogue."
                        )
                    )
                } else {
                    characterHasDialogue = true
                }

            case .action:
                finishCharacterCue()
                let characterCount = countTextUnits(block.text).characters
                let renderedLines = renderedLineCounts[block.id, default: 0]
                if characterCount >= options.longActionCharacterThreshold
                    || renderedLines >= options.longActionRenderedLineThreshold {
                    issues.append(
                        ScriptWorkshopAnalysisIssue(
                            severity: .warning,
                            code: "long-action-block",
                            message: "An action block is \(characterCount) characters and \(renderedLines) rendered lines long.",
                            sceneID: scene.id,
                            blockID: block.id,
                            fixHint: "Split the action into shorter visual beats where the shot, subject, or dramatic action changes."
                        )
                    )
                }

            case .transition, .shot:
                finishCharacterCue()

            case .note:
                break
            }

            if trimmed.isEmpty, block.kind != .note {
                issues.append(
                    ScriptWorkshopAnalysisIssue(
                        severity: .information,
                        code: "empty-script-block",
                        message: "An empty \(block.kind.rawValue) block remains in the scene.",
                        sceneID: scene.id,
                        blockID: block.id,
                        fixHint: "Remove the empty block if it is not serving as the current insertion point."
                    )
                )
            }
        }
        finishCharacterCue()
    }

    private static func analyzeSceneNumbers(
        _ document: ScriptWorkshopDocument,
        explicitNumbers: [UUID: String],
        issues: inout [ScriptWorkshopAnalysisIssue]
    ) {
        var groups: [String: [(scene: ScriptWorkshopScene, number: String)]] = [:]
        let globallyLocked = document.workspace?.sceneNumbersLocked == true

        for (index, scene) in document.scenes.enumerated() {
            let assignedNumber = explicitNumbers[scene.id]?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).analysisNonEmpty
                ?? scene.metadata?.sceneNumber.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).analysisNonEmpty
            let locked = globallyLocked || scene.metadata?.isNumberLocked == true
            if locked, assignedNumber == nil {
                issues.append(
                    ScriptWorkshopAnalysisIssue(
                        severity: .error,
                        code: "locked-scene-missing-number",
                        message: "A locked scene has no production number.",
                        sceneID: scene.id,
                        fixHint: "Assign a unique scene number before issuing or exporting the production draft."
                    )
                )
            }
            let number = assignedNumber ?? String(index + 1)
            groups[number.uppercased(), default: []].append((scene, number))
        }

        for numberKey in groups.keys.sorted() {
            guard let group = groups[numberKey], group.count > 1 else { continue }
            let isLockedDuplicate = globallyLocked || group.contains {
                $0.scene.metadata?.isNumberLocked == true
            }
            guard isLockedDuplicate else { continue }
            for item in group {
                issues.append(
                    ScriptWorkshopAnalysisIssue(
                        severity: .error,
                        code: "duplicate-locked-scene-number",
                        message: "Locked scene number “\(item.number)” is used by \(group.count) scenes.",
                        sceneID: item.scene.id,
                        fixHint: "Assign a unique locked number or an A/B suffix without renumbering issued scenes."
                    )
                )
            }
        }
    }

    private static func analyzeBeatLinks(
        _ document: ScriptWorkshopDocument,
        options: ScriptWorkshopAnalysisOptions,
        issues: inout [ScriptWorkshopAnalysisIssue]
    ) {
        let beats = document.workspace?.beats ?? []
        let sceneIDs = Set(document.scenes.map(\.id))
        let sceneIDsLinkedByBeat = Set(beats.flatMap(\.sceneIDs))

        if options.requireBeatLinks {
            for scene in document.scenes {
                let metadataLinks = scene.metadata?.beatIDs ?? []
                if metadataLinks.isEmpty, !sceneIDsLinkedByBeat.contains(scene.id) {
                    issues.append(
                        ScriptWorkshopAnalysisIssue(
                            severity: .information,
                            code: "scene-without-beat",
                            message: "Scene “\(scene.heading.analysisNonEmpty ?? "Untitled")” is not linked to an outline beat.",
                            sceneID: scene.id,
                            fixHint: "Link the scene to an existing beat or create a beat from the scene."
                        )
                    )
                }
            }
        }

        let knownBeatIDs = Set(beats.map(\.id))
        for scene in document.scenes {
            for beatID in scene.metadata?.beatIDs ?? [] where !knownBeatIDs.contains(beatID) {
                issues.append(
                    ScriptWorkshopAnalysisIssue(
                        severity: .warning,
                        code: "dangling-scene-beat-link",
                        message: "A scene points to an outline beat that no longer exists.",
                        sceneID: scene.id,
                        fixHint: "Remove the stale link or reconnect the scene to a current beat."
                    )
                )
            }
        }
        for beat in beats {
            if beat.sceneIDs.isEmpty {
                issues.append(
                    ScriptWorkshopAnalysisIssue(
                        severity: .information,
                        code: "beat-without-scene",
                        message: "Outline beat “\(beat.title)” is not linked to a script scene.",
                        fixHint: "Link it to a scene when drafted, or mark it intentionally unassigned."
                    )
                )
            }
            if beat.sceneIDs.contains(where: { !sceneIDs.contains($0) }) {
                issues.append(
                    ScriptWorkshopAnalysisIssue(
                        severity: .warning,
                        code: "dangling-beat-scene-link",
                        message: "Outline beat “\(beat.title)” references a scene that no longer exists.",
                        fixHint: "Remove the stale scene reference from the beat."
                    )
                )
            }
        }
    }

    private static func renderedLineCountsByBlock(
        _ pagination: ScriptWorkshopPaginationResult
    ) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        for line in pagination.pages.flatMap(\.lines) {
            guard let blockID = line.blockID, !line.isGenerated else { continue }
            result[blockID, default: 0] += 1
        }
        return result
    }

    private static func isValidSceneHeading(_ heading: String) -> Bool {
        let trimmed = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let upper = trimmed.uppercased()
        let latinPrefixes = [
            "INT.", "EXT.", "INT/EXT.", "INT./EXT.", "I/E.", "EST."
        ]
        if latinPrefixes.contains(where: { upper.hasPrefix($0) }) {
            return true
        }
        return ["内景", "外景", "内/外", "内外景", "室内", "室外"].contains {
            trimmed.hasPrefix($0)
        }
    }

    private static func normalizedCharacterName(_ value: String) -> String? {
        let name = value
            .replacingOccurrences(
                of: #"(?:\s*[\(（][^\)）]*[\)）])+\s*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.analysisNonEmpty
    }

    private static func countTextUnits(_ text: String) -> (words: Int, characters: Int) {
        var words = 0
        var characters = 0
        var inLatinWord = false

        for character in text {
            if character.isWhitespace {
                if inLatinWord {
                    words += 1
                    inLatinWord = false
                }
                continue
            }
            characters += 1
            if isCJK(character) {
                if inLatinWord {
                    words += 1
                    inLatinWord = false
                }
                words += 1
            } else if character.isLetter || character.isNumber
                        || character == "'" || character == "’" {
                inLatinWord = true
            } else if inLatinWord {
                words += 1
                inLatinWord = false
            }
        }
        if inLatinWord {
            words += 1
        }
        return (words, characters)
    }

    private static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            let value = $0.value
            return (0x3400...0x4DBF).contains(value)
                || (0x4E00...0x9FFF).contains(value)
                || (0xF900...0xFAFF).contains(value)
                || (0x20000...0x323AF).contains(value)
                || (0x3040...0x30FF).contains(value)
                || (0x31F0...0x31FF).contains(value)
                || (0xFF66...0xFF9D).contains(value)
                || (0x3100...0x312F).contains(value)
                || (0x31A0...0x31BF).contains(value)
                || (0x1100...0x11FF).contains(value)
                || (0x3130...0x318F).contains(value)
                || (0xA960...0xA97F).contains(value)
                || (0xAC00...0xD7AF).contains(value)
                || (0xD7B0...0xD7FF).contains(value)
        }
    }
}

private struct CharacterAccumulator {
    var displayName: String
    var dialogueBlockCount = 0
    var sourceLineCount = 0
    var renderedLineCount = 0
    var wordCount = 0
    var characterCount = 0
    var sceneCount = 0
}

private extension String {
    var analysisNonEmpty: String? {
        isEmpty ? nil : self
    }
}
