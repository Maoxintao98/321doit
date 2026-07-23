import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class OffloadViewModel: ObservableObject {
    @Published var taskID = UUID()
    @Published var projectName = ""
    @Published var cardNumber = ""
    @Published var operatorName = ""
    @Published var camera = ""
    @Published var location = ""
    @Published var notes = ""
    @Published var generateProxies = false
    @Published var safeCopyPackage = true
    @Published var editorialDeliveryPackage = false
    @Published var transcodeProfile: TranscodeProfile = .default
    @Published var sourceURL: URL?
    @Published var targetRoots: [URL] = []
    @Published var snapshot = OffloadSnapshot(
        message: L10n.t("请填写项目信息，选择来源和目标盘后即可开始。",
                        "Fill in the project info and pick a source and destination to begin.",
                        language: .system),
        totalFiles: 0,
        completedFiles: 0,
        totalBytes: 0,
        copiedBytes: 0,
        startedAt: nil,
        targets: [],
        recentLog: nil
    )
    @Published var logs: [String] = []
    @Published var isRunning = false
    @Published var alertMessage: String?
    @Published var lastReport: OffloadReport?
    @Published var mountedSourceCandidate: MountedSourceCandidate?
    @Published var cameraRegistry: [RegisteredCamera] = []
    private var ignoredVolumes: Set<URL> = []
    @Published var preflightResults: [PreflightCheckResult] = []
    @Published var verifyOnly = false
    @Published var hasRestoredPendingTask = false
    /// Prevents view re-entry from reapplying defaults over an in-progress task draft.
    var hasAppliedTaskDefaults = false
    @Published var language: AppLanguage = .system
    @Published var projectAssociationMode: ProjectAssociationMode = .independent
    @Published var linkedProjectID: UUID?

    /// Called after a successful offload with the root URLs of every destination
    /// that completed. Wired at the workspace root to copy the current script log
    /// into each destination's `_ScriptLog` folder during 拷盘.
    var onOffloadSucceeded: (([URL]) -> Void)?

    private func tr(_ zh: String, _ en: String) -> String {
        L10n.t(zh, en, language: language)
    }

    private var currentTask: Task<Void, Never>?
    private var mountObserver: NSObjectProtocol?
    private var mountDetectionTask: Task<Void, Never>?
    private var lastSpeedSample: (date: Date, copiedBytes: UInt64, targetBytes: [UUID: UInt64])?
    private var dockProgressEnabled = false
    private var isCancelling = false
    private let pendingTaskKey: String

    init(persistenceID: String = "default", migrateLegacyPendingTask: Bool = false) {
        self.pendingTaskKey = "pendingOffloadTask.\(persistenceID)"
        if migrateLegacyPendingTask,
           UserDefaults.standard.data(forKey: pendingTaskKey) == nil,
           let legacy = UserDefaults.standard.data(forKey: "pendingOffloadTask") {
            UserDefaults.standard.set(legacy, forKey: pendingTaskKey)
            UserDefaults.standard.removeObject(forKey: "pendingOffloadTask")
        }
        restorePendingTask()
        startVolumeMonitoring()
    }

    private func restorePendingTask() {
        if let data = UserDefaults.standard.data(forKey: pendingTaskKey),
           let pending = try? JSONDecoder().decode(OffloadSettings.self, from: data) {
            self.taskID = pending.taskID
            self.projectName = pending.projectName
            self.cardNumber = pending.cardNumber
            self.operatorName = pending.operatorName
            self.camera = pending.camera
            self.location = pending.location
            self.notes = pending.notes
            self.sourceURL = SecurityScopedBookmarks.resolvedURL(for: pending.sourceURL, role: "source")
            self.targetRoots = pending.targetRoots.map { SecurityScopedBookmarks.resolvedURL(for: $0, role: "target") }
            self.generateProxies = pending.generateProxies
            self.safeCopyPackage = true
            self.editorialDeliveryPackage = false
            self.transcodeProfile = pending.transcodeProfile
            self.verifyOnly = pending.verifyOnly
            self.projectAssociationMode = pending.projectAssociationMode
            self.linkedProjectID = pending.linkedProjectID
            self.hasRestoredPendingTask = true
            self.hasAppliedTaskDefaults = true
        }
    }

    deinit {
        mountDetectionTask?.cancel()
        if let mountObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(mountObserver)
        }
    }

    func resetTask() {
        taskID = UUID()
        projectName = ""
        cardNumber = ""
        operatorName = ""
        camera = ""
        location = ""
        notes = ""
        sourceURL = nil
        targetRoots = []
        generateProxies = false
        safeCopyPackage = true
        editorialDeliveryPackage = false
        transcodeProfile = .default
        verifyOnly = false
        hasRestoredPendingTask = false
        hasAppliedTaskDefaults = false
        projectAssociationMode = .independent
        linkedProjectID = nil
        UserDefaults.standard.removeObject(forKey: pendingTaskKey)
    }

    var canStart: Bool {
        !isRunning
        && !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !operatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && sourceURL != nil
        && !targetRoots.isEmpty
        && targetRoots.count <= 3
        && !selectedOutputPackageModes.isEmpty
    }

    var outputPreview: String {
        outputFolderNames.joined(separator: "  +  ")
    }

    var outputFolderNames: [String] {
        let base = makeOutputFolderName(project: projectName, date: Date(), card: cardNumber)
        let modes = selectedOutputPackageModes
        if modes.count <= 1 {
            return [base]
        }
        return modes.map { "\(base)_\($0.folderSuffix)" }
    }

    var selectedOutputPackageModes: [OffloadPackageMode] {
        [.safeCopy]
    }

    var failedFileEntries: [String] {
        guard let report = lastReport else { return [] }
        return report.files.flatMap { file in
            file.targetResults.compactMap { result in
                result.verified ? nil : "\(file.relativePath) | \(result.rootPath) | \(result.error ?? "Unknown failure")"
            }
        } + report.targets.flatMap { target in
            target.proxyErrors.map { "Proxy/LUT | \(target.outputURL.path) | \($0)" }
        }
    }

    var nextReelSuggestion: String {
        nextReel(after: cardNumber)
    }

    func pickSource() {
        let panel = NSOpenPanel()
        panel.title = tr("选择来源卡或文件夹", "Select Source Card or Folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = tr("选择来源", "Choose Source")
        if let sourceURL {
            panel.directoryURL = sourceURL
        } else if let candidate = mountedSourceCandidate {
            panel.directoryURL = candidate.url
        }
        if panel.runModal() == .OK {
            if let url = panel.url {
                SecurityScopedBookmarks.save(url: url, role: "source")
                sourceURL = SecurityScopedBookmarks.resolvedURL(for: url, role: "source")
            }
            mountedSourceCandidate = nil
            lastReport = nil
            updatePreflight(appSettings: nil)
        }
    }

    func addTarget() {
        guard targetRoots.count < 3 else {
            alertMessage = tr("最多只能选择 3 个目标。", "You can select up to 3 destinations.")
            return
        }
        let panel = NSOpenPanel()
        panel.title = tr("选择目标盘或文件夹", "Select Destination")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = tr("选择目标", "Choose")
        if let lastTarget = targetRoots.last {
            panel.directoryURL = lastTarget
        } else if let sourceURL {
            panel.directoryURL = sourceURL.deletingLastPathComponent()
        }
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.standardizedFileURL.path
            if targetRoots.contains(where: { $0.standardizedFileURL.path == path }) {
                alertMessage = tr("这个目标已经添加过。", "This destination is already in the list.")
                return
            }
            SecurityScopedBookmarks.save(url: url, role: "target")
            targetRoots.append(SecurityScopedBookmarks.resolvedURL(for: url, role: "target"))
            lastReport = nil
            updatePreflight(appSettings: nil)
        }
    }

    func removeTarget(_ url: URL) {
        targetRoots.removeAll { $0.standardizedFileURL.path == url.standardizedFileURL.path }
        updatePreflight(appSettings: nil)
    }

    func acceptMountedSourceCandidate() {
        guard let candidate = mountedSourceCandidate else { return }
        SecurityScopedBookmarks.save(url: candidate.url, role: "source")
        sourceURL = SecurityScopedBookmarks.resolvedURL(for: candidate.url, role: "source")
        if cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let suggested = candidate.suggestedCardName {
            cardNumber = suggested
        }
        mountedSourceCandidate = nil
        lastReport = nil
        updatePreflight(appSettings: nil)
    }

    func ignoreMountedSourceCandidate() {
        if let candidate = mountedSourceCandidate {
            ignoredVolumes.insert(candidate.url)
        }
        mountedSourceCandidate = nil
    }

    func incrementReel() {
        cardNumber = nextReelSuggestion
    }

    func updatePreflight(appSettings: AppSettings?) {
        preflightResults = PreflightChecker.run(
            projectName: projectName,
            cardNumber: cardNumber,
            operatorName: operatorName,
            sourceURL: sourceURL,
            targetRoots: targetRoots,
            outputFolderName: outputPreview,
            outputFolderNames: outputFolderNames,
            settings: appSettings,
            generateProxies: generateProxies,
            transcodeProfile: transcodeProfile,
            language: language
        )
    }

    func pickLUT() {
        let panel = NSOpenPanel()
        panel.title = tr("选择 LUT 文件", "Select LUT File")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = tr("选择 LUT", "Choose LUT")
        // Accept .cube / .3dl LUT files. UTType is the modern replacement for allowedFileTypes.
        let cubeType = UTType(filenameExtension: "cube") ?? .data
        let threeDLType = UTType(filenameExtension: "3dl") ?? .data
        panel.allowedContentTypes = [cubeType, threeDLType, .data]
        if panel.runModal() == .OK, let url = panel.url {
            transcodeProfile.lutPath = url.path
            if transcodeProfile.lutMode == .none {
                transcodeProfile.lutMode = .applyLUT
            }
        }
    }

    func start(appSettings: AppSettings) {
        language = appSettings.general.language
        guard currentTask == nil else { return }
        guard canStart, let sourceURL else {
            alertMessage = tr("项目、卡号、操作员、来源和目标都必须填写。",
                              "Project, card, operator, source and destination are all required.")
            return
        }
        let wasRestoredPendingTask = hasRestoredPendingTask
        let resolvedSourceURL = SecurityScopedBookmarks.resolvedURL(for: sourceURL, role: "source")
        let resolvedTargetRoots = targetRoots.map { SecurityScopedBookmarks.resolvedURL(for: $0, role: "target") }
        self.sourceURL = resolvedSourceURL
        self.targetRoots = resolvedTargetRoots
        updatePreflight(appSettings: appSettings)
        if PreflightChecker.hasBlockingErrors(preflightResults) {
            alertMessage = blockingPreflightMessage(preflightResults)
            return
        }

        var effectiveTranscodeProfile = transcodeProfile
        effectiveTranscodeProfile.enableHardwareAcceleration = appSettings.transcode.enableHardwareAcceleration
        effectiveTranscodeProfile.ffmpegPath = appSettings.transcode.ffmpegPath.isEmpty ? nil : appSettings.transcode.ffmpegPath

        let sourceCardProfile = CameraCardDetector.detect(sourceURL: sourceURL)

        let effectiveGenerateProxies = generateProxies || effectiveTranscodeProfile.burnIn.enabled

        let settings = OffloadSettings(
            projectName: projectName,
            cardNumber: cardNumber,
            operatorName: operatorName,
            camera: camera,
            location: location,
            notes: notes,
            sourceURL: resolvedSourceURL,
            targetRoots: resolvedTargetRoots,
            createdAt: Date(),
            generateProxies: effectiveGenerateProxies,
            transcodeProfile: effectiveTranscodeProfile,
            language: appSettings.general.language,
            checksumAlgorithm: appSettings.checksum.algorithm,
            xxHash64Implementation: appSettings.checksum.xxHash64Implementation,
            copyBufferKB: appSettings.performance.copyBufferKB,
            writeSidecarChecksum: appSettings.checksum.writeSidecarChecksum,
            generateAscMHL: appSettings.checksum.generateAscMHL,
            generateCSVLog: appSettings.checksum.generateCSVLog,
            generateJSONLog: appSettings.checksum.generateJSONLog,
            generateTXTBrief: appSettings.report.generateBriefReport,
            recordEnvironmentInReport: appSettings.checksum.recordEnvironmentInReport,
            sourceCardProfile: sourceCardProfile,
            verifyOnly: verifyOnly,
            checksumRetryCount: appSettings.checksum.retryOnFailure,
            enableSpeedLimit: appSettings.performance.enableSpeedLimit,
            speedLimitMBps: appSettings.performance.speedLimitMBps,
            resumedFromJournal: false,
            strictResume: appSettings.copyVerify.strictResume || wasRestoredPendingTask,
            ioRetryCount: appSettings.copyVerify.ioRetryCount,
            handoff: .init(),
            outputPackageModes: selectedOutputPackageModes,
            taskID: taskID,
            projectAssociationMode: projectAssociationMode,
            linkedProjectID: linkedProjectID
        )

        AppLogger.log(
            .info,
            category: "offload",
            "Task \(settings.taskID.uuidString.lowercased()) started; project=\(settings.projectName); card=\(settings.cardNumber); targets=\(settings.targetRoots.count); verifyOnly=\(settings.verifyOnly)"
        )

        hasRestoredPendingTask = false
        if appSettings.logs.keepIncompleteTaskOnCrash {
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: pendingTaskKey)
            }
        }

        isRunning = true
        isCancelling = false
        dockProgressEnabled = appSettings.notification.dockProgress
        lastSpeedSample = nil
        logs.removeAll()
        lastReport = nil
        snapshot = OffloadSnapshot(
            message: tr("正在预检...", "Running preflight..."),
            totalFiles: 0,
            completedFiles: 0,
            totalBytes: 0,
            copiedBytes: 0,
            startedAt: Date(),
            targets: [],
            recentLog: nil
        )

        currentTask = Task {
            let scopedURLs: [(url: URL, role: String)] = [(settings.sourceURL, "source")]
                + settings.targetRoots.map { ($0, "target") }
                + (settings.transcodeProfile.ffmpegPath.map { [(URL(fileURLWithPath: $0), "ffmpeg")] } ?? [])
            let accessTokens = SecurityScopedBookmarks.startAccessing(urls: scopedURLs)
            defer { accessTokens.forEach { $0.stop() } }
            do {
                let report = try await OffloadEngine().run(settings: settings) { [weak self] snapshot in
                    await MainActor.run {
                        self?.apply(snapshot)
                    }
                }
                await MainActor.run {
                    self.lastReport = report
                    self.isRunning = false
                    self.isCancelling = false
                    self.currentTask = nil
                    self.clearDockProgress()
                    self.logs = report.logs
                    self.snapshot.message = self.tr(
                        "完成：\(report.successfulTargets.count) 个目标成功。",
                        "Completed: \(report.successfulTargets.count) destination\(report.successfulTargets.count == 1 ? "" : "s") succeeded."
                    )
                    UserDefaults.standard.removeObject(forKey: self.pendingTaskKey)
                }
                await CompletionActions.handleSuccess(report: report, appSettings: appSettings)
                AppLogger.log(
                    .info,
                    category: "offload",
                    "Task \(report.settings.taskID.uuidString.lowercased()) completed; files=\(report.totalFiles); bytes=\(report.totalBytes); successfulTargets=\(report.successfulTargets.count)"
                )
                for entry in report.logs {
                    AppLogger.log(.detailed, category: "offload.task", entry)
                }
                await MainActor.run {
                    let roots = report.successfulTargets.map(\.rootURL)
                    if !roots.isEmpty { self.onOffloadSucceeded?(roots) }
                }
            } catch is CancellationError {
                AppLogger.log(.warning, category: "offload", "Task \(settings.taskID.uuidString.lowercased()) cancelled")
                await MainActor.run {
                    self.isRunning = false
                    self.isCancelling = false
                    self.currentTask = nil
                    self.clearDockProgress()
                    self.snapshot.message = self.tr("已取消。", "Canceled.")
                }
            } catch {
                AppLogger.log(.error, category: "offload", "Task \(settings.taskID.uuidString.lowercased()) failed: \(error.localizedDescription)")
                await CompletionActions.handleFailure(error: error, appSettings: appSettings)
                await MainActor.run {
                    self.isRunning = false
                    self.isCancelling = false
                    self.currentTask = nil
                    self.clearDockProgress()
                    self.alertMessage = error.localizedDescription
                    self.snapshot.message = self.tr(
                        "失败：\(error.localizedDescription)",
                        "Failed: \(error.localizedDescription)"
                    )
                    self.logs.append(error.localizedDescription)
                }
            }
        }
    }

    func cancel() {
        guard isRunning || currentTask != nil else { return }
        guard !isCancelling else { return }
        isCancelling = true
        currentTask?.cancel()
        snapshot.message = tr("正在取消...", "Canceling...")
    }

    func revealReports() {
        guard let report = lastReport else { return }
        let urls = report.successfulTargets.flatMap {
            [$0.pdfURL, $0.csvURL, $0.jsonURL, $0.txtURL, $0.mhlURL, $0.sidecarURL].compactMap { $0 }
        }
        if !urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    func revealOutputFolder() {
        guard let outputURL = lastReport?.successfulTargets.first?.outputURL else { return }
        NSWorkspace.shared.open(outputURL)
    }

    // MARK: - Post Handoff actions

    /// First successful target's handoff package, used by the completion-page buttons.
    var firstHandoff: HandoffOutput? {
        lastReport?.successfulTargets.compactMap(\.handoff).first
    }

    var hasResolveHandoff: Bool {
        firstHandoff?.resolveScriptURL != nil
    }

    var hasFinalCutHandoff: Bool {
        firstHandoff?.fcpxmldURL != nil
    }

    func revealHandoffPackage() {
        guard let url = firstHandoff?.rootURL else { return }
        NSWorkspace.shared.open(url)
    }

    func sendToResolve() {
        guard let scriptURL = firstHandoff?.resolveScriptURL else {
            alertMessage = tr("未生成 DaVinci Resolve 交接文件。",
                              "DaVinci Resolve handoff file was not generated.")
            return
        }
        if !HandoffAppDetector.isResolveInstalled() {
            alertMessage = tr("未找到 DaVinci Resolve。请先安装 DaVinci Resolve，或只生成交接包。",
                              "DaVinci Resolve not found. Install Resolve first, or build only the handoff package.")
            return
        }
        Task { [weak self] in
            do {
                let result = try await HandoffResolveLauncher.sendToResolve(scriptURL: scriptURL)
                await MainActor.run {
                    self?.presentResolveResult(result)
                }
            } catch {
                await MainActor.run {
                    self?.alertMessage = error.localizedDescription
                }
            }
        }
    }

    private func presentResolveResult(_ result: ResolveLaunchResult) {
        if result.ok {
            var lines: [String] = []
            if let project = result.projectName, !project.isEmpty {
                lines.append(tr("项目：\(project)", "Project: \(project)"))
            }
            lines.append(tr("导入原始素材：\(result.importedOriginals)",
                            "Imported originals: \(result.importedOriginals)"))
            lines.append(tr("链接代理：\(result.linkedProxies)",
                            "Linked proxies: \(result.linkedProxies)"))
            if !result.missingProxies.isEmpty {
                lines.append(tr("代理缺失：\(result.missingProxies.count)",
                                "Missing proxies: \(result.missingProxies.count)"))
            }
            if !result.failedProxyLinks.isEmpty {
                lines.append(tr("代理链接失败：\(result.failedProxyLinks.count)",
                                "Proxy link failures: \(result.failedProxyLinks.count)"))
            }
            if !result.failedMedia.isEmpty {
                lines.append(tr("素材导入失败：\(result.failedMedia.count)",
                                "Media import failures: \(result.failedMedia.count)"))
            }
            alertMessage = tr("已发送到 DaVinci Resolve", "Sent to DaVinci Resolve") + "\n" + lines.joined(separator: "\n")
        } else {
            let detail = result.errorMessage ?? tr("Resolve 脚本未返回成功结果。",
                                                   "Resolve script did not return a success result.")
            alertMessage = tr("DaVinci Resolve 导入失败：\(detail)",
                              "DaVinci Resolve import failed: \(detail)")
        }
    }

    func sendToFinalCut() {
        guard let fcpxmldURL = firstHandoff?.fcpxmldURL else {
            alertMessage = tr("未生成 Final Cut Pro 交接文件。",
                              "Final Cut Pro handoff file was not generated.")
            return
        }
        if !HandoffAppDetector.isFinalCutInstalled() {
            alertMessage = tr("未找到 Final Cut Pro。请先安装 Final Cut Pro，或只生成交接包。",
                              "Final Cut Pro not found. Install FCP first, or build only the handoff package.")
            return
        }
        let compatURL = firstHandoff?.fcpxmlCompatURL
        Task { [weak self] in
            do {
                try await HandoffFinalCutLauncher.sendToFinalCut(
                    fcpxmldURL: fcpxmldURL,
                    compatURL: compatURL
                )
            } catch {
                await MainActor.run {
                    self?.alertMessage = error.localizedDescription
                }
            }
        }
    }

    func showFailedFiles() {
        let entries = failedFileEntries
        guard !entries.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = tr("失败文件列表", "Failed Files")
        alert.informativeText = entries.prefix(40).joined(separator: "\n") + (entries.count > 40 ? "\n..." : "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func exportFailedReport() {
        let entries = failedFileEntries
        guard !entries.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = OutputFileNamer.fileName(
            projectName: lastReport?.settings.projectName ?? projectName,
            date: Date(),
            attribute: tr("失败文件", "Failed Files"),
            extension: "csv"
        )
        if panel.runModal() == .OK, let url = panel.url {
            let header = "relative_path,target,error\n"
            let body = failedFileRows().map { row in
                row.map(csvEscape).joined(separator: ",")
            }.joined(separator: "\n")
            do {
                try (header + body + "\n").write(to: url, atomically: true, encoding: .utf8)
            } catch {
                alertMessage = tr("导出失败报告失败：\(error.localizedDescription)",
                                  "Failed to export failure report: \(error.localizedDescription)")
            }
        }
    }

    private func failedFileRows() -> [[String]] {
        guard let report = lastReport else { return [] }
        let fileRows = report.files.flatMap { file in
            file.targetResults.compactMap { result -> [String]? in
                result.verified ? nil : [file.relativePath, result.rootPath, result.error ?? "Unknown failure"]
            }
        }
        let proxyRows = report.targets.flatMap { target in
            target.proxyErrors.map { ["Proxy/LUT", target.outputURL.path, $0] }
        }
        return fileRows + proxyRows
    }

    private func blockingPreflightMessage(_ results: [PreflightCheckResult]) -> String {
        let errors = results.filter { $0.severity == .error }
        if let ffmpegError = errors.first(where: { $0.message.localizedCaseInsensitiveContains("FFmpeg") }) {
            return [ffmpegError.message, ffmpegError.detail]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
        let separator = language.resolved == .zh ? "：" : ": "
        let details = errors.prefix(3).map { result in
            if let detail = result.detail, !detail.isEmpty {
                return "\(result.message)\(separator)\(detail)"
            }
            return result.message
        }
        if details.isEmpty {
            return tr("预检发现必须处理的问题，请先修正红色项目。",
                      "Preflight found blocking issues. Please fix the items marked in red first.")
        }
        let header = tr("预检发现必须处理的问题：", "Preflight found blocking issues:")
        return header + "\n" + details.joined(separator: "\n")
    }

    private func csvEscape(_ value: String) -> String {
        spreadsheetSafeCSVField(value)
    }

    private func apply(_ newSnapshot: OffloadSnapshot) {
        var enriched = newSnapshot
        let now = Date()
        let previous = lastSpeedSample
        let targetBytes = Dictionary(uniqueKeysWithValues: newSnapshot.targets.map { ($0.id, $0.copiedBytes) })

        if let startedAt = newSnapshot.startedAt {
            let elapsed = max(0, now.timeIntervalSince(startedAt))
            if elapsed > 0.5 {
                enriched.averageBytesPerSecond = Double(newSnapshot.copiedBytes) / elapsed
            }
        }

        if let previous {
            let interval = max(0.001, now.timeIntervalSince(previous.date))
            let delta = newSnapshot.copiedBytes >= previous.copiedBytes ? newSnapshot.copiedBytes - previous.copiedBytes : 0
            enriched.currentBytesPerSecond = Double(delta) / interval
            enriched.targets = newSnapshot.targets.map { target in
                var target = target
                let lastBytes = previous.targetBytes[target.id] ?? target.copiedBytes
                let targetDelta = target.copiedBytes >= lastBytes ? target.copiedBytes - lastBytes : 0
                target.bytesPerSecond = Double(targetDelta) / interval
                return target
            }
        }

        if enriched.currentBytesPerSecond > 1, enriched.totalBytes > enriched.copiedBytes {
            enriched.etaSeconds = Double(enriched.totalBytes - enriched.copiedBytes) / enriched.currentBytesPerSecond
        } else if enriched.averageBytesPerSecond > 1, enriched.totalBytes > enriched.copiedBytes {
            enriched.etaSeconds = Double(enriched.totalBytes - enriched.copiedBytes) / enriched.averageBytesPerSecond
        } else {
            enriched.etaSeconds = nil
        }

        lastSpeedSample = (now, newSnapshot.copiedBytes, targetBytes)
        snapshot = enriched
        updateDockProgress(enriched.progress)
        if let log = newSnapshot.recentLog, logs.last != log {
            logs.append(log)
            if logs.count > 500 {
                logs.removeFirst(logs.count - 500)
            }
        }
    }

    private func updateDockProgress(_ progress: Double) {
        guard dockProgressEnabled, isRunning else { return }
        let clamped = max(0, min(1, progress))
        let view = DockProgressView(progress: clamped)
        view.frame = NSRect(x: 0, y: 0, width: NSApp.dockTile.size.width, height: NSApp.dockTile.size.height)
        NSApp.dockTile.contentView = view
        NSApp.dockTile.display()
    }

    private func clearDockProgress() {
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.badgeLabel = nil
        NSApp.dockTile.display()
    }

    private func startVolumeMonitoring() {
        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else {
                return
            }
            Task { @MainActor in
                self.handleMountedVolume(url)
            }
        }
    }

    private func handleMountedVolume(_ url: URL) {
        guard !isRunning else { return }
        
        // Exclude system disk or explicitly ignored volumes
        if url.path == "/" || url.path.hasPrefix("/System") || ignoredVolumes.contains(url) {
            return
        }
        
        // Exclude if it is one of the target directories
        let isTarget = targetRoots.contains { target in
            target.path.hasPrefix(url.path) || url.path.hasPrefix(target.path)
        }
        if isTarget {
            return
        }

        mountDetectionTask?.cancel()
        mountDetectionTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            let inspection: (profile: CameraCardProfile, videoCount: Int)? = await Task.detached(priority: .utility) {
                let profile = CameraCardDetector.detect(sourceURL: url)
                let videoCount = CameraCardDetector.videoFileCount(sourceURL: url)
                guard profile != .unknown || videoCount > 0 else { return nil }
                return (profile: profile, videoCount: videoCount)
            }.value
            guard !Task.isCancelled, let inspection else { return }
            await MainActor.run {
                self?.inspectMountedVolume(url, profile: inspection.profile, videoCount: inspection.videoCount)
            }
        }
    }

    private func inspectMountedVolume(_ url: URL, profile: CameraCardProfile, videoCount: Int) {
        guard !isRunning else { return }
        guard !ignoredVolumes.contains(url) else { return }

        mountedSourceCandidate = MountedSourceCandidate(
            volumeName: url.lastPathComponent,
            url: url,
            profile: profile,
            videoFileCount: videoCount,
            status: tr("等待确认", "Awaiting confirmation"),
            suggestedCardName: suggestedCardName(for: url.lastPathComponent)
        )
    }

    private func suggestedCardName(for volumeName: String) -> String? {
        let registeredCardNames = cameraRegistry
            .flatMap(\.cardNames)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !registeredCardNames.isEmpty else { return nil }

        let exact = volumeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = registeredCardNames.first(where: { $0.caseInsensitiveCompare(exact) == .orderedSame }) {
            return match
        }

        let genericNames = ["untitled", "no name", "noname", "unknown", "eos_digital"]
        let normalized = volumeName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard genericNames.contains(where: { normalized == $0 || normalized.hasPrefix("\($0) ") }) else {
            return nil
        }

        for camera in cameraRegistry {
            let current = camera.currentCard.trimmingCharacters(in: .whitespacesAndNewlines)
            if !current.isEmpty,
               let registered = registeredCardNames.first(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) {
                return registered
            }
        }

        return registeredCardNames.first
    }

    private func nextReel(after value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "A001" }
        let pattern = #"^(.*?)(\d+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.numberOfRanges == 3,
              let prefixRange = Range(match.range(at: 1), in: trimmed),
              let numberRange = Range(match.range(at: 2), in: trimmed),
              let number = Int(trimmed[numberRange])
        else {
            return "\(trimmed)001"
        }
        let prefix = String(trimmed[prefixRange])
        let numberString = String(trimmed[numberRange])
        return "\(prefix)\(String(format: "%0*d", numberString.count, number + 1))"
    }
}

private final class DockProgressView: NSView {
    let progress: Double

    init(progress: Double) {
        self.progress = progress
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        if let icon = NSApp.applicationIconImage {
            icon.draw(in: bounds)
        }

        let barHeight = max(7, bounds.height * 0.08)
        let inset = bounds.width * 0.13
        let y = bounds.height * 0.11
        let track = NSRect(x: inset, y: y, width: bounds.width - inset * 2, height: barHeight)
        let radius = barHeight / 2

        NSColor.black.withAlphaComponent(0.38).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        let fillWidth = max(barHeight, track.width * CGFloat(max(0, min(1, progress))))
        let fill = NSRect(x: track.minX, y: track.minY, width: fillWidth, height: track.height)
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }
}
