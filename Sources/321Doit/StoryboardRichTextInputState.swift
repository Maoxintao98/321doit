import AppKit

enum StoryboardRichTextMetrics {
    static let editorParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.5
        return style
    }()
}

/// NSTextView does not emit `textDidChange` while an input method is still
/// composing marked text. Surface that visual content state explicitly so the
/// placeholder cannot overlap Pinyin, Kana, or other IME composition text.
final class StoryboardRichNSTextView: NSTextView {
    var contentStateChanged: ((Bool) -> Void)?

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        super.setMarkedText(
            string,
            selectedRange: selectedRange,
            replacementRange: replacementRange
        )
        notifyContentState()
    }

    override func unmarkText() {
        super.unmarkText()
        notifyContentState()
    }

    override func didChangeText() {
        super.didChangeText()
        notifyContentState()
    }

    private func notifyContentState() {
        let isEmpty = string.isEmpty && !hasMarkedText()
        needsDisplay = true
        contentStateChanged?(isEmpty)
    }
}
