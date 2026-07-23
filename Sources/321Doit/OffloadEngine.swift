import Foundation
import IOKit.pwr_mgt

typealias OffloadProgressHandler = (OffloadSnapshot) async -> Void

final class OffloadEngine {
#if DEBUG
    static var attemptedManifestWriteSpy: ((Bool) -> Void)? = nil
    static var actualManifestWriteSpy: ((Bool) -> Void)? = nil
    static var testInjectErrorOnPath: String? = nil
#endif

    private let fileManager = FileManager.default

    /// Upper bound on how often the byte-copy loop publishes progress. A fast
    /// disk would otherwise trigger a main-actor hop + Dock redraw on every
    /// chunk (dozens to hundreds per second), which both wastes work and
    /// throttles copy throughput by coupling it to the main thread.
    private static let minProgressInterval: TimeInterval = 0.08
    private var lastProgressPublishAt = Date.distantPast

    /// Returns true at most every `minProgressInterval` seconds; used to
    /// rate-limit the high-frequency in-loop progress publishes. Per-file and
    /// completion publishes bypass this so final counts stay accurate.
    private func shouldPublishLoopProgress() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastProgressPublishAt) >= Self.minProgressInterval else { return false }
        lastProgressPublishAt = now
        return true
    }

    func run(settings: OffloadSettings, progress: @escaping OffloadProgressHandler) async throws -> OffloadReport {
        var settings = settings
        if settings.sourceCardProfile == .unknown {
            settings.sourceCardProfile = CameraCardDetector.detect(sourceURL: settings.sourceURL)
        }

        let startedAt = Date()
        var logs: [String] = []
        let lang = settings.language
        func tr(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: lang) }

        func log(_ message: String) {
            let line = "[\(Self.timeString(Date()))] \(message)"
            logs.append(line)
        }

        let sourceFiles = try preflight(settings: settings)
        let totalBytes = sourceFiles.reduce(UInt64(0)) { $0 + $1.size }
        let chunkSize = Self.normalizedChunkSize(copyBufferKB: settings.copyBufferKB)
        var sourceBytesProcessed: UInt64 = 0
        var completedFiles = 0
        var fileRecords: [FileCopyRecord] = []
        let targets = makeTargetWorks(settings: settings)

        let sleepAssertion = SleepAssertion(reason: "321Doit is offloading camera media")
        defer { sleepAssertion.release() }

        log(tr("任务开始：\(settings.outputFolderName)", "Task started: \(settings.outputFolderName)"))
        log(tr("校验算法：\(settings.checksumAlgorithm.displayName)", "Checksum: \(settings.checksumAlgorithm.displayName)"))
        if settings.checksumAlgorithm == .xxhash64 {
            log(tr("xxHash64 实现：\(settings.xxHash64Implementation.label.0)",
                   "xxHash64 implementation: \(settings.xxHash64Implementation.label.1)"))
        }
        log(tr("识别卡类型：\(settings.sourceCardProfile.displayName)",
               "Detected card: \(settings.sourceCardProfile.displayName)"))
        for target in targets {
            try fileManager.createDirectory(at: target.outputURL, withIntermediateDirectories: true)
            try target.writeResumeManifest()
        }
        if targets.contains(where: { $0.wasResumedFromManifest }) {
            settings.resumedFromJournal = true
            log(tr("检测到 session.json，任务将按 interrupted/resumed 流程恢复。",
                   "session.json detected; resuming the task via the interrupted/resumed flow."))
        }

        try await publish(
            progress,
            message: tr("正在拷贝", "Copying"),
            totalFiles: sourceFiles.count,
            completedFiles: completedFiles,
            totalBytes: totalBytes,
            copiedBytes: sourceBytesProcessed,
            startedAt: startedAt,
            targets: targets,
            recentLog: logs.last
        )

        for sourceFile in sourceFiles {
            try Task.checkCancellation()
            let record: FileCopyRecord
            if settings.verifyOnly {
                record = try await verifyExistingFile(
                    sourceFile,
                    targets: targets,
                    totalFiles: sourceFiles.count,
                    completedFiles: &completedFiles,
                    totalBytes: totalBytes,
                    sourceBytesProcessed: &sourceBytesProcessed,
                    checksumAlgorithm: settings.checksumAlgorithm,
                    xxHash64Implementation: settings.xxHash64Implementation,
                    retryCount: settings.checksumRetryCount,
                    chunkSize: chunkSize,
                    strictResume: settings.strictResume,
                    startedAt: startedAt,
                    language: lang,
                    logs: &logs,
                    progress: progress
                )
            } else {
                record = try await copyOneFile(
                    sourceFile,
                    targets: targets,
                    totalFiles: sourceFiles.count,
                    completedFiles: &completedFiles,
                    totalBytes: totalBytes,
                    sourceBytesProcessed: &sourceBytesProcessed,
                    checksumAlgorithm: settings.checksumAlgorithm,
                    xxHash64Implementation: settings.xxHash64Implementation,
                    retryCount: settings.checksumRetryCount,
                    chunkSize: chunkSize,
                    enableSpeedLimit: settings.enableSpeedLimit,
                    speedLimitMBps: settings.speedLimitMBps,
                    strictResume: settings.strictResume,
                    ioRetryCount: settings.ioRetryCount,
                    startedAt: startedAt,
                    language: lang,
                    logs: &logs,
                    progress: progress
                )
            }
            fileRecords.append(record)
        }

        try Task.checkCancellation()
        for target in targets where target.isActive {
            target.state = .completed
            try? target.writeResumeManifest(force: true)
        }

        let endedAt = Date()
        var reports = targets.map {
            TargetReport(
                rootURL: $0.rootURL,
                outputURL: $0.outputURL,
                packageMode: $0.packageMode,
                state: $0.state,
                copiedBytes: $0.copiedBytes,
                verifiedBytes: $0.verifiedBytes,
                error: $0.error,
                mhlURL: nil,
                pdfURL: nil,
                csvURL: nil,
                jsonURL: nil,
                txtURL: nil,
                sidecarURL: nil,
                proxyURL: nil,
                proxyFilesCreated: 0,
                proxyErrors: []
            )
        }

        let copyCompletedCount = reports.filter { $0.state == .completed }.count
        if copyCompletedCount == 0 {
            log(tr("所有目标失败，未写入报告。", "All destinations failed; no report was written."))
            throw OffloadError.allTargetsFailed
        }

        let shouldTranscode = settings.generateProxies || settings.transcodeProfile.burnIn.enabled
        if shouldTranscode {
            for index in reports.indices where reports[index].state == .completed {
                try Task.checkCancellation()
                let targetOutput = reports[index].outputURL.path
                let targetId = targets[index].id
                log(tr("开始转码 \(settings.transcodeProfile.codec.displayName)：\(targetOutput)",
                       "Starting transcode \(settings.transcodeProfile.codec.displayName): \(targetOutput)"))
                targets[index].state = .transcoding
                let proxyResult = try await ProxyTranscoder.transcodeVerifiedFiles(
                    files: fileRecords,
                    target: reports[index],
                    profile: settings.transcodeProfile,
                    offload: settings
                ) { message, transcodeProgress in
                    if let workIndex = targets.firstIndex(where: { $0.id == targetId }) {
                        targets[workIndex].transcodeProgress = transcodeProgress
                    }
                    await progress(OffloadSnapshot(
                        message: message,
                        totalFiles: sourceFiles.count,
                        completedFiles: completedFiles,
                        totalBytes: totalBytes,
                        copiedBytes: totalBytes,
                        startedAt: startedAt,
                        targets: targets.map { $0.progress },
                        recentLog: logs.last
                    ))
                }
                targets[index].state = .completed
                reports[index].proxyURL = proxyResult.proxyURL
                reports[index].proxyFilesCreated = proxyResult.created
                reports[index].proxyErrors = proxyResult.errors
                log(tr(
                    "转码完成 \(settings.transcodeProfile.codec.shortLabel)：\(proxyResult.created) 个，失败 \(proxyResult.errors.count) 个。",
                    "Transcode finished \(settings.transcodeProfile.codec.shortLabel): \(proxyResult.created) created, \(proxyResult.errors.count) failed."
                ))
                for error in proxyResult.errors {
                    log(tr("转码失败：\(error)", "Transcode failed: \(error)"))
                }
            }
        }

        if settings.transcodeProfile.frameExtraction.enabled {
            for index in reports.indices where reports[index].state == .completed {
                try Task.checkCancellation()
                let targetId = targets[index].id
                log(tr("开始抽取视频帧：\(reports[index].outputURL.path)",
                       "Starting frame extraction: \(reports[index].outputURL.path)"))
                targets[index].state = .transcoding
                let frameResult = try await ProxyTranscoder.extractFrames(
                    files: fileRecords,
                    target: reports[index],
                    profile: settings.transcodeProfile
                ) { message, progressVal in
                    if let workIndex = targets.firstIndex(where: { $0.id == targetId }) {
                        targets[workIndex].transcodeProgress = progressVal
                    }
                    await progress(OffloadSnapshot(
                        message: message,
                        totalFiles: sourceFiles.count,
                        completedFiles: completedFiles,
                        totalBytes: totalBytes,
                        copiedBytes: totalBytes,
                        startedAt: startedAt,
                        targets: targets.map { $0.progress },
                        recentLog: logs.last
                    ))
                }
                targets[index].state = .completed
                log(tr(
                    "截图导出完成：创建 \(frameResult.created) 张，失败 \(frameResult.errors.count) 张。",
                    "Frame extraction finished: \(frameResult.created) created, \(frameResult.errors.count) failed."
                ))
                for error in frameResult.errors {
                    log(tr("截图失败：\(error)", "Frame extraction failed: \(error)"))
                }
            }
        }

        var reportFailures: [String] = []
        for index in reports.indices where reports[index].state == .completed {
            try Task.checkCancellation()
            do {
                let urls = try ReportWriter.writeTargetReports(
                    settings: settings,
                    startedAt: startedAt,
                    endedAt: endedAt,
                    totalFiles: sourceFiles.count,
                    totalBytes: totalBytes,
                    files: fileRecords,
                    target: reports[index],
                    allTargets: reports,
                    logs: logs
                )
                reports[index].mhlURL = urls.mhlURL
                reports[index].pdfURL = urls.pdfURL
                reports[index].csvURL = urls.csvURL
                reports[index].jsonURL = urls.jsonURL
                reports[index].txtURL = urls.txtURL
                reports[index].sidecarURL = urls.sidecarURL
                log(tr("报告完成：\(reports[index].outputURL.path)",
                       "Reports written: \(reports[index].outputURL.path)"))
            } catch {
                reports[index].state = .failed
                reports[index].error = tr("报告写入失败：\(error.localizedDescription)",
                                          "Failed to write reports: \(error.localizedDescription)")
                reportFailures.append("\(reports[index].outputURL.path): \(error.localizedDescription)")
                log(tr("报告写入失败：\(reports[index].outputURL.path) \(error.localizedDescription)",
                       "Failed to write reports: \(reports[index].outputURL.path) \(error.localizedDescription)"))
            }
        }

        for index in reports.indices where reports[index].state == .completed {
            Self.writeAuditLog(
                outputURL: reports[index].outputURL,
                settings: settings,
                startedAt: startedAt,
                endedAt: endedAt,
                files: fileRecords,
                target: reports[index],
                logs: logs
            )
        }

        if !reportFailures.isEmpty {
            throw OffloadError.reportGenerationFailed(reportFailures)
        }

        let completedCount = reports.filter { $0.state == .completed }.count

        let finalReport = OffloadReport(
            settings: settings,
            startedAt: startedAt,
            endedAt: endedAt,
            totalFiles: sourceFiles.count,
            totalBytes: totalBytes,
            files: fileRecords,
            targets: reports,
            logs: logs
        )

        try Task.checkCancellation()
        try await publish(
            progress,
            message: tr("任务完成：\(completedCount) 个目标成功",
                        "Task complete: \(completedCount) destination\(completedCount == 1 ? "" : "s") succeeded"),
            totalFiles: sourceFiles.count,
            completedFiles: completedFiles,
            totalBytes: totalBytes,
            copiedBytes: totalBytes,
            startedAt: startedAt,
            targets: targets,
            recentLog: logs.last
        )

        return finalReport
    }

    private func preflight(settings: OffloadSettings) throws -> [SourceFile] {
        guard !settings.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !settings.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !settings.operatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw OffloadError.missingRequiredFields
        }
        guard !settings.targetRoots.isEmpty else { throw OffloadError.noTargets }
        guard settings.targetRoots.count <= 3 else { throw OffloadError.tooManyTargets }

        let files = try enumerateSourceFiles(at: settings.sourceURL)
        guard !files.isEmpty else { throw OffloadError.noFiles }
        let totalBytes = files.reduce(UInt64(0)) { $0 + $1.size }

        var seenTargets = Set<String>()
        for targetRoot in settings.targetRoots {
            let standardized = targetRoot.standardizedFileURL.path
            if seenTargets.contains(standardized) {
                throw OffloadError.duplicateTarget(targetRoot)
            }
            seenTargets.insert(standardized)

            for mode in settings.normalizedOutputPackageModes {
                let outputURL = targetRoot.appendingPathComponent(settings.outputFolderName(for: mode), isDirectory: true)
                if isSameOrNested(outputURL, under: settings.sourceURL) || isSameOrNested(settings.sourceURL, under: outputURL) {
                    throw OffloadError.nestedPath(L10n.t(
                        "来源和目标不能相同或互相嵌套：\(targetRoot.path)",
                        "Source and destination cannot be the same or nested: \(targetRoot.path)",
                        language: settings.language
                    ))
                }
                if settings.verifyOnly {
                    if !fileManager.fileExists(atPath: outputURL.path) {
                        throw OffloadError.duplicateOutput(outputURL)
                    }
                } else if fileManager.fileExists(atPath: outputURL.path), !Self.hasResumeManifest(at: outputURL) {
                    throw OffloadError.duplicateOutput(outputURL)
                }
            }

            let capacity = availableCapacity(at: targetRoot)
            let neededBytes = totalBytes * UInt64(settings.normalizedOutputPackageModes.count)
            if !settings.verifyOnly, capacity > 0 && capacity < neededBytes {
                throw OffloadError.insufficientSpace(target: targetRoot, needed: neededBytes, available: capacity)
            }

            if let fsName = Self.filesystemName(for: targetRoot),
               Self.isLikelyFAT32(fsName),
               let large = files.first(where: { $0.size > Self.fat32SingleFileLimit }) {
                throw OffloadError.fat32LargeFile(target: targetRoot, file: large.relativePath, size: large.size)
            }
        }

        return files
    }

    private func verifyExistingFile(
        _ sourceFile: SourceFile,
        targets: [TargetWork],
        totalFiles: Int,
        completedFiles: inout Int,
        totalBytes: UInt64,
        sourceBytesProcessed: inout UInt64,
        checksumAlgorithm: ChecksumAlgorithm,
        xxHash64Implementation: XXHash64Implementation,
        retryCount: Int,
        chunkSize: Int,
        strictResume: Bool,
        startedAt: Date,
        language: AppLanguage,
        logs: inout [String],
        progress: @escaping OffloadProgressHandler
    ) async throws -> FileCopyRecord {
        func tr(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: language) }
        func appendLog(_ message: String) {
            logs.append("[\(Self.timeString(Date()))] \(message)")
        }

        let sourceHash = try hashFileWithRetry(
            at: sourceFile.url,
            algorithm: checksumAlgorithm,
            xxHash64Implementation: xxHash64Implementation,
            chunkSize: chunkSize,
            retryCount: retryCount
        )
        sourceBytesProcessed &+= sourceFile.size
        var targetResults: [FileTargetResult] = []

        for target in targets {
            guard target.isActive else {
                targetResults.append(FileTargetResult(
                    rootPath: target.rootURL.path,
                    outputPath: target.destinationURL(for: sourceFile).path,
                    copied: false,
                    verified: false,
                    hash: nil,
                    error: tr("目标此前失败，已跳过。", "Destination failed earlier; skipped.")
                ))
                continue
            }

            target.state = .verifying
            let finalURL = target.destinationURL(for: sourceFile)
            do {
                target.recordStatus(sourceFile, sourceHash: sourceHash, targetHash: nil, status: .verifying, errorMessage: nil)
                try target.writeResumeManifest()
                guard fileManager.fileExists(atPath: finalURL.path) else {
                    target.fail(tr("重新校验失败，目标缺少文件：\(sourceFile.relativePath)",
                                   "Re-verify failed, destination missing file: \(sourceFile.relativePath)"))
                    target.recordStatus(sourceFile, sourceHash: sourceHash, targetHash: nil, status: .failed, errorMessage: target.error)
                    try? target.writeResumeManifest()
                    targetResults.append(FileTargetResult(
                        rootPath: target.rootURL.path,
                        outputPath: finalURL.path,
                        copied: false,
                        verified: false,
                        hash: nil,
                        error: target.error
                    ))
                    continue
                }
                let size = try fileSize(at: finalURL)
                let targetHash = try hashFileWithRetry(
                    at: finalURL,
                    algorithm: checksumAlgorithm,
                    xxHash64Implementation: xxHash64Implementation,
                    chunkSize: chunkSize,
                    retryCount: retryCount,
                    bypassCache: true
                )
                if size == sourceFile.size && targetHash == sourceHash {
                    target.verifiedBytes &+= sourceFile.size
                    target.copiedBytes &+= sourceFile.size
                    target.recordVerifiedFile(sourceFile, sourceHash: sourceHash, targetHash: targetHash)
                    try target.writeResumeManifest()
                    targetResults.append(FileTargetResult(
                        rootPath: target.rootURL.path,
                        outputPath: finalURL.path,
                        copied: true,
                        verified: true,
                        hash: targetHash,
                        error: nil
                    ))
                } else {
                    target.fail(tr("重新校验失败：\(sourceFile.relativePath)",
                                   "Re-verify failed: \(sourceFile.relativePath)"))
                    target.recordStatus(sourceFile, sourceHash: sourceHash, targetHash: targetHash, status: .failed, errorMessage: target.error)
                    try? target.writeResumeManifest()
                    targetResults.append(FileTargetResult(
                        rootPath: target.rootURL.path,
                        outputPath: finalURL.path,
                        copied: true,
                        verified: false,
                        hash: targetHash,
                        error: target.error
                    ))
                }
            } catch let error as CancellationError {
                throw error
            } catch {
                target.fail(tr("重新校验失败：\(sourceFile.relativePath) \(error.localizedDescription)",
                               "Re-verify failed: \(sourceFile.relativePath) \(error.localizedDescription)"))
                target.recordStatus(sourceFile, sourceHash: sourceHash, targetHash: nil, status: .failed, errorMessage: target.error)
                try? target.writeResumeManifest()
                targetResults.append(FileTargetResult(
                    rootPath: target.rootURL.path,
                    outputPath: finalURL.path,
                    copied: true,
                    verified: false,
                    hash: nil,
                    error: target.error
                ))
            }
        }

        completedFiles += 1
        appendLog(tr("重新校验完成：\(sourceFile.relativePath)",
                     "Re-verify finished: \(sourceFile.relativePath)"))
        let record = FileCopyRecord(
            relativePath: sourceFile.relativePath,
            size: sourceFile.size,
            modifiedAt: sourceFile.modifiedAt,
            sourceHash: sourceHash,
            targetResults: targetResults
        )

        try await publish(
            progress,
            message: tr("重新校验 \(sourceFile.relativePath)", "Re-verifying \(sourceFile.relativePath)"),
            totalFiles: totalFiles,
            completedFiles: completedFiles,
            totalBytes: totalBytes,
            copiedBytes: sourceBytesProcessed,
            startedAt: startedAt,
            targets: targets,
            recentLog: logs.last
        )
        return record
    }

    private func makeTargetWorks(settings: OffloadSettings) -> [TargetWork] {
        settings.targetRoots.flatMap { root in
            settings.normalizedOutputPackageModes.map { mode in
                let outputURL = root.appendingPathComponent(settings.outputFolderName(for: mode), isDirectory: true)
                let manifest = Self.readResumeManifest(at: outputURL)

                // Clean up orphaned temp files from previous crashes
                if let enumerator = FileManager.default.enumerator(at: outputURL, includingPropertiesForKeys: nil) {
                    for case let url as URL in enumerator {
                        if url.lastPathComponent.hasPrefix(".321doit-copying-") {
                            try? FileManager.default.removeItem(at: url)
                        }
                    }
                }

                return TargetWork(
                    rootURL: root,
                    outputURL: outputURL,
                    packageMode: mode,
                    cardNumber: settings.cardNumber,
                    resumeManifest: manifest
                )
            }
        }
    }

    private func copyOneFile(
        _ sourceFile: SourceFile,
        targets: [TargetWork],
        totalFiles: Int,
        completedFiles: inout Int,
        totalBytes: UInt64,
        sourceBytesProcessed: inout UInt64,
        checksumAlgorithm: ChecksumAlgorithm,
        xxHash64Implementation: XXHash64Implementation,
        retryCount: Int,
        chunkSize: Int,
        enableSpeedLimit: Bool,
        speedLimitMBps: Int,
        strictResume: Bool,
        ioRetryCount: Int,
        startedAt: Date,
        language: AppLanguage,
        logs: inout [String],
        progress: @escaping OffloadProgressHandler
    ) async throws -> FileCopyRecord {
        func tr(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: language) }
        func appendLog(_ message: String) {
            logs.append("[\(Self.timeString(Date()))] \(message)")
        }

        let sourceHandle = try FileHandle(forReadingFrom: sourceFile.url)
        defer { try? sourceHandle.close() }
        // Don't pollute the buffer cache with gigabytes of source media; the
        // source hash is computed from the bytes we read regardless.
        _ = fcntl(sourceHandle.fileDescriptor, F_NOCACHE, 1)

        let sourceHasher = Checksum.makeSink(
            for: checksumAlgorithm,
            xxHash64Implementation: xxHash64Implementation
        )
        var openTargets: [OpenTargetFile] = []
        var targetResults: [FileTargetResult] = []
        var resumedSourceHash: String?

        defer {
            for openTarget in openTargets {
                try? openTarget.handle.close()
                try? fileManager.removeItem(at: openTarget.tempURL)
            }
        }

        for target in targets {
            guard target.isActive else {
                targetResults.append(FileTargetResult(
                    rootPath: target.rootURL.path,
                    outputPath: target.destinationURL(for: sourceFile).path,
                    copied: false,
                    verified: false,
                    hash: nil,
                    error: tr("目标此前失败，已跳过。", "Destination failed earlier; skipped.")
                ))
                continue
            }

            do {
                let finalURL = target.destinationURL(for: sourceFile)
                if let resumed = target.verifiedResumeRecord(for: sourceFile, strictResume: strictResume),
                   fileManager.fileExists(atPath: finalURL.path),
                   (try? fileSize(at: finalURL)) == sourceFile.size {

                    var shouldSkip = true
                    if strictResume {
                        // Strict resume re-validates both sides before trusting
                        // a session.json entry from a previous run.
                        do {
                            let sourceHash = try hashFileWithRetry(
                                at: sourceFile.url,
                                algorithm: checksumAlgorithm,
                                xxHash64Implementation: xxHash64Implementation,
                                chunkSize: chunkSize,
                                retryCount: retryCount
                            )
                            let targetHash = try hashFileWithRetry(
                                at: finalURL,
                                algorithm: checksumAlgorithm,
                                xxHash64Implementation: xxHash64Implementation,
                                chunkSize: chunkSize,
                                retryCount: retryCount,
                                bypassCache: true
                            )
                            if sourceHash != resumed.sourceHash || targetHash != resumed.targetHash {
                                shouldSkip = false
                            }
                        } catch let error as CancellationError {
                            throw error
                        } catch {
                            shouldSkip = false
                        }
                    }

                    if shouldSkip {
                        targetResults.append(FileTargetResult(
                            rootPath: target.rootURL.path,
                            outputPath: finalURL.path,
                            copied: true,
                            verified: true,
                            hash: resumed.targetHash,
                            error: nil
                        ))
                        resumedSourceHash = resumed.sourceHash
                        let hashMode = strictResume
                            ? tr("通过 Strict Re-hash", "via Strict Re-hash")
                            : tr("通过 Size/MTime", "via Size/MTime")
                        appendLog(tr(
                            "续传跳过已校验文件 (\(hashMode))：\(target.displayName) \(sourceFile.relativePath)",
                            "Resume skip verified file (\(hashMode)): \(target.displayName) \(sourceFile.relativePath)"
                        ))
                        continue
                    }
                }

                target.state = .copying
                target.recordStatus(sourceFile, sourceHash: "", targetHash: nil, status: .copying, errorMessage: nil)
                try target.writeResumeManifest()
                let tempURL = finalURL.deletingLastPathComponent()
                    .appendingPathComponent(".321doit-copying-\(UUID().uuidString)-\(finalURL.lastPathComponent)")
                try withIORetry(count: ioRetryCount) {
                    try fileManager.createDirectory(at: finalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                }
                try withIORetry(count: ioRetryCount) {
                    if !fileManager.createFile(atPath: tempURL.path, contents: nil) {
                        throw CocoaError(.fileWriteUnknown)
                    }
                }
                let handle = try withIORetry(count: ioRetryCount) {
                    try FileHandle(forWritingTo: tempURL)
                }
                openTargets.append(OpenTargetFile(target: target, finalURL: finalURL, tempURL: tempURL, handle: handle))
            } catch let error as CancellationError {
                throw error
            } catch {
                target.fail(tr("打开目标文件失败：\(sourceFile.relativePath) \(error.localizedDescription)",
                               "Failed to open destination file: \(sourceFile.relativePath) \(error.localizedDescription)"))
                target.recordStatus(sourceFile, sourceHash: "", targetHash: nil, status: .failed, errorMessage: target.error)
                try? target.writeResumeManifest()
                appendLog(tr("目标失败：\(target.displayName) \(sourceFile.relativePath)",
                             "Destination failed: \(target.displayName) \(sourceFile.relativePath)"))
                targetResults.append(FileTargetResult(
                    rootPath: target.rootURL.path,
                    outputPath: target.destinationURL(for: sourceFile).path,
                    copied: false,
                    verified: false,
                    hash: nil,
                    error: target.error
                ))
            }
        }

        if openTargets.isEmpty {
            if !targetResults.isEmpty, let sourceHash = resumedSourceHash {
                sourceBytesProcessed &+= sourceFile.size
                completedFiles += 1
                appendLog(tr("完成文件：\(sourceFile.relativePath)",
                             "File complete: \(sourceFile.relativePath)"))
                let record = FileCopyRecord(
                    relativePath: sourceFile.relativePath,
                    size: sourceFile.size,
                    modifiedAt: sourceFile.modifiedAt,
                    sourceHash: sourceHash,
                    targetResults: targetResults
                )
                try updateResumeManifests(for: record, targets: targets)
                try await publish(
                    progress,
                    message: tr("续传跳过 \(sourceFile.relativePath)",
                                "Resume skipped \(sourceFile.relativePath)"),
                    totalFiles: totalFiles,
                    completedFiles: completedFiles,
                    totalBytes: totalBytes,
                    copiedBytes: sourceBytesProcessed,
                    startedAt: startedAt,
                    targets: targets,
                    recentLog: logs.last
                )
                return record
            }
            throw OffloadError.allTargetsFailed
        }

        let speedLimitBytesPerSecond = enableSpeedLimit ? Double(max(1, speedLimitMBps)) * 1_000_000 : 0
        let copyStartedAt = Date()
        var copiedThisFile: UInt64 = 0
        var lastSpaceCheckChunk: UInt64 = 0
        let spaceCheckInterval: UInt64 = 128 * 1024 * 1024

        while true {
            try Task.checkCancellation()

#if DEBUG
            if let injectPath = OffloadEngine.testInjectErrorOnPath, sourceFile.relativePath.contains(injectPath) {
                OffloadEngine.testInjectErrorOnPath = nil
                throw CocoaError(.fileReadUnknown)
            }
#endif

            let data = try sourceHandle.read(upToCount: chunkSize) ?? Data()
            if data.isEmpty { break }
            let count = UInt64(data.count)
            sourceHasher.update(data)
            sourceBytesProcessed &+= count
            copiedThisFile &+= count

            var stillOpen: [OpenTargetFile] = []
            for openTarget in openTargets {
                guard openTarget.target.isActive else { continue }
                do {
                    try withIORetry(count: ioRetryCount) {
                        try openTarget.handle.write(contentsOf: data)
                    }
                    openTarget.target.copiedBytes &+= count
                    stillOpen.append(openTarget)
                } catch let error as CancellationError {
                    throw error
                } catch {
                    openTarget.target.fail(tr("写入失败：\(sourceFile.relativePath) \(error.localizedDescription)",
                                              "Write failed: \(sourceFile.relativePath) \(error.localizedDescription)"))
                    try? openTarget.handle.close()
                    try? fileManager.removeItem(at: openTarget.tempURL)
                    appendLog(tr("写入失败：\(openTarget.target.displayName) \(sourceFile.relativePath)",
                                 "Write failed: \(openTarget.target.displayName) \(sourceFile.relativePath)"))
                    targetResults.append(FileTargetResult(
                        rootPath: openTarget.target.rootURL.path,
                        outputPath: openTarget.finalURL.path,
                        copied: false,
                        verified: false,
                        hash: nil,
                        error: openTarget.target.error
                    ))
                }
            }
            openTargets = stillOpen

            if shouldPublishLoopProgress() {
                try await publish(
                    progress,
                    message: tr("正在拷贝 \(sourceFile.relativePath)",
                                "Copying \(sourceFile.relativePath)"),
                    totalFiles: totalFiles,
                    completedFiles: completedFiles,
                    totalBytes: totalBytes,
                    copiedBytes: sourceBytesProcessed,
                    startedAt: startedAt,
                    targets: targets,
                    recentLog: logs.last
                )
            }

            if openTargets.isEmpty {
                break
            }

            if copiedThisFile - lastSpaceCheckChunk >= spaceCheckInterval {
                lastSpaceCheckChunk = copiedThisFile
                for openTarget in openTargets where openTarget.target.isActive {
                    let remaining = availableCapacity(at: openTarget.target.rootURL)
                    if remaining > 0 && remaining < 1_073_741_824 {
                        appendLog(tr(
                            "⚠ 目标盘剩余空间不足 1 GB：\(openTarget.target.displayName)（剩余 \(formatBytes(remaining))）",
                            "⚠ Destination has less than 1 GB remaining: \(openTarget.target.displayName) (\(formatBytes(remaining)) left)"
                        ))
                    }
                }
            }

            if speedLimitBytesPerSecond > 0 {
                let expectedElapsed = Double(copiedThisFile) / speedLimitBytesPerSecond
                let actualElapsed = Date().timeIntervalSince(copyStartedAt)
                if expectedElapsed > actualElapsed {
                    let delay = expectedElapsed - actualElapsed
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        let sourceHash = sourceHasher.finalize()
        for openTarget in openTargets {
            // Force the written bytes all the way to physical media before we
            // verify — otherwise the read-back below would be served from the
            // buffer cache and a bad physical write would go undetected.
            _ = fcntl(openTarget.handle.fileDescriptor, F_FULLFSYNC)
            try? openTarget.handle.close()
            guard openTarget.target.isActive else { continue }
            openTarget.target.state = .verifying
            openTarget.target.recordStatus(sourceFile, sourceHash: sourceHash, targetHash: nil, status: .verifying, errorMessage: nil)
            try? openTarget.target.writeResumeManifest()

            do {
                let size = try fileSize(at: openTarget.tempURL)
                let hash = try hashFileWithRetry(
                    at: openTarget.tempURL,
                    algorithm: checksumAlgorithm,
                    xxHash64Implementation: xxHash64Implementation,
                    chunkSize: chunkSize,
                    retryCount: retryCount,
                    bypassCache: true
                )
                if size != sourceFile.size || hash != sourceHash {
                    openTarget.target.fail(tr("校验失败：\(sourceFile.relativePath)",
                                              "Verify failed: \(sourceFile.relativePath)"))
                    openTarget.target.recordStatus(sourceFile, sourceHash: sourceHash, targetHash: hash, status: .failed, errorMessage: openTarget.target.error)
                    try? openTarget.target.writeResumeManifest()
                    try? fileManager.removeItem(at: openTarget.tempURL)
                    appendLog(tr("校验失败：\(openTarget.target.displayName) \(sourceFile.relativePath)",
                                 "Verify failed: \(openTarget.target.displayName) \(sourceFile.relativePath)"))
                    targetResults.append(FileTargetResult(
                        rootPath: openTarget.target.rootURL.path,
                        outputPath: openTarget.finalURL.path,
                        copied: true,
                        verified: false,
                        hash: hash,
                        error: openTarget.target.error
                    ))
                    continue
                }

                if fileManager.fileExists(atPath: openTarget.finalURL.path) {
                    try withIORetry(count: ioRetryCount) {
                        try fileManager.removeItem(at: openTarget.finalURL)
                    }
                }
                try withIORetry(count: ioRetryCount) {
                    try fileManager.moveItem(at: openTarget.tempURL, to: openTarget.finalURL)
                }
                try withIORetry(count: ioRetryCount) {
                    try fileManager.setAttributes([.modificationDate: sourceFile.modifiedAt], ofItemAtPath: openTarget.finalURL.path)
                }
                openTarget.target.verifiedBytes &+= sourceFile.size
                openTarget.target.recordVerifiedFile(sourceFile, sourceHash: sourceHash, targetHash: hash)
                // Forced per file (by design, enforced by EngineSmokeTests): each
                // verified file's state is durably journaled before moving on, so a
                // crash never costs resume rework. This re-encodes the whole
                // manifest each time — fine for camera media (large files, low
                // count). A high-file-count card would want an append-only journal
                // instead (a manifest-format change + test update), not a weaker
                // crash-safety guarantee.
                try withIORetry(count: ioRetryCount) {
                    try openTarget.target.writeResumeManifest(force: true)
                }
                targetResults.append(FileTargetResult(
                    rootPath: openTarget.target.rootURL.path,
                    outputPath: openTarget.finalURL.path,
                    copied: true,
                    verified: true,
                    hash: hash,
                    error: nil
                ))
            } catch let error as CancellationError {
                throw error
            } catch {
                openTarget.target.fail(tr("校验或落盘失败：\(sourceFile.relativePath) \(error.localizedDescription)",
                                          "Verify or finalize failed: \(sourceFile.relativePath) \(error.localizedDescription)"))
                openTarget.target.recordStatus(sourceFile, sourceHash: sourceHash, targetHash: nil, status: .failed, errorMessage: openTarget.target.error)
                try? openTarget.target.writeResumeManifest()
                try? fileManager.removeItem(at: openTarget.tempURL)
                appendLog(tr("目标失败：\(openTarget.target.displayName) \(sourceFile.relativePath)",
                             "Destination failed: \(openTarget.target.displayName) \(sourceFile.relativePath)"))
                targetResults.append(FileTargetResult(
                    rootPath: openTarget.target.rootURL.path,
                    outputPath: openTarget.finalURL.path,
                    copied: true,
                    verified: false,
                    hash: nil,
                    error: openTarget.target.error
                ))
            }
        }
        
        // Clear open targets so the defer block doesn't delete them.
        openTargets.removeAll()

        completedFiles += 1
        appendLog(tr("完成文件：\(sourceFile.relativePath)",
                     "File complete: \(sourceFile.relativePath)"))
        let record = FileCopyRecord(
            relativePath: sourceFile.relativePath,
            size: sourceFile.size,
            modifiedAt: sourceFile.modifiedAt,
            sourceHash: sourceHash,
            targetResults: targetResults
        )
        try updateResumeManifests(for: record, targets: targets)
        try await publish(
            progress,
            message: tr("完成 \(sourceFile.relativePath)",
                        "Done \(sourceFile.relativePath)"),
            totalFiles: totalFiles,
            completedFiles: completedFiles,
            totalBytes: totalBytes,
            copiedBytes: sourceBytesProcessed,
            startedAt: startedAt,
            targets: targets,
            recentLog: logs.last
        )

        return record
    }

    private func updateResumeManifests(for record: FileCopyRecord, targets: [TargetWork]) throws {
        for target in targets {
            let expectedPath = target.destinationURL(for: record).path
            let matching = record.targetResults.first { $0.outputPath == expectedPath }
            guard let matching, matching.verified, let targetHash = matching.hash else { continue }
            target.recordVerifiedFile(record, targetHash: targetHash)
            try target.writeResumeManifest()
        }
    }

    private func fileSize(at url: URL) throws -> UInt64 {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        return UInt64(values.fileSize ?? 0)
    }

    private func hashFileWithRetry(
        at url: URL,
        algorithm: ChecksumAlgorithm,
        xxHash64Implementation: XXHash64Implementation,
        chunkSize: Int,
        retryCount: Int,
        bypassCache: Bool = false
    ) throws -> String {
        var lastError: Error?
        for attempt in 0...max(0, retryCount) {
            do {
                try Task.checkCancellation()
                return try Checksum.hashFile(
                    at: url,
                    algorithm: algorithm,
                    xxHash64Implementation: xxHash64Implementation,
                    chunkSize: chunkSize,
                    bypassCache: bypassCache
                )
            } catch let error as CancellationError {
                throw error
            } catch {
                lastError = error
                if attempt < retryCount {
                    Thread.sleep(forTimeInterval: min(0.5, 0.1 * Double(attempt + 1)))
                }
            }
        }
        throw lastError ?? CocoaError(.fileReadUnknown)
    }

    private func withIORetry<T>(count: Int, operation: () throws -> T) throws -> T {
        let retryCount = max(0, count)
        var lastError: Error?
        for attempt in 0...retryCount {
            do {
                try Task.checkCancellation()
                return try operation()
            } catch let error as CancellationError {
                throw error
            } catch {
                lastError = error
                if attempt < retryCount {
                    Thread.sleep(forTimeInterval: min(0.5, 0.1 * Double(attempt + 1)))
                }
            }
        }
        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    private func publish(
        _ handler: OffloadProgressHandler,
        message: String,
        totalFiles: Int,
        completedFiles: Int,
        totalBytes: UInt64,
        copiedBytes: UInt64,
        startedAt: Date?,
        targets: [TargetWork],
        recentLog: String?
    ) async throws {
        let snapshot = OffloadSnapshot(
            message: message,
            totalFiles: totalFiles,
            completedFiles: completedFiles,
            totalBytes: totalBytes,
            copiedBytes: copiedBytes,
            startedAt: startedAt,
            targets: targets.map { $0.progress },
            recentLog: recentLog
        )
        await handler(snapshot)
    }

    private static func timeString(_ date: Date) -> String {
        timeFormatterLock.lock()
        defer { timeFormatterLock.unlock() }
        return timeFormatter.string(from: date)
    }

    private static let timeFormatterLock = NSLock()
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static func normalizedChunkSize(copyBufferKB: Int) -> Int {
        max(64, min(8192, copyBufferKB)) * 1024
    }

    private static let fat32SingleFileLimit: UInt64 = 4_294_967_295

    private static func filesystemName(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey]) else { return nil }
        return values.volumeLocalizedFormatDescription
    }

    private static func isLikelyFAT32(_ filesystemName: String) -> Bool {
        let lower = filesystemName.lowercased()
        if lower.contains("exfat") { return false }
        return lower.contains("fat32") || lower.contains("ms-dos") || lower.contains("msdos")
    }

    private static func writeAuditLog(
        outputURL: URL,
        settings: OffloadSettings,
        startedAt: Date,
        endedAt: Date,
        files: [FileCopyRecord],
        target: TargetReport,
        logs: [String]
    ) {
        let dir = OffloadPackageLayout.workflowRoot(outputURL: outputURL)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("audit.json")

        var fileEntries: [[String: Any]] = []
        for file in files {
            let matchingResult = file.targetResults.first { $0.outputPath.contains(outputURL.path) }
            var entry: [String: Any] = [
                "relativePath": file.relativePath,
                "sizeBytes": file.size,
                "sourceHash": file.sourceHash,
                "algorithm": settings.checksumAlgorithm.displayName
            ]
            if let result = matchingResult {
                entry["targetHash"] = result.hash ?? NSNull()
                entry["copied"] = result.copied
                entry["verified"] = result.verified
                if let error = result.error { entry["error"] = error }
            }
            fileEntries.append(entry)
        }

        let verifiedCount = files.filter { file in
            file.targetResults.contains { $0.outputPath.contains(outputURL.path) && $0.verified }
        }.count
        let failedCount = files.filter { file in
            file.targetResults.contains { $0.outputPath.contains(outputURL.path) && !$0.verified }
        }.count

        let audit: [String: Any] = [
            "schema": "321doit-audit-v1",
            "environment": [
                "app": appName,
                "version": appVersionString,
                "build": appBuildNumberString,
                "os": "macOS \(osVersionDisplay())",
                "hostname": ProcessInfo.processInfo.hostName,
                "user": NSUserName()
            ] as [String: Any],
            "task": [
                "project": settings.projectName,
                "card": settings.cardNumber,
                "operator": settings.operatorName,
                "camera": settings.camera,
                "source": settings.sourceURL.path,
                "destination": target.rootURL.path,
                "outputFolder": outputURL.path,
                "checksumAlgorithm": settings.checksumAlgorithm.displayName,
                "strictResume": settings.strictResume,
                "verifyOnly": settings.verifyOnly,
                "resumed": settings.resumedFromJournal
            ] as [String: Any],
            "timing": [
                "startedAt": iso8601String(startedAt),
                "endedAt": iso8601String(endedAt),
                "durationSeconds": Int(endedAt.timeIntervalSince(startedAt))
            ] as [String: Any],
            "summary": [
                "totalFiles": files.count,
                "totalBytes": files.reduce(UInt64(0)) { $0 + $1.size },
                "verifiedFiles": verifiedCount,
                "failedFiles": failedCount,
                "targetState": target.state.rawValue,
                "copiedBytes": target.copiedBytes,
                "verifiedBytes": target.verifiedBytes
            ] as [String: Any],
            "files": fileEntries
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: audit, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private static func hasResumeManifest(at outputURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: resumeManifestURL(for: outputURL).path)
        || FileManager.default.fileExists(atPath: legacyResumeManifestURL(for: outputURL).path)
    }

    private static func readResumeManifest(at outputURL: URL) -> ResumeManifest? {
        let url = resumeManifestURL(for: outputURL)
        let legacyURL = legacyResumeManifestURL(for: outputURL)
        guard let data = (try? Data(contentsOf: url)) ?? (try? Data(contentsOf: legacyURL)) else { return nil }
        return try? JSONDecoder().decode(ResumeManifest.self, from: data)
    }

    private static func resumeManifestURL(for outputURL: URL) -> URL {
        OffloadPackageLayout.workflowRoot(outputURL: outputURL)
            .appendingPathComponent("session.json")
    }

    private static func legacyResumeManifestURL(for outputURL: URL) -> URL {
        let alternateDirectory = OffloadPackageLayout.isLegacyLayout(outputURL: outputURL)
            ? ".321doit"
            : "_321Doit"
        return outputURL
            .appendingPathComponent(alternateDirectory, isDirectory: true)
            .appendingPathComponent("session.json")
    }
}

private final class TargetWork {
    let id = UUID()
    let rootURL: URL
    let outputURL: URL
    let packageMode: OffloadPackageMode
    let cardNumber: String
    var state: TargetState = .pending
    var copiedBytes: UInt64 = 0
    var verifiedBytes: UInt64 = 0
    var transcodeProgress: Double?
    var error: String?
    var isActive = true
    var resumeManifest: ResumeManifest
    let wasResumedFromManifest: Bool

    init(rootURL: URL, outputURL: URL, packageMode: OffloadPackageMode, cardNumber: String, resumeManifest: ResumeManifest?) {
        self.rootURL = rootURL
        self.outputURL = outputURL
        self.packageMode = packageMode
        self.cardNumber = cardNumber
        self.wasResumedFromManifest = !(resumeManifest?.files.isEmpty ?? true)
        self.resumeManifest = resumeManifest ?? ResumeManifest(
            appName: appName,
            appVersion: appVersionString,
            outputPath: outputURL.path,
            files: [:],
            updatedAt: iso8601String(Date())
        )

        for record in self.resumeManifest.files.values where record.isVerified {
            let finalURL = OffloadPackageLayout.originalFileURL(
                outputURL: outputURL,
                mode: packageMode,
                cardNumber: cardNumber,
                relativePath: record.relativePath
            )
            let values = try? finalURL.resourceValues(forKeys: [.fileSizeKey])
            let size = UInt64(values?.fileSize ?? 0)
            if FileManager.default.fileExists(atPath: finalURL.path), size == record.size {
                copiedBytes &+= record.size
                verifiedBytes &+= record.size
            }
        }
    }

    var displayName: String {
        let rootName = rootURL.lastPathComponent.isEmpty ? rootURL.path : rootURL.lastPathComponent
        return "\(rootName) · \(packageMode.folderSuffix)"
    }

    var progress: TargetProgress {
        TargetProgress(
            id: id,
            rootURL: rootURL,
            outputURL: outputURL,
            packageMode: packageMode,
            state: state,
            copiedBytes: copiedBytes,
            verifiedBytes: verifiedBytes,
            transcodeProgress: transcodeProgress,
            error: error
        )
    }

    func fail(_ message: String) {
        state = .failed
        error = message
        isActive = false
        try? writeResumeManifest(force: true)
    }

    func destinationURL(for sourceFile: SourceFile) -> URL {
        OffloadPackageLayout.originalFileURL(
            outputURL: outputURL,
            mode: packageMode,
            cardNumber: cardNumber,
            relativePath: sourceFile.relativePath
        )
    }

    func destinationURL(for record: FileCopyRecord) -> URL {
        OffloadPackageLayout.originalFileURL(
            outputURL: outputURL,
            mode: packageMode,
            cardNumber: cardNumber,
            relativePath: record.relativePath
        )
    }

    func verifiedResumeRecord(for sourceFile: SourceFile, strictResume: Bool) -> ResumeFileRecord? {
        guard let record = resumeManifest.files[sourceFile.relativePath],
              record.isVerified,
              record.size == sourceFile.size
        else { return nil }
        
        if !strictResume {
            guard abs(record.modifiedAt - sourceFile.modifiedAt.timeIntervalSince1970) < 1.0 else { return nil }
        }
        
        return record
    }

    func recordStatus(
        _ sourceFile: SourceFile,
        sourceHash: String,
        targetHash: String?,
        status: ResumeFileStatus,
        errorMessage: String?
    ) {
        resumeManifest.files[sourceFile.relativePath] = ResumeFileRecord(
            relativePath: sourceFile.relativePath,
            size: sourceFile.size,
            modifiedAt: sourceFile.modifiedAt.timeIntervalSince1970,
            sourceHash: sourceHash,
            targetHash: targetHash,
            status: status,
            verified: status == .verified,
            errorMessage: errorMessage,
            updatedAt: iso8601String(Date())
        )
        resumeManifest.updatedAt = iso8601String(Date())
    }

    func recordVerifiedFile(_ sourceFile: SourceFile, sourceHash: String, targetHash: String) {
        recordStatus(
            sourceFile,
            sourceHash: sourceHash,
            targetHash: targetHash,
            status: .verified,
            errorMessage: nil
        )
    }

    func recordVerifiedFile(_ record: FileCopyRecord, targetHash: String) {
        resumeManifest.files[record.relativePath] = ResumeFileRecord(
            relativePath: record.relativePath,
            size: record.size,
            modifiedAt: record.modifiedAt.timeIntervalSince1970,
            sourceHash: record.sourceHash,
            targetHash: targetHash,
            status: .verified,
            verified: true,
            errorMessage: nil,
            updatedAt: iso8601String(Date())
        )
        resumeManifest.updatedAt = iso8601String(Date())
    }

    private var lastManifestWriteTime: Date = .distantPast

    func writeResumeManifest(force: Bool = false) throws {
    #if DEBUG
        OffloadEngine.attemptedManifestWriteSpy?(force)
    #endif
        let now = Date()
        if !force && now.timeIntervalSince(lastManifestWriteTime) < 1.0 {
            return
        }
        lastManifestWriteTime = now

    #if DEBUG
        OffloadEngine.actualManifestWriteSpy?(force)
    #endif

        let dir = OffloadPackageLayout.workflowRoot(outputURL: outputURL)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("session.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(resumeManifest)
        try data.write(to: url, options: [.atomic])
    }
}

private struct OpenTargetFile {
    let target: TargetWork
    let finalURL: URL
    let tempURL: URL
    let handle: FileHandle
}

private struct ResumeManifest: Codable {
    var appName: String
    var appVersion: String
    var outputPath: String
    var files: [String: ResumeFileRecord]
    var updatedAt: String
}

private enum ResumeFileStatus: String, Codable {
    case pending
    case copying
    case copied
    case verifying
    case verified
    case failed
}

private struct ResumeFileRecord: Codable {
    var relativePath: String
    var size: UInt64
    var modifiedAt: TimeInterval
    var sourceHash: String
    var targetHash: String?
    var status: ResumeFileStatus
    var verified: Bool
    var errorMessage: String?
    var updatedAt: String

    var isVerified: Bool {
        verified || status == .verified
    }

    private enum CodingKeys: String, CodingKey {
        case relativePath
        case size
        case modifiedAt
        case sourceHash
        case targetHash
        case status
        case verified
        case errorMessage
        case updatedAt
    }

    init(
        relativePath: String,
        size: UInt64,
        modifiedAt: TimeInterval,
        sourceHash: String,
        targetHash: String?,
        status: ResumeFileStatus,
        verified: Bool,
        errorMessage: String?,
        updatedAt: String
    ) {
        self.relativePath = relativePath
        self.size = size
        self.modifiedAt = modifiedAt
        self.sourceHash = sourceHash
        self.targetHash = targetHash
        self.status = status
        self.verified = verified
        self.errorMessage = errorMessage
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        size = try container.decode(UInt64.self, forKey: .size)
        modifiedAt = try container.decode(TimeInterval.self, forKey: .modifiedAt)
        sourceHash = try container.decodeIfPresent(String.self, forKey: .sourceHash) ?? ""
        targetHash = try container.decodeIfPresent(String.self, forKey: .targetHash)
        verified = try container.decodeIfPresent(Bool.self, forKey: .verified) ?? false
        status = try container.decodeIfPresent(ResumeFileStatus.self, forKey: .status) ?? (verified ? .verified : .pending)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? iso8601String(Date())
    }
}

final class SleepAssertion {
    private var assertionID: IOPMAssertionID = 0
    private var active = false

    init(reason: String) {
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        active = result == kIOReturnSuccess
    }

    func release() {
        guard active else { return }
        IOPMAssertionRelease(assertionID)
        active = false
    }

    deinit {
        release()
    }
}
