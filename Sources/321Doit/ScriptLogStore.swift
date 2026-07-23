import AppKit
import CoreLocation
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ScriptLogStore: ObservableObject {
    @Published private(set) var project: Project
    @Published var projectFolderURL: URL?
    @Published var selectedShootingDayID: UUID?
    @Published var selectedSceneID: UUID?
    @Published var selectedShotID: UUID?
    @Published var selectedTakeID: UUID?
    @Published var selectedTakeIDs: Set<UUID> = []
    @Published var isBatchMode: Bool = false
    @Published var alertMessage: String?
    @Published var lastSavedAt: Date?
    @Published var lastExportURL: URL?
    @Published var isInspectorVisible: Bool = false
    @Published var language: AppLanguage = .system {
        didSet { migrateDefaultsToLanguage() }
    }

    @Published var expandedDayIDs: Set<UUID> = []
    @Published var expandedSceneIDs: Set<UUID> = []
    @Published var expandedShotIDs: Set<UUID> = []
    @Published var expandedTakeGroupIDs: Set<UUID> = []

    @Published var hasUnsavedChanges: Bool = false

    private let folderDefaultsKey = "321doit.scriptLog.projectFolder"
    private let fm = FileManager.default
    static func defaultDepartmentNames(language: AppLanguage = .system) -> [String] {
        let t: (String, String) -> String = { zh, en in L10n.t(zh, en, language: language) }
        return [
            t("导演组", "Director"), t("摄影组", "Camera"), t("灯光组", "Lighting"),
            t("录音组", "Sound"), t("美术组", "Art"), t("服化组", "Wardrobe/MUA"),
            t("道具组", "Props"), t("制片组", "Production"), "DIT",
            t("演员组", "Cast"), t("场务组", "Grip"), t("车辆组", "Transport"),
            t("后期组", "Post")
        ]
    }

    private let macLocationProvider = MacLocationProvider.shared
    private var undoStack: [ProjectSnapshot] = []
    private var saveWorkItem: DispatchWorkItem?
    private var requestedMacLocationDayIDs: Set<UUID> = []

    private struct ProjectSnapshot {
        var project: Project
        var selectedShootingDayID: UUID?
        var selectedSceneID: UUID?
        var selectedShotID: UUID?
        var selectedTakeID: UUID?
        var selectedTakeIDs: Set<UUID>
    }

    private struct CallSheetExportDocument: Codable {
        var project: ProjectMetadata
        var dayCode: String
        var day: ShootingDay
        var exportedAt: Date
    }

    init(loadPersistedProject: Bool = true) {
        project = loadPersistedProject
            ? Self.makeDefaultProject(language: .system)
            : Self.makeBlankProject(language: .system)
        if loadPersistedProject {
            loadInitialProject()
        } else {
            normalizeSelection()
        }
    }

    var storageDirectoryURL: URL {
        (projectFolderURL ?? Self.defaultProjectFolderURL())
            .appendingPathComponent("_321Doit", isDirectory: true)
    }

    var projectJSONURL: URL {
        storageDirectoryURL.appendingPathComponent("project.json")
    }

    var scriptLogJSONURL: URL {
        storageDirectoryURL.appendingPathComponent("script_log.json")
    }

    var reportsDirectoryURL: URL {
        storageDirectoryURL.appendingPathComponent("reports", isDirectory: true)
    }

    var currentShootingDay: ShootingDay? {
        guard let id = selectedShootingDayID else { return nil }
        return project.shootingDays.first(where: { $0.id == id })
    }

    var currentScene: ScriptScene? {
        guard let sceneID = selectedSceneID else { return nil }
        return currentShootingDay?.scenes.first(where: { $0.id == sceneID })
    }

    var currentShot: Shot? {
        guard let shotID = selectedShotID else { return nil }
        return currentScene?.shots.first(where: { $0.id == shotID })
    }

    var currentTake: Take? {
        guard let takeID = selectedTakeID else { return nil }
        return currentShot?.takes.first(where: { $0.id == takeID })
    }

    var takeCount: Int {
        project.shootingDays.reduce(0) { dayTotal, day in
            dayTotal + day.scenes.reduce(0) { sceneTotal, scene in
                sceneTotal + scene.shots.reduce(0) { $0 + $1.takes.count }
            }
        }
    }

    @discardableResult
    func chooseProjectFolder() -> Bool {
        let panel = NSSavePanel()
        panel.title = t("保存 321Doit 工程文件", "Save 321Doit Project")
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [UTType(ProjectRepository.projectContentTypeIdentifier) ?? .package]
        panel.nameFieldStringValue = "\(Self.projectDirectoryName(for: project.name)).\(ProjectRepository.projectFileExtension)"
        if panel.runModal() == .OK, let selectedURL = panel.url {
            let url = ProjectRepository.normalizedProjectPackageURL(selectedURL)
            let hasExisting = ProjectRepository.isProjectFolder(url)

            if hasExisting {
                let alert = NSAlert()
                alert.messageText = t("风险提示：已存在项目", "Warning: Existing Project Found")
                alert.informativeText = t(
                    "该文件夹已存在项目数据。继续将会覆盖原有数据。",
                    "Project data already exists here. Continuing will overwrite the existing project."
                )
                alert.addButton(withTitle: t("覆盖另存为", "Overwrite"))
                alert.addButton(withTitle: t("取消", "Cancel"))

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    projectFolderURL = url
                    let chosenName = url.deletingPathExtension().lastPathComponent
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !chosenName.isEmpty { project.name = chosenName }
                    UserDefaults.standard.set(url.path, forKey: folderDefaultsKey)
                    save()
                    return alertMessage == nil
                }
            } else {
                projectFolderURL = url
                let chosenName = url.deletingPathExtension().lastPathComponent
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !chosenName.isEmpty { project.name = chosenName }
                UserDefaults.standard.set(url.path, forKey: folderDefaultsKey)
                save()
                return alertMessage == nil
            }
        }
        return false
    }

    @discardableResult
    func newProject() -> Bool {
        if hasUnsavedChanges {
            let alert = NSAlert()
            alert.messageText = t("是否新建项目？", "New Project?")
            alert.informativeText = t(
                "当前项目可能有未保存的更改。继续将丢失进度。",
                "There are unsaved changes. Continuing will lose progress."
            )
            alert.addButton(withTitle: t("新建", "New"))
            alert.addButton(withTitle: t("取消", "Cancel"))
            if alert.runModal() != .alertFirstButtonReturn {
                return false
            }
        }

        projectFolderURL = nil
        UserDefaults.standard.removeObject(forKey: folderDefaultsKey)
        project = Self.makeDefaultProject(language: language)
        undoStack.removeAll()
        hasUnsavedChanges = false
        expandedDayIDs.removeAll()
        expandedSceneIDs.removeAll()
        expandedShotIDs.removeAll()
        expandedTakeGroupIDs.removeAll()
        normalizeSelection()
        expandAllHierarchy()
        alertMessage = nil
        return true
    }

    @discardableResult
    func createNewProject(name: String, folderURL: URL) -> Bool {
        if hasUnsavedChanges {
            let alert = NSAlert()
            alert.messageText = t("是否新建项目？", "New Project?")
            alert.informativeText = t(
                "当前项目可能有未保存的更改。继续将丢失进度。",
                "There are unsaved changes. Continuing will lose progress."
            )
            alert.addButton(withTitle: t("新建", "New"))
            alert.addButton(withTitle: t("取消", "Cancel"))
            if alert.runModal() != .alertFirstButtonReturn {
                return false
            }
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedProjectName = trimmedName.isEmpty ? t("未命名项目", "Untitled Project") : trimmedName
        let projectDirectoryURL = ProjectRepository.projectPackageURL(
            in: folderURL,
            projectName: resolvedProjectName
        )

        let hasExisting = ProjectRepository.isProjectFolder(projectDirectoryURL)
        if hasExisting {
            let alert = NSAlert()
            alert.messageText = t("风险提示：已存在项目", "Warning: Existing Project Found")
            alert.informativeText = t(
                "该文件夹已存在项目数据。继续将会覆盖原有数据。",
                "Project data already exists here. Continuing will overwrite the existing project."
            )
            alert.addButton(withTitle: t("覆盖并创建", "Overwrite and Create"))
            alert.addButton(withTitle: t("取消", "Cancel"))
            if alert.runModal() != .alertFirstButtonReturn {
                return false
            }
        }

        let resolvedURL = projectDirectoryURL
        SecurityScopedBookmarks.save(url: resolvedURL, role: "project")
        projectFolderURL = SecurityScopedBookmarks.resolvedURL(for: resolvedURL, role: "project")
        UserDefaults.standard.set(projectFolderURL?.path ?? resolvedURL.path, forKey: folderDefaultsKey)
        project = Self.makeDefaultProject(language: language)
        project.name = resolvedProjectName
        undoStack.removeAll()
        selectedTakeIDs.removeAll()
        isBatchMode = false
        hasUnsavedChanges = false
        lastSavedAt = nil
        expandedDayIDs.removeAll()
        expandedSceneIDs.removeAll()
        expandedShotIDs.removeAll()
        expandedTakeGroupIDs.removeAll()
        normalizeSelection()
        expandAllHierarchy()
        save()
        return alertMessage == nil
    }

    @discardableResult
    func openProject() -> Bool {
        if hasUnsavedChanges {
            let alert = NSAlert()
            alert.messageText = t("是否打开项目？", "Open Project?")
            alert.informativeText = t(
                "当前项目可能有未保存的更改。继续将丢失进度。",
                "There are unsaved changes. Continuing will lose progress."
            )
            alert.addButton(withTitle: t("打开", "Open"))
            alert.addButton(withTitle: t("取消", "Cancel"))
            if alert.runModal() != .alertFirstButtonReturn {
                return false
            }
        }

        let panel = NSOpenPanel()
        panel.title = t("打开 321Doit 工程文件或旧项目文件夹", "Open a 321Doit Project or Legacy Project Folder")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [
            UTType(ProjectRepository.projectContentTypeIdentifier) ?? .package,
            .folder
        ]
        if panel.runModal() == .OK, let url = panel.url {
            if !openProject(at: url) {
                let alert = NSAlert()
                alert.messageText = t("无效的项目", "Invalid Project")
                alert.informativeText = t(
                    "该文件夹不包含有效的 321Doit 项目数据。",
                    "This folder does not contain valid 321Doit project data."
                )
                alert.addButton(withTitle: t("确定", "OK"))
                alert.runModal()
                return false
            }
            return true
        }
        return false
    }

    @discardableResult
    func openProject(at url: URL) -> Bool {
        guard Self.isProjectFolder(url) else { return false }
        SecurityScopedBookmarks.save(url: url, role: "project")
        let resolvedURL = SecurityScopedBookmarks.resolvedURL(for: url, role: "project")
        projectFolderURL = resolvedURL
        UserDefaults.standard.set(resolvedURL.path, forKey: folderDefaultsKey)
        expandedDayIDs.removeAll()
        expandedSceneIDs.removeAll()
        expandedShotIDs.removeAll()
        expandedTakeGroupIDs.removeAll()
        loadProject(from: resolvedURL)
        expandAllHierarchy()
        return true
    }

    func save() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        do {
            try saveToDisk()
            hasUnsavedChanges = false
            alertMessage = nil
            lastSavedAt = Date()
        } catch {
            alertMessage = t("场记保存失败：\(error.localizedDescription)", "Save failed: \(error.localizedDescription)")
        }
    }

    func restoreIndependentWorkspace(from folder: URL) -> Bool {
        guard ProjectRepository.isProjectFolder(folder) else { return false }
        projectFolderURL = folder
        expandedDayIDs.removeAll()
        expandedSceneIDs.removeAll()
        expandedShotIDs.removeAll()
        expandedTakeGroupIDs.removeAll()
        loadProject(from: folder)
        expandAllHierarchy()
        return alertMessage == nil
    }

    func persistIndependentWorkspace(to folder: URL) throws {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        projectFolderURL = folder
        try ProjectRepository.save(project, to: folder)
        hasUnsavedChanges = false
        alertMessage = nil
        lastSavedAt = Date()
    }

    func resetIndependentWorkspaceInMemory() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        projectFolderURL = nil
        project = Self.makeBlankProject(language: language)
        undoStack.removeAll()
        selectedTakeIDs.removeAll()
        isBatchMode = false
        hasUnsavedChanges = false
        lastSavedAt = nil
        expandedDayIDs.removeAll()
        expandedSceneIDs.removeAll()
        expandedShotIDs.removeAll()
        expandedTakeGroupIDs.removeAll()
        normalizeSelection()
        alertMessage = nil
    }

    func reload() {
        undoStack.removeAll()
        loadProject(from: projectFolderURL ?? Self.defaultProjectFolderURL())
    }

    func setProjectName(_ value: String) {
        mutateProject { $0.name = value }
    }

    func setProductionName(_ value: String) {
        mutateProject { $0.productionName = value }
    }

    func setDirector(_ value: String) {
        mutateProject { $0.director = value }
    }

    func setDP(_ value: String) {
        mutateProject { $0.dp = value }
    }

    func setDITName(_ value: String) {
        mutateProject { $0.ditName = value }
    }

    func setScriptSupervisor(_ value: String) {
        mutateProject { $0.scriptSupervisor = value }
    }

    func setCameraCount(_ count: Int) {
        mutateProject { project in
            let target = max(1, min(12, count))
            while project.cameraRegistry.count < target {
                let index = project.cameraRegistry.count
                let letter = Self.cameraLetter(for: index)
                let card = "\(letter)01"
                project.cameraRegistry.append(
                    RegisteredCamera(
                        label: L10n.t("\(letter)机", "Cam \(letter)", language: language),
                        currentCard: card,
                        cardNames: [card],
                        nextExpectedClipID: "\(card)C001"
                    )
                )
            }
            if project.cameraRegistry.count > target {
                project.cameraRegistry.removeLast(project.cameraRegistry.count - target)
            }
            Self.syncCameraUsageToRegistry(project: &project, pruneScriptLogRecords: true)
        }
    }

    func updateRegisteredCamera(id: UUID, update: (inout RegisteredCamera) -> Void) {
        mutateProject { project in
            guard let index = project.cameraRegistry.firstIndex(where: { $0.id == id }) else { return }
            let old = project.cameraRegistry[index]
            update(&project.cameraRegistry[index])
            project.cameraRegistry[index].normalizeCards()
            Self.syncCameraUsageToRegistry(project: &project, oldCamera: old, newCamera: project.cameraRegistry[index], pruneScriptLogRecords: false)
        }
    }

    func updateRegisteredCameraCard(cameraID: UUID, cardIndex: Int, value: String) {
        mutateProject { project in
            guard let cameraIndex = project.cameraRegistry.firstIndex(where: { $0.id == cameraID }) else { return }
            guard project.cameraRegistry[cameraIndex].cardNames.indices.contains(cardIndex) else { return }
            let old = project.cameraRegistry[cameraIndex]
            project.cameraRegistry[cameraIndex].cardNames[cardIndex] = value
            project.cameraRegistry[cameraIndex].normalizeCards()
            Self.syncCameraUsageToRegistry(project: &project, oldCamera: old, newCamera: project.cameraRegistry[cameraIndex], pruneScriptLogRecords: false)
        }
    }

    func addCard(to cameraID: UUID) {
        mutateProject { project in
            guard let index = project.cameraRegistry.firstIndex(where: { $0.id == cameraID }) else { return }
            let old = project.cameraRegistry[index]
            let label = project.cameraRegistry[index].label.replacingOccurrences(of: "机", with: "")
            let nextIndex = project.cameraRegistry[index].cardNames.count + 1
            project.cameraRegistry[index].cardNames.append("\(label)\(String(format: "%02d", nextIndex))")
            project.cameraRegistry[index].normalizeCards()
            Self.syncCameraUsageToRegistry(project: &project, oldCamera: old, newCamera: project.cameraRegistry[index], pruneScriptLogRecords: false)
        }
    }

    func removeCard(from cameraID: UUID, cardIndex: Int) {
        mutateProject { project in
            guard let cameraIndex = project.cameraRegistry.firstIndex(where: { $0.id == cameraID }) else { return }
            guard project.cameraRegistry[cameraIndex].cardNames.indices.contains(cardIndex),
                  project.cameraRegistry[cameraIndex].cardNames.count > 1 else { return }
            let old = project.cameraRegistry[cameraIndex]
            project.cameraRegistry[cameraIndex].cardNames.remove(at: cardIndex)
            project.cameraRegistry[cameraIndex].normalizeCards()
            Self.syncCameraUsageToRegistry(project: &project, oldCamera: old, newCamera: project.cameraRegistry[cameraIndex], pruneScriptLogRecords: false)
        }
    }

    func addRegisteredCamera() {
        mutateProject { project in
            let existing = Set(project.cameraRegistry.map(\.label))
            let candidates = (0..<8).map { i -> String in
                let letter = String(UnicodeScalar(UInt8(65 + i)))
                return L10n.t("\(letter)机", "Cam \(letter)", language: language)
            }
            let label = candidates.first { !existing.contains($0) } ?? L10n.t("新机位", "New Cam", language: language)
            let prefix = label
                .replacingOccurrences(of: "机", with: "")
                .replacingOccurrences(of: "Cam ", with: "")
            let card = "\(prefix)01"
            project.cameraRegistry.append(
                RegisteredCamera(
                    label: label,
                    currentCard: card,
                    cardNames: [card],
                    nextExpectedClipID: "\(card)C001"
                )
            )
            Self.syncCameraUsageToRegistry(project: &project, pruneScriptLogRecords: false)
        }
    }

    func removeRegisteredCamera(id: UUID) {
        mutateProject { project in
            guard project.cameraRegistry.count > 1 else { return }
            project.cameraRegistry.removeAll { $0.id == id }
            Self.syncCameraUsageToRegistry(project: &project, pruneScriptLogRecords: true)
        }
    }

    func addPrincipalCastMember() {
        mutateProject { project in
            project.principalCast.append(PrincipalCastMember())
        }
    }

    func updatePrincipalCastMember(id: UUID, update: (inout PrincipalCastMember) -> Void) {
        mutateProject { project in
            guard let index = project.principalCast.firstIndex(where: { $0.id == id }) else { return }
            update(&project.principalCast[index])
        }
    }

    func removePrincipalCastMember(id: UUID) {
        mutateProject { project in
            project.principalCast.removeAll { $0.id == id }
            if project.principalCast.isEmpty {
                project.principalCast = [PrincipalCastMember()]
            }
        }
    }

    func addDepartmentContact() {
        mutateProject { project in
            let existing = Set(project.departmentContacts.map { $0.departmentName.trimmedForCheck })
            let name = Self.defaultDepartmentNames(language: language).first { !existing.contains($0) } ?? ""
            project.departmentContacts.append(DepartmentContact(departmentName: name))
        }
    }

    func updateDepartmentContact(id: UUID, update: (inout DepartmentContact) -> Void) {
        mutateProject { project in
            guard let index = project.departmentContacts.firstIndex(where: { $0.id == id }) else { return }
            update(&project.departmentContacts[index])
        }
    }

    func removeDepartmentContact(id: UUID) {
        mutateProject { project in
            project.departmentContacts.removeAll { $0.id == id }
            if project.departmentContacts.isEmpty {
                project.departmentContacts = [DepartmentContact(departmentName: t("导演组", "Director"))]
            }
        }
    }

    func selectShootingDay(_ id: UUID) {
        selectedShootingDayID = id
        expandedDayIDs.insert(id)
        expandDescendants(inDay: id)
        selectFirstSceneShotTake(inDay: id)
    }

    func selectScene(_ id: UUID) {
        selectedSceneID = id
        expandedSceneIDs.insert(id)
        expandDescendants(inScene: id)
        selectFirstShotTake(inScene: id)
    }

    func selectShot(_ id: UUID) {
        selectedShotID = id
        expandedShotIDs.insert(id)
        expandedTakeGroupIDs.insert(id)
        selectFirstTake(inShot: id)
    }

    func expandAllHierarchy() {
        expandedDayIDs = Set(project.shootingDays.map(\.id))
        expandedSceneIDs = Set(project.shootingDays.flatMap { $0.scenes.map(\.id) })
        expandedShotIDs = Set(project.shootingDays.flatMap { $0.scenes.flatMap { $0.shots.map(\.id) } })
        expandedTakeGroupIDs = expandedShotIDs
    }

    func shootingDayCode(for id: UUID) -> String {
        Self.dayCode(in: project, dayID: id)
    }

    @discardableResult
    func createShootingPlanDay(on date: Date = Date(), type: ShootingDayType = .shooting) -> UUID {
        let nextIndex = project.shootingDays.count + 1
        var callSheet = Self.defaultCallSheet(from: project)
        callSheet.type = type
        callSheet.title = type == .shooting ? "" : type.label(language: language)
        let newDay = ShootingDay(
            date: date,
            label: L10n.t("第 \(nextIndex) 天", "Day \(nextIndex)", language: language),
            scenes: [Self.makeDefaultScene(sceneNumber: "")],
            callSheet: callSheet
        )
        let scene = newDay.scenes[0]
        let shot = scene.shots[0]
        let take = shot.takes[0]

        mutateProject { project in
            project.shootingDays.append(newDay)
        }
        selectedShootingDayID = newDay.id
        selectedSceneID = scene.id
        selectedShotID = shot.id
        selectedTakeID = take.id
        expandedDayIDs.insert(newDay.id)
        expandedSceneIDs.insert(scene.id)
        expandedShotIDs.insert(shot.id)
        expandedTakeGroupIDs.insert(shot.id)
        return newDay.id
    }

    @discardableResult
    func createOrUpdateShootingPlanDay(on date: Date, type: ShootingDayType = .shooting) -> UUID {
        let normalizedDate = Calendar.current.startOfDay(for: date)
        if let existing = project.shootingDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: normalizedDate) }) {
            updateShootingDay(existing.id) { day in
                day.date = normalizedDate
                day.callSheet.type = type
                if type != .shooting && day.callSheet.title.trimmedForCheck.isEmpty {
                    day.callSheet.title = type.label(language: language)
                }
            }
            selectedShootingDayID = existing.id
            return existing.id
        }
        return createShootingPlanDay(on: normalizedDate, type: type)
    }

    func setShootingPlanStartDate(_ date: Date) {
        let startDate = Calendar.current.startOfDay(for: date)
        mutateProject { project in
            let orderedDays = project.shootingDays.sorted { $0.date < $1.date }
            guard !orderedDays.isEmpty else { return }
            let originalStartDate = Calendar.current.startOfDay(for: orderedDays[0].date)
            let orderedIDs = orderedDays.map(\.id)
            for (index, dayID) in orderedIDs.enumerated() {
                guard let originalDay = orderedDays.first(where: { $0.id == dayID }),
                      let dayIndex = project.shootingDays.firstIndex(where: { $0.id == dayID }) else { continue }
                let originalDate = Calendar.current.startOfDay(for: originalDay.date)
                let offset = Calendar.current.dateComponents([.day], from: originalStartDate, to: originalDate).day ?? index
                guard let shiftedDate = Calendar.current.date(byAdding: .day, value: offset, to: startDate) else { continue }
                project.shootingDays[dayIndex].date = shiftedDate
                project.shootingDays[dayIndex].label = L10n.t("第 \(index + 1) 天", "Day \(index + 1)", language: language)
            }
            project.shootingDays.sort { $0.date < $1.date }
        }
        selectedShootingDayID = project.shootingDays.first?.id
    }

    func setShootingPlanDays(on dates: [Date], type: ShootingDayType) {
        let normalizedDates = normalizedUniqueDates(dates)
        guard !normalizedDates.isEmpty else { return }
        var firstSelectedID: UUID?
        mutateProject { project in
            for date in normalizedDates {
                if let index = project.shootingDays.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                    project.shootingDays[index].date = date
                    project.shootingDays[index].callSheet.type = type
                    if type != .shooting && project.shootingDays[index].callSheet.title.trimmedForCheck.isEmpty {
                        project.shootingDays[index].callSheet.title = type.label(language: language)
                    }
                    firstSelectedID = firstSelectedID ?? project.shootingDays[index].id
                } else {
                    let nextIndex = project.shootingDays.count + 1
                    var callSheet = Self.defaultCallSheet(from: project)
                    callSheet.type = type
                    callSheet.title = type == .shooting ? "" : type.label(language: language)
                    let newDay = ShootingDay(
                        date: date,
                        label: L10n.t("第 \(nextIndex) 天", "Day \(nextIndex)", language: language),
                        scenes: [Self.makeDefaultScene(sceneNumber: "")],
                        callSheet: callSheet
                    )
                    project.shootingDays.append(newDay)
                    firstSelectedID = firstSelectedID ?? newDay.id
                }
            }
            project.shootingDays.sort { $0.date < $1.date }
        }
        if let firstSelectedID {
            selectedShootingDayID = firstSelectedID
            selectFirstSceneShotTake(inDay: firstSelectedID)
        }
    }

    func ensureShootingPlanDays(on dates: [Date], type: ShootingDayType = .shooting) {
        let normalizedDates = normalizedUniqueDates(dates)
        guard !normalizedDates.isEmpty else { return }
        var firstSelectedID: UUID?
        mutateProject { project in
            for date in normalizedDates {
                if let existing = project.shootingDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                    firstSelectedID = firstSelectedID ?? existing.id
                    continue
                }
                let nextIndex = project.shootingDays.count + 1
                var callSheet = Self.defaultCallSheet(from: project)
                callSheet.type = type
                callSheet.title = type == .shooting ? "" : type.label(language: language)
                let newDay = ShootingDay(
                    date: date,
                    label: L10n.t("第 \(nextIndex) 天", "Day \(nextIndex)", language: language),
                    scenes: [Self.makeDefaultScene(sceneNumber: "")],
                    callSheet: callSheet
                )
                project.shootingDays.append(newDay)
                firstSelectedID = firstSelectedID ?? newDay.id
            }
            project.shootingDays.sort { $0.date < $1.date }
        }
        if let firstSelectedID {
            selectedShootingDayID = firstSelectedID
            selectFirstSceneShotTake(inDay: firstSelectedID)
        }
    }

    func propagateCallSheet(from sourceID: UUID, to dates: [Date]) {
        let normalizedDates = normalizedUniqueDates(dates)
        guard normalizedDates.count > 1,
              let source = project.shootingDays.first(where: { $0.id == sourceID }) else { return }
        mutateProject { project in
            for date in normalizedDates {
                if let index = project.shootingDays.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                    guard project.shootingDays[index].id != sourceID else { continue }
                    var copiedSheet = Self.propagatedCallSheet(source.callSheet, preservingIDsFrom: project.shootingDays[index].callSheet)
                    copiedSheet.updatedAt = Date()
                    project.shootingDays[index].callSheet = copiedSheet
                } else {
                    let nextIndex = project.shootingDays.count + 1
                    var copiedSheet = Self.propagatedCallSheet(source.callSheet)
                    copiedSheet.updatedAt = Date()
                    let newDay = ShootingDay(
                        date: date,
                        label: L10n.t("第 \(nextIndex) 天", "Day \(nextIndex)", language: language),
                        scenes: [Self.makeDefaultScene(sceneNumber: "")],
                        callSheet: copiedSheet
                    )
                    project.shootingDays.append(newDay)
                }
            }
            project.shootingDays.sort { $0.date < $1.date }
        }
    }

    func setShootingPlanDaysStatus(on dates: [Date], status: ShootingDayCallSheetStatus) {
        let normalizedDates = normalizedUniqueDates(dates)
        guard !normalizedDates.isEmpty else { return }
        mutateProject { project in
            for date in normalizedDates {
                guard let index = project.shootingDays.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) else { continue }
                project.shootingDays[index].callSheet.status = status
                project.shootingDays[index].callSheet.updatedAt = Date()
            }
        }
    }

    func duplicateShootingPlanDay(_ sourceID: UUID? = nil) {
        let source = sourceID.flatMap { id in project.shootingDays.first(where: { $0.id == id }) } ?? currentShootingDay ?? project.shootingDays.last
        guard let source else {
            _ = createShootingPlanDay()
            return
        }
        let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: source.date) ?? Date()
        var copiedSheet = Self.duplicatedCallSheet(source.callSheet)
        copiedSheet.status = .draft
        copiedSheet.updatedAt = Date()

        let nextIndex = project.shootingDays.count + 1
        let newDay = ShootingDay(
            date: nextDate,
            label: L10n.t("第 \(nextIndex) 天", "Day \(nextIndex)", language: language),
            scenes: [Self.makeDefaultScene(sceneNumber: "")],
            callSheet: copiedSheet
        )
        mutateProject { project in
            project.shootingDays.append(newDay)
        }
        selectedShootingDayID = newDay.id
        expandAllHierarchy()
    }

    func deleteShootingPlanDay(_ id: UUID) {
        mutateProject { project in
            guard project.shootingDays.count > 1 else { return }
            project.shootingDays.removeAll { $0.id == id }
        }
    }

    func clearShootingPlanDaySchedule(_ id: UUID) {
        mutateProject { project in
            guard let index = project.shootingDays.firstIndex(where: { $0.id == id }) else { return }
            Self.clearCallSheetSchedule(in: &project, dayIndex: index)
        }
    }

    func clearShootingPlanDaySchedules(on dates: [Date]) {
        let normalizedDates = normalizedUniqueDates(dates)
        guard !normalizedDates.isEmpty else { return }
        mutateProject { project in
            for date in normalizedDates {
                guard let index = project.shootingDays.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) else { continue }
                Self.clearCallSheetSchedule(in: &project, dayIndex: index)
            }
        }
    }

    func deleteShootingPlanDays(on dates: [Date]) {
        let normalizedDates = normalizedUniqueDates(dates)
        guard !normalizedDates.isEmpty else { return }
        mutateProject { project in
            let idsToDelete = Set(project.shootingDays.filter { day in
                normalizedDates.contains { Calendar.current.isDate($0, inSameDayAs: day.date) }
            }.map(\.id))
            guard !idsToDelete.isEmpty else { return }
            let remaining = project.shootingDays.filter { !idsToDelete.contains($0.id) }
            guard !remaining.isEmpty else { return }
            project.shootingDays = remaining
        }
    }

    func updateShootingDay(_ id: UUID, update: (inout ShootingDay) -> Void) {
        mutateProject { project in
            guard let index = project.shootingDays.firstIndex(where: { $0.id == id }) else { return }
            update(&project.shootingDays[index])
            project.shootingDays[index].callSheet.updatedAt = Date()
        }
    }

    func updateScenePlanSceneNumber(dayID: UUID, planID: UUID, value: String) {
        mutateProject { project in
            guard let dayIndex = project.shootingDays.firstIndex(where: { $0.id == dayID }),
                  let planIndex = project.shootingDays[dayIndex].callSheet.scenePlans.firstIndex(where: { $0.id == planID })
            else { return }

            project.shootingDays[dayIndex].callSheet.scenePlans[planIndex].sceneNumber = value
            project.shootingDays[dayIndex].callSheet.updatedAt = Date()
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

            if let linkedID = project.shootingDays[dayIndex].callSheet.scenePlans[planIndex].sceneID,
               let sceneIndex = project.shootingDays[dayIndex].scenes.firstIndex(where: { $0.id == linkedID }) {
                Self.setSceneNumber(in: &project, dayIndex: dayIndex, sceneIndex: sceneIndex, value: value)
                return
            }

            guard !trimmed.isEmpty else { return }
            if let existingIndex = project.shootingDays[dayIndex].scenes.firstIndex(where: { $0.sceneNumber.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed }) {
                project.shootingDays[dayIndex].callSheet.scenePlans[planIndex].sceneID = project.shootingDays[dayIndex].scenes[existingIndex].id
                Self.setSceneNumber(in: &project, dayIndex: dayIndex, sceneIndex: existingIndex, value: value)
            } else {
                let scene = Self.makeDefaultScene(sceneNumber: value)
                project.shootingDays[dayIndex].scenes.append(scene)
                project.shootingDays[dayIndex].callSheet.scenePlans[planIndex].sceneID = scene.id
            }
        }
    }

    func updateMainLocation(dayID: UUID, value: String) {
        mutateProject { project in
            guard let index = project.shootingDays.firstIndex(where: { $0.id == dayID }) else { return }
            project.shootingDays[index].callSheet.mainLocation = value
            project.shootingDays[index].callSheet.updatedAt = Date()
            Self.rememberLocationValue(value, in: &project)
        }
    }

    func updateLocationInfo(dayID: UUID, keyPath: WritableKeyPath<LocationInfo, String>, value: String) {
        mutateProject { project in
            guard let index = project.shootingDays.firstIndex(where: { $0.id == dayID }) else { return }
            project.shootingDays[index].callSheet.locationInfo[keyPath: keyPath] = value
            project.shootingDays[index].callSheet.updatedAt = Date()
            Self.rememberLocationValue(value, in: &project)
        }
    }

    func clearLocationMemory() {
        mutateProject { project in
            project.locationMemory.removeAll()
        }
    }

    func importScriptLogScenesToCallSheet(dayID: UUID) {
        mutateProject { project in
            guard let dayIndex = project.shootingDays.firstIndex(where: { $0.id == dayID }) else { return }
            let existingSceneIDs = Set(project.shootingDays[dayIndex].callSheet.scenePlans.compactMap(\.sceneID))
            let additions = project.shootingDays[dayIndex].scenes
                .filter { !existingSceneIDs.contains($0.id) }
                .map { scene in
                    DayScenePlan(
                        sceneID: scene.id,
                        sceneNumber: scene.sceneNumber,
                        location: "",
                        summary: scene.description,
                        cameraUnits: Array(Set(scene.shots.map(\.cameraSetup))).sorted()
                    )
                }
            guard !additions.isEmpty else { return }
            project.shootingDays[dayIndex].callSheet.scenePlans.append(contentsOf: additions)
            project.shootingDays[dayIndex].callSheet.updatedAt = Date()
        }
    }

    func importPrincipalCastToCallSheet(dayID: UUID) {
        mutateProject { project in
            guard let dayIndex = project.shootingDays.firstIndex(where: { $0.id == dayID }) else { return }
            let existingKeys = Set(project.shootingDays[dayIndex].callSheet.castCalls.map {
                "\($0.performerName.trimmedForCheck.lowercased())|\($0.characterName.trimmedForCheck.lowercased())"
            })
            let additions = project.principalCast.compactMap { cast -> CastCall? in
                let performer = cast.performerName.trimmedForCheck
                let character = cast.characterName.trimmedForCheck
                guard !performer.isEmpty || !character.isEmpty else { return nil }
                let key = "\(performer.lowercased())|\(character.lowercased())"
                guard !existingKeys.contains(key) else { return nil }
                return CastCall(
                    performerName: cast.performerName,
                    characterName: cast.characterName,
                    phone: cast.phone,
                    note: cast.note
                )
            }
            guard !additions.isEmpty else { return }
            project.shootingDays[dayIndex].callSheet.castCalls.append(contentsOf: additions)
            project.shootingDays[dayIndex].callSheet.updatedAt = Date()
        }
    }

    func autofillSunTimesFromMacLocation(dayID: UUID, force: Bool = false) {
        guard let day = project.shootingDays.first(where: { $0.id == dayID }) else { return }
        guard force || day.callSheet.sunriseTime.trimmedForCheck.isEmpty || day.callSheet.sunsetTime.trimmedForCheck.isEmpty else { return }
        guard force || !requestedMacLocationDayIDs.contains(dayID) else { return }
        requestedMacLocationDayIDs.insert(dayID)

        Task { @MainActor in
            let location = force
                ? try? await macLocationProvider.requestLocation()
                : await macLocationProvider.locationIfAuthorized()
            guard let location else {
                requestedMacLocationDayIDs.remove(dayID)
                return
            }
            guard let currentDay = project.shootingDays.first(where: { $0.id == dayID }),
                  let sunTimes = Self.sunTimes(
                    for: currentDay.date,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                  ) else { return }
            let address = await macLocationProvider.address(for: location)
            mutateProject { project in
                guard let index = project.shootingDays.firstIndex(where: { $0.id == dayID }) else { return }
                if force || project.shootingDays[index].callSheet.sunriseTime.trimmedForCheck.isEmpty {
                    project.shootingDays[index].callSheet.sunriseTime = sunTimes.sunrise
                }
                if force || project.shootingDays[index].callSheet.sunsetTime.trimmedForCheck.isEmpty {
                    project.shootingDays[index].callSheet.sunsetTime = sunTimes.sunset
                }
                if let address, project.shootingDays[index].callSheet.mainLocation.trimmedForCheck.isEmpty {
                    project.shootingDays[index].callSheet.mainLocation = address
                    Self.rememberLocationValue(address, in: &project)
                }
                if let address, project.shootingDays[index].callSheet.locationInfo.shootingLocation.trimmedForCheck.isEmpty {
                    project.shootingDays[index].callSheet.locationInfo.shootingLocation = address
                    Self.rememberLocationValue(address, in: &project)
                }
                project.shootingDays[index].callSheet.updatedAt = Date()
            }
        }
    }

    func autofillSunTimesForAllDaysFromMacLocation(force: Bool = false) {
        let candidates = project.shootingDays.filter { day in
            force || day.callSheet.sunriseTime.trimmedForCheck.isEmpty || day.callSheet.sunsetTime.trimmedForCheck.isEmpty
        }
        guard !candidates.isEmpty else { return }

        Task { @MainActor in
            let location = force
                ? try? await macLocationProvider.requestLocation()
                : await macLocationProvider.locationIfAuthorized()
            guard let location else { return }
            let address = await macLocationProvider.address(for: location)
            mutateProject { project in
                for candidate in candidates {
                    guard let index = project.shootingDays.firstIndex(where: { $0.id == candidate.id }),
                          let sunTimes = Self.sunTimes(
                            for: project.shootingDays[index].date,
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude
                          ) else { continue }
                    if force || project.shootingDays[index].callSheet.sunriseTime.trimmedForCheck.isEmpty {
                        project.shootingDays[index].callSheet.sunriseTime = sunTimes.sunrise
                    }
                    if force || project.shootingDays[index].callSheet.sunsetTime.trimmedForCheck.isEmpty {
                        project.shootingDays[index].callSheet.sunsetTime = sunTimes.sunset
                    }
                    if let address, project.shootingDays[index].callSheet.mainLocation.trimmedForCheck.isEmpty {
                        project.shootingDays[index].callSheet.mainLocation = address
                        Self.rememberLocationValue(address, in: &project)
                    }
                    if let address, project.shootingDays[index].callSheet.locationInfo.shootingLocation.trimmedForCheck.isEmpty {
                        project.shootingDays[index].callSheet.locationInfo.shootingLocation = address
                        Self.rememberLocationValue(address, in: &project)
                    }
                    project.shootingDays[index].callSheet.updatedAt = Date()
                }
            }
        }
    }

    func pushCallSheetScenesToScriptLog(dayID: UUID) {
        mutateProject { project in
            guard let dayIndex = project.shootingDays.firstIndex(where: { $0.id == dayID }) else { return }
            for plan in project.shootingDays[dayIndex].callSheet.scenePlans {
                if let sceneID = plan.sceneID,
                   let sceneIndex = project.shootingDays[dayIndex].scenes.firstIndex(where: { $0.id == sceneID }) {
                    project.shootingDays[dayIndex].scenes[sceneIndex].sceneNumber = plan.sceneNumber
                    project.shootingDays[dayIndex].scenes[sceneIndex].description = plan.summary
                    for shotIndex in project.shootingDays[dayIndex].scenes[sceneIndex].shots.indices {
                        for takeIndex in project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes.indices {
                            project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes[takeIndex].sceneNumber = plan.sceneNumber
                        }
                    }
                    if let firstUnit = plan.cameraUnits.first(where: { !$0.trimmedForCheck.isEmpty }),
                       let shotIndex = project.shootingDays[dayIndex].scenes[sceneIndex].shots.indices.first {
                        project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].cameraSetup = firstUnit
                    }
                    if !plan.shotNumber.trimmedForCheck.isEmpty,
                       let shotIndex = project.shootingDays[dayIndex].scenes[sceneIndex].shots.indices.first {
                        project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].shotNumber = plan.shotNumber
                        for takeIndex in project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes.indices {
                            project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes[takeIndex].shotNumber = plan.shotNumber
                        }
                    }
                } else if !plan.sceneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    project.shootingDays[dayIndex].scenes.append(
                        ScriptScene(
                            sceneNumber: plan.sceneNumber,
                            description: plan.summary,
                            shots: [
                                Self.makeDefaultShot(
                                    sceneNumber: plan.sceneNumber,
                                    shotNumber: plan.shotNumber.isEmpty ? "1" : plan.shotNumber
                                )
                            ]
                        )
                    )
                    if let sceneIndex = project.shootingDays[dayIndex].scenes.indices.last,
                       let firstUnit = plan.cameraUnits.first(where: { !$0.trimmedForCheck.isEmpty }) {
                        project.shootingDays[dayIndex].scenes[sceneIndex].shots[0].cameraSetup = firstUnit
                    }
                }
            }
        }
    }

    func callSheetChecks(dayID: UUID?) -> [ShootingDayCheckResult] {
        guard let dayID, let day = project.shootingDays.first(where: { $0.id == dayID }) else { return [] }
        let sheet = day.callSheet
        var results: [ShootingDayCheckResult] = []

        if sheet.callTime.trimmedForCheck.isEmpty {
            results.append(ShootingDayCheckResult(level: .warning, message: t("缺少全组到场", "Missing crew call"), relatedSection: .overview))
        }
        if sheet.mainLocation.trimmedForCheck.isEmpty {
            results.append(ShootingDayCheckResult(level: .warning, message: t("缺少主拍摄地点", "Missing main location"), relatedSection: .overview))
        }
        if sheet.locationInfo.meetingPoint.trimmedForCheck.isEmpty {
            results.append(ShootingDayCheckResult(level: .warning, message: t("缺少集合地点", "Missing meeting point"), relatedSection: .location))
        }
        if sheet.locationInfo.emergencyContactName.trimmedForCheck.isEmpty && sheet.locationInfo.emergencyContactPhone.trimmedForCheck.isEmpty {
            results.append(ShootingDayCheckResult(level: .critical, message: t("缺少紧急联系人", "Missing emergency contact"), relatedSection: .location))
        }
        if sheet.scenePlans.isEmpty {
            results.append(ShootingDayCheckResult(level: .warning, message: t("今日场次为空", "No scenes planned for the day"), relatedSection: .scenes))
        }
        for scene in sheet.scenePlans where scene.location.trimmedForCheck.isEmpty {
            let number = scene.sceneNumber.trimmedForCheck.isEmpty ? t("未命名场次", "Untitled scene") : scene.sceneNumber
            results.append(ShootingDayCheckResult(level: .warning, message: t("第 \(number) 场没有地点", "Scene \(number) has no location"), relatedSection: .scenes))
        }
        for cast in sheet.castCalls where !cast.performerName.trimmedForCheck.isEmpty && cast.callTime.trimmedForCheck.isEmpty {
            results.append(ShootingDayCheckResult(level: .warning, message: t("\(cast.performerName) 没有到场时间", "\(cast.performerName) has no call time"), relatedSection: .cast))
        }
        if sheet.departmentCalls.filter({ $0.showInExport }).isEmpty {
            results.append(ShootingDayCheckResult(level: .info, message: t("部门通告为空", "No department calls"), relatedSection: .departments))
        }
        for camera in sheet.cameraPlans where camera.expectedCardIDs.filter({ !$0.trimmedForCheck.isEmpty }).isEmpty {
            let unit = camera.unitName.trimmedForCheck.isEmpty ? t("未命名机位", "Untitled unit") : camera.unitName
            results.append(ShootingDayCheckResult(level: .warning, message: t("\(unit) 没有分配预计卡号", "\(unit) has no expected card ID"), relatedSection: .camera))
        }
        if sheet.ditPlan.checksumAlgorithm.trimmedForCheck.isEmpty {
            results.append(ShootingDayCheckResult(level: .critical, message: t("DIT 计划缺少校验算法", "DIT plan is missing checksum algorithm"), relatedSection: .dit))
        }
        if sheet.ditPlan.primaryDestinationName.trimmedForCheck.isEmpty && sheet.ditPlan.backupDestinationName.trimmedForCheck.isEmpty {
            results.append(ShootingDayCheckResult(level: .warning, message: t("DIT 计划缺少目标盘", "DIT plan has no destination drive"), relatedSection: .dit))
        }

        if results.isEmpty {
            results.append(ShootingDayCheckResult(level: .info, message: t("发布前检查通过", "Preflight checks passed"), relatedSection: .export))
        }
        return results
    }

    func toggleDayExpanded(_ id: UUID) {
        toggle(id, keyPath: \.expandedDayIDs)
    }

    func toggleSceneExpanded(_ id: UUID) {
        toggle(id, keyPath: \.expandedSceneIDs)
    }

    func toggleShotExpanded(_ id: UUID) {
        toggle(id, keyPath: \.expandedShotIDs)
    }

    func toggleTakeGroupExpanded(for shotID: UUID) {
        toggle(shotID, keyPath: \.expandedTakeGroupIDs)
    }

    func updateSceneNumber(id: UUID, value: String) {
        mutateProject { project in
            for dayIndex in project.shootingDays.indices {
                if let sceneIndex = project.shootingDays[dayIndex].scenes.firstIndex(where: { $0.id == id }) {
                    Self.setSceneNumber(in: &project, dayIndex: dayIndex, sceneIndex: sceneIndex, value: value)
                    return
                }
            }
        }
    }

    func deleteSelectedHierarchyItem() {
        if selectedTakeID != nil {
            deleteCurrentTake()
        } else if selectedShotID != nil {
            deleteCurrentShot()
        } else if selectedSceneID != nil {
            deleteCurrentScene()
        } else if selectedShootingDayID != nil {
            deleteCurrentDay()
        }
    }

    func navigateTake(offset: Int) {
        let allTakes = project.shootingDays.flatMap { day in
            day.scenes.flatMap { scene in
                scene.shots.flatMap { shot in
                    shot.takes.map { (day.id, scene.id, shot.id, $0.id) }
                }
            }
        }
        guard !allTakes.isEmpty else { return }

        let currentIndex = allTakes.firstIndex(where: { $0.3 == selectedTakeID }) ?? -1
        var nextIndex = currentIndex + offset

        if nextIndex < 0 {
            nextIndex = allTakes.count - 1
        } else if nextIndex >= allTakes.count {
            nextIndex = 0
        }

        let target = allTakes[nextIndex]
        selectShootingDay(target.0)
        selectScene(target.1)
        selectShot(target.2)
        selectTake(target.3)
    }

    func navigateScene(offset: Int) {
        let allScenes = project.shootingDays.flatMap { day in
            day.scenes.map { (day.id, $0.id) }
        }
        guard !allScenes.isEmpty else { return }

        let currentIndex = allScenes.firstIndex(where: { $0.1 == selectedSceneID }) ?? -1
        var nextIndex = currentIndex + offset

        if nextIndex < 0 {
            nextIndex = allScenes.count - 1
        } else if nextIndex >= allScenes.count {
            nextIndex = 0
        }

        let target = allScenes[nextIndex]
        selectShootingDay(target.0)
        selectScene(target.1)
    }

    func navigateShot(offset: Int) {
        let allShots = project.shootingDays.flatMap { day in
            day.scenes.flatMap { scene in
                scene.shots.map { (day.id, scene.id, $0.id) }
            }
        }
        guard !allShots.isEmpty else { return }

        let currentIndex = allShots.firstIndex(where: { $0.2 == selectedShotID }) ?? -1
        var nextIndex = currentIndex + offset

        if nextIndex < 0 {
            nextIndex = allShots.count - 1
        } else if nextIndex >= allShots.count {
            nextIndex = 0
        }

        let target = allShots[nextIndex]
        selectShootingDay(target.0)
        selectScene(target.1)
        selectShot(target.2)
    }

    func selectTake(_ id: UUID, isShift: Bool = false, isCommand: Bool = false) {
        if isBatchMode {
            if isShift, let lastID = selectedTakeID, lastID != id {
                var allTakes: [Take] = []
                for d in project.shootingDays {
                    for s in d.scenes {
                        for sh in s.shots {
                            allTakes.append(contentsOf: sh.takes)
                        }
                    }
                }
                if let i1 = allTakes.firstIndex(where: { $0.id == lastID }),
                   let i2 = allTakes.firstIndex(where: { $0.id == id }) {
                    let range = min(i1, i2)...max(i1, i2)
                    let takesToAdd = allTakes[range]
                    for t in takesToAdd {
                        if selectedTakeIDs.count < 20 || selectedTakeIDs.contains(t.id) {
                            selectedTakeIDs.insert(t.id)
                        }
                    }
                }
            } else if isCommand {
                if selectedTakeIDs.contains(id) {
                    selectedTakeIDs.remove(id)
                } else if selectedTakeIDs.count < 20 {
                    selectedTakeIDs.insert(id)
                }
            } else {
                if selectedTakeIDs.contains(id) && selectedTakeIDs.count == 1 {
                    selectedTakeIDs.remove(id)
                } else {
                    selectedTakeIDs = [id]
                }
            }
            selectedTakeID = id
        } else {
            selectedTakeID = id
            selectedTakeIDs = [id]
            normalizeSelection()
        }
    }

    func toggleBatchMode() {
        isBatchMode.toggle()
        if isBatchMode {
            if let current = selectedTakeID {
                selectedTakeIDs = [current]
            } else {
                selectedTakeIDs = []
            }
        } else {
            selectedTakeIDs = []
            if let first = selectedTakeIDs.first {
                selectedTakeID = first
            }
        }
    }

    func addShootingDay() {
        let newDay = ShootingDay(
            date: Date(),
            label: L10n.t("第 \(project.shootingDays.count + 1) 天", "Day \(project.shootingDays.count + 1)", language: language),
            scenes: [Self.makeDefaultScene(sceneNumber: "")]
        )
        let scene = newDay.scenes[0]
        let shot = scene.shots[0]
        let take = shot.takes[0]
        mutateProject { project in
            project.shootingDays.append(newDay)
        }
        selectedShootingDayID = newDay.id
        selectedSceneID = scene.id
        selectedShotID = shot.id
        selectedTakeID = take.id
        expandedDayIDs.insert(newDay.id)
        expandedSceneIDs.insert(scene.id)
        expandedShotIDs.insert(shot.id)
        expandedTakeGroupIDs.insert(shot.id)
    }

    func addScene() {
        guard let dayIndex = selectedDayIndex(in: project) else { return }
        let scene = Self.makeDefaultScene(sceneNumber: "")
        let shot = scene.shots[0]
        let take = shot.takes[0]
        mutateProject { project in
            project.shootingDays[dayIndex].scenes.append(scene)
        }
        selectedSceneID = scene.id
        selectedShotID = shot.id
        selectedTakeID = take.id
        expandedSceneIDs.insert(scene.id)
        expandedShotIDs.insert(shot.id)
        expandedTakeGroupIDs.insert(shot.id)
    }

    func addShot() {
        guard let indexes = selectedSceneIndexes(in: project) else { return }
        let scene = project.shootingDays[indexes.day].scenes[indexes.scene]
        let nextNumber = nextShotNumber(in: scene)
        let shot = Self.makeDefaultShot(sceneNumber: scene.sceneNumber, shotNumber: nextNumber)
        let take = shot.takes[0]
        mutateProject { project in
            project.shootingDays[indexes.day].scenes[indexes.scene].shots.append(shot)
        }
        selectedShotID = shot.id
        selectedTakeID = take.id
        expandedShotIDs.insert(shot.id)
        expandedTakeGroupIDs.insert(shot.id)
    }

    func newNextTake() {
        guard let indexes = selectedShotIndexes(in: project) else { return }
        let shot = project.shootingDays[indexes.day].scenes[indexes.scene].shots[indexes.shot]
        let scene = project.shootingDays[indexes.day].scenes[indexes.scene]
        let nextNumber = nextTakeNumber(in: shot)
        let take = freshTake(
            sceneNumber: scene.sceneNumber,
            shotNumber: shot.shotNumber,
            takeNumber: nextNumber,
            cameraSetup: shot.cameraSetup,
            templateRecords: cameraTemplate(from: currentTake ?? shot.takes.last)
        )
        mutateProject { project in
            project.shootingDays[indexes.day].scenes[indexes.scene].shots[indexes.shot].takes.append(take)
        }
        selectedTakeID = take.id
        expandedTakeGroupIDs.insert(shot.id)
    }

    func newNextFaultEvent() {
        guard let indexes = selectedShotIndexes(in: project) else { return }
        let shot = project.shootingDays[indexes.day].scenes[indexes.scene].shots[indexes.shot]
        let scene = project.shootingDays[indexes.day].scenes[indexes.scene]
        var take = freshTake(
            sceneNumber: scene.sceneNumber,
            shotNumber: shot.shotNumber,
            takeNumber: shot.takes.last?.takeNumber ?? 1, // Doesn't matter
            cameraSetup: shot.cameraSetup,
            templateRecords: cameraTemplate(from: currentTake ?? shot.takes.last)
        )
        take.recordType = .faultEvent
        take.status = .ng
        for i in take.cameraRecords.indices {
            take.cameraRecords[i].rollState = .faultConsumed
            take.cameraRecords[i].status = .ng
        }
        mutateProject { project in
            project.shootingDays[indexes.day].scenes[indexes.scene].shots[indexes.shot].takes.append(take)
        }
        selectedTakeID = take.id
        expandedTakeGroupIDs.insert(shot.id)
    }

    func toggleCurrentFaultEvent() {
        updateCurrentTake { take in
            if take.recordType == .faultEvent {
                if let backup = take.faultBackup {
                    take.status = backup.status
                    take.isCircleTake = backup.isCircleTake
                    for backupRecord in backup.cameraBackups {
                        if let index = take.cameraRecords.firstIndex(where: { $0.id == backupRecord.cameraRecordID }) {
                            take.cameraRecords[index].status = backupRecord.status
                            take.cameraRecords[index].rollState = backupRecord.rollState
                        }
                    }
                } else {
                    take.status = .hold
                    for index in take.cameraRecords.indices {
                        take.cameraRecords[index].status = .hold
                        take.cameraRecords[index].rollState = .recorded
                    }
                }
                take.recordType = .take
                take.faultBackup = nil
            } else {
                take.faultBackup = FaultEventBackup(
                    status: take.status,
                    isCircleTake: take.isCircleTake,
                    cameraBackups: take.cameraRecords.map {
                        CameraFaultBackup(cameraRecordID: $0.id, status: $0.status, rollState: $0.rollState)
                    }
                )
                take.recordType = .faultEvent
                take.status = .ng
                take.isCircleTake = false
                for index in take.cameraRecords.indices {
                    take.cameraRecords[index].rollState = .faultConsumed
                    take.cameraRecords[index].status = .ng
                }
            }
        }
    }

    func newNextShot() {
        guard let indexes = selectedSceneIndexes(in: project) else { return }
        let scene = project.shootingDays[indexes.day].scenes[indexes.scene]
        let previousShot = currentShot ?? scene.shots.last
        let nextNumber = nextShotNumber(in: scene)
        let cameraSetup = previousShot?.cameraSetup ?? "A"
        let take = freshTake(
            sceneNumber: scene.sceneNumber,
            shotNumber: nextNumber,
            takeNumber: 1,
            cameraSetup: cameraSetup,
            templateRecords: cameraTemplate(from: currentTake ?? previousShot?.takes.last)
        )
        let shot = Shot(
            shotNumber: nextNumber,
            cameraSetup: cameraSetup,
            takes: [take]
        )
        mutateProject { project in
            project.shootingDays[indexes.day].scenes[indexes.scene].shots.append(shot)
        }
        selectedShotID = shot.id
        selectedTakeID = take.id
        expandedShotIDs.insert(shot.id)
        expandedTakeGroupIDs.insert(shot.id)
    }

    func newNextScene() {
        guard let dayIndex = selectedDayIndex(in: project) else { return }
        let cameraSetup = currentShot?.cameraSetup ?? "A"
        let take = freshTake(
            sceneNumber: "",
            shotNumber: "1",
            takeNumber: 1,
            cameraSetup: cameraSetup,
            templateRecords: cameraTemplate(from: currentTake ?? currentShot?.takes.last)
        )
        let shot = Shot(
            shotNumber: "1",
            cameraSetup: cameraSetup,
            takes: [take]
        )
        let scene = ScriptScene(
            sceneNumber: "",
            description: "",
            shots: [shot]
        )
        mutateProject { project in
            project.shootingDays[dayIndex].scenes.append(scene)
        }
        selectedSceneID = scene.id
        selectedShotID = shot.id
        selectedTakeID = take.id
        expandedSceneIDs.insert(scene.id)
        expandedShotIDs.insert(shot.id)
        expandedTakeGroupIDs.insert(shot.id)
    }

    func deleteCurrentTake() {
        guard let indexes = selectedTakeIndexes(in: project) else { return }
        mutateProject { project in
            var shot = project.shootingDays[indexes.day].scenes[indexes.scene].shots[indexes.shot]
            shot.takes.remove(at: indexes.take)
            project.shootingDays[indexes.day].scenes[indexes.scene].shots[indexes.shot] = shot
        }
        normalizeSelection()
    }

    func deleteCurrentShot() {
        guard let indexes = selectedShotIndexes(in: project) else { return }
        mutateProject { project in
            var scene = project.shootingDays[indexes.day].scenes[indexes.scene]
            scene.shots.remove(at: indexes.shot)
            project.shootingDays[indexes.day].scenes[indexes.scene] = scene
        }
        normalizeSelection()
    }

    func deleteCurrentScene() {
        guard let dayIndex = selectedDayIndex(in: project) else { return }
        guard let sceneIndex = project.shootingDays[dayIndex].scenes.firstIndex(where: { $0.id == selectedSceneID }) else { return }
        mutateProject { project in
            project.shootingDays[dayIndex].scenes.remove(at: sceneIndex)
        }
        normalizeSelection()
    }

    func deleteCurrentDay() {
        guard let dayIndex = selectedDayIndex(in: project) else { return }
        mutateProject { project in
            project.shootingDays.remove(at: dayIndex)
        }
        normalizeSelection()
    }

    func duplicateCurrentTake() {
        guard let indexes = selectedShotIndexes(in: project) else { return }
        let shot = project.shootingDays[indexes.day].scenes[indexes.scene].shots[indexes.shot]
        let source = currentTake ?? shot.takes.last
        guard let source else {
            newNextTake()
            return
        }
        let take = source.duplicated(nextTakeNumber: nextTakeNumber(in: shot))
        mutateProject { project in
            project.shootingDays[indexes.day].scenes[indexes.scene].shots[indexes.shot].takes.append(take)
        }
        selectedTakeID = take.id
        expandedTakeGroupIDs.insert(shot.id)
    }

    func updateCurrentScene(description: String) {
        guard let indexes = selectedSceneIndexes(in: project) else { return }
        mutateProject { project in
            project.shootingDays[indexes.day].scenes[indexes.scene].description = description
        }
    }

    func undoLastChange() {
        guard let snapshot = undoStack.popLast() else { return }
        project = snapshot.project
        selectedShootingDayID = snapshot.selectedShootingDayID
        selectedSceneID = snapshot.selectedSceneID
        selectedShotID = snapshot.selectedShotID
        selectedTakeID = snapshot.selectedTakeID
        selectedTakeIDs = snapshot.selectedTakeIDs
        normalizeSelection()
        save()
    }

    func updateCurrentShot(cameraSetup: String) {
        guard let indexes = selectedShotIndexes(in: project) else { return }
        mutateProject { project in
            project.shootingDays[indexes.day].scenes[indexes.scene].shots[indexes.shot].cameraSetup = cameraSetup
        }
    }

    func updateCurrentTake(_ update: (inout Take) -> Void) {
        guard let indexes = selectedTakeIndexes(in: project) else { return }
        mutateProject { project in
            var take = project.shootingDays[indexes.day].scenes[indexes.scene].shots[indexes.shot].takes[indexes.take]
            update(&take)
            take.updatedAt = Date()
            project.shootingDays[indexes.day].scenes[indexes.scene].shots[indexes.shot].takes[indexes.take] = take
        }
    }

    func markStatus(_ status: TakeStatus) {
        updateCurrentTake { take in
            take.status = status

            // Synchronize to all camera records based on user logic:
            // If main take is OK, all cameras are OK.
            // If main take is NG, all cameras are NG.
            // If main take is KP, all cameras are KP.
            for index in take.cameraRecords.indices {
                take.cameraRecords[index].status = status
                if status == .good {
                    take.cameraRecords[index].pictureAvailable = true
                    take.cameraRecords[index].audioAvailable = true
                }
            }
        }
    }

    func toggleCircleTake() {
        updateCurrentTake { $0.isCircleTake.toggle() }
    }

    func setPictureUsable(_ usable: Bool) {
        updateCurrentTake { take in
            take.pictureUsable = usable
            for index in take.cameraRecords.indices {
                take.cameraRecords[index].pictureAvailable = usable
            }
        }
    }

    func setSoundUsable(_ usable: Bool) {
        updateCurrentTake { take in
            take.soundUsable = usable
            for index in take.cameraRecords.indices {
                take.cameraRecords[index].audioAvailable = usable
            }
        }
    }

    func batchMarkStatus(_ status: TakeStatus) {
        guard !selectedTakeIDs.isEmpty else { return }
        mutateProject { project in
            for d in project.shootingDays.indices {
                for s in project.shootingDays[d].scenes.indices {
                    for sh in project.shootingDays[d].scenes[s].shots.indices {
                        for t in project.shootingDays[d].scenes[s].shots[sh].takes.indices {
                            let takeId = project.shootingDays[d].scenes[s].shots[sh].takes[t].id
                            if selectedTakeIDs.contains(takeId) {
                                project.shootingDays[d].scenes[s].shots[sh].takes[t].status = status
                                for c in project.shootingDays[d].scenes[s].shots[sh].takes[t].cameraRecords.indices {
                                    project.shootingDays[d].scenes[s].shots[sh].takes[t].cameraRecords[c].status = status
                                    if status == .good {
                                        project.shootingDays[d].scenes[s].shots[sh].takes[t].cameraRecords[c].pictureAvailable = true
                                        project.shootingDays[d].scenes[s].shots[sh].takes[t].cameraRecords[c].audioAvailable = true
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func batchToggleQuickTag(_ tag: String) {
        guard !selectedTakeIDs.isEmpty else { return }
        mutateProject { project in
            // Determine if we are adding or removing. If *all* selected takes have it, remove it. Otherwise, add it to all.
            var hasTagCount = 0
            for d in project.shootingDays.indices {
                for s in project.shootingDays[d].scenes.indices {
                    for sh in project.shootingDays[d].scenes[s].shots.indices {
                        for t in project.shootingDays[d].scenes[s].shots[sh].takes.indices {
                            if selectedTakeIDs.contains(project.shootingDays[d].scenes[s].shots[sh].takes[t].id) {
                                if project.shootingDays[d].scenes[s].shots[sh].takes[t].quickTags.contains(tag) {
                                    hasTagCount += 1
                                }
                            }
                        }
                    }
                }
            }

            let shouldAdd = hasTagCount < selectedTakeIDs.count

            for d in project.shootingDays.indices {
                for s in project.shootingDays[d].scenes.indices {
                    for sh in project.shootingDays[d].scenes[s].shots.indices {
                        for t in project.shootingDays[d].scenes[s].shots[sh].takes.indices {
                            if selectedTakeIDs.contains(project.shootingDays[d].scenes[s].shots[sh].takes[t].id) {
                                if shouldAdd {
                                    if !project.shootingDays[d].scenes[s].shots[sh].takes[t].quickTags.contains(tag) {
                                        project.shootingDays[d].scenes[s].shots[sh].takes[t].quickTags.append(tag)
                                    }
                                } else {
                                    project.shootingDays[d].scenes[s].shots[sh].takes[t].quickTags.removeAll { $0 == tag }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func toggleQuickTag(_ tag: String) {
        updateCurrentTake { take in
            if take.quickTags.contains(tag) {
                take.quickTags.removeAll { $0 == tag }
            } else {
                take.quickTags.append(tag)
            }
        }
    }

    func markPictureUnusable() {
        setPictureUsable(false)
    }

    func markSoundUnusable() {
        setSoundUsable(false)
    }

    func updateCameraRecord(id: UUID, update: (inout CameraRecord) -> Void) {
        guard let indexes = selectedTakeIndexes(in: project) else { return }
        mutateProject { project in
            var take = project.shootingDays[indexes.day].scenes[indexes.scene].shots[indexes.shot].takes[indexes.take]
            guard let index = take.cameraRecords.firstIndex(where: { $0.id == id }) else { return }

            let oldStatus = take.cameraRecords[index].status
            let oldClipName = take.cameraRecords[index].clipName
            let oldCardName = take.cameraRecords[index].cardName

            update(&take.cameraRecords[index])
            let newStatus = take.cameraRecords[index].status

            if oldStatus != newStatus {
                if newStatus == .ng {
                    // User logic: If one camera is NG, the whole take is NG,
                    // but other cameras should fall back to KP if they were OK.
                    take.status = .ng
                    for i in take.cameraRecords.indices {
                        if i != index && take.cameraRecords[i].status == .good {
                            take.cameraRecords[i].status = .hold
                        }
                    }
                } else {
                    let allGood = take.cameraRecords.allSatisfy { $0.status == .good }
                    let anyNG = take.cameraRecords.contains { $0.status == .ng }

                    if allGood {
                        take.status = .good
                    } else if anyNG {
                        take.status = .ng
                    } else {
                        take.status = .hold
                    }
                }
            }

            take.updatedAt = Date()
            project.shootingDays[indexes.day].scenes[indexes.scene].shots[indexes.shot].takes[indexes.take] = take

            let updatedRecord = take.cameraRecords[index]
            if oldClipName != updatedRecord.clipName || oldCardName != updatedRecord.cardName {
                Self.syncCameraRegistry(project: &project, from: updatedRecord)
            }
        }
    }

    func addCameraRecord() {
        updateCurrentTake { take in
            let existingLabels = take.cameraRecords.map(\.cameraLabel)
            let possibleLabels = (0..<7).map { i -> String in
                let letter = String(UnicodeScalar(UInt8(65 + i)))
                return L10n.t("\(letter)机", "Cam \(letter)", language: language)
            }
            let nextLabel = possibleLabels.first(where: { !existingLabels.contains($0) }) ?? L10n.t("新机位", "New Cam", language: language)
            let newRecord = CameraRecord(
                cameraLabel: nextLabel,
                status: .hold,
                clipName: "",
                cardName: "",
                tcIn: "",
                tcOut: "",
                pictureAvailable: true,
                audioAvailable: true,
                notes: ""
            )
            take.cameraRecords.append(newRecord)
        }
    }

    func removeCameraRecord(id: UUID) {
        updateCurrentTake { take in
            take.cameraRecords.removeAll { $0.id == id }
        }
    }

    func bindClipFiles() {
        let panel = NSOpenPanel()
        panel.title = t("绑定素材文件", "Link Media Files")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                addClipReference(
                    ClipReference(
                        fileName: url.lastPathComponent,
                        filePath: url.path
                    )
                )
            }
        }
    }

    func addClipReference(_ clip: ClipReference) {
        updateCurrentTake { take in
            take.linkedClips.append(clip)
        }
    }

    func removeClipReference(id: UUID) {
        updateCurrentTake { take in
            take.linkedClips.removeAll { $0.id == id }
        }
    }

    func updateClipReference(id: UUID, update: (inout ClipReference) -> Void) {
        updateCurrentTake { take in
            guard let index = take.linkedClips.firstIndex(where: { $0.id == id }) else { return }
            update(&take.linkedClips[index])
        }
    }

    func exportCSV() {
        export(defaultName: exportFileName(attribute: t("场记", "Script Log"), extension: "csv"), allowedType: .commaSeparatedText) { url in
            try ScriptLogExporter.writeCSV(project: project, language: language, to: url)
        }
    }

    func exportJSON() {
        export(defaultName: exportFileName(attribute: t("场记", "Script Log"), extension: "json"), allowedType: .json) { url in
            try ScriptLogExporter.writeJSON(project: project, to: url)
        }
    }

    func exportPDFPlaceholder() {
        export(defaultName: exportFileName(attribute: t("场记", "Script Log"), extension: "pdf"), allowedType: .pdf) { url in
            try ScriptLogExporter.writePDFPlaceholder(project: project, language: language, to: url)
        }
    }

    func exportCallSheet(dayID: UUID, format: CallSheetExportFormat) {
        guard let day = project.shootingDays.first(where: { $0.id == dayID }) else { return }
        let code = shootingDayCode(for: dayID)
        let type = format == .html ? UTType.html : UTType.json
        export(
            defaultName: exportFileName(attribute: "\(t("通告单", "Call Sheet"))_\(code)", extension: format.fileExtension),
            allowedType: type
        ) { url in
            switch format {
            case .html:
                try callSheetHTML(day: day, dayCode: code).write(to: url, atomically: true, encoding: .utf8)
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let document = CallSheetExportDocument(project: project.metadataOnly, dayCode: code, day: day, exportedAt: Date())
                try encoder.encode(document).write(to: url, options: .atomic)
            }
        }
    }

    private func loadInitialProject() {
        let savedPath = UserDefaults.standard.string(forKey: folderDefaultsKey)
        let folder = savedPath.map(URL.init(fileURLWithPath:)) ?? Self.defaultProjectFolderURL()
        projectFolderURL = folder
        if ProjectRepository.isProjectFolder(folder) {
            loadProject(from: folder)
        } else {
            project = Self.makeDefaultProject(language: language)
            normalizeSelection()
            save()
        }
    }

    private func loadProject(from folder: URL) {
        do {
            let loaded = try ProjectRepository.load(from: folder)
            projectFolderURL = folder
            project = loaded
            undoStack.removeAll()
            hasUnsavedChanges = false
            expandedDayIDs.removeAll()
            expandedSceneIDs.removeAll()
            expandedShotIDs.removeAll()
            expandedTakeGroupIDs.removeAll()
            normalizeSelection()
            alertMessage = nil
        } catch {
            alertMessage = t("场记读取失败：\(error.localizedDescription)", "Load failed: \(error.localizedDescription)")
            project = Self.makeDefaultProject(language: language)
            undoStack.removeAll()
            normalizeSelection()
        }
    }

    private func saveToDisk() throws {
        guard let folder = projectFolderURL else { return }
        try ProjectRepository.save(project, to: folder)
    }

    func mutateProject(_ update: (inout Project) -> Void) {
        let before = makeSnapshot()
        var updated = project
        update(&updated)
        guard updated != project else { return }
        undoStack.append(before)
        if undoStack.count > 100 {
            undoStack.removeFirst(undoStack.count - 100)
        }
        project = updated
        hasUnsavedChanges = true
        normalizeSelection()
        scheduleSave()
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.save()
            }
        }
        saveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func toggle(_ id: UUID, keyPath: ReferenceWritableKeyPath<ScriptLogStore, Set<UUID>>) {
        if self[keyPath: keyPath].contains(id) {
            self[keyPath: keyPath].remove(id)
        } else {
            self[keyPath: keyPath].insert(id)
        }
    }

    private func makeSnapshot() -> ProjectSnapshot {
        ProjectSnapshot(
            project: project,
            selectedShootingDayID: selectedShootingDayID,
            selectedSceneID: selectedSceneID,
            selectedShotID: selectedShotID,
            selectedTakeID: selectedTakeID,
            selectedTakeIDs: selectedTakeIDs
        )
    }

    private func normalizeSelection() {
        if project.cameraRegistry.isEmpty {
            project.cameraRegistry = Project.defaultCameraRegistry
        }
        if project.principalCast.isEmpty {
            project.principalCast = [PrincipalCastMember()]
        }
        if project.departmentContacts.isEmpty {
            project.departmentContacts = [DepartmentContact(departmentName: L10n.t("导演组", "Director", language: language))]
        }
        for index in project.cameraRegistry.indices {
            project.cameraRegistry[index].normalizeCards()
        }
        for dayIndex in project.shootingDays.indices {
            if project.shootingDays[dayIndex].callSheet.departmentCalls.isEmpty {
                project.shootingDays[dayIndex].callSheet.departmentCalls = DepartmentCall.defaultDepartments()
            }
            if project.shootingDays[dayIndex].callSheet.cameraPlans.isEmpty {
                project.shootingDays[dayIndex].callSheet.cameraPlans = project.cameraRegistry.map { camera in
                    CameraCardPlan(
                        unitName: camera.label,
                        cameraID: camera.id,
                        expectedCardIDs: camera.cardNames.isEmpty ? [camera.currentCard] : camera.cardNames
                    )
                }
            }
            if project.shootingDays[dayIndex].callSheet.ditPlan.ditName.isEmpty {
                project.shootingDays[dayIndex].callSheet.ditPlan.ditName = project.ditName
            }
        }
        if project.shootingDays.isEmpty {
            project.shootingDays = [Self.makeDefaultShootingDay(language: language)]
        }
        if selectedShootingDayID == nil || !project.shootingDays.contains(where: { $0.id == selectedShootingDayID }) {
            selectedShootingDayID = project.shootingDays.first?.id
        }
        guard let dayIndex = selectedDayIndex(in: project) else { return }

        if project.shootingDays[dayIndex].scenes.isEmpty {
            project.shootingDays[dayIndex].scenes = [Self.makeDefaultScene(sceneNumber: "")]
        }
        if selectedSceneID == nil || !project.shootingDays[dayIndex].scenes.contains(where: { $0.id == selectedSceneID }) {
            selectedSceneID = project.shootingDays[dayIndex].scenes.first?.id
        }
        guard let sceneIndex = selectedSceneIndex(in: project, dayIndex: dayIndex) else { return }

        if project.shootingDays[dayIndex].scenes[sceneIndex].shots.isEmpty {
            let sceneNumber = project.shootingDays[dayIndex].scenes[sceneIndex].sceneNumber
            project.shootingDays[dayIndex].scenes[sceneIndex].shots = [Self.makeDefaultShot(sceneNumber: sceneNumber, shotNumber: "1")]
        }
        if selectedShotID == nil || !project.shootingDays[dayIndex].scenes[sceneIndex].shots.contains(where: { $0.id == selectedShotID }) {
            selectedShotID = project.shootingDays[dayIndex].scenes[sceneIndex].shots.first?.id
        }
        guard let shotIndex = selectedShotIndex(in: project, dayIndex: dayIndex, sceneIndex: sceneIndex) else { return }

        if project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes.isEmpty {
            let scene = project.shootingDays[dayIndex].scenes[sceneIndex]
            let shot = project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex]
            project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes = [
                Take(sceneNumber: scene.sceneNumber, shotNumber: shot.shotNumber, cameraLabel: shot.cameraSetup)
            ]
        }
        for takeIndex in project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes.indices {
            if project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes[takeIndex].cameraRecords.isEmpty {
                project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes[takeIndex].cameraRecords = project.cameraRegistry.map { reg in
                    CameraRecord(
                        cameraLabel: reg.label,
                        status: .hold,
                        rollState: .recorded,
                        clipName: reg.nextExpectedClipID,
                        cardName: reg.currentCard
                    )
                }
            }
        }
        if selectedTakeID == nil || !project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes.contains(where: { $0.id == selectedTakeID }) {
            selectedTakeID = project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes.first?.id
        }

        if expandedDayIDs.isEmpty && expandedSceneIDs.isEmpty && expandedShotIDs.isEmpty && expandedTakeGroupIDs.isEmpty {
            expandedDayIDs = Set(project.shootingDays.map(\.id))
            expandedSceneIDs = Set(project.shootingDays.flatMap { $0.scenes.map(\.id) })
            expandedShotIDs = Set(project.shootingDays.flatMap { $0.scenes.flatMap { $0.shots.map(\.id) } })
            expandedTakeGroupIDs = expandedShotIDs
        }
    }

    private func export(defaultName: String, allowedType: UTType, write: (URL) throws -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [allowedType]
        panel.directoryURL = reportsDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try write(url)
                lastExportURL = url
                alertMessage = nil
            } catch {
                alertMessage = t("场记导出失败：\(error.localizedDescription)", "Export failed: \(error.localizedDescription)")
            }
        }
    }

    private func exportFileName(attribute: String, extension ext: String) -> String {
        OutputFileNamer.fileName(
            projectName: project.displayName,
            date: Date(),
            attribute: attribute,
            extension: ext
        )
    }

    private func callSheetHTML(day: ShootingDay, dayCode: String) -> String {
        let sheet = day.callSheet
        let projectName = htmlEscaped(LocalizedDisplay.projectName(project, language: language.resolved))
        let title = htmlEscaped(sheet.title.trimmedForCheck.isEmpty ? "\(dayCode) \(t("通告单", "Call Sheet"))" : sheet.title)
        let dateText = htmlEscaped(displayDate.string(from: day.date))
        let status = htmlEscaped(sheet.status.label(language: language.resolved))
        let type = htmlEscaped(sheet.type.label(language: language.resolved))
        let scenes = sheet.scenePlans.map { scene in
            """
            <tr>
              <td>\(htmlEscaped(scene.sceneNumber))</td>
              <td>\(htmlEscaped(scene.location))</td>
              <td>\(htmlEscaped(scene.summary))</td>
              <td>\(htmlEscaped(scene.cast.joined(separator: ", ")))</td>
              <td>\(htmlEscaped(scene.cameraUnits.joined(separator: ", ")))</td>
            </tr>
            """
        }.joined(separator: "\n")
        let timeline = sheet.timeline.map { item in
            "<tr><td>\(htmlEscaped(item.time))</td><td>\(htmlEscaped(item.category.label(language: language.resolved)))</td><td>\(htmlEscaped(item.title))</td><td>\(htmlEscaped(item.note))</td></tr>"
        }.joined(separator: "\n")
        let cast = sheet.castCalls.filter(\.showInExport).map { item in
            "<tr><td>\(htmlEscaped(item.performerName))</td><td>\(htmlEscaped(item.characterName))</td><td>\(htmlEscaped(item.callTime))</td><td>\(htmlEscaped(item.makeupTime))</td><td>\(htmlEscaped(item.note))</td></tr>"
        }.joined(separator: "\n")
        let departments = sheet.departmentCalls.filter(\.showInExport).map { item in
            "<tr><td>\(htmlEscaped(item.departmentName))</td><td>\(htmlEscaped(item.callTime))</td><td>\(htmlEscaped(item.leadName))</td><td>\(htmlEscaped(item.note))</td></tr>"
        }.joined(separator: "\n")
        let cameras = sheet.cameraPlans.map { item in
            "<tr><td>\(htmlEscaped(item.unitName))</td><td>\(htmlEscaped(item.cameraName))</td><td>\(htmlEscaped(item.recordingFormat))</td><td>\(htmlEscaped(item.expectedCardIDs.joined(separator: ", ")))</td><td>\(htmlEscaped(item.note))</td></tr>"
        }.joined(separator: "\n")
        let htmlLang = language.resolved == .zh ? "zh-CN" : "en"
        func label(_ zh: String, _ en: String) -> String {
            htmlEscaped(t(zh, en))
        }

        return """
        <!doctype html>
        <html lang="\(htmlLang)">
        <head>
          <meta charset="utf-8">
          <title>\(projectName) \(title)</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif; margin: 40px; color: #1d1d1f; }
            header { border-bottom: 2px solid #1d1d1f; padding-bottom: 18px; margin-bottom: 24px; }
            h1 { margin: 0 0 8px; font-size: 30px; }
            h2 { margin: 28px 0 10px; font-size: 18px; }
            .meta { color: #6e6e73; font-size: 13px; display: flex; gap: 16px; flex-wrap: wrap; }
            .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px; }
            .box { border: 1px solid #d2d2d7; border-radius: 10px; padding: 12px; min-height: 54px; }
            .label { color: #86868b; font-size: 11px; margin-bottom: 5px; }
            table { width: 100%; border-collapse: collapse; font-size: 13px; }
            th, td { border-bottom: 1px solid #e5e5ea; padding: 8px 6px; text-align: left; vertical-align: top; }
            th { color: #6e6e73; font-size: 11px; text-transform: uppercase; letter-spacing: .03em; }
            footer { margin-top: 36px; color: #86868b; font-size: 11px; }
          </style>
        </head>
        <body>
          <header>
            <h1>\(projectName) · \(title)</h1>
            <div class="meta"><span>\(dayCode)</span><span>\(dateText)</span><span>\(type)</span><span>\(status)</span></div>
          </header>
          <section class="grid">
            <div class="box"><div class="label">\(label("全组到场", "Crew Call"))</div>\(htmlEscaped(sheet.callTime))</div>
            <div class="box"><div class="label">\(label("预计开机", "Estimated Start"))</div>\(htmlEscaped(sheet.estimatedStartTime))</div>
            <div class="box"><div class="label">\(label("预计收工", "Estimated Wrap"))</div>\(htmlEscaped(sheet.estimatedWrapTime))</div>
            <div class="box"><div class="label">\(label("主地点", "Main Location"))</div>\(htmlEscaped(sheet.mainLocation))</div>
            <div class="box"><div class="label">\(label("集合地点", "Meeting Point"))</div>\(htmlEscaped(sheet.locationInfo.meetingPoint))</div>
            <div class="box"><div class="label">\(label("紧急联系人", "Emergency Contact"))</div>\(htmlEscaped(sheet.locationInfo.emergencyContactName)) \(htmlEscaped(sheet.locationInfo.emergencyContactPhone))</div>
          </section>
          <h2>\(label("时间安排", "Schedule"))</h2><table><thead><tr><th>\(label("时间", "Time"))</th><th>\(label("类型", "Type"))</th><th>\(label("内容", "Title"))</th><th>\(label("备注", "Note"))</th></tr></thead><tbody>\(timeline)</tbody></table>
          <h2>\(label("今日场次", "Scenes Today"))</h2><table><thead><tr><th>\(label("场次", "Scene"))</th><th>\(label("地点", "Location"))</th><th>\(label("内容", "Summary"))</th><th>\(label("演员", "Cast"))</th><th>\(label("机位", "Unit"))</th></tr></thead><tbody>\(scenes)</tbody></table>
          <h2>\(label("演员通告", "Cast Calls"))</h2><table><thead><tr><th>\(label("演员", "Performer"))</th><th>\(label("角色", "Character"))</th><th>\(label("到场", "Call"))</th><th>\(label("化妆", "Makeup"))</th><th>\(label("备注", "Note"))</th></tr></thead><tbody>\(cast)</tbody></table>
          <h2>\(label("部门通告", "Department Calls"))</h2><table><thead><tr><th>\(label("部门", "Department"))</th><th>\(label("到场", "Call"))</th><th>\(label("负责人", "Lead"))</th><th>\(label("备注", "Note"))</th></tr></thead><tbody>\(departments)</tbody></table>
          <h2>\(label("摄影机 / 卡号计划", "Camera / Card Plan"))</h2><table><thead><tr><th>\(label("机位", "Unit"))</th><th>\(label("摄影机", "Camera"))</th><th>\(label("格式", "Format"))</th><th>\(label("预计卡号", "Expected Cards"))</th><th>\(label("备注", "Note"))</th></tr></thead><tbody>\(cameras)</tbody></table>
          <h2>\(label("DIT / 代理 / 后期交接", "DIT / Proxy / Handoff"))</h2>
          <section class="grid">
            <div class="box"><div class="label">DIT</div>\(htmlEscaped(sheet.ditPlan.ditName))</div>
            <div class="box"><div class="label">\(label("校验算法", "Checksum"))</div>\(htmlEscaped(sheet.ditPlan.checksumAlgorithm))</div>
            <div class="box"><div class="label">\(label("代理格式", "Proxy Format"))</div>\(htmlEscaped(sheet.ditPlan.proxyFormat))</div>
          </section>
          <footer>\(label("321Doit 生成", "Generated by 321Doit")) · \(htmlEscaped(displayDateTime.string(from: Date())))</footer>
        </body>
        </html>
        """
    }

    private func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func t(_ zh: String, _ en: String) -> String {
        L10n.t(zh, en, language: language)
    }

    private var displayDate: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.resolved == .en ? "en_US_POSIX" : "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }

    private var displayDateTime: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.resolved == .en ? "en_US_POSIX" : "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private func selectedDayIndex(in project: Project) -> Int? {
        guard let id = selectedShootingDayID else { return project.shootingDays.indices.first }
        return project.shootingDays.firstIndex(where: { $0.id == id })
    }

    private func selectedSceneIndex(in project: Project, dayIndex: Int) -> Int? {
        guard let id = selectedSceneID else { return project.shootingDays[dayIndex].scenes.indices.first }
        return project.shootingDays[dayIndex].scenes.firstIndex(where: { $0.id == id })
    }

    private func selectedShotIndex(in project: Project, dayIndex: Int, sceneIndex: Int) -> Int? {
        guard let id = selectedShotID else { return project.shootingDays[dayIndex].scenes[sceneIndex].shots.indices.first }
        return project.shootingDays[dayIndex].scenes[sceneIndex].shots.firstIndex(where: { $0.id == id })
    }

    private func selectedTakeIndex(in project: Project, dayIndex: Int, sceneIndex: Int, shotIndex: Int) -> Int? {
        guard let id = selectedTakeID else {
            return project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes.indices.first
        }
        return project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes.firstIndex(where: { $0.id == id })
    }

    private func selectedSceneIndexes(in project: Project) -> (day: Int, scene: Int)? {
        guard let day = selectedDayIndex(in: project),
              let scene = selectedSceneIndex(in: project, dayIndex: day) else { return nil }
        return (day, scene)
    }

    private func selectedShotIndexes(in project: Project) -> (day: Int, scene: Int, shot: Int)? {
        guard let indexes = selectedSceneIndexes(in: project),
              let shot = selectedShotIndex(in: project, dayIndex: indexes.day, sceneIndex: indexes.scene) else { return nil }
        return (indexes.day, indexes.scene, shot)
    }

    private func selectedTakeIndexes(in project: Project) -> (day: Int, scene: Int, shot: Int, take: Int)? {
        guard let indexes = selectedShotIndexes(in: project),
              let take = selectedTakeIndex(in: project, dayIndex: indexes.day, sceneIndex: indexes.scene, shotIndex: indexes.shot) else { return nil }
        return (indexes.day, indexes.scene, indexes.shot, take)
    }

    private func expandDescendants(inDay dayID: UUID) {
        guard let day = project.shootingDays.first(where: { $0.id == dayID }) else { return }
        let sceneIDs = day.scenes.map(\.id)
        let shotIDs = day.scenes.flatMap { $0.shots.map(\.id) }
        expandedSceneIDs.formUnion(sceneIDs)
        expandedShotIDs.formUnion(shotIDs)
        expandedTakeGroupIDs.formUnion(shotIDs)
    }

    private func expandDescendants(inScene sceneID: UUID) {
        guard let scene = project.shootingDays.flatMap(\.scenes).first(where: { $0.id == sceneID }) else { return }
        let shotIDs = scene.shots.map(\.id)
        expandedShotIDs.formUnion(shotIDs)
        expandedTakeGroupIDs.formUnion(shotIDs)
    }

    private func selectFirstSceneShotTake(inDay dayID: UUID) {
        guard let day = project.shootingDays.first(where: { $0.id == dayID }) else {
            normalizeSelection()
            return
        }
        selectedSceneID = day.scenes.first?.id
        selectedShotID = day.scenes.first?.shots.first?.id
        selectedTakeID = day.scenes.first?.shots.first?.takes.first?.id
        selectedTakeIDs = selectedTakeID.map { [$0] } ?? []
        normalizeSelection()
    }

    private func selectFirstShotTake(inScene sceneID: UUID) {
        guard let dayIndex = selectedDayIndex(in: project),
              let scene = project.shootingDays[dayIndex].scenes.first(where: { $0.id == sceneID }) else {
            normalizeSelection()
            return
        }
        selectedShotID = scene.shots.first?.id
        selectedTakeID = scene.shots.first?.takes.first?.id
        selectedTakeIDs = selectedTakeID.map { [$0] } ?? []
        normalizeSelection()
    }

    private func selectFirstTake(inShot shotID: UUID) {
        guard let indexes = selectedSceneIndexes(in: project),
              let shot = project.shootingDays[indexes.day].scenes[indexes.scene].shots.first(where: { $0.id == shotID }) else {
            normalizeSelection()
            return
        }
        selectedTakeID = shot.takes.first?.id
        selectedTakeIDs = selectedTakeID.map { [$0] } ?? []
        normalizeSelection()
    }

    private func normalizedUniqueDates(_ dates: [Date]) -> [Date] {
        var seen = Set<Date>()
        return dates
            .map { Calendar.current.startOfDay(for: $0) }
            .sorted()
            .filter { seen.insert($0).inserted }
    }

    private static func rememberLocationValue(_ value: String, in project: inout Project) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if project.locationMemory.contains(where: { existing in
            let old = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            return old.count > trimmed.count && old.hasPrefix(trimmed)
        }) {
            return
        }
        let pruned = project.locationMemory.filter { existing in
            let old = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            return !(trimmed.count > old.count && trimmed.hasPrefix(old))
        }
        project.locationMemory = Project.normalizedMemory([trimmed] + pruned)
    }

    private static func setSceneNumber(in project: inout Project, dayIndex: Int, sceneIndex: Int, value: String) {
        project.shootingDays[dayIndex].scenes[sceneIndex].sceneNumber = value
        for shotIndex in project.shootingDays[dayIndex].scenes[sceneIndex].shots.indices {
            for takeIndex in project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes.indices {
                project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes[takeIndex].sceneNumber = value
            }
        }
        for planIndex in project.shootingDays[dayIndex].callSheet.scenePlans.indices
            where project.shootingDays[dayIndex].callSheet.scenePlans[planIndex].sceneID == project.shootingDays[dayIndex].scenes[sceneIndex].id {
            project.shootingDays[dayIndex].callSheet.scenePlans[planIndex].sceneNumber = value
        }
    }

    private static func syncCameraUsageToRegistry(
        project: inout Project,
        oldCamera: RegisteredCamera? = nil,
        newCamera: RegisteredCamera? = nil,
        pruneScriptLogRecords: Bool
    ) {
        let activeLabels = Set(project.cameraRegistry.map(\.label))

        for dayIndex in project.shootingDays.indices {
            var nextPlans: [CameraCardPlan] = []
            for camera in project.cameraRegistry {
                let existing = project.shootingDays[dayIndex].callSheet.cameraPlans.first {
                    $0.cameraID == camera.id || $0.unitName == camera.label || $0.unitName == oldCamera?.label
                }
                var plan = existing ?? CameraCardPlan()
                plan.unitName = camera.label
                plan.cameraID = camera.id
                plan.expectedCardIDs = camera.cardNames.isEmpty ? [camera.currentCard].filter { !$0.isEmpty } : camera.cardNames
                nextPlans.append(plan)
            }
            project.shootingDays[dayIndex].callSheet.cameraPlans = nextPlans

            for sceneIndex in project.shootingDays[dayIndex].scenes.indices {
                for shotIndex in project.shootingDays[dayIndex].scenes[sceneIndex].shots.indices {
                    for takeIndex in project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes.indices {
                        var records = project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes[takeIndex].cameraRecords
                        if pruneScriptLogRecords {
                            records.removeAll { !activeLabels.contains($0.cameraLabel) }
                        }
                        if let oldCamera, let newCamera {
                            for recordIndex in records.indices where records[recordIndex].cameraLabel == oldCamera.label {
                                records[recordIndex].cameraLabel = newCamera.label
                                if records[recordIndex].clipName.trimmedForCheck.isEmpty || records[recordIndex].clipName == oldCamera.nextExpectedClipID {
                                    records[recordIndex].clipName = newCamera.nextExpectedClipID
                                }
                                if records[recordIndex].cardName.trimmedForCheck.isEmpty || oldCamera.cardNames.contains(records[recordIndex].cardName) || records[recordIndex].cardName == oldCamera.currentCard {
                                    records[recordIndex].cardName = newCamera.currentCard
                                }
                            }
                        }
                        for camera in project.cameraRegistry where !records.contains(where: { $0.cameraLabel == camera.label }) {
                            records.append(
                                CameraRecord(
                                    cameraLabel: camera.label,
                                    status: .hold,
                                    rollState: .recorded,
                                    clipName: camera.nextExpectedClipID,
                                    cardName: camera.currentCard
                                )
                            )
                        }
                        project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes[takeIndex].cameraRecords = records
                    }
                }
            }
        }
    }

    private static func cameraLetter(for index: Int) -> String {
        let scalars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        guard scalars.indices.contains(index) else { return "Z" }
        return String(scalars[index])
    }

    private static func dayCode(in project: Project, dayID: UUID) -> String {
        guard let index = project.shootingDays.firstIndex(where: { $0.id == dayID }) else { return "D--" }
        return String(format: "D%02d", index + 1)
    }

    private static func defaultCallSheet(from project: Project) -> ShootingDayCallSheet {
        var sheet = ShootingDayCallSheet()
        sheet.ditPlan.ditName = project.ditName
        sheet.castCalls = project.principalCast.compactMap { cast in
            let performer = cast.performerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let character = cast.characterName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !performer.isEmpty || !character.isEmpty else { return nil }
            return CastCall(
                performerName: cast.performerName,
                characterName: cast.characterName,
                phone: cast.phone,
                note: cast.note
            )
        }
        let departmentCalls = project.departmentContacts.compactMap { contact -> DepartmentCall? in
            let department = contact.departmentName.trimmingCharacters(in: .whitespacesAndNewlines)
            let lead = contact.leadName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !department.isEmpty || !lead.isEmpty else { return nil }
            return DepartmentCall(
                departmentName: contact.departmentName,
                leadName: contact.leadName,
                phone: contact.phone,
                note: contact.note
            )
        }
        if !departmentCalls.isEmpty {
            sheet.departmentCalls = departmentCalls
        }
        sheet.cameraPlans = project.cameraRegistry.map { camera in
            CameraCardPlan(
                unitName: camera.label,
                cameraID: camera.id,
                expectedCardIDs: camera.cardNames.isEmpty ? [camera.currentCard] : camera.cardNames
            )
        }
        if sheet.cameraPlans.isEmpty {
            sheet.cameraPlans = CameraCardPlan.defaultPlans()
        }
        return sheet
    }

    private static func clearCallSheetSchedule(in project: inout Project, dayIndex: Int) {
        let oldID = project.shootingDays[dayIndex].id
        let oldDate = project.shootingDays[dayIndex].date
        let oldLabel = project.shootingDays[dayIndex].label
        let oldType = project.shootingDays[dayIndex].callSheet.type
        let oldScenes = project.shootingDays[dayIndex].scenes
        var cleanSheet = defaultCallSheet(from: project)
        cleanSheet.type = oldType
        cleanSheet.timeline = []
        cleanSheet.scenePlans = []
        cleanSheet.castCalls = []
        cleanSheet.generalNote = ""
        cleanSheet.updatedAt = Date()
        project.shootingDays[dayIndex] = ShootingDay(
            id: oldID,
            date: oldDate,
            label: oldLabel,
            scenes: oldScenes,
            callSheet: cleanSheet
        )
    }

    private static func sunTimes(for date: Date, latitude: Double, longitude: Double) -> (sunrise: String, sunset: String)? {
        guard abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        guard let sunrise = solarTime(for: date, latitude: latitude, longitude: longitude, isSunrise: true),
              let sunset = solarTime(for: date, latitude: latitude, longitude: longitude, isSunrise: false) else { return nil }
        return (formatSolarHour(sunrise, date: date), formatSolarHour(sunset, date: date))
    }

    private static func solarTime(for date: Date, latitude: Double, longitude: Double, isSunrise: Bool) -> Double? {
        let calendar = Calendar.current
        guard let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) else { return nil }

        let longitudeHour = longitude / 15.0
        let approximateTime = Double(dayOfYear) + ((isSunrise ? 6.0 : 18.0) - longitudeHour) / 24.0
        let meanAnomaly = (0.9856 * approximateTime) - 3.289
        var trueLongitude = meanAnomaly
            + (1.916 * sin(degreesToRadians(meanAnomaly)))
            + (0.020 * sin(2 * degreesToRadians(meanAnomaly)))
            + 282.634
        trueLongitude = normalizedDegrees(trueLongitude)

        var rightAscension = radiansToDegrees(atan(0.91764 * tan(degreesToRadians(trueLongitude))))
        rightAscension = normalizedDegrees(rightAscension)
        let longitudeQuadrant = floor(trueLongitude / 90.0) * 90.0
        let ascensionQuadrant = floor(rightAscension / 90.0) * 90.0
        rightAscension = (rightAscension + longitudeQuadrant - ascensionQuadrant) / 15.0

        let sinDeclination = 0.39782 * sin(degreesToRadians(trueLongitude))
        let cosDeclination = cos(asin(sinDeclination))
        let zenith = 90.833
        let cosHour = (cos(degreesToRadians(zenith)) - (sinDeclination * sin(degreesToRadians(latitude))))
            / (cosDeclination * cos(degreesToRadians(latitude)))

        guard cosHour >= -1, cosHour <= 1 else { return nil }
        let hourAngle = (isSunrise ? 360.0 - radiansToDegrees(acos(cosHour)) : radiansToDegrees(acos(cosHour))) / 15.0
        let localMeanTime = hourAngle + rightAscension - (0.06571 * approximateTime) - 6.622
        let utcHour = normalizedHour(localMeanTime - longitudeHour)
        let timeZoneHours = Double(TimeZone.current.secondsFromGMT(for: date)) / 3600.0
        return normalizedHour(utcHour + timeZoneHours)
    }

    private static func formatSolarHour(_ value: Double, date: Date) -> String {
        let hour = Int(floor(value))
        let minute = Int(round((value - Double(hour)) * 60.0))
        let adjustedHour = (hour + minute / 60) % 24
        let adjustedMinute = minute % 60
        return String(format: "%02d:%02d", adjustedHour, adjustedMinute)
    }

    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func radiansToDegrees(_ radians: Double) -> Double {
        radians * 180 / .pi
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value < 0 { value += 360 }
        return value
    }

    private static func normalizedHour(_ hour: Double) -> Double {
        var value = hour.truncatingRemainder(dividingBy: 24)
        if value < 0 { value += 24 }
        return value
    }

    private static func duplicatedCallSheet(_ source: ShootingDayCallSheet) -> ShootingDayCallSheet {
        var copy = source
        copy.timeline = source.timeline.map {
            var item = $0
            item.id = UUID()
            return item
        }
        copy.scenePlans = source.scenePlans.map {
            var item = $0
            item.id = UUID()
            item.sceneID = nil
            item.isCompleted = false
            return item
        }
        copy.castCalls = source.castCalls.map {
            var item = $0
            item.id = UUID()
            return item
        }
        copy.departmentCalls = source.departmentCalls.map {
            var item = $0
            item.id = UUID()
            return item
        }
        copy.cameraPlans = source.cameraPlans.map {
            var item = $0
            item.id = UUID()
            return item
        }
        copy.revisions = []
        return copy
    }

    private static func propagatedCallSheet(_ source: ShootingDayCallSheet, preservingIDsFrom existing: ShootingDayCallSheet? = nil) -> ShootingDayCallSheet {
        var copy = source
        if let existing {
            copy.status = existing.status
        }
        copy.timeline = source.timeline.enumerated().map { offset, sourceItem in
            var item = sourceItem
            item.id = Self.preservedID(from: existing?.timeline, at: offset)
            return item
        }
        copy.scenePlans = source.scenePlans.enumerated().map { offset, sourceItem in
            var item = sourceItem
            item.id = Self.preservedID(from: existing?.scenePlans, at: offset)
            item.sceneID = nil
            item.isCompleted = false
            return item
        }
        copy.castCalls = source.castCalls.enumerated().map { offset, sourceItem in
            var item = sourceItem
            item.id = Self.preservedID(from: existing?.castCalls, at: offset)
            return item
        }
        copy.departmentCalls = source.departmentCalls.enumerated().map { offset, sourceItem in
            var item = sourceItem
            item.id = Self.preservedID(from: existing?.departmentCalls, at: offset)
            return item
        }
        copy.cameraPlans = source.cameraPlans.enumerated().map { offset, sourceItem in
            var item = sourceItem
            item.id = Self.preservedID(from: existing?.cameraPlans, at: offset)
            return item
        }
        copy.revisions = []
        return copy
    }

    private static func preservedID<Item: Identifiable>(from items: [Item]?, at offset: Int) -> UUID where Item.ID == UUID {
        guard let items, items.indices.contains(offset) else { return UUID() }
        return items[offset].id
    }

    private func nextShotNumber(in scene: ScriptScene) -> String {
        "\(scene.shots.count + 1)"
    }

    private func nextTakeNumber(in shot: Shot) -> Int {
        let maxTake = shot.takes
            .filter { $0.recordType == .take }
            .map(\.takeNumber)
            .max() ?? 0
        return maxTake + 1
    }

    private func freshTake(
        sceneNumber: String,
        shotNumber: String,
        takeNumber: Int,
        cameraSetup: String,
        templateRecords: [CameraRecord]
    ) -> Take {
        let cleanRecords = templateRecords.map { r in
            var copy = r
            copy.status = .hold
            copy.rollState = .recorded
            copy.notes = ""
            return copy
        }

        return Take(
            sceneNumber: sceneNumber,
            shotNumber: shotNumber,
            takeNumber: takeNumber,
            cameraLabel: cameraSetup.isEmpty ? "A" : cameraSetup,
            status: .hold,
            isCircleTake: false,
            pictureUsable: true,
            soundUsable: true,
            performanceRating: 3,
            technicalRating: 3,
            performanceNote: "",
            technicalNote: "",
            generalNote: "",
            quickTags: [],
            cameraRecords: cleanRecords.isEmpty ? cameraTemplate(from: nil) : cleanRecords,
            linkedClips: []
        )
    }

    private func cameraTemplate(from take: Take?) -> [CameraRecord] {
        let records = take?.cameraRecords ?? []
        guard !records.isEmpty else {
            return project.cameraRegistry.map { reg in
                CameraRecord(
                    cameraLabel: reg.label,
                    status: .hold,
                    rollState: .recorded,
                    clipName: reg.nextExpectedClipID,
                    cardName: reg.currentCard,
                    tcIn: "",
                    tcOut: "",
                    pictureAvailable: true,
                    audioAvailable: true,
                    notes: ""
                )
            }
        }
        return records.map { record in
            let newClipName = record.rollState == .noRoll ? record.clipName : incrementStringSuffix(record.clipName)
            return CameraRecord(
                cameraLabel: record.cameraLabel,
                status: .hold,
                rollState: .recorded,
                clipName: newClipName,
                cardName: record.cardName,
                tcIn: "",
                tcOut: "",
                pictureAvailable: true,
                audioAvailable: true,
                notes: ""
            )
        }
    }

    private static func syncCameraRegistry(project: inout Project, from record: CameraRecord) {
        let clipName = record.clipName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cardName = record.cardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clipName.isEmpty || !cardName.isEmpty else { return }

        if let index = project.cameraRegistry.firstIndex(where: { $0.label == record.cameraLabel }) {
            if !clipName.isEmpty {
                project.cameraRegistry[index].nextExpectedClipID = clipName
            }
            if !cardName.isEmpty {
                project.cameraRegistry[index].currentCard = cardName
                if !project.cameraRegistry[index].cardNames.contains(cardName) {
                    project.cameraRegistry[index].cardNames.append(cardName)
                }
                project.cameraRegistry[index].normalizeCards()
            }
        } else {
            project.cameraRegistry.append(
                RegisteredCamera(
                    label: record.cameraLabel,
                    currentCard: cardName,
                    cardNames: cardName.isEmpty ? [] : [cardName],
                    nextExpectedClipID: clipName
                )
            )
        }
    }

    /// Increments the trailing number in a string, preserving prefixes and extensions.
    /// e.g. "A001C001" -> "A001C002", "C0001.MP4" -> "C0002.MP4", "A001_C001" -> "A001_C002"
    private func incrementStringSuffix(_ str: String) -> String {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let nsString = trimmed as NSString
        // Match the last sequence of digits, followed by any non-digit suffix (like an extension)
        guard let regex = try? NSRegularExpression(pattern: "(\\d+)([^\\d]*)$"),
              let match = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsString.length)).last else {
            return trimmed
        }

        let numberRange = match.range(at: 1)
        let numberString = nsString.substring(with: numberRange)

        if let number = Int(numberString) {
            let nextNumber = number + 1
            let paddedNumber = String(format: "%0\(numberString.count)d", nextNumber)
            return nsString.replacingCharacters(in: numberRange, with: paddedNumber)
        }

        return trimmed
    }

    // MARK: - Language migration

    private static let knownTimelineZH = ["全组通告", "预计开机", "午饭", "预计收工"]
    private static let knownTimelineEN = ["Crew Call", "Start Shooting", "Meal Break", "Wrap"]
    private static let knownDeptZH = ["导演组", "摄影组", "灯光组", "录音组", "美术组", "服化组", "道具组", "制片组", "演员组", "场务组", "车辆组", "后期组"]
    private static let knownDeptEN = ["Director", "Camera", "Lighting", "Sound", "Art", "Wardrobe/MUA", "Props", "Production", "Cast", "Grip", "Transport", "Post"]
    private static let knownCamZH = ["A机", "B机", "C机", "D机", "E机", "F机", "G机", "H机"]
    private static let knownCamEN = ["Cam A", "Cam B", "Cam C", "Cam D", "Cam E", "Cam F", "Cam G", "Cam H"]

    private func migrateDefaultsToLanguage() {
        let isEnglish = language.resolved == .en
        let fromTimeline = isEnglish ? Self.knownTimelineZH : Self.knownTimelineEN
        let toTimeline   = isEnglish ? Self.knownTimelineEN : Self.knownTimelineZH
        let fromDept     = isEnglish ? Self.knownDeptZH : Self.knownDeptEN
        let toDept       = isEnglish ? Self.knownDeptEN : Self.knownDeptZH
        let fromCam      = isEnglish ? Self.knownCamZH : Self.knownCamEN
        let toCam        = isEnglish ? Self.knownCamEN : Self.knownCamZH

        var changed = false

        for i in project.cameraRegistry.indices {
            if let idx = fromCam.firstIndex(of: project.cameraRegistry[i].label) {
                project.cameraRegistry[i].label = toCam[idx]
                changed = true
            }
        }

        for di in project.shootingDays.indices {
            for ti in project.shootingDays[di].callSheet.timeline.indices {
                if let idx = fromTimeline.firstIndex(of: project.shootingDays[di].callSheet.timeline[ti].title) {
                    project.shootingDays[di].callSheet.timeline[ti].title = toTimeline[idx]
                    changed = true
                }
            }
            for ci in project.shootingDays[di].callSheet.departmentCalls.indices {
                if let idx = fromDept.firstIndex(of: project.shootingDays[di].callSheet.departmentCalls[ci].departmentName) {
                    project.shootingDays[di].callSheet.departmentCalls[ci].departmentName = toDept[idx]
                    changed = true
                }
            }
            for pi in project.shootingDays[di].callSheet.cameraPlans.indices {
                if let idx = fromCam.firstIndex(of: project.shootingDays[di].callSheet.cameraPlans[pi].unitName) {
                    project.shootingDays[di].callSheet.cameraPlans[pi].unitName = toCam[idx]
                    changed = true
                }
            }
        }

        for di in project.departmentContacts.indices {
            if let idx = fromDept.firstIndex(of: project.departmentContacts[di].departmentName) {
                project.departmentContacts[di].departmentName = toDept[idx]
                changed = true
            }
        }

        if changed { save() }
    }

    private static func makeDefaultProject(language: AppLanguage = .system) -> Project {
        let t: (String, String) -> String = { zh, en in L10n.t(zh, en, language: language) }
        return Project(
            name: "Untitled",
            shootingDays: [makeDefaultShootingDay(language: language)],
            cameraRegistry: Project.defaultCameraRegistry(language: language),
            principalCast: [PrincipalCastMember()],
            departmentContacts: [DepartmentContact(departmentName: t("导演组", "Director"))]
        )
    }

    private static func makeBlankProject(language: AppLanguage = .system) -> Project {
        Project(
            name: "Untitled",
            shootingDays: [],
            cameraRegistry: [],
            principalCast: [],
            departmentContacts: []
        )
    }

    private static func makeDefaultShootingDay(language: AppLanguage = .system) -> ShootingDay {
        let label = L10n.t("第 1 天", "Day 1", language: language)
        return ShootingDay(date: Date(), label: label, scenes: [makeDefaultScene(sceneNumber: "")])
    }

    private static func makeDefaultScene(sceneNumber: String, language: AppLanguage = .system) -> ScriptScene {
        ScriptScene(
            sceneNumber: sceneNumber,
            shots: [makeDefaultShot(sceneNumber: sceneNumber, shotNumber: "1", language: language)]
        )
    }

    private static func makeDefaultShot(sceneNumber: String, shotNumber: String, language: AppLanguage = .system) -> Shot {
        let records = Project.defaultCameraRegistry(language: language).map { reg in
            CameraRecord(
                cameraLabel: reg.label,
                status: .hold,
                rollState: .recorded,
                clipName: reg.nextExpectedClipID,
                cardName: reg.currentCard
            )
        }
        return Shot(
            shotNumber: shotNumber,
            cameraSetup: "A",
            takes: [
                Take(
                    sceneNumber: sceneNumber,
                    shotNumber: shotNumber,
                    takeNumber: 1,
                    cameraLabel: "A",
                    status: .hold,
                    cameraRecords: records
                )
            ]
        )
    }

    private static func defaultProjectFolderURL() -> URL {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("321Doit", isDirectory: true)
            .appendingPathComponent("CurrentProject", isDirectory: true)
    }

    private static func projectDirectoryName(for projectName: String) -> String {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let parts = trimmed.components(separatedBy: illegal)
        let name = parts.joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return name.isEmpty ? "Untitled" : name
    }

    nonisolated static func isProjectFolder(_ url: URL) -> Bool {
        ProjectRepository.isProjectFolder(url)
    }
}

private extension String {
    var trimmedForCheck: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
