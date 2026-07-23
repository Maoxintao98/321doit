import Foundation
import Darwin

/// Probes media files with ffprobe and parses the JSON into ``ProbedMedia``.
///
/// All ffprobe invocations use ``Process.arguments`` (never `sh -c` or string
/// concatenation) and parse the JSON output — never human-readable console text.
/// UI callers should use the async ``probe``; tests use ``probeSync``.
struct MediaProbeService {
    private static let probeTimeout: TimeInterval = 8
    let language: AppLanguage

    /// Resolve an ffprobe URL next to the configured/auto-detected ffmpeg.
    /// Reuses ``FFmpegLocator`` so the user's configured path and search
    /// strategy are honored consistently with the rest of the app.
    func ffprobeURL(configuredFFmpegPath: String?) -> URL? {
        let ffmpeg = FFmpegLocator.executableURL(configuredPath: configuredFFmpegPath)
        if let ffmpeg {
            let candidate = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        // Fallback to common locations on PATH.
        let candidates = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/opt/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Whether ffprobe (given the configured ffmpeg path) is available.
    func isAvailable(configuredFFmpegPath: String?) -> Bool {
        ffprobeURL(configuredFFmpegPath: configuredFFmpegPath) != nil
    }

    /// Asynchronous probe. The completion is dispatched on the main queue so
    /// SwiftUI callers can update state safely.
    func probe(
        url: URL,
        configuredFFmpegPath: String?,
        completion: @escaping (Result<ProbedMedia, MediaConversionError>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = probeSync(url: url, configuredFFmpegPath: configuredFFmpegPath)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Synchronous probe for tests and non-UI callers. Never blocks the UI
    /// thread indirectly; callers must dispatch to a background queue.
    func probeSync(
        url: URL,
        configuredFFmpegPath: String?
    ) -> Result<ProbedMedia, MediaConversionError> {
        guard let ffprobe = ffprobeURL(configuredFFmpegPath: configuredFFmpegPath) else {
            return .failure(.dependencyMissing)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.probeFailed)
        }

        let process = Process()
        process.executableURL = ffprobe
        // Arguments only — never shell concatenation. The path is passed as
        // a single argv element so spaces / unicode / leading dashes are safe.
        process.arguments = [
            "-v", "error",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            "-show_chapters",
            url.path
        ]

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let processFinished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            processFinished.signal()
        }

        do {
            try process.run()
        } catch {
            return .failure(.probeFailed)
        }
        // Drain stdout and stderr concurrently. Reading stderr to EOF before
        // stdout can deadlock when a large ffprobe JSON payload fills the
        // stdout pipe while the process is still holding stderr open.
        let drainGroup = DispatchGroup()
        var outData = Data()
        var errData = Data()
        drainGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            drainGroup.leave()
        }
        drainGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            drainGroup.leave()
        }
        let didTimeOut = processFinished.wait(timeout: .now() + Self.probeTimeout) == .timedOut
        if didTimeOut, process.isRunning {
            process.terminate()
            if processFinished.wait(timeout: .now() + 1) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = processFinished.wait(timeout: .now() + 1)
            }
        }
        process.waitUntilExit()
        drainGroup.wait()

        if didTimeOut {
            return .failure(.probeTimedOut)
        }

        guard process.terminationStatus == 0, !outData.isEmpty else {
            let errText = String(data: errData, encoding: .utf8) ?? ""
            _ = errText // surfaced via probeFailed code; not in normal logs
            return .failure(.probeFailed)
        }

        guard let parsed = parse(outData, url: url) else {
            return .failure(.probeFailed)
        }
        return .success(parsed)
    }

    /// Parse ffprobe JSON bytes into ``ProbedMedia``. Pure and testable.
    func parse(_ data: Data, url: URL) -> ProbedMedia? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let formatDict = (root["format"] as? [String: Any]) ?? [:]
        let streamsRaw = (root["streams"] as? [[String: Any]]) ?? []
        let chaptersRaw = (root["chapters"] as? [[String: Any]]) ?? []
        let format = ProbedFormat.from(formatDict)
        let streams = streamsRaw.map { ProbedStream.from($0) }.sorted { $0.index < $1.index }
        let chapters = chaptersRaw.map { ProbedChapter.from($0) }
        return ProbedMedia(url: url, format: format, streams: streams, chapters: chapters)
    }
}
