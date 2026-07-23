import Foundation

struct MediaConversionEngine {
    let language: AppLanguage
    let configuredFFmpegPath: String

    func convert(
        sourceURL: URL,
        probed: ProbedMedia,
        mode: MediaConversionMode,
        target: MediaContainer,
        transcodeSettings: MediaTranscodeSettings = .default,
        destinationDirectory: URL,
        progress: @escaping @Sendable (MediaConversionProgress) -> Void
    ) async throws -> MediaConversionOutput {
        guard let ffmpegURL = FFmpegLocator.executableURL(configuredPath: configuredFFmpegPath) else {
            throw MediaConversionError.dependencyMissing
        }
        try validateDestination(destinationDirectory, sourceSize: probed.sizeBytes)

        let finalURL = uniqueOutputURL(
            sourceURL: sourceURL,
            destinationDirectory: destinationDirectory,
            target: target
        )
        let tempURL = destinationDirectory.appendingPathComponent(
            ".\(finalURL.deletingPathExtension().lastPathComponent).321doit-partial-\(UUID().uuidString).\(target.fileExtension)"
        )
        let encoderCapabilities = await availableEncoders(of: ffmpegURL)
        let arguments = try makeArguments(
            sourceURL: sourceURL,
            outputURL: tempURL,
            probed: probed,
            mode: mode,
            target: target,
            transcodeSettings: transcodeSettings,
            encoderCapabilities: encoderCapabilities
        )
        let startedAt = Date()
        let ffmpegVersion = await version(of: ffmpegURL)
        let parser = ProgressParser(duration: probed.durationSeconds, callback: progress)

        do {
            let result = try await MediaProcessRunner.run(
                executableURL: ffmpegURL,
                arguments: arguments,
                stderrChunk: { parser.consume($0) }
            )
            guard result.terminationStatus == 0 else {
                throw EngineFailure(message: Self.conciseError(result.stderrText))
            }
            guard FileManager.default.fileExists(atPath: tempURL.path) else {
                throw EngineFailure(message: "ffmpeg completed without creating an output file")
            }
            progress(MediaConversionProgress(fraction: 1, processedSeconds: probed.durationSeconds ?? 0, speed: ""))
            return MediaConversionOutput(
                temporaryURL: tempURL,
                finalURL: finalURL,
                ffmpegArguments: arguments,
                startedAt: startedAt,
                completedAt: Date(),
                ffmpegVersion: ffmpegVersion
            )
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: tempURL)
            throw MediaConversionError.cancelled
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    private func version(of executableURL: URL) async -> String {
        guard let result = try? await MediaProcessRunner.run(executableURL: executableURL, arguments: ["-version"]),
              result.terminationStatus == 0 else { return "unknown" }
        return result.stdoutText.split(separator: "\n").first.map(String.init) ?? "unknown"
    }

    private func availableEncoders(of executableURL: URL) async -> Set<String> {
        guard let result = try? await MediaProcessRunner.run(
            executableURL: executableURL,
            arguments: ["-hide_banner", "-encoders"]
        ), result.terminationStatus == 0 else { return [] }
        let text = result.stdoutText + "\n" + result.stderrText
        return Set(text.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    /// Makes a verified temporary output visible. This is deliberately a
    /// separate operation so callers cannot publish an unverified file.
    func commitVerifiedOutput(_ output: MediaConversionOutput) throws -> URL {
        guard FileManager.default.fileExists(atPath: output.temporaryURL.path) else {
            throw MediaConversionError.conversionFailed
        }
        guard !FileManager.default.fileExists(atPath: output.finalURL.path) else {
            throw MediaConversionError.outputExists
        }
        try FileManager.default.moveItem(at: output.temporaryURL, to: output.finalURL)
        return output.finalURL
    }

    func discardTemporaryOutput(_ output: MediaConversionOutput) {
        try? FileManager.default.removeItem(at: output.temporaryURL)
    }

    private func validateDestination(_ directory: URL, sourceSize: Int64) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              FileManager.default.isWritableFile(atPath: directory.path) else {
            throw MediaConversionError.targetNotWritable
        }
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values?.volumeAvailableCapacityForImportantUsage,
           available > 0,
           sourceSize > 0,
           available < sourceSize + max(512 * 1024 * 1024, sourceSize / 20) {
            throw MediaConversionError.insufficientSpace
        }
    }

    private func uniqueOutputURL(sourceURL: URL, destinationDirectory: URL, target: MediaContainer) -> URL {
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        var candidate = destinationDirectory.appendingPathComponent("\(stem).\(target.fileExtension)")
        var suffix = 1
        while FileManager.default.fileExists(atPath: candidate.path) || candidate.standardizedFileURL == sourceURL.standardizedFileURL {
            candidate = destinationDirectory.appendingPathComponent("\(stem)_\(suffix).\(target.fileExtension)")
            suffix += 1
        }
        return candidate
    }

    private func makeArguments(
        sourceURL: URL,
        outputURL: URL,
        probed: ProbedMedia,
        mode: MediaConversionMode,
        target: MediaContainer,
        transcodeSettings: MediaTranscodeSettings,
        encoderCapabilities: Set<String>
    ) throws -> [String] {
        var args = ["-hide_banner", "-nostdin", "-v", "warning", "-progress", "pipe:2", "-nostats", "-n", "-i", sourceURL.path]
        switch mode {
        case .rewrap:
            args += [
                "-map", "0:v?",
                "-map", "0:a?",
                "-map", "0:s?"
            ]
            if target == .mov || target == .mp4 {
                for stream in probed.dataStreams where stream.isQuickTimeTimecode {
                    args += ["-map", "0:\(stream.index)?"]
                }
            }
            args += ["-map_metadata", "0", "-map_chapters", "0", "-c", "copy"]
        case .transcode:
            args += ["-map", "0:v:0", "-map_metadata", "0", "-map_chapters", "0"]
            if transcodeSettings.audioCodec != .none, !probed.audioStreams.isEmpty {
                args += ["-map", "0:a?"]
            }
            let videoEncoder = try resolvedVideoEncoder(
                for: transcodeSettings.videoCodec,
                available: encoderCapabilities
            )
            args += ["-sn", "-dn", "-c:v", videoEncoder]
            args += videoEncodingArguments(transcodeSettings, target: target, encoder: videoEncoder)
            if let targetHeight = transcodeSettings.scale.targetHeight {
                args += ["-vf", "scale=-2:\(targetHeight):force_original_aspect_ratio=decrease"]
            }
            if let fps = transcodeSettings.frameRate.ffmpegValue {
                args += ["-r", fps]
            }
            switch transcodeSettings.audioCodec {
            case .aac:
                args += ["-c:a", "aac", "-b:a", "256k"]
            case .opus:
                args += ["-c:a", encoderCapabilities.contains("libopus") ? "libopus" : "opus", "-b:a", "192k"]
            case .pcm:
                args += ["-c:a", "pcm_s24le"]
            case .copy:
                args += ["-c:a", "copy"]
            case .none:
                args += ["-an"]
            }
            if target == .mp4 || target == .mov {
                args += ["-movflags", "+faststart"]
            }
        case .losslessAudio:
            args += ["-map", "0:a:0", "-vn", "-sn", "-dn", "-map_metadata", "0", "-map_chapters", "-1"]
            args += ["-c:a", losslessCodec(for: probed.audioStreams[0], target: target)]
        }
        args += ["-f", muxerName(target), outputURL.path]
        return args
    }

    private func resolvedVideoEncoder(
        for codec: MediaVideoCodec,
        available: Set<String>
    ) throws -> String {
        let candidates: [String]
        switch codec {
        case .h264: candidates = ["libx264", "h264_videotoolbox"]
        case .h265: candidates = ["libx265", "hevc_videotoolbox"]
        case .prores422, .prores422HQ: candidates = ["prores_ks", "prores_videotoolbox", "prores"]
        case .av1: candidates = ["libaom-av1", "libsvtav1", "av1_videotoolbox"]
        case .vp9: candidates = ["libvpx-vp9"]
        case .mpeg2: candidates = ["mpeg2video"]
        case .dnxhrHQX: candidates = ["dnxhd"]
        }
        if let encoder = candidates.first(where: available.contains) { return encoder }
        // Some custom FFmpeg builds omit the encoder table. Preserve the
        // normal encoder name and let FFmpeg return its own diagnostic.
        if available.isEmpty { return codec.ffmpegEncoder }
        throw EngineFailure(message: "当前 FFmpeg 未包含 \(codec.displayName) 编码器。请在设置中选择完整版本的 FFmpeg，或改用当前可用的编码格式。")
    }

    private func videoEncodingArguments(
        _ settings: MediaTranscodeSettings,
        target: MediaContainer,
        encoder: String
    ) -> [String] {
        switch settings.videoCodec {
        case .h264:
            if encoder == "h264_videotoolbox" {
                return ["-q:v", videoToolboxQuality(settings.quality), "-allow_sw", "1", "-pix_fmt", "yuv420p"]
            }
            return [
                "-preset", encoderPreset(settings.quality),
                "-crf", crf(settings.quality, codec: .h264),
                "-pix_fmt", "yuv420p"
            ]
        case .h265:
            if encoder == "hevc_videotoolbox" {
                var arguments = ["-q:v", videoToolboxQuality(settings.quality), "-allow_sw", "1", "-pix_fmt", "yuv420p10le"]
                if target == .mp4 || target == .mov { arguments += ["-tag:v", "hvc1"] }
                return arguments
            }
            var arguments = [
                "-preset", encoderPreset(settings.quality),
                "-crf", crf(settings.quality, codec: .h265),
                "-pix_fmt", "yuv420p10le"
            ]
            if target == .mp4 || target == .mov { arguments += ["-tag:v", "hvc1"] }
            return arguments
        case .prores422:
            return ["-profile:v", encoder == "prores_videotoolbox" ? "standard" : "2", "-pix_fmt", "yuv422p10le"]
        case .prores422HQ:
            return ["-profile:v", encoder == "prores_videotoolbox" ? "hq" : "3", "-pix_fmt", "yuv422p10le"]
        case .av1:
            return [
                "-crf", crf(settings.quality, codec: .av1),
                "-b:v", "0",
                "-cpu-used", settings.quality == .compact ? "6" : (settings.quality == .balanced ? "5" : "4"),
                "-pix_fmt", "yuv420p10le"
            ]
        case .vp9:
            return [
                "-crf", crf(settings.quality, codec: .vp9),
                "-b:v", "0",
                "-row-mt", "1",
                "-pix_fmt", "yuv420p"
            ]
        case .mpeg2:
            let quality: String
            switch settings.quality {
            case .compact: quality = "6"
            case .balanced: quality = "4"
            case .high: quality = "2"
            case .master: quality = "1"
            }
            return ["-q:v", quality, "-pix_fmt", "yuv420p"]
        case .dnxhrHQX:
            return ["-profile:v", "dnxhr_hqx", "-pix_fmt", "yuv422p10le"]
        }
    }

    private func videoToolboxQuality(_ quality: MediaTranscodeQuality) -> String {
        switch quality {
        case .compact: return "45"
        case .balanced: return "60"
        case .high: return "75"
        case .master: return "90"
        }
    }

    private func encoderPreset(_ quality: MediaTranscodeQuality) -> String {
        switch quality {
        case .compact: return "medium"
        case .balanced: return "medium"
        case .high: return "slow"
        case .master: return "slower"
        }
    }

    private func crf(_ quality: MediaTranscodeQuality, codec: MediaVideoCodec) -> String {
        switch codec {
        case .h264:
            switch quality { case .compact: return "25"; case .balanced: return "21"; case .high: return "18"; case .master: return "15" }
        case .h265:
            switch quality { case .compact: return "29"; case .balanced: return "25"; case .high: return "20"; case .master: return "17" }
        case .av1:
            switch quality { case .compact: return "38"; case .balanced: return "32"; case .high: return "26"; case .master: return "20" }
        case .vp9:
            switch quality { case .compact: return "38"; case .balanced: return "32"; case .high: return "26"; case .master: return "20" }
        case .prores422, .prores422HQ, .mpeg2, .dnxhrHQX:
            return "0"
        }
    }

    private func muxerName(_ target: MediaContainer) -> String {
        switch target {
        case .mov: return "mov"
        case .mp4: return "mp4"
        case .mkv: return "matroska"
        case .webm: return "webm"
        case .avi: return "avi"
        case .mpegts: return "mpegts"
        case .mxf: return "mxf"
        case .wav: return "wav"
        case .aiff: return "aiff"
        case .flac: return "flac"
        case .m4a: return "ipod"
        }
    }

    private func losslessCodec(for stream: ProbedStream, target: MediaContainer) -> String {
        if target == .flac { return "flac" }
        if target == .m4a { return "alac" }

        let floating = stream.codecName.lowercased().hasPrefix("pcm_f")
            || stream.sampleFmt.lowercased().hasPrefix("flt")
            || stream.sampleFmt.lowercased().hasPrefix("dbl")
        let depth = Int(stream.bitDepth) ?? inferredDepth(stream.sampleFmt)
        if floating {
            let bits = depth > 32 ? 64 : 32
            return "pcm_f\(bits)\(target == .aiff ? "be" : "le")"
        }
        if depth <= 8 { return "pcm_u8" }
        let bits = depth <= 16 ? 16 : (depth <= 24 ? 24 : 32)
        return "pcm_s\(bits)\(target == .aiff ? "be" : "le")"
    }

    private func inferredDepth(_ sampleFormat: String) -> Int {
        let value = sampleFormat.lowercased()
        if value.contains("64") || value.hasPrefix("dbl") { return 64 }
        if value.contains("32") || value.hasPrefix("flt") { return 32 }
        if value.contains("16") { return 16 }
        if value.contains("8") { return 8 }
        return 24
    }

    private static func conciseError(_ text: String) -> String {
        text.split(separator: "\n").suffix(8).joined(separator: "\n")
    }
}

struct EngineFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

private final class ProgressParser: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private var speed = ""
    private let duration: Double?
    private let callback: @Sendable (MediaConversionProgress) -> Void

    init(duration: Double?, callback: @escaping @Sendable (MediaConversionProgress) -> Void) {
        self.duration = duration
        self.callback = callback
    }

    func consume(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        lock.lock()
        pending += text
        let lines = pending.split(separator: "\n", omittingEmptySubsequences: false)
        pending = String(lines.last ?? "")
        for raw in lines.dropLast() {
            let line = String(raw)
            if line.hasPrefix("speed=") { speed = String(line.dropFirst(6)) }
            guard line.hasPrefix("out_time_us=") || line.hasPrefix("out_time_ms=") else { continue }
            let rawValue = line.split(separator: "=", maxSplits: 1).last.flatMap { Double($0) } ?? 0
            let seconds = rawValue / 1_000_000
            let fraction = duration.map { min(max(seconds / max($0, 0.001), 0), 0.99) } ?? 0
            callback(MediaConversionProgress(fraction: fraction, processedSeconds: seconds, speed: speed))
        }
        lock.unlock()
    }
}
