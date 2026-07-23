import Foundation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case zh
    case en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .zh:     return "简体中文"
        case .en:     return "English"
        }
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .system: return L10n.t("跟随系统", "System", language: language)
        case .zh:     return "简体中文"
        case .en:     return "English"
        }
    }

    /// Resolve `system` to an actual language using the OS locale.
    var resolved: AppLanguage {
        if self != .system { return self }
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        return code.lowercased().hasPrefix("zh") ? .zh : .en
    }
}

/// Minimal bilingual string helper. Call sites pass both translations.
/// `current` is read from the active SettingsStore (see L10n).
enum L10n {
    /// Returns the appropriate translation for the active language.
    static func t(_ zh: String, _ en: String, language: AppLanguage) -> String {
        switch language.resolved {
        case .zh: return zh
        case .en: return en
        case .system: return zh // unreachable after resolved
        }
    }

    /// Bilingual fallback that always shows both, used for top-bar labels etc.
    static func biLine(_ zh: String, _ en: String) -> String {
        "\(zh) / \(en)"
    }
}
