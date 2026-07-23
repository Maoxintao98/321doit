import Foundation

// MARK: - Containers & modes

enum MediaContainer: String, Codable, CaseIterable, Identifiable {
    case mov
    case mp4
    case mkv
    case webm
    case avi
    case mpegts     // .mts / .m2ts / .ts
    case mxf
    case wav
    case aiff
    case flac
    case m4a        // ALAC

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .mpegts: return "m2ts"
        default: return rawValue
        }
    }

    var isAudioOnly: Bool {
        switch self {
        case .wav, .aiff, .flac, .m4a: return true
        default: return false
        }
    }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .mov:    return L10n.t("MOV", "MOV", language: language)
        case .mp4:   return "MP4"
        case .mkv:   return L10n.t("MKV", "MKV", language: language)
        case .webm:  return "WebM"
        case .avi:   return "AVI"
        case .mpegts: return L10n.t("MTS / M2TS / TS", "MTS / M2TS / TS", language: language)
        case .mxf:   return L10n.t("MXF", "MXF", language: language)
        case .wav:   return L10n.t("WAV PCM", "WAV PCM", language: language)
        case .aiff:  return L10n.t("AIFF PCM", "AIFF PCM", language: language)
        case .flac:  return L10n.t("FLAC", "FLAC", language: language)
        case .m4a:   return L10n.t("ALAC (M4A)", "ALAC (M4A)", language: language)
        }
    }
}

enum MediaConversionMode: String, Codable, CaseIterable, Identifiable {
    /// Stream copy — no video/audio re-encode.
    case rewrap
    /// Decode and encode picture/sound into a new delivery format.
    case transcode
    /// Reversible audio encoding between PCM/FLAC/ALAC.
    case losslessAudio

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .rewrap: return L10n.t("仅更换封装", "Rewrap / Stream Copy", language: language)
        case .transcode: return L10n.t("视频转码", "Video Transcode", language: language)
        case .losslessAudio: return L10n.t("无损音频转换", "Lossless Audio Conversion", language: language)
        }
    }

    /// Whether this mode re-encodes video / audio streams. Rewrap never does;
    /// lossless audio re-encodes audio (mathematically reversible) but never video.
    var reencodesVideo: Bool { self == .transcode }
    var reencodesAudio: Bool {
        switch self {
        case .rewrap: return false
        case .transcode, .losslessAudio: return true
        }
    }
}

enum MediaVideoCodec: String, Codable, CaseIterable, Identifiable {
    case h264
    case h265
    case prores422
    case prores422HQ
    case av1
    case vp9
    case mpeg2
    case dnxhrHQX

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .h264: return "H.264 / AVC"
        case .h265: return "H.265 / HEVC"
        case .prores422: return "Apple ProRes 422"
        case .prores422HQ: return "Apple ProRes 422 HQ"
        case .av1: return "AV1"
        case .vp9: return "Google VP9"
        case .mpeg2: return "MPEG-2 Video"
        case .dnxhrHQX: return "Avid DNxHR HQX"
        }
    }

    var shortName: String {
        switch self {
        case .h264: return "H.264"
        case .h265: return "H.265"
        case .prores422: return "ProRes 422"
        case .prores422HQ: return "ProRes HQ"
        case .av1: return "AV1"
        case .vp9: return "VP9"
        case .mpeg2: return "MPEG-2"
        case .dnxhrHQX: return "DNxHR HQX"
        }
    }

    var ffmpegEncoder: String {
        switch self {
        case .h264: return "libx264"
        case .h265: return "libx265"
        case .prores422, .prores422HQ: return "prores_ks"
        case .av1: return "libaom-av1"
        case .vp9: return "libvpx-vp9"
        case .mpeg2: return "mpeg2video"
        case .dnxhrHQX: return "dnxhd"
        }
    }

    var probedCodecNames: Set<String> {
        switch self {
        case .h264: return ["h264"]
        case .h265: return ["hevc", "h265"]
        case .prores422, .prores422HQ: return ["prores"]
        case .av1: return ["av1"]
        case .vp9: return ["vp9"]
        case .mpeg2: return ["mpeg2video"]
        case .dnxhrHQX: return ["dnxhd", "dnxhr"]
        }
    }

    var supportedContainers: [MediaContainer] {
        switch self {
        case .h264: return [.mp4, .mov, .mkv, .mpegts, .mxf, .avi]
        case .h265: return [.mp4, .mov, .mkv, .mpegts]
        case .prores422, .prores422HQ: return [.mov, .mkv]
        case .av1: return [.mkv, .mp4, .webm]
        case .vp9: return [.webm, .mkv]
        case .mpeg2: return [.mxf, .mpegts, .mkv, .mov]
        case .dnxhrHQX: return [.mxf, .mov, .mkv]
        }
    }
}

enum MediaAudioCodec: String, Codable, CaseIterable, Identifiable {
    case aac
    case opus
    case pcm
    case copy
    case none

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .aac: return "AAC 256 kbps"
        case .opus: return "Opus 192 kbps"
        case .pcm: return L10n.t("PCM 24-bit", "PCM 24-bit", language: language)
        case .copy: return L10n.t("保留原编码", "Copy source audio", language: language)
        case .none: return L10n.t("不输出音频", "No audio", language: language)
        }
    }
}

enum MediaTranscodeQuality: String, Codable, CaseIterable, Identifiable {
    case compact
    case balanced
    case high
    case master

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .compact: return L10n.t("小体积", "Compact", language: language)
        case .balanced: return L10n.t("均衡", "Balanced", language: language)
        case .high: return L10n.t("高质量", "High Quality", language: language)
        case .master: return L10n.t("母版", "Master", language: language)
        }
    }
}

enum MediaOutputScale: String, Codable, CaseIterable, Identifiable {
    case source
    case uhd4K
    case hd1080
    case hd720

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .source: return L10n.t("保持原始", "Source", language: language)
        case .uhd4K: return "4K · 2160p"
        case .hd1080: return "Full HD · 1080p"
        case .hd720: return "HD · 720p"
        }
    }

    var targetHeight: Int? {
        switch self {
        case .source: return nil
        case .uhd4K: return 2160
        case .hd1080: return 1080
        case .hd720: return 720
        }
    }
}

enum MediaOutputFrameRate: String, Codable, CaseIterable, Identifiable {
    case source
    case fps23976
    case fps24
    case fps25
    case fps30
    case fps50
    case fps60

    var id: String { rawValue }

    func displayName(language: AppLanguage) -> String {
        switch self {
        case .source: return L10n.t("保持原始", "Source", language: language)
        case .fps23976: return "23.976 fps"
        case .fps24: return "24 fps"
        case .fps25: return "25 fps"
        case .fps30: return "30 fps"
        case .fps50: return "50 fps"
        case .fps60: return "60 fps"
        }
    }

    var ffmpegValue: String? {
        switch self {
        case .source: return nil
        case .fps23976: return "24000/1001"
        case .fps24: return "24"
        case .fps25: return "25"
        case .fps30: return "30"
        case .fps50: return "50"
        case .fps60: return "60"
        }
    }
}

struct MediaTranscodeSettings: Codable, Equatable {
    var videoCodec: MediaVideoCodec = .h265
    var audioCodec: MediaAudioCodec = .aac
    var quality: MediaTranscodeQuality = .high
    var scale: MediaOutputScale = .source
    var frameRate: MediaOutputFrameRate = .source

    static let `default` = MediaTranscodeSettings()
}

// MARK: - Probed media (parsed ffprobe JSON)

enum MediaStreamKind: String, Codable {
    case video, audio, subtitle, data, attachment
    init?(rawType: String) {
        self.init(rawValue: rawType)
    }
}

struct ProbedStream: Codable, Equatable {
    let index: Int
    let kind: MediaStreamKind
    let codecName: String
    let codecLongName: String
    let profile: String
    let codecTagString: String

    // video
    let width: Int
    let height: Int
    let pixFmt: String
    let sampleAspectRatio: String
    let displayAspectRatio: String
    let rFrameRate: String
    let avgFrameRate: String
    let bitsPerRawSample: String

    // audio
    let sampleRate: String
    let channels: String
    let channelLayout: String
    let sampleFmt: String
    let bitsPerSample: String

    // timing / color / common
    let timeBase: String
    let startTime: String
    let duration: String
    let nbFrames: String
    let bitRate: String
    let colorRange: String
    let colorSpace: String
    let colorTransfer: String
    let colorPrimaries: String
    let rotation: String
    let tags: [String: String]
    let disposition: [String: Int]
    let sideData: [[String: String]]

    var isVideo: Bool { kind == .video }
    var isAudio: Bool { kind == .audio }
    var isSubtitle: Bool { kind == .subtitle }
    var isData: Bool { kind == .data }
    var isAttachment: Bool { kind == .attachment }

    /// Timecode carried as a stream tag (common for QuickTime timecode tracks).
    var tagTimecode: String? { tags["timecode"] ?? tags["TIMECODE"] }

    var isQuickTimeTimecode: Bool {
        let codec = codecName.lowercased()
        let tag = codecTagString.lowercased()
        let handler = tags["handler_name"]?.lowercased() ?? ""
        return codec == "timecode"
            || codec == "tmcd"
            || tag.contains("tmcd")
            || handler.contains("timecode")
            || tagTimecode != nil
    }

    var codecDisplayName: String {
        let codec = codecName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !codec.isEmpty, codec.lowercased() != "unknown" {
            return codec
        }
        let tag = codecTagString.trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.isEmpty ? "unknown" : tag
    }

    /// Best-effort bit depth (video bits_per_raw_sample, audio bits_per_sample).
    var bitDepth: String {
        let v = bitsPerRawSample.trimmingCharacters(in: .whitespaces)
        if !v.isEmpty { return v }
        return bitsPerSample.trimmingCharacters(in: .whitespaces)
    }

    static func from(_ json: [String: Any]) -> ProbedStream {
        func str(_ key: String) -> String {
            if let v = json[key] { return String(describing: v) }
            return ""
        }
        func intStr(_ key: String) -> String { str(key) }

        let rawType = str("codec_type").lowercased()
        let kind = MediaStreamKind(rawType: rawType) ?? .data

        var rotation = ""
        if let side = json["side_data_list"] as? [[String: Any]] {
            for entry in side {
                if let r = entry["rotation"] { rotation = String(describing: r) }
                // displaymatrix-based rotation is reported as a side data entry
                // without a scalar "rotation" field; leave as-is for V1.
            }
        }

        let tags = (json["tags"] as? [String: Any])?.mapValues { String(describing: $0) } ?? [:]
        let disposition = (json["disposition"] as? [String: Any])?.compactMapValues { Int(String(describing: $0)) } ?? [:]
        let sideData = (json["side_data_list"] as? [[String: Any]])?
            .map { $0.mapValues { String(describing: $0) } } ?? []

        return ProbedStream(
            index: Int(str("index")) ?? 0,
            kind: kind,
            codecName: str("codec_name"),
            codecLongName: str("codec_long_name"),
            profile: str("profile"),
            codecTagString: str("codec_tag_string"),
            width: Int(str("width")) ?? 0,
            height: Int(str("height")) ?? 0,
            pixFmt: str("pix_fmt"),
            sampleAspectRatio: str("sample_aspect_ratio"),
            displayAspectRatio: str("display_aspect_ratio"),
            rFrameRate: str("r_frame_rate"),
            avgFrameRate: str("avg_frame_rate"),
            bitsPerRawSample: str("bits_per_raw_sample"),
            sampleRate: str("sample_rate"),
            channels: str("channels"),
            channelLayout: str("channel_layout"),
            sampleFmt: str("sample_fmt"),
            bitsPerSample: str("bits_per_sample"),
            timeBase: str("time_base"),
            startTime: str("start_time"),
            duration: str("duration"),
            nbFrames: str("nb_frames"),
            bitRate: str("bit_rate"),
            colorRange: str("color_range"),
            colorSpace: str("color_space"),
            colorTransfer: str("color_transfer"),
            colorPrimaries: str("color_primaries"),
            rotation: rotation,
            tags: tags,
            disposition: disposition,
            sideData: sideData
        )
    }
}

struct ProbedFormat: Codable, Equatable {
    let formatName: String
    let formatLongName: String
    let filename: String
    let nbStreams: Int
    let duration: String
    let startTime: String
    let size: String
    let bitRate: String
    let tags: [String: String]

    static func from(_ json: [String: Any]) -> ProbedFormat {
        func str(_ key: String) -> String {
            if let v = json[key] { return String(describing: v) }
            return ""
        }
        let tags = (json["tags"] as? [String: Any])?.mapValues { String(describing: $0) } ?? [:]
        return ProbedFormat(
            formatName: str("format_name"),
            formatLongName: str("format_long_name"),
            filename: str("filename"),
            nbStreams: Int(str("nb_streams")) ?? 0,
            duration: str("duration"),
            startTime: str("start_time"),
            size: str("size"),
            bitRate: str("bit_rate"),
            tags: tags
        )
    }
}

struct ProbedChapter: Codable, Equatable {
    let id: String
    let start: String
    let end: String
    let title: String

    static func from(_ json: [String: Any]) -> ProbedChapter {
        func str(_ key: String) -> String {
            if let v = json[key] { return String(describing: v) }
            return ""
        }
        let tags = (json["tags"] as? [String: Any])?.mapValues { String(describing: $0) } ?? [:]
        return ProbedChapter(
            id: str("id"),
            start: str("start_time"),
            end: str("end_time"),
            title: tags["title"] ?? ""
        )
    }
}

struct ProbedMedia: Codable, Equatable {
    let url: URL
    let format: ProbedFormat
    let streams: [ProbedStream]
    let chapters: [ProbedChapter]
    /// Best-effort file size in bytes (from format.size when present).
    var sizeBytes: Int64 { Int64(format.size) ?? 0 }
    var durationSeconds: Double? { Double(format.duration) }

    var videoStreams: [ProbedStream] { streams.filter { $0.isVideo } }
    var audioStreams: [ProbedStream] { streams.filter { $0.isAudio } }
    var subtitleStreams: [ProbedStream] { streams.filter { $0.isSubtitle } }
    var dataStreams: [ProbedStream] { streams.filter { $0.isData || $0.isAttachment } }

    /// A QuickTime timecode track is reported as a data/attachment stream
    /// whose codec is `timecode`, or whose codec tag is `tmcd`.
    var hasQuickTimeTimecodeTrack: Bool {
        streams.contains {
            ($0.isData || $0.isAttachment) && $0.isQuickTimeTimecode
        }
    }
}

// MARK: - Compatibility

enum RiskSeverity: String, Codable {
    case info
    case warning
    case blocking
}

enum CompatibilityVerdict: String, Codable {
    case compatible
    case compatibleWithWarnings
    case incompatible
    case probeFailed
    case missingDependency
}

struct CompatibilityRisk: Codable, Equatable {
    let severity: RiskSeverity
    let code: String
    let zh: String
    let en: String
    /// Stream index this risk concerns, if any.
    let streamIndex: Int?

    func message(language: AppLanguage) -> String {
        L10n.t(zh, en, language: language)
    }
}

struct CompatibilityResult: Codable, Equatable {
    let verdict: CompatibilityVerdict
    let risks: [CompatibilityRisk]
    let reencodesVideo: Bool
    let reencodesAudio: Bool
    let subtitleRetained: Bool
    let dataRetained: Bool

    var summary: (String, String) {
        switch verdict {
        case .compatible:
            return ("可以执行，未发现风险", "Ready to run; no risks detected")
        case .compatibleWithWarnings:
            return ("可以执行，但存在元数据或兼容性提醒", "Ready to run, with metadata/compatibility warnings")
        case .incompatible:
            return ("目标容器无法承载至少一条必要流", "Target container cannot carry at least one required stream")
        case .probeFailed:
            return ("无法读取输入媒体", "Could not read the input media")
        case .missingDependency:
            return ("缺少 ffmpeg / ffprobe", "ffmpeg / ffprobe not available")
        }
    }
}

// MARK: - Task lifecycle (Phase 1 skeleton; full state in Phase 2)

enum MediaConversionTaskState: String, Codable {
    case waiting
    case analyzing
    case ready
    case converting
    case verifying
    case completed
    case warning
    case failed
    case cancelled
    case interrupted
}

/// Stable error codes surfaced in logs and reports.
enum MediaConversionError: String, Error {
    case dependencyMissing = "MC_DEPENDENCY_MISSING"
    case probeFailed = "MC_PROBE_FAILED"
    case probeTimedOut = "MC_PROBE_TIMED_OUT"
    case incompatibleContainer = "MC_INCOMPATIBLE_CONTAINER"
    case insufficientSpace = "MC_INSUFFICIENT_SPACE"
    case outputExists = "MC_OUTPUT_EXISTS"
    case targetNotWritable = "MC_TARGET_NOT_WRITABLE"
    case conversionFailed = "MC_CONVERSION_FAILED"
    case verificationFailed = "MC_VERIFICATION_FAILED"
    case reportFailed = "MC_REPORT_FAILED"
    case cancelled = "MC_CANCELLED"

    func message(language: AppLanguage) -> String {
        switch self {
        case .dependencyMissing:
            return L10n.t("缺少 ffmpeg 或 ffprobe", "ffmpeg or ffprobe is missing", language: language)
        case .probeFailed:
            return L10n.t("无法分析输入文件", "Could not analyze the input file", language: language)
        case .probeTimedOut:
            return L10n.t("素材分析超时，请重试或检查文件是否仍可访问", "Media analysis timed out. Retry or check that the file is still available.", language: language)
        case .incompatibleContainer:
            return L10n.t("容器与流不兼容", "Container is incompatible with the streams", language: language)
        case .insufficientSpace:
            return L10n.t("输出空间不足", "Insufficient space on the output volume", language: language)
        case .outputExists:
            return L10n.t("输出文件已存在", "Output file already exists", language: language)
        case .targetNotWritable:
            return L10n.t("目标目录不可写", "Target directory is not writable", language: language)
        case .conversionFailed:
            return L10n.t("转换失败", "Conversion failed", language: language)
        case .verificationFailed:
            return L10n.t("转换后验证不一致", "Post-conversion verification mismatch", language: language)
        case .reportFailed:
            return L10n.t("报告写入失败", "Report write failed", language: language)
        case .cancelled:
            return L10n.t("任务已取消", "Task cancelled", language: language)
        }
    }
}

/// Lightweight, serializable project context shared with other tools.
/// A linked project supplies defaults and archiving context; it never
/// changes the conversion algorithm.
struct ToolProjectContext: Codable, Equatable {
    var projectID: UUID
    var projectName: String
    var projectFolderURL: URL?
}

/// Public request used by other tools (offload, handoff) to enqueue conversions.
struct MediaConversionRequest: Equatable {
    var sourceURLs: [URL]
    var mode: MediaConversionMode
    var targetContainer: MediaContainer
    var destinationURL: URL
    var projectContext: ToolProjectContext?
}

// MARK: - Phase 2 execution and verification

struct MediaConversionProgress: Codable, Equatable {
    var fraction: Double
    var processedSeconds: Double
    var speed: String
}

struct MediaConversionOutput: Equatable {
    var temporaryURL: URL
    var finalURL: URL
    var ffmpegArguments: [String]
    var startedAt: Date
    var completedAt: Date
    var ffmpegVersion: String
}

enum MediaVerificationLevel: String, Codable {
    case packetPayload
    case decodedContent
    case structureOnly
}

struct MediaVerificationResult: Codable, Equatable {
    var passed: Bool
    var level: MediaVerificationLevel
    var hasMetadataWarnings: Bool
    var sourceSignature: String?
    var outputSignature: String?
    var messages: [String]
    var verifiedAt: Date
}

struct MediaConversionReport: Codable, Equatable {
    var schema: String
    var schemaVersion: Int
    var taskID: UUID
    var createdAt: Date
    var startedAt: Date
    var endedAt: Date
    var appVersion: String
    var ffmpegVersion: String
    var projectAssociationMode: String
    var linkedProjectID: UUID?
    var sourcePath: String
    var outputPath: String
    var sourceSizeBytes: Int64
    var outputSizeBytes: Int64
    var mode: MediaConversionMode
    var targetContainer: MediaContainer
    var transcodeSettings: MediaTranscodeSettings?
    var projectContext: ToolProjectContext?
    var ffmpegArguments: [String]
    var sourceProbe: ProbedMedia
    var outputProbe: ProbedMedia
    var compatibility: CompatibilityResult
    var reencodesVideo: Bool
    var reencodesAudio: Bool
    var verification: MediaVerificationResult
    var warnings: [CompatibilityRisk]
    var errors: [String]
}
