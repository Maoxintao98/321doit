import Foundation

enum ScriptWorkshopFountainDiagnosticSeverity: String, Codable, Equatable {
    case information
    case warning
}

struct ScriptWorkshopFountainDiagnostic: Codable, Equatable {
    var severity: ScriptWorkshopFountainDiagnosticSeverity
    var code: String
    var message: String
}

struct ScriptWorkshopFountainExportResult: Equatable {
    var source: String
    var diagnostics: [ScriptWorkshopFountainDiagnostic]

    var isLossy: Bool {
        diagnostics.contains { $0.severity == .warning }
    }
}

enum ScriptWorkshopFountain {
    private static let shotMarker = "[[321Doit Element: Shot]]"

    static func parse(_ source: String, linkedProjectID: UUID? = nil) -> ScriptWorkshopDocument {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var title = "未命名剧本"
        var author = ""
        var index = 0
        var foundTitlePage = false

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if foundTitlePage {
                    index += 1
                    break
                }
                index += 1
                continue
            }
            if let value = titlePageValue(trimmed, key: "title") {
                title = value
                foundTitlePage = true
                index += 1
                continue
            }
            if let value = titlePageValue(trimmed, key: "author")
                ?? titlePageValue(trimmed, key: "authors") {
                author = value
                foundTitlePage = true
                index += 1
                continue
            }
            if foundTitlePage, trimmed.contains(":") {
                index += 1
                continue
            }
            break
        }

        var scenes: [ScriptWorkshopScene] = []
        var current: ScriptWorkshopScene?
        var pendingSynopsis = ""
        var previousKind: ScriptWorkshopBlockKind?
        var pendingKind: ScriptWorkshopBlockKind?
        var pendingExplicitPageBreak = false

        func finishScene() {
            guard var scene = current else { return }
            if scene.blocks.isEmpty {
                scene.blocks = [ScriptWorkshopBlock(kind: .action)]
            }
            scenes.append(scene)
            current = nil
            previousKind = nil
        }

        while index < lines.count {
            let raw = lines[index]
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            index += 1

            if trimmed.isEmpty {
                previousKind = nil
                continue
            }
            if trimmed.hasPrefix("#") { continue }
            if trimmed == "===" {
                pendingExplicitPageBreak = true
                previousKind = nil
                continue
            }
            if trimmed.hasPrefix("="), !trimmed.hasPrefix("===") {
                pendingSynopsis = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                continue
            }
            if trimmed.caseInsensitiveCompare(shotMarker) == .orderedSame {
                pendingKind = .shot
                previousKind = nil
                continue
            }
            if isSceneHeading(trimmed) {
                finishScene()
                let components = sceneHeadingComponents(trimmed)
                current = ScriptWorkshopScene(
                    heading: components.heading,
                    synopsis: pendingSynopsis,
                    blocks: [],
                    metadata: ScriptWorkshopSceneMetadata(
                        sceneNumber: components.sceneNumber ?? ""
                    )
                )
                pendingSynopsis = ""
                continue
            }

            if current == nil {
                current = ScriptWorkshopScene(
                    heading: "开场",
                    synopsis: pendingSynopsis,
                    blocks: []
                )
                pendingSynopsis = ""
            }

            let kind: ScriptWorkshopBlockKind
            let text: String
            let isDualDialogueCharacter = trimmed.hasSuffix("^")
            if let forcedKind = pendingKind {
                kind = forcedKind
                text = trimmed.hasPrefix("!") ? String(trimmed.dropFirst()) : trimmed
                pendingKind = nil
            } else if trimmed.hasPrefix("[["), trimmed.hasSuffix("]]") {
                kind = .note
                text = String(trimmed.dropFirst(2).dropLast(2))
            } else if trimmed.hasPrefix(">") || trimmed.uppercased().hasSuffix(" TO:") {
                kind = .transition
                text = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
            } else if (trimmed.hasPrefix("(") && trimmed.hasSuffix(")"))
                || (trimmed.hasPrefix("（") && trimmed.hasSuffix("）")) {
                kind = .parenthetical
                text = trimmed
            } else if previousKind == .character || previousKind == .parenthetical || previousKind == .dialogue {
                kind = .dialogue
                text = trimmed
            } else if trimmed.hasPrefix("@")
                || looksLikeCharacter(trimmed, nextLine: index < lines.count ? lines[index] : nil) {
                kind = .character
                text = trimmed
                    .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                    .replacingOccurrences(of: "^", with: "")
            } else {
                kind = .action
                text = trimmed.hasPrefix("!") ? String(trimmed.dropFirst()) : trimmed
            }

            if kind == .dialogue,
               !pendingExplicitPageBreak,
               current?.blocks.last?.kind == .dialogue,
               var last = current?.blocks.removeLast() {
                last.text += "\n\(text)"
                last.updatedAt = Date()
                current?.blocks.append(last)
            } else {
                current?.blocks.append(
                    ScriptWorkshopBlock(
                        kind: kind,
                        text: text,
                        metadata: ScriptWorkshopBlockMetadata(
                            dualDialogue: kind == .character && isDualDialogueCharacter,
                            explicitPageBreakBefore: pendingExplicitPageBreak
                        )
                    )
                )
            }
            pendingExplicitPageBreak = false
            previousKind = kind
        }
        finishScene()

        return ScriptWorkshopDocument(
            linkedProjectID: linkedProjectID,
            title: title,
            author: author,
            scenes: scenes.isEmpty ? [ScriptWorkshopScene()] : scenes
        )
    }

    static func render(_ document: ScriptWorkshopDocument) -> String {
        renderWithReport(document).source
    }

    static func renderWithReport(
        _ document: ScriptWorkshopDocument
    ) -> ScriptWorkshopFountainExportResult {
        var output: [String] = []
        var diagnostics: [ScriptWorkshopFountainDiagnostic] = []
        output.append("Title: \(document.title)")
        if !document.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output.append("Author: \(document.author)")
        }
        output.append("")

        for scene in document.scenes {
            if !scene.synopsis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                output.append("= \(scene.synopsis)")
                output.append("")
            }
            let sceneNumber = scene.metadata?.sceneNumber
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            output.append(
                fountainSceneHeading(scene.heading)
                    + (sceneNumber.isEmpty ? "" : " #\(sceneNumber)#")
            )
            output.append("")

            for (index, block) in scene.blocks.enumerated() {
                let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                if block.metadata?.explicitPageBreakBefore == true {
                    output.append("===")
                    output.append("")
                }
                switch block.kind {
                case .action:
                    output.append(trimmed.uppercased() == trimmed ? "!\(trimmed)" : trimmed)
                case .character:
                    output.append(
                        "@\(trimmed.uppercased())"
                            + (block.metadata?.dualDialogue == true ? "^" : "")
                    )
                case .dialogue, .parenthetical:
                    output.append(trimmed)
                case .transition:
                    output.append(">\(trimmed)")
                case .shot:
                    // Fountain has no native Shot element. A standard note plus
                    // forced action preserves the semantic type in 321Doit
                    // without accidentally turning the shot into a scene.
                    output.append(shotMarker)
                    output.append("!\(trimmed)")
                case .note:
                    output.append("[[\(trimmed)]]")
                }
                let nextKind = scene.blocks.dropFirst(index + 1)
                    .first { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?
                    .kind
                let continuesDialogue =
                    (block.kind == .character && (nextKind == .parenthetical || nextKind == .dialogue))
                    || (block.kind == .parenthetical && nextKind == .dialogue)
                if !continuesDialogue {
                    output.append("")
                }
            }
        }
        if !(document.workspace?.revisionSets.isEmpty ?? true) {
            diagnostics.append(.init(
                severity: .warning,
                code: "revision-history-sidecar-required",
                message: "Fountain does not carry the screenplay's production revision history."
            ))
        }
        if document.workspace?.sceneNumbersLocked == true {
            diagnostics.append(.init(
                severity: .warning,
                code: "page-locks-not-represented",
                message: "Fountain preserves scene labels but not locked production pagination."
            ))
        }
        if !(document.workspace?.boneyard.isEmpty ?? true) {
            diagnostics.append(.init(
                severity: .warning,
                code: "boneyard-not-represented",
                message: "The boneyard remains in the project and is not included in the Fountain file."
            ))
        }
        if !(document.workspace?.branches.isEmpty ?? true) {
            diagnostics.append(.init(
                severity: .warning,
                code: "branches-not-represented",
                message: "Writing branches remain in the project and are not included in the Fountain file."
            ))
        }
        return ScriptWorkshopFountainExportResult(
            source: output.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines) + "\n",
            diagnostics: diagnostics
        )
    }

    private static func titlePageValue(_ line: String, key: String) -> String? {
        let prefix = "\(key):"
        guard line.lowercased().hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func isSceneHeading(_ line: String) -> Bool {
        if line.hasPrefix("."), !line.hasPrefix("..") { return true }
        let upper = line.uppercased()
        return ["INT.", "EXT.", "INT/EXT.", "INT./EXT.", "I/E.", "EST."]
            .contains { upper.hasPrefix($0) }
    }

    private static func normalizedSceneHeading(_ line: String) -> String {
        if line.hasPrefix(".") { return String(line.dropFirst()) }
        return line
    }

    private static func sceneHeadingComponents(
        _ line: String
    ) -> (heading: String, sceneNumber: String?) {
        let normalized = normalizedSceneHeading(line)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = normalized.range(
            of: #"\s+#([^#\n]+)#\s*$"#,
            options: .regularExpression
        ) else {
            return (normalized, nil)
        }
        let suffix = String(normalized[range])
        let number = suffix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = String(normalized[..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (heading, number.isEmpty ? nil : number)
    }

    private static func looksLikeCharacter(_ line: String, nextLine: String?) -> Bool {
        guard line.count <= 64,
              line == line.uppercased(),
              line.rangeOfCharacter(from: .letters) != nil,
              let nextLine,
              !nextLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return !line.hasSuffix(".") && !line.hasSuffix("!")
    }

    private static func fountainSceneHeading(_ heading: String) -> String {
        let trimmed = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ".未命名场景" }
        if isSceneHeading(trimmed) { return trimmed.uppercased() }
        return ".\(trimmed)"
    }
}
