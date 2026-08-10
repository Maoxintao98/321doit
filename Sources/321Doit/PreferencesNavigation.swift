import SwiftUI

enum PrefCategory: String, CaseIterable, Identifiable {
    case workspace
    case mediaPipeline
    case delivery
    case system

    var id: String { rawValue }

    func label(_ lang: AppLanguage) -> String {
        switch self {
        case .workspace: return L10n.t("工作区与应用", "Workspace & App", language: lang)
        case .mediaPipeline: return L10n.t("素材流程", "Media Pipeline", language: lang)
        case .delivery: return L10n.t("交付与自动化", "Delivery & Automation", language: lang)
        case .system: return L10n.t("系统与支持", "System & Support", language: lang)
        }
    }

    var symbol: String {
        switch self {
        case .workspace: return "square.grid.2x2"
        case .mediaPipeline: return "externaldrive.connected.to.line.below"
        case .delivery: return "arrow.up.forward.app"
        case .system: return "wrench.and.screwdriver"
        }
    }

    var sections: [PrefSection] {
        switch self {
        case .workspace:
            return [.general, .projectTemplate, .shortcuts, .mira]
        case .mediaPipeline:
            return [.copyVerify, .checksum, .report, .transcode, .ffmpeg, .lut]
        case .delivery:
            return [.handoff, .notification]
        case .system:
            return [.safety, .performance, .logs, .about]
        }
    }
}

extension PrefSection {
    func summary(_ lang: AppLanguage) -> String {
        switch self {
        case .general: return L10n.t("语言、外观与动效", "Language, appearance and motion", language: lang)
        case .projectTemplate: return L10n.t("新任务的项目默认值", "Project defaults for new tasks", language: lang)
        case .copyVerify: return L10n.t("目标盘、续传与失败重试", "Destinations, resume and retries", language: lang)
        case .checksum: return L10n.t("Hash 算法与校验输出", "Hash algorithms and verification output", language: lang)
        case .report: return L10n.t("报告格式与完成动作", "Report formats and completion actions", language: lang)
        case .transcode: return L10n.t("代理编码与默认画质", "Proxy codecs and default quality", language: lang)
        case .ffmpeg: return L10n.t("转码引擎状态与路径", "Transcode engine status and path", language: lang)
        case .lut: return L10n.t("默认 LUT 与色彩处理", "Default LUT and color processing", language: lang)
        case .handoff: return L10n.t("Final Cut 与 Resolve 交接", "Final Cut and Resolve handoff", language: lang)
        case .shortcuts: return L10n.t("场记操作与按键映射", "Script-log actions and key mapping", language: lang)
        case .safety: return L10n.t("固定生效的数据保护边界", "Always-on data protection boundaries", language: lang)
        case .performance: return L10n.t("I/O 缓冲与速度限制", "I/O buffering and rate limits", language: lang)
        case .notification: return L10n.t("本机提醒与 Webhook", "Local alerts and webhooks", language: lang)
        case .logs: return L10n.t("任务恢复、日志与诊断", "Recovery, logs and diagnostics", language: lang)
        case .mira: return L10n.t("模型服务、凭据与权限", "Model services, credentials and permissions", language: lang)
        case .about: return L10n.t("更新、版本与开源信息", "Updates, version and open-source info", language: lang)
        }
    }

    func matchesSettingsSearch(_ rawQuery: String, language: AppLanguage) -> Bool {
        let query = rawQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !query.isEmpty else { return true }

        let haystack = ([label(language), summary(language)] + searchKeywords)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return haystack.localizedStandardContains(query)
    }

    private var searchKeywords: [String] {
        switch self {
        case .general:
            return ["语言 language 外观 appearance 主题 theme 深色 dark 浅色 light 动效 motion"]
        case .projectTemplate:
            return ["项目 project 工作区 workspace 默认值 defaults 拷卡 offload 任务 task"]
        case .copyVerify:
            return ["拷贝 copy 校验 verify 目标盘 destination 续传 resume 重试 retry 覆盖 overwrite"]
        case .checksum:
            return ["checksum hash xxhash md5 sha mhl sidecar csv json 校验算法"]
        case .report:
            return ["报告 report pdf txt 打开 open 完成 finish"]
        case .transcode:
            return ["代理 proxy 转码 transcode codec 编码 h264 h265 prores 画质 quality 分辨率 resolution"]
        case .ffmpeg:
            return ["ffmpeg ffprobe 路径 path engine 引擎 codec"]
        case .lut:
            return ["lut 色彩 color 调色 look intensity 强度"]
        case .handoff:
            return ["后期 handoff final cut fcp resolve davinci timeline timecode proxy lut"]
        case .shortcuts:
            return ["快捷键 shortcut keyboard 场记 script log take shot scene"]
        case .safety:
            return ["安全 safety 磁盘 storage source 源盘 overwrite hash 保护"]
        case .performance:
            return ["性能 performance io buffer 缓冲 速度 speed bandwidth 带宽 sleep"]
        case .notification:
            return ["通知 notification sound 声音 popup 弹窗 dock webhook slack 飞书 企业微信"]
        case .logs:
            return ["日志 log diagnostics 诊断 recovery 恢复 retention 保留 jsonl"]
        case .mira:
            return ["mira ai opencode 模型 model api key provider 服务 凭据 credential 权限 permission"]
        case .about:
            return ["关于 about update 更新 beta version 版本 license 开源 github"]
        }
    }
}

struct PreferencesSidebar: View {
    @EnvironmentObject private var store: SettingsStore
    @Environment(\.themeColors) private var colors
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: PrefSection
    @Binding var searchText: String
    @State private var hoveredSection: PrefSection?

    private var lang: AppLanguage { store.settings.general.language.resolved }
    private var hasResults: Bool {
        PrefCategory.allCases.contains { category in
            category.sections.contains { $0.matchesSettingsSearch(searchText, language: lang) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: DoitSpacing.xxs) {
                    Text("321Doit")
                        .font(DoitFont.bodyEmphasis)
                    Text(L10n.t("设置中心", "Settings", language: lang))
                        .font(DoitFont.caption)
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DoitSpacing.md)
            .padding(.vertical, DoitSpacing.sm)

            Divider()

            List {
                ForEach(PrefCategory.allCases) { category in
                    let sections = category.sections.filter {
                        $0.matchesSettingsSearch(searchText, language: lang)
                    }
                    if !sections.isEmpty {
                        Section {
                            ForEach(sections) { section in
                                Button {
                                    selection = section
                                } label: {
                                    preferenceRow(section)
                                }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                                .listRowBackground(Color.clear)
                                .accessibilityIdentifier("preferences.section.\(section.rawValue)")
                                .onHover { hovering in
                                    hoveredSection = hovering ? section : nil
                                }
                            }
                        } header: {
                            Label(category.label(lang), systemImage: category.symbol)
                                .font(DoitFont.caption)
                                .foregroundStyle(colors.textTertiary)
                        }
                    }
                }

                if !hasResults {
                    VStack(spacing: DoitSpacing.xs) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundStyle(colors.textTertiary)
                        Text(L10n.t("没有匹配的设置", "No matching settings", language: lang))
                            .font(DoitFont.callout)
                            .fontWeight(.medium)
                        Text(L10n.t("可搜索功能、格式或服务名称", "Try a feature, format, or service name", language: lang))
                            .font(DoitFont.caption)
                            .foregroundStyle(colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .listRowBackground(Color.clear)
                }
            }
            .searchable(
                text: $searchText,
                placement: .sidebar,
                prompt: L10n.t("搜索设置、格式或服务", "Search settings, formats, or services", language: lang)
            )
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .tint(colors.accentDeep)
            .accentColor(colors.accentDeep)
        }
        .navigationSplitViewColumnWidth(min: 250, ideal: 278, max: 320)
    }

    private func preferenceRow(_ section: PrefSection) -> some View {
        let isSelected = selection == section
        let isHovered = hoveredSection == section
        return HStack(alignment: .top, spacing: DoitSpacing.xs) {
            Image(systemName: section.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(colors.accent)
                .frame(width: 18, height: 20)
            VStack(alignment: .leading, spacing: DoitSpacing.xxs) {
                Text(section.label(lang))
                    .font(DoitFont.callout)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundStyle(colors.textPrimary)
                Text(section.summary(lang))
                    .font(DoitFont.caption)
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isSelected
                ? colors.accent.opacity(colorScheme == .dark ? 0.22 : 0.13)
                : (isHovered ? colors.textPrimary.opacity(0.05) : Color.clear),
            in: RoundedRectangle(cornerRadius: DoitRadius.control, style: .continuous)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(isSelected ? colors.accent : Color.clear)
                .frame(width: 3, height: 24)
                .padding(.leading, 1)
        }
    }
}
