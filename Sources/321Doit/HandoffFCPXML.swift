import Foundation

// MARK: - FCPXML emitter
//
// Produces a FCPXML 1.10 bundle (PROJECT_TIME_ATTRIBUTE.fcpxmld/Info.fcpxml) and a flat
// compat .fcpxml. All `asset src` URLs reference originals/proxies via
// `media-rep` so Final Cut Pro picks them up without scanning 02_PROXY.

struct FCPXMLTime: Equatable {
    let numerator: Int64
    let denominator: Int64

    var xml: String {
        if denominator == 1 {
            return "\(numerator)s"
        }
        return "\(numerator)/\(denominator)s"
    }

    /// Build a duration covering `frames` ticks at the given rational fps.
    /// fps = fpsNumerator / fpsDenominator   (e.g. 30000/1001 = 29.97).
    /// duration = frames / fps = frames * fpsDenominator / fpsNumerator.
    static func duration(forFrames frames: Int64, fpsNumerator: Int64, fpsDenominator: Int64) -> FCPXMLTime {
        let num = frames * fpsDenominator
        let den = fpsNumerator
        return FCPXMLTime(numerator: num, denominator: den)
    }

    static func zero() -> FCPXMLTime {
        FCPXMLTime(numerator: 0, denominator: 1)
    }

    func adding(_ other: FCPXMLTime) -> FCPXMLTime {
        // a/b + c/d = (a*d + c*b) / (b*d)
        let num = numerator * other.denominator + other.numerator * denominator
        let den = denominator * other.denominator
        return FCPXMLTime(numerator: num, denominator: den).reduced()
    }

    func reduced() -> FCPXMLTime {
        let common = FCPXMLTime.gcd(abs(numerator), Int64(abs(denominator)))
        guard common > 0 else { return self }
        return FCPXMLTime(numerator: numerator / common, denominator: denominator / common)
    }

    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        var x = a
        var y = b
        while y != 0 {
            let r = x % y
            x = y
            y = r
        }
        return x
    }
}

private struct FormatKey: Hashable {
    var width: Int
    var height: Int
}

enum FCPXMLBuilder {

    /// Returns: (fcpxmldURL, compatXMLURL).
    @discardableResult
    static func write(
        manifest: HandoffManifest,
        offload: OffloadSettings,
        into directory: URL
    ) throws -> (fcpxmld: URL, compat: URL, readme: URL) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let xml = renderXML(manifest: manifest, offload: offload)

        let bundleName = OutputFileNamer.fileName(
            projectName: manifest.project.name,
            date: offload.createdAt,
            attribute: "FCP_Import",
            extension: "fcpxmld"
        )
        let bundleURL = directory.appendingPathComponent(bundleName, isDirectory: true)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let infoURL = bundleURL.appendingPathComponent("Info.fcpxml")
        try xml.write(to: infoURL, atomically: true, encoding: .utf8)

        let compatName = OutputFileNamer.fileName(
            projectName: manifest.project.name,
            date: offload.createdAt,
            attribute: "FCP_Compat",
            extension: "fcpxml"
        )
        let compatURL = directory.appendingPathComponent(compatName)
        try xml.write(to: compatURL, atomically: true, encoding: .utf8)

        let readmeURL = directory.appendingPathComponent(
            OutputFileNamer.fileName(projectName: manifest.project.name, date: offload.createdAt, attribute: "FCP_README", extension: "md")
        )
        try fcpReadme(bundleName: bundleName, compatName: compatName, hasProxies: hasProxies(in: manifest))
            .write(to: readmeURL, atomically: true, encoding: .utf8)

        return (bundleURL, compatURL, readmeURL)
    }

    private static func hasProxies(in manifest: HandoffManifest) -> Bool {
        manifest.media.contains { ($0.proxy?.exists ?? false) }
    }

    // MARK: - Render

    static func renderXML(manifest: HandoffManifest, offload: OffloadSettings) -> String {
        let frameRate = offload.handoff.frameRate.rational

        let frameDuration = FCPXMLTime(
            numerator: frameRate.denominator,
            denominator: frameRate.numerator
        )

        // ---- format resources: one per resolution + project fps, plus timeline format ----
        var resourceLines: [String] = []
        let timelineKey = FormatKey(width: manifest.project.timeline.width, height: manifest.project.timeline.height)
        var formatIDsByKey: [FormatKey: String] = [timelineKey: "r_format_001"]
        var formatOrder: [FormatKey] = [timelineKey]

        for clip in manifest.media where clip.original.hasVideo {
            let key = formatKey(for: clip, fallback: timelineKey)
            if formatIDsByKey[key] == nil {
                formatIDsByKey[key] = String(format: "r_format_%03d", formatIDsByKey.count + 1)
                formatOrder.append(key)
            }
        }

        for key in formatOrder {
            guard let formatID = formatIDsByKey[key] else { continue }
            let formatName = formatResourceName(
                width: key.width,
                height: key.height,
                frameRate: manifest.project.frameRate.display
            )
            resourceLines.append(
                "    <format id=\"\(formatID)\" name=\"\(escape(formatName))\" frameDuration=\"\(frameDuration.xml)\" width=\"\(key.width)\" height=\"\(key.height)\"/>"
            )
        }

        var assetIDForClip: [String: String] = [:]
        var formatIDForClip: [String: String] = [:]
        for (index, clip) in manifest.media.enumerated() {
            let assetID = "r_asset_\(index + 1)"
            assetIDForClip[clip.id] = assetID
            if clip.original.hasVideo {
                let key = formatKey(for: clip, fallback: timelineKey)
                formatIDForClip[clip.id] = formatIDsByKey[key]
            }
            resourceLines.append(contentsOf: renderAsset(
                clip: clip,
                assetID: assetID,
                formatID: formatIDForClip[clip.id],
                fpsNumerator: frameRate.numerator,
                fpsDenominator: frameRate.denominator
            ))
        }

        // ---- event clips ----
        var eventLines: [String] = []
        var spineLines: [String] = []
        var spineOffset = FCPXMLTime.zero()

        let sortedClips = manifest.media.sorted { lhs, rhs in
            if lhs.cardId != rhs.cardId {
                return lhs.cardId.localizedStandardCompare(rhs.cardId) == .orderedAscending
            }
            return lhs.original.filename.localizedStandardCompare(rhs.original.filename) == .orderedAscending
        }

        for clip in sortedClips {
            guard let assetID = assetIDForClip[clip.id] else { continue }
            let clipFormatID = formatIDForClip[clip.id]
            let durationFrames = clip.original.durationFrames > 0
                ? clip.original.durationFrames
                : Int64((clip.original.durationSeconds * Double(frameRate.numerator) / Double(frameRate.denominator)).rounded())
            let duration = FCPXMLTime.duration(
                forFrames: max(durationFrames, 1),
                fpsNumerator: frameRate.numerator,
                fpsDenominator: frameRate.denominator
            )
            eventLines.append(contentsOf: renderEventAssetClip(
                clip: clip,
                assetID: assetID,
                formatID: clipFormatID,
                duration: duration
            ))
            if offload.handoff.generateStarterTimeline {
                spineLines.append(contentsOf: renderSpineAssetClip(
                    clip: clip,
                    assetID: assetID,
                    duration: duration,
                    offset: spineOffset
                ))
                spineOffset = spineOffset.adding(duration)
            }
        }

        let timelineDuration = spineOffset.numerator == 0
            ? FCPXMLTime.duration(forFrames: 1, fpsNumerator: frameRate.numerator, fpsDenominator: frameRate.denominator)
            : spineOffset
        let startTC = parseTimecodeAsRationalSeconds(
            timecode: manifest.project.timeline.startTimecode,
            fpsNumerator: frameRate.numerator,
            fpsDenominator: frameRate.denominator
        )

        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<!DOCTYPE fcpxml>")
        lines.append("<fcpxml version=\"1.10\">")
        lines.append("  <resources>")
        lines.append(contentsOf: resourceLines)
        lines.append("  </resources>")
        lines.append("  <library>")
        lines.append("    <event name=\"\(escape(manifest.project.shootDay))\">")
        lines.append(contentsOf: eventLines)
        if offload.handoff.generateStarterTimeline && !spineLines.isEmpty {
            lines.append("      <project name=\"\(escape(manifest.project.timeline.name))\">")
            lines.append("        <sequence format=\"\(formatIDsByKey[timelineKey] ?? "r_format_001")\" duration=\"\(timelineDuration.xml)\" tcStart=\"\(startTC.xml)\" tcFormat=\"NDF\">")
            lines.append("          <spine>")
            lines.append(contentsOf: spineLines)
            lines.append("          </spine>")
            lines.append("        </sequence>")
            lines.append("      </project>")
        }
        lines.append("    </event>")
        lines.append("  </library>")
        lines.append("</fcpxml>")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Renderers

    private static func renderAsset(
        clip: HandoffMediaItem,
        assetID: String,
        formatID: String?,
        fpsNumerator: Int64,
        fpsDenominator: Int64
    ) -> [String] {
        var out: [String] = []
        let durationFrames = clip.original.durationFrames > 0
            ? clip.original.durationFrames
            : Int64((clip.original.durationSeconds * Double(fpsNumerator) / Double(fpsDenominator)).rounded())
        let duration = FCPXMLTime.duration(
            forFrames: max(durationFrames, 1),
            fpsNumerator: fpsNumerator,
            fpsDenominator: fpsDenominator
        )

        let audioRate = clip.original.audioSampleRate > 0 ? clip.original.audioSampleRate : 48000
        let audioChannels = clip.original.audioChannels > 0 ? clip.original.audioChannels : 2

        var attributes: [(String, String)] = [
            ("id", assetID),
            ("name", clip.original.filename),
            ("uid", clip.id),
            ("start", "0s"),
            ("duration", duration.xml),
            ("hasVideo", clip.original.hasVideo ? "1" : "0"),
            ("hasAudio", clip.original.hasAudio ? "1" : "0")
        ]
        if clip.original.hasVideo, let formatID {
            attributes.append(("format", formatID))
        }
        if clip.original.hasAudio {
            attributes.append(("audioSources", "1"))
            attributes.append(("audioChannels", String(audioChannels)))
            attributes.append(("audioRate", String(audioRate)))
        }

        out.append("    <asset \(formatAttributes(attributes))>")
        out.append("      <media-rep kind=\"original-media\" sig=\"\(escape(clip.id))_ORIGINAL\" src=\"\(escape(clip.original.fileUrl))\"/>")
        if let proxy = clip.proxy, proxy.exists {
            out.append("      <media-rep kind=\"proxy-media\" sig=\"\(escape(clip.id))_PROXY\" src=\"\(escape(proxy.fileUrl))\"/>")
        }
        out.append("    </asset>")
        return out
    }

    private static func renderEventAssetClip(
        clip: HandoffMediaItem,
        assetID: String,
        formatID: String?,
        duration: FCPXMLTime
    ) -> [String] {
        var attributes: [(String, String)] = [
            ("name", clip.original.filename),
            ("ref", assetID),
            ("duration", duration.xml)
        ]
        if clip.original.hasVideo, let formatID {
            attributes.append(("format", formatID))
        }
        var out: [String] = []
        out.append("      <asset-clip \(formatAttributes(attributes))>")
        if !clip.cardId.isEmpty {
            out.append("        <keyword start=\"0s\" duration=\"\(duration.xml)\" value=\"\(escape(clip.cardId))\"/>")
        }
        let cameraSummary = [clip.camera.vendor, clip.camera.model].filter { !$0.isEmpty }.joined(separator: " ")
        if !cameraSummary.isEmpty {
            out.append("        <keyword start=\"0s\" duration=\"\(duration.xml)\" value=\"\(escape(cameraSummary))\"/>")
        }
        
        let startXml = "0s"
        let durXml = duration.xml
        if let status = clip.metadata.status {
            if status == "ng" {
                out.append("        <rating name=\"reject\" start=\"\(startXml)\" duration=\"\(durXml)\"/>")
                out.append("        <keyword start=\"\(startXml)\" duration=\"\(durXml)\" value=\"NG\"/>")
            } else if status == "hold" || status == "kp" {
                out.append("        <rating name=\"favorite\" start=\"\(startXml)\" duration=\"\(durXml)\"/>")
                out.append("        <keyword start=\"\(startXml)\" duration=\"\(durXml)\" value=\"KP\"/>")
            } else if status == "good" || status == "ok" {
                out.append("        <keyword start=\"\(startXml)\" duration=\"\(durXml)\" value=\"OK\"/>")
            }
        }
        
        if clip.metadata.isCircleTake == true {
            out.append("        <rating name=\"favorite\" start=\"\(startXml)\" duration=\"\(durXml)\"/>")
            out.append("        <keyword start=\"\(startXml)\" duration=\"\(durXml)\" value=\"Circle Take\"/>")
        }
        
        if let tags = clip.metadata.tags {
            for tag in tags {
                out.append("        <keyword start=\"\(startXml)\" duration=\"\(durXml)\" value=\"\(escape(tag))\"/>")
            }
        }

        var notesArr: [String] = ["Imported by 321Doit.", "\(clip.hashes.algorithm): \(clip.hashes.value)"]
        let note = clip.metadata.notes
        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notesArr.insert("📝 " + note, at: 0)
        }
        out.append("        <note>\(escape(notesArr.joined(separator: " ")))</note>")

        out.append("      </asset-clip>")
        return out
    }

    private static func renderSpineAssetClip(
        clip: HandoffMediaItem,
        assetID: String,
        duration: FCPXMLTime,
        offset: FCPXMLTime
    ) -> [String] {
        let attributes: [(String, String)] = [
            ("name", clip.original.filename),
            ("ref", assetID),
            ("offset", offset.xml),
            ("start", "0s"),
            ("duration", duration.xml),
            ("audioRole", "dialogue")
        ]
        
        var children: [String] = []
        let startXml = "0s"
        let durXml = duration.xml
        if let status = clip.metadata.status {
            if status == "ng" {
                children.append("              <rating name=\"reject\" start=\"\(startXml)\" duration=\"\(durXml)\"/>")
            } else if status == "hold" || status == "kp" {
                children.append("              <rating name=\"favorite\" start=\"\(startXml)\" duration=\"\(durXml)\"/>")
            }
        }
        
        if clip.metadata.isCircleTake == true {
            children.append("              <rating name=\"favorite\" start=\"\(startXml)\" duration=\"\(durXml)\"/>")
        }
        
        if children.isEmpty {
            return ["            <asset-clip \(formatAttributes(attributes))/>"]
        } else {
            var out = ["            <asset-clip \(formatAttributes(attributes))>"]
            out.append(contentsOf: children)
            out.append("            </asset-clip>")
            return out
        }
    }

    // MARK: - Helpers

    private static func formatKey(for clip: HandoffMediaItem, fallback: FormatKey) -> FormatKey {
        let width = clip.original.width > 0 ? clip.original.width : fallback.width
        let height = clip.original.height > 0 ? clip.original.height : fallback.height
        return FormatKey(width: width, height: height)
    }

    private static func formatResourceName(width: Int, height: Int, frameRate: String) -> String {
        let normalized = frameRate.replacingOccurrences(of: ".", with: "")
        return "FFVideoFormat\(width)x\(height)p\(normalized)"
    }

    private static func formatAttributes(_ attrs: [(String, String)]) -> String {
        attrs.map { "\($0.0)=\"\(escape($0.1))\"" }.joined(separator: " ")
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Convert "HH:MM:SS:FF" into FCPXML rational seconds at the given fps.
    static func parseTimecodeAsRationalSeconds(
        timecode: String,
        fpsNumerator: Int64,
        fpsDenominator: Int64
    ) -> FCPXMLTime {
        let parts = timecode.split(separator: ":")
        guard parts.count == 4,
              let hh = Int64(parts[0]),
              let mm = Int64(parts[1]),
              let ss = Int64(parts[2]),
              let ff = Int64(parts[3]) else {
            NSLog("321Doit FCPXML: invalid start timecode '%@', falling back to 01:00:00:00", timecode)
            return FCPXMLTime(numerator: 3600, denominator: 1) // 01:00:00:00 fallback
        }
        let wholeSeconds = hh * 3600 + mm * 60 + ss
        return FCPXMLTime(
            numerator: wholeSeconds * fpsNumerator + ff * fpsDenominator,
            denominator: fpsNumerator
        ).reduced()
    }

    // MARK: - README

    private static func fcpReadme(bundleName: String, compatName: String, hasProxies: Bool) -> String {
        let proxyNote: String
        if hasProxies {
            proxyNote = """
            321Doit 在 FCPXML 中已为每个素材声明 `original-media` 和 `proxy-media`，
            Final Cut Pro 不需要扫描 `02_PROXY` 目录就能识别代理。
            """
        } else {
            proxyNote = """
            该任务未生成代理。导入后可以在 Final Cut Pro 中对素材右键，
            选择 *Transcode Media… → Create Proxy Media* 自行生成代理。
            """
        }
        return """
        # Final Cut Pro 交接包 / Final Cut Pro Handoff

        由 321Doit 自动生成。包内 `\(bundleName)` 是首选导入文件，
        旁边的 `\(compatName)` 是兼容回退路径。

        ## 一键导入 / One-click Import

        在 321Doit 中点击 **发送到 Final Cut Pro** / *Send to Final Cut Pro*。
        321Doit 会用 `NSWorkspace.open` 打开 `.fcpxmld`，由 Final Cut Pro 完成 XML 导入。

        ## 手动导入 / Manual Import

        1. 打开 Final Cut Pro。
        2. 选择 *File › Import › XML…*。
        3. 选择 `\(bundleName)` 或 `\(compatName)`。
        4. Final Cut Pro 会创建 Library / Event / Project / Clips。

        ## 代理 / Proxies

        \(proxyNote)

        ## 行为说明 / Notes

        - 所有 asset src 使用绝对 file:// URL，已对中文与空格做百分号编码。
        - asset id 唯一，`uid` 稳定，重复生成不会变化。
        - duration 使用 rational seconds（例如 250/25s），不会出现浮点漂移。
        - 不会修改原始素材或代理素材，所有引用都是只读路径。
        """
    }
}
