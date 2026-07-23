@preconcurrency import AVFoundation
import Foundation
import AppKit

struct ProxyTranscodeResult: Equatable {
    var proxyURL: URL
    var created: Int
    var errors: [String]
}

// AVFoundation reader/writer instances are reference types driven by serial
// requestMediaDataWhenReady queues. The box only moves those references across
// queue closures; it does not make arbitrary values thread-safe.
private final class UnsafeSendableBox<Value: AnyObject>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private struct BurnInRenderContext {
    var fileName: String
    var projectName: String
    var cardNumber: String
    var camera: String
    var shootDay: String
}

enum ProxyTranscoder {
    static let proxyFolderName = "02_PROXIES"

    private static let standardVideoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "mxf", "avi", "mkv",
        "mts", "m2ts", "ts", "vob", "wmv", "flv", "webm",
        "3gp", "3g2", "asf", "f4v"
    ]

    private static let rawVideoExtensions: Set<String> = [
        "r3d",      // RED
        "braw",     // Blackmagic RAW
        "ari",      // ARRIRAW
        "arx",
        "arri",
        "rmf",      // Canon RMF
        "crm",      // Canon Cinema RAW Light
        "mlv",      // Magic Lantern RAW Video
        "nev",      // Nikon RAW Video
        "ndr",
        "dng"       // CinemaDNG sequence
    ]

    static func shouldAttemptProxy(for relativePath: String, attemptRaw: Bool) -> Bool {
        let ext = URL(fileURLWithPath: relativePath).pathExtension.lowercased()
        if standardVideoExtensions.contains(ext) { return true }
        if attemptRaw && rawVideoExtensions.contains(ext) { return true }
        return false
    }

    private static func verifiedTargetURL(for file: FileCopyRecord, target: TargetReport) -> URL? {
        file.targetResults.first {
            $0.verified && $0.outputPath.hasPrefix(target.outputURL.path)
        }.map { URL(fileURLWithPath: $0.outputPath) }
    }

    private static func burnInContext(
        enabled: Bool,
        file: FileCopyRecord,
        sourceURL: URL,
        offload: OffloadSettings?
    ) -> BurnInRenderContext? {
        guard enabled else { return nil }
        let handoff = offload?.handoff ?? .init()
        return BurnInRenderContext(
            fileName: sourceURL.lastPathComponent,
            projectName: offload?.projectName ?? "",
            cardNumber: offload?.cardNumber ?? "",
            camera: offload?.camera ?? "",
            shootDay: HandoffManifestBuilder.effectiveShootDay(
                handoff: handoff,
                fallback: offload?.cardNumber ?? ""
            )
        )
    }

    static func transcodeVerifiedFiles(
        files: [FileCopyRecord],
        target: TargetReport,
        profile: TranscodeProfile = .default,
        offload: OffloadSettings? = nil,
        progress: ((String, Double) async -> Void)? = nil
    ) async throws -> ProxyTranscodeResult {
        let lutRequested = profile.lutMode == .applyLUT || profile.lutMode == .cleanAndLUT
        let primaryKind: ProxyOutputKind = lutRequested ? .lutBaked : .standard
        let proxyRoot = OffloadPackageLayout.proxyRoot(outputURL: target.outputURL, profile: profile, kind: primaryKind)
        var created = 0
        var errors: [String] = []

        let validFiles = files.filter { file in
            shouldAttemptProxy(for: file.relativePath, attemptRaw: profile.attemptRaw)
            && file.targetResults.contains(where: { $0.outputPath.hasPrefix(target.outputURL.path) && $0.verified })
        }
        
        let total = validFiles.count
        var processed = 0

        for file in validFiles {
            try Task.checkCancellation()
            guard let sourceURL = verifiedTargetURL(for: file, target: target) else {
                errors.append("\(file.relativePath): verified target file is missing")
                processed += 1
                continue
            }
            let outputURL = proxyRoot.appendingPathComponent(proxyRelativePath(for: file.relativePath, profile: profile, kind: primaryKind))

            let usingLUT: Bool
            if lutRequested {
                do {
                    try validateLUTPath(profile.lutPath)
                    usingLUT = true
                } catch {
                    errors.append("\(file.relativePath) [LUT]: \(error.localizedDescription)")
                    processed += 1
                    continue
                }
            } else {
                usingLUT = false
            }

            do {
                if let progress {
                    let lutTag = usingLUT ? " + LUT" : ""
                    await progress("\(profile.codec.shortLabel)\(lutTag) transcoding: \(file.relativePath)", Double(processed) / Double(max(1, total)))
                }
                try await transcodeOne(
                    sourceURL: sourceURL,
                    outputURL: outputURL,
                    profile: profile,
                    applyingLUT: usingLUT,
                    burnInContext: burnInContext(
                        enabled: profile.burnIn.enabled && profile.burnIn.target == .proxyTranscode,
                        file: file,
                        sourceURL: sourceURL,
                        offload: offload
                    )
                )
                created += 1

                // Optional clean copy alongside the LUT'd file.
                if usingLUT && profile.lutMode == .cleanAndLUT {
                    let cleanURL = OffloadPackageLayout.proxyRoot(outputURL: target.outputURL, profile: profile, kind: .clean)
                        .appendingPathComponent(proxyRelativePath(for: file.relativePath, profile: profile, kind: .clean))
                    do {
                        try await transcodeOne(
                            sourceURL: sourceURL,
                            outputURL: cleanURL,
                            profile: profile,
                            applyingLUT: false,
                            burnInContext: nil
                        )
                        created += 1
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        errors.append("\(file.relativePath) [clean]: \(error.localizedDescription)")
                    }
                }

                if profile.burnIn.enabled && profile.burnIn.target == .reviewCopy {
                    let burnURL = OffloadPackageLayout.proxyRoot(outputURL: target.outputURL, profile: profile, kind: .burnIn)
                        .appendingPathComponent(proxyRelativePath(for: file.relativePath, profile: profile, kind: .burnIn))
                    do {
                        try await transcodeOne(
                            sourceURL: sourceURL,
                            outputURL: burnURL,
                            profile: profile,
                            applyingLUT: usingLUT,
                            burnInContext: burnInContext(enabled: true, file: file, sourceURL: sourceURL, offload: offload)
                        )
                        created += 1
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        errors.append("\(file.relativePath) [burn-in]: \(error.localizedDescription)")
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                errors.append("\(file.relativePath): \(error.localizedDescription)")
            }

            processed += 1
            if let progress {
                await progress("Done: \(file.relativePath)", Double(processed) / Double(max(1, total)))
            }
        }

        return ProxyTranscodeResult(proxyURL: proxyRoot, created: created, errors: errors)
    }

    static func extractFrames(
        files: [FileCopyRecord],
        target: TargetReport,
        profile: TranscodeProfile,
        progress: ((String, Double) async -> Void)? = nil
    ) async throws -> ProxyTranscodeResult {
        let frameSettings = profile.frameExtraction
        guard frameSettings.enabled, frameSettings.framesPerVideo > 0 else {
            return ProxyTranscodeResult(proxyURL: target.outputURL, created: 0, errors: [])
        }

        let framesRoot = OffloadPackageLayout.thumbnailsRoot(outputURL: target.outputURL)
        var created = 0
        var errors: [String] = []

        let validFiles = files.filter { file in
            shouldAttemptProxy(for: file.relativePath, attemptRaw: profile.attemptRaw)
            && file.targetResults.contains(where: { $0.outputPath.hasPrefix(target.outputURL.path) && $0.verified })
        }
        
        let total = validFiles.count * frameSettings.framesPerVideo
        var processed = 0

        for file in validFiles {
            try Task.checkCancellation()
            guard let sourceURL = verifiedTargetURL(for: file, target: target) else {
                errors.append("\(file.relativePath): verified target file is missing")
                continue
            }
            let asset = AVURLAsset(url: sourceURL)
            let durationSeconds: Double
            do {
                durationSeconds = try await asset.load(.duration).seconds
            } catch {
                errors.append("\(file.relativePath): could not read video duration")
                continue
            }

            guard durationSeconds > 0 else {
                errors.append("\(file.relativePath): invalid video duration")
                continue
            }

            for k in 0..<frameSettings.framesPerVideo {
                let timePoint = durationSeconds * (Double(k) + 0.5) / Double(frameSettings.framesPerVideo)
                let stem = sourceURL.deletingPathExtension().lastPathComponent
                let frameFileName = String(format: "%@_frame%02d.jpg", stem, k + 1)
                
                let relativeDir = URL(fileURLWithPath: file.relativePath).deletingLastPathComponent().relativePath
                let outDir = relativeDir == "." ? framesRoot : framesRoot.appendingPathComponent(relativeDir, isDirectory: true)
                let outputURL = outDir.appendingPathComponent(frameFileName)

                let usingLUT: Bool
                if frameSettings.applyLUT, profile.lutPath?.isEmpty == false {
                    do {
                        try validateLUTPath(profile.lutPath)
                        usingLUT = true
                    } catch {
                        errors.append("\(frameFileName) [LUT]: \(error.localizedDescription)")
                        processed += 1
                        continue
                    }
                } else {
                    usingLUT = false
                }

                do {
                    if let progress {
                        await progress("Extracting still: \(frameFileName)", Double(processed) / Double(max(1, total)))
                    }
                    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
                    
                    if let ffmpegURL = findFFmpeg(profile: profile) {
                        var args: [String] = [
                            "-y", "-hide_banner", "-loglevel", "error",
                            "-ss", String(format: "%.3f", timePoint),
                            "-i", sourceURL.path,
                            "-vframes", "1",
                            "-q:v", "2"
                        ]
                        var videoFilters: [String] = []
                        if usingLUT, let lutPath = profile.lutPath, !lutPath.isEmpty {
                            videoFilters.append(lut3dFilter(path: lutPath, intensity: profile.lutIntensity))
                        }
                        if !videoFilters.isEmpty {
                            args += ["-vf", videoFilters.joined(separator: ",")]
                        }
                        args.append(outputURL.path)
                        
                        let process = Process()
                        process.executableURL = ffmpegURL
                        process.arguments = args
                        try await runFFmpegProcessCancellable(process)
                        try Task.checkCancellation()
                        if process.terminationStatus == 0 {
                            created += 1
                        } else {
                            throw ProxyError.failed("FFmpeg frame extraction failed")
                        }
                    } else {
                        // Fallback to AVFoundation if ffmpeg not found or no LUT requested
                        if usingLUT {
                            throw ProxyError.failed("Applying LUT during frame extraction requires ffmpeg")
                        }
                        let generator = AVAssetImageGenerator(asset: asset)
                        generator.appliesPreferredTrackTransform = true
                        generator.requestedTimeToleranceBefore = .zero
                        generator.requestedTimeToleranceAfter = .zero
                        let cmTime = CMTime(seconds: timePoint, preferredTimescale: 600)
                        let cgImage = try await generator.image(at: cmTime).image
                        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                        if let tiffData = nsImage.tiffRepresentation,
                           let bitmap = NSBitmapImageRep(data: tiffData),
                           let jpegData = bitmap.representation(using: .jpeg, properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 0.85]) {
                            try jpegData.write(to: outputURL)
                            created += 1
                        } else {
                            throw ProxyError.failed("Could not encode JPEG data")
                        }
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    errors.append("\(frameFileName): \(error.localizedDescription)")
                }
                processed += 1
            }
        }
        return ProxyTranscodeResult(proxyURL: framesRoot, created: created, errors: errors)
    }

    static func proxyRelativePath(
        for relativePath: String,
        profile: TranscodeProfile = .default,
        kind: ProxyOutputKind = .standard
    ) -> String {
        let url = URL(fileURLWithPath: relativePath)
        let directory = url.deletingLastPathComponent().relativePath
        let stem = url.deletingPathExtension().lastPathComponent
        let suffix: String
        switch kind {
        case .standard:
            suffix = profile.codec.fileSuffix
        case .lutBaked:
            suffix = "_proxy_lut"
        case .clean:
            suffix = "_proxy_clean"
        case .burnIn:
            suffix = "_proxy_burnin"
        }
        let fileName = "\(stem)\(suffix).\(profile.codec.fileExtension)"
        if directory == "." || directory == "/" || directory.isEmpty {
            return fileName
        }
        return "\(directory)/\(fileName)"
    }

    private static func transcodeOne(
        sourceURL: URL,
        outputURL: URL,
        profile: TranscodeProfile,
        applyingLUT: Bool,
        burnInContext: BurnInRenderContext?
    ) async throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let ffmpegURL = findFFmpeg(profile: profile)

        if profile.enableHardwareAcceleration,
           profile.codec.isProRes,
           profile.codec != .prores4444XQ,
           !applyingLUT,
           burnInContext == nil,
           profile.scale == .original {
            do {
                try await transcodeProResWithAVAssetWriter(
                    sourceURL: sourceURL,
                    outputURL: outputURL,
                    profile: profile
                )
                return
            } catch is CancellationError {
                // A cancellation is not an AVAssetWriter failure — propagate it
                // instead of falling back to a fresh ffmpeg encode.
                throw CancellationError()
            } catch {
                if let ffmpegURL {
                    // Fallback to FFmpeg if AVAssetWriter fails
                    try await transcodeWithFFmpeg(
                        ffmpegURL: ffmpegURL,
                        sourceURL: sourceURL,
                        outputURL: outputURL,
                        profile: profile,
                        applyingLUT: applyingLUT,
                        burnInContext: burnInContext
                    )
                    return
                } else {
                    throw error
                }
            }
        }

        if let ffmpegURL {
            try await transcodeWithFFmpeg(
                ffmpegURL: ffmpegURL,
                sourceURL: sourceURL,
                outputURL: outputURL,
                profile: profile,
                applyingLUT: applyingLUT,
                burnInContext: burnInContext
            )
            return
        }

        if applyingLUT {
            // AVFoundation can't apply 3D LUTs, so be explicit.
            throw ProxyError.failed("LUT transcode requires ffmpeg, but ffmpeg was not found: \(sourceURL.lastPathComponent)")
        }
        if burnInContext != nil {
            throw ProxyError.failed("Burn-in overlay requires ffmpeg, but ffmpeg was not found: \(sourceURL.lastPathComponent)")
        }

        try await transcodeWithAVFoundation(sourceURL: sourceURL, outputURL: outputURL, profile: profile)
    }

    // MARK: - AVFoundation fallback

    private static func transcodeProResWithAVAssetWriter(
        sourceURL: URL,
        outputURL: URL,
        profile: TranscodeProfile
    ) async throws {
        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProxyError.unsupported(sourceURL.lastPathComponent)
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)

        let tempURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".321doit-prores-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let reader = try AVAssetReader(asset: asset)
        let writer = try AVAssetWriter(outputURL: tempURL, fileType: .mov)

        let readerVideoOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_422YpCbCr8
            ]
        )
        readerVideoOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerVideoOutput) else {
            throw ProxyError.unsupported(sourceURL.lastPathComponent)
        }
        reader.add(readerVideoOutput)

        var dimensions = naturalSize.applying(preferredTransform)
        dimensions.width = abs(dimensions.width)
        dimensions.height = abs(dimensions.height)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: proResCodecType(for: profile.codec),
            AVVideoWidthKey: max(2, Int(dimensions.width.rounded())),
            AVVideoHeightKey: max(2, Int(dimensions.height.rounded()))
        ]
        let writerVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerVideoInput.expectsMediaDataInRealTime = false
        writerVideoInput.transform = preferredTransform
        guard writer.canAdd(writerVideoInput) else {
            throw ProxyError.unsupported(sourceURL.lastPathComponent)
        }
        writer.add(writerVideoInput)

        var readerAudioOutput: AVAssetReaderTrackOutput?
        var writerAudioInput: AVAssetWriterInput?
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            audioOutput.alwaysCopiesSampleData = false
            if reader.canAdd(audioOutput) {
                reader.add(audioOutput)
                readerAudioOutput = audioOutput

                let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
                audioInput.expectsMediaDataInRealTime = false
                if writer.canAdd(audioInput) {
                    writer.add(audioInput)
                    writerAudioInput = audioInput
                }
            }
        }

        guard writer.startWriting(), reader.startReading() else {
            throw writer.error ?? reader.error ?? ProxyError.failed(sourceURL.lastPathComponent)
        }
        writer.startSession(atSourceTime: .zero)

        let readerBox = UnsafeSendableBox(reader)
        let writerBox = UnsafeSendableBox(writer)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let group = DispatchGroup()
                let videoQueue = DispatchQueue(label: "321doit.prores.video")
                let audioQueue = DispatchQueue(label: "321doit.prores.audio")
                let writerVideoInputBox = UnsafeSendableBox(writerVideoInput)
                let readerVideoOutputBox = UnsafeSendableBox(readerVideoOutput)

                group.enter()
                writerVideoInputBox.value.requestMediaDataWhenReady(on: videoQueue) {
                    let input = writerVideoInputBox.value
                    let output = readerVideoOutputBox.value
                    while input.isReadyForMoreMediaData {
                        guard let sample = output.copyNextSampleBuffer() else {
                            input.markAsFinished()
                            group.leave()
                            return
                        }
                        if !input.append(sample) {
                            input.markAsFinished()
                            group.leave()
                            return
                        }
                    }
                }

                if let readerAudioOutput, let writerAudioInput {
                    let readerAudioOutputBox = UnsafeSendableBox(readerAudioOutput)
                    let writerAudioInputBox = UnsafeSendableBox(writerAudioInput)
                    group.enter()
                    writerAudioInputBox.value.requestMediaDataWhenReady(on: audioQueue) {
                        let input = writerAudioInputBox.value
                        let output = readerAudioOutputBox.value
                        while input.isReadyForMoreMediaData {
                            guard let sample = output.copyNextSampleBuffer() else {
                                input.markAsFinished()
                                group.leave()
                                return
                            }
                            if !input.append(sample) {
                                input.markAsFinished()
                                group.leave()
                                return
                            }
                        }
                    }
                }

                group.notify(queue: .global(qos: .userInitiated)) {
                    let reader = readerBox.value
                    let writer = writerBox.value
                    // Cancelled mid-file: onCancel called reader.cancelReading(),
                    // which made the pump see end-of-stream. Tear down the writer
                    // and surface cancellation instead of finalizing a truncated
                    // proxy. cancelWriting() here is safe — the pump has stopped.
                    if reader.status == .cancelled {
                        writer.cancelWriting()
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    if reader.status == .failed || writer.status == .failed {
                        continuation.resume(throwing: writer.error ?? reader.error ?? ProxyError.failed(sourceURL.lastPathComponent))
                        return
                    }
                    writerBox.value.finishWriting {
                        let writer = writerBox.value
                        if writer.status == .completed {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: writer.error ?? ProxyError.failed(sourceURL.lastPathComponent))
                        }
                    }
                }
            }
        } onCancel: {
            // Safe to call from any thread; makes copyNextSampleBuffer() return
            // nil so the sample pump finishes and the group's notify block can
            // surface the cancellation.
            readerBox.value.cancelReading()
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: outputURL)
    }

    private static func proResCodecType(for codec: TranscodeCodec) -> AVVideoCodecType {
        switch codec {
        case .proresProxy: return .proRes422Proxy
        case .proresLT: return .proRes422LT
        case .prores422: return .proRes422
        case .prores422HQ: return .proRes422HQ
        case .prores4444: return .proRes4444
        case .prores4444XQ: return .proRes4444
        default: return .proRes422
        }
    }

    private static func transcodeWithAVFoundation(sourceURL: URL, outputURL: URL, profile: TranscodeProfile) async throws {
        if profile.codec == .h266 {
            throw ProxyError.unsupported("H.266 requires ffmpeg (libvvenc): \(sourceURL.lastPathComponent)")
        }

        let asset = AVURLAsset(url: sourceURL)
        let preset: String
        let outputType: AVFileType
        if profile.codec.isProRes {
            preset = AVAssetExportPresetAppleProRes422LPCM
            outputType = .mov
        } else if profile.codec == .h265 {
            preset = AVAssetExportPresetHEVCHighestQuality
            outputType = .mp4
        } else {
            preset = AVAssetExportPresetHighestQuality
            outputType = .mp4
        }

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ProxyError.unsupported(sourceURL.lastPathComponent)
        }

        let tempURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".321doit-proxy-\(UUID().uuidString).\(profile.codec.fileExtension)")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        session.outputURL = tempURL
        session.outputFileType = outputType
        session.shouldOptimizeForNetworkUse = false

        await withCheckedContinuation { continuation in
            session.exportAsynchronously {
                continuation.resume()
            }
        }

        switch session.status {
        case .completed:
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: outputURL)
            return
        case .failed:
            throw session.error ?? ProxyError.failed(sourceURL.lastPathComponent)
        case .cancelled:
            throw ProxyError.cancelled(sourceURL.lastPathComponent)
        default:
            throw ProxyError.failed(sourceURL.lastPathComponent)
        }
    }

    // MARK: - FFmpeg

    private static func findFFmpeg(profile: TranscodeProfile) -> URL? {
        FFmpegLocator.executableURL(configuredPath: profile.ffmpegPath)
    }

    private static func validateLUTPath(_ rawPath: String?) throws {
        guard let rawPath,
              !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyError.failed("LUT mode selected but no LUT file path is set")
        }
        guard FileManager.default.fileExists(atPath: rawPath) else {
            throw ProxyError.failed("LUT file does not exist: \(rawPath)")
        }
    }

    /// Runs an ffmpeg `Process` to completion as a cancellable async task. If the
    /// surrounding Task is cancelled, the process is sent SIGTERM so it stops
    /// promptly instead of running to completion as an orphan burning CPU. The
    /// caller should follow this with `try Task.checkCancellation()` to surface
    /// the cancellation rather than misreading the SIGTERM exit code as a failure.
    private static func runFFmpegProcessCancellable(_ process: Process) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
    }

    private static func transcodeWithFFmpeg(
        ffmpegURL: URL,
        sourceURL: URL,
        outputURL: URL,
        profile: TranscodeProfile,
        applyingLUT: Bool,
        burnInContext: BurnInRenderContext?
    ) async throws {
        let tempURL = outputURL.deletingLastPathComponent()
            .appendingPathComponent(".321doit-proxy-\(UUID().uuidString).\(profile.codec.fileExtension)")
        var burnInOverlayURL: URL?
        defer {
            try? FileManager.default.removeItem(at: tempURL)
            if let burnInOverlayURL {
                try? FileManager.default.removeItem(at: burnInOverlayURL)
            }
        }

        var args: [String] = [
            "-y",
            "-hide_banner",
            "-loglevel", "error",
            "-i", sourceURL.path
        ]

        var videoFilters: [String] = []
        if applyingLUT, let lutPath = profile.lutPath, !lutPath.isEmpty {
            videoFilters.append(lut3dFilter(path: lutPath, intensity: profile.lutIntensity))
        }
        if let scale = profile.scale.ffmpegFilter {
            videoFilters.append(scale)
        }
        if let burnInContext {
            if ffmpegSupportsFilter(ffmpegURL, named: "drawtext") {
                videoFilters.append(drawtextFilter(settings: profile.burnIn, context: burnInContext))
            } else {
                burnInOverlayURL = try makeBurnInOverlayImage(
                    settings: profile.burnIn,
                    context: burnInContext,
                    directory: outputURL.deletingLastPathComponent()
                )
                if let burnInOverlayURL {
                    args += ["-loop", "1", "-i", burnInOverlayURL.path]
                }
            }
        }

        if burnInOverlayURL != nil {
            let baseChain = videoFilters.isEmpty ? "null" : videoFilters.joined(separator: ",")
            let filterGraph = [
                "[0:v]\(baseChain)[vbase]",
                "[1:v]format=rgba[wm]",
                "[vbase][wm]overlay=\(overlayPositionFilter(for: profile.burnIn.position)):format=auto[vout]"
            ].joined(separator: ";")
            args += ["-filter_complex", filterGraph, "-map", "[vout]", "-map", "0:a?"]
        } else {
            args += ["-map", "0:v:0", "-map", "0:a?"]
        }
        if burnInOverlayURL == nil && !videoFilters.isEmpty {
            args += ["-vf", videoFilters.joined(separator: ",")]
        }

        args += ffmpegVideoArgs(for: profile)
        args += ffmpegAudioArgs(for: profile)
        args.append(tempURL.path)

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = args

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()
        try await runFFmpegProcessCancellable(process)
        // Surface a cancellation as such, rather than reporting the SIGTERM
        // exit code as a bogus "ffmpeg failed".
        try Task.checkCancellation()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = (stderr?.isEmpty == false ? stderr! : sourceURL.lastPathComponent)
            throw ProxyError.failed(detail)
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: outputURL)
    }

    private static func ffmpegVideoArgs(for profile: TranscodeProfile) -> [String] {
        switch profile.codec {
        case .proresProxy:
            return ["-c:v", "prores_ks", "-profile:v", "0", "-vendor", "apl0", "-pix_fmt", "yuv422p10le"]
        case .proresLT:
            return ["-c:v", "prores_ks", "-profile:v", "1", "-vendor", "apl0", "-pix_fmt", "yuv422p10le"]
        case .prores422:
            return ["-c:v", "prores_ks", "-profile:v", "2", "-vendor", "apl0", "-pix_fmt", "yuv422p10le"]
        case .prores422HQ:
            return ["-c:v", "prores_ks", "-profile:v", "3", "-vendor", "apl0", "-pix_fmt", "yuv422p10le"]
        case .prores4444:
            return ["-c:v", "prores_ks", "-profile:v", "4", "-vendor", "apl0", "-pix_fmt", "yuva444p10le"]
        case .prores4444XQ:
            return ["-c:v", "prores_ks", "-profile:v", "5", "-vendor", "apl0", "-pix_fmt", "yuva444p10le"]
        case .h264:
            var args: [String]
            if profile.enableHardwareAcceleration {
                args = [
                    "-c:v", "h264_videotoolbox",
                    "-allow_sw", "1",
                    "-profile:v", "high",
                    "-pix_fmt", "yuv420p",
                    "-movflags", "+faststart"
                ]
                args += videoToolboxRateControlArgs(quality: profile.quality, bitrate: profile.bitrate, codec: .h264)
            } else {
                args = ["-c:v", "libx264", "-preset", "medium", "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
                args += rateControlArgs(quality: profile.quality, bitrate: profile.bitrate, codec: .h264)
            }
            return args
        case .h265:
            var args: [String]
            if profile.enableHardwareAcceleration {
                args = [
                    "-c:v", "hevc_videotoolbox",
                    "-allow_sw", "1",
                    "-pix_fmt", "yuv420p10le",
                    "-tag:v", "hvc1",
                    "-movflags", "+faststart"
                ]
                args += videoToolboxRateControlArgs(quality: profile.quality, bitrate: profile.bitrate, codec: .h265)
            } else {
                args = ["-c:v", "libx265", "-preset", "medium", "-pix_fmt", "yuv420p10le", "-tag:v", "hvc1", "-movflags", "+faststart"]
                args += rateControlArgs(quality: profile.quality, bitrate: profile.bitrate, codec: .h265)
            }
            return args
        case .h266:
            var args = ["-c:v", "libvvenc", "-preset", "medium", "-pix_fmt", "yuv420p10le"]
            args += rateControlArgs(quality: profile.quality, bitrate: profile.bitrate, codec: .h266)
            return args
        }
    }

    private static func videoToolboxRateControlArgs(
        quality: TranscodeQuality,
        bitrate: TranscodeBitrate,
        codec: TranscodeCodec
    ) -> [String] {
        let mbps: Int
        if let configured = bitrate.mbps {
            mbps = configured
        } else {
            switch (codec, quality) {
            case (.h264, .low):    mbps = 8
            case (.h264, .medium): mbps = 16
            case (.h264, .high):   mbps = 35
            case (.h265, .low):    mbps = 6
            case (.h265, .medium): mbps = 12
            case (.h265, .high):   mbps = 28
            default:               mbps = 16
            }
        }

        return [
            "-b:v", "\(mbps)M",
            "-maxrate", "\(Int(Double(mbps) * 1.5))M",
            "-bufsize", "\(mbps * 2)M"
        ]
    }

    private static func rateControlArgs(
        quality: TranscodeQuality,
        bitrate: TranscodeBitrate,
        codec: TranscodeCodec
    ) -> [String] {
        if let mbps = bitrate.mbps {
            let target = "\(mbps)M"
            let maxRate = "\(Int(Double(mbps) * 1.5))M"
            let bufSize = "\(mbps * 2)M"
            switch codec {
            case .h266:
                return ["-b:v", target]
            default:
                return ["-b:v", target, "-maxrate", maxRate, "-bufsize", bufSize]
            }
        }
        switch codec {
        case .h264:
            switch quality {
            case .low:    return ["-crf", "28"]
            case .medium: return ["-crf", "23"]
            case .high:   return ["-crf", "18"]
            }
        case .h265:
            switch quality {
            case .low:    return ["-crf", "32"]
            case .medium: return ["-crf", "28"]
            case .high:   return ["-crf", "22"]
            }
        case .h266:
            switch quality {
            case .low:    return ["-qp", "40"]
            case .medium: return ["-qp", "32"]
            case .high:   return ["-qp", "24"]
            }
        default:
            return []
        }
    }

    private static func ffmpegAudioArgs(for profile: TranscodeProfile) -> [String] {
        if profile.codec.isProRes {
            return ["-c:a", "pcm_s16le"]
        }
        return ["-c:a", "aac", "-b:a", "192k"]
    }

    private static func drawtextFilter(settings: BurnInSettings, context: BurnInRenderContext) -> String {
        let fields = settings.fields
        var parts: [String] = []
        if fields.fileName { parts.append(context.fileName) }
        if fields.timecode { parts.append("%{pts\\:hms}") }
        if fields.reelOrCard, !context.cardNumber.isEmpty { parts.append(context.cardNumber) }
        if fields.cameraID, !context.camera.isEmpty { parts.append(context.camera) }
        if fields.projectName, !context.projectName.isEmpty { parts.append(context.projectName) }
        if fields.shootDay, !context.shootDay.isEmpty { parts.append(context.shootDay) }
        if parts.isEmpty { parts.append(context.fileName) }

        let fontSize: Int
        switch settings.size {
        case .small: fontSize = 24
        case .medium: fontSize = 34
        case .large: fontSize = 48
        }

        let margin = max(18, fontSize / 2)
        let (x, y): (String, String)
        switch settings.position {
        case .topLeft:
            x = "\(margin)"; y = "\(margin)"
        case .topRight:
            x = "w-tw-\(margin)"; y = "\(margin)"
        case .bottomLeft:
            x = "\(margin)"; y = "h-th-\(margin)"
        case .bottomRight:
            x = "w-tw-\(margin)"; y = "h-th-\(margin)"
        case .bottomCenter:
            x = "(w-tw)/2"; y = "h-th-\(margin)"
        }

        return [
            "drawtext=text=\(ffmpegDrawtextEscaped(parts.joined(separator: " | ")))",
            "x=\(x)",
            "y=\(y)",
            "fontsize=\(fontSize)",
            "fontcolor=white",
            "box=1",
            "boxcolor=black@0.55",
            "boxborderw=\(max(8, fontSize / 3))"
        ].joined(separator: ":")
    }

    private static func ffmpegDrawtextEscaped(_ text: String) -> String {
        var escaped = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\":
                escaped += "\\\\"
            case ":", ",", "'", "[", "]", ";":
                escaped += "\\\(String(scalar))"
            case "\n", "\r":
                escaped += " "
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }

    private static func ffmpegSupportsFilter(_ ffmpegURL: URL, named filterName: String) -> Bool {
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = ["-hide_banner", "-filters"]
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe
        do {
            try process.run()
            process.waitUntilExit()
            let stdout = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let text = stdout + "\n" + stderr
            return text
                .split(separator: "\n")
                .contains { line in
                    let normalized = line
                        .replacingOccurrences(of: ".", with: " ")
                        .split(separator: " ")
                    return normalized.contains(Substring(filterName))
                }
        } catch {
            return false
        }
    }

    private static func makeBurnInOverlayImage(
        settings: BurnInSettings,
        context: BurnInRenderContext,
        directory: URL
    ) throws -> URL {
        let text = staticBurnInText(settings: settings, context: context)
        let fontSize: CGFloat
        switch settings.size {
        case .small: fontSize = 24
        case .medium: fontSize = 34
        case .large: fontSize = 48
        }

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let maxTextWidth: CGFloat = 900
        let textSize = (text as NSString).boundingRect(
            with: NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).integral.size
        let paddingX = max(14, fontSize * 0.45)
        let paddingY = max(10, fontSize * 0.32)
        let width = max(64, Int(ceil(textSize.width + paddingX * 2)))
        let height = max(36, Int(ceil(textSize.height + paddingY * 2)))

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) else {
            throw ProxyError.failed("Could not create burn-in overlay image")
        }
        rep.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            NSGraphicsContext.restoreGraphicsState()
            throw ProxyError.failed("Could not create burn-in drawing context")
        }
        NSGraphicsContext.current = ctx
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let box = NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
            xRadius: max(6, fontSize * 0.22),
            yRadius: max(6, fontSize * 0.22)
        )
        NSColor.black.withAlphaComponent(0.58).setFill()
        box.fill()
        (text as NSString).draw(
            with: NSRect(x: paddingX, y: paddingY, width: CGFloat(width) - paddingX * 2, height: CGFloat(height) - paddingY * 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ProxyError.failed("Could not export the burn-in overlay image")
        }
        let overlayURL = directory.appendingPathComponent(".321doit-burnin-\(UUID().uuidString).png")
        try data.write(to: overlayURL, options: [.atomic])
        return overlayURL
    }

    private static func staticBurnInText(settings: BurnInSettings, context: BurnInRenderContext) -> String {
        let fields = settings.fields
        var parts: [String] = []
        if fields.fileName { parts.append(context.fileName) }
        if fields.reelOrCard, !context.cardNumber.isEmpty { parts.append(context.cardNumber) }
        if fields.cameraID, !context.camera.isEmpty { parts.append(context.camera) }
        if fields.projectName, !context.projectName.isEmpty { parts.append(context.projectName) }
        if fields.shootDay, !context.shootDay.isEmpty { parts.append(context.shootDay) }
        if parts.isEmpty { parts.append(context.fileName) }
        return parts.joined(separator: " | ")
    }

    private static func overlayPositionFilter(for position: BurnInPosition) -> String {
        let margin = "18"
        switch position {
        case .topLeft:
            return "\(margin):\(margin)"
        case .topRight:
            return "main_w-overlay_w-\(margin):\(margin)"
        case .bottomLeft:
            return "\(margin):main_h-overlay_h-\(margin)"
        case .bottomRight:
            return "main_w-overlay_w-\(margin):main_h-overlay_h-\(margin)"
        case .bottomCenter:
            return "(main_w-overlay_w)/2:main_h-overlay_h-\(margin)"
        }
    }

    /// Build a `lut3d=…` ffmpeg filter expression. If intensity < 1, blend the LUT
    /// output back over the source using `blend=all_opacity=intensity`.
    static func lut3dFilter(path: String, intensity: Double) -> String {
        let escaped = ffmpegFiltergraphEscapedPath(path)
        let base = "lut3d=file=\(escaped)"
        let clamped = max(0, min(1, intensity))
        if clamped >= 0.999 {
            return base
        }
        // Use split + lut3d + blend to interpolate between source and LUT'd image.
        // The "all_opacity" blend mode mixes the top (LUT) over the bottom (source).
        return "split[a][b];[b]\(base)[c];[a][c]blend=all_mode=normal:all_opacity=\(String(format: "%.3f", clamped))"
    }

    static func ffmpegFiltergraphEscapedPath(_ path: String) -> String {
        var escaped = ""
        for scalar in path.unicodeScalars {
            switch scalar {
            case "\\":
                escaped += "\\\\"
            case " ", "\t", "\n", "\r", "'", "\"", ":", ",", "[", "]", ";":
                escaped += "\\\(String(scalar))"
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }
}

enum ProxyError: LocalizedError {
    case unsupported(String)
    case failed(String)
    case cancelled(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let name):
            return "AVFoundation cannot transcode this file on this system: \(name)"
        case .failed(let name):
            return "Proxy generation failed: \(name)"
        case .cancelled(let name):
            return "Proxy generation was canceled: \(name)"
        }
    }
}
