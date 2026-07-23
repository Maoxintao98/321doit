import Foundation
import SwiftUI

/// On-set script-log store for the iPad app.
///
/// Owns the working set of shooting days and the current selection, autosaves to
/// the app's Documents directory, and produces a `.321log` export that the macOS
/// 321Doit app can import.
@MainActor
final class ScripterStore: ObservableObject {
    @Published var projectName: String
    @Published private(set) var projectID: UUID
    @Published var days: [ShootingDay]
    @Published var cameras: [ScripterCamera]

    @Published var selectedDayID: UUID?
    @Published var selectedSceneID: UUID?
    @Published var selectedShotID: UUID?
    @Published var selectedTakeID: UUID?

    @Published var language: AppLanguage
    /// When true, deleting a take skips the confirmation dialog ("don't ask again").
    @Published var skipDeleteTakeConfirm: Bool {
        didSet { UserDefaults.standard.set(skipDeleteTakeConfirm, forKey: "scripter.skipDeleteTakeConfirm") }
    }
    @Published var lastSavedAt: Date?
    @Published var alertMessage: String?

    private let fm = FileManager.default
    private var saveWork: DispatchWorkItem?
    private var undoStack: [Snapshot] = []
    private let maxUndo = 50

    private struct Snapshot {
        var projectName: String
        var days: [ShootingDay]
        var cameras: [ScripterCamera]
        var selectedDayID: UUID?
        var selectedSceneID: UUID?
        var selectedShotID: UUID?
        var selectedTakeID: UUID?
    }

    private struct PersistedState: Codable {
        var projectID: UUID
        var projectName: String
        var language: AppLanguage
        var days: [ShootingDay]
        var cameras: [ScripterCamera]?
        var updatedAt: Date
    }

    // MARK: - Init / persistence location

    init() {
        projectID = UUID()
        projectName = ""
        days = []
        cameras = []
        skipDeleteTakeConfirm = UserDefaults.standard.bool(forKey: "scripter.skipDeleteTakeConfirm")
        // Default to Simplified Chinese on first launch; user can switch in
        // Project Settings. A saved state below overrides this.
        language = .zh
        load()
        if cameras.isEmpty {
            cameras = ScripterCamera.defaults(language: language)
        }
        if days.isEmpty {
            let day = Self.makeDefaultDay(language: language)
            days = [day]
            selectedDayID = day.id
            selectedSceneID = day.scenes.first?.id
            selectedShotID = day.scenes.first?.shots.first?.id
        }
        if projectName.isEmpty {
            projectName = L10n.t("未命名项目", "Untitled Project", language: language)
        }
        // Restore a sensible selection so the detail pane isn't empty on launch.
        if selectedTakeID == nil {
            selectedTakeID = currentShot?.takes.first?.id
        }
        // Snap any pre-existing takes (e.g. old Cam A/B/C defaults) onto the
        // current project camera list so the two panels always agree.
        reconcileAllTakesToCameras()
    }

    private var stateURL: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("scripter_state.json")
    }

    var exportsDirectory: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Exports", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Selection helpers

    var currentDay: ShootingDay? {
        days.first { $0.id == selectedDayID }
    }

    var currentScene: ScriptScene? {
        currentDay?.scenes.first { $0.id == selectedSceneID }
    }

    var currentShot: Shot? {
        currentScene?.shots.first { $0.id == selectedShotID }
    }

    var currentTake: Take? {
        currentShot?.takes.first { $0.id == selectedTakeID }
    }

    var totalTakeCount: Int {
        days.reduce(0) { d, day in
            d + day.scenes.reduce(0) { s, scene in
                s + scene.shots.reduce(0) { $0 + $1.takes.count }
            }
        }
    }

    // MARK: - Index lookup

    private func dayIndex(_ id: UUID?) -> Int? {
        guard let id else { return nil }
        return days.firstIndex { $0.id == id }
    }

    // MARK: - Mutations: days

    func addDay() {
        pushUndo()
        let day = Self.makeDefaultDay(language: language, index: days.count + 1)
        days.append(day)
        selectedDayID = day.id
        selectedSceneID = day.scenes.first?.id
        selectedShotID = day.scenes.first?.shots.first?.id
        selectedTakeID = nil
        scheduleSave()
    }

    func renameDay(_ id: UUID, label: String) {
        guard let i = dayIndex(id) else { return }
        days[i].label = label
        scheduleSave()
    }

    func setDayDate(_ id: UUID, date: Date) {
        guard let i = dayIndex(id) else { return }
        days[i].date = date
        scheduleSave()
    }

    func deleteDay(_ id: UUID) {
        pushUndo()
        days.removeAll { $0.id == id }
        if days.isEmpty {
            // Never leave the project with zero days (matches the macOS app,
            // which always keeps at least one shooting day).
            let day = Self.makeDefaultDay(language: language)
            days = [day]
            selectedDayID = day.id
            selectedSceneID = day.scenes.first?.id
            selectedShotID = day.scenes.first?.shots.first?.id
            selectedTakeID = nil
        } else if selectedDayID == id {
            selectedDayID = days.first?.id
            selectedSceneID = currentDay?.scenes.first?.id
            selectedShotID = currentScene?.shots.first?.id
            selectedTakeID = nil
        }
        scheduleSave()
    }

    // MARK: - Mutations: scenes

    func addScene() {
        guard let di = dayIndex(selectedDayID) else { return }
        pushUndo()
        let nextNumber = "\(days[di].scenes.count + 1)"
        var scene = ScriptScene(sceneNumber: nextNumber)
        let shot = Shot(shotNumber: "1", cameraSetup: "")
        scene.shots = [shot]
        days[di].scenes.append(scene)
        selectedSceneID = scene.id
        selectedShotID = shot.id
        selectedTakeID = nil
        scheduleSave()
    }

    func updateScene(_ id: UUID, _ mutate: (inout ScriptScene) -> Void) {
        guard let di = dayIndex(selectedDayID),
              let si = days[di].scenes.firstIndex(where: { $0.id == id }) else { return }
        mutate(&days[di].scenes[si])
        scheduleSave()
    }

    func deleteScene(_ id: UUID) {
        guard let di = dayIndex(selectedDayID) else { return }
        pushUndo()
        days[di].scenes.removeAll { $0.id == id }
        if selectedSceneID == id {
            selectedSceneID = days[di].scenes.first?.id
            selectedShotID = currentScene?.shots.first?.id
            selectedTakeID = nil
        }
        scheduleSave()
    }

    // MARK: - Mutations: shots

    func addShot(toScene sceneID: UUID) {
        guard let di = dayIndex(selectedDayID),
              let si = days[di].scenes.firstIndex(where: { $0.id == sceneID }) else { return }
        pushUndo()
        let count = days[di].scenes[si].shots.count
        let shot = Shot(shotNumber: "\(count + 1)", cameraSetup: "")
        days[di].scenes[si].shots.append(shot)
        selectedSceneID = sceneID
        selectedShotID = shot.id
        selectedTakeID = nil
        scheduleSave()
    }

    func updateShot(scene sceneID: UUID, shot shotID: UUID, _ mutate: (inout Shot) -> Void) {
        guard let di = dayIndex(selectedDayID),
              let si = days[di].scenes.firstIndex(where: { $0.id == sceneID }),
              let shi = days[di].scenes[si].shots.firstIndex(where: { $0.id == shotID }) else { return }
        mutate(&days[di].scenes[si].shots[shi])
        scheduleSave()
    }

    func deleteShot(scene sceneID: UUID, shot shotID: UUID) {
        guard let di = dayIndex(selectedDayID),
              let si = days[di].scenes.firstIndex(where: { $0.id == sceneID }) else { return }
        pushUndo()
        days[di].scenes[si].shots.removeAll { $0.id == shotID }
        if selectedShotID == shotID {
            selectedShotID = days[di].scenes[si].shots.first?.id
            selectedTakeID = nil
        }
        scheduleSave()
    }

    // MARK: - Mutations: takes

    @discardableResult
    func addTake(scene sceneID: UUID, shot shotID: UUID) -> Take? {
        guard let di = dayIndex(selectedDayID),
              let si = days[di].scenes.firstIndex(where: { $0.id == sceneID }),
              let shi = days[di].scenes[si].shots.firstIndex(where: { $0.id == shotID }) else { return nil }
        pushUndo()
        let scene = days[di].scenes[si]
        let shot = scene.shots[shi]
        let next = (shot.takes.map(\.takeNumber).max() ?? 0) + 1

        // Build a camera record per project camera. Each camera's clip number is
        // the *project-wide* last clip for that camera + 1 (continuous numbering
        // across scenes/shots/days), falling back to the camera's start clip.
        let records: [CameraRecord] = cameras.map { cam in
            let clip = lastClip(forCamera: cam.label).map(ClipNumber.next(after:)) ?? cam.startClip
            return CameraRecord(
                cameraLabel: cam.label,
                status: .hold,
                rollState: .recorded,
                clipName: clip,
                cardName: cam.cardName)
        }

        let take = Take(
            sceneNumber: scene.sceneNumber,
            shotNumber: shot.shotNumber,
            takeNumber: next,
            cameraLabel: cameras.first?.label ?? "A",
            status: .unset,
            cameraRecords: records.isEmpty ? CameraRecord.defaultRecords() : records
        )
        days[di].scenes[si].shots[shi].takes.append(take)
        selectedSceneID = sceneID
        selectedShotID = shotID
        selectedTakeID = take.id
        scheduleSave()
        return take
    }

    func duplicateTake(scene sceneID: UUID, shot shotID: UUID, take takeID: UUID) {
        guard let di = dayIndex(selectedDayID),
              let si = days[di].scenes.firstIndex(where: { $0.id == sceneID }),
              let shi = days[di].scenes[si].shots.firstIndex(where: { $0.id == shotID }),
              let ti = days[di].scenes[si].shots[shi].takes.firstIndex(where: { $0.id == takeID }) else { return }
        pushUndo()
        let takes = days[di].scenes[si].shots[shi].takes
        let next = (takes.map(\.takeNumber).max() ?? 0) + 1
        let copy = takes[ti].duplicated(nextTakeNumber: next)
        days[di].scenes[si].shots[shi].takes.insert(copy, at: ti + 1)
        selectedTakeID = copy.id
        scheduleSave()
    }

    func updateTake(scene sceneID: UUID, shot shotID: UUID, take takeID: UUID, _ mutate: (inout Take) -> Void) {
        guard let di = dayIndex(selectedDayID),
              let si = days[di].scenes.firstIndex(where: { $0.id == sceneID }),
              let shi = days[di].scenes[si].shots.firstIndex(where: { $0.id == shotID }),
              let ti = days[di].scenes[si].shots[shi].takes.firstIndex(where: { $0.id == takeID }) else { return }
        mutate(&days[di].scenes[si].shots[shi].takes[ti])
        days[di].scenes[si].shots[shi].takes[ti].updatedAt = Date()
        scheduleSave()
    }

    /// Convenience for the currently selected take.
    func updateCurrentTake(_ mutate: (inout Take) -> Void) {
        guard let s = selectedSceneID, let sh = selectedShotID, let t = selectedTakeID else { return }
        updateTake(scene: s, shot: sh, take: t, mutate)
    }

    func deleteTake(scene sceneID: UUID, shot shotID: UUID, take takeID: UUID) {
        guard let di = dayIndex(selectedDayID),
              let si = days[di].scenes.firstIndex(where: { $0.id == sceneID }),
              let shi = days[di].scenes[si].shots.firstIndex(where: { $0.id == shotID }) else { return }
        pushUndo()
        days[di].scenes[si].shots[shi].takes.removeAll { $0.id == takeID }
        if selectedTakeID == takeID { selectedTakeID = nil }
        scheduleSave()
    }

    // MARK: - Undo

    var canUndo: Bool { !undoStack.isEmpty }

    private func pushUndo() {
        undoStack.append(Snapshot(
            projectName: projectName, days: days, cameras: cameras,
            selectedDayID: selectedDayID, selectedSceneID: selectedSceneID,
            selectedShotID: selectedShotID, selectedTakeID: selectedTakeID))
        if undoStack.count > maxUndo { undoStack.removeFirst(undoStack.count - maxUndo) }
    }

    func undo() {
        guard let s = undoStack.popLast() else { return }
        projectName = s.projectName
        days = s.days
        cameras = s.cameras
        selectedDayID = s.selectedDayID
        selectedSceneID = s.selectedSceneID
        selectedShotID = s.selectedShotID
        selectedTakeID = s.selectedTakeID
        scheduleSave()
    }

    // MARK: - Persistence

    /// Serial queue so background saves never overlap or block the main thread.
    private let saveQueue = DispatchQueue(label: "scripter.save", qos: .utility)

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        // 1.2s debounce: typing bursts coalesce into a single write.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    /// Encodes a snapshot on the main actor (cheap value-type copy) then hands
    /// the heavy JSON encode + disk write to a background queue, so editing never
    /// stutters waiting on I/O.
    func save() {
        saveWork?.cancel()
        let state = PersistedState(
            projectID: projectID, projectName: projectName,
            language: language, days: days, cameras: cameras, updatedAt: Date())
        let url = stateURL
        saveQueue.async { [weak self] in
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601   // compact (no pretty/sorted)
                let data = try encoder.encode(state)
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async { self?.lastSavedAt = Date() }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.alertMessage = L10n.t("保存失败：\(error.localizedDescription)",
                                               "Save failed: \(error.localizedDescription)", language: self.language)
                }
            }
        }
    }

    /// Immediate, synchronous save for when the app is about to be backgrounded.
    /// The debounced/async path may not run before iOS suspends the process, so
    /// here we encode and write inline on the main thread (cheap for text data)
    /// to guarantee the latest edits are on disk before suspension.
    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        let state = PersistedState(
            projectID: projectID, projectName: projectName,
            language: language, days: days, cameras: cameras, updatedAt: Date())
        let url = stateURL
        // Drain every older queued snapshot first, then write the newest state
        // on that same serial queue. This prevents a stale async save from
        // landing after the backgrounding save and rolling the project back.
        let result: Result<Date, Error> = saveQueue.sync {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(state)
                try data.write(to: url, options: .atomic)
                return .success(Date())
            } catch {
                return .failure(error)
            }
        }
        switch result {
        case .success(let date):
            lastSavedAt = date
        case .failure(let error):
            alertMessage = L10n.t("保存失败：\(error.localizedDescription)",
                                  "Save failed: \(error.localizedDescription)", language: language)
        }
    }

    private func load() {
        guard fm.fileExists(atPath: stateURL.path) else { return }
        do {
            let data = try Data(contentsOf: stateURL)
            let state = try JSONDecoder.iso.decode(PersistedState.self, from: data)
            projectID = state.projectID
            projectName = state.projectName
            language = state.language
            days = state.days
            cameras = state.cameras ?? []
            selectedDayID = days.first?.id
            selectedSceneID = currentDay?.scenes.first?.id
            selectedShotID = currentScene?.shots.first?.id
        } catch {
            alertMessage = L10n.t("读取本地数据失败：\(error.localizedDescription)",
                                  "Failed to load saved data: \(error.localizedDescription)", language: language)
        }
    }

    // MARK: - Export

    func makeExportDocument() -> ScripterExportDocument {
        ScripterExportDocument(
            projectID: projectID,
            projectName: projectName.isEmpty ? "Untitled" : projectName,
            shootingDays: days,
            updatedAt: Date())
    }

    /// Writes a `.321log` file into the Exports directory and returns its URL.
    func writeExportFile() throws -> URL {
        save()
        let doc = makeExportDocument()
        let data = try JSONEncoder.prettyISO.encode(doc)
        let stamp = Self.fileStampFormatter.string(from: Date())
        let safeName = sanitize(projectName.isEmpty ? "Scriptlog" : projectName)
        let url = exportsDirectory.appendingPathComponent("\(safeName)_\(stamp).321log")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func sanitize(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return s.components(separatedBy: bad).joined(separator: "-")
    }

    /// Writes a CSV table of every take and returns its URL. Columns mirror the
    /// macOS script log so it opens cleanly in Excel / Numbers.
    func writeCSVFile() throws -> URL {
        save()
        let stamp = Self.fileStampFormatter.string(from: Date())
        let safeName = sanitize(projectName.isEmpty ? "Scriptlog" : projectName)
        let url = exportsDirectory.appendingPathComponent("\(safeName)_\(stamp).csv")
        let csv = makeCSV()
        try Data(csv.utf8).write(to: url, options: .atomic)
        return url
    }

    private func makeCSV() -> String {
        func esc(_ s: String) -> String {
            var s = s
            // Neutralize spreadsheet formula injection: a leading = + - @ makes
            // Excel/Numbers evaluate the cell. Prefix with an apostrophe so the
            // value is treated as plain text.
            if let first = s.first, "=+-@\t\r".contains(first) {
                s = "'" + s
            }
            if s.contains(",") || s.contains("\"") || s.contains("\n") {
                return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return s
        }
        let t: (String, String) -> String = { zh, en in L10n.t(zh, en, language: self.language) }
        var headers = [t("拍摄日", "Day"), t("场", "Scene"), t("镜", "Shot"),
                       t("条", "Take"), t("状态", "Status"), t("圈选", "Circle"),
                       t("表演", "Perf"), t("技术", "Tech")]
        for cam in cameras {
            headers.append("\(cam.label) " + t("素材号", "Clip"))
            headers.append("\(cam.label) " + t("卡号", "Card"))
        }
        headers.append(t("备注", "Note"))

        var lines = [headers.map(esc).joined(separator: ",")]
        for day in days {
            for scene in day.scenes {
                for shot in scene.shots {
                    for take in shot.takes {
                        var row = [
                            day.label, scene.sceneNumber, shot.shotNumber,
                            "T\(take.takeNumber)",
                            take.status.hasStatus ? take.status.label(language: language) : "",
                            take.isCircleTake ? "●" : "",
                            String(take.performanceRating),
                            String(take.technicalRating)
                        ]
                        for cam in cameras {
                            let rec = take.cameraRecords.first { $0.cameraLabel == cam.label }
                            row.append(rec?.clipName ?? "")
                            row.append(rec?.cardName ?? "")
                        }
                        row.append(take.generalNote)
                        lines.append(row.map(esc).joined(separator: ","))
                    }
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static let fileStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Cameras (project panel)

    /// Re-translates camera labels that still use a default name
    /// ("A机"/"Cam A" …) to the current language. User-customized names that
    /// don't match the default pattern are left untouched. Call after the
    /// language changes so an English UI never shows "A机".
    func relocalizeDefaultCameraNames() {
        for i in cameras.indices {
            let label = cameras[i].label
            // Match "<Letter>机" or "Cam <Letter>".
            var letter: String?
            if label.count == 2, label.hasSuffix("机"), let first = label.first, first.isLetter {
                letter = String(first)
            } else if label.hasPrefix("Cam "), label.count == 5 {
                letter = String(label.suffix(1))
            }
            if let letter, letter.range(of: "^[A-Z]$", options: .regularExpression) != nil {
                let newLabel = L10n.t("\(letter)机", "Cam \(letter)", language: language)
                if newLabel != label {
                    renameCameraRecords(from: label, to: newLabel)
                    cameras[i].label = newLabel
                }
            }
        }
        scheduleSave()
    }

    func addCamera() {
        pushUndo()
        let letter = Self.cameraLetter(for: cameras.count)
        let label = L10n.t("\(letter)机", "Cam \(letter)", language: language)
        cameras.append(ScripterCamera(label: label,
                                      cardName: "\(letter)001",
                                      startClip: "\(letter)0001"))
        reconcileAllTakesToCameras()
        scheduleSave()
    }

    func updateCamera(_ id: UUID, _ mutate: (inout ScripterCamera) -> Void) {
        guard let i = cameras.firstIndex(where: { $0.id == id }) else { return }
        let oldLabel = cameras[i].label
        mutate(&cameras[i])
        let newLabel = cameras[i].label
        // Renaming a camera propagates to every take's matching records so the
        // script log stays in sync with the project panel.
        if oldLabel != newLabel {
            renameCameraRecords(from: oldLabel, to: newLabel)
        }
        scheduleSave()
    }

    func deleteCamera(_ id: UUID) {
        guard cameras.count > 1 else { return }   // keep at least one camera
        pushUndo()
        cameras.removeAll { $0.id == id }
        reconcileAllTakesToCameras()
        scheduleSave()
    }

    private func renameCameraRecords(from old: String, to new: String) {
        for di in days.indices {
            for si in days[di].scenes.indices {
                for shi in days[di].scenes[si].shots.indices {
                    for ti in days[di].scenes[si].shots[shi].takes.indices {
                        for ri in days[di].scenes[si].shots[shi].takes[ti].cameraRecords.indices
                        where days[di].scenes[si].shots[shi].takes[ti].cameraRecords[ri].cameraLabel == old {
                            days[di].scenes[si].shots[shi].takes[ti].cameraRecords[ri].cameraLabel = new
                        }
                    }
                }
            }
        }
    }

    /// The last non-empty clip number recorded for a camera anywhere in the
    /// project, scanning in shooting order (day → scene → shot → take). Used to
    /// continue clip numbering across scenes/shots/days.
    private func lastClip(forCamera label: String) -> String? {
        var result: String?
        for day in days {
            for scene in day.scenes {
                for shot in scene.shots {
                    for take in shot.takes {
                        if let clip = take.cameraRecords.first(where: { $0.cameraLabel == label })?.clipName,
                           !clip.isEmpty {
                            result = clip
                        }
                    }
                }
            }
        }
        return result
    }

    /// Makes every take's camera records match the project's camera list:
    /// keeps matching records *untouched*, drops removed cameras, and adds newly
    /// added cameras with an auto-filled clip (project-wide last clip + 1, else
    /// the camera start). Existing clip numbers are never modified.
    func reconcileAllTakesToCameras() {
        guard !cameras.isEmpty else { return }
        // Running last-clip per camera as we walk in shooting order, so freshly
        // added camera columns get continuous numbering too.
        var running: [String: String] = [:]
        for di in days.indices {
            for si in days[di].scenes.indices {
                for shi in days[di].scenes[si].shots.indices {
                    for ti in days[di].scenes[si].shots[shi].takes.indices {
                        let existingRecords = days[di].scenes[si].shots[shi].takes[ti].cameraRecords
                        var rebuilt: [CameraRecord] = []
                        for cam in cameras {
                            if let existing = existingRecords.first(where: { $0.cameraLabel == cam.label }) {
                                rebuilt.append(existing)                 // keep as-is
                                if !existing.clipName.isEmpty { running[cam.label] = existing.clipName }
                            } else {
                                let clip = running[cam.label].map(ClipNumber.next(after:)) ?? cam.startClip
                                rebuilt.append(CameraRecord(
                                    cameraLabel: cam.label, status: .hold, rollState: .recorded,
                                    clipName: clip, cardName: cam.cardName))
                                running[cam.label] = clip
                            }
                        }
                        days[di].scenes[si].shots[shi].takes[ti].cameraRecords = rebuilt
                    }
                }
            }
        }
    }

    private static func cameraLetter(for index: Int) -> String {
        let scalar = UnicodeScalar(UInt8(65 + min(index, 25)))
        return String(Character(scalar))
    }

    // MARK: - Defaults

    static func makeDefaultDay(language: AppLanguage, index: Int = 1) -> ShootingDay {
        var scene = ScriptScene(sceneNumber: "1")
        scene.shots = [Shot(shotNumber: "1", cameraSetup: "")]
        let label = L10n.t("第 \(index) 天", "Day \(index)", language: language)
        return ShootingDay(date: Date(), label: label, scenes: [scene])
    }
}
