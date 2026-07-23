import CryptoKit
import Foundation

struct MediaVerificationService {
    let language: AppLanguage
    let configuredFFmpegPath: String

    func verify(
        source: ProbedMedia,
        outputURL: URL,
        mode: MediaConversionMode,
        transcodeSettings: MediaTranscodeSettings = .default
    ) async throws -> (ProbedMedia, MediaVerificationResult) {
        let probeService = MediaProbeService(language: language)
        let output: ProbedMedia = try await Task.detached(priority: .utility) {
            switch probeService.probeSync(url: outputURL, configuredFFmpegPath: configuredFFmpegPath) {
            case .success(let media): return media
            case .failure(let error): throw error
            }
        }.value

        let structure = structureCheck(
            source: source,
            output: output,
            mode: mode,
            transcodeSettings: transcodeSettings
        )
        guard structure.blocking.isEmpty else {
            return (output, MediaVerificationResult(
                passed: false,
                level: .structureOnly,
                hasMetadataWarnings: !structure.warnings.isEmpty,
                sourceSignature: nil,
                outputSignature: nil,
                messages: structure.blocking + structure.warnings,
                verifiedAt: Date()
            ))
        }

        if mode == .rewrap {
            let sourcePacket = try await packetSignature(media: source)
            let outputPacket = try await packetSignature(media: output)
            if sourcePacket == outputPacket {
                return (output, MediaVerificationResult(
                    passed: true,
                    level: .packetPayload,
                    hasMetadataWarnings: !structure.warnings.isEmpty,
                    sourceSignature: sourcePacket,
                    outputSignature: outputPacket,
                    messages: [L10n.t("所有映射流的压缩包负载哈希一致", "Compressed packet payload hashes match for all mapped streams", language: language)] + structure.warnings,
                    verifiedAt: Date()
                ))
            }
            // Some muxers legitimately repartition packets. Compare decoded
            // content before declaring a failure.
            let sourceDecoded = try await decodedSignatures(media: source)
            let outputDecoded = try await decodedSignatures(media: output)
            return (output, MediaVerificationResult(
                passed: sourceDecoded == outputDecoded,
                level: .decodedContent,
                hasMetadataWarnings: !structure.warnings.isEmpty,
                sourceSignature: sourceDecoded,
                outputSignature: outputDecoded,
                messages: [sourceDecoded == outputDecoded
                    ? L10n.t("封装改变了包边界，但解码后内容哈希一致", "Packet boundaries changed, but decoded-content hashes match", language: language)
                    : L10n.t("解码后内容哈希不一致", "Decoded-content hashes do not match", language: language)] + structure.warnings,
                verifiedAt: Date()
            ))
        }

        if mode == .transcode {
            return (output, MediaVerificationResult(
                passed: true,
                level: .structureOnly,
                hasMetadataWarnings: !structure.warnings.isEmpty,
                sourceSignature: nil,
                outputSignature: nil,
                messages: [L10n.t(
                    "输出可正常解码，编码、画幅、时长与音频结构已复核",
                    "Output decodes successfully; codec, frame, duration, and audio structure were verified",
                    language: language
                )] + structure.warnings,
                verifiedAt: Date()
            ))
        }

        let sourceDecoded = try await decodedSignatures(media: source, audioOnly: true)
        let outputDecoded = try await decodedSignatures(media: output, audioOnly: true)
        return (output, MediaVerificationResult(
            passed: sourceDecoded == outputDecoded,
            level: .decodedContent,
            hasMetadataWarnings: !structure.warnings.isEmpty,
            sourceSignature: sourceDecoded,
            outputSignature: outputDecoded,
            messages: [sourceDecoded == outputDecoded
                ? L10n.t("规范化 PCM 内容哈希一致", "Canonical PCM content hashes match", language: language)
                : L10n.t("规范化 PCM 内容哈希不一致", "Canonical PCM content hashes do not match", language: language)] + structure.warnings,
            verifiedAt: Date()
        ))
    }

    private struct StructureCheck {
        var blocking: [String] = []
        var warnings: [String] = []
    }

    private func structureCheck(
        source: ProbedMedia,
        output: ProbedMedia,
        mode: MediaConversionMode,
        transcodeSettings: MediaTranscodeSettings
    ) -> StructureCheck {
        var check = StructureCheck()
        switch mode {
        case .rewrap:
            let sourceStreams = source.streams.filter {
                $0.kind == .video || $0.kind == .audio || $0.kind == .subtitle
            }
            let outputStreams = output.streams.filter {
                $0.kind == .video || $0.kind == .audio || $0.kind == .subtitle
            }
            guard sourceStreams.count == outputStreams.count else {
                check.blocking.append(L10n.t("输出的主要媒体流数量与输入不一致", "Output primary media stream count differs from input", language: language))
                return check
            }
            for (position, pair) in zip(sourceStreams, outputStreams).enumerated() {
                let input = pair.0
                let result = pair.1
                let label = L10n.t("第 \(position + 1) 条流", "Stream \(position + 1)", language: language)
                if input.kind != result.kind || input.codecName.lowercased() != result.codecName.lowercased() {
                    check.blocking.append(L10n.t("\(label)的类型或编码发生变化", "\(label) changed type or codec", language: language))
                    continue
                }
                if input.profile != result.profile, !input.profile.isEmpty, !result.profile.isEmpty {
                    check.blocking.append(L10n.t("\(label)的编码 Profile 发生变化", "\(label) codec profile changed", language: language))
                }
                if input.isVideo {
                    if input.width != result.width || input.height != result.height || input.pixFmt != result.pixFmt || input.bitDepth != result.bitDepth {
                        check.blocking.append(L10n.t("\(label)的分辨率、像素格式或位深发生变化", "\(label) resolution, pixel format, or bit depth changed", language: language))
                    }
                    if input.avgFrameRate != result.avgFrameRate, !input.avgFrameRate.isEmpty, !result.avgFrameRate.isEmpty {
                        check.blocking.append(L10n.t("\(label)的帧率发生变化", "\(label) frame rate changed", language: language))
                    }
                    if [input.colorRange, input.colorSpace, input.colorTransfer, input.colorPrimaries, input.rotation]
                        != [result.colorRange, result.colorSpace, result.colorTransfer, result.colorPrimaries, result.rotation] {
                        check.warnings.append(L10n.t("\(label)的色彩或旋转标签存在差异", "\(label) color or rotation tags differ", language: language))
                    }
                }
                if input.isAudio {
                    if input.sampleRate != result.sampleRate || input.channels != result.channels || input.bitDepth != result.bitDepth {
                        check.blocking.append(L10n.t("\(label)的采样率、声道数或位深发生变化", "\(label) sample rate, channel count, or bit depth changed", language: language))
                    }
                    if input.channelLayout != result.channelLayout, !input.channelLayout.isEmpty, !result.channelLayout.isEmpty {
                        check.warnings.append(L10n.t("\(label)的声道布局标签存在差异", "\(label) channel-layout tag differs", language: language))
                    }
                }
                if input.timeBase != result.timeBase, !input.timeBase.isEmpty, !result.timeBase.isEmpty {
                    check.warnings.append(L10n.t("\(label)的容器时基发生变化，内容哈希仍会独立复核", "\(label) container time base changed; content hashes are verified independently", language: language))
                }
                if input.tagTimecode != result.tagTimecode {
                    check.warnings.append(L10n.t("\(label)的 timecode 标签存在差异", "\(label) timecode tag differs", language: language))
                }
            }
            if source.chapters.count != output.chapters.count {
                check.blocking.append(L10n.t("章节数量发生变化", "Chapter count changed", language: language))
            }
            if source.hasQuickTimeTimecodeTrack != output.hasQuickTimeTimecodeTrack {
                check.warnings.append(L10n.t("QuickTime Timecode 轨保留状态发生变化", "QuickTime timecode-track retention changed", language: language))
            }
            return check
        case .transcode:
            guard let video = output.videoStreams.first else {
                check.blocking.append(L10n.t("输出缺少视频流", "Output has no video stream", language: language))
                return check
            }
            if !transcodeSettings.videoCodec.probedCodecNames.contains(video.codecName.lowercased()) {
                check.blocking.append(L10n.t(
                    "输出视频编码与所选编码不一致",
                    "Output video codec does not match the selected codec",
                    language: language
                ))
            }
            if let targetHeight = transcodeSettings.scale.targetHeight, video.height > targetHeight {
                check.blocking.append(L10n.t(
                    "输出分辨率高于所选上限",
                    "Output resolution exceeds the selected limit",
                    language: language
                ))
            }
            if transcodeSettings.audioCodec == .none, !output.audioStreams.isEmpty {
                check.blocking.append(L10n.t("输出包含未要求的音频流", "Output contains an unexpected audio stream", language: language))
            }
            if transcodeSettings.audioCodec != .none,
               !source.audioStreams.isEmpty,
               output.audioStreams.isEmpty {
                check.blocking.append(L10n.t("输出缺少音频流", "Output is missing audio", language: language))
            }
            if let sourceDuration = source.durationSeconds,
               let outputDuration = output.durationSeconds,
               abs(sourceDuration - outputDuration) > max(0.25, sourceDuration * 0.01) {
                check.blocking.append(L10n.t("输出时长与输入不一致", "Output duration differs from the source", language: language))
            }
            return check
        case .losslessAudio:
            guard let input = source.audioStreams.first, let result = output.audioStreams.first,
                  output.audioStreams.count == 1 else {
                check.blocking.append(L10n.t("输出音频流结构异常", "Unexpected output audio stream structure", language: language))
                return check
            }
            if input.sampleRate != result.sampleRate {
                check.blocking.append(L10n.t("采样率发生变化", "Sample rate changed", language: language))
            }
            if input.channels != result.channels {
                check.blocking.append(L10n.t("声道数量发生变化", "Channel count changed", language: language))
            }
            if input.channelLayout != result.channelLayout, !input.channelLayout.isEmpty, !result.channelLayout.isEmpty {
                check.warnings.append(L10n.t("声道布局标签存在差异", "Channel-layout tag differs", language: language))
            }
            return check
        }
    }

    private func packetSignature(media: ProbedMedia) async throws -> String {
        let probe = MediaProbeService(language: language)
        guard let executable = probe.ffprobeURL(configuredFFmpegPath: configuredFFmpegPath) else {
            throw MediaConversionError.dependencyMissing
        }
        let streamGroups: [(String, [ProbedStream])] = [
            ("v", media.videoStreams),
            ("a", media.audioStreams),
            ("s", media.subtitleStreams)
        ]
        var signatures: [String] = []
        for (prefix, streams) in streamGroups {
            for ordinal in streams.indices {
                let result = try await MediaProcessRunner.run(executableURL: executable, arguments: [
                    "-v", "error",
                    "-select_streams", "\(prefix):\(ordinal)",
                    "-show_packets",
                    "-show_data_hash", "sha256",
                    "-show_entries", "packet=size,data_hash",
                    "-of", "compact=p=0:nk=1",
                    media.url.path
                ])
                guard result.terminationStatus == 0 else {
                    throw MediaConversionError.verificationFailed
                }
                signatures.append("\(prefix):\(ordinal):\(Self.sha256(result.stdout))")
            }
        }
        return Self.sha256(Data(signatures.joined(separator: "\n").utf8))
    }

    private func decodedSignatures(media: ProbedMedia, audioOnly: Bool = false) async throws -> String {
        guard let executable = FFmpegLocator.executableURL(configuredPath: configuredFFmpegPath) else {
            throw MediaConversionError.dependencyMissing
        }
        let streams = media.streams.filter { stream in
            audioOnly ? stream.isAudio : (stream.isAudio || stream.isVideo)
        }
        var signatures: [String] = []
        for stream in streams {
            var arguments = ["-hide_banner", "-nostdin", "-v", "error", "-i", media.url.path, "-map", "0:\(stream.index)"]
            if stream.isAudio {
                let floating = stream.codecName.lowercased().hasPrefix("pcm_f")
                    || stream.sampleFmt.lowercased().hasPrefix("flt")
                    || stream.sampleFmt.lowercased().hasPrefix("dbl")
                arguments += ["-c:a", floating ? "pcm_f64le" : "pcm_s32le"]
            }
            arguments += ["-f", "hash", "-hash", "sha256", "-"]
            let result = try await MediaProcessRunner.run(executableURL: executable, arguments: arguments)
            guard result.terminationStatus == 0 else { throw MediaConversionError.verificationFailed }
            signatures.append("\(stream.kind.rawValue):\(result.stdoutText.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return Self.sha256(Data(signatures.joined(separator: "\n").utf8))
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
