import AppKit
import SwiftUI

/// A compact, non-scrolling Markdown preview used by Living Storyboard cells.
/// Editing happens in a rich-text sheet, while the project file continues to
/// store portable Markdown source.
struct StoryboardMarkdownField: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors

    @Binding var text: String
    let editorTitle: String
    var placeholder: String? = nil
    var isSelected = false
    var fontSize: CGFloat = 10
    var minimumHeight: CGFloat = 44

    @State private var isEditorPresented = false
    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private var resolvedPlaceholder: String { placeholder ?? L10n.t("请输入文本", "Enter text", language: lang) }

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(isSelected ? ToolAccent.storyboard.primary.opacity(0.06) : colors.inputBg.opacity(0.78))
            .overlay(alignment: .topLeading) {
                Group {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(resolvedPlaceholder).foregroundStyle(colors.textTertiary)
                    } else {
                        Text(renderedText).foregroundStyle(colors.textPrimary)
                    }
                }
                .font(.system(size: fontSize))
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
                .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isSelected ? ToolAccent.storyboard.primary.opacity(0.72) : colors.hairline.opacity(0.95),
                        lineWidth: isSelected ? 1.2 : 1
                    )
            }
            .frame(minHeight: minimumHeight)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onTapGesture(count: 2) { isEditorPresented = true }
            .help(L10n.t("双击打开编辑器", "Double-click to edit", language: lang))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(editorTitle)
            .accessibilityValue(text.isEmpty ? resolvedPlaceholder : text)
            .accessibilityHint(L10n.t("双击打开编辑器", "Double-click to edit", language: lang))
            .sheet(isPresented: $isEditorPresented) {
                StoryboardMarkdownEditor(
                    title: editorTitle,
                    initialMarkdown: text,
                    save: { text = $0 }
                )
            }
    }

    private var renderedText: AttributedString {
        StoryboardMarkdownRendering.attributedString(from: text)
    }
}

private struct StoryboardMarkdownEditor: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors

    let title: String
    let save: (String) -> Void

    @State private var richText: NSAttributedString
    @StateObject private var formatController = StoryboardRichTextFormatController()
    private var lang: AppLanguage { settings.settings.general.language.resolved }

    init(title: String, initialMarkdown: String, save: @escaping (String) -> Void) {
        self.title = title
        self.save = save
        _richText = State(initialValue: StoryboardMarkdownCodec.attributedString(from: initialMarkdown))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .padding(16)

            Divider()

            richTextToolbar
            Divider()

            StoryboardRichTextView(
                attributedText: $richText,
                controller: formatController
            )
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(colors.inputBg.opacity(0.52))

            Divider()

            HStack {
                Spacer()
                Button(L10n.t("取消", "Cancel", language: lang)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.t("应用", "Apply", language: lang)) {
                    save(StoryboardMarkdownCodec.markdown(from: richText))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(minWidth: 660, idealWidth: 760, minHeight: 460, idealHeight: 560)
        .background(colors.panelBg)
    }

    private var richTextToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                formatButton(.bold, systemImage: "bold", help: L10n.t("加粗（⌘B）", "Bold (⌘B)", language: lang), shortcut: "b")
                formatButton(.italic, systemImage: "italic", help: L10n.t("斜体（⌘I）", "Italic (⌘I)", language: lang), shortcut: "i")
                formatButton(.strikethrough, systemImage: "strikethrough", help: L10n.t("删除线（⇧⌘X）", "Strikethrough (⇧⌘X)", language: lang), shortcut: "x", modifiers: [.command, .shift])
                formatButton(.code, systemImage: "chevron.left.forwardslash.chevron.right", help: L10n.t("行内代码", "Inline Code", language: lang))

                Divider().frame(height: 22).padding(.horizontal, 2)

                formatButton(.heading, systemImage: "textformat.size", help: L10n.t("标题", "Heading", language: lang))
                formatButton(.bulletList, systemImage: "list.bullet", help: L10n.t("无序列表", "Bulleted List", language: lang))
                formatButton(.numberedList, systemImage: "list.number", help: L10n.t("有序列表", "Numbered List", language: lang))
                formatButton(.quote, systemImage: "text.quote", help: L10n.t("引用", "Quote", language: lang))
                formatButton(.link, systemImage: "link", help: L10n.t("链接", "Link", language: lang))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func formatButton(
        _ style: StoryboardRichTextStyle,
        systemImage: String,
        help: String,
        shortcut: Character? = nil,
        modifiers: EventModifiers = .command
    ) -> some View {
        let button = Button {
            formatController.toggle(style)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 24)
                .foregroundStyle(formatController.activeStyles.contains(style) ? Color.white : ToolAccent.storyboard.primary)
                .background(
                    formatController.activeStyles.contains(style)
                        ? ToolAccent.storyboard.primary
                        : ToolAccent.storyboard.primary.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)

        if let shortcut {
            button.keyboardShortcut(KeyEquivalent(shortcut), modifiers: modifiers)
        } else {
            button
        }
    }

}

private enum StoryboardRichTextStyle: String, Hashable {
    case bold
    case italic
    case strikethrough
    case code
    case heading
    case bulletList
    case numberedList
    case quote
    case link
}

private extension NSAttributedString.Key {
    static let storyboardCode = NSAttributedString.Key("com.321doit.storyboard.markdown.code")
    static let storyboardBlock = NSAttributedString.Key("com.321doit.storyboard.markdown.block")
}

@MainActor
private final class StoryboardRichTextFormatController: ObservableObject {
    @Published private(set) var activeStyles = Set<StoryboardRichTextStyle>()

    private weak var textView: NSTextView?
    private var changed: ((NSAttributedString) -> Void)?

    func attach(_ textView: NSTextView, changed: @escaping (NSAttributedString) -> Void) {
        let isNewTextView = self.textView !== textView
        self.textView = textView
        self.changed = changed
        if isNewTextView {
            DispatchQueue.main.async { [weak self] in
                self?.refreshActiveStyles()
            }
        }
    }

    func toggle(_ style: StoryboardRichTextStyle) {
        guard let textView else { return }
        switch style {
        case .bold:
            toggleFontTrait(.boldFontMask, style: style, in: textView)
        case .italic:
            toggleFontTrait(.italicFontMask, style: style, in: textView)
        case .strikethrough:
            toggleAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, style: style, in: textView)
        case .code:
            toggleCode(in: textView)
        case .link:
            toggleAttribute(.link, value: URL(string: "https://example.com")!, style: style, in: textView)
        case .heading, .bulletList, .numberedList, .quote:
            toggleBlock(style, in: textView)
        }
        changed?(textView.attributedString())
        refreshActiveStyles()
        textView.window?.makeFirstResponder(textView)
    }

    func refreshActiveStyles() {
        guard let textView else { return }
        let attributes = effectiveAttributes(in: textView)
        var next = Set<StoryboardRichTextStyle>()
        let font = attributes[.font] as? NSFont ?? StoryboardMarkdownCodec.baseFont
        let traits = NSFontManager.shared.traits(of: font)
        if traits.contains(.boldFontMask) { next.insert(.bold) }
        if traits.contains(.italicFontMask) { next.insert(.italic) }
        if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { next.insert(.strikethrough) }
        if attributes[.storyboardCode] != nil { next.insert(.code) }
        if attributes[.link] != nil { next.insert(.link) }
        if let raw = attributes[.storyboardBlock] as? String,
           let block = StoryboardRichTextStyle(rawValue: raw) {
            next.insert(block)
        }
        // updateNSView re-attaches the controller. Publishing an unchanged set
        // here would immediately schedule another SwiftUI update and could
        // create a tight main-thread render loop as the editor opens.
        if next != activeStyles {
            activeStyles = next
        }
    }

    private func effectiveAttributes(in textView: NSTextView) -> [NSAttributedString.Key: Any] {
        let range = textView.selectedRange()
        if range.length == 0 {
            return textView.typingAttributes
        }
        guard textView.textStorage?.length ?? 0 > 0 else { return textView.typingAttributes }
        return textView.textStorage?.attributes(at: min(range.location, (textView.textStorage?.length ?? 1) - 1), effectiveRange: nil) ?? [:]
    }

    private func toggleFontTrait(
        _ trait: NSFontTraitMask,
        style: StoryboardRichTextStyle,
        in textView: NSTextView
    ) {
        let enable = !activeStyles.contains(style)
        let range = textView.selectedRange()
        if range.length == 0 {
            var attributes = textView.typingAttributes
            let font = attributes[.font] as? NSFont ?? StoryboardMarkdownCodec.baseFont
            attributes[.font] = converted(font: font, trait: trait, enable: enable)
            textView.typingAttributes = attributes
            return
        }

        guard let storage = textView.textStorage else { return }
        var fonts: [(NSRange, NSFont)] = []
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            fonts.append((subrange, value as? NSFont ?? StoryboardMarkdownCodec.baseFont))
        }
        storage.beginEditing()
        for (subrange, font) in fonts {
            storage.addAttribute(.font, value: converted(font: font, trait: trait, enable: enable), range: subrange)
        }
        storage.endEditing()
    }

    private func converted(font: NSFont, trait: NSFontTraitMask, enable: Bool) -> NSFont {
        enable
            ? NSFontManager.shared.convert(font, toHaveTrait: trait)
            : NSFontManager.shared.convert(font, toNotHaveTrait: trait)
    }

    private func toggleAttribute(
        _ key: NSAttributedString.Key,
        value: Any,
        style: StoryboardRichTextStyle,
        in textView: NSTextView
    ) {
        let enable = !activeStyles.contains(style)
        let range = textView.selectedRange()
        if range.length == 0 {
            var attributes = textView.typingAttributes
            if enable { attributes[key] = value } else { attributes.removeValue(forKey: key) }
            textView.typingAttributes = attributes
            return
        }
        if enable {
            textView.textStorage?.addAttribute(key, value: value, range: range)
        } else {
            textView.textStorage?.removeAttribute(key, range: range)
        }
    }

    private func toggleCode(in textView: NSTextView) {
        let enable = !activeStyles.contains(.code)
        let range = textView.selectedRange()
        if range.length == 0 {
            var attributes = textView.typingAttributes
            if enable {
                attributes[.storyboardCode] = true
                attributes[.font] = StoryboardMarkdownCodec.codeFont
                attributes[.backgroundColor] = NSColor.secondaryLabelColor.withAlphaComponent(0.10)
            } else {
                attributes.removeValue(forKey: .storyboardCode)
                attributes.removeValue(forKey: .backgroundColor)
                attributes[.font] = StoryboardMarkdownCodec.baseFont
            }
            textView.typingAttributes = attributes
            return
        }
        if enable {
            textView.textStorage?.addAttributes([
                .storyboardCode: true,
                .font: StoryboardMarkdownCodec.codeFont,
                .backgroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.10)
            ], range: range)
        } else {
            textView.textStorage?.removeAttribute(.storyboardCode, range: range)
            textView.textStorage?.removeAttribute(.backgroundColor, range: range)
            textView.textStorage?.addAttribute(.font, value: StoryboardMarkdownCodec.baseFont, range: range)
        }
    }

    private func toggleBlock(_ style: StoryboardRichTextStyle, in textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let source = storage.string as NSString
        let selected = textView.selectedRange()
        let paragraphRange = source.lineRange(for: selected)
        let enable = !activeStyles.contains(style)

        storage.beginEditing()
        storage.removeAttribute(.storyboardBlock, range: paragraphRange)
        if style == .heading {
            storage.addAttribute(
                .font,
                value: enable ? NSFont.systemFont(ofSize: 20, weight: .bold) : StoryboardMarkdownCodec.baseFont,
                range: paragraphRange
            )
        }
        if enable {
            storage.addAttribute(.storyboardBlock, value: style.rawValue, range: paragraphRange)
        }
        storage.endEditing()

        var attributes = textView.typingAttributes
        if enable { attributes[.storyboardBlock] = style.rawValue }
        else { attributes.removeValue(forKey: .storyboardBlock) }
        if style == .heading {
            attributes[.font] = enable ? NSFont.systemFont(ofSize: 20, weight: .bold) : StoryboardMarkdownCodec.baseFont
        }
        textView.typingAttributes = attributes
    }
}

private struct StoryboardRichTextView: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @ObservedObject var controller: StoryboardRichTextFormatController

    func makeCoordinator() -> Coordinator {
        Coordinator(attributedText: $attributedText, controller: controller)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = StoryboardTextViewFactory.scrollView()
        let textView = StoryboardRichNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(attributedText)
        textView.font = StoryboardMarkdownCodec.baseFont
        textView.defaultParagraphStyle = StoryboardRichTextMetrics.editorParagraphStyle
        textView.typingAttributes = [
            .font: StoryboardMarkdownCodec.baseFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: StoryboardRichTextMetrics.editorParagraphStyle
        ]
        scrollView.documentView = textView
        controller.attach(textView) { next in attributedText = next }
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? StoryboardRichNSTextView else { return }
        controller.attach(textView) { next in attributedText = next }
        if !textView.attributedString().isEqual(to: attributedText) {
            let selection = textView.selectedRange()
            textView.textStorage?.setAttributedString(attributedText)
            textView.setSelectedRange(NSRange(location: min(selection.location, attributedText.length), length: 0))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var attributedText: NSAttributedString
        private let controller: StoryboardRichTextFormatController

        init(attributedText: Binding<NSAttributedString>, controller: StoryboardRichTextFormatController) {
            _attributedText = attributedText
            self.controller = controller
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            attributedText = textView.attributedString()
            controller.refreshActiveStyles()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            controller.refreshActiveStyles()
        }
    }
}

private struct StoryboardMarkdownSourceView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, selection: $selection) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = StoryboardTextViewFactory.scrollView()
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        scrollView.documentView = textView
        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
        let maximum = (textView.string as NSString).length
        let location = min(max(selection.location, 0), maximum)
        let length = min(max(selection.length, 0), maximum - location)
        let nextSelection = NSRange(location: location, length: length)
        if textView.selectedRange() != nextSelection { textView.setSelectedRange(nextSelection) }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var selection: NSRange

        init(text: Binding<String>, selection: Binding<NSRange>) {
            _text = text
            _selection = selection
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            selection = textView.selectedRange()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            selection = textView.selectedRange()
        }
    }
}

private enum StoryboardTextViewFactory {
    static func scrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        return scrollView
    }
}

private enum StoryboardMarkdownCodec {
    static let baseFont = NSFont.systemFont(ofSize: 15)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: baseFont,
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: StoryboardRichTextMetrics.editorParagraphStyle
    ]

    static func attributedString(from markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let lines = markdown.components(separatedBy: "\n")
        for (index, rawLine) in lines.enumerated() {
            let (block, content) = blockAndContent(for: rawLine)
            let start = result.length
            appendInline(content, to: result)
            let contentRange = NSRange(location: start, length: result.length - start)
            if let block, contentRange.length > 0 {
                result.addAttribute(.storyboardBlock, value: block.rawValue, range: contentRange)
                if block == .heading {
                    result.addAttribute(.font, value: NSFont.systemFont(ofSize: 20, weight: .bold), range: contentRange)
                }
            }
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
        }
        return result
    }

    static func markdown(from attributed: NSAttributedString) -> String {
        guard attributed.length > 0 else { return "" }
        let source = attributed.string as NSString
        var output: [String] = []
        var location = 0
        while location < source.length {
            let lineRange = source.lineRange(for: NSRange(location: location, length: 0))
            var contentRange = lineRange
            while contentRange.length > 0 {
                let finalCharacter = source.substring(with: NSRange(location: NSMaxRange(contentRange) - 1, length: 1))
                if finalCharacter == "\n" || finalCharacter == "\r" { contentRange.length -= 1 }
                else { break }
            }
            let block = blockStyle(in: attributed, range: contentRange)
            output.append(blockPrefix(block) + inlineMarkdown(from: attributed, range: contentRange))
            location = NSMaxRange(lineRange)
        }
        if source.hasSuffix("\n") { output.append("") }
        return output.joined(separator: "\n")
    }

    private static func blockAndContent(for line: String) -> (StoryboardRichTextStyle?, String) {
        if line.hasPrefix("## ") { return (.heading, String(line.dropFirst(3))) }
        if line.hasPrefix("- ") { return (.bulletList, String(line.dropFirst(2))) }
        if line.hasPrefix("> ") { return (.quote, String(line.dropFirst(2))) }
        if let match = line.range(of: #"^[0-9]+\. "#, options: .regularExpression) {
            return (.numberedList, String(line[match.upperBound...]))
        }
        return (nil, line)
    }

    private static func appendInline(_ source: String, to result: NSMutableAttributedString) {
        guard !source.isEmpty else { return }
        guard let token = firstToken(in: source) else {
            result.append(NSAttributedString(string: source, attributes: baseAttributes))
            return
        }

        let before = String(source[..<token.fullRange.lowerBound])
        if !before.isEmpty { result.append(NSAttributedString(string: before, attributes: baseAttributes)) }
        let start = result.length
        if token.style == .code {
            result.append(NSAttributedString(string: token.content, attributes: baseAttributes))
        } else {
            appendInline(token.content, to: result)
        }
        let range = NSRange(location: start, length: result.length - start)
        apply(token.style, url: token.url, to: result, range: range)
        appendInline(String(source[token.fullRange.upperBound...]), to: result)
    }

    private struct InlineToken {
        let fullRange: Range<String.Index>
        let content: String
        let style: StoryboardRichTextStyle
        let url: String?
    }

    private static func firstToken(in source: String) -> InlineToken? {
        var candidates: [InlineToken] = []
        addMatch(#"\[([^\]]+)\]\(([^)]+)\)"#, style: .link, in: source, candidates: &candidates, urlGroup: 2)
        addMatch(#"\*\*(.+?)\*\*"#, style: .bold, in: source, candidates: &candidates)
        addMatch(#"~~(.+?)~~"#, style: .strikethrough, in: source, candidates: &candidates)
        addMatch(#"`([^`]+)`"#, style: .code, in: source, candidates: &candidates)
        addMatch(#"(?<!\*)\*([^*]+)\*(?!\*)"#, style: .italic, in: source, candidates: &candidates)
        return candidates.min { lhs, rhs in
            source.distance(from: source.startIndex, to: lhs.fullRange.lowerBound)
                < source.distance(from: source.startIndex, to: rhs.fullRange.lowerBound)
        }
    }

    private static func addMatch(
        _ pattern: String,
        style: StoryboardRichTextStyle,
        in source: String,
        candidates: inout [InlineToken],
        urlGroup: Int? = nil
    ) {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let fullRange = Range(match.range(at: 0), in: source),
              let contentRange = Range(match.range(at: 1), in: source) else { return }
        let url = urlGroup.flatMap { group -> String? in
            guard let range = Range(match.range(at: group), in: source) else { return nil }
            return String(source[range])
        }
        candidates.append(InlineToken(fullRange: fullRange, content: String(source[contentRange]), style: style, url: url))
    }

    private static func apply(
        _ style: StoryboardRichTextStyle,
        url: String?,
        to result: NSMutableAttributedString,
        range: NSRange
    ) {
        guard range.length > 0 else { return }
        switch style {
        case .bold:
            convertFonts(in: result, range: range, trait: .boldFontMask)
        case .italic:
            convertFonts(in: result, range: range, trait: .italicFontMask)
        case .strikethrough:
            result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        case .code:
            result.addAttributes([
                .storyboardCode: true,
                .font: codeFont,
                .backgroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.10)
            ], range: range)
        case .link:
            if let url, let destination = URL(string: url) {
                result.addAttribute(.link, value: destination, range: range)
            }
        case .heading, .bulletList, .numberedList, .quote:
            break
        }
    }

    private static func convertFonts(in result: NSMutableAttributedString, range: NSRange, trait: NSFontTraitMask) {
        var fonts: [(NSRange, NSFont)] = []
        result.enumerateAttribute(.font, in: range) { value, subrange, _ in
            fonts.append((subrange, value as? NSFont ?? baseFont))
        }
        for (subrange, font) in fonts {
            result.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: subrange)
        }
    }

    private static func blockStyle(in attributed: NSAttributedString, range: NSRange) -> StoryboardRichTextStyle? {
        guard range.location < attributed.length,
              let raw = attributed.attribute(.storyboardBlock, at: range.location, effectiveRange: nil) as? String else { return nil }
        return StoryboardRichTextStyle(rawValue: raw)
    }

    private static func blockPrefix(_ block: StoryboardRichTextStyle?) -> String {
        switch block {
        case .heading: return "## "
        case .bulletList: return "- "
        case .numberedList: return "1. "
        case .quote: return "> "
        default: return ""
        }
    }

    private static func inlineMarkdown(from attributed: NSAttributedString, range: NSRange) -> String {
        guard range.length > 0 else { return "" }
        var output = ""
        attributed.enumerateAttributes(in: range) { attributes, subrange, _ in
            let content = (attributed.string as NSString).substring(with: subrange)
            if attributes[.storyboardCode] != nil {
                output += "`\(content)`"
                return
            }

            var prefix = ""
            var suffix = ""
            let font = attributes[.font] as? NSFont ?? baseFont
            let traits = NSFontManager.shared.traits(of: font)
            if traits.contains(.boldFontMask) { prefix += "**"; suffix = "**" + suffix }
            if traits.contains(.italicFontMask) { prefix += "*"; suffix = "*" + suffix }
            if (attributes[.strikethroughStyle] as? Int ?? 0) != 0 { prefix += "~~"; suffix = "~~" + suffix }
            if let link = attributes[.link] as? URL {
                output += "[\(prefix)\(content)\(suffix)](\(link.absoluteString))"
            } else {
                output += prefix + content + suffix
            }
        }
        return output
    }
}
