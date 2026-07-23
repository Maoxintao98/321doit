import Foundation

enum LocalizedDisplay {
    static func projectName(_ project: Project, language: AppLanguage) -> String {
        let trimmed = project.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "未命名项目" || trimmed == "Untitled Project" || trimmed == "Untitled" {
            return L10n.t("未命名项目", "Untitled Project", language: language)
        }
        return trimmed
    }

    static func dayTitle(_ day: ShootingDay?, language: AppLanguage) -> String {
        guard let day else { return L10n.t("第 1 天", "Day 1", language: language) }
        let trimmed = day.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return fallbackDayDate(day.date)
        }
        if trimmed.allSatisfy(\.isNumber) {
            return L10n.t("第 \(trimmed) 天", "Day \(trimmed)", language: language)
        }
        if trimmed.hasPrefix("Day ") {
            let suffix = trimmed.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
            return L10n.t("第 \(suffix) 天", "Day \(suffix)", language: language)
        }
        if trimmed.hasPrefix("第 "), trimmed.hasSuffix(" 天") {
            let suffix = trimmed.dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespacesAndNewlines)
            return L10n.t("第 \(suffix) 天", "Day \(suffix)", language: language)
        }
        return trimmed
    }

    static func sceneTitle(_ raw: String, language: AppLanguage) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return L10n.t("双击输入场号", "Double-click to enter scene #", language: language) }
        if trimmed.allSatisfy(\.isNumber) {
            return L10n.t("第 \(trimmed) 场", "Scene \(trimmed)", language: language)
        }
        return trimmed
    }

    static func cameraLabel(_ raw: String, language: AppLanguage) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if language.resolved == .zh {
            return trimmed.isEmpty ? "A机" : trimmed
        }
        if trimmed.hasSuffix("机") {
            let prefix = trimmed.dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                return "Cam \(prefix)"
            }
        }
        if trimmed.hasPrefix("Cam ") || trimmed.hasPrefix("Camera ") {
            return trimmed
        }
        return trimmed.isEmpty ? "Cam A" : trimmed
    }

    private static func fallbackDayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
