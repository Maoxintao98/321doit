import AppKit
import Foundation

enum StoryboardIssueSeverity: Int, Codable, CaseIterable {
    case information
    case warning
    case severe
    case blocking
}

enum StoryboardIssueCategory: String, Codable {
    case continuity
    case timing
    case space
    case production
    case data
}

struct StoryboardAnalysisIssue: Identifiable, Codable, Equatable {
    var id: UUID
    var severity: StoryboardIssueSeverity
    var category: StoryboardIssueCategory
    var title: String
    var detail: String
    var sceneID: UUID?
    var shotIDs: [UUID]

    init(
        id: UUID = UUID(),
        severity: StoryboardIssueSeverity,
        category: StoryboardIssueCategory,
        title: String,
        detail: String,
        sceneID: UUID? = nil,
        shotIDs: [UUID] = []
    ) {
        self.id = id
        self.severity = severity
        self.category = category
        self.title = title
        self.detail = detail
        self.sceneID = sceneID
        self.shotIDs = shotIDs
    }
}

enum StoryboardAnalysisEngine {
    static func analyze(document: StoryboardDocument, language: AppLanguage = .system) -> [StoryboardAnalysisIssue] {
        document.scenes.flatMap { analyze(scene: $0, language: language) }
    }

    static func analyze(scene: StoryboardScene, language: AppLanguage = .system) -> [StoryboardAnalysisIssue] {
        var issues: [StoryboardAnalysisIssue] = []
        let duration = scene.shots.reduce(0) { $0 + $1.durationSeconds }
        if let target = scene.targetDurationSeconds, duration > target {
            issues.append(StoryboardAnalysisIssue(
                severity: .warning,
                category: .timing,
                title: t("场次超过目标时长", "Scene exceeds target duration", language),
                detail: t("当前 \(format(duration)) 秒，目标 \(format(target)) 秒，超出 \(format(duration - target)) 秒。", "Current: \(format(duration))s; target: \(format(target))s; over by \(format(duration - target))s.", language),
                sceneID: scene.id,
                shotIDs: scene.shots.map(\.id)
            ))
        }
        if scene.shots.isEmpty {
            issues.append(StoryboardAnalysisIssue(
                severity: .information,
                category: .data,
                title: t("场次没有镜头", "Scene has no shots", language),
                detail: t("建立镜头后才能进行节奏、连续性和拍摄难度分析。", "Add shots before analyzing pacing, continuity, and production difficulty.", language),
                sceneID: scene.id
            ))
        }

        for shot in scene.shots {
            if shot.frame.assetID == nil && shot.annotations.isEmpty {
                issues.append(StoryboardAnalysisIssue(
                    severity: .information,
                    category: .data,
                    title: t("\(shot.shotNumber) 尚无画面", "\(shot.shotNumber) has no frame", language),
                    detail: t("可以导入图片、粘贴截图或使用导演笔建立画面。", "Import an image, paste a screenshot, or draw a frame to establish the composition.", language),
                    sceneID: scene.id,
                    shotIDs: [shot.id]
                ))
            }
            if shot.durationSeconds < 0.6 {
                issues.append(StoryboardAnalysisIssue(
                    severity: .warning,
                    category: .timing,
                    title: t("\(shot.shotNumber) 时长过短", "\(shot.shotNumber) is very short", language),
                    detail: t("少于 0.6 秒的镜头可能无法让观众识别信息。", "Shots shorter than 0.6 seconds may not give viewers enough time to read the image.", language),
                    sceneID: scene.id,
                    shotIDs: [shot.id]
                ))
            }
            if let motion = shot.cameraMotions.first, [.crane, .rise, .fall].contains(motion.kind),
               !(shot.specialEquipment ?? []).contains(where: { $0.localizedCaseInsensitiveContains("摇臂") || $0.localizedCaseInsensitiveContains("crane") }) {
                issues.append(StoryboardAnalysisIssue(
                    severity: .warning,
                    category: .production,
                    title: t("\(shot.shotNumber) 需要升降设备", "\(shot.shotNumber) needs elevation equipment", language),
                    detail: t("镜头设置了升降运动，但特殊设备中未记录摇臂或升降设备。", "The shot uses an elevation move, but no crane or lifting equipment is listed in Special Equipment.", language),
                    sceneID: scene.id,
                    shotIDs: [shot.id]
                ))
            }
            if let difficulty = shot.productionDifficulty, difficulty >= 4 {
                let equipment = (shot.specialEquipment ?? []).joined(separator: "、")
                issues.append(StoryboardAnalysisIssue(
                    severity: difficulty >= 5 ? .severe : .warning,
                    category: .production,
                    title: t("\(shot.shotNumber) 拍摄难度较高", "\(shot.shotNumber) has high production difficulty", language),
                    detail: equipment.isEmpty
                        ? t("难度标记为 \(difficulty)/5，但没有记录特殊设备或执行说明。", "Difficulty is marked \(difficulty)/5, but no special equipment or execution notes are recorded.", language)
                        : t("难度标记为 \(difficulty)/5；计划设备：\(equipment)。请在通告与机位计划中确认。", "Difficulty is marked \(difficulty)/5; planned equipment: \(equipment). Confirm it in the call sheet and camera plan.", language),
                    sceneID: scene.id,
                    shotIDs: [shot.id]
                ))
            }
            for path in shot.movementPaths where path.points.contains(where: { !(0...1).contains($0.x) || !(0...1).contains($0.y) }) {
                issues.append(StoryboardAnalysisIssue(
                    severity: .severe,
                    category: .data,
                    title: t("\(shot.shotNumber) 路径超出画布", "\(shot.shotNumber) path is outside the canvas", language),
                    detail: t("人物或摄影机路径包含无效坐标。", "A character or camera path contains invalid coordinates.", language),
                    sceneID: scene.id,
                    shotIDs: [shot.id]
                ))
            }
        }

        for index in 1..<scene.shots.count {
            let previous = scene.shots[index - 1]
            let current = scene.shots[index]
            if previous.shotSize == current.shotSize,
               previous.cameraAngle == current.cameraAngle,
               previous.cameraMotions.first?.kind == current.cameraMotions.first?.kind {
                issues.append(StoryboardAnalysisIssue(
                    severity: .information,
                    category: .continuity,
                    title: t("\(previous.shotNumber) / \(current.shotNumber) 视觉信息接近", "\(previous.shotNumber) / \(current.shotNumber) have similar visual information", language),
                    detail: t("相邻镜头景别、角度和运镜相同，可能产生重复或跳切感。", "Adjacent shots share size, angle, and movement; this may feel repetitive or like a jump cut.", language),
                    sceneID: scene.id,
                    shotIDs: [previous.id, current.id]
                ))
            }
            if let lhs = previous.screenDirection,
               let rhs = current.screenDirection,
               lhs != .neutral,
               rhs != .neutral,
               lhs != rhs {
                issues.append(StoryboardAnalysisIssue(
                    severity: .warning,
                    category: .continuity,
                    title: t("运动方向发生反转", "Screen direction reverses", language),
                    detail: t("\(previous.shotNumber) 与 \(current.shotNumber) 的屏幕方向相反，请确认是否越轴或有中性镜头过渡。", "\(previous.shotNumber) and \(current.shotNumber) have opposite screen directions. Confirm an intentional axis crossing or a neutral transition shot.", language),
                    sceneID: scene.id,
                    shotIDs: [previous.id, current.id]
                ))
            }
            let distance = abs(shotSizeRank(previous.shotSize) - shotSizeRank(current.shotSize))
            if distance == 0 {
                continue
            } else if distance >= 5 {
                issues.append(StoryboardAnalysisIssue(
                    severity: .information,
                    category: .continuity,
                    title: t("景别跨度较大", "Large shot-size jump", language),
                    detail: t("\(previous.shotNumber) 到 \(current.shotNumber) 跨越 \(distance) 个景别层级，请确认情绪跳变是否有意为之。", "\(previous.shotNumber) to \(current.shotNumber) jumps \(distance) shot-size levels. Confirm that the emotional shift is intentional.", language),
                    sceneID: scene.id,
                    shotIDs: [previous.id, current.id]
                ))
            }
        }

        if let space = scene.space {
            let forbidden = space.objects.filter { $0.kind == .forbiddenZone }
            let cameras = space.objects.filter { $0.kind == .camera }
            for camera in cameras {
                if forbidden.contains(where: { contains($0, point: camera.position) }) {
                    issues.append(StoryboardAnalysisIssue(
                        severity: .severe,
                        category: .space,
                        title: t("摄影机位于禁区", "Camera is in a restricted zone", language),
                        detail: t("机位“\(camera.label)”与禁止区域重叠，当前方案不可直接执行。", "Camera position “\(camera.label)” overlaps a restricted zone, so this setup cannot be executed as planned.", language),
                        sceneID: scene.id
                    ))
                }
            }
            if space.objects.filter({ $0.kind == .axis }).count > 1 {
                issues.append(StoryboardAnalysisIssue(
                    severity: .information,
                    category: .space,
                    title: t("场景存在多条轴线", "Scene has multiple axes", language),
                    detail: t("拍摄前请明确当前镜头组使用的主轴线。", "Before shooting, identify the primary axis for this shot group.", language),
                    sceneID: scene.id
                ))
            }
        }
        return issues
    }

    private static func contains(_ object: StoryboardSceneObject, point: StoryboardPoint) -> Bool {
        abs(point.x - object.position.x) <= object.size.width / 2 &&
        abs(point.y - object.position.y) <= object.size.height / 2
    }

    private static func shotSizeRank(_ size: StoryboardShotSize) -> Int {
        switch size {
        case .extremeWide: return 0
        case .wide: return 1
        case .full: return 2
        case .medium: return 3
        case .mediumCloseUp: return 4
        case .closeUp: return 5
        case .extremeCloseUp: return 6
        }
    }

    private static func format(_ seconds: Double) -> String {
        String(format: "%.1f", seconds)
    }

    private static func t(_ zh: String, _ en: String, _ language: AppLanguage) -> String {
        L10n.t(zh, en, language: language)
    }
}

enum StoryboardExportFormat: String, CaseIterable, Identifiable {
    case csv
    case json
    case fcpxml
    case resolveXML
    case edl
    case otio
    case contactSheet

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json, .otio: return "json"
        case .fcpxml: return "fcpxml"
        case .resolveXML: return "xml"
        case .edl: return "edl"
        case .contactSheet: return "png"
        }
    }
}

enum StoryboardExporter {
    static func data(
        for format: StoryboardExportFormat,
        document: StoryboardDocument,
        imageResolver: (UUID?) -> NSImage?
    ) throws -> Data {
        switch format {
        case .csv: return Data(csv(document).utf8)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(document)
        case .fcpxml: return Data(fcpxml(document).utf8)
        case .resolveXML: return Data(resolveXML(document).utf8)
        case .edl: return Data(edl(document).utf8)
        case .otio: return Data(otio(document).utf8)
        case .contactSheet:
            guard let data = contactSheet(document, imageResolver: imageResolver) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data
        }
    }

    static func write(
        document: StoryboardDocument,
        format: StoryboardExportFormat,
        to url: URL,
        imageResolver: (UUID?) -> NSImage?
    ) throws {
        try data(for: format, document: document, imageResolver: imageResolver)
            .write(to: url, options: .atomic)
    }

    private static func csv(_ document: StoryboardDocument) -> String {
        var rows = ["项目,场次,镜头ID,镜头号,描述,景别,角度,焦段,运镜,时长,对白/声音,导演意图,拍摄备注,预计条次,设备"]
        for scene in document.scenes {
            for shot in scene.shots {
                let structuredCues = shot.audioCues.map(\.text).joined(separator: " / ")
                let soundNotes = [shot.soundDescription ?? "", structuredCues]
                    .filter { !$0.isEmpty }
                    .joined(separator: " / ")
                rows.append([
                    document.title,
                    scene.sceneNumber,
                    shot.id.uuidString,
                    shot.shotNumber,
                    StoryboardMarkdownRendering.plainText(from: shot.description),
                    shot.shotSize.rawValue,
                    shot.cameraAngle.rawValue,
                    shot.lens,
                    shot.cameraMotions.first?.kind.rawValue ?? "locked",
                    String(format: "%.2f", shot.durationSeconds),
                    soundNotes,
                    shot.directorIntent ?? "",
                    shot.notes,
                    shot.expectedTakes.map(String.init) ?? "",
                    (shot.specialEquipment ?? []).joined(separator: " / ")
                ].map(csvCell).joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func fcpxml(_ document: StoryboardDocument) -> String {
        let gaps = document.scenes.flatMap(\.shots).map { shot in
            "<gap name=\"\(xml(shot.shotNumber)) \(xml(StoryboardMarkdownRendering.plainText(from: shot.description)))\" duration=\"\(time(shot.durationSeconds))\" start=\"0s\"><note>\(xml(StoryboardMarkdownRendering.plainText(from: shot.notes)))</note></gap>"
        }.joined(separator: "\n")
        let total = document.scenes.flatMap(\.shots).reduce(0) { $0 + $1.durationSeconds }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.10"><resources><format id="r1" name="FFVideoFormat1080p25" frameDuration="1/25s" width="1920" height="1080"/></resources><library><event name="\(xml(document.title))"><project name="\(xml(document.title))"><sequence format="r1" duration="\(time(total))"><spine>\(gaps)</spine></sequence></project></event></library></fcpxml>
        """
    }

    private static func resolveXML(_ document: StoryboardDocument) -> String {
        var startFrame = 0
        let items = document.scenes.flatMap(\.shots).enumerated().map { offset, shot -> String in
            let frames = max(1, Int((shot.durationSeconds * 25).rounded()))
            defer { startFrame += frames }
            return "<clipitem id=\"clipitem-\(offset + 1)\"><name>\(xml(shot.shotNumber)) \(xml(StoryboardMarkdownRendering.plainText(from: shot.description)))</name><duration>\(frames)</duration><rate><timebase>25</timebase><ntsc>FALSE</ntsc></rate><start>\(startFrame)</start><end>\(startFrame + frames)</end><in>0</in><out>\(frames)</out></clipitem>"
        }.joined()
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><xmeml version=\"5\"><sequence><name>\(xml(document.title))</name><rate><timebase>25</timebase><ntsc>FALSE</ntsc></rate><media><video><track>\(items)</track></video></media></sequence></xmeml>"
    }

    private static func edl(_ document: StoryboardDocument) -> String {
        var output = "TITLE: \(document.title)\nFCM: NON-DROP FRAME\n\n"
        var cursor = 0
        for (index, shot) in document.scenes.flatMap(\.shots).enumerated() {
            let length = max(1, Int((shot.durationSeconds * 25).rounded()))
            output += String(format: "%03d  AX       V     C        %@ %@ %@ %@\n", index + 1, tc(0), tc(length), tc(cursor), tc(cursor + length))
            output += "* FROM CLIP NAME: \(shot.shotNumber) \(StoryboardMarkdownRendering.plainText(from: shot.description))\n"
            cursor += length
        }
        return output
    }

    private static func otio(_ document: StoryboardDocument) -> String {
        let children: [[String: Any]] = document.scenes.flatMap(\.shots).map { shot in
            [
                "OTIO_SCHEMA": "Clip.2",
                "name": "\(shot.shotNumber) \(StoryboardMarkdownRendering.plainText(from: shot.description))",
                "metadata": [
                    "shot_id": shot.id.uuidString,
                    "shot_size": shot.shotSize.rawValue,
                    "camera_angle": shot.cameraAngle.rawValue,
                    "camera_motion": shot.cameraMotions.first?.kind.rawValue ?? "locked"
                ],
                "source_range": [
                    "OTIO_SCHEMA": "TimeRange.1",
                    "start_time": ["OTIO_SCHEMA": "RationalTime.1", "value": 0, "rate": 25],
                    "duration": ["OTIO_SCHEMA": "RationalTime.1", "value": Int((shot.durationSeconds * 25).rounded()), "rate": 25]
                ],
                "media_reference": ["OTIO_SCHEMA": "MissingReference.1"]
            ]
        }
        let root: [String: Any] = [
            "OTIO_SCHEMA": "Timeline.1",
            "name": document.title,
            "tracks": [
                "OTIO_SCHEMA": "Stack.1",
                "children": [["OTIO_SCHEMA": "Track.1", "name": "Storyboard", "kind": "Video", "children": children]]
            ]
        ]
        let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private static func contactSheet(
        _ document: StoryboardDocument,
        imageResolver: (UUID?) -> NSImage?
    ) -> Data? {
        let shots = document.scenes.flatMap { scene in scene.shots.map { (scene.sceneNumber, $0) } }
        let columns = 3
        let cardWidth: CGFloat = 520
        let cardHeight: CGFloat = 360
        let margin: CGFloat = 36
        let header: CGFloat = 90
        let rows = max(1, Int(ceil(Double(shots.count) / Double(columns))))
        let size = NSSize(width: margin * 2 + cardWidth * CGFloat(columns), height: header + margin + cardHeight * CGFloat(rows))
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        let title = "\(document.title) · CONTACT SHEET"
        title.draw(at: NSPoint(x: margin, y: size.height - 58), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 28), .foregroundColor: NSColor.black])
        for (index, item) in shots.enumerated() {
            let row = index / columns
            let column = index % columns
            let x = margin + CGFloat(column) * cardWidth
            let y = size.height - header - CGFloat(row + 1) * cardHeight
            let imageRect = NSRect(x: x + 12, y: y + 82, width: cardWidth - 24, height: cardHeight - 100)
            NSColor(calibratedWhite: 0.94, alpha: 1).setFill(); imageRect.fill()
            if let frame = imageResolver(item.1.frame.assetID) {
                frame.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            }
            "场 \(item.0) · \(item.1.shotNumber) · \(item.1.shotSize.rawValue) · \(String(format: "%.1fs", item.1.durationSeconds))"
                .draw(at: NSPoint(x: x + 12, y: y + 52), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 15), .foregroundColor: NSColor.black])
            item.1.description.draw(in: NSRect(x: x + 12, y: y + 12, width: cardWidth - 24, height: 34), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.darkGray])
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private static func csvCell(_ value: String) -> String {
        spreadsheetSafeCSVField(value, alwaysQuote: true)
    }

    private static func xml(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func time(_ seconds: Double) -> String {
        let frames = max(1, Int((seconds * 25).rounded()))
        return "\(frames)/25s"
    }

    private static func tc(_ frames: Int) -> String {
        let fps = 25
        let hours = frames / (fps * 3600)
        let minutes = (frames / (fps * 60)) % 60
        let seconds = (frames / fps) % 60
        let remainder = frames % fps
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, remainder)
    }
}

enum StoryboardAnimaticExporter {
    static func export(
        scene: StoryboardScene,
        to outputURL: URL,
        ffmpegURL: URL,
        imageResolver: (UUID?) -> NSImage?,
        audioResolver: (UUID?) -> URL? = { _ in nil }
    ) throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("321doit-animatic-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let fps = 12
        var frameIndex = 0
        let renderedCanvases: [NSImage?] = scene.shots.map {
            renderCanvas(shot: $0, imageResolver: imageResolver)
        }
        for (shotIndex, shot) in scene.shots.enumerated() {
            let count = max(1, Int((shot.durationSeconds * Double(fps)).rounded()))
            for index in 0..<count {
                let progress = count <= 1 ? 0 : Double(index) / Double(count - 1)
                let image = renderFrame(
                    shot: shot,
                    progress: progress,
                    source: renderedCanvases[shotIndex],
                    previousSource: shotIndex > 0
                        ? renderedCanvases[shotIndex - 1]
                        : nil
                )
                guard let data = image.pngData else { throw CocoaError(.fileWriteUnknown) }
                let url = root.appendingPathComponent(String(format: "frame-%06d.png", frameIndex))
                try data.write(to: url, options: .atomic)
                frameIndex += 1
            }
        }
        guard frameIndex > 0 else { throw StoryboardCommandError.invalidValue("场次没有可导出的镜头。") }

        var audioInputs: [(url: URL, start: Double, duration: Double, volume: Double)] = []
        var shotStart = 0.0
        for shot in scene.shots {
            for cue in shot.audioCues {
                guard let url = audioResolver(cue.assetID) else { continue }
                let available = max(0.1, shot.durationSeconds - cue.startSeconds)
                let duration = cue.durationSeconds > 0 ? min(cue.durationSeconds, available) : available
                let volume: Double = cue.kind == .music ? 0.45 : cue.kind == .ambience ? 0.65 : 1
                audioInputs.append((url, shotStart + max(0, cue.startSeconds), duration, volume))
            }
            shotStart += shot.durationSeconds
        }

        let process = Process()
        process.executableURL = ffmpegURL
        var arguments = [
            "-hide_banner", "-v", "error", "-y",
            "-framerate", "\(fps)",
            "-i", root.appendingPathComponent("frame-%06d.png").path
        ]
        for input in audioInputs { arguments += ["-i", input.url.path] }
        arguments += ["-vf", "fps=24,format=yuv420p", "-c:v", "libx264"]
        if !audioInputs.isEmpty {
            var chains: [String] = []
            for (index, input) in audioInputs.enumerated() {
                let delay = max(0, Int((input.start * 1_000).rounded()))
                chains.append("[\(index + 1):a]atrim=0:\(String(format: "%.3f", input.duration)),asetpts=PTS-STARTPTS,adelay=\(delay)|\(delay),volume=\(String(format: "%.2f", input.volume))[a\(index)]")
            }
            let labels = audioInputs.indices.map { "[a\($0)]" }.joined()
            chains.append("\(labels)amix=inputs=\(audioInputs.count):duration=longest:normalize=0[aout]")
            arguments += ["-filter_complex", chains.joined(separator: ";"), "-map", "0:v:0", "-map", "[aout]", "-c:a", "aac", "-b:a", "192k", "-shortest"]
        }
        arguments += ["-movflags", "+faststart", outputURL.path]
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "FFmpeg 导出失败"
            throw StoryboardCommandError.invalidValue(detail)
        }
    }

    private static func renderFrame(
        shot: StoryboardShot,
        progress: Double,
        source: NSImage?,
        previousSource: NSImage?
    ) -> NSImage {
        let size = NSSize(width: 1280, height: 720)
        let output = NSImage(size: size)
        output.lockFocus()
        NSColor.black.setFill(); NSRect(origin: .zero, size: size).fill()

        if let source {
            let motion = shot.cameraMotions.first?.kind ?? .locked
            let scale: CGFloat
            let xOffset: CGFloat
            let yOffset: CGFloat
            switch motion {
            case .push, .dolly, .zoom:
                scale = 1 + CGFloat(progress) * 0.18; xOffset = 0; yOffset = 0
            case .pull:
                scale = 1.18 - CGFloat(progress) * 0.18; xOffset = 0; yOffset = 0
            case .pan, .truck, .follow:
                scale = 1.08; xOffset = (CGFloat(progress) - 0.5) * 150; yOffset = 0
            case .tilt, .crane, .rise:
                scale = 1.08; xOffset = 0; yOffset = (CGFloat(progress) - 0.5) * 100
            case .fall:
                scale = 1.08; xOffset = 0; yOffset = (0.5 - CGFloat(progress)) * 100
            case .orbit:
                scale = 1.08
                xOffset = sin(CGFloat(progress) * .pi * 2) * 90
                yOffset = cos(CGFloat(progress) * .pi * 2) * 40
            default:
                scale = 1; xOffset = 0; yOffset = 0
            }
            let rect = NSRect(
                x: (size.width - size.width * scale) / 2 + xOffset,
                y: (size.height - size.height * scale) / 2 + yOffset,
                width: size.width * scale,
                height: size.height * scale
            )
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else {
            NSColor(calibratedWhite: 0.12, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
        }

        let transitionWindow = 0.18
        if shot.transition == .dissolve, progress < transitionWindow, let previousSource {
            previousSource.draw(
                in: NSRect(origin: .zero, size: size),
                from: .zero,
                operation: .sourceOver,
                fraction: CGFloat(1 - progress / transitionWindow),
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
        }
        if (shot.transition == .fadeIn || shot.transition == .dipToBlack), progress < transitionWindow {
            NSColor.black.withAlphaComponent(CGFloat(1 - progress / transitionWindow)).setFill()
            NSRect(origin: .zero, size: size).fill()
        }
        if (shot.transition == .fadeOut || shot.transition == .dipToBlack), progress > 1 - transitionWindow {
            NSColor.black.withAlphaComponent(CGFloat((progress - (1 - transitionWindow)) / transitionWindow)).setFill()
            NSRect(origin: .zero, size: size).fill()
        }

        let label = "\(shot.shotNumber)  \(StoryboardMarkdownRendering.plainText(from: shot.description))"
        label.draw(at: NSPoint(x: 38, y: 34), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 24),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor.black.withAlphaComponent(0.55)
        ])
        if let dialogue = shot.audioCues.first(where: { $0.kind == .dialogue })?.text, !dialogue.isEmpty {
            dialogue.draw(in: NSRect(x: 160, y: 72, width: 960, height: 80), withAttributes: [
                .font: NSFont.systemFont(ofSize: 27, weight: .medium),
                .foregroundColor: NSColor.white,
                .paragraphStyle: centeredParagraph()
            ])
        }
        output.unlockFocus()
        return output
    }

    private static func renderCanvas(
        shot: StoryboardShot,
        imageResolver: (UUID?) -> NSImage?
    ) -> NSImage? {
        let size = NSSize(width: 1280, height: 720)
        let hasArtwork = shot.frame.assetID != nil
            || !(shot.canvasElements ?? []).isEmpty
            || !shot.annotations.isEmpty
        guard hasArtwork else { return nil }

        let output = NSImage(size: size)
        output.lockFocus()
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        if let background = imageResolver(shot.frame.assetID) {
            drawAspectFill(background, in: NSRect(origin: .zero, size: size))
        }

        let elements = shot.canvasElements ?? []
        let layers = shot.annotationLayers ?? []
        let annotationByID = Dictionary(uniqueKeysWithValues: shot.annotations.map { ($0.id, $0) })
        var assignedAnnotationIDs = Set<UUID>()
        for reference in shot.resolvedCanvasLayerOrder {
            switch reference.kind {
            case .image:
                guard let element = elements.first(where: { $0.id == reference.id }),
                      let image = imageResolver(element.assetID) else { continue }
                drawElement(image, element: element, size: size)
            case .drawing:
                guard let layer = layers.first(where: { $0.id == reference.id }) else { continue }
                assignedAnnotationIDs.formUnion(layer.annotationIDs)
                renderAnnotations(layer.annotationIDs.compactMap { annotationByID[$0] }, size: size)
            }
        }
        renderAnnotations(shot.annotations.filter { !assignedAnnotationIDs.contains($0.id) }, size: size)
        output.unlockFocus()
        return output
    }

    private static func drawAspectFill(_ image: NSImage, in rect: NSRect) {
        guard image.size.width > 0, image.size.height > 0 else { return }
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let destination = NSRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        image.draw(in: destination, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }

    private static func drawElement(_ image: NSImage, element: StoryboardCanvasElement, size: NSSize) {
        let width = max(1, element.size.width * size.width)
        let height = max(1, element.size.height * size.height)
        let center = NSPoint(x: element.position.x * size.width, y: (1 - element.position.y) * size.height)
        let imageAspect = image.size.width / max(image.size.height, 1)
        let boxAspect = width / max(height, 1)
        let fittedSize = imageAspect > boxAspect
            ? NSSize(width: width, height: width / imageAspect)
            : NSSize(width: height * imageAspect, height: height)

        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.rotate(byDegrees: -element.rotationDegrees)
        transform.scaleX(by: element.flippedHorizontally ? -1 : 1, yBy: element.flippedVertically ? -1 : 1)
        transform.concat()
        image.draw(
            in: NSRect(x: -fittedSize.width / 2, y: -fittedSize.height / 2, width: fittedSize.width, height: fittedSize.height),
            from: .zero,
            operation: .sourceOver,
            fraction: element.opacity,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        context.restoreGraphicsState()
    }

    private static func renderAnnotations(_ annotations: [StoryboardAnnotation], size: NSSize) {
        for annotation in annotations {
            let points = annotation.points.map { NSPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height) }
            guard let first = points.first else { continue }
            let path = NSBezierPath()
            path.lineWidth = 5
            path.lineCapStyle = .round
            path.move(to: first)
            for point in points.dropFirst() { path.line(to: point) }
            NSColor(hex: annotation.colorHex).setStroke()
            path.stroke()
        }
    }

    private static func centeredParagraph() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle(); style.alignment = .center; return style
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let value = Int(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0xFF3B30
        self.init(
            red: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255,
            blue: CGFloat(value & 255) / 255,
            alpha: 1
        )
    }
}
