import SwiftUI

// MARK: - Media info summary (presentation layer over ProbedMedia)
//
// Turns parsed ffprobe data into human-readable technical lines for the
// "素材信息卡" (media info card).
//
// Hard rule: we only display what the container actually declares.
// Color fields that are not written into the file are shown as "未标记"
// (untagged) — never inferred from resolution or content. Camera Log
// flavors (S-Log3 / C-Log / V-Log …) are not recorded in the standard
// color fields at all; detecting them requires vendor-specific metadata,
// which this layer deliberately does not guess at.

struct MediaInfoSummary {
    let media: ProbedMedia
    let lang: AppLanguage

    private func t(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: lang) }

    // MARK: Duration

    /// "00:12:43" / "12:43" from format.duration (seconds).
    var durationLabel: String? {
        guard let seconds = media.durationSeconds, seconds.isFinite, seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%02d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: Video

    var primaryVideo: ProbedStream? { media.videoStreams.first }

    var resolutionLabel: String? {
        guard let v = primaryVideo, v.width > 0, v.height > 0 else { return nil }
        return "\(v.width) × \(v.height)"
    }

    /// Frame rate parsed from avg_frame_rate (fallback r_frame_rate), e.g. "25.00 fps".
    var fpsLabel: String? {
        guard let v = primaryVideo else { return nil }
        for raw in [v.avgFrameRate, v.rFrameRate] {
            if let fps = Self.parseFrameRate(raw) {
                return String(format: "%.2f fps", fps)
            }
        }
        return nil
    }

    static func parseFrameRate(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "/")
        let value: Double
        if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
            value = num / den
        } else if let v = Double(trimmed) {
            value = v
        } else {
            return nil
        }
        guard value.isFinite, value > 0, value < 1000 else { return nil }
        return value
    }

    /// "HEVC" / "ProRes" / "H.264" …
    var videoCodecLabel: String? {
        guard let v = primaryVideo, !v.codecName.isEmpty else { return nil }
        return Self.codecDisplayName(v.codecName, profile: v.profile)
    }

    /// "10-bit · yuv420p10le · 86.4 Mbps" — segments omitted when absent.
    var encodingLabel: String? {
        guard let v = primaryVideo else { return nil }
        var parts: [String] = []
        if let depth = Self.bitDepthLabel(for: v) { parts.append(depth) }
        if !v.pixFmt.isEmpty { parts.append(v.pixFmt) }
        if let br = videoBitrateLabel { parts.append(br) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Video stream bit rate, falling back to the container's overall rate.
    var videoBitrateLabel: String? {
        if let v = primaryVideo, let mbps = Self.mbps(v.bitRate) { return mbps }
        return Self.mbps(media.format.bitRate)
    }

    static func bitDepthLabel(for stream: ProbedStream) -> String? {
        let depth = stream.bitDepth.trimmingCharacters(in: .whitespaces)
        guard !depth.isEmpty, depth != "0" else { return nil }
        return "\(depth)-bit"
    }

    static func mbps(_ rawBitRate: String) -> String? {
        guard let bps = Double(rawBitRate.trimmingCharacters(in: .whitespaces)), bps > 0 else { return nil }
        return String(format: "%.1f Mbps", bps / 1_000_000)
    }

    // MARK: Color marking (declared values only — never guessed)

    /// Standard color fields as declared in the container. `nil` = untagged.
    struct ColorMarking {
        let primaries: String?  // "BT.709" / "BT.2020" / "DCI-P3" / "BT.601"
        let transfer: String?   // "BT.709" / "PQ" / "HLG" / "sRGB" / …
        let range: String?      // "Limited" / "Full" — always tagged or nil

        var isUntagged: Bool { primaries == nil && transfer == nil }

        /// "BT.2020 · HLG · Limited" for the expanded card.
        func line(untagged: String) -> String {
            if isUntagged { return untagged }
            return [primaries, transfer, range].compactMap { $0 }.joined(separator: " · ")
        }

        /// "BT.2020/HLG" for the one-line list summary.
        func compact(untagged: String) -> String {
            if isUntagged { return untagged }
            let joined = [primaries, transfer].compactMap { $0 }.joined(separator: "/")
            return joined.isEmpty ? untagged : joined
        }
    }

    var colorMarking: ColorMarking {
        guard let v = primaryVideo else {
            return ColorMarking(primaries: nil, transfer: nil, range: nil)
        }
        return ColorMarking(
            primaries: Self.mapPrimaries(v.colorPrimaries),
            transfer: Self.mapTransfer(v.colorTransfer),
            range: Self.mapRange(v.colorRange, lang: lang)
        )
    }

    var untaggedLabel: String { t("未标记", "Untagged") }

    static func mapPrimaries(_ raw: String) -> String? {
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
        case "bt709": return "BT.709"
        case "bt2020": return "BT.2020"
        case "smpte432": return "DCI-P3"
        case "smpte170m", "bt470bg", "smpte240m": return "BT.601"
        case "fcc": return "BT.601"
        default: return nil
        }
    }

    static func mapTransfer(_ raw: String) -> String? {
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
        case "bt709": return "BT.709"
        case "smpte2084": return "PQ"
        case "arib-std-b67": return "HLG"
        case "iec61966-2-1": return "sRGB"
        case "linear": return "Linear"
        case "gamma22": return "Gamma 2.2"
        case "gamma28": return "Gamma 2.8"
        case "smpte170m", "bt470bg": return "BT.601"
        case "bt2020-10", "bt2020-12": return "BT.2020"
        default: return nil
        }
    }

    static func mapRange(_ raw: String, lang: AppLanguage) -> String? {
        switch raw.lowercased().trimmingCharacters(in: .whitespaces) {
        case "tv", "limited", "mpeg": return L10n.t("Limited", "Limited", language: lang)
        case "pc", "full", "jpeg": return L10n.t("Full", "Full", language: lang)
        default: return nil
        }
    }

    /// Boundary note shown in the expanded card when color is untagged.
    var logBoundaryNote: String {
        t("色彩信息未写入容器，仅显示「未标记」，不凭画面猜测。S-Log3、C-Log、V-Log 等相机 Log 不记录在标准色彩字段中，完整识别需读取厂商元数据。",
          "Color is not written into the container, so it is shown as Untagged — never guessed from pixels. Camera Log flavors (S-Log3, C-Log, V-Log …) are not recorded in standard color fields; full detection requires vendor metadata.")
    }

    // MARK: Audio

    /// "AAC · 48 kHz · 2 声道" from the first audio stream.
    var audioLabel: String? {
        guard let a = media.audioStreams.first else { return nil }
        var parts: [String] = []
        if !a.codecName.isEmpty { parts.append(Self.codecDisplayName(a.codecName, profile: a.profile)) }
        if let rate = Self.sampleRateLabel(a.sampleRate) { parts.append(rate) }
        if let ch = Self.channelsLabel(a.channels, lang: lang) { parts.append(ch) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func sampleRateLabel(_ raw: String) -> String? {
        guard let hz = Double(raw.trimmingCharacters(in: .whitespaces)), hz > 0 else { return nil }
        let khz = hz / 1000
        return khz.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f kHz", khz)
            : String(format: "%.1f kHz", khz)
    }

    static func channelsLabel(_ raw: String, lang: AppLanguage) -> String? {
        guard let n = Int(raw.trimmingCharacters(in: .whitespaces)), n > 0 else { return nil }
        return L10n.t("\(n) 声道", "\(n) ch", language: lang)
    }

    // MARK: Timecode

    /// First declared timecode value: QuickTime tmcd track, any stream tag,
    /// then container-level tag. `nil` when the file carries none.
    var timecodeLabel: String? {
        let tcStream = media.streams.first {
            ($0.isData || $0.isAttachment)
                && ($0.codecName.lowercased() == "timecode" || $0.codecTagString.lowercased() == "tmcd")
        }
        if let tc = tcStream?.tagTimecode, !tc.isEmpty { return tc }
        for stream in media.streams {
            if let tc = stream.tagTimecode, !tc.isEmpty { return tc }
        }
        if let tc = media.format.tags["timecode"] ?? media.format.tags["TIMECODE"], !tc.isEmpty { return tc }
        return nil
    }

    // MARK: Compact one-liner (list row)
    //
    // "00:12:43 · 3840 × 2160 · 25.00 fps · HEVC · BT.2020/HLG"
    // Audio-only files lead with codec/rate/channels instead of picture info.

    var compactLine: String {
        var parts: [String] = []
        if let d = durationLabel { parts.append(d) }
        if primaryVideo != nil {
            if let r = resolutionLabel { parts.append(r.replacingOccurrences(of: " ", with: "")) }
            if let f = fpsLabel { parts.append(f.replacingOccurrences(of: " fps", with: "fps")) }
            if let c = videoCodecLabel { parts.append(c) }
            parts.append(colorMarking.compact(untagged: untaggedLabel))
        } else if let a = audioLabel {
            parts.append(a)
        }
        return parts.isEmpty ? t("暂无媒体信息", "No media info yet") : parts.joined(separator: " · ")
    }

    // MARK: Codec display names

    static func codecDisplayName(_ raw: String, profile: String) -> String {
        switch raw.lowercased() {
        case "hevc", "h265": return "HEVC"
        case "h264": return "H.264"
        case "vvc", "h266": return "H.266"
        case "prores": return profile.isEmpty ? "ProRes" : "ProRes \(profile)"
        case "dnxhd": return "DNxHD"
        case "mpeg2video": return "MPEG-2"
        case "mpeg4": return "MPEG-4"
        case "aac": return "AAC"
        case "alac": return "ALAC"
        case "flac": return "FLAC"
        case "mp3": return "MP3"
        case "opus": return "Opus"
        case "ac3": return "AC-3"
        case "eac3": return "E-AC-3"
        case let name where name.hasPrefix("pcm_"): return "PCM"
        case "timecode": return "Timecode"
        default: return raw.uppercased()
        }
    }
}

// MARK: - Expanded media info card

/// Full two-layer "素材信息卡": complete video/audio stream details,
/// timecode, and container-level technical metadata.
struct MediaInfoExpandedCard: View {
    let media: ProbedMedia
    let lang: AppLanguage
    @Environment(\.themeColors) private var colors

    private var summary: MediaInfoSummary { MediaInfoSummary(media: media, lang: lang) }
    private func t(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: lang) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(media.videoStreams.enumerated()), id: \.element.index) { position, stream in
                infoSection(title: media.videoStreams.count > 1
                            ? t("视频流 \(position + 1)", "Video Stream \(position + 1)")
                            : t("视频流", "Video Stream")) {
                    row(t("编码", "Codec"), codecDetail(stream))
                    row(t("分辨率", "Resolution"), summary.resolutionLabel)
                    row(t("帧率", "Frame Rate"), summary.fpsLabel)
                    row(t("像素格式", "Pixel Format"), pixelFormatDetail(stream))
                    row(t("码率", "Bit Rate"), summary.videoBitrateLabel)
                    row(t("色彩", "Color"), summary.colorMarking.line(untagged: summary.untaggedLabel))
                    if !stream.rotation.isEmpty, stream.rotation != "0" {
                        row(t("旋转", "Rotation"), "\(stream.rotation)°")
                    }
                }
            }

            ForEach(Array(media.audioStreams.enumerated()), id: \.element.index) { position, stream in
                infoSection(title: media.audioStreams.count > 1
                            ? t("音频流 \(position + 1)", "Audio Stream \(position + 1)")
                            : t("音频流", "Audio Stream")) {
                    row(t("编码", "Codec"), codecDetail(stream))
                    row(t("采样率", "Sample Rate"), MediaInfoSummary.sampleRateLabel(stream.sampleRate))
                    row(t("声道", "Channels"), channelsDetail(stream))
                    row(t("采样格式", "Sample Format"), sampleFormatDetail(stream))
                    row(t("码率", "Bit Rate"), MediaInfoSummary.mbps(stream.bitRate))
                }
            }

            infoSection(title: t("时间码", "Timecode")) {
                row(t("起始时间码", "Start TC"), summary.timecodeLabel ?? t("无", "None"))
            }

            infoSection(title: t("技术元数据", "Technical Metadata")) {
                row(t("容器", "Container"), containerLabel)
                row(t("文件大小", "File Size"), media.sizeBytes > 0 ? formatBytes(UInt64(media.sizeBytes)) : nil)
                row(t("总码率", "Overall Bit Rate"), MediaInfoSummary.mbps(media.format.bitRate))
                row(t("时长", "Duration"), summary.durationLabel)
                row(t("流数量", "Streams"), "\(media.format.nbStreams > 0 ? media.format.nbStreams : media.streams.count)")
                if let encoder = media.format.tags["encoder"], !encoder.isEmpty {
                    row(t("封装软件", "Muxing App"), encoder)
                }
                if let creation = media.format.tags["creation_time"], !creation.isEmpty {
                    row(t("创建时间", "Creation Time"), creation)
                }
            }

            if summary.colorMarking.isUntagged, summary.primaryVideo != nil {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(colors.textTertiary)
                    Text(summary.logBoundaryNote)
                        .font(.system(size: 9))
                        .foregroundStyle(colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(colors.surfaceBg.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(colors.hairline.opacity(0.7), lineWidth: 0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func infoSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(colors.textTertiary)
            VStack(alignment: .leading, spacing: 3, content: content)
        }
    }

    private func row(_ label: String, _ value: String?) -> AnyView {
        guard let value, !value.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 86, alignment: .leading)
                Text(value)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        )
    }

    private func codecDetail(_ stream: ProbedStream) -> String {
        let name = MediaInfoSummary.codecDisplayName(stream.codecName, profile: stream.profile)
        if !stream.codecLongName.isEmpty, stream.codecLongName.lowercased() != stream.codecName.lowercased() {
            return "\(name) — \(stream.codecLongName)"
        }
        return name
    }

    private func pixelFormatDetail(_ stream: ProbedStream) -> String? {
        var parts: [String] = []
        if !stream.pixFmt.isEmpty { parts.append(stream.pixFmt) }
        if let depth = MediaInfoSummary.bitDepthLabel(for: stream) { parts.append(depth) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func channelsDetail(_ stream: ProbedStream) -> String? {
        guard let label = MediaInfoSummary.channelsLabel(stream.channels, lang: lang) else { return nil }
        if !stream.channelLayout.isEmpty, stream.channelLayout.lowercased() != "unknown" {
            return "\(label)（\(stream.channelLayout)）"
        }
        return label
    }

    private func sampleFormatDetail(_ stream: ProbedStream) -> String? {
        var parts: [String] = []
        if !stream.sampleFmt.isEmpty { parts.append(stream.sampleFmt) }
        if let depth = MediaInfoSummary.bitDepthLabel(for: stream) { parts.append(depth) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var containerLabel: String? {
        if !media.format.formatLongName.isEmpty { return media.format.formatLongName }
        return media.format.formatName.isEmpty ? nil : media.format.formatName
    }
}
