import AppKit
import SwiftUI

private let recentProjectDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

private struct LanguagePopUpButton: NSViewRepresentable {
    @Binding var selection: AppLanguage
    var resolvedLanguage: AppLanguage

    func makeNSView(context: Context) -> NSPopUpButton {
        let btn = NSPopUpButton(frame: .zero, pullsDown: true)
        btn.isBordered = false
        btn.focusRingType = .none
        btn.font = .systemFont(ofSize: 12)
        (btn.cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        btn.target = context.coordinator
        btn.action = #selector(Coordinator.changed(_:))
        rebuild(btn)
        return btn
    }

    func updateNSView(_ btn: NSPopUpButton, context: Context) {
        rebuild(btn)
    }

    private func rebuild(_ btn: NSPopUpButton) {
        btn.removeAllItems()
        let title = "🌐  \(selection.displayName(language: resolvedLanguage))"
        btn.addItem(withTitle: title)
        if let cell = btn.cell as? NSButtonCell {
            cell.attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
            )
        }
        btn.menu?.addItem(.separator())
        for opt in AppLanguage.allCases {
            let item = NSMenuItem(
                title: opt.displayName(language: resolvedLanguage),
                action: nil,
                keyEquivalent: ""
            )
            item.representedObject = opt
            if opt == selection { item.state = .on }
            btn.menu?.addItem(item)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject {
        var parent: LanguagePopUpButton
        init(_ parent: LanguagePopUpButton) { self.parent = parent }
        @objc func changed(_ sender: NSPopUpButton) {
            guard let opt = sender.selectedItem?.representedObject as? AppLanguage else { return }
            parent.selection = opt
        }
    }
}

struct RecentProject: Identifiable, Codable, Equatable {
    var id: String { path }
    var name: String
    var path: String
    var lastOpenedAt: Date

    var url: URL { URL(fileURLWithPath: path) }
    var isAccessible: Bool { ScriptLogStore.isProjectFolder(url) }
}

@MainActor
final class RecentProjectStore: ObservableObject {
    @Published private(set) var projects: [RecentProject] = []
    private let key = "321doit.recentProjects"
    private let limit = 8

    init() {
        load()
    }

    func record(url: URL?, name: String) {
        guard let url else { return }
        let standardized = url.standardizedFileURL
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? standardized.lastPathComponent : name
        projects.removeAll { $0.path == standardized.path }
        projects.insert(
            RecentProject(name: displayName, path: standardized.path, lastOpenedAt: Date()),
            at: 0
        )
        if projects.count > limit {
            projects.removeLast(projects.count - limit)
        }
        save()
    }

    func remove(_ project: RecentProject) {
        projects.removeAll { $0.id == project.id }
        save()
    }

    func relocate(_ project: RecentProject, to url: URL, name: String) {
        remove(project)
        record(url: url, name: name)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        do {
            projects = try JSONDecoder().decode([RecentProject].self, from: data)
        } catch {
            UserDefaults.standard.removeObject(forKey: key)
            AppLogger.log(.warning, category: "projects", "Discarded unreadable recent-project index: \(error.localizedDescription)")
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(projects)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            AppLogger.log(.error, category: "projects", "Could not persist recent-project index: \(error.localizedDescription)")
        }
    }
}

private struct CapabilityDetail: Identifiable {
    let id: String
    let icon: String
    let title: (String, String)
    let cardSummary: (String, String)
    let tags: [(String, String)]
    let value: (String, String)
    let detailIntro: (String, String)
    let headline: (String, String)
    let body: [(String, String)]
    let emphasis: (String, String)
    let abilities: [CapabilityAbility]
    let workflow: [(String, String)]
    let supportStatuses: [CapabilitySupportStatus]
    let closing: (String, String)

    init(
        id: String,
        icon: String,
        title: (String, String),
        cardSummary: (String, String),
        tags: [(String, String)] = [],
        value: (String, String),
        detailIntro: (String, String),
        headline: (String, String),
        body: [(String, String)],
        emphasis: (String, String),
        abilities: [CapabilityAbility],
        workflow: [(String, String)],
        supportStatuses: [CapabilitySupportStatus],
        closing: (String, String)
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.cardSummary = cardSummary
        self.tags = tags
        self.value = value
        self.detailIntro = detailIntro
        self.headline = headline
        self.body = body
        self.emphasis = emphasis
        self.abilities = abilities
        self.workflow = workflow
        self.supportStatuses = supportStatuses
        self.closing = closing
    }

    init(
        id: String,
        icon: String,
        title: (String, String),
        summary: (String, String),
        headline: (String, String),
        body: [(String, String)],
        emphasis: (String, String),
        coreAbilities: [(String, String)]
    ) {
        self.init(
            id: id,
            icon: icon,
            title: title,
            cardSummary: summary,
            tags: [],
            value: emphasis,
            detailIntro: summary,
            headline: headline,
            body: body,
            emphasis: emphasis,
            abilities: coreAbilities.enumerated().map { index, item in
                CapabilityAbility(title: ("能力 \(index + 1)", "Capability \(index + 1)"), text: item)
            },
            workflow: [],
            supportStatuses: [],
            closing: emphasis
        )
    }
}

private struct CapabilityAbility: Identifiable {
    var id: String { title.1 }
    let title: (String, String)
    let text: (String, String)
}

private struct CapabilitySupportStatus: Identifiable {
    var id: String { name.1 }
    let name: (String, String)
    let status: (String, String)
}

struct ProjectManagerView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @ObservedObject var store: ScriptLogStore
    @ObservedObject var recentProjects: RecentProjectStore
    let enterWorkspace: (Workspace) -> Void
    let showSupport: () -> Void
    var openNewProjectOnAppear: Bool = false
    var newProjectRequestID: UUID? = nil

    @State private var selectedCapability: CapabilityDetail?
    @State private var isNewProjectSheetPresented = false
    @State private var isSupportPresented = false
    @State private var didHandleInitialNewProject = false
    @State private var hoveredCapabilityID: String?
    @State private var hoveredActionID: String?
    @State private var hoveredRecentProjectID: String?

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private var reducesMotion: Bool { systemReduceMotion || settings.settings.general.reduceMotion }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                quickStart
                recentProjectsSection
                if settings.settings.general.showProjectManagerCapabilities {
                    capabilitiesSection
                }
                resourcesSection
            }
            .padding(.horizontal, 42)
            .padding(.vertical, 34)
            .frame(maxWidth: 1120, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surfaceBg)
        .sheet(item: $selectedCapability) { detail in
            CapabilityDetailView(detail: detail)
                .environmentObject(settings)
                .environment(\.appTheme, settings.settings.general.theme)
                .tint(colors.accent)
        }
        .sheet(isPresented: $isSupportPresented) {
            SupportView()
                .environmentObject(settings)
                .environment(\.appTheme, settings.settings.general.theme)
                .tint(colors.accent)
        }
        .sheet(isPresented: $isNewProjectSheetPresented) {
            NewProjectSheet { name, folder in
                if store.createNewProject(name: name, folderURL: folder) {
                    recentProjects.record(url: store.projectFolderURL, name: LocalizedDisplay.projectName(store.project, language: lang))
                    isNewProjectSheetPresented = false
                    enterWorkspace(.project)
                }
            }
            .environmentObject(settings)
            .environment(\.appTheme, settings.settings.general.theme)
            .tint(colors.accent)
        }
        .onAppear {
            guard openNewProjectOnAppear, !didHandleInitialNewProject else { return }
            didHandleInitialNewProject = true
            isNewProjectSheetPresented = true
        }
        .onChange(of: newProjectRequestID) { _ in
            isNewProjectSheetPresented = true
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            AppLogo(size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text("321Doit")
                    .font(.system(size: 28, weight: .semibold))
                Text(L10n.t("项目资料与拍摄上下文管理",
                            "Project metadata and production context",
                            language: lang))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            settingsMenu
        }
    }

    private var settingsMenu: some View {
        LanguagePopUpButton(
            selection: settings.binding(\.general.language),
            resolvedLanguage: lang
        )
        .fixedSize()
    }

    private var quickStart: some View {
        section(title: L10n.t("快速开始", "Quick Start", language: lang)) {
            HStack(spacing: 12) {
                managerActionCard(
                    id: "new",
                    icon: "plus.square",
                    title: L10n.t("新建项目", "New Project", language: lang),
                    subtitle: L10n.t("从空白场记和项目配置开始。", "Start with a clean project and script log.", language: lang),
                    prominent: true
                ) {
                    isNewProjectSheetPresented = true
                }
                managerActionCard(
                    id: "open",
                    icon: "folder",
                    title: L10n.t("打开现有项目", "Open Existing Project", language: lang),
                    subtitle: L10n.t("打开已有的 321Doit 项目文件夹。", "Open an existing 321Doit project folder.", language: lang),
                    prominent: false
                ) {
                    if store.openProject() {
                        recentProjects.record(url: store.projectFolderURL, name: LocalizedDisplay.projectName(store.project, language: lang))
                        enterWorkspace(.project)
                    }
                }
            }
        }
    }

    private var recentProjectsSection: some View {
        section(title: L10n.t("最近项目", "Recent Projects", language: lang)) {
            if recentProjects.projects.isEmpty {
                Text(L10n.t("还没有最近项目。新建或打开项目后会显示在这里。",
                            "No recent projects yet. New and opened projects will appear here.",
                            language: lang))
                    .font(.system(size: 12))
                    .foregroundStyle(colors.textSecondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .doitSurface(
                        colors: colors,
                        cornerRadius: DoitVisual.radiusControl,
                        elevation: .inset
                    )
            } else {
                VStack(spacing: 8) {
                    ForEach(recentProjects.projects) { project in
                        recentProjectRow(project)
                    }
                }
            }
        }
    }

    private var capabilitiesSection: some View {
        section(title: L10n.t("核心功能介绍", "Core Features", language: lang)) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 10)], spacing: 10) {
                    ForEach(capabilities) { detail in
                        capability(detail)
                    }
                }
                Text(L10n.t("321Doit 把拍摄日、片场下卡、场记、摄影机卡管理、代理转码与后期交接放在同一个项目里。",
                            "321Doit keeps shooting days, on-set offload, script logging, camera-card management, proxy transcode, and post handoff in one project.",
                            language: lang))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }

    private var capabilities: [CapabilityDetail] {
        latestCapabilities
    }

    private var latestCapabilities: [CapabilityDetail] {
        [
            CapabilityDetail(
                id: "shooting-day",
                icon: "calendar",
                title: ("拍摄日", "Shooting Day"),
                cardSummary: ("以日历管理每日通告，并连接场记、卡号与后期交接。",
                              "Manage daily call sheets in a calendar connected to script logs, cards, and handoff."),
                tags: [("通告单", "Call sheet"), ("日历", "Calendar"), ("检查", "Preflight")],
                value: ("让每天拍什么、谁到场、怎么下卡和怎么交接都进入同一条项目链路。",
                        "Keep what shoots each day, who is called, how cards are offloaded, and how post receives it in one chain."),
                detailIntro: ("用拍摄日历和单日工作台组织每日通告、场次计划、演员部门、摄影机卡号与 DIT 交接要求。",
                              "Use a shooting calendar and day workspace for call sheets, scene plans, cast and departments, camera cards, and DIT handoff."),
                headline: ("让每个拍摄日都有一个清晰的工作台", "A Clear Workspace for Every Shoot Day"),
                body: [
                    ("拍摄日模块把拍摄日编号、自然日期、单日通告、今日场次、演员与部门、地点安全、摄影机卡号计划和 DIT 交接集中在同一个工作台里。它让全组围绕同一天的数据协作，而不是各自维护分散的表格。每天开工前，制片、导演组、场记、DIT 和后期都能清楚看到今天要拍什么、哪些信息还缺失，以及后期需要接收到什么。",
                     "The Shoot Day module brings the shooting day number, calendar date, daily call sheet, today’s scenes, cast and departments, location safety, camera card planning, and DIT handoff into one shared workspace. It helps the crew work around the same day-level data instead of maintaining separate spreadsheets. Before call time, production, the AD team, script supervisor, DIT, and post-production can all see what is being shot today, what information is still missing, and what needs to be handed off to post.")
                ],
                emphasis: ("每天开工前，项目应该已经知道今天要拍什么、哪些信息缺失、后期需要接到什么。",
                           "Before call time, the project should already know what shoots today, what is missing, and what post needs."),
                abilities: [
                    CapabilityAbility(title: ("拍摄日历", "Shooting Calendar"), text: ("用 D01 / D02 与自然日期双系统管理项目节奏。", "Manage project rhythm with both D-codes and calendar dates.")),
                    CapabilityAbility(title: ("单日工作台", "Day Workspace"), text: ("集中编辑总览、时间安排、今日场次、演员部门和地点安全。", "Edit overview, schedule, scenes, cast, departments, and safety in one place.")),
                    CapabilityAbility(title: ("摄影机卡计划", "Camera Card Plan"), text: ("把机位、摄影机、格式和预计卡号提前纳入通告。", "Plan units, cameras, formats, and expected cards before shooting.")),
                    CapabilityAbility(title: ("发布前检查", "Preflight Checks"), text: ("导出前检查全组到场、地点、场次、紧急联系人和 DIT 设置。", "Check crew call, locations, scenes, emergency contacts, and DIT settings before export.")),
                    CapabilityAbility(title: ("场记联动", "Script Log Link"), text: ("从场记导入场次，也可以把今日场次推送到场记。", "Import scenes from Script Log or push today's plan back to Script Log.")),
                    CapabilityAbility(title: ("通告导出", "Call Sheet Export"), text: ("MVP 支持 HTML 预览与 JSON 数据，PDF 正式版正在适配。", "MVP supports HTML preview and JSON data; formal PDF is being adapted."))
                ],
                workflow: [("拍摄日历", "Calendar"), ("单日工作台", "Day Workspace"), ("发布前检查", "Preflight"), ("导出通告", "Export Call Sheet"), ("进入场记", "Open Script Log"), ("后期交接", "Post Handoff")],
                supportStatuses: [],
                closing: ("321Doit 要让每日通告从一张通知表，变成片场当天所有数据流转的入口。",
                          "321Doit turns the daily call sheet from a notice into the entry point for the day's production data.")
            ),
            CapabilityDetail(
                id: "dit-offload",
                icon: "externaldrive.badge.checkmark",
                title: ("DIT 下卡", "DIT Offload"),
                cardSummary: ("高速多目标拷贝、校验与报告生成。",
                              "High-speed multi-destination copy, verification, and reports."),
                tags: [("多盘备份", "Multi-drive"), ("校验报告", "Verify reports"), ("MHL", "MHL")],
                value: ("把片场最不能出错的一步，变成可验证、可交接的安全链路。",
                        "Turn the most critical on-set step into a verifiable, handoff-ready safety chain."),
                detailIntro: ("高性能拷贝、预检、校验、续传与报告生成，把片场素材落地变成一条可追踪的安全链路。",
                              "High-performance copy, preflight, verification, resume, and reporting for a traceable on-set media chain."),
                headline: ("从 Finder 到 Minder", "From Finder to Minder"),
                body: [
                    ("DIT 下卡模块是一套为片场素材安全设计的高性能下卡系统。它支持多目标盘并行写入，下卡前自动完成容量、权限、重名、系统盘风险和文件系统限制等预检，并在拷贝过程中进行逐文件校验。",
                     "The DIT Offload module is not just a file copier. It is a high-performance offload system designed for on-set media safety. It supports parallel copying to multiple destination drives, runs preflight checks for capacity, permissions, duplicate names, system-drive risks, and filesystem limitations before the transfer begins, and verifies every file during the copy process."),
                    ("你可以根据项目需求选择 xxHash64、MD5、SHA-1 或 SHA-256 等校验算法，自动生成 MHL、PDF、CSV、JSON、TXT 等交接报告。每一张卡的来源、去向、文件数量、校验结果和异常信息，都可以被清楚记录、追踪和交接。",
                     "Depending on the project’s needs, you can choose checksum algorithms such as xxHash64, MD5, SHA-1, or SHA-256, and automatically generate handoff reports in MHL, PDF, CSV, JSON, and TXT formats. Every card’s source, destination, file count, verification result, and exception record can be clearly documented, traced, and handed off.")
                ],
                emphasis: ("每一次下卡，都应该知道素材从哪里来、去了哪里、是否完整、是否可信。",
                           "Every offload should make it clear where media came from, where it went, and whether it is complete and trustworthy."),
                abilities: [
                    CapabilityAbility(title: ("高性能多目标下卡", "High-Performance Multi-Destination Offload"), text: ("可同时写入主盘、备份盘和交接盘，适合多硬盘、多人员交接的片场环境。", "Write to master, backup, and handoff drives at the same time for real set handoffs.")),
                    CapabilityAbility(title: ("多重安全校验", "Layered Verification"), text: ("支持 xxHash64、MD5、SHA-1、SHA-256 等校验算法，拷贝完成后逐文件验证。", "Use xxHash64, MD5, SHA-1, SHA-256 and per-file verification after copy.")),
                    CapabilityAbility(title: ("下卡前风险预检", "Preflight Risk Check"), text: ("提前检查容量、权限、重名、系统盘、文件系统限制等风险，尽量把问题挡在开始之前。", "Check capacity, permissions, duplicates, system-disk risk, and filesystem limits before starting.")),
                    CapabilityAbility(title: ("中断续传与恢复", "Resume & Recovery"), text: ("任务中断后可继续，不必从头重来，适合真实片场里的突发情况。", "Continue interrupted jobs instead of restarting from zero.")),
                    CapabilityAbility(title: ("自动报告生成", "Automatic Reports"), text: ("自动输出 MHL、PDF、CSV、JSON、TXT 等报告，方便交接、归档和追责。", "Generate MHL, PDF, CSV, JSON, TXT and other handoff reports.")),
                    CapabilityAbility(title: ("完整证据链", "Complete Evidence Chain"), text: ("记录源卡、目标盘、文件数量、校验结果、时间与异常信息，让素材流转有据可查。", "Record source cards, destinations, file counts, verification results, time, and exceptions."))
                ],
                workflow: [("插卡识别", "Card Detection"), ("风险预检", "Preflight"), ("多目标拷贝", "Multi-Destination Copy"), ("逐文件校验", "Per-File Verify"), ("报告生成", "Reports"), ("后期交接", "Post Handoff")],
                supportStatuses: [],
                closing: ("321Doit 不是帮你“拷一下文件”，而是帮你把片场最不能出错的一步变成可靠流程。",
                          "321Doit does not just copy files; it turns the set's most fragile step into a reliable workflow.")
            ),
            CapabilityDetail(
                id: "script-log",
                icon: "list.clipboard",
                title: ("场记", "Script Log"),
                cardSummary: ("用快捷键快速记录场、镜、条次、机位与好条。",
                              "Use shortcuts to quickly log scenes, shots, takes, cameras, and selects."),
                tags: [("多机位", "Multi-camera"), ("快捷记录", "Fast logging"), ("元数据", "Metadata")],
                value: ("让现场判断直接进入后期，而不是停在一张表里。",
                        "Move on-set decisions directly into post instead of trapping them in a sheet."),
                detailIntro: ("用快捷键高速记录拍摄信息，把现场判断变成后期可以读取、筛选和导入的数据。",
                              "Fast shortcut logging that turns on-set decisions into data post can read, filter, and import."),
                headline: ("让场记更常记", "Script Notes That Stick"),
                body: [
                    ("不是把纸质场记单搬到屏幕上，而是一套面向真实片场的高速记录系统。通过快捷键、快速递增、智能继承和多机位联动，场次、镜号、条次、好坏、备注、时间码与素材关系，都能在几秒内记录成结构化数据。从现场记录完成的那一刻生成后期可见、可识别、可筛选、可导入的信息。",
                     "More than a paper script sheet moved onto a screen, this is a high-speed logging system built for real sets. With keyboard shortcuts, quick increments, smart inheritance, and multi-camera linking, scenes, shots, takes, camera positions, circled takes, bad takes, notes, timecode, and media relationships can all be captured as structured data in seconds. The moment a record is completed on set, post-production already has information that is identifiable, filterable, and ready to import.")
                ],
                emphasis: ("现场记录完成的那一刻，后期就已经拿到了可识别、可筛选、可导入的信息。",
                           "The moment logging is done on set, post already has data it can recognize, filter, and import."),
                abilities: [
                    CapabilityAbility(title: ("高速快捷键记录", "High-Speed Shortcuts"), text: ("快速推进场次、镜号、条次和机位，比传统手填场记更快。", "Advance scenes, shots, takes, and cameras faster than manual logging.")),
                    CapabilityAbility(title: ("多机位联动", "Multi-Camera Linking"), text: ("A/B/C 机共享同一条拍摄信息，不需要重复填写同一条内容。", "A/B/C cameras share the same take context without repeated entry.")),
                    CapabilityAbility(title: ("智能继承", "Smart Inheritance"), text: ("上一条的场次、镜号、机位和备注规则可自动继承，减少重复操作。", "Inherit scene, shot, camera, and note rules from the previous take.")),
                    CapabilityAbility(title: ("好条快速标记", "Fast Select Marking"), text: ("快速标记好条、坏条、保留条、假开机、NG、环条等现场状态。", "Mark selects, rejects, keep takes, false starts, NG, circle takes, and more.")),
                    CapabilityAbility(title: ("备注结构化", "Structured Notes"), text: ("表演、焦点、构图、声音、穿帮、导演意见等信息不再只是文字，而是可整理的数据。", "Performance, focus, framing, sound, continuity, and director notes become structured data.")),
                    CapabilityAbility(title: ("写入后期元数据", "Post Metadata"), text: ("场记信息可进入项目元数据，并随素材、代理和交接包进入后期流程。", "Script log data can travel with media, proxies, and handoff packages into post."))
                ],
                workflow: [("现场记录", "On-Set Log"), ("关联素材", "Link Media"), ("写入元数据", "Write Metadata"), ("导入后期", "Import to Post"), ("筛选好条", "Filter Selects")],
                supportStatuses: [
                    CapabilitySupportStatus(name: ("Final Cut Pro", "Final Cut Pro"), status: ("优先适配一键导入与元数据映射", "Priority support for one-click import and metadata mapping")),
                    CapabilitySupportStatus(name: ("DaVinci Resolve", "DaVinci Resolve"), status: ("优先适配场记信息导入与素材备注", "Priority support for script log import and clip notes")),
                    CapabilitySupportStatus(name: ("Premiere Pro", "Premiere Pro"), status: ("规划中", "Planned")),
                    CapabilitySupportStatus(name: ("剪映专业版", "Jianying Pro"), status: ("规划中", "Planned")),
                    CapabilitySupportStatus(name: ("Avid Media Composer", "Avid Media Composer"), status: ("规划中", "Planned"))
                ],
                closing: ("321Doit 要解决的不是“怎么填一张场记表”，而是让现场记录真正进入后期工作流。",
                          "321Doit is not about filling a log sheet; it is about getting on-set records into the post workflow.")
            ),
            CapabilityDetail(
                id: "camera-card-management",
                icon: "camera.aperture",
                title: ("摄影机卡管理", "Camera Card Management"),
                cardSummary: ("统一管理卡号、卷名、设备类型与下卡状态。",
                              "Manage card IDs, volume names, device types, and offload status."),
                tags: [("卡号追踪", "Card tracking"), ("卷名识别", "Volume ID"), ("风险检查", "Risk check")],
                value: ("把不同设备、不同卡号、不同卷名统一到项目级管理。",
                        "Unify devices, card IDs, and volume names inside project-level management."),
                detailIntro: ("识别卡号、卷名、设备类型和素材结构，把微单与电影机流程统一到同一套管理系统里。",
                              "Recognize card IDs, volume names, device types, and media structures in one management system."),
                headline: ("给你的摄影卡办张身份证", "Every Card Has an Identity"),
                body: [
                    ("摄影机卡管理用于统一登记和追踪项目中的所有素材卡。它可以记录卡号、卷名、设备类型、素材结构、下卡历史和人工备注，把微单、电影机、多机位和不同格式的素材卡纳入同一套管理逻辑。",
                     "Register card IDs, volume names, device types, media structure, and offload history in one place."),
                    ("每张卡不再只是一个卷名或盘符，而是拥有清楚的身份记录：它属于哪台设备、对应哪个项目、是否已经下卡、是否存在重复、遗漏或命名风险。无论是前期拍摄、DIT 下卡，还是后期交接，都可以围绕同一套摄影机卡信息工作，减少靠记忆、口头确认和临时表格带来的混乱。",
                     "Every card becomes traceable, from source and project ownership to offload status, duplicates, missing records, and naming risks.")
                ],
                emphasis: ("微单流程、电影机流程、多机位流程，都应该被统一管理，而不是靠人脑记忆。",
                           "Mirrorless, cinema-camera, and multi-camera workflows should be managed by one system, not memory."),
                abilities: [
                    CapabilityAbility(title: ("多设备融合", "Multi-Device Fusion"), text: ("支持微单、电影机、运动相机、录机、无人机与多机位混合素材管理。", "Manage mirrorless, cinema, action, recorder, drone, and multi-camera media.")),
                    CapabilityAbility(title: ("自动识别结构", "Structure Recognition"), text: ("识别 Sony、Canon、RED、ARRI、Blackmagic、GoPro、Panasonic 等常见设备素材结构。", "Recognize common Sony, Canon, RED, ARRI, Blackmagic, GoPro, and Panasonic media structures.")),
                    CapabilityAbility(title: ("卡号同步管理", "Card ID Sync"), text: ("同步管理卡号、卷名、设备类型、项目归属与下卡状态。", "Track card ID, volume name, device type, project ownership, and offload status.")),
                    CapabilityAbility(title: ("防止素材混乱", "Reduce Media Chaos"), text: ("降低漏拷、重复拷、误格式化、卡号混乱和同名卷风险。", "Reduce missed copies, duplicate copies, accidental formatting, card chaos, and duplicate volume risk.")),
                    CapabilityAbility(title: ("连接 DIT 流程", "Connected DIT Flow"), text: ("卡号可以与下卡记录、校验报告、场记信息和代理文件联动。", "Link card IDs with offload records, verification reports, script logs, and proxies.")),
                    CapabilityAbility(title: ("完整流转记录", "Lifecycle Trace"), text: ("每张卡从插入、识别、下卡、校验到交接都可以留下轨迹。", "Trace each card from insertion and recognition to offload, verification, and handoff."))
                ],
                workflow: [("插入摄影机卡", "Insert Card"), ("识别设备与素材结构", "Identify Device & Media"), ("绑定卡号、卷名与项目", "Bind Card, Volume & Project"), ("执行下卡与校验", "Offload & Verify"), ("生成记录与报告", "Write Records & Reports"), ("交接到后期", "Post Handoff")],
                supportStatuses: [],
                closing: ("321Doit 不只是管理文件夹，而是管理每一张卡在整个项目里的生命轨迹。",
                          "321Doit does not just manage folders; it manages each card's full project lifecycle.")
            ),
            CapabilityDetail(
                id: "proxy-transcode",
                icon: "film.stack",
                title: ("代理与转码", "Proxy & Transcode"),
                cardSummary: ("生成 H.264 / H.265 / ProRes 代理，支持 LUT 烘焙，并可在后期软件中一键链接。",
                              "Generate H.264 / H.265 / ProRes proxies, support LUT bake-in, and prepare one-click relinking for post."),
                tags: [("代理文件", "Proxies"), ("LUT", "LUT"), ("FCP & Resolve", "FCP & Resolve")],
                value: ("让代理从生成那一刻起，就为剪辑、审片和交接服务。",
                        "Make proxies serve editorial, review, and handoff from the moment they are created."),
                detailIntro: ("下卡后直接生成剪辑代理、审片版本和 LUT 预览，让后期软件可以更快链接和使用。",
                              "Generate editorial proxies, review versions, and LUT previews after offload for faster post linking."),
                headline: ("下卡即开剪", "From Card to Cut"),
                body: [
                    ("下卡后即可生成 H.264、H.265 或 ProRes 代理，支持 LUT 烧录或保留干净版本，并保持代理与原素材的对应关系。素材、代理、场记和交接数据可以一起进入 Final Cut Pro 与 DaVinci Resolve，让后期不用重新整理，也不用再猜哪条对应哪条。",
                     "Generate H.264, H.265, or ProRes proxies right after offload, with baked LUTs or clean versions. Proxies stay linked to the original media and are prepared for Final Cut Pro and DaVinci Resolve, so media, notes, and handoff data move into post together.")
                ],
                emphasis: ("这不是“转一个小文件看看”，而是直接把后期代理工作流准备好。",
                           "This is not making a smaller file to preview; it prepares the proxy workflow for post."),
                abilities: [
                    CapabilityAbility(title: ("多格式代理", "Multi-Format Proxy"), text: ("支持 H.264、H.265、ProRes 等常见代理与转码格式。", "Support H.264, H.265, ProRes and other common proxy formats.")),
                    CapabilityAbility(title: ("LUT 烘焙", "LUT Bake-In"), text: ("可生成带 LUT 的导演预览、客户样片和现场审片版本。", "Generate LUT-baked director, client, and on-set review versions.")),
                    CapabilityAbility(title: ("干净剪辑代理", "Clean Editorial Proxy"), text: ("可保留无 LUT 代理，方便剪辑与调色保持专业流程。", "Keep no-LUT proxies for editorial and color-safe post workflows.")),
                    CapabilityAbility(title: ("一键链接准备", "One-Click Linking Prep"), text: ("代理文件与原始素材保持对应关系，方便后期软件一键链接。", "Maintain original/proxy relationships for easier one-click linking.")),
                    CapabilityAbility(title: ("后期软件优先适配", "Post Software Priority"), text: ("面向 Final Cut Pro 和 DaVinci Resolve 的代理识别与链接流程设计。", "Designed around Final Cut Pro and DaVinci Resolve proxy linking flows.")),
                    CapabilityAbility(title: ("硬件加速路径", "Hardware Acceleration Path"), text: ("H.264 / H.265 可走硬件加速，ProRes 可根据情况走系统或 FFmpeg 路径。", "H.264 / H.265 can use hardware paths; ProRes can use system or FFmpeg paths as appropriate."))
                ],
                workflow: [("原始素材", "Original Media"), ("生成代理", "Generate Proxy"), ("LUT 预览", "LUT Preview"), ("保持对应关系", "Keep Link"), ("后期一键链接", "One-Click Link"), ("剪辑开工", "Editorial Starts")],
                supportStatuses: [
                    CapabilitySupportStatus(name: ("Final Cut Pro", "Final Cut Pro"), status: ("重点支持代理链接与导入工作流", "Priority support for proxy linking and import workflow")),
                    CapabilitySupportStatus(name: ("DaVinci Resolve", "DaVinci Resolve"), status: ("重点支持代理链接与素材交接工作流", "Priority support for proxy linking and media handoff workflow")),
                    CapabilitySupportStatus(name: ("Premiere Pro", "Premiere Pro"), status: ("规划中", "Planned")),
                    CapabilitySupportStatus(name: ("剪映专业版", "Jianying Pro"), status: ("规划中", "Planned")),
                    CapabilitySupportStatus(name: ("Avid Media Composer", "Avid Media Composer"), status: ("规划中", "Planned"))
                ],
                closing: ("321Doit 要做的不是单纯转码，而是让代理从生成那一刻起就能服务后期。",
                          "321Doit is not just transcoding; it makes proxies useful to post from the moment they are created.")
            ),
            CapabilityDetail(
                id: "post-handoff",
                icon: "shippingbox",
                title: ("后期交接", "Post Handoff"),
                cardSummary: ("打包素材、代理、场记、报告与项目索引，交给剪辑可直接接上。",
                              "Package media, proxies, script logs, reports, and project indexes for editorial."),
                tags: [("交接包", "Handoff"), ("索引文件", "Index"), ("一键导入", "One-click import")],
                value: ("把一块硬盘交接，升级成完整项目上下文交接。",
                        "Upgrade drive delivery into complete project-context handoff."),
                detailIntro: ("把原始素材、代理文件、场记信息、摄影机卡记录和校验报告整理成后期可直接接手的交接包。",
                              "Package originals, proxies, script logs, card records, and verification reports for post takeover."),
                headline: ("对你的剪辑好点", "No More Sorting Footage"),
                body: [
                    ("把原始素材、代理文件、场记信息、摄影机卡记录和校验报告整理成清晰的后期交接包。素材可按场次、镜号、条次和好坏条分类，剪辑不用再翻场记单、对聊天记录或手动整理文件夹，就能直接看到哪些是 OK 条、NG 条、保留条，以及每条素材对应的上下文。",
                     "Turn media, proxies, script notes, card records, and reports into a clean handoff. Editors can see scenes, takes, OK / NG status, and context directly in Final Cut Pro or DaVinci Resolve."),
                    ("交接数据可进入 Final Cut Pro、DaVinci Resolve 等后期流程，让素材、代理、场记判断和卡号记录一起被剪辑软件识别。Avid、Premiere Pro、剪映 / CapCut 以及更多剪辑软件的生态兼容也在规划中，目标是让后期拿到的不是一块硬盘，而是一个已经整理好的项目入口。",
                     "Avid, Premiere Pro, CapCut, and more workflows are planned.")
                ],
                emphasis: ("321Doit 的目标是让后期接到的不只是一块硬盘，而是一个已经整理好的项目上下文。",
                           "321Doit aims to hand post not just a drive, but an organized project context."),
                abilities: [
                    CapabilityAbility(title: ("一键交接包", "One-Click Handoff Package"), text: ("一键生成面向后期的完整交接结构，减少人工整理成本。", "Generate a complete post-facing handoff structure in one step.")),
                    CapabilityAbility(title: ("素材与代理同交接", "Media & Proxy Together"), text: ("原始素材、代理文件和对应关系一起交付，减少后期重新链接。", "Deliver originals, proxies, and relationships together to reduce relinking.")),
                    CapabilityAbility(title: ("场记信息随片走", "Script Log Travels With Media"), text: ("场次、镜号、条次、好条、备注等信息可随交接包进入后期。", "Scene, shot, take, select, and note data can travel into post.")),
                    CapabilityAbility(title: ("卡号记录可追踪", "Traceable Card Records"), text: ("摄影机卡、卷名、设备和下卡记录一起进入项目交接链路。", "Camera cards, volume names, devices, and offload records enter the handoff chain.")),
                    CapabilityAbility(title: ("校验报告随附", "Verification Reports Included"), text: ("MHL、PDF、CSV、JSON 等报告可随交接包归档和确认。", "MHL, PDF, CSV, JSON and other reports can be archived with the package.")),
                    CapabilityAbility(title: ("后期软件导入", "Post Software Import"), text: ("重点面向 Final Cut Pro 和 DaVinci Resolve 的一键导入与交接流程。", "Focused on one-click import and handoff flows for Final Cut Pro and DaVinci Resolve."))
                ],
                workflow: [("整理素材", "Organize Media"), ("匹配代理", "Match Proxies"), ("合并场记", "Merge Script Log"), ("附带报告", "Attach Reports"), ("一键导入", "One-Click Import"), ("后期接手", "Post Takes Over")],
                supportStatuses: [
                    CapabilitySupportStatus(name: ("Final Cut Pro", "Final Cut Pro"), status: ("重点支持一键导入、代理链接和元数据交接", "Priority support for one-click import, proxy linking, and metadata handoff")),
                    CapabilitySupportStatus(name: ("DaVinci Resolve", "DaVinci Resolve"), status: ("重点支持素材交接、场记导入和代理链接", "Priority support for media handoff, script log import, and proxy linking")),
                    CapabilitySupportStatus(name: ("Premiere Pro", "Premiere Pro"), status: ("正在规划追加", "Planned")),
                    CapabilitySupportStatus(name: ("剪映专业版", "Jianying Pro"), status: ("正在规划追加", "Planned")),
                    CapabilitySupportStatus(name: ("Avid Media Composer", "Avid Media Composer"), status: ("正在规划追加", "Planned"))
                ],
                closing: ("321Doit 要让片场交给后期的，不是一堆文件，而是一套可以直接工作的项目结构。",
                          "321Doit makes the handoff not a pile of files, but a project structure post can start working with.")
            ),
            CapabilityDetail(
                id: "reports-traceability",
                icon: "doc.text.magnifyingglass",
                title: ("报告与追踪", "Reports & Traceability"),
                cardSummary: ("自动保存拷卡、校验、场记、卡号与交接记录。",
                              "Automatically preserve offload, verification, script log, card, and handoff records."),
                tags: [("可追溯", "Traceable"), ("PDF", "PDF"), ("CSV", "CSV")],
                value: ("让素材管理不再靠“应该没问题”，而是靠可验证记录。",
                        "Replace “it should be fine” with verifiable records."),
                detailIntro: ("记录每一次下卡、校验、续传、代理、场记和交接操作，让项目从现场到后期都可追踪。",
                              "Record offload, verification, resume, proxy, script log, and handoff operations from set to post."),
                headline: ("工作留痕，无惧甩锅", "Trace It. Prove It."),
                body: [
                    ("记录每一次下卡、校验、续传、代理、场记和交接操作，自动生成 MHL、PDF、CSV、JSON、TXT 等报告。源卡、目标盘、文件数量、校验算法、校验结果、异常信息、卡号记录和场记判断都能被追踪。",
                     "Log every offload, checksum, proxy, script note, card record, and handoff."),
                    ("素材有没有拷完、哪块盘是主盘、哪条是 OK 条、代理是否对应原片、哪里出现过警告，都不再靠聊天记录和口头解释。项目从现场到后期，每一步都有据可查。",
                     "Generate MHL, PDF, CSV, JSON, and TXT reports so every media move stays traceable, verifiable, and ready for post.")
                ],
                emphasis: ("素材从摄影机出来之后，每一步都应该有记录。",
                           "After media leaves the camera, every step should have a record."),
                abilities: [
                    CapabilityAbility(title: ("下卡记录", "Offload Records"), text: ("保存源卡、目标盘、文件数量、容量、时间和任务状态。", "Save source cards, destinations, file counts, capacity, time, and task status.")),
                    CapabilityAbility(title: ("校验证据", "Verification Evidence"), text: ("记录校验算法、校验结果、失败文件和异常信息。", "Record verification algorithms, results, failed files, and exceptions.")),
                    CapabilityAbility(title: ("场记追踪", "Script Log Trace"), text: ("保留场次、镜号、条次、机位、好条、备注和现场判断。", "Keep scene, shot, take, camera, select, note, and on-set decisions.")),
                    CapabilityAbility(title: ("卡号追踪", "Card Trace"), text: ("记录摄影机卡、卷名、设备结构、项目归属和流转状态。", "Track camera cards, volume names, device structures, project ownership, and flow status.")),
                    CapabilityAbility(title: ("交接报告", "Handoff Reports"), text: ("自动生成 MHL、PDF、CSV、JSON、TXT 等多种交接与归档格式。", "Generate MHL, PDF, CSV, JSON, TXT and other handoff/archive formats.")),
                    CapabilityAbility(title: ("诊断信息", "Diagnostics"), text: ("记录错误、警告、权限、磁盘和文件系统问题，方便后续排查。", "Record errors, warnings, permissions, disk, and filesystem issues for later diagnosis."))
                ],
                workflow: [("现场产生素材", "Media Created"), ("下卡校验", "Offload & Verify"), ("生成代理", "Generate Proxy"), ("记录场记", "Record Script Log"), ("后期交接", "Post Handoff"), ("项目归档", "Archive")],
                supportStatuses: [],
                closing: ("321Doit 让素材管理不再靠“应该没问题”，而是靠清楚、完整、可验证的记录。",
                          "321Doit replaces “it should be fine” with clear, complete, verifiable records.")
            )
        ]
    }

    private var legacyCapabilities: [CapabilityDetail] {
        [
            CapabilityDetail(
                id: "dit-offload",
                icon: "externaldrive.badge.checkmark",
                title: ("DIT 下卡", "DIT Offload"),
                summary: ("超高性能多目标下卡，多重安全校验，自动生成 MHL / PDF / CSV / JSON 报告。",
                          "High-performance multi-destination offload, layered safety checks, and automatic MHL / PDF / CSV / JSON reports."),
                headline: ("把 Finder 拷卡时代结束掉。", "End the Finder copy era."),
                body: [
                    ("321Doit 的 DIT 下卡不是简单复制文件，而是一套为片场素材安全设计的高性能下卡系统。它可以在多块目标盘之间并行写入，自动完成预检、拷贝、校验、续传和报告生成，把过去靠人工经验、截图和反复确认的流程，变成一条可验证、可追踪、可交接的安全链路。",
                     "321Doit DIT Offload is not a simple file copy. It is a high-performance offload system designed for on-set media safety. It can write to multiple destination drives in parallel, run preflight, copy, verify, resume, and generate reports automatically, turning a workflow that used to rely on memory, screenshots, and repeated manual checks into a verifiable, traceable handoff chain."),
                    ("从源卡读取、目标盘容量检查、文件系统限制、重名风险、系统盘风险，到拷贝后的逐文件校验，321Doit 会把每一步都记录下来。你不再需要凭感觉判断“应该拷好了”，而是可以明确知道：拷了什么、拷到哪里、校验是否通过、什么时候完成、有没有风险。",
                     "From source-card reading, destination capacity checks, filesystem limits, duplicate-name risk, and system-disk risk to per-file verification after copying, 321Doit records every step. You no longer have to guess that a copy is probably done; you can know exactly what was copied, where it went, whether verification passed, when it finished, and what risks were found.")
                ],
                emphasis: ("它适合真正高压的片场环境：多卡、多机、多硬盘、多人员交接、时间紧、不能错。",
                           "It is built for real high-pressure set conditions: many cards, many cameras, many drives, many handoffs, very little time, and no room for mistakes."),
                coreAbilities: [
                    ("超高性能多目标下卡，可同时写入主盘、备份盘和交接盘。", "High-performance multi-destination offload to master, backup, and handoff drives at the same time."),
                    ("多重安全校验，支持 xxHash64、MD5、SHA-1、SHA-256。", "Layered verification with xxHash64, MD5, SHA-1, and SHA-256."),
                    ("下卡前自动预检容量、权限、重名、系统盘、文件系统限制等风险。", "Automatic preflight for capacity, permissions, duplicate names, system-disk risk, filesystem limits, and more."),
                    ("支持续传与恢复，中断后不用从头再来。", "Resume and recovery support so interrupted jobs do not need to start over."),
                    ("自动生成 MHL、PDF、CSV、JSON、TXT 等交接报告。", "Automatic MHL, PDF, CSV, JSON, and TXT handoff reports."),
                    ("为后期、制片、DIT、剪辑提供完整素材证据链。", "A complete media evidence chain for post, production, DIT, and editorial.")
                ]
            ),
            CapabilityDetail(
                id: "script-log",
                icon: "list.clipboard",
                title: ("场记", "Script Log"),
                summary: ("用快捷键高速标记场次、镜号、条次、机位、好条与备注，并写入后期可用元数据。",
                          "Use shortcuts to rapidly mark scenes, shots, takes, cameras, selects, and notes as post-ready metadata."),
                headline: ("场记不应该只是填表，而应该直接变成后期能用的数据。", "Script logs should not just fill forms; they should become data post can use."),
                body: [
                    ("321Doit 的场记模块不是把传统纸质场记单搬到屏幕上，而是重新设计了一套更适合现代片场的高效记录方式。通过快捷键、快速递增、智能继承和结构化记录，你可以用极低操作成本完成场次、镜号、条次、机位、好条、坏条、备注、时间码和素材关系的标记。",
                     "321Doit Script Log is not a paper log sheet moved onto a screen. It redesigns logging for modern sets. With shortcuts, fast increments, smart inheritance, and structured records, you can mark scenes, shots, takes, cameras, selects, rejects, notes, timecode, and media relationships with very low operation cost."),
                    ("传统场记经常卡在重复填写、信息断层和后期无法使用上。321Doit 要解决的是：现场记录完，后期就能接着用。场记信息不再只是写在表格里，而是可以跟素材、卡号、代理和交接包关联，成为后期软件能够读取、筛选和理解的元数据。",
                     "Traditional script logs often get stuck in repeated typing, broken context, and data post cannot use. 321Doit is designed so that once the set record is complete, post can continue from it. Log information is no longer just text in a table; it can connect to media, card IDs, proxies, and handoff packages as metadata that post software can read, filter, and understand.")
                ],
                emphasis: ("拍摄现场越混乱，它越能把信息理清楚。",
                           "The more chaotic the set becomes, the more it helps keep the information clear."),
                coreAbilities: [
                    ("超高效快捷键记录，快速推进场次、镜号、条次和机位。", "High-speed shortcut logging for scenes, shots, takes, and cameras."),
                    ("支持好条、坏条、保留条、假开机、NG、环条等现场状态。", "Support selects, rejects, keep takes, false starts, NG, circle takes, and other on-set states."),
                    ("支持多机位记录，A/B/C 机不需要重复填写同一条信息。", "Multi-camera logging so A/B/C cameras do not require repeated entry of the same information."),
                    ("支持备注表演、焦点、构图、声音、穿帮、导演意见等关键信息。", "Notes for performance, focus, framing, sound, continuity issues, director comments, and other key details."),
                    ("场记信息可写入项目元数据，并跟素材、代理、卡号关联。", "Script log data can be written into project metadata and linked with media, proxies, and card IDs."),
                    ("后续可智能导入 Final Cut Pro、DaVinci Resolve 等后期软件。", "Future intelligent import into Final Cut Pro, DaVinci Resolve, and other post software."),
                    ("让“现场记了什么”和“后期看到什么”真正打通。", "Connect what was recorded on set with what post actually sees.")
                ]
            ),
            CapabilityDetail(
                id: "camera-card-management",
                icon: "camera.aperture",
                title: ("摄影机卡管理", "Camera Card Management"),
                summary: ("同步管理微单、电影机、录机和多机位卡号，让每一张卡都有身份和流转记录。",
                          "Manage mirrorless, cinema camera, recorder, and multi-camera cards so every card has identity and history."),
                headline: ("让微单流程和电影机流程，在同一个系统里被统一管理。", "Manage mirrorless and cinema-camera workflows inside one system."),
                body: [
                    ("现实片场并不总是纯电影机流程。很多小型剧组、广告组、纪录片团队会同时使用 Sony 微单、FX 系列、Canon、RED、ARRI、Blackmagic、GoPro、无人机、录机甚至手机素材。不同设备的卡结构、卷名规则和格式化习惯完全不同，这就是素材混乱的根源。",
                     "Real sets are not always pure cinema-camera workflows. Small crews, commercial teams, and documentary productions may use Sony mirrorless bodies, FX cameras, Canon, RED, ARRI, Blackmagic, GoPro, drones, external recorders, and even phone footage in the same project. Each device has different card structures, volume naming rules, and formatting habits, which is where media confusion starts."),
                    ("321Doit 的摄影机卡管理模块，会把卡号、卷名、设备类型、素材结构、下卡记录和项目关系统一管理。它不只看卷名，而是结合设备特征、文件结构、历史记录和人工卡号，帮助你判断这张卡是谁、来自哪里、有没有下过、是否重复、是否存在风险。",
                     "321Doit Camera Card Management brings card IDs, volume names, device types, media structures, offload records, and project relationships into one system. It does not only look at volume names; it combines device traits, folder structures, history, and manual card IDs to help identify whose card it is, where it came from, whether it has been copied, whether it is duplicated, and whether it carries risk.")
                ],
                emphasis: ("无论你是标准电影机流程，还是微单混合流程，321Doit 都能把它纳入同一套片场数据管理系统。",
                           "Whether the production uses a standard cinema workflow or a mixed mirrorless workflow, 321Doit brings it into one on-set data management system."),
                coreAbilities: [
                    ("支持微单、电影机、运动相机、录机、多机位混合素材管理。", "Manage mixed media from mirrorless cameras, cinema cameras, action cameras, recorders, and multi-camera shoots."),
                    ("识别 Sony、Canon、RED、ARRI、Blackmagic、GoPro、Panasonic 等常见设备结构。", "Recognize common Sony, Canon, RED, ARRI, Blackmagic, GoPro, Panasonic, and similar device structures."),
                    ("同步管理卡号、卷名、设备类型、项目归属和下卡状态。", "Synchronize card ID, volume name, device type, project ownership, and offload status."),
                    ("降低漏拷、重复拷贝、误格式化、卡号混乱的风险。", "Reduce the risk of missed copies, duplicate copies, accidental formatting, and card-ID confusion."),
                    ("可与 DIT 下卡、场记、代理和后期交接联动。", "Link with DIT Offload, Script Log, Proxies, and Post Handoff."),
                    ("让每一张卡从插入、下卡、校验到交接都有完整轨迹。", "Give every card a complete path from insertion, offload, verification, and handoff.")
                ]
            ),
            CapabilityDetail(
                id: "proxies-dailies",
                icon: "film.stack",
                title: ("代理与转码", "Proxy & Transcode"),
                summary: ("生成 H.264 / H.265 / ProRes 代理，支持 LUT 烘焙，并可在后期软件中一键链接。",
                          "Generate H.264 / H.265 / ProRes proxies and dailies, support LUT bake-in, and prepare one-click relinking for post."),
                headline: ("下卡之后，剪辑可以立刻开工。", "After offload, editorial can start immediately."),
                body: [
                    ("321Doit 的代理与转码模块不是普通压缩工具，而是为了让素材从片场直接进入剪辑流程。它可以在下卡后自动生成剪辑代理、审片样片、带 LUT 预览文件和无 LUT 干净代理，并把这些文件和原始素材保持清晰关系。",
                     "321Doit Proxy & Transcode is not a generic compression tool. It is designed to move media from set directly into editorial. After offload, it can automatically generate editorial proxies, review dailies, LUT-baked preview files, and clean no-LUT proxies while keeping a clear relationship to the original media."),
                    ("真正重要的是：这些代理不是散落在硬盘里的“另一个版本”，而是面向后期软件的一键链接流程设计。你可以把代理、原始素材、场记信息和交接数据一起交给后期，让 Final Cut Pro 和 DaVinci Resolve 更快识别、更快链接、更快进入剪辑状态。",
                     "The important point is that these proxies are not just another version scattered on a drive. They are designed for one-click post-software linking. You can hand proxies, originals, script log data, and handoff data to post together, helping Final Cut Pro and DaVinci Resolve recognize, relink, and enter editorial faster.")
                ],
                emphasis: ("不是“转一个小文件看看”，而是直接把后期代理工作流准备好。",
                           "It is not just making a smaller file to look at; it prepares the proxy workflow for post."),
                coreAbilities: [
                    ("支持 H.264、H.265、ProRes 等常见代理与转码格式。", "Support common proxy and transcode formats such as H.264, H.265, and ProRes."),
                    ("支持 LUT 烘焙，可生成带 LUT 的导演 / 客户预览版本。", "Support LUT bake-in for director or client preview versions."),
                    ("支持无 LUT 剪辑代理，方便后期调色保持干净流程。", "Support clean no-LUT editorial proxies for color-safe post workflows."),
                    ("代理文件可与原始素材保持对应关系，便于后期软件一键链接。", "Keep proxy files linked to original media for easier post-software relinking."),
                    ("面向 Final Cut Pro 与 DaVinci Resolve 的代理工作流设计。", "Proxy workflow design for Final Cut Pro and DaVinci Resolve."),
                    ("可配合场记元数据、卡号信息和交接包进入完整后期流程。", "Works with script log metadata, card information, and handoff packages."),
                    ("适合片场快速出样片、剪辑先行、远程审片和低性能设备剪辑。", "Useful for on-set dailies, editorial-first workflows, remote review, and editing on lower-power machines.")
                ]
            ),
            CapabilityDetail(
                id: "post-handoff",
                icon: "shippingbox",
                title: ("后期交接", "Post Handoff"),
                summary: ("一键生成后期交接包，素材、代理、场记、卡号和报告直接导入 Final Cut Pro / DaVinci Resolve。",
                          "Generate post handoff packages that bring media, proxies, script logs, card IDs, and reports into Final Cut Pro / DaVinci Resolve."),
                headline: ("不是把硬盘交出去，而是把后期工程直接准备好。", "Do not just hand over a drive; prepare the post workflow."),
                body: [
                    ("321Doit 的后期交接模块要解决的是小剧组最常见、也最致命的问题：素材到了剪辑手里，却不知道哪条是好条，代理在哪里，卡号怎么对应，场记写了什么，哪块盘是主盘，哪块盘是备份，哪些文件校验通过。",
                     "321Doit Post Handoff addresses one of the most common and dangerous problems for small crews: media reaches editorial, but nobody knows which takes are selects, where the proxies are, how card IDs map, what the script log says, which drive is master, which is backup, and which files passed verification."),
                    ("通过后期交接模块，你可以一键生成结构化交接包，把原始素材、代理文件、场记信息、摄影机卡记录、校验报告和诊断信息统一打包。剪辑不需要重新猜、不需要重新整理、不需要从一堆文件夹里翻素材，而是可以直接进入 Final Cut Pro 或 DaVinci Resolve 的导入流程。",
                     "With Post Handoff, you can generate a structured handoff package in one step, bundling originals, proxies, script log data, camera-card records, verification reports, and diagnostics. Editors do not need to guess, reorganize, or dig through folders; they can move directly into the Final Cut Pro or DaVinci Resolve import workflow.")
                ],
                emphasis: ("321Doit 的目标是让片场和后期之间不再断层。",
                           "321Doit is designed to remove the break between set and post."),
                coreAbilities: [
                    ("一键生成面向后期的完整交接包。", "Generate complete post-facing handoff packages in one step."),
                    ("支持素材、代理、场记信息、卡号记录和校验报告统一交接。", "Handoff media, proxies, script log data, card records, and verification reports together."),
                    ("面向 Final Cut Pro 和 DaVinci Resolve 的一键导入流程。", "One-click import flow for Final Cut Pro and DaVinci Resolve."),
                    ("场记信息可随交接包进入后期，帮助剪辑快速筛选好条和备注。", "Script log data can travel with the package to help editors quickly find selects and notes."),
                    ("支持原始素材与代理文件的对应关系，减少手动重新链接。", "Maintain relationships between originals and proxies to reduce manual relinking."),
                    ("Premiere Pro、剪映、Avid 等更多后期软件适配正在规划追加。", "Premiere Pro, Jianying, Avid, and more post software integrations are planned."),
                    ("让剪辑打开项目时，看到的不只是素材，而是完整拍摄上下文。", "When editorial opens the project, they see not just media, but the full shooting context.")
                ]
            ),
            CapabilityDetail(
                id: "reports-traceability",
                icon: "doc.text.magnifyingglass",
                title: ("报告与追踪", "Reports & Traceability"),
                summary: ("自动保存拷贝、校验、场记、卡号和交接记录，让每一次素材流转都有证据。",
                          "Automatically preserve copy, verification, script log, card, and handoff records so every media movement has evidence."),
                headline: ("专业流程的核心，是任何时候都能查得回来。", "The core of a professional workflow is being able to trace it back at any time."),
                body: [
                    ("片场最可怕的不是慢，而是出事以后没人说得清。素材有没有拷完？哪块盘是主盘？校验过没有？这张卡是不是已经格式化？这条为什么没进剪辑？代理是不是对应原始素材？这些问题如果靠人脑、聊天记录和文件夹命名来回答，迟早会出问题。",
                     "The most dangerous thing on set is not being slow; it is nobody being able to explain what happened when something goes wrong. Was the media fully copied? Which drive is master? Was it verified? Has this card already been formatted? Why did this take not reach editorial? Does this proxy match the original? If those questions are answered from memory, chat logs, and folder names, failure is only a matter of time."),
                    ("321Doit 的报告与追踪模块，会把每一次关键操作都记录下来。下卡、校验、续传、场记、卡号、代理、交接，都可以成为项目的一部分。它不只是生成报告，而是在帮你建立一套完整的片场数据证据链。",
                     "321Doit Reports & Traceability records every critical operation. Offload, verification, resume, script log, card IDs, proxies, and handoff can all become part of the project. It is not only generating reports; it is building a complete on-set data evidence chain.")
                ],
                emphasis: ("素材从摄影机出来之后，每一步都应该有记录。",
                           "After media leaves the camera, every step should have a record."),
                coreAbilities: [
                    ("自动保存下卡、校验、续传、代理、场记和交接记录。", "Automatically save offload, verification, resume, proxy, script log, and handoff records."),
                    ("支持 MHL、PDF、CSV、JSON、TXT 等多种报告格式。", "Support report formats including MHL, PDF, CSV, JSON, and TXT."),
                    ("PDF 可用于制片、导演、后期和客户确认。", "PDF reports can be used for production, director, post, and client confirmation."),
                    ("JSON / CSV 可用于自动化归档、项目管理和后续系统集成。", "JSON / CSV can support automated archiving, project management, and future system integration."),
                    ("记录错误、警告、诊断信息，方便快速排查问题。", "Record errors, warnings, and diagnostics for fast troubleshooting."),
                    ("让素材从拍摄现场到后期制作再到最终归档，全程可追踪。", "Keep media traceable from set to post production to final archive.")
                ]
            )
        ]
    }

    private var resourcesSection: some View {
        section(title: L10n.t("资源与支持", "Resources & Support", language: lang)) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], spacing: 10) {
                resourceCard("book", L10n.t("使用指南", "User Guide", language: lang)) {
                    openReadme()
                }
                resourceCard("heart", L10n.t("联系与支持", "Contact & Support", language: lang)) {
                    isSupportPresented = true
                }
                resourceCard("link", L10n.t("项目主页", "Project Home", language: lang)) {
                    openURL(UpdateSettings.githubURL)
                }
            }
        }
    }

    private func recentProjectRow(_ project: RecentProject) -> some View {
        let isHovered = hoveredRecentProjectID == project.id
        return Button {
            if project.isAccessible {
                openRecentProject(project)
            } else {
                relocate(project)
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: project.isAccessible ? "folder" : "exclamationmark.triangle")
                    .font(.system(size: 18))
                    .foregroundStyle(project.isAccessible ? colors.accent : colors.stateWarning)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                    Text(project.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(project.isAccessible ? lastOpenedText(project.lastOpenedAt) : L10n.t("项目文件不可访问", "Project files are not accessible", language: lang))
                        .font(.system(size: 10))
                        .foregroundStyle(project.isAccessible ? colors.textTertiary : colors.stateWarning)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .padding(.trailing, project.isAccessible ? 148 : 92)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: DoitVisual.radiusControl, style: .continuous))
            .doitSurface(
                colors: colors,
                cornerRadius: DoitVisual.radiusControl,
                elevation: .panel,
                accent: project.isAccessible ? colors.accent : colors.stateWarning,
                isHovered: isHovered,
                isMuted: !project.isAccessible
            )
        }
        .buttonStyle(DoitPressableButtonStyle(reduceMotion: reducesMotion, pressedScale: 0.992))
        .focusable(false)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hovering in
            withAnimation(DoitVisual.hoverAnimation(reduceMotion: reducesMotion)) {
                hoveredRecentProjectID = hovering ? project.id : nil
            }
        }
        .overlay(alignment: .trailing) {
            HStack(spacing: 10) {
                if project.isAccessible {
                    Button(L10n.t("打开", "Open", language: lang)) {
                        openRecentProject(project)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([project.url])
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                    .help(L10n.t("在 Finder 中显示", "Show in Finder", language: lang))
                } else {
                    Button(L10n.t("重新定位", "Relocate", language: lang)) {
                        relocate(project)
                    }
                    .buttonStyle(.borderless)
                    .focusable(false)
                }

                Button {
                    recentProjects.remove(project)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .focusable(false)
                .help(L10n.t("从列表移除", "Remove from list", language: lang))
            }
            .padding(.trailing, 12)
        }
    }

    private func openRecentProject(_ project: RecentProject) {
        if store.openProject(at: project.url) {
            recentProjects.record(url: store.projectFolderURL, name: LocalizedDisplay.projectName(store.project, language: lang))
            enterWorkspace(.project)
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            content()
        }
    }

    private func managerActionCard(id: String, icon: String, title: String, subtitle: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        let isHovered = hoveredActionID == id
        return Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(prominent ? Color.white : colors.accent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(prominent ? Color.white.opacity(0.82) : colors.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .foregroundStyle(prominent ? Color.white : colors.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: DoitVisual.radiusCard, style: .continuous))
            .doitSurface(
                colors: colors,
                cornerRadius: DoitVisual.radiusCard,
                fill: prominent ? colors.accent.opacity(0.92) : colors.panelBg.opacity(0.74),
                elevation: .panel,
                accent: colors.accent,
                isHovered: isHovered
            )
        }
        .buttonStyle(DoitPressableButtonStyle(reduceMotion: reducesMotion))
        .focusable(false)
        .onHover { hovering in
            withAnimation(DoitVisual.hoverAnimation(reduceMotion: reducesMotion)) {
                hoveredActionID = hovering ? id : nil
            }
        }
    }

    private func capability(_ detail: CapabilityDetail) -> some View {
        let isHovered = hoveredCapabilityID == detail.id

        return Button {
            selectedCapability = detail
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: detail.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(colors.accent)
                    .frame(width: 34, height: 34)
                    .background(colors.accent.opacity(isHovered ? 0.13 : 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: DoitVisual.radiusSmall, style: .continuous))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(L10n.t(detail.title.0, detail.title.1, language: lang))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(colors.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(colors.accent)
                            .opacity(isHovered ? 0.75 : 0.22)
                    }

                    Text(L10n.t(detail.cardSummary.0, detail.cardSummary.1, language: lang))
                        .font(.system(size: 11))
                        .foregroundStyle(colors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        ForEach(Array(detail.tags.prefix(3).enumerated()), id: \.offset) { _, tag in
                            Text(L10n.t(tag.0, tag.1, language: lang))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(colors.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(colors.accent.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .background(colors.panelBg.opacity(0.44))
            .doitSurface(
                colors: colors,
                cornerRadius: DoitVisual.radiusControl,
                fill: colors.panelBg.opacity(0.5),
                elevation: .panel,
                accent: colors.accent,
                isHovered: isHovered
            )
        }
        .buttonStyle(DoitPressableButtonStyle(reduceMotion: reducesMotion))
        .focusable(false)
        .onHover { hovering in
            withAnimation(DoitVisual.hoverAnimation(reduceMotion: reducesMotion)) {
                hoveredCapabilityID = hovering ? detail.id : nil
            }
        }
    }

    private func resourceCard(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(colors.accent)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .doitSurface(
                colors: colors,
                cornerRadius: DoitVisual.radiusControl,
                elevation: .panel
            )
        }
        .buttonStyle(DoitPressableButtonStyle(reduceMotion: reducesMotion))
        .focusable(false)
    }

    private func relocate(_ project: RecentProject) {
        let panel = NSOpenPanel()
        panel.title = L10n.t("重新定位项目文件夹", "Relocate Project Folder", language: lang)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url, store.openProject(at: url) {
            recentProjects.relocate(project, to: url, name: LocalizedDisplay.projectName(store.project, language: lang))
            enterWorkspace(.project)
        }
    }

    private func lastOpenedText(_ date: Date) -> String {
        let value = recentProjectDateFormatter.string(from: date)
        return L10n.t("最近打开 \(value)", "Last opened \(value)", language: lang)
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openReadme() {
        openURL("\(UpdateSettings.githubURL)/blob/main/README.md")
    }

    private func workspace(for detail: CapabilityDetail) -> Workspace {
        switch detail.id {
        case "script-log":
            return .scriptLog
        case "post-handoff":
            return .handoff
        case "reports-traceability":
            return .reports
        case "dit-offload", "proxy-transcode":
            return .offload
        default:
            return .project
        }
    }
}

private struct CapabilityDetailView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss
    let detail: CapabilityDetail

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    coreValue
                    workflowStrip
                    compactCapabilities
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
        }
        .frame(width: 720, height: 560)
        .background(colors.surfaceBg)
        .onExitCommand {
            dismiss()
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(L10n.t("关闭", "Close", language: lang))
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 2)
    }

    private var coreValue: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t(detail.headline.0, detail.headline.1, language: lang))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(detail.body.enumerated()), id: \.offset) { _, paragraph in
                let paragraphText = L10n.t(paragraph.0, paragraph.1, language: lang)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !paragraphText.isEmpty {
                    Text(paragraphText)
                        .font(.system(size: 13))
                        .foregroundStyle(colors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var workflowStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("流程", "Workflow", language: lang))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colors.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(Array(detail.workflow.enumerated()), id: \.offset) { index, step in
                        Text(L10n.t(step.0, step.1, language: lang))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(index == 0 ? colors.accent : colors.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(index == 0 ? colors.accent.opacity(0.09) : colors.panelBg.opacity(0.45))
                            .clipShape(Capsule())
                        if index < detail.workflow.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(colors.textTertiary.opacity(0.75))
                        }
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(12)
        .background(colors.panelBg.opacity(0.30))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colors.hairline.opacity(0.55), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var compactCapabilities: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.t("能力", "Capabilities", language: lang))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colors.textPrimary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 8) {
                ForEach(Array(detail.abilities.enumerated()), id: \.element.id) { index, ability in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: abilityIcon(at: index))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(colors.accent)
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.t(ability.title.0, ability.title.1, language: lang))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(colors.textPrimary)
                                .lineLimit(1)
                            Text(L10n.t(ability.text.0, ability.text.1, language: lang))
                                .font(.system(size: 10))
                                .foregroundStyle(colors.textSecondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private func abilityIcon(at index: Int) -> String {
        ["checkmark.circle", "scope", "number", "exclamationmark.shield", "link", "clock.arrow.circlepath"][index % 6]
    }
}

struct NewProjectSheet: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @State private var projectName = ""
    @State private var folderURL: URL?
    let onCreate: (String, URL) -> Void

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private var canCreate: Bool {
        !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && folderURL != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("新建项目", "New Project", language: lang))
                        .font(.system(size: 22, weight: .semibold))
                    Text(L10n.t("填写项目名称，并选择这个项目的保存位置。",
                                "Enter a project name and choose where this project will be saved.",
                                language: lang))
                        .font(.system(size: 12))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }
            }

            VStack(alignment: .leading, spacing: 12) {
                formRow(title: L10n.t("项目名称", "Project Name", language: lang)) {
                    TextField(L10n.t("请输入项目名称", "Enter project name", language: lang), text: $projectName)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(colors.inputBg)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(colors.hairline, lineWidth: 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }

                formRow(title: L10n.t("保存位置", "Save Location", language: lang)) {
                    HStack(spacing: 8) {
                        Text(displaySavePath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(folderURL == nil ? colors.textSecondary : colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(colors.inputBg)
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(colors.hairline, lineWidth: 0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        Button {
                            chooseFolder()
                        } label: {
                            Label(L10n.t("选择", "Choose", language: lang), systemImage: "folder")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .focusable(false)
                    }
                }
            }
            .padding(16)
            .liquidGlassSurface(colors: colors, cornerRadius: 16)

            HStack {
                Spacer()
                Button(L10n.t("取消", "Cancel", language: lang)) {
                    dismiss()
                }
                .buttonStyle(.borderless)
                .focusable(false)
                Button {
                    guard let folderURL else { return }
                    onCreate(projectName, folderURL)
                } label: {
                    Text(L10n.t("创建项目", "Create Project", language: lang))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
                .focusable(false)
            }
        }
        .padding(24)
        .frame(width: 620)
        .background(colors.surfaceBg)
    }

    private func formRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            content()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = L10n.t("选择项目保存位置", "Choose Project Save Location", language: lang)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if let defaultRoot = defaultRootURL {
            panel.directoryURL = defaultRoot
        }
        if panel.runModal() == .OK {
            folderURL = panel.url
        }
    }

    private var defaultRootURL: URL? {
        let path = settings.settings.general.defaultProjectRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    private var displaySavePath: String {
        guard let folderURL else {
            return L10n.t("尚未选择", "Not selected", language: lang)
        }
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return folderURL.path }
        return folderURL.appendingPathComponent(projectFolderName(for: name), isDirectory: true).path
    }

    private func projectFolderName(for name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let folderName = name.components(separatedBy: illegal)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return folderName.isEmpty ? L10n.t("未命名项目", "Untitled Project", language: lang) : folderName
    }
}
