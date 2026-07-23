import AVFoundation
import Foundation

// MARK: - Manifest model
//
// Sole source of truth for the post-handoff package, per
// `321Doit Post Handoff Tech Doc` v0.2 §3.

struct HandoffManifest: Encodable, Equatable {
    var schemaVersion: String = "321doit-handoff-v1"
    var createdBy: HandoffCreator
    var project: HandoffProject
    var media: [HandoffMediaItem]
    var reports: HandoffReportRefs
    var handoff: HandoffSummary
}

struct HandoffCreator: Encodable, Equatable {
    var appName: String
    var appVersion: String
    var platform: String

    static func current() -> HandoffCreator {
        HandoffCreator(
            appName: HandoffAppInfo.name,
            appVersion: HandoffAppInfo.version,
            platform: "macOS"
        )
    }
}

/// Indirection: avoids the parser conflating "appName" with the same-named stored property.
enum HandoffAppInfo {
    static let name: String = appName
    static let version: String = appVersionString
}

struct HandoffProject: Encodable, Equatable {
    var name: String
    var shootDay: String
    var date: String
    var frameRate: HandoffFrameRateInfo
    var timeline: HandoffTimelineInfo
    var color: HandoffColorInfo
}

struct HandoffFrameRateInfo: Encodable, Equatable {
    var display: String
    var numerator: Int64
    var denominator: Int64
}

struct HandoffTimelineInfo: Encodable, Equatable {
    var name: String
    var width: Int
    var height: Int
    var startTimecode: String
    var dropFrame: Bool
}

struct HandoffColorInfo: Encodable, Equatable {
    var mode: String
    var lutPath: String?
    var applyLutOnImport: Bool
}

struct HandoffMediaItem: Encodable, Equatable {
    var id: String
    var cardId: String
    var camera: HandoffCamera
    var original: HandoffMediaFile
    var proxy: HandoffMediaProxy?
    var hashes: HandoffHashes
    var metadata: HandoffMetadata
}

struct HandoffCamera: Encodable, Equatable {
    var vendor: String
    var model: String
    var reel: String
}

struct HandoffMediaFile: Encodable, Equatable {
    var path: String
    var fileUrl: String
    var filename: String
    var sizeBytes: UInt64
    var codec: String
    var width: Int
    var height: Int
    var durationFrames: Int64
    var durationSeconds: Double
    var startTimecode: String
    var hasVideo: Bool
    var hasAudio: Bool
    var audioChannels: Int
    var audioSampleRate: Int
}

struct HandoffMediaProxy: Encodable, Equatable {
    var path: String
    var fileUrl: String
    var exists: Bool
    var codec: String
}

struct HandoffHashes: Encodable, Equatable {
    var algorithm: String
    var value: String
}

struct HandoffMetadata: Encodable, Equatable {
    var scene: String
    var shot: String
    var take: String
    var cameraAngle: String
    var notes: String
    var status: String?
    var isCircleTake: Bool?
    var tags: [String]?
}

struct HandoffReportRefs: Encodable, Equatable {
    var mhl: String?
    var pdf: String?
    var csv: String?
    var json: String?
    var txt: String?
    var sidecar: String?
}

struct HandoffSummary: Encodable, Equatable {
    var target: String                 // "resolve" | "finalCut" | "both"
    var generatedFiles: [String]
    var notes: String
}

// MARK: - Builder

enum HandoffManifestBuilder {

    /// Build a manifest from a successful TargetReport. The manifest layout uses
    /// absolute file paths to the *target* — this is the "shippable" copy of the
    /// originals/proxies/reports.
    static func make(
        offload: OffloadSettings,
        target: TargetReport,
        files: [FileCopyRecord],
        scriptLogProject: Project?
    ) async -> HandoffManifest {
        let handoff = offload.handoff
        let frameRate = handoff.frameRate.rational
        let resolution = handoff.resolution.size

        let creator = HandoffCreator.current()
        let projectName = effectiveProjectName(handoff: handoff, fallback: offload.projectName)
        let shootDay = effectiveShootDay(handoff: handoff, fallback: offload.cardNumber)
        let date = effectiveDate(handoff: handoff, fallback: offload.createdAt)

        let project = HandoffProject(
            name: projectName,
            shootDay: shootDay,
            date: date,
            frameRate: HandoffFrameRateInfo(
                display: handoff.frameRate.displayName,
                numerator: frameRate.numerator,
                denominator: frameRate.denominator
            ),
            timeline: HandoffTimelineInfo(
                name: "\(shootDay)_Assembly",
                width: resolution.width,
                height: resolution.height,
                startTimecode: handoff.startTimecode,
                dropFrame: handoff.frameRate.isDropFrame
            ),
            color: HandoffColorInfo(
                mode: handoff.colorMode.displayName,
                lutPath: lutPathForHandoff(offload: offload, target: target),
                applyLutOnImport: handoff.importLUT
            )
        )

        // Probe clips concurrently — each AVAsset probe is independent, I/O-bound
        // work, so a serial loop over hundreds/thousands of clips is needlessly
        // slow. A bounded window (6 in flight) avoids opening thousands of assets
        // at once (fd/memory pressure); results are re-indexed so the manifest
        // keeps deterministic input order.
        let cardId = offload.cardNumber.isEmpty ? "UNKNOWN_CARD" : offload.cardNumber
        let maxConcurrentProbes = 6
        var itemsByIndex: [Int: HandoffMediaItem] = [:]
        await withTaskGroup(of: (Int, HandoffMediaItem?).self) { group in
            var submitted = 0
            func submitNext() {
                guard submitted < files.count else { return }
                let index = submitted
                let record = files[index]
                group.addTask {
                    (index, await buildMediaItem(
                        offload: offload,
                        target: target,
                        record: record,
                        cardId: cardId,
                        scriptLogProject: scriptLogProject
                    ))
                }
                submitted += 1
            }
            for _ in 0..<min(maxConcurrentProbes, files.count) { submitNext() }
            while let (index, item) = await group.next() {
                if let item { itemsByIndex[index] = item }
                submitNext()
            }
        }
        let mediaItems = (0..<files.count).compactMap { itemsByIndex[$0] }

        let reports = HandoffReportRefs(
            mhl: target.mhlURL?.path,
            pdf: target.pdfURL?.path,
            csv: target.csvURL?.path,
            json: target.jsonURL?.path,
            txt: target.txtURL?.path,
            sidecar: target.sidecarURL?.path
        )

        let targetLabel: String
        switch handoff.target {
        case .none:     targetLabel = "none"
        case .resolve:  targetLabel = "resolve"
        case .finalCut: targetLabel = "finalCut"
        case .both:     targetLabel = "both"
        }

        return HandoffManifest(
            createdBy: creator,
            project: project,
            media: mediaItems,
            reports: reports,
            handoff: HandoffSummary(
                target: targetLabel,
                generatedFiles: [],
                notes: ""
            )
        )
    }

    static func write(
        manifest: HandoffManifest,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: [.atomic])
    }

    // MARK: - Per-clip helpers

    private static func buildMediaItem(
        offload: OffloadSettings,
        target: TargetReport,
        record: FileCopyRecord,
        cardId: String,
        scriptLogProject: Project?
    ) async -> HandoffMediaItem? {
        guard let result = record.targetResults.first(where: {
            $0.outputPath.hasPrefix(target.outputURL.path) && $0.verified
        }) else {
            return nil
        }

        let originalURL = URL(fileURLWithPath: result.outputPath)
        guard isHandoffMediaFile(originalURL) else { return nil }

        let probe = await MediaProbe.probe(at: originalURL)
        let proxyInfo = locateProxy(
            offload: offload,
            target: target,
            originalURL: originalURL,
            relativePath: record.relativePath
        )

        let id = stableMediaID(
            cardId: cardId,
            relativePath: record.relativePath,
            size: record.size,
            hash: record.sourceHash
        )

        let original = HandoffMediaFile(
            path: originalURL.path,
            fileUrl: HandoffURL.fileURL(forAbsolutePath: originalURL.path),
            filename: originalURL.lastPathComponent,
            sizeBytes: record.size,
            codec: probe.codec,
            width: probe.width,
            height: probe.height,
            durationFrames: probe.durationFrames,
            durationSeconds: probe.durationSeconds,
            startTimecode: probe.startTimecode,
            hasVideo: probe.hasVideo,
            hasAudio: probe.hasAudio,
            audioChannels: probe.audioChannels,
            audioSampleRate: probe.audioSampleRate
        )

        let proxy: HandoffMediaProxy?
        if let proxyURL = proxyInfo.url {
            proxy = HandoffMediaProxy(
                path: proxyURL.path,
                fileUrl: HandoffURL.fileURL(forAbsolutePath: proxyURL.path),
                exists: proxyInfo.exists,
                codec: proxyInfo.codec
            )
        } else {
            proxy = nil
        }

        var scriptLogScene = ""
        var scriptLogShot = ""
        var scriptLogTake = ""
        var scriptLogAngle = ""
        var scriptLogNotes = ""
        var scriptLogStatus: String?
        var scriptLogIsCircleTake: Bool?
        var scriptLogTags: [String]?

        if let scriptProject = scriptLogProject, offload.handoff.injectScriptLogMetadata {
            let filename = originalURL.lastPathComponent
            let stem = originalURL.deletingPathExtension().lastPathComponent
            
            var matchedTake: Take?
            var matchedRecord: CameraRecord?
            var matchedSceneName: String?
            
            for day in scriptProject.shootingDays {
                for scene in day.scenes {
                    for shot in scene.shots {
                        for take in shot.takes {
                            if let linked = take.linkedClips.first(where: { linkedClipMatches($0, originalURL: originalURL) }) {
                                matchedTake = take
                                matchedSceneName = scene.sceneNumber
                                scriptLogShot = shot.shotNumber
                                matchedRecord = take.cameraRecords.first(where: { $0.cardName == linked.cameraCard }) ?? take.cameraRecords.first
                                break
                            }

                            for camRecord in take.cameraRecords {
                                if cameraRecordMatches(camRecord, originalURL: originalURL, filename: filename, stem: stem) {
                                    matchedTake = take; matchedRecord = camRecord; matchedSceneName = scene.sceneNumber
                                    scriptLogShot = shot.shotNumber
                                    break
                                }
                            }
                            if matchedRecord != nil { break }
                        }
                        if matchedRecord != nil { break }
                    }
                    if matchedRecord != nil { break }
                }
                if matchedRecord != nil { break }
            }
            
            if let matchedRecord = matchedRecord, let take = matchedTake {
                scriptLogScene = matchedSceneName ?? ""
                scriptLogTake = String(take.takeNumber)
                scriptLogAngle = matchedRecord.cameraLabel
                
                let combinedNotes = [take.generalNote, matchedRecord.notes]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " | ")
                if !combinedNotes.isEmpty {
                    scriptLogNotes = combinedNotes
                }
                
                scriptLogStatus = matchedRecord.status.rawValue
                scriptLogIsCircleTake = take.isCircleTake
                if !take.quickTags.isEmpty {
                    scriptLogTags = take.quickTags
                }
            } else {
                print("⚠️ No script log match found for file: \(filename)")
            }
        }

        return HandoffMediaItem(
            id: id,
            cardId: cardId,
            camera: HandoffCamera(
                vendor: cameraVendor(from: offload.camera),
                model: offload.camera,
                reel: cardId
            ),
            original: original,
            proxy: proxy,
            hashes: HandoffHashes(
                algorithm: offload.checksumAlgorithm.mhlHashType,
                value: record.sourceHash
            ),
            metadata: HandoffMetadata(
                scene: scriptLogScene,
                shot: scriptLogShot,
                take: scriptLogTake,
                cameraAngle: scriptLogAngle,
                notes: scriptLogNotes,
                status: scriptLogStatus,
                isCircleTake: scriptLogIsCircleTake,
                tags: scriptLogTags
            )
        )
    }

    private static func linkedClipMatches(_ clip: ClipReference, originalURL: URL) -> Bool {
        let path = clip.filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty && URL(fileURLWithPath: path).standardizedFileURL.path == originalURL.standardizedFileURL.path {
            return true
        }

        let filename = originalURL.lastPathComponent.lowercased()
        let stem = originalURL.deletingPathExtension().lastPathComponent.lowercased()
        let clipName = clip.fileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !clipName.isEmpty && (clipName == filename || clipName == stem)
    }

    private static func cameraRecordMatches(
        _ record: CameraRecord,
        originalURL: URL,
        filename: String,
        stem: String
    ) -> Bool {
        let value = record.clipName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }

        let lower = value.lowercased()
        let filenameLower = filename.lowercased()
        let stemLower = stem.lowercased()

        if value.contains("/") {
            let url = URL(fileURLWithPath: value)
            if url.standardizedFileURL.path == originalURL.standardizedFileURL.path {
                return true
            }
            let last = url.lastPathComponent.lowercased()
            let lastStem = url.deletingPathExtension().lastPathComponent.lowercased()
            return last == filenameLower || lastStem == stemLower
        }

        if lower == filenameLower || lower == stemLower {
            return true
        }

        return filenameLower.contains(lower) || stemLower.contains(lower)
    }

    private static func locateProxy(
        offload: OffloadSettings,
        target: TargetReport,
        originalURL: URL,
        relativePath: String
    ) -> (url: URL?, exists: Bool, codec: String) {
        guard offload.handoff.importProxies else { return (nil, false, "") }

        let proxyRoot = OffloadPackageLayout.proxyRoot(outputURL: target.outputURL, profile: offload.transcodeProfile, kind: .standard)
        let candidates: [URL] = [
            proxyRoot.appendingPathComponent(ProxyTranscoder.proxyRelativePath(for: relativePath, profile: offload.transcodeProfile)),
            OffloadPackageLayout.proxyRoot(outputURL: target.outputURL, profile: offload.transcodeProfile, kind: .clean)
                .appendingPathComponent(ProxyTranscoder.proxyRelativePath(for: relativePath, profile: offload.transcodeProfile, kind: .clean)),
            OffloadPackageLayout.proxyRoot(outputURL: target.outputURL, profile: offload.transcodeProfile, kind: .lutBaked)
                .appendingPathComponent(ProxyTranscoder.proxyRelativePath(for: relativePath, profile: offload.transcodeProfile, kind: .lutBaked))
        ]
        let existing = candidates.first { FileManager.default.fileExists(atPath: $0.path) }
        let proxyURL = existing ?? candidates[0]
        return (proxyURL, existing != nil, offload.transcodeProfile.codec.displayName)
    }

    private static func lutPathForHandoff(
        offload: OffloadSettings,
        target: TargetReport
    ) -> String? {
        guard offload.handoff.importLUT,
              let lutPath = offload.transcodeProfile.lutPath,
              !lutPath.isEmpty else { return nil }
        let lutDir = OffloadPackageLayout.handoffRoot(outputURL: target.outputURL)
            .appendingPathComponent("LUT", isDirectory: true)
        return lutDir.appendingPathComponent(URL(fileURLWithPath: lutPath).lastPathComponent).path
    }

    static func isHandoffMediaFile(_ url: URL) -> Bool {
        if ProxyTranscoder.shouldAttemptProxy(for: url.lastPathComponent, attemptRaw: true) {
            return true
        }
        return audioExtensions.contains(url.pathExtension.lowercased())
    }

    private static let audioExtensions: Set<String> = [
        "wav", "wave", "bwf", "aif", "aiff", "caf", "m4a",
        "aac", "mp3", "flac", "ogg", "oga", "wma"
    ]

    private static func cameraVendor(from camera: String) -> String {
        let lower = camera.lowercased()
        if lower.contains("alexa") || lower.contains("arri") { return "ARRI" }
        if lower.contains("red") { return "RED" }
        if lower.contains("sony") || lower.contains("fx") || lower.contains("a7") { return "Sony" }
        if lower.contains("canon") || lower.contains("c70") || lower.contains("c300") || lower.contains("c500") { return "Canon" }
        if lower.contains("blackmagic") || lower.contains("ursa") || lower.contains("pocket") { return "Blackmagic" }
        if lower.contains("panasonic") || lower.contains("varicam") || lower.contains("eva") { return "Panasonic" }
        if lower.contains("nikon") || lower.contains("z9") { return "Nikon" }
        if lower.contains("dji") { return "DJI" }
        return ""
    }

    /// Stable ID per the spec: cardId + filename stem + first 8 hex of hash.
    private static func stableMediaID(
        cardId: String,
        relativePath: String,
        size: UInt64,
        hash: String
    ) -> String {
        let stem = URL(fileURLWithPath: relativePath)
            .deletingPathExtension()
            .lastPathComponent
            .replacingOccurrences(of: " ", with: "_")
        let hashStub = String(hash.prefix(16))
        return "\(cardId)_\(stem)_\(hashStub.isEmpty ? String(size) : hashStub)"
    }

    static func effectiveProjectName(handoff: HandoffSettings, fallback: String) -> String {
        let trimmed = handoff.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func effectiveShootDay(handoff: HandoffSettings, fallback: String) -> String {
        let trimmed = handoff.shootDay.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let cardTrim = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return cardTrim.isEmpty ? "Day01" : cardTrim
    }

    static func effectiveDate(handoff: HandoffSettings, fallback: Date) -> String {
        let trimmed = handoff.shootDate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: fallback)
    }
}

// MARK: - URL helpers (RFC 3986 percent-encoded file:// URLs).

enum HandoffURL {
    /// Build a `file:///…` URL for an absolute filesystem path. Spaces, Chinese
    /// characters, etc. are percent-encoded by the system. Always absolute.
    static func fileURL(forAbsolutePath path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.absoluteString
    }
}

// MARK: - Media probe (best-effort AVAsset probe; cheap fallbacks if it fails).

struct MediaProbeResult {
    var codec: String = ""
    var width: Int = 0
    var height: Int = 0
    var durationFrames: Int64 = 0
    var durationSeconds: Double = 0
    var startTimecode: String = "00:00:00:00"
    var hasVideo: Bool = false
    var hasAudio: Bool = false
    var audioChannels: Int = 0
    var audioSampleRate: Int = 0
}

enum MediaProbe {
    /// Best-effort AVAsset probe. Falls back to safe zero values if AVAsset
    /// cannot read the file.
    static func probe(at url: URL) async -> MediaProbeResult {
        var out = MediaProbeResult()
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        // Duration (seconds + 25fps frame fallback if we can't read native rate).
        if let cmDuration = try? await asset.load(.duration),
           cmDuration.isValid,
           !cmDuration.isIndefinite {
            let seconds = CMTimeGetSeconds(cmDuration)
            if seconds.isFinite && seconds >= 0 {
                out.durationSeconds = seconds
            }
        }

        // Video tracks
        if let videoTracks = try? await asset.loadTracks(withMediaType: .video),
           let v = videoTracks.first {
            out.hasVideo = true
            let naturalSize = (try? await v.load(.naturalSize)) ?? .zero
            let preferredTransform = (try? await v.load(.preferredTransform)) ?? .identity
            let size = naturalSize.applying(preferredTransform)
            out.width = Int(abs(size.width))
            out.height = Int(abs(size.height))
            let nominalFps = Double((try? await v.load(.nominalFrameRate)) ?? 0)
            if nominalFps > 0 {
                out.durationFrames = Int64((out.durationSeconds * nominalFps).rounded())
            }
            if let desc = (try? await v.load(.formatDescriptions))?.first {
                out.codec = fourCCString(CMFormatDescriptionGetMediaSubType(desc))
            }
        }

        // Audio tracks
        if let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
           let a = audioTracks.first {
            out.hasAudio = true
            if let desc = (try? await a.load(.formatDescriptions))?.first {
                if let abd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                    out.audioChannels = Int(abd.mChannelsPerFrame)
                    out.audioSampleRate = Int(abd.mSampleRate)
                }
            }
            if out.audioSampleRate == 0 { out.audioSampleRate = 48000 }
        }

        // Try to read embedded start timecode.
        if let tc = await readStartTimecode(asset: asset) {
            out.startTimecode = tc
        }

        return out
    }

    private static func fourCCString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        let s = String(bytes: bytes, encoding: .ascii) ?? ""
        return s.trimmingCharacters(in: .whitespaces)
    }

    private static func readStartTimecode(asset: AVAsset) async -> String? {
        guard let tcTracks = try? await asset.loadTracks(withMediaType: .timecode),
              let track = tcTracks.first else { return nil }
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            return nil
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading(), let buffer = output.copyNextSampleBuffer() else {
            return nil
        }
        guard let block = CMSampleBufferGetDataBuffer(buffer) else { return nil }
        var length: Int = 0
        var dataPtr: UnsafeMutablePointer<Int8>? = nil
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPtr) == kCMBlockBufferNoErr else {
            return nil
        }
        guard length >= 4, let ptr = dataPtr else { return nil }
        // Big-endian 32-bit frame count.
        let raw = ptr.withMemoryRebound(to: UInt8.self, capacity: 4) { rebound -> UInt32 in
            (UInt32(rebound[0]) << 24) | (UInt32(rebound[1]) << 16) | (UInt32(rebound[2]) << 8) | UInt32(rebound[3])
        }
        // Use 25 fps as a safe display fallback for the manifest if we can't
        // discover the timecode track's frameDuration easily.
        let fps = await inferTimecodeFPS(track: track) ?? 25
        return formatTimecode(frames: Int(raw), fps: fps)
    }

    private static func inferTimecodeFPS(track: AVAssetTrack) async -> Int? {
        guard let desc = (try? await track.load(.formatDescriptions))?.first else { return nil }
        let extensions = CMFormatDescriptionGetExtensions(desc) as? [String: Any]
        if let frameDuration = extensions?["FrameDuration"] as? [String: Any],
           let value = frameDuration["value"] as? Int64,
           let timescale = frameDuration["timescale"] as? Int32, value > 0 {
            return Int((Double(timescale) / Double(value)).rounded())
        }
        return nil
    }

    private static func formatTimecode(frames: Int, fps: Int) -> String {
        let safeFps = max(1, fps)
        let totalSeconds = frames / safeFps
        let hh = totalSeconds / 3600
        let mm = (totalSeconds % 3600) / 60
        let ss = totalSeconds % 60
        let ff = frames % safeFps
        return String(format: "%02d:%02d:%02d:%02d", hh, mm, ss, ff)
    }
}
