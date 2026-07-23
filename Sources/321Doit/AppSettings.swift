import AppKit
import Foundation
import Security
import SwiftUI

// MARK: - Top-level container

struct AppSettings: Codable, Equatable {
    var version: Int = 1
    var general: GeneralSettings = .init()
    var projectTemplate: ProjectTemplateSettings = .init()
    var copyVerify: CopyVerifySettings = .init()
    var checksum: ChecksumSettings = .init()
    var report: ReportSettings = .init()
    var transcode: TranscodeSettings = .init()
    var lut: LUTSettings = .init()
    var safety: StorageSafetySettings = .init()
    var performance: PerformanceSettings = .init()
    var notification: NotificationSettings = .init()
    var logs: LogSettings = .init()
    var update: UpdateSettings = .init()
    var handoff: HandoffSettings = .init()
    var shortcuts: ScriptLogShortcutSettings = .init()
    /// Whether the welcome modal has been confirmed at least once.
    var welcomeAcknowledged: Bool = false
    /// Whether the user has opted to skip the welcome modal on launch.
    var skipWelcomeOnLaunch: Bool = false

    private enum CodingKeys: String, CodingKey {
        case version, general, projectTemplate, copyVerify, checksum, report, transcode, lut
        case safety, performance, notification, logs, update, handoff, shortcuts
        case welcomeAcknowledged, skipWelcomeOnLaunch
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        general = try c.decodeIfPresent(GeneralSettings.self, forKey: .general) ?? .init()
        // Legacy palette choices are no longer exposed after the UI redesign.
        // Normalize old preference files to the single current visual system.
        general.theme = .defaultTheme
        projectTemplate = try c.decodeIfPresent(ProjectTemplateSettings.self, forKey: .projectTemplate) ?? .init()
        copyVerify = try c.decodeIfPresent(CopyVerifySettings.self, forKey: .copyVerify) ?? .init()
        checksum = try c.decodeIfPresent(ChecksumSettings.self, forKey: .checksum) ?? .init()
        report = try c.decodeIfPresent(ReportSettings.self, forKey: .report) ?? .init()
        transcode = try c.decodeIfPresent(TranscodeSettings.self, forKey: .transcode) ?? .init()
        lut = try c.decodeIfPresent(LUTSettings.self, forKey: .lut) ?? .init()
        safety = try c.decodeIfPresent(StorageSafetySettings.self, forKey: .safety) ?? .init()
        performance = try c.decodeIfPresent(PerformanceSettings.self, forKey: .performance) ?? .init()
        notification = try c.decodeIfPresent(NotificationSettings.self, forKey: .notification) ?? .init()
        logs = try c.decodeIfPresent(LogSettings.self, forKey: .logs) ?? .init()
        update = try c.decodeIfPresent(UpdateSettings.self, forKey: .update) ?? .init()
        handoff = try c.decodeIfPresent(HandoffSettings.self, forKey: .handoff) ?? .init()
        shortcuts = try c.decodeIfPresent(ScriptLogShortcutSettings.self, forKey: .shortcuts) ?? .init()
        welcomeAcknowledged = try c.decodeIfPresent(Bool.self, forKey: .welcomeAcknowledged) ?? false
        skipWelcomeOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .skipWelcomeOnLaunch) ?? false
    }
}

// MARK: - Script Log shortcuts

enum ShortcutKey: String, Codable, CaseIterable, Identifiable {
    case returnKey = "return"
    case leftArrow = "leftArrow"
    case rightArrow = "rightArrow"
    case upArrow = "upArrow"
    case downArrow = "downArrow"
    case zero = "0"
    case one = "1"
    case two = "2"
    case three = "3"
    case four = "4"
    case five = "5"
    case six = "6"
    case seven = "7"
    case eight = "8"
    case nine = "9"
    case a = "a"
    case b = "b"
    case c = "c"
    case d = "d"
    case e = "e"
    case f = "f"
    case g = "g"
    case h = "h"
    case i = "i"
    case j = "j"
    case k = "k"
    case l = "l"
    case m = "m"
    case n = "n"
    case o = "o"
    case p = "p"
    case q = "q"
    case r = "r"
    case s = "s"
    case t = "t"
    case u = "u"
    case v = "v"
    case w = "w"
    case x = "x"
    case y = "y"
    case z = "z"

    var id: String { rawValue }

    var keyEquivalent: KeyEquivalent {
        switch self {
        case .returnKey:
            return .return
        case .leftArrow:
            return .leftArrow
        case .rightArrow:
            return .rightArrow
        case .upArrow:
            return .upArrow
        case .downArrow:
            return .downArrow
        default:
            return KeyEquivalent(Character(rawValue))
        }
    }

    var label: String {
        switch self {
        case .returnKey: return "Enter"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        default: return rawValue.uppercased()
        }
    }
}

struct ShortcutCommand: Codable, Equatable {
    var key: ShortcutKey
    var command: Bool
    var shift: Bool
    var option: Bool
    var control: Bool

    init(
        key: ShortcutKey,
        command: Bool = false,
        shift: Bool = false,
        option: Bool = false,
        control: Bool = false
    ) {
        self.key = key
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }

    var modifiers: EventModifiers {
        var result = EventModifiers()
        if command { result.insert(.command) }
        if shift { result.insert(.shift) }
        if option { result.insert(.option) }
        if control { result.insert(.control) }
        return result
    }

    var displayName: String {
        var parts: [String] = []
        if control { parts.append("Control") }
        if option { parts.append("Option") }
        if shift { parts.append("Shift") }
        if command { parts.append("Command") }
        parts.append(key.label)
        return parts.joined(separator: " + ")
    }
}

enum ScriptLogShortcutAction: String, CaseIterable, Identifiable {
    case nextTake
    case nextShot
    case nextScene
    case markOK
    case markKP
    case markNG
    case circleTake
    case faultEvent
    case undo

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .nextTake: return L10n.t("新建下一条", "Next Take", language: language)
        case .nextShot: return L10n.t("新建下一镜", "Next Shot", language: language)
        case .nextScene: return L10n.t("新建下一场", "Next Scene", language: language)
        case .markOK: return L10n.t("标记 OK", "Mark OK", language: language)
        case .markKP: return L10n.t("标记 KP", "Mark KP", language: language)
        case .markNG: return L10n.t("标记 NG", "Mark NG", language: language)
        case .circleTake: return L10n.t("开/关优选条", "Toggle Circle Take", language: language)
        case .faultEvent: return L10n.t("故障条", "Fault Event", language: language)
        case .undo: return L10n.t("撤回", "Undo", language: language)
        }
    }
}

struct ScriptLogShortcutSettings: Codable, Equatable {
    var nextTake = ShortcutCommand(key: .returnKey)
    var nextShot = ShortcutCommand(key: .returnKey, shift: true)
    var nextScene = ShortcutCommand(key: .returnKey, command: true)
    var markOK = ShortcutCommand(key: .one)
    var markKP = ShortcutCommand(key: .two)
    var markNG = ShortcutCommand(key: .three)
    var circleTake = ShortcutCommand(key: .four)
    var faultEvent = ShortcutCommand(key: .five)
    var undo = ShortcutCommand(key: .z, command: true)

    subscript(action: ScriptLogShortcutAction) -> ShortcutCommand {
        get {
            switch action {
            case .nextTake: return nextTake
            case .nextShot: return nextShot
            case .nextScene: return nextScene
            case .markOK: return markOK
            case .markKP: return markKP
            case .markNG: return markNG
            case .circleTake: return circleTake
            case .faultEvent: return faultEvent
            case .undo: return undo
            }
        }
        set {
            switch action {
            case .nextTake: nextTake = newValue
            case .nextShot: nextShot = newValue
            case .nextScene: nextScene = newValue
            case .markOK: markOK = newValue
            case .markKP: markKP = newValue
            case .markNG: markNG = newValue
            case .circleTake: circleTake = newValue
            case .faultEvent: faultEvent = newValue
            case .undo: undo = newValue
            }
        }
    }
}

// MARK: - General

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: (String, String) {
        switch self {
        case .system: return ("跟随系统", "System")
        case .light:  return ("浅色", "Light")
        case .dark:   return ("深色", "Dark")
        }
    }
}

enum TimeFormat: String, Codable, CaseIterable, Identifiable {
    case hour24, hour12
    var id: String { rawValue }
    var label: (String, String) {
        switch self {
        case .hour24: return ("24 小时制", "24-hour")
        case .hour12: return ("12 小时制", "12-hour")
        }
    }
}

enum CapacityUnit: String, Codable, CaseIterable, Identifiable {
    case decimal // GB (1000-based)
    case binary  // GiB (1024-based)
    var id: String { rawValue }
    var label: (String, String) {
        switch self {
        case .decimal: return ("GB (1000)", "GB (decimal)")
        case .binary:  return ("GiB (1024)", "GiB (binary)")
        }
    }
}

struct ThemeColors: Equatable {
    // Logo / brand mark colors
    let inkTop: Color
    let inkBottom: Color
    let accent: Color
    let accentDeep: Color
    let warm: Color

    // Full-page UI surface colors
    let surfaceBg: Color       // main window background
    let panelBg: Color         // side panels, log header, card bg
    let inputBg: Color         // text field / path row background
    let hairline: Color        // borders, separators
    let sectionHeader: Color   // section title / label color
    let progressBarBg: Color   // inactive progress bar track

    // Text colors
    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    // Semantic state colors
    let stateSuccess: Color
    let stateFail: Color
    let stateRunning: Color
    let stateWarning: Color
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case defaultTheme
    case cinemaParadisk
    case grandBudaPaste
    case raidRunner2049
    case pulpFriction
    case chunkingExpress
    case noSpaceOdyssey

    var id: String { rawValue }

    var label: (String, String) {
        switch self {
        case .defaultTheme:    return ("默认", "Default")
        case .cinemaParadisk:  return ("天堂电疗院", "Cinema Paradisk")
        case .grandBudaPaste:  return ("布达拉宫的陈佩斯大饭店", "The Grand BudaPaste Hotel")
        case .raidRunner2049:  return ("仁义杀手2049", "RAID Runner 2049")
        case .pulpFriction:    return ("低速小说", "Pulp Friction")
        case .chunkingExpress: return ("重启森林", "Chunking Express")
        case .noSpaceOdyssey:  return ("盗梦空间不足", "2001: No Space Odyssey")
        }
    }

    func colors(isDark: Bool) -> ThemeColors {
        switch self {
        case .defaultTheme:
            // Dynamic warm tone: deep amber on light backgrounds (the previous
            // pale yellow was washed out on white), bright amber on dark.
            let warmDynamic = Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark
                    ? NSColor(red: 1.00, green: 0.74, blue: 0.30, alpha: 1.0)
                    : NSColor(red: 0.84, green: 0.50, blue: 0.06, alpha: 1.0)
            })
            return ThemeColors(
                inkTop:       Color(red: 0.10, green: 0.13, blue: 0.18),
                inkBottom:    Color(red: 0.04, green: 0.06, blue: 0.10),
                accent:       Color.blue,
                accentDeep:   Color.blue.opacity(0.85),
                warm:         warmDynamic,
                surfaceBg:    Color(nsColor: .windowBackgroundColor),
                panelBg:      Color(nsColor: .controlBackgroundColor),
                inputBg:      Color(nsColor: .textBackgroundColor),
                hairline:     Color(nsColor: .separatorColor),
                sectionHeader: Color.secondary,
                progressBarBg: Color.primary.opacity(0.07),
                textPrimary:   Color.primary,
                textSecondary: Color.secondary,
                textTertiary:  Color.secondary.opacity(0.6),
                stateSuccess: Color(red: 0.20, green: 0.70, blue: 0.40),
                stateFail:    Color(red: 0.85, green: 0.30, blue: 0.30),
                stateRunning: Color.blue,
                stateWarning: Color.orange
            )

        case .cinemaParadisk:
            if isDark {
                return ThemeColors(
                    inkTop: Color(red: 0.25, green: 0.18, blue: 0.12),
                    inkBottom: Color(red: 0.15, green: 0.10, blue: 0.05),
                    accent: Color(red: 0.85, green: 0.52, blue: 0.22),
                    accentDeep: Color(red: 0.72, green: 0.38, blue: 0.12),
                    warm: Color(red: 0.90, green: 0.78, blue: 0.42),
                    surfaceBg: Color(red: 0.16, green: 0.14, blue: 0.11),
                    panelBg: Color(red: 0.22, green: 0.18, blue: 0.14),
                    inputBg: Color(red: 0.28, green: 0.23, blue: 0.18),
                    hairline: Color(red: 0.45, green: 0.38, blue: 0.32).opacity(0.4),
                    sectionHeader: Color(red: 0.75, green: 0.65, blue: 0.50),
                    progressBarBg: Color(red: 0.85, green: 0.52, blue: 0.22).opacity(0.15),
                    textPrimary: Color(red: 0.96, green: 0.94, blue: 0.90),
                    textSecondary: Color(red: 0.85, green: 0.80, blue: 0.75),
                    textTertiary: Color(red: 0.65, green: 0.60, blue: 0.55),
                    stateSuccess: Color(red: 0.55, green: 0.68, blue: 0.40),
                    stateFail: Color(red: 0.85, green: 0.35, blue: 0.25),
                    stateRunning: Color(red: 0.85, green: 0.52, blue: 0.22),
                    stateWarning: Color(red: 0.92, green: 0.75, blue: 0.35)
                )
            } else {
                return ThemeColors(
                    inkTop: Color(red: 0.98, green: 0.92, blue: 0.85),
                    inkBottom: Color(red: 0.94, green: 0.85, blue: 0.75),
                    accent: Color(red: 0.82, green: 0.45, blue: 0.15),
                    accentDeep: Color(red: 0.65, green: 0.32, blue: 0.10),
                    warm: Color(red: 0.75, green: 0.62, blue: 0.35),
                    surfaceBg: Color(red: 0.98, green: 0.96, blue: 0.92),
                    panelBg: Color(red: 0.94, green: 0.90, blue: 0.85),
                    inputBg: Color.white,
                    hairline: Color(red: 0.80, green: 0.70, blue: 0.60).opacity(0.3),
                    sectionHeader: Color(red: 0.55, green: 0.45, blue: 0.35),
                    progressBarBg: Color(red: 0.82, green: 0.45, blue: 0.15).opacity(0.1),
                    textPrimary: Color(red: 0.25, green: 0.18, blue: 0.12),
                    textSecondary: Color(red: 0.45, green: 0.38, blue: 0.32),
                    textTertiary: Color(red: 0.65, green: 0.58, blue: 0.52),
                    stateSuccess: Color(red: 0.45, green: 0.58, blue: 0.30),
                    stateFail: Color(red: 0.75, green: 0.25, blue: 0.15),
                    stateRunning: Color(red: 0.82, green: 0.45, blue: 0.15),
                    stateWarning: Color(red: 0.85, green: 0.65, blue: 0.25)
                )
            }

        case .grandBudaPaste:
            if isDark {
                return ThemeColors(
                    inkTop: Color(red: 0.22, green: 0.14, blue: 0.18),
                    inkBottom: Color(red: 0.12, green: 0.08, blue: 0.10),
                    accent: Color(red: 0.92, green: 0.65, blue: 0.75),
                    accentDeep: Color(red: 0.75, green: 0.35, blue: 0.48),
                    warm: Color(red: 0.92, green: 0.85, blue: 0.65),
                    surfaceBg: Color(red: 0.18, green: 0.14, blue: 0.16),
                    panelBg: Color(red: 0.24, green: 0.18, blue: 0.21),
                    inputBg: Color(red: 0.30, green: 0.23, blue: 0.27),
                    hairline: Color(red: 0.50, green: 0.38, blue: 0.45).opacity(0.4),
                    sectionHeader: Color(red: 0.85, green: 0.70, blue: 0.78),
                    progressBarBg: Color(red: 0.92, green: 0.65, blue: 0.75).opacity(0.15),
                    textPrimary: Color(red: 0.98, green: 0.94, blue: 0.96),
                    textSecondary: Color(red: 0.88, green: 0.80, blue: 0.85),
                    textTertiary: Color(red: 0.70, green: 0.60, blue: 0.65),
                    stateSuccess: Color(red: 0.55, green: 0.75, blue: 0.58),
                    stateFail: Color(red: 0.88, green: 0.40, blue: 0.45),
                    stateRunning: Color(red: 0.92, green: 0.65, blue: 0.75),
                    stateWarning: Color(red: 0.95, green: 0.80, blue: 0.50)
                )
            } else {
                return ThemeColors(
                    inkTop: Color(red: 0.99, green: 0.95, blue: 0.96), // 极浅粉（趋于白色）
                    inkBottom: Color(red: 0.96, green: 0.88, blue: 0.90),
                    accent: Color(red: 0.85, green: 0.25, blue: 0.50), // 强调色改为更正的粉红
                    accentDeep: Color(red: 0.65, green: 0.15, blue: 0.35),
                    warm: Color(red: 0.82, green: 0.55, blue: 0.20), // 金黄色改为深金橙，增加对比
                    surfaceBg: Color(red: 1.00, green: 0.96, blue: 0.98),
                    panelBg: Color(red: 0.98, green: 0.92, blue: 0.94),
                    inputBg: Color.white,
                    hairline: Color(red: 0.85, green: 0.75, blue: 0.80).opacity(0.3),
                    sectionHeader: Color(red: 0.65, green: 0.35, blue: 0.45),
                    progressBarBg: Color(red: 0.85, green: 0.25, blue: 0.50).opacity(0.1),
                    textPrimary: Color(red: 0.28, green: 0.12, blue: 0.18),
                    textSecondary: Color(red: 0.45, green: 0.25, blue: 0.32),
                    textTertiary: Color(red: 0.65, green: 0.45, blue: 0.50),
                    stateSuccess: Color(red: 0.35, green: 0.60, blue: 0.40),
                    stateFail: Color(red: 0.80, green: 0.20, blue: 0.25),
                    stateRunning: Color(red: 0.85, green: 0.25, blue: 0.50),
                    stateWarning: Color(red: 0.85, green: 0.55, blue: 0.20)
                )
            }

        case .raidRunner2049:
            if isDark {
                return ThemeColors(
                    inkTop: Color(red: 0.15, green: 0.15, blue: 0.18),
                    inkBottom: Color(red: 0.08, green: 0.08, blue: 0.10),
                    accent: Color(red: 1.00, green: 0.62, blue: 0.18),
                    accentDeep: Color(red: 0.85, green: 0.45, blue: 0.10),
                    warm: Color(red: 0.55, green: 0.72, blue: 0.88),
                    surfaceBg: Color(red: 0.11, green: 0.11, blue: 0.14),
                    panelBg: Color(red: 0.16, green: 0.16, blue: 0.19),
                    inputBg: Color(red: 0.22, green: 0.22, blue: 0.25),
                    hairline: Color(red: 0.35, green: 0.35, blue: 0.40).opacity(0.5),
                    sectionHeader: Color(red: 0.60, green: 0.65, blue: 0.75),
                    progressBarBg: Color(red: 1.00, green: 0.62, blue: 0.18).opacity(0.15),
                    textPrimary: Color(red: 0.94, green: 0.95, blue: 0.98),
                    textSecondary: Color(red: 0.80, green: 0.82, blue: 0.88),
                    textTertiary: Color(red: 0.60, green: 0.62, blue: 0.68),
                    stateSuccess: Color(red: 0.55, green: 0.72, blue: 0.88),
                    stateFail: Color(red: 0.95, green: 0.35, blue: 0.25),
                    stateRunning: Color(red: 1.00, green: 0.62, blue: 0.18),
                    stateWarning: Color(red: 1.00, green: 0.75, blue: 0.25)
                )
            } else {
                return ThemeColors(
                    inkTop: Color(red: 0.85, green: 0.86, blue: 0.90),
                    inkBottom: Color(red: 0.75, green: 0.76, blue: 0.82),
                    accent: Color(red: 0.95, green: 0.50, blue: 0.00),
                    accentDeep: Color(red: 0.75, green: 0.35, blue: 0.00),
                    warm: Color(red: 0.35, green: 0.55, blue: 0.75),
                    surfaceBg: Color(red: 0.92, green: 0.93, blue: 0.95),
                    panelBg: Color(red: 0.85, green: 0.86, blue: 0.88),
                    inputBg: Color.white,
                    hairline: Color(red: 0.70, green: 0.72, blue: 0.75).opacity(0.3),
                    sectionHeader: Color(red: 0.40, green: 0.45, blue: 0.55),
                    progressBarBg: Color(red: 0.95, green: 0.50, blue: 0.00).opacity(0.1),
                    textPrimary: Color(red: 0.10, green: 0.12, blue: 0.18),
                    textSecondary: Color(red: 0.35, green: 0.38, blue: 0.45),
                    textTertiary: Color(red: 0.55, green: 0.58, blue: 0.65),
                    stateSuccess: Color(red: 0.30, green: 0.50, blue: 0.70),
                    stateFail: Color(red: 0.80, green: 0.20, blue: 0.15),
                    stateRunning: Color(red: 0.95, green: 0.50, blue: 0.00),
                    stateWarning: Color(red: 0.95, green: 0.65, blue: 0.15)
                )
            }

        case .pulpFriction:
            if isDark {
                return ThemeColors(
                    inkTop: Color(red: 0.18, green: 0.15, blue: 0.12),
                    inkBottom: Color(red: 0.10, green: 0.08, blue: 0.05),
                    accent: Color(red: 0.95, green: 0.82, blue: 0.35),
                    accentDeep: Color(red: 0.80, green: 0.65, blue: 0.20),
                    warm: Color(red: 0.85, green: 0.32, blue: 0.25),
                    surfaceBg: Color(red: 0.12, green: 0.10, blue: 0.09),
                    panelBg: Color(red: 0.18, green: 0.15, blue: 0.13),
                    inputBg: Color(red: 0.24, green: 0.21, blue: 0.18),
                    hairline: Color(red: 0.42, green: 0.36, blue: 0.30).opacity(0.5),
                    sectionHeader: Color(red: 0.80, green: 0.72, blue: 0.60),
                    progressBarBg: Color(red: 0.95, green: 0.82, blue: 0.35).opacity(0.15),
                    textPrimary: Color(red: 0.96, green: 0.92, blue: 0.85),
                    textSecondary: Color(red: 0.85, green: 0.80, blue: 0.72),
                    textTertiary: Color(red: 0.65, green: 0.60, blue: 0.55),
                    stateSuccess: Color(red: 0.60, green: 0.75, blue: 0.40),
                    stateFail: Color(red: 0.85, green: 0.32, blue: 0.25),
                    stateRunning: Color(red: 0.95, green: 0.82, blue: 0.35),
                    stateWarning: Color(red: 0.98, green: 0.65, blue: 0.20)
                )
            } else {
                return ThemeColors(
                    inkTop: Color(red: 0.95, green: 0.90, blue: 0.80),
                    inkBottom: Color(red: 0.90, green: 0.82, blue: 0.70),
                    accent: Color(red: 0.75, green: 0.55, blue: 0.10),
                    accentDeep: Color(red: 0.55, green: 0.40, blue: 0.05),
                    warm: Color(red: 0.80, green: 0.25, blue: 0.15),
                    surfaceBg: Color(red: 0.98, green: 0.95, blue: 0.88),
                    panelBg: Color(red: 0.94, green: 0.90, blue: 0.82),
                    inputBg: Color.white,
                    hairline: Color(red: 0.75, green: 0.65, blue: 0.55).opacity(0.3),
                    sectionHeader: Color(red: 0.50, green: 0.42, blue: 0.35),
                    progressBarBg: Color(red: 0.75, green: 0.55, blue: 0.10).opacity(0.1),
                    textPrimary: Color(red: 0.18, green: 0.15, blue: 0.12),
                    textSecondary: Color(red: 0.40, green: 0.35, blue: 0.30),
                    textTertiary: Color(red: 0.60, green: 0.55, blue: 0.50),
                    stateSuccess: Color(red: 0.40, green: 0.60, blue: 0.25),
                    stateFail: Color(red: 0.75, green: 0.20, blue: 0.15),
                    stateRunning: Color(red: 0.75, green: 0.55, blue: 0.10),
                    stateWarning: Color(red: 0.85, green: 0.45, blue: 0.10)
                )
            }

        case .chunkingExpress:
            if isDark {
                return ThemeColors(
                    inkTop: Color(red: 0.10, green: 0.15, blue: 0.22),
                    inkBottom: Color(red: 0.05, green: 0.08, blue: 0.12),
                    accent: Color(red: 0.25, green: 0.95, blue: 0.62),
                    accentDeep: Color(red: 0.15, green: 0.72, blue: 0.48),
                    warm: Color(red: 0.98, green: 0.88, blue: 0.38),
                    surfaceBg: Color(red: 0.08, green: 0.11, blue: 0.16),
                    panelBg: Color(red: 0.12, green: 0.16, blue: 0.22),
                    inputBg: Color(red: 0.18, green: 0.22, blue: 0.30),
                    hairline: Color(red: 0.30, green: 0.40, blue: 0.55).opacity(0.4),
                    sectionHeader: Color(red: 0.50, green: 0.75, blue: 0.85),
                    progressBarBg: Color(red: 0.25, green: 0.95, blue: 0.62).opacity(0.15),
                    textPrimary: Color(red: 0.92, green: 0.96, blue: 1.00),
                    textSecondary: Color(red: 0.78, green: 0.88, blue: 0.95),
                    textTertiary: Color(red: 0.55, green: 0.65, blue: 0.75),
                    stateSuccess: Color(red: 0.30, green: 0.90, blue: 0.60),
                    stateFail: Color(red: 0.92, green: 0.35, blue: 0.40),
                    stateRunning: Color(red: 0.25, green: 0.95, blue: 0.62),
                    stateWarning: Color(red: 0.98, green: 0.88, blue: 0.38)
                )
            } else {
                return ThemeColors(
                    inkTop: Color(red: 0.85, green: 0.92, blue: 0.98),
                    inkBottom: Color(red: 0.75, green: 0.85, blue: 0.92),
                    accent: Color(red: 0.10, green: 0.75, blue: 0.45),
                    accentDeep: Color(red: 0.05, green: 0.55, blue: 0.35),
                    warm: Color(red: 0.85, green: 0.72, blue: 0.10),
                    surfaceBg: Color(red: 0.94, green: 0.98, blue: 1.00),
                    panelBg: Color(red: 0.88, green: 0.94, blue: 0.98),
                    inputBg: Color.white,
                    hairline: Color(red: 0.70, green: 0.80, blue: 0.90).opacity(0.3),
                    sectionHeader: Color(red: 0.35, green: 0.55, blue: 0.65),
                    progressBarBg: Color(red: 0.10, green: 0.75, blue: 0.45).opacity(0.1),
                    textPrimary: Color(red: 0.08, green: 0.18, blue: 0.25),
                    textSecondary: Color(red: 0.30, green: 0.45, blue: 0.55),
                    textTertiary: Color(red: 0.50, green: 0.65, blue: 0.75),
                    stateSuccess: Color(red: 0.20, green: 0.70, blue: 0.40),
                    stateFail: Color(red: 0.80, green: 0.25, blue: 0.30),
                    stateRunning: Color(red: 0.10, green: 0.75, blue: 0.45),
                    stateWarning: Color(red: 0.85, green: 0.65, blue: 0.10)
                )
            }

        case .noSpaceOdyssey:
            if isDark {
                return ThemeColors(
                    inkTop: Color(red: 0.15, green: 0.16, blue: 0.18),
                    inkBottom: Color(red: 0.08, green: 0.09, blue: 0.10),
                    accent: Color(red: 0.60, green: 0.75, blue: 0.90),
                    accentDeep: Color(red: 0.40, green: 0.55, blue: 0.72),
                    warm: Color(red: 1.00, green: 0.65, blue: 0.15),
                    surfaceBg: Color(red: 0.10, green: 0.11, blue: 0.13),
                    panelBg: Color(red: 0.15, green: 0.16, blue: 0.18),
                    inputBg: Color(red: 0.20, green: 0.21, blue: 0.23),
                    hairline: Color(red: 0.35, green: 0.36, blue: 0.38).opacity(0.6),
                    sectionHeader: Color(red: 0.60, green: 0.65, blue: 0.70),
                    progressBarBg: Color(red: 0.60, green: 0.75, blue: 0.90).opacity(0.15),
                    textPrimary: Color(red: 0.96, green: 0.97, blue: 0.98),
                    textSecondary: Color(red: 0.80, green: 0.82, blue: 0.85),
                    textTertiary: Color(red: 0.60, green: 0.62, blue: 0.65),
                    stateSuccess: Color(red: 0.45, green: 0.78, blue: 0.58),
                    stateFail: Color(red: 0.92, green: 0.35, blue: 0.32),
                    stateRunning: Color(red: 0.60, green: 0.75, blue: 0.90),
                    stateWarning: Color(red: 1.00, green: 0.65, blue: 0.15)
                )
            } else {
                return ThemeColors(
                    inkTop: Color(red: 0.95, green: 0.96, blue: 0.98),
                    inkBottom: Color(red: 0.90, green: 0.91, blue: 0.93),
                    accent: Color(red: 0.35, green: 0.55, blue: 0.75),
                    accentDeep: Color(red: 0.20, green: 0.40, blue: 0.60),
                    warm: Color(red: 0.95, green: 0.55, blue: 0.10),
                    surfaceBg: Color(red: 0.98, green: 0.98, blue: 1.00),
                    panelBg: Color(red: 0.95, green: 0.95, blue: 0.97),
                    inputBg: Color.white,
                    hairline: Color(red: 0.80, green: 0.82, blue: 0.85).opacity(0.3),
                    sectionHeader: Color(red: 0.50, green: 0.52, blue: 0.55),
                    progressBarBg: Color(red: 0.35, green: 0.55, blue: 0.75).opacity(0.1),
                    textPrimary: Color(red: 0.12, green: 0.14, blue: 0.16),
                    textSecondary: Color(red: 0.40, green: 0.42, blue: 0.45),
                    textTertiary: Color(red: 0.60, green: 0.62, blue: 0.65),
                    stateSuccess: Color(red: 0.35, green: 0.65, blue: 0.45),
                    stateFail: Color(red: 0.80, green: 0.25, blue: 0.20),
                    stateRunning: Color(red: 0.35, green: 0.55, blue: 0.75),
                    stateWarning: Color(red: 0.95, green: 0.55, blue: 0.10)
                )
            }
        }
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .defaultTheme
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
    
    var themeColors: ThemeColors {
        self.appTheme.colors(isDark: self.colorScheme == .dark)
    }
}

struct GeneralSettings: Codable, Equatable {
    /// Default to following the OS language. Falls through to English when the
    /// system isn't Chinese, otherwise Chinese — see AppLanguage.resolved.
    var language: AppLanguage = .system
    var appearance: AppearanceMode = .system
    var theme: AppTheme = .defaultTheme
    var timeFormat: TimeFormat = .hour24
    var capacityUnit: CapacityUnit = .decimal
    var defaultProjectRoot: String = ""
    var defaultReportFolder: String = ""
    var defaultProxyFolder: String = ""
    var restoreLastProjectOnLaunch: Bool = true
    var autoScanExternalDrivesOnLaunch: Bool = false
    var showAdvancedFeatures: Bool = false
    var showContactSupportEntry: Bool = true
    var showProjectManagerCapabilities: Bool = true
    var customQuickTags: [String] = []
}

// MARK: - Project template

enum ShootDayFormat: String, Codable, CaseIterable, Identifiable {
    case longDayN     // Day 01
    case shortDayN    // D01
    case isoDate      // 2025-05-01
    var id: String { rawValue }
    var label: (String, String) {
        switch self {
        case .longDayN:  return ("Day 01", "Day 01")
        case .shortDayN: return ("D01", "D01")
        case .isoDate:   return ("2025-05-01", "2025-05-01")
        }
    }
}

struct ProjectTemplateSettings: Codable, Equatable {
    var defaultProjectName: String = ""
    var projectCode: String = ""
    var productionCompany: String = ""
    var directorOfPhotography: String = ""
    var ditName: String = ""
    var defaultCameraModel: String = ""
    var defaultCameraIDs: [String] = ["A_CAM", "B_CAM", "C_CAM"]
    var shootDayFormat: ShootDayFormat = .shortDayN
    var rollNamingRule: String = "{Card}"
    /// Folder template. Variables: {Project} {ProjectCode} {ShootDay} {Camera} {Card} {Date} {Operator}
    var folderTemplate: String = "{Project}_{Date}_{Card}"
}

// MARK: - Copy & Verify

enum ExistingFilePolicy: String, Codable, CaseIterable, Identifiable {
    case neverOverwrite
    case skipIdentical
    case errorAndStop
    case promptUser
    var id: String { rawValue }
    var label: (String, String) {
        switch self {
        case .neverOverwrite: return ("永不覆盖", "Never overwrite")
        case .skipIdentical:  return ("跳过相同文件", "Skip identical files")
        case .errorAndStop:   return ("报错并停止", "Error and stop")
        case .promptUser:     return ("手动确认", "Prompt user")
        }
    }
}

struct CopyVerifySettings: Codable, Equatable {
    var defaultTargetCount: Int = 2
    var enforceCapacityCheck: Bool = true
    var detectTargetFilesystem: Bool = true
    var allowCopyToSystemDisk: Bool = false   // DANGER
    var allowSourceTargetSameVolume: Bool = false // DANGER
    var copyHiddenFiles: Bool = false
    var preserveTimestamps: Bool = true
    var preservePermissions: Bool = true
    var preserveFolderStructure: Bool = true
    var existingFilePolicy: ExistingFilePolicy = .neverOverwrite
    var autoDetectMountedSource: Bool = true
    var autoIncrementReel: Bool = true
    var reelPrefix: String = "A"
    var reelDigits: Int = 3
    var defaultOutputPackageModes: [OffloadPackageMode] = [.safeCopy]
    var strictResume: Bool = true
    var ioRetryCount: Int = 3

    init() {}

    private enum CodingKeys: String, CodingKey {
        case defaultTargetCount
        case enforceCapacityCheck
        case detectTargetFilesystem
        case allowCopyToSystemDisk
        case allowSourceTargetSameVolume
        case copyHiddenFiles
        case preserveTimestamps
        case preservePermissions
        case preserveFolderStructure
        case existingFilePolicy
        case autoDetectMountedSource
        case autoIncrementReel
        case reelPrefix
        case reelDigits
        case defaultOutputPackageModes
        case strictResume
        case ioRetryCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultTargetCount = try c.decodeIfPresent(Int.self, forKey: .defaultTargetCount) ?? 2
        enforceCapacityCheck = try c.decodeIfPresent(Bool.self, forKey: .enforceCapacityCheck) ?? true
        detectTargetFilesystem = try c.decodeIfPresent(Bool.self, forKey: .detectTargetFilesystem) ?? true
        allowCopyToSystemDisk = try c.decodeIfPresent(Bool.self, forKey: .allowCopyToSystemDisk) ?? false
        allowSourceTargetSameVolume = try c.decodeIfPresent(Bool.self, forKey: .allowSourceTargetSameVolume) ?? false
        copyHiddenFiles = try c.decodeIfPresent(Bool.self, forKey: .copyHiddenFiles) ?? false
        preserveTimestamps = try c.decodeIfPresent(Bool.self, forKey: .preserveTimestamps) ?? true
        preservePermissions = try c.decodeIfPresent(Bool.self, forKey: .preservePermissions) ?? true
        preserveFolderStructure = try c.decodeIfPresent(Bool.self, forKey: .preserveFolderStructure) ?? true
        existingFilePolicy = try c.decodeIfPresent(ExistingFilePolicy.self, forKey: .existingFilePolicy) ?? .neverOverwrite
        autoDetectMountedSource = try c.decodeIfPresent(Bool.self, forKey: .autoDetectMountedSource) ?? true
        autoIncrementReel = try c.decodeIfPresent(Bool.self, forKey: .autoIncrementReel) ?? true
        reelPrefix = try c.decodeIfPresent(String.self, forKey: .reelPrefix) ?? "A"
        reelDigits = try c.decodeIfPresent(Int.self, forKey: .reelDigits) ?? 3
        defaultOutputPackageModes = try c.decodeIfPresent([OffloadPackageMode].self, forKey: .defaultOutputPackageModes) ?? [.safeCopy]
        strictResume = try c.decodeIfPresent(Bool.self, forKey: .strictResume) ?? true
        ioRetryCount = try c.decodeIfPresent(Int.self, forKey: .ioRetryCount) ?? 3
    }
}

struct ChecksumSettings: Codable, Equatable {
    var algorithm: ChecksumAlgorithm = .xxhash64
    var xxHash64Implementation: XXHash64Implementation = .automatic
    var dualStageVerification: Bool = true   // source-on-read + target-readback
    var retryOnFailure: Int = 0
    var continueOtherTargetsOnFailure: Bool = true
    var writeSidecarChecksum: Bool = true
    var generateAscMHL: Bool = true
    var generateCSVLog: Bool = true
    var generateJSONLog: Bool = true
    var includeFullHashesInReport: Bool = true
    var recordEnvironmentInReport: Bool = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case algorithm
        case xxHash64Implementation
        case dualStageVerification
        case retryOnFailure
        case continueOtherTargetsOnFailure
        case writeSidecarChecksum
        case generateAscMHL
        case generateCSVLog
        case generateJSONLog
        case includeFullHashesInReport
        case recordEnvironmentInReport
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        algorithm = try container.decodeIfPresent(ChecksumAlgorithm.self, forKey: .algorithm) ?? .xxhash64
        xxHash64Implementation = try container.decodeIfPresent(XXHash64Implementation.self, forKey: .xxHash64Implementation) ?? .automatic
        dualStageVerification = try container.decodeIfPresent(Bool.self, forKey: .dualStageVerification) ?? true
        retryOnFailure = try container.decodeIfPresent(Int.self, forKey: .retryOnFailure) ?? 0
        continueOtherTargetsOnFailure = try container.decodeIfPresent(Bool.self, forKey: .continueOtherTargetsOnFailure) ?? true
        writeSidecarChecksum = try container.decodeIfPresent(Bool.self, forKey: .writeSidecarChecksum) ?? true
        generateAscMHL = try container.decodeIfPresent(Bool.self, forKey: .generateAscMHL) ?? true
        generateCSVLog = try container.decodeIfPresent(Bool.self, forKey: .generateCSVLog) ?? true
        generateJSONLog = try container.decodeIfPresent(Bool.self, forKey: .generateJSONLog) ?? true
        includeFullHashesInReport = try container.decodeIfPresent(Bool.self, forKey: .includeFullHashesInReport) ?? true
        recordEnvironmentInReport = try container.decodeIfPresent(Bool.self, forKey: .recordEnvironmentInReport) ?? true
    }
}

// MARK: - Report

enum ReportLanguage: String, Codable, CaseIterable, Identifiable {
    case zh, en, dual
    var id: String { rawValue }
    var label: (String, String) {
        switch self {
        case .zh:   return ("中文", "Chinese")
        case .en:   return ("英文", "English")
        case .dual: return ("中英双语", "Bilingual")
        }
    }
}

struct ReportContentToggles: Codable, Equatable {
    var projectInfo: Bool = true
    var cameraInfo: Bool = true
    var sourceInfo: Bool = true
    var destinationInfo: Bool = true
    var fileCount: Bool = true
    var totalSize: Bool = true
    var startTime: Bool = true
    var endTime: Bool = true
    var elapsed: Bool = true
    var averageSpeed: Bool = true
    var hashAlgorithm: Bool = true
    var verifyResult: Bool = true
    var failedFiles: Bool = true
    var operatorSignature: Bool = false
    var appVersion: Bool = true
    var systemVersion: Bool = true
}

struct ReportSettings: Codable, Equatable {
    var pdfTemplate: String = "default"
    var includeProjectLogo: Bool = false
    var projectLogoPath: String = ""
    var includeCompanyLogo: Bool = false
    var companyLogoPath: String = ""
    var namingTemplate: String = "{Project}_{Date}_{Card}_CopyReport"
    var language: ReportLanguage = .dual
    var generateBriefReport: Bool = true
    var generateFullTechReport: Bool = true
    var autoOpenReportOnFinish: Bool = false
    var autoOpenReportFolderOnFinish: Bool = true
    var content: ReportContentToggles = .init()
}

// MARK: - Transcode

enum AudioPolicy: String, Codable, CaseIterable, Identifiable {
    case keepOriginal
    case aac192
    case pcm16
    case stripAudio
    var id: String { rawValue }
    var label: (String, String) {
        switch self {
        case .keepOriginal: return ("保留原始", "Keep original")
        case .aac192:       return ("AAC 192k", "AAC 192k")
        case .pcm16:        return ("PCM 16-bit", "PCM 16-bit")
        case .stripAudio:   return ("不要音频", "Strip audio")
        }
    }
}

struct TranscodeSettings: Codable, Equatable {
    var autoTranscodeOnVerified: Bool = false
    var defaultProxyFolder: String = ""
    var namingTemplate: String = "{stem}{suffix}.{ext}"
    var defaultCodec: TranscodeCodec = .proresProxy
    var defaultQuality: TranscodeQuality = .medium
    var defaultBitrate: TranscodeBitrate = .auto
    var defaultScale: TranscodeScale = .hd1080
    var keepOriginalFrameRate: Bool = true
    var audioPolicy: AudioPolicy = .keepOriginal
    var embedTimecode: Bool = true
    var enableHardwareAcceleration: Bool = true
    var maxConcurrentTranscodes: Int = 2
    var failedTranscodeAffectsTaskState: Bool = false
    var attemptRawSources: Bool = false
    var ffmpegPath: String = ""
}

// MARK: - LUT

struct LUTSlot: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var camera: String   // e.g. "A_CAM" / "B_CAM"
    var colorSpace: String // e.g. "Sony S-Log3"
    var lutPath: String
}

struct LUTSettings: Codable, Equatable {
    var defaultLUTFolder: String = ""
    var defaultLUTPath: String = ""
    var autoApply: Bool = false
    var allowPerCardOverride: Bool = true
    var matchByCamera: Bool = false
    var generateBothLUTAndClean: Bool = false
    var intensity: Double = 1.0    // 0...1
    var colorSpaceNote: String = ""
    var perCameraSlots: [LUTSlot] = []
}

// MARK: - Storage Safety

struct StorageSafetySettings: Codable, Equatable {
    var sourceReadOnly: Bool = true
    var preventWritingToSource: Bool = true
    var minimumTargetFreeSpaceGB: Int = 50
    var targetFullWarningPercent: Int = 90
    var detectSameSourceTarget: Bool = true
    var detectNestedTargetUnderSource: Bool = true
    var detectCaseConflict: Bool = true
    var detectIllegalCharacters: Bool = true
    var detectLongFileNames: Bool = true
    var detectFilesystemDifferences: Bool = true
    var preventSystemSleepDuringCopy: Bool = true
    var allowEjectSourceOnFinish: Bool = false
    var allowEjectTargetOnFinish: Bool = false
    // DANGER toggles
    var allowOverwriteExisting: Bool = false
    var disableTargetReadback: Bool = false
    var allowWritingToSource: Bool = false
    var allowSameVolumeForSourceAndTarget: Bool = false
    var allowCopyToSystemDisk: Bool = false
}

// MARK: - Performance

struct PerformanceSettings: Codable, Equatable {
    var copyBufferKB: Int = 8192            // 8MB, optimized for modern MacBook storage throughput
    var maxConcurrentFiles: Int = 1
    var maxConcurrentTargets: Int = 3
    var enableSpeedLimit: Bool = false
    var speedLimitMBps: Int = 200
    var lowPowerMode: Bool = false
    var preventAppNap: Bool = true
    var preventSystemSleep: Bool = true
    var showRealtimeSpeedGraph: Bool = false
    var showPerTargetSpeed: Bool = true
    var verboseLogging: Bool = false
}

// MARK: - Notification

enum WebhookKind: String, Codable, CaseIterable, Identifiable {
    case slack
    case feishu
    case wecom
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .slack: return "Slack"
        case .feishu: return "Lark / Feishu"
        case .wecom: return "WeCom"
        case .custom: return "Custom"
        }
    }
}

struct WebhookEndpointSettings: Codable, Equatable {
    var enabled: Bool = false
    var kind: WebhookKind
    var name: String
    var maskedURL: String = ""

    init(kind: WebhookKind, name: String? = nil, enabled: Bool = false, maskedURL: String = "") {
        self.kind = kind
        self.name = name ?? kind.displayName
        self.enabled = enabled
        self.maskedURL = maskedURL
    }
}

struct NotificationSettings: Equatable {
    var soundOnFinish: Bool = true
    var warnSoundOnVerifyFailure: Bool = true
    var systemNotification: Bool = true
    var popupOnFinish: Bool = false
    var popupOnFailure: Bool = true
    var dockProgress: Bool = true
    var menuBarStatus: Bool = false
    var autoOpenReportOnFinish: Bool = false
    var autoOpenOutputFolderOnFinish: Bool = false
    var slackWebhook: WebhookEndpointSettings = .init(kind: .slack)
    var feishuWebhook: WebhookEndpointSettings = .init(kind: .feishu)
    var wecomWebhook: WebhookEndpointSettings = .init(kind: .wecom)
    var customWebhook: WebhookEndpointSettings = .init(kind: .custom)

    var legacySlackWebhookURL: String = ""
    var legacyFeishuWebhookURL: String = ""
    var legacyWecomWebhookURL: String = ""
    var legacyCustomWebhookURL: String = ""
}

extension NotificationSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case soundOnFinish
        case warnSoundOnVerifyFailure
        case systemNotification
        case popupOnFinish
        case popupOnFailure
        case dockProgress
        case menuBarStatus
        case autoOpenReportOnFinish
        case autoOpenOutputFolderOnFinish
        case slackWebhook
        case feishuWebhook
        case wecomWebhook
        case customWebhook
        case slackWebhookURL
        case feishuWebhookURL
        case wecomWebhookURL
        case customWebhookURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        soundOnFinish = try container.decodeIfPresent(Bool.self, forKey: .soundOnFinish) ?? true
        warnSoundOnVerifyFailure = try container.decodeIfPresent(Bool.self, forKey: .warnSoundOnVerifyFailure) ?? true
        systemNotification = try container.decodeIfPresent(Bool.self, forKey: .systemNotification) ?? true
        popupOnFinish = try container.decodeIfPresent(Bool.self, forKey: .popupOnFinish) ?? false
        popupOnFailure = try container.decodeIfPresent(Bool.self, forKey: .popupOnFailure) ?? true
        dockProgress = try container.decodeIfPresent(Bool.self, forKey: .dockProgress) ?? true
        menuBarStatus = try container.decodeIfPresent(Bool.self, forKey: .menuBarStatus) ?? false
        autoOpenReportOnFinish = try container.decodeIfPresent(Bool.self, forKey: .autoOpenReportOnFinish) ?? false
        autoOpenOutputFolderOnFinish = try container.decodeIfPresent(Bool.self, forKey: .autoOpenOutputFolderOnFinish) ?? false

        slackWebhook = try container.decodeIfPresent(WebhookEndpointSettings.self, forKey: .slackWebhook) ?? .init(kind: .slack)
        feishuWebhook = try container.decodeIfPresent(WebhookEndpointSettings.self, forKey: .feishuWebhook) ?? .init(kind: .feishu)
        wecomWebhook = try container.decodeIfPresent(WebhookEndpointSettings.self, forKey: .wecomWebhook) ?? .init(kind: .wecom)
        customWebhook = try container.decodeIfPresent(WebhookEndpointSettings.self, forKey: .customWebhook) ?? .init(kind: .custom)

        legacySlackWebhookURL = try container.decodeIfPresent(String.self, forKey: .slackWebhookURL) ?? ""
        legacyFeishuWebhookURL = try container.decodeIfPresent(String.self, forKey: .feishuWebhookURL) ?? ""
        legacyWecomWebhookURL = try container.decodeIfPresent(String.self, forKey: .wecomWebhookURL) ?? ""
        legacyCustomWebhookURL = try container.decodeIfPresent(String.self, forKey: .customWebhookURL) ?? ""

        applyLegacyMetadata()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(soundOnFinish, forKey: .soundOnFinish)
        try container.encode(warnSoundOnVerifyFailure, forKey: .warnSoundOnVerifyFailure)
        try container.encode(systemNotification, forKey: .systemNotification)
        try container.encode(popupOnFinish, forKey: .popupOnFinish)
        try container.encode(popupOnFailure, forKey: .popupOnFailure)
        try container.encode(dockProgress, forKey: .dockProgress)
        try container.encode(menuBarStatus, forKey: .menuBarStatus)
        try container.encode(autoOpenReportOnFinish, forKey: .autoOpenReportOnFinish)
        try container.encode(autoOpenOutputFolderOnFinish, forKey: .autoOpenOutputFolderOnFinish)
        try container.encode(slackWebhook, forKey: .slackWebhook)
        try container.encode(feishuWebhook, forKey: .feishuWebhook)
        try container.encode(wecomWebhook, forKey: .wecomWebhook)
        try container.encode(customWebhook, forKey: .customWebhook)
    }

    private mutating func applyLegacyMetadata() {
        let legacy: [(WebhookKind, String)] = [
            (.slack, legacySlackWebhookURL),
            (.feishu, legacyFeishuWebhookURL),
            (.wecom, legacyWecomWebhookURL),
            (.custom, legacyCustomWebhookURL)
        ]
        for (kind, url) in legacy where !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let masked = WebhookCredentialStore.mask(url)
            switch kind {
            case .slack:
                slackWebhook.enabled = true
                slackWebhook.maskedURL = masked
            case .feishu:
                feishuWebhook.enabled = true
                feishuWebhook.maskedURL = masked
            case .wecom:
                wecomWebhook.enabled = true
                wecomWebhook.maskedURL = masked
            case .custom:
                customWebhook.enabled = true
                customWebhook.maskedURL = masked
            }
        }
    }

    func endpoint(for kind: WebhookKind) -> WebhookEndpointSettings {
        switch kind {
        case .slack: return slackWebhook
        case .feishu: return feishuWebhook
        case .wecom: return wecomWebhook
        case .custom: return customWebhook
        }
    }

    mutating func setEndpoint(_ endpoint: WebhookEndpointSettings) {
        switch endpoint.kind {
        case .slack: slackWebhook = endpoint
        case .feishu: feishuWebhook = endpoint
        case .wecom: wecomWebhook = endpoint
        case .custom: customWebhook = endpoint
        }
    }
}

enum WebhookCredentialStore {
    static let service = "com.321doit.webhook"

    static func mask(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme,
              let host = components.host else {
            return trimmed.isEmpty ? "" : "****"
        }
        return "\(scheme)://\(host)/.../****"
    }

    static func read(kind: WebhookKind) throws -> String? {
        var query = baseQuery(kind: kind)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw keychainError(status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ url: String, kind: WebhookKind) throws {
        let data = Data(url.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        var query = baseQuery(kind: kind)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        if status != errSecItemNotFound { throw keychainError(status) }
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw keychainError(addStatus) }
    }

    static func delete(kind: WebhookKind) throws {
        let status = SecItemDelete(baseQuery(kind: kind) as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound { return }
        throw keychainError(status)
    }

    static func migrateLegacyURLs(in settings: inout NotificationSettings) throws -> Bool {
        var migrated = false
        let legacy: [(WebhookKind, String)] = [
            (.slack, settings.legacySlackWebhookURL),
            (.feishu, settings.legacyFeishuWebhookURL),
            (.wecom, settings.legacyWecomWebhookURL),
            (.custom, settings.legacyCustomWebhookURL)
        ]

        for (kind, url) in legacy {
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            try write(trimmed, kind: kind)
            var endpoint = settings.endpoint(for: kind)
            endpoint.enabled = true
            endpoint.maskedURL = mask(trimmed)
            settings.setEndpoint(endpoint)
            migrated = true
        }

        if migrated {
            settings.legacySlackWebhookURL = ""
            settings.legacyFeishuWebhookURL = ""
            settings.legacyWecomWebhookURL = ""
            settings.legacyCustomWebhookURL = ""
        }
        return migrated
    }

    private static func baseQuery(kind: WebhookKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue
        ]
    }

    private static func keychainError(_ status: OSStatus) -> NSError {
        NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: "Keychain error \(status)"]
        )
    }
}

// MARK: - Logs

enum LogLevel: String, Codable, CaseIterable, Identifiable {
    case normal, detailed, debug
    var id: String { rawValue }
    var label: (String, String) {
        switch self {
        case .normal:   return ("Normal", "Normal")
        case .detailed: return ("Detailed", "Detailed")
        case .debug:    return ("Debug", "Debug")
        }
    }
}

struct LogSettings: Codable, Equatable {
    var logFolder: String = ""
    var retentionDays: Int = 30
    var level: LogLevel = .normal
    var exportJSON: Bool = false
    var exportText: Bool = true
    var includeSummaryInReport: Bool = true
    var keepIncompleteTaskOnCrash: Bool = true
    var allowDiagnosticsExport: Bool = true
}

// MARK: - Update / About

struct UpdateSettings: Codable, Equatable {
    var autoCheckForUpdates: Bool = true
    var receiveBeta: Bool = false
    /// Read-only display values — not user editable.
    static let appVersion: String = appVersionString
    static let buildNumber: String = appBuildNumberString
    static let githubURL: String = "https://github.com/Maoxintao98/321doit"
    static let issueURL: String = "https://github.com/Maoxintao98/321doit/issues"
    static let supportEmail: String = "maoxintao98@outlook.com"
    static let supportPhone: String = "17816196151"
    static let supportWeChat: String = "17816196151"
    static let oneTimeSupportURL: String = "https://github.com/sponsors/Maoxintao98?frequency=one-time"
    static let longTermSponsorURL: String = "https://github.com/sponsors/Maoxintao98"
    /// Sparkle-compatible appcast feed. Override at build time by editing
    /// the `SUFeedURL` entry baked into Info.plist by build.sh; this string
    /// is only used as a debug display in preferences.
    static let appcastURL: String = "https://maoxintao98.github.io/321doit/appcast.xml"
    static var licenseBlurb: (String, String) {
        ("免费 & 开源。自由使用、修改与分发。", "Free & open source. Feel free to use, modify and distribute.")
    }
}

// MARK: - Persistent store

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { schedulePersist() }
    }
    @Published var credentialWarning: String?
    @Published var persistenceWarning: String?

    private let fileURL: URL
    private let backupURL: URL
    private var persistTask: DispatchWorkItem?

    init() {
        let storeURL = Self.makeStoreURL()
        self.fileURL = storeURL
        self.backupURL = storeURL.deletingLastPathComponent().appendingPathComponent("settings.backup.json")
        self.credentialWarning = nil
        self.persistenceWarning = nil

        var loadedSettings: AppSettings
        var needsPersist = false
        let primaryExists = FileManager.default.fileExists(atPath: fileURL.path)
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            loadedSettings = decoded
        } else if let backupData = try? Data(contentsOf: backupURL),
                  let decoded = try? JSONDecoder().decode(AppSettings.self, from: backupData) {
            loadedSettings = decoded
            needsPersist = true
            self.persistenceWarning = L10n.t(
                "设置文件无法读取，已从上一份有效备份恢复。损坏文件会保留用于诊断。",
                "Settings were unreadable and were recovered from the previous valid backup. The corrupt file is retained for diagnostics.",
                language: decoded.general.language
            )
            Self.archiveCorruptSettingsIfPresent(at: fileURL)
            AppLogger.log(.warning, category: "settings", "Recovered settings from the previous valid backup")
        } else {
            loadedSettings = AppSettings()
            if primaryExists {
                self.persistenceWarning = L10n.t(
                    "设置文件和备份都无法读取，已使用安全默认值；损坏文件已保留。",
                    "Settings and their backup were unreadable, so safe defaults were loaded; the corrupt file was retained.",
                    language: loadedSettings.general.language
                )
                Self.archiveCorruptSettingsIfPresent(at: fileURL)
                AppLogger.log(.error, category: "settings", "Settings and backup were unreadable; loaded safe defaults")
            }
        }

        if loadedSettings.performance.copyBufferKB == 1024 {
            loadedSettings.performance.copyBufferKB = 8192
            needsPersist = true
        }

        do {
            let migrated = try WebhookCredentialStore.migrateLegacyURLs(in: &loadedSettings.notification)
            self.settings = loadedSettings
            if migrated || needsPersist {
                persist()
            }
        } catch {
            self.settings = loadedSettings
            self.credentialWarning = L10n.t(
                "Webhook 凭据迁移失败：\(error.localizedDescription)",
                "Webhook credential migration failed: \(error.localizedDescription)",
                language: loadedSettings.general.language
            )
            NSLog("[321Doit] webhook credential migration failed: \(error)")
            AppLogger.log(.error, category: "settings", "Webhook credential migration failed: \(error.localizedDescription)")
        }
    }

    private static func makeStoreURL() -> URL {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory,
                                   in: .userDomainMask,
                                   appropriateFor: nil,
                                   create: true)) ?? fm.temporaryDirectory
        let dir = support.appendingPathComponent("321Doit", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    private static func archiveCorruptSettingsIfPresent(at url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let archive = url.deletingLastPathComponent().appendingPathComponent("settings-corrupt-\(stamp).json")
        do {
            try fm.copyItem(at: url, to: archive)
            let corruptFiles = ((try? fm.contentsOfDirectory(
                at: url.deletingLastPathComponent(),
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []).filter { $0.lastPathComponent.hasPrefix("settings-corrupt-") }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for expired in corruptFiles.dropFirst(3) { try? fm.removeItem(at: expired) }
        } catch {
            AppLogger.log(.error, category: "settings", "Could not archive corrupt settings: \(error.localizedDescription)")
        }
    }

    /// Convenience binding helper for nested key paths.
    func binding<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { self.settings[keyPath: keyPath] = $0 }
        )
    }

    func resetToDefaults() {
        settings = AppSettings()
    }

    func saveNow() {
        persistTask?.cancel()
        persistTask = nil
        persist()
    }

    func exportJSON(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(SettingsExportEnvelope(settings: settings))
        try data.write(to: url)
    }

    func importJSON(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoded = try Self.decodeImportedSettings(from: data)
        self.settings = decoded
    }

    func setWebhookURL(_ url: String, for kind: WebhookKind) throws {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try WebhookCredentialStore.delete(kind: kind)
        } else {
            guard URL(string: trimmed) != nil else {
                throw SettingsImportError.invalidWebhookURL
            }
            try WebhookCredentialStore.write(trimmed, kind: kind)
        }

        var endpoint = settings.notification.endpoint(for: kind)
        endpoint.enabled = !trimmed.isEmpty
        endpoint.maskedURL = WebhookCredentialStore.mask(trimmed)
        settings.notification.setEndpoint(endpoint)
    }

    func clearWebhookCredentials() throws {
        for kind in WebhookKind.allCases {
            try WebhookCredentialStore.delete(kind: kind)
            var endpoint = settings.notification.endpoint(for: kind)
            endpoint.enabled = false
            endpoint.maskedURL = ""
            settings.notification.setEndpoint(endpoint)
        }
    }

    private static func decodeImportedSettings(from data: Data) throws -> AppSettings {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(SettingsExportEnvelope.self, from: data) {
            guard envelope.app == "321Doit" else { throw SettingsImportError.wrongApp }
            guard envelope.schemaVersion == SettingsExportEnvelope.supportedSchemaVersion else {
                throw SettingsImportError.unsupportedVersion(envelope.schemaVersion)
            }
            return envelope.settings
        }
        throw SettingsImportError.invalidEnvelope
    }

    // Coalesce frequent writes so binding-driven typing doesn't hammer the disk.
    private func schedulePersist() {
        persistTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.persist() }
        persistTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            if let current = try? Data(contentsOf: fileURL),
               (try? JSONDecoder().decode(AppSettings.self, from: current)) != nil {
                try current.write(to: backupURL, options: [.atomic])
            }
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            NSLog("[321Doit] failed to persist settings: \(error)")
            AppLogger.log(.error, category: "settings", "Failed to persist settings: \(error.localizedDescription)")
            persistenceWarning = L10n.t(
                "设置保存失败：\(error.localizedDescription)",
                "Settings could not be saved: \(error.localizedDescription)",
                language: settings.general.language
            )
        }
    }
}

private struct SettingsExportEnvelope: Codable {
    static let supportedSchemaVersion = 1

    var app: String = "321Doit"
    var schemaVersion: Int = Self.supportedSchemaVersion
    var exportedAt: String = iso8601String(Date())
    var settings: AppSettings
}

enum SettingsImportError: LocalizedError {
    case wrongApp
    case unsupportedVersion(Int)
    case invalidEnvelope
    case invalidWebhookURL

    var errorDescription: String? {
        switch self {
        case .wrongApp:
            return "Not a 321Doit settings file."
        case .unsupportedVersion(let version):
            return "Unsupported settings schemaVersion: \(version)."
        case .invalidEnvelope:
            return "Settings JSON is incomplete; expected app, schemaVersion, exportedAt, and settings."
        case .invalidWebhookURL:
            return "Webhook URL is invalid."
        }
    }
}
