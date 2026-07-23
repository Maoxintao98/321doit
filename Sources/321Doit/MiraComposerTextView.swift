import AppKit
import SwiftUI

struct MiraComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = MiraSubmitTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = { [weak coordinator = context.coordinator] submittedText in
            coordinator?.submit(submittedText)
        }
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 5, height: 7)
        textView.minSize = NSSize(width: 0, height: 44)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.setAccessibilityIdentifier("mira.composer")
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? MiraSubmitTextView else { return }
        textView.onSubmit = { [weak coordinator = context.coordinator] submittedText in
            coordinator?.submit(submittedText)
        }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MiraComposerTextView

        init(parent: MiraComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func submit(_ submittedText: String) {
            parent.text = submittedText
            parent.onSubmit(submittedText)
        }
    }
}

private final class MiraSubmitTextView: NSTextView {
    var onSubmit: ((String) -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let wantsNewline = event.modifierFlags.contains(.shift)

        // Let the input method commit Chinese/Japanese/Korean composition first.
        if isReturn, !wantsNewline, !hasMarkedText() {
            onSubmit?(string)
            return
        }
        super.keyDown(with: event)
    }
}
