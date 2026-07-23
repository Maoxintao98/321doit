import Foundation
import SwiftUI

/// A small Markdown renderer that keeps block boundaries intact while relying
/// on AttributedString for inline Markdown such as bold text and links.
struct MiraRichText: View {
    private let blocks: [MiraMarkdownBlock]

    init(_ markdown: String) {
        blocks = MiraMarkdownBlock.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(blocks) { block in
                switch block.kind {
                case .paragraph:
                    Text(Self.inlineMarkdown(block.content))
                case .heading(let level):
                    Text(Self.inlineMarkdown(block.content))
                        .font(.system(size: level == 1 ? 18 : 15, weight: .semibold))
                case .list(let marker):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(marker)
                            .frame(minWidth: 16, alignment: .trailing)
                        Text(Self.inlineMarkdown(block.content))
                    }
                case .code:
                    Text(block.content)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color.black.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .textSelection(.enabled)
    }

    private static func inlineMarkdown(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options))
            ?? AttributedString(plainFallback(source))
    }

    private static func plainFallback(_ source: String) -> String {
        var output = source
        output = output.replacingOccurrences(of: "`", with: "")
        output = output.replacingOccurrences(of: "**", with: "")
        output = output.replacingOccurrences(of: "__", with: "")
        output = output.replacingOccurrences(of: "~~", with: "")
        output = output.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        return output
    }
}

private struct MiraMarkdownBlock: Identifiable {
    enum Kind {
        case paragraph
        case heading(Int)
        case list(String)
        case code
    }

    let id: Int
    let kind: Kind
    let content: String

    static func parse(_ markdown: String) -> [Self] {
        let lines = markdown.components(separatedBy: .newlines)
        var result: [Self] = []
        var index = 0

        func append(_ kind: Kind, _ content: String) {
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            result.append(Self(id: result.count, kind: kind, content: content))
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }
            if trimmed.hasPrefix("```") {
                index += 1
                var codeLines: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                append(.code, codeLines.joined(separator: "\n"))
                continue
            }
            if let heading = heading(in: trimmed) {
                append(.heading(heading.level), heading.text)
                index += 1
                continue
            }
            if let item = listItem(in: line) {
                append(.list(item.marker), item.text)
                index += 1
                continue
            }

            var paragraph = [line]
            index += 1
            while index < lines.count {
                let next = lines[index]
                let nextTrimmed = next.trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty || nextTrimmed.hasPrefix("```") || heading(in: nextTrimmed) != nil || listItem(in: next) != nil {
                    break
                }
                paragraph.append(next)
                index += 1
            }
            append(.paragraph, paragraph.joined(separator: "\n"))
        }
        return result.isEmpty ? [Self(id: 0, kind: .paragraph, content: markdown)] : result
    }

    private static func heading(in line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6,
              line.dropFirst(hashes.count).first == " " else { return nil }
        return (hashes.count, String(line.dropFirst(hashes.count + 1)))
    }

    private static func listItem(in line: String) -> (marker: String, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return ("•", String(trimmed.dropFirst(marker.count)))
        }
        let digits = trimmed.prefix { $0.isNumber }
        guard !digits.isEmpty,
              trimmed.dropFirst(digits.count).hasPrefix(". ") else { return nil }
        return ("\(digits).", String(trimmed.dropFirst(digits.count + 2)))
    }
}
