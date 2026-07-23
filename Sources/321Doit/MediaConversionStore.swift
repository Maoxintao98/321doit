import Foundation
import SwiftUI

struct MediaConversionQueueItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var sourceURL: URL
    var state: MediaConversionTaskState = .waiting
    var progress = MediaConversionProgress(fraction: 0, processedSeconds: 0, speed: "")
    var probed: ProbedMedia?
    var compatibility: CompatibilityResult?
    var outputURL: URL?
    var reportURL: URL?
    var errorText: String?
}

@MainActor
final class MediaConversionStore: ObservableObject {
    @Published var items: [MediaConversionQueueItem] = []
    @Published var mode: MediaConversionMode = .rewrap
    @Published var target: MediaContainer = .mov
    @Published var transcodeSettings: MediaTranscodeSettings = .default
    @Published var destinationURL: URL?
    @Published var isRunning = false
    @Published var bannerMessage: String?

    private var runningTask: Task<Void, Never>?
    private let persistenceKey = "mediaConversionQueue.v1"
    private let compatibilityRevisionKey = "mediaConversionCompatibilityRevision"
    private let currentCompatibilityRevision = 3

    init() {
        restoreQueue()
    }

    var runnableCount: Int {
        items.filter { ($0.state == .ready || $0.state == .warning) && $0.outputURL == nil }.count
    }

    func add(urls: [URL], language: AppLanguage, configuredFFmpegPath: String) {
        let expanded = expand(urls: urls)
        let existing = Set(items.map { $0.sourceURL.standardizedFileURL })
        let additions = expanded
            .filter { !existing.contains($0.standardizedFileURL) }
            .map { MediaConversionQueueItem(sourceURL: $0) }
        guard !additions.isEmpty else { return }
        items.append(contentsOf: additions)
        if destinationURL == nil { destinationURL = additions[0].sourceURL.deletingLastPathComponent() }
        persistQueue()
        analyzePending(language: language, configuredFFmpegPath: configuredFFmpegPath)
    }

    func reanalyze(language: AppLanguage, configuredFFmpegPath: String) {
        for index in items.indices where ![.analyzing, .converting, .verifying, .completed].contains(items[index].state)
            && items[index].outputURL == nil {
            if let probe = items[index].probed {
                applyCompatibility(probe, at: index, language: language)
            } else {
                items[index].state = .waiting
            }
        }
        persistQueue()
        analyzePending(language: language, configuredFFmpegPath: configuredFFmpegPath)
    }

    func retryAnalysis(_ id: UUID, language: AppLanguage, configuredFFmpegPath: String) {
        guard !isRunning, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].probed = nil
        items[index].compatibility = nil
        items[index].errorText = nil
        items[index].state = .waiting
        persistQueue()
        analyzePending(language: language, configuredFFmpegPath: configuredFFmpegPath)
    }

    func remove(_ id: UUID) {
        guard !isRunning else { return }
        items.removeAll { $0.id == id }
        persistQueue()
    }

    func clearFinished() {
        guard !isRunning else { return }
        items.removeAll {
            [.completed, .failed, .cancelled, .interrupted].contains($0.state)
                || ($0.state == .warning && $0.outputURL != nil)
        }
        persistQueue()
    }

    func cancelCurrent() {
        runningTask?.cancel()
    }

    func run(
        language: AppLanguage,
        configuredFFmpegPath: String,
        projectContext: ToolProjectContext?
    ) {
        guard !isRunning, let destinationURL else { return }
        isRunning = true
        bannerMessage = nil
        runningTask = Task { [weak self] in
            guard let self else { return }
            await self.runQueue(
                language: language,
                configuredFFmpegPath: configuredFFmpegPath,
                destinationURL: destinationURL,
                projectContext: projectContext
            )
            self.isRunning = false
            self.runningTask = nil
            self.persistQueue()
        }
    }

    private func analyzePending(language: AppLanguage, configuredFFmpegPath: String) {
        let pendingIDs = items.filter { $0.state == .waiting || $0.state == .interrupted }.map(\.id)
        guard !pendingIDs.isEmpty else { return }
        for id in pendingIDs {
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index].state = .analyzing
            }
        }
        Task { [weak self] in
            guard let self else { return }
            let service = MediaProbeService(language: language)
            for id in pendingIDs {
                guard let index = self.items.firstIndex(where: { $0.id == id }) else { continue }
                let url = self.items[index].sourceURL
                let result = await Task.detached(priority: .userInitiated) {
                    service.probeSync(url: url, configuredFFmpegPath: configuredFFmpegPath)
                }.value
                guard let currentIndex = self.items.firstIndex(where: { $0.id == id }) else { continue }
                switch result {
                case .success(let probe):
                    self.items[currentIndex].probed = probe
                    self.applyCompatibility(probe, at: currentIndex, language: language)
                case .failure(let error):
                    self.items[currentIndex].state = .failed
                    self.items[currentIndex].errorText = error.message(language: language)
                }
            }
            self.persistQueue()
        }
    }

    private func applyCompatibility(_ probe: ProbedMedia, at index: Int, language: AppLanguage) {
        let result = MediaCompatibilityService(language: language).decide(
            probed: probe,
            mode: mode,
            target: target,
            transcode: transcodeSettings
        )
        items[index].compatibility = result
        items[index].errorText = result.verdict == .incompatible
            ? result.risks.first(where: { $0.severity == .blocking })?.message(language: language)
            : nil
        items[index].state = result.verdict == .incompatible ? .failed
            : (result.verdict == .compatibleWithWarnings ? .warning : .ready)
    }

    private func runQueue(
        language: AppLanguage,
        configuredFFmpegPath: String,
        destinationURL: URL,
        projectContext: ToolProjectContext?
    ) async {
        let engine = MediaConversionEngine(language: language, configuredFFmpegPath: configuredFFmpegPath)
        let verifier = MediaVerificationService(language: language, configuredFFmpegPath: configuredFFmpegPath)
        let taskIDs = items.filter { ($0.state == .ready || $0.state == .warning) && $0.outputURL == nil }.map(\.id)

        AppLogger.log(.info, category: "conversion", "Queue started; tasks=\(taskIDs.count); mode=\(mode.rawValue); target=\(target.rawValue)")

        for id in taskIDs {
            if Task.isCancelled { markCancelled(id); break }
            guard let index = items.firstIndex(where: { $0.id == id }),
                  let probe = items[index].probed,
                  let compatibility = items[index].compatibility else { continue }
            items[index].state = .converting
            items[index].progress = MediaConversionProgress(fraction: 0, processedSeconds: 0, speed: "")
            persistQueue()
            var staged: MediaConversionOutput?
            do {
                let output = try await engine.convert(
                    sourceURL: items[index].sourceURL,
                    probed: probe,
                    mode: mode,
                    target: target,
                    transcodeSettings: transcodeSettings,
                    destinationDirectory: destinationURL,
                    progress: { [weak self] update in
                        Task { @MainActor in
                            guard let self, let current = self.items.firstIndex(where: { $0.id == id }) else { return }
                            self.items[current].progress = update
                        }
                    }
                )
                staged = output
                guard let current = items.firstIndex(where: { $0.id == id }) else {
                    engine.discardTemporaryOutput(output)
                    continue
                }
                items[current].state = .verifying
                let (temporaryProbe, verification) = try await verifier.verify(
                    source: probe,
                    outputURL: output.temporaryURL,
                    mode: mode,
                    transcodeSettings: transcodeSettings
                )
                guard verification.passed else {
                    engine.discardTemporaryOutput(output)
                    items[current].state = .failed
                    items[current].errorText = verification.messages.joined(separator: " · ")
                    AppLogger.log(.error, category: "conversion", "Task \(id.uuidString.lowercased()) verification failed: \(verification.messages.joined(separator: " · "))")
                    continue
                }

                let finalURL = try engine.commitVerifiedOutput(output)
                staged = nil
                items[current].outputURL = finalURL
                let finalProbe = relocated(temporaryProbe, to: finalURL)
                let report = MediaConversionReport(
                    schema: "com.321doit.media-conversion-result",
                    schemaVersion: 1,
                    taskID: id,
                    createdAt: Date(),
                    startedAt: output.startedAt,
                    endedAt: Date(),
                    appVersion: Self.appVersion,
                    ffmpegVersion: output.ffmpegVersion,
                    projectAssociationMode: projectContext == nil ? "independent" : "linkedProject",
                    linkedProjectID: projectContext?.projectID,
                    sourcePath: probe.url.path,
                    outputPath: finalURL.path,
                    sourceSizeBytes: probe.sizeBytes,
                    outputSizeBytes: finalProbe.sizeBytes,
                    mode: mode,
                    targetContainer: target,
                    transcodeSettings: mode == .transcode ? transcodeSettings : nil,
                    projectContext: projectContext,
                    ffmpegArguments: output.ffmpegArguments,
                    sourceProbe: probe,
                    outputProbe: finalProbe,
                    compatibility: compatibility,
                    reencodesVideo: compatibility.reencodesVideo,
                    reencodesAudio: compatibility.reencodesAudio,
                    verification: verification,
                    warnings: compatibility.risks.filter { $0.severity != .blocking },
                    errors: []
                )
                do {
                    items[current].reportURL = try MediaConversionReportWriter.write(
                        report,
                        beside: finalURL,
                        linkedProjectFolderURL: projectContext?.projectFolderURL
                    )
                    items[current].state = compatibility.risks.contains(where: { $0.severity == .warning })
                        || verification.hasMetadataWarnings ? .warning : .completed
                    AppLogger.log(.info, category: "conversion", "Task \(id.uuidString.lowercased()) completed; output=\(finalURL.lastPathComponent)")
                } catch {
                    items[current].state = .warning
                    items[current].errorText = MediaConversionError.reportFailed.message(language: language)
                    AppLogger.log(.warning, category: "conversion", "Task \(id.uuidString.lowercased()) output verified but report failed")
                }
            } catch {
                if let staged { engine.discardTemporaryOutput(staged) }
                guard let current = items.firstIndex(where: { $0.id == id }) else { continue }
                if Task.isCancelled || (error as? MediaConversionError) == .cancelled {
                    items[current].state = .cancelled
                    items[current].errorText = MediaConversionError.cancelled.message(language: language)
                    AppLogger.log(.warning, category: "conversion", "Task \(id.uuidString.lowercased()) cancelled")
                    break
                }
                items[current].state = .failed
                if let typed = error as? MediaConversionError {
                    items[current].errorText = typed.message(language: language)
                } else {
                    items[current].errorText = error.localizedDescription
                }
                AppLogger.log(.error, category: "conversion", "Task \(id.uuidString.lowercased()) failed: \(error.localizedDescription)")
            }
            persistQueue()
        }
    }

    private func markCancelled(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = .cancelled
    }

    private func expand(urls: [URL]) -> [URL] {
        let supported = Set(["mov", "mp4", "m4v", "mkv", "mts", "m2ts", "ts", "mxf", "wav", "wave", "aif", "aiff", "flac", "m4a"])
        var result: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
                while let file = enumerator?.nextObject() as? URL {
                    let values = try? file.resourceValues(forKeys: Set(keys))
                    if values?.isRegularFile == true, supported.contains(file.pathExtension.lowercased()) { result.append(file) }
                }
            } else if supported.contains(url.pathExtension.lowercased()) {
                result.append(url)
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func relocated(_ media: ProbedMedia, to url: URL) -> ProbedMedia {
        let format = ProbedFormat(
            formatName: media.format.formatName,
            formatLongName: media.format.formatLongName,
            filename: url.path,
            nbStreams: media.format.nbStreams,
            duration: media.format.duration,
            startTime: media.format.startTime,
            size: media.format.size,
            bitRate: media.format.bitRate,
            tags: media.format.tags
        )
        return ProbedMedia(url: url, format: format, streams: media.streams, chapters: media.chapters)
    }

    private func persistQueue() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: persistenceKey)
        } catch {
            AppLogger.log(.error, category: "media-conversion", "Could not persist conversion queue: \(error.localizedDescription)")
        }
    }

    private func restoreQueue() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey) else { return }
        var saved: [MediaConversionQueueItem]
        do {
            saved = try JSONDecoder().decode([MediaConversionQueueItem].self, from: data)
        } catch {
            UserDefaults.standard.removeObject(forKey: persistenceKey)
            AppLogger.log(.warning, category: "media-conversion", "Discarded unreadable conversion queue: \(error.localizedDescription)")
            return
        }
        let needsCompatibilityRefresh =
            UserDefaults.standard.integer(forKey: compatibilityRevisionKey) < currentCompatibilityRevision
        for index in saved.indices where [.analyzing, .converting, .verifying].contains(saved[index].state) {
            saved[index].state = .interrupted
            saved[index].errorText = nil
        }
        if needsCompatibilityRefresh {
            for index in saved.indices where saved[index].outputURL == nil {
                saved[index].compatibility = nil
                saved[index].errorText = nil
                saved[index].state = .waiting
            }
            UserDefaults.standard.set(currentCompatibilityRevision, forKey: compatibilityRevisionKey)
        }
        items = saved.filter { FileManager.default.fileExists(atPath: $0.sourceURL.path) }
        if needsCompatibilityRefresh {
            persistQueue()
        }
    }

    private static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }
}
