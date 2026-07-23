import SwiftUI

enum Workspace: String, CaseIterable, Identifiable, Codable {
    case project
    case shootingDay
    case scriptLog
    case offload
    case handoff
    case reports

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .project:
            return L10n.t("项目", "Project", language: language)
        case .shootingDay:
            return L10n.t("拍摄日", "Shooting Day", language: language)
        case .scriptLog:
            return L10n.t("场记", "Script Log", language: language)
        case .offload:
            return L10n.t("DIT 下盘", "Offload", language: language)
        case .handoff:
            return L10n.t("后期交接", "Post Handoff", language: language)
        case .reports:
            return L10n.t("报告", "Reports", language: language)
        }
    }

    func subtitle(language: AppLanguage) -> String {
        switch self {
        case .project:
            return L10n.t("项目元数据与本地项目目录", "Project metadata and local project folder", language: language)
        case .shootingDay:
            return L10n.t("拍摄日历、单日工作台与通告单", "Shooting calendar, day workspace and call sheets", language: language)
        case .scriptLog:
            return L10n.t("片场快速记录 Scene / Shot / Take", "Fast on-set Scene / Shot / Take logging", language: language)
        case .offload:
            return L10n.t("稳定的 3-2-1 拷贝、校验、代理与交接", "Stable 3-2-1 copy, verify, proxy and handoff", language: language)
        case .handoff:
            return L10n.t("交接包、达芬奇导入与剪辑素材归类", "Handoff packages, Resolve import and editorial media sorting", language: language)
        case .reports:
            return L10n.t("下盘报告与场记导出", "Offload reports and script-log exports", language: language)
        }
    }

    var systemImage: String {
        switch self {
        case .project: return "folder"
        case .shootingDay: return "calendar"
        case .scriptLog: return "list.clipboard"
        case .offload: return "externaldrive.badge.checkmark"
        case .handoff: return "shippingbox"
        case .reports: return "doc.text.magnifyingglass"
        }
    }
}
