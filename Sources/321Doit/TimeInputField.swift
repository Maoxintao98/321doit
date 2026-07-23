import SwiftUI

enum TimeInputMode: Equatable {
    case clock
    case timecode(framesPerSecond: Int)

    var placeholder: String {
        switch self {
        case .clock:
            return "HH:mm"
        case .timecode:
            return "HH:mm:ss:ff"
        }
    }
}

struct TimeInputField: View {
    @Environment(\.themeColors) private var colors
    @Environment(\.toolAccentColor) private var toolAccentColor
    @Binding var text: String
    var placeholder: String?
    var mode: TimeInputMode = .clock

    @State private var isPickerPresented = false
    @State private var draftText = ""
    @State private var hour = 0
    @State private var minute = 0
    @State private var second = 0
    @State private var frame = 0
    @FocusState private var isFocused: Bool
    @FocusState private var isDraftFocused: Bool

    private var activeAccent: Color {
        toolAccentColor ?? colors.accent
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder ?? mode.placeholder, text: Binding(
                get: { text },
                set: { value in
                    text = value
                    syncSelection(from: value)
                }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13, design: .monospaced))
            .focused($isFocused)
            .padding(.horizontal, 8)
            .frame(minHeight: 26)
            .background(colors.inputBg)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isFocused ? activeAccent : colors.hairline,
                        lineWidth: isFocused ? 1.5 : 0.5
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Button {
                openPicker()
            } label: {
                Image(systemName: mode == .clock ? "clock" : "timer")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(activeAccent)
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .help("Open picker")
        }
        .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                TextField(placeholder ?? mode.placeholder, text: Binding(
                    get: { draftText },
                    set: { value in
                        draftText = value
                        text = value
                        syncSelection(from: value)
                    }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .focused($isDraftFocused)
                .padding(.horizontal, 8)
                .frame(minHeight: 26)
                .background(colors.inputBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            isDraftFocused ? activeAccent : colors.hairline,
                            lineWidth: isDraftFocused ? 1.5 : 0.5
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                HStack(spacing: 8) {
                    pickerColumn(range: 0...23, selection: $hour, suffix: nil)
                    separator
                    pickerColumn(range: 0...59, selection: $minute, suffix: nil)
                    if case .timecode(let fps) = mode {
                        separator
                        pickerColumn(range: 0...59, selection: $second, suffix: nil)
                        separator
                        pickerColumn(range: 0...max(0, fps - 1), selection: $frame, suffix: nil)
                    }
                }
                .frame(height: 174)
            }
            .padding(12)
            .frame(width: mode == .clock ? 190 : 330)
            .background(colors.panelBg)
            .tint(activeAccent)
            .accentColor(activeAccent)
            .onAppear {
                isDraftFocused = true
            }
        }
    }

    private var separator: some View {
        Text(":")
            .font(.system(size: 19, weight: .semibold, design: .monospaced))
            .foregroundStyle(colors.textSecondary)
            .frame(width: 10)
    }

    private func pickerColumn(range: ClosedRange<Int>, selection: Binding<Int>, suffix: String?) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(range), id: \.self) { value in
                        Button {
                            selection.wrappedValue = value
                            commitSelection()
                        } label: {
                            Text(display(value, selected: value == selection.wrappedValue, suffix: suffix))
                                .font(.system(size: 17, weight: value == selection.wrappedValue ? .semibold : .regular, design: .monospaced))
                                .foregroundStyle(value == selection.wrappedValue ? activeAccent : colors.textPrimary)
                                .frame(width: 52, height: 28)
                                .contentShape(Rectangle())
                        }
                        .id(value)
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 72)
            }
            .frame(width: 56)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(colors.hairline, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onAppear {
                proxy.scrollTo(selection.wrappedValue, anchor: .center)
            }
            .onChange(of: selection.wrappedValue) { value in
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(value, anchor: .center)
                }
            }
        }
    }

    private func display(_ value: Int, selected: Bool, suffix: String?) -> String {
        let base = String(format: "%02d", value)
        let withSuffix = suffix.map { "\(base)\($0)" } ?? base
        return selected ? "[\(withSuffix)]" : withSuffix
    }

    private func openPicker() {
        draftText = text
        syncSelection(from: text)
        isPickerPresented = true
    }

    private func syncSelection(from value: String) {
        let parsed = Self.parse(value, mode: mode)
        guard let parsed else { return }
        hour = parsed.hour
        minute = parsed.minute
        second = parsed.second
        frame = parsed.frame
    }

    private func commitSelection() {
        let formatted = Self.format(hour: hour, minute: minute, second: second, frame: frame, mode: mode)
        draftText = formatted
        text = formatted
    }

    private static func parse(_ value: String, mode: TimeInputMode) -> (hour: Int, minute: Int, second: Int, frame: Int)? {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "：", with: ":")
        guard !cleaned.isEmpty else { return nil }

        if cleaned.contains(":") {
            let parts = cleaned.split(separator: ":", omittingEmptySubsequences: false)
            switch mode {
            case .clock:
                guard parts.count >= 2,
                      let hour = Int(parts[0]),
                      let minute = Int(parts[1]),
                      valid(hour: hour, minute: minute)
                else { return nil }
                return (hour, minute, 0, 0)
            case .timecode(let fps):
                guard parts.count >= 2,
                      let hour = Int(parts[0]),
                      let minute = Int(parts[1])
                else { return nil }
                let second = parts.count > 2 ? (Int(parts[2]) ?? 0) : 0
                let frame = parts.count > 3 ? (Int(parts[3]) ?? 0) : 0
                guard valid(hour: hour, minute: minute, second: second, frame: frame, fps: fps) else { return nil }
                return (hour, minute, second, frame)
            }
        }

        guard cleaned.allSatisfy(\.isNumber) else { return nil }
        switch mode {
        case .clock:
            let padded = cleaned.count <= 2 ? cleaned : String(cleaned.suffix(4))
            if padded.count <= 2, let hour = Int(padded), valid(hour: hour, minute: 0) {
                return (hour, 0, 0, 0)
            }
            let split = padded.index(padded.endIndex, offsetBy: -2)
            guard let hour = Int(padded[..<split]), let minute = Int(padded[split...]), valid(hour: hour, minute: minute) else { return nil }
            return (hour, minute, 0, 0)
        case .timecode(let fps):
            let padded = String(repeating: "0", count: max(0, 8 - cleaned.count)) + String(cleaned.suffix(8))
            let hEnd = padded.index(padded.startIndex, offsetBy: 2)
            let mEnd = padded.index(hEnd, offsetBy: 2)
            let sEnd = padded.index(mEnd, offsetBy: 2)
            guard let hour = Int(padded[..<hEnd]),
                  let minute = Int(padded[hEnd..<mEnd]),
                  let second = Int(padded[mEnd..<sEnd]),
                  let frame = Int(padded[sEnd...]),
                  valid(hour: hour, minute: minute, second: second, frame: frame, fps: fps)
            else { return nil }
            return (hour, minute, second, frame)
        }
    }

    private static func format(hour: Int, minute: Int, second: Int, frame: Int, mode: TimeInputMode) -> String {
        switch mode {
        case .clock:
            return String(format: "%02d:%02d", hour, minute)
        case .timecode:
            return String(format: "%02d:%02d:%02d:%02d", hour, minute, second, frame)
        }
    }

    private static func valid(hour: Int, minute: Int, second: Int = 0, frame: Int = 0, fps: Int = 25) -> Bool {
        (0...23).contains(hour)
            && (0...59).contains(minute)
            && (0...59).contains(second)
            && (0...max(0, fps - 1)).contains(frame)
    }
}
