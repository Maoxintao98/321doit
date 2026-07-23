import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - JSON coders (kept byte-compatible with the macOS app)

extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var prettyISO: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

// MARK: - Document type

extension UTType {
    static let scriptLog = UTType(exportedAs: "com.321doit.scriptlog")
}

// MARK: - Export payload
//
// `.321log` file. It is a *superset* of the macOS app's `ScriptLogDocument`
// (projectID / shootingDays / updatedAt), so the Mac side can decode it either
// as a full `ScripterExportDocument` (to recover the project name) or, with the
// extra keys ignored, straight into its existing `ScriptLogDocument`.
struct ScripterExportDocument: Codable, Equatable {
    var schemaVersion: Int
    var app: String
    var appVersion: String
    var projectID: UUID
    var projectName: String
    var shootingDays: [ShootingDay]
    var updatedAt: Date
    var exportedAt: Date

    init(
        schemaVersion: Int = 1,
        app: String = "321Doit Scripter (iPad)",
        appVersion: String = AppInfo.version,
        projectID: UUID,
        projectName: String,
        shootingDays: [ShootingDay],
        updatedAt: Date = Date(),
        exportedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.app = app
        self.appVersion = appVersion
        self.projectID = projectID
        self.projectName = projectName
        self.shootingDays = shootingDays
        self.updatedAt = updatedAt
        self.exportedAt = exportedAt
    }
}

enum AppInfo {
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - Camera configuration (project-level)
//
// Replaces the per-shot "cameraSetup" field. The project declares how many
// cameras are on set, each with its current card and a starting clip/material
// number. New takes auto-fill each camera's clip number (previous + 1).
struct ScripterCamera: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var label: String          // display name, e.g. "A机" / "Cam A"
    var cardName: String       // current card number, e.g. "A001"
    var startClip: String      // first clip/material number, e.g. "A0001"

    init(id: UUID = UUID(), label: String, cardName: String = "", startClip: String = "") {
        self.id = id
        self.label = label
        self.cardName = cardName
        self.startClip = startClip
    }

    /// Default camera set: one A camera. The project panel lets the user add more.
    static func defaults(language: AppLanguage) -> [ScripterCamera] {
        [ScripterCamera(label: L10n.t("A机", "Cam A", language: language),
                        cardName: "A001", startClip: "A0001")]
    }
}

enum ClipNumber {
    /// Increments the trailing number in a clip id, preserving its zero-padding
    /// and any non-numeric prefix. "A0001" → "A0002", "C12" → "C13", "" → "".
    static func next(after clip: String) -> String {
        guard !clip.isEmpty else { return "" }
        let chars = Array(clip)
        var split = chars.count            // index where the trailing digit run starts
        while split > 0, chars[split - 1].isNumber { split -= 1 }
        let prefix = String(chars[..<split])
        let digits = String(chars[split...])
        guard !digits.isEmpty, let value = Int(digits) else {
            return clip + "1"              // no trailing digits → append "1"
        }
        let padded = String(format: "%0\(digits.count)d", value + 1)
        return prefix + padded
    }
}

// MARK: - Light theme

struct Palette {
    let accent = Color.orange
    let okColor = Color.green
    let ngColor = Color.red
    let kpColor = Color.yellow
    let circle = Color.orange
    var background: Color { Color(uiColor: .systemGroupedBackground) }
    var card: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    var field: Color { Color(uiColor: .tertiarySystemFill) }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette()
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension TakeStatus {
    func tint(_ p: Palette) -> Color {
        switch self {
        case .unset: return .gray
        case .good: return p.okColor
        case .ng: return p.ngColor
        case .hold: return p.kpColor
        case .reset: return .gray
        case .wildTrack: return .blue
        case .rehearsal: return .purple
        }
    }
}
