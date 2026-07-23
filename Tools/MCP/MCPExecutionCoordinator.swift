import Foundation

private struct MCPManagedTaskRecord {
    var id: String
    var kind: String
    var state: String
    var progress: Double
    var message: String
    var startedAt: Date
    var updatedAt: Date
    var result: JSONObject?
    var error: String?

    var dictionary: JSONObject {
        var value: JSONObject = [
            "task_id": id,
            "kind": kind,
            "state": state,
            "progress": progress,
            "message": message,
            "started_at": ISO8601DateFormatter().string(from: startedAt),
            "updated_at": ISO8601DateFormatter().string(from: updatedAt)
        ]
        if let result { value["result"] = result }
        if let error { value["error"] = error }
        return value
    }
}

final class MCPExecutionCoordinator {
    private let lock = NSLock()
    private let persistenceURL: URL
    private var records: [String: MCPManagedTaskRecord] = [:]
    private var runningTasks: [String: Task<Void, Never>] = [:]
    private var idempotencyTasks: [String: String] = [:]

    init(persistenceURL: URL? = nil) {
        self.persistenceURL = persistenceURL ?? Self.defaultPersistenceURL()
        loadPersistedState()
    }

    func startOffload(settings: OffloadSettings, idempotencyKey: String) -> JSONObject {
        let taskID = existingOrNewTaskID(kind: "offload", idempotencyKey: idempotencyKey)
        if let existing = status(taskID: taskID) { return existing }

        createRecord(id: taskID, kind: "offload", message: "Queued verified camera-card offload")
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let report = try await OffloadEngine().run(settings: settings) { snapshot in
                    self.update(
                        taskID: taskID,
                        state: "running",
                        progress: snapshot.progress,
                        message: snapshot.message,
                        result: [
                            "completed_files": snapshot.completedFiles,
                            "total_files": snapshot.totalFiles,
                            "copied_bytes": snapshot.copiedBytes,
                            "total_bytes": snapshot.totalBytes,
                            "targets": snapshot.targets.map { target in
                                [
                                    "path": target.outputURL.path,
                                    "state": target.state.rawValue,
                                    "copied_bytes": target.copiedBytes,
                                    "verified_bytes": target.verifiedBytes,
                                    "error": target.error ?? ""
                                ] as JSONObject
                            }
                        ]
                    )
                }
                self.finish(taskID: taskID, result: self.offloadResult(report))
            } catch is CancellationError {
                self.cancelled(taskID: taskID)
            } catch {
                self.fail(taskID: taskID, error: error.localizedDescription)
            }
        }
        setRunningTask(task, for: taskID)
        return status(taskID: taskID) ?? ["task_id": taskID, "state": "queued"]
    }

    func startConversion(
        sourceURLs: [URL],
        destinationURL: URL,
        mode: MediaConversionMode,
        target: MediaContainer,
        transcodeSettings: MediaTranscodeSettings,
        ffmpegPath: String,
        idempotencyKey: String
    ) -> JSONObject {
        let taskID = existingOrNewTaskID(kind: "media_conversion", idempotencyKey: idempotencyKey)
        if let existing = status(taskID: taskID) { return existing }

        createRecord(id: taskID, kind: "media_conversion", message: "Queued verified media conversion")
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                var outputs: [JSONObject] = []
                for (index, sourceURL) in sourceURLs.enumerated() {
                    try Task.checkCancellation()
                    let prefix = Double(index) / Double(max(sourceURLs.count, 1))
                    let width = 1 / Double(max(sourceURLs.count, 1))
                    self.update(
                        taskID: taskID,
                        state: "running",
                        progress: prefix,
                        message: "Analyzing \(sourceURL.lastPathComponent)"
                    )

                    let probeService = MediaProbeService(language: .en)
                    let sourceProbe: ProbedMedia
                    switch probeService.probeSync(url: sourceURL, configuredFFmpegPath: ffmpegPath) {
                    case .success(let value):
                        sourceProbe = value
                    case .failure(let error):
                        throw error
                    }
                    let compatibility = MediaCompatibilityService(language: .en).decide(
                        probed: sourceProbe,
                        mode: mode,
                        target: target,
                        transcode: transcodeSettings
                    )
                    guard compatibility.verdict != .incompatible,
                          compatibility.verdict != .missingDependency,
                          compatibility.verdict != .probeFailed else {
                        throw MCPServerError.conflict(
                            compatibility.risks.map { $0.message(language: .en) }.joined(separator: " · ")
                        )
                    }

                    let engine = MediaConversionEngine(language: .en, configuredFFmpegPath: ffmpegPath)
                    let staged = try await engine.convert(
                        sourceURL: sourceURL,
                        probed: sourceProbe,
                        mode: mode,
                        target: target,
                        transcodeSettings: transcodeSettings,
                        destinationDirectory: destinationURL
                    ) { update in
                        self.update(
                            taskID: taskID,
                            state: "running",
                            progress: min(0.95, prefix + update.fraction * width * 0.8),
                            message: "Converting \(sourceURL.lastPathComponent)"
                        )
                    }

                    do {
                        let verifier = MediaVerificationService(language: .en, configuredFFmpegPath: ffmpegPath)
                        self.update(
                            taskID: taskID,
                            state: "running",
                            progress: prefix + width * 0.85,
                            message: "Verifying \(sourceURL.lastPathComponent)"
                        )
                        let (_, verification) = try await verifier.verify(
                            source: sourceProbe,
                            outputURL: staged.temporaryURL,
                            mode: mode,
                            transcodeSettings: transcodeSettings
                        )
                        guard verification.passed else {
                            engine.discardTemporaryOutput(staged)
                            throw MCPServerError.conflict(verification.messages.joined(separator: " · "))
                        }
                        let finalURL = try engine.commitVerifiedOutput(staged)
                        let finalProbe: ProbedMedia
                        switch probeService.probeSync(url: finalURL, configuredFFmpegPath: ffmpegPath) {
                        case .success(let value):
                            finalProbe = value
                        case .failure(let error):
                            try? FileManager.default.removeItem(at: finalURL)
                            throw error
                        }
                        let report = MediaConversionReport(
                            schema: "com.321doit.media-conversion-result",
                            schemaVersion: 1,
                            taskID: UUID(),
                            createdAt: Date(),
                            startedAt: staged.startedAt,
                            endedAt: Date(),
                            appVersion: DoitMCPServer.version,
                            ffmpegVersion: staged.ffmpegVersion,
                            projectAssociationMode: "independent",
                            linkedProjectID: nil,
                            sourcePath: sourceURL.path,
                            outputPath: finalURL.path,
                            sourceSizeBytes: sourceProbe.sizeBytes,
                            outputSizeBytes: finalProbe.sizeBytes,
                            mode: mode,
                            targetContainer: target,
                            transcodeSettings: mode == .transcode ? transcodeSettings : nil,
                            projectContext: nil,
                            ffmpegArguments: staged.ffmpegArguments,
                            sourceProbe: sourceProbe,
                            outputProbe: finalProbe,
                            compatibility: compatibility,
                            reencodesVideo: compatibility.reencodesVideo,
                            reencodesAudio: compatibility.reencodesAudio,
                            verification: verification,
                            warnings: compatibility.risks.filter { $0.severity != .blocking },
                            errors: []
                        )
                        let reportURL = try MediaConversionReportWriter.write(report, beside: finalURL)
                        outputs.append([
                            "source_path": sourceURL.path,
                            "output_path": finalURL.path,
                            "report_path": reportURL.path,
                            "verification": try MCPJSON.dictionary(from: verification)
                        ])
                    } catch {
                        engine.discardTemporaryOutput(staged)
                        throw error
                    }
                }
                self.finish(taskID: taskID, result: [
                    "outputs": outputs,
                    "output_count": outputs.count,
                    "destination_path": destinationURL.path
                ])
            } catch is CancellationError {
                self.cancelled(taskID: taskID)
            } catch {
                self.fail(taskID: taskID, error: error.localizedDescription)
            }
        }
        setRunningTask(task, for: taskID)
        return status(taskID: taskID) ?? ["task_id": taskID, "state": "queued"]
    }

    func status(taskID: String) -> JSONObject? {
        lock.lock()
        defer { lock.unlock() }
        return records[taskID]?.dictionary
    }

    func cancel(taskID: String) -> JSONObject? {
        lock.lock()
        let task = runningTasks[taskID]
        lock.unlock()
        guard let task else { return status(taskID: taskID) }
        task.cancel()
        update(taskID: taskID, state: "cancelling", message: "Cancellation requested")
        return status(taskID: taskID)
    }

    private func existingOrNewTaskID(kind: String, idempotencyKey: String) -> String {
        let token = "\(kind):\(idempotencyKey)"
        lock.lock()
        defer { lock.unlock() }
        if let existing = idempotencyTasks[token] { return existing }
        let id = UUID().uuidString.lowercased()
        idempotencyTasks[token] = id
        return id
    }

    private func createRecord(id: String, kind: String, message: String) {
        let now = Date()
        lock.lock()
        records[id] = MCPManagedTaskRecord(
            id: id,
            kind: kind,
            state: "queued",
            progress: 0,
            message: message,
            startedAt: now,
            updatedAt: now
        )
        persistLocked()
        lock.unlock()
    }

    private func setRunningTask(_ task: Task<Void, Never>, for taskID: String) {
        lock.lock()
        runningTasks[taskID] = task
        lock.unlock()
    }

    private func update(
        taskID: String,
        state: String,
        progress: Double? = nil,
        message: String,
        result: JSONObject? = nil
    ) {
        lock.lock()
        if var record = records[taskID] {
            record.state = state
            if let progress { record.progress = max(0, min(1, progress)) }
            record.message = message
            record.updatedAt = Date()
            if let result { record.result = result }
            records[taskID] = record
            persistLocked()
        }
        lock.unlock()
    }

    private func finish(taskID: String, result: JSONObject) {
        lock.lock()
        if var record = records[taskID] {
            record.state = "completed"
            record.progress = 1
            record.message = "Task completed"
            record.updatedAt = Date()
            record.result = result
            records[taskID] = record
        }
        runningTasks[taskID] = nil
        persistLocked()
        lock.unlock()
    }

    private func fail(taskID: String, error: String) {
        lock.lock()
        if var record = records[taskID] {
            record.state = "failed"
            record.message = "Task failed"
            record.updatedAt = Date()
            record.error = error
            records[taskID] = record
        }
        runningTasks[taskID] = nil
        persistLocked()
        lock.unlock()
    }

    private func cancelled(taskID: String) {
        lock.lock()
        if var record = records[taskID] {
            record.state = "cancelled"
            record.message = "Task cancelled"
            record.updatedAt = Date()
            records[taskID] = record
        }
        runningTasks[taskID] = nil
        persistLocked()
        lock.unlock()
    }

    private static func defaultPersistenceURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        // Do not let independent MCP clients overwrite each other's tasks.
        // A caller that needs restart recovery (such as Mira) supplies an
        // explicit, private store path for its own runtime scope.
        let directory = base
            .appendingPathComponent("321Doit/MCP/Sessions", isDirectory: true)
            .appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("tasks.json")
    }

    private func loadPersistedState() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? JSONObject else { return }
        let formatter = ISO8601DateFormatter()
        let storedRecords = root["records"] as? [String: JSONObject] ?? [:]
        let storedIdempotency = root["idempotency"] as? [String: String] ?? [:]

        lock.lock()
        for (id, value) in storedRecords {
            guard let kind = value["kind"] as? String,
                  let state = value["state"] as? String,
                  let progress = value["progress"] as? Double,
                  let message = value["message"] as? String,
                  let startedText = value["started_at"] as? String,
                  let updatedText = value["updated_at"] as? String,
                  let startedAt = formatter.date(from: startedText),
                  let updatedAt = formatter.date(from: updatedText) else { continue }
            var record = MCPManagedTaskRecord(
                id: id,
                kind: kind,
                state: state,
                progress: progress,
                message: message,
                startedAt: startedAt,
                updatedAt: updatedAt,
                result: value["result"] as? JSONObject,
                error: value["error"] as? String
            )
            if ["queued", "running", "cancelling"].contains(record.state) {
                record.state = "interrupted"
                record.message = "MCP restarted before this task completed"
                record.updatedAt = Date()
                record.error = "The previous MCP process ended. Inspect the recorded paths before retrying with a new idempotency key."
            }
            records[id] = record
        }
        idempotencyTasks = storedIdempotency.filter { records[$0.value] != nil }
        persistLocked()
        lock.unlock()
    }

    private func persistLocked() {
        let root: JSONObject = [
            "schema": "com.321doit.mcp-task-store",
            "version": 1,
            "records": Dictionary(uniqueKeysWithValues: records.map { ($0.key, $0.value.dictionary) }),
            "idempotency": idempotencyTasks
        ]
        guard JSONSerialization.isValidJSONObject(root),
              let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: persistenceURL, options: .atomic)
    }

    private func offloadResult(_ report: OffloadReport) -> JSONObject {
        let targets = report.targets.map { target -> JSONObject in
            var reportPaths: JSONObject = [:]
            if let value = target.mhlURL { reportPaths["mhl"] = value.path }
            if let value = target.pdfURL { reportPaths["pdf"] = value.path }
            if let value = target.csvURL { reportPaths["csv"] = value.path }
            if let value = target.jsonURL { reportPaths["json"] = value.path }
            if let value = target.txtURL { reportPaths["txt"] = value.path }
            if let value = target.sidecarURL { reportPaths["checksum_sidecar"] = value.path }
            var value: JSONObject = [
                "target_root": target.rootURL.path,
                "output_path": target.outputURL.path,
                "reports_directory": OffloadPackageLayout.reportsRoot(outputURL: target.outputURL).path,
                "state": target.state.rawValue,
                "copied_bytes": target.copiedBytes,
                "verified_bytes": target.verifiedBytes,
                "report_paths": reportPaths
            ]
            if let error = target.error { value["error"] = error }
            return value
        }
        return [
            "task_id": report.settings.taskID.uuidString.lowercased(),
            "project_name": report.settings.projectName,
            "card_number": report.settings.cardNumber,
            "source_path": report.settings.sourceURL.path,
            "total_files": report.totalFiles,
            "total_bytes": report.totalBytes,
            "started_at": ISO8601DateFormatter().string(from: report.startedAt),
            "ended_at": ISO8601DateFormatter().string(from: report.endedAt),
            "successful_target_count": report.successfulTargets.count,
            "targets": targets
        ]
    }
}
