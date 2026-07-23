import Foundation

/// Decides whether a probed source can be carried into a target container
/// **without re-encoding** (rewrap) or as a **lossless audio** conversion,
/// and produces per-stream risks. Judgements are based on actual codec
/// names from ffprobe — never on file extensions.
struct MediaCompatibilityService {
    let language: AppLanguage

    func decide(
        probed: ProbedMedia,
        mode: MediaConversionMode,
        target: MediaContainer,
        transcode: MediaTranscodeSettings = .default
    ) -> CompatibilityResult {
        switch mode {
        case .rewrap:
            return decideRewrap(probed: probed, target: target)
        case .transcode:
            return decideTranscode(probed: probed, target: target, settings: transcode)
        case .losslessAudio:
            return decideLosslessAudio(probed: probed, target: target)
        }
    }

    // MARK: - Video transcode

    private func decideTranscode(
        probed: ProbedMedia,
        target: MediaContainer,
        settings: MediaTranscodeSettings
    ) -> CompatibilityResult {
        var risks: [CompatibilityRisk] = []

        if probed.videoStreams.isEmpty {
            risks.append(blocking(
                code: "MC_NO_VIDEO_STREAM",
                zh: "输入没有可转码的视频流",
                en: "Input has no video stream to transcode",
                streamIndex: nil))
        }
        if target.isAudioOnly {
            risks.append(blocking(
                code: "MC_VIDEO_TARGET_REQUIRED",
                zh: "视频转码需要选择视频容器",
                en: "Video transcoding requires a video container",
                streamIndex: nil))
        }
        if !settings.videoCodec.supportedContainers.contains(target) {
            risks.append(blocking(
                code: "MC_CODEC_CONTAINER_PAIR",
                zh: "(settings.videoCodec.displayName) 不支持输出到 (target.displayName(language: language))",
                en: "(settings.videoCodec.displayName) is not supported in (target.displayName(language: language))",
                streamIndex: nil))
        }

        switch settings.audioCodec {
        case .pcm where target == .mp4 || target == .webm || target == .mpegts:
            risks.append(blocking(
                code: "MC_AUDIO_CONTAINER_PAIR",
                zh: "(target.displayName(language: language)) 不支持当前 PCM 输出，请选择兼容的音频编码",
                en: "(target.displayName(language: language)) does not support this PCM output; choose a compatible audio codec",
                streamIndex: nil))
        case .aac where target == .webm || target == .mxf:
            risks.append(blocking(
                code: "MC_AUDIO_CONTAINER_PAIR",
                zh: "(target.displayName(language: language)) 不支持 AAC 输出，请选择 Opus、PCM 或保留原编码",
                en: "(target.displayName(language: language)) does not support AAC output; choose Opus, PCM, or source audio",
                streamIndex: nil))
        case .opus where target != .webm && target != .mkv:
            risks.append(blocking(
                code: "MC_AUDIO_CONTAINER_PAIR",
                zh: "Opus 音频仅用于 WebM 或 MKV 输出",
                en: "Opus audio is limited to WebM or MKV output",
                streamIndex: nil))
        case .copy:
            for stream in probed.audioStreams where !Self.audioCodecs(target).contains(stream.codecName.lowercased()) {
                risks.append(blocking(
                    code: "MC_AUDIO_COPY_INCOMPATIBLE",
                    zh: "原音频编码 (stream.codecName) 无法直接写入 (target.rawValue.uppercased())，请改选 AAC 或 PCM",
                    en: "Source audio codec (stream.codecName) cannot be copied into (target.rawValue.uppercased()); choose AAC or PCM",
                    streamIndex: stream.index))
            }
        default:
            break
        }

        if !probed.subtitleStreams.isEmpty {
            risks.append(risk(
                severity: .warning,
                code: "MC_TRANSCODE_SUBTITLE_OMITTED",
                zh: "检测到字幕流；当前视频转码会保留画面与声音，但不写入字幕流",
                en: "Subtitle streams were detected. This transcode keeps picture and sound but omits subtitles",
                streamIndex: nil))
        }
        if !probed.dataStreams.isEmpty {
            risks.append(risk(
                severity: .warning,
                code: "MC_TRANSCODE_DATA_OMITTED",
                zh: "相机私有数据流不会写入转码文件；基础色彩标签与时间码标签会尽量保留",
                en: "Camera-private data streams are omitted; standard color and timecode tags are preserved where possible",
                streamIndex: nil))
        }

        return assemble(
            probed: probed,
            target: target,
            risks: risks,
            reencodesVideo: true,
            reencodesAudio: !probed.audioStreams.isEmpty && settings.audioCodec != .copy && settings.audioCodec != .none,
            subtitleRetained: false,
            dataRetained: false
        )
    }

    // MARK: - Rewrap

    private func decideRewrap(probed: ProbedMedia, target: MediaContainer) -> CompatibilityResult {
        var risks: [CompatibilityRisk] = []

        for stream in probed.streams {
            switch stream.kind {
            case .video:
                if !Self.videoCodecs(target).contains(stream.codecName.lowercased()) {
                    risks.append(blocking(
                        code: "MC_INCOMPATIBLE_CONTAINER",
                        zh: "视频编码 \(stream.codecName) 无法直接封装进 \(target.rawValue.uppercased())",
                        en: "Video codec \(stream.codecName) cannot be stream-copied into \(target.rawValue.uppercased())",
                        streamIndex: stream.index))
                }
            case .audio:
                if !Self.audioCodecs(target).contains(stream.codecName.lowercased()) {
                    risks.append(blocking(
                        code: "MC_INCOMPATIBLE_CONTAINER",
                        zh: "音频编码 \(stream.codecName) 无法直接封装进 \(target.rawValue.uppercased())",
                        en: "Audio codec \(stream.codecName) cannot be stream-copied into \(target.rawValue.uppercased())",
                        streamIndex: stream.index))
                }
            case .subtitle:
                if !Self.subtitleCodecs(target).contains(stream.codecName.lowercased()) {
                    risks.append(blocking(
                        code: "MC_INCOMPATIBLE_CONTAINER",
                        zh: "字幕编码 \(stream.codecName) 无法直接封装进 \(target.rawValue.uppercased())，需转换而非静默丢弃",
                        en: "Subtitle codec \(stream.codecName) cannot be stream-copied into \(target.rawValue.uppercased()) (conversion required, never silently dropped)",
                        streamIndex: stream.index))
                }
            case .data, .attachment:
                // Timecode / metadata tracks are not rewrappable verbatim into
                // most containers; flag as a metadata risk, not a content block.
                if stream.isQuickTimeTimecode {
                    risks.append(risk(
                        severity: target == .mov || target == .mp4 ? .info : .warning,
                        code: "MC_TIMECODE_TRACK",
                        zh: target == .mov || target == .mp4
                            ? "QuickTime Timecode 轨将按原流保留并在转换后复核"
                            : "QuickTime Timecode 轨无法等价保存，将转换为容器标签",
                        en: target == .mov || target == .mp4
                            ? "QuickTime timecode track will be mapped and verified after conversion"
                            : "QuickTime timecode track cannot be preserved equivalently and will become a container tag",
                        streamIndex: stream.index))
                } else {
                    risks.append(risk(
                        severity: .warning,
                        code: "MC_AUXILIARY_DATA_OMITTED",
                        zh: stream.isAttachment
                            ? "检测到附件流 \(stream.codecDisplayName)；转换时将忽略该附件，画面和声音不受影响，外挂字幕字体可能变化"
                            : "检测到相机附加数据流 \(stream.codecDisplayName)；转换时将忽略该私有附加流，不影响画面和声音",
                        en: stream.isAttachment
                            ? "Attachment stream \(stream.codecDisplayName) will be omitted; picture and sound are unaffected, but external subtitle fonts may change"
                            : "Camera auxiliary data stream \(stream.codecDisplayName) will be omitted; picture and sound are unaffected",
                        streamIndex: stream.index))
                }
            }
        }

        // Color metadata: usually carries through MOV/MP4/MKV; surface info.
        if let v = probed.videoStreams.first, !v.colorSpace.isEmpty || !v.colorPrimaries.isEmpty {
            risks.append(risk(
                severity: .info,
                code: "MC_COLOR_METADATA",
                zh: "色彩标签（range/transfer/matrix/primaries）将尽量保留",
                en: "Color tags (range/transfer/matrix/primaries) will be preserved where possible",
                streamIndex: v.index))
        }

        let subtitlesRetained = probed.subtitleStreams.allSatisfy {
            Self.subtitleCodecs(target).contains($0.codecName.lowercased())
        }
        let dataRetained = probed.dataStreams.allSatisfy {
            $0.isQuickTimeTimecode && (target == .mov || target == .mp4)
        }
        return assemble(probed: probed, target: target, risks: risks,
                        reencodesVideo: false, reencodesAudio: false,
                        subtitleRetained: subtitlesRetained,
                        dataRetained: dataRetained)
    }

    // MARK: - Lossless audio

    private func decideLosslessAudio(probed: ProbedMedia, target: MediaContainer) -> CompatibilityResult {
        var risks: [CompatibilityRisk] = []
        let audio = probed.audioStreams

        guard !audio.isEmpty else {
            risks.append(blocking(
                code: "MC_INCOMPATIBLE_CONTAINER",
                zh: "输入没有可转换的音频流",
                en: "Input has no audio stream to convert",
                streamIndex: nil))
            return assemble(probed: probed, target: target, risks: risks,
                            reencodesVideo: false, reencodesAudio: true,
                            subtitleRetained: false, dataRetained: false)
        }

        guard target.isAudioOnly else {
            risks.append(blocking(
                code: "MC_INCOMPATIBLE_CONTAINER",
                zh: "无损音频转换只能输出到音频容器（WAV/AIFF/FLAC/ALAC）",
                en: "Lossless audio conversion only targets audio containers (WAV/AIFF/FLAC/ALAC)",
                streamIndex: nil))
            return assemble(probed: probed, target: target, risks: risks,
                            reencodesVideo: false, reencodesAudio: true,
                            subtitleRetained: false, dataRetained: false)
        }

        // One media file may contain several independent audio programs. V1
        // intentionally does not guess whether these should be merged, split,
        // or mapped into a multi-track container. A single multi-channel stream
        // (including PolyWAV) remains fully supported.
        if audio.count > 1 {
            risks.append(blocking(
                code: "MC_MULTIPLE_AUDIO_STREAMS",
                zh: "输入包含多条独立音频流；V1 不会擅自合并或只保留第一条，请先拆分后分别转换",
                en: "The input contains multiple independent audio streams. V1 will not merge them or keep only the first; split them before conversion",
                streamIndex: nil))
        }

        for stream in audio {
            let codec = stream.codecName.lowercased()
            if !Self.losslessAudioSources.contains(codec) {
                risks.append(blocking(
                    code: "MC_INCOMPATIBLE_CONTAINER",
                    zh: "音频编码 \(codec) 不是无损可逆格式，不能用于无损音频转换",
                    en: "Audio codec \(codec) is not a mathematically reversible format; cannot lossless-convert",
                    streamIndex: stream.index))
                continue
            }
            let isFloatingPointPCM = codec.hasPrefix("pcm_f")
                || stream.sampleFmt.lowercased().hasPrefix("flt")
                || stream.sampleFmt.lowercased().hasPrefix("dbl")
            if isFloatingPointPCM && (target == .flac || target == .m4a) {
                risks.append(blocking(
                    code: "MC_INCOMPATIBLE_CONTAINER",
                    zh: "浮点 PCM 不能数学无损地转换为 \(target.rawValue.uppercased()) 的整数编码",
                    en: "Floating-point PCM cannot be mathematically lossless-converted to the integer coding used by \(target.rawValue.uppercased())",
                    streamIndex: stream.index))
                continue
            }
            // Bit depth / channel layout representability in the target.
            if !Self.canRepresentDepth(target: target, bitDepth: stream.bitDepth) {
                risks.append(blocking(
                    code: "MC_INCOMPATIBLE_CONTAINER",
                    zh: "目标 \(target.rawValue.uppercased()) 无法表示 \(stream.bitDepth) 位深，需用户明确选择转换",
                    en: "Target \(target.rawValue.uppercased()) cannot represent \(stream.bitDepth)-bit depth; explicit conversion choice required",
                    streamIndex: stream.index))
            }
            if !Self.canRepresentChannels(target: target, layout: stream.channelLayout, count: stream.channels) {
                risks.append(risk(
                    severity: .warning,
                    code: "MC_CHANNEL_LAYOUT",
                    zh: "声道布局 \(stream.channelLayout) 在目标中可能以默认布局保存",
                    en: "Channel layout \(stream.channelLayout) may be stored as a default layout in the target",
                    streamIndex: stream.index))
            }
        }

        if !probed.videoStreams.isEmpty || !probed.subtitleStreams.isEmpty || !probed.dataStreams.isEmpty {
            risks.append(risk(
                severity: .info,
                code: "MC_AUDIO_EXTRACTION",
                zh: "无损音频模式只输出音频；视频、字幕和数据流不会写入音频文件",
                en: "Lossless audio mode outputs audio only; video, subtitle and data streams are not written to the audio file",
                streamIndex: nil))
        }

        // BWF time reference / iXML / track names risk.
        if probed.format.tags["time_reference"] != nil || probed.format.tags["iXML"] != nil {
            risks.append(risk(
                severity: .warning,
                code: "MC_AUDIO_METADATA",
                zh: "BWF 时间参考 / iXML / 轨道名等专业音频元数据存在丢失风险",
                en: "BWF time reference / iXML / track-name professional metadata may be lost",
                streamIndex: nil))
        }

        return assemble(probed: probed, target: target, risks: risks,
                        reencodesVideo: false, reencodesAudio: true,
                        subtitleRetained: false, dataRetained: false)
    }

    // MARK: - Assembly

    private func assemble(
        probed: ProbedMedia, target: MediaContainer, risks: [CompatibilityRisk],
        reencodesVideo: Bool, reencodesAudio: Bool,
        subtitleRetained: Bool, dataRetained: Bool
    ) -> CompatibilityResult {
        let hasBlocking = risks.contains { $0.severity == .blocking }
        // Informational notes (for example, "timecode will be retained") are
        // confirmations, not warnings. Only an actual behavior change should
        // put the item into the warning state.
        let hasWarning = risks.contains { $0.severity == .warning }
        let verdict: CompatibilityVerdict
        if hasBlocking { verdict = .incompatible }
        else if hasWarning { verdict = .compatibleWithWarnings }
        else { verdict = .compatible }
        return CompatibilityResult(
            verdict: verdict,
            risks: risks,
            reencodesVideo: reencodesVideo,
            reencodesAudio: reencodesAudio,
            subtitleRetained: subtitleRetained,
            dataRetained: dataRetained
        )
    }

    // MARK: - Matrices

    private func blocking(code: String, zh: String, en: String, streamIndex: Int?) -> CompatibilityRisk {
        CompatibilityRisk(severity: .blocking, code: code, zh: zh, en: en, streamIndex: streamIndex)
    }
    private func risk(severity: RiskSeverity, code: String, zh: String, en: String, streamIndex: Int?) -> CompatibilityRisk {
        CompatibilityRisk(severity: severity, code: code, zh: zh, en: en, streamIndex: streamIndex)
    }

    private static func videoCodecs(_ c: MediaContainer) -> Set<String> {
        switch c {
        case .mov: return videoMov
        case .mp4: return videoMp4
        case .mkv: return videoMkv
        case .webm: return videoWebM
        case .avi: return videoAVI
        case .mpegts: return videoMpegts
        case .mxf: return videoMxf
        case .wav, .aiff, .flac, .m4a: return []
        }
    }
    private static func audioCodecs(_ c: MediaContainer) -> Set<String> {
        switch c {
        case .mov: return audioMov
        case .mp4: return audioMp4
        case .mkv: return audioMkv
        case .webm: return audioWebM
        case .avi: return audioAVI
        case .mpegts: return audioMpegts
        case .mxf: return audioMxf
        case .wav: return audioWav
        case .aiff: return audioAiff
        case .flac: return audioFlac
        case .m4a: return audioM4a
        }
    }
    private static func subtitleCodecs(_ c: MediaContainer) -> Set<String> {
        switch c {
        case .mov, .mp4: return ["mov_text", "tx3g"]
        case .mkv: return ["ass", "ssa", "subrip", "srt", "sub", "webvtt", "hdmv_pgs_subtitle", "dvd_subtitle", "dvb_subtitle"]
        case .webm: return ["webvtt"]
        case .avi: return []
        case .mpegts: return ["dvb_subtitle"]
        case .mxf: return []
        case .wav, .aiff, .flac, .m4a: return []
        }
    }

    private static let videoMov: Set<String> = [
        "h264", "hevc", "prores", "mpeg4", "mjpeg", "dvvideo", "av1", "vp9", "vp8",
        "mpeg2video", "dnxhd", "dnxhr", "png", "qtrle", "v210", "v210x"
    ]
    private static let videoMp4: Set<String> = [
        "h264", "hevc", "av1", "mpeg4", "mjpeg"
    ]
    private static let videoMpegts: Set<String> = [
        "h264", "hevc", "mpeg2video", "mpeg4", "av1", "vc1"
    ]
    private static let videoMxf: Set<String> = [
        "mpeg2video", "prores", "dnxhd", "dnxhr", "h264", "vc3"
    ]
    private static let videoMkv: Set<String> = [
        "h264", "hevc", "av1", "vp9", "vp8", "mpeg2video", "mpeg4", "prores",
        "mjpeg", "theora", "dnxhd", "dnxhr", "dvvideo", "png", "qtrle", "v210",
        "flv1", "wmv3", "vc1"
    ]
    private static let videoWebM: Set<String> = ["vp8", "vp9", "av1"]
    private static let videoAVI: Set<String> = ["h264", "mpeg4", "mjpeg", "dvvideo", "rawvideo"]

    private static let audioMov: Set<String> = [
        "aac", "ac3", "eac3", "alac", "mp3", "pcm_s16le", "pcm_s24le", "pcm_s32le",
        "pcm_s16be", "pcm_s24be", "pcm_f32le", "pcm_f64le", "sowt", "twos", "in24", "in32",
        "opus", "vorbis", "mp2"
    ]
    private static let audioMp4: Set<String> = [
        "aac", "ac3", "eac3", "alac", "mp3", "opus", "mp2"
        // NOTE: pcm_* is intentionally absent — the MP4 muxer rejects PCM.
    ]
    private static let audioMkv: Set<String> = [
        "aac", "ac3", "eac3", "alac", "mp3", "mp2", "pcm_s16le", "pcm_s24le",
        "pcm_s32le", "pcm_s16be", "pcm_s24be", "pcm_f32le", "pcm_f64le", "flac",
        "opus", "vorbis", "truehd", "dts", "dca"
    ]
    private static let audioWebM: Set<String> = ["opus", "vorbis"]
    private static let audioAVI: Set<String> = [
        "pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_u8", "mp3", "mp2", "aac", "ac3"
    ]
    private static let audioMpegts: Set<String> = [
        "aac", "ac3", "eac3", "mp2", "mp3", "opus"
    ]
    private static let audioMxf: Set<String> = [
        "pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_s16be", "pcm_s24be"
    ]
    private static let audioWav: Set<String> = [
        "pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_s16be", "pcm_s24be", "pcm_s32be",
        "pcm_u8", "pcm_f32le", "pcm_f64le", "pcm_s24le"
    ]
    private static let audioAiff: Set<String> = [
        "pcm_s16be", "pcm_s24be", "pcm_s32be", "pcm_s16le", "pcm_s24le", "pcm_u8",
        "pcm_f32be", "pcm_f64be"
    ]
    private static let audioFlac: Set<String> = [
        "flac", "pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_s16be", "pcm_s24be", "pcm_s32be"
    ]
    private static let audioM4a: Set<String> = [
        "alac", "aac"
    ]

    private static let losslessAudioSources: Set<String> = [
        "pcm_s16le", "pcm_s24le", "pcm_s32le", "pcm_s16be", "pcm_s24be", "pcm_s32be",
        "pcm_u8", "pcm_f32le", "pcm_f64le", "pcm_f32be", "pcm_f64be",
        "flac", "alac", "sowt", "twos", "in24", "in32"
    ]

    private static func canRepresentDepth(target: MediaContainer, bitDepth: String) -> Bool {
        let depth = Int(bitDepth) ?? 0
        switch target {
        case .wav, .flac:
            return [8, 16, 24, 32, 0].contains(depth)
        case .aiff:
            return [8, 16, 24, 32, 0].contains(depth)
        case .m4a: // ALAC
            return [16, 24, 0].contains(depth)
        default:
            return true
        }
    }

    private static func canRepresentChannels(target: MediaContainer, layout: String, count: String) -> Bool {
        let n = Int(count) ?? 0
        switch target {
        case .m4a: return n > 0 && n <= 8     // ALAC up to 8 channels
        case .flac: return n > 0 && n <= 8
        case .wav, .aiff: return n > 0 && n <= 18 // WAV/AIFF support many channels
        default: return true
        }
    }

}
