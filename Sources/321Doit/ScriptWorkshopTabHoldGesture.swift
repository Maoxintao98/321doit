import Foundation

/// Pure key-state logic kept separate from AppKit so short/long Tab behavior can
/// be exercised deterministically without synthesizing keyboard events.
struct ScriptWorkshopTabHoldGesture: Equatable {
    static let holdDuration: TimeInterval = 0.42

    enum Phase: Equatable {
        case idle
        case pending
        case wheel
    }

    enum KeyDownDisposition: Equatable {
        case passThrough
        case armHold
        case consume
        case cancelWheelAndConsume
    }

    enum HoldDisposition: Equatable {
        case none
        case beginWheel
    }

    enum KeyUpDisposition: Equatable {
        case passThrough
        case shortPress
        case endWheel
        case consume
        case cancelWheelAndConsume
    }

    private(set) var phase: Phase = .idle

    mutating func keyDown(
        isRepeat: Bool,
        hasMarkedText: Bool
    ) -> KeyDownDisposition {
        if hasMarkedText {
            let wasShowingWheel = phase == .wheel
            phase = .idle
            return wasShowingWheel ? .cancelWheelAndConsume : .consume
        }
        if isRepeat {
            return .consume
        }
        switch phase {
        case .idle:
            phase = .pending
            return .armHold
        case .pending, .wheel:
            return .consume
        }
    }

    mutating func holdThresholdReached(hasMarkedText: Bool) -> HoldDisposition {
        guard phase == .pending, !hasMarkedText else {
            if hasMarkedText {
                phase = .idle
            }
            return .none
        }
        phase = .wheel
        return .beginWheel
    }

    mutating func keyUp(hasMarkedText: Bool) -> KeyUpDisposition {
        if hasMarkedText {
            let wasShowingWheel = phase == .wheel
            phase = .idle
            return wasShowingWheel ? .cancelWheelAndConsume : .consume
        }
        switch phase {
        case .idle:
            return .passThrough
        case .pending:
            phase = .idle
            return .shortPress
        case .wheel:
            phase = .idle
            return .endWheel
        }
    }

    /// Returns true only when a visible wheel needs a cancellation event.
    mutating func cancel() -> Bool {
        let wasShowingWheel = phase == .wheel
        phase = .idle
        return wasShowingWheel
    }
}

enum ScriptWorkshopCaretPolicy {
    /// Programmatic content inserted into the focused empty block (for example
    /// by the character sub-wheel) owns the caret and places it after the new
    /// text. Ordinary external updates preserve the writer's current location.
    static func locationAfterExternalUpdate(
        previousText: String,
        newText: String,
        currentUTF16Location: Int,
        isFocused: Bool
    ) -> Int {
        let previousWasEmpty = previousText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        let newHasText = !newText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        if isFocused, previousWasEmpty, newHasText {
            return newText.utf16.count
        }
        return min(max(0, currentUTF16Location), newText.utf16.count)
    }
}
