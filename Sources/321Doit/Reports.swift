import AppKit
import CoreGraphics
import CryptoKit
import Foundation

struct ReportOutputURLs {
    /// ASC MHL v2.0–compliant manifest. Lives at `<outputURL>/ascmhl/`, the
    /// path the official `ascmhl` tool searches when given the offload root.
    var mhlURL: URL?
    var pdfURL: URL
    var csvURL: URL?
    var jsonURL: URL?
    var txtURL: URL?
    var sidecarURL: URL?
}

enum ReportWriter {
#if DEBUG
    /// One-shot failure injection used to prove that copied media is not
    /// reported as a successful task when its mandatory reports cannot be
    /// written. This code is excluded from release builds.
    static var testInjectWriteFailure = false
#endif

    static func writeTargetReports(
        settings: OffloadSettings,
        startedAt: Date,
        endedAt: Date,
        totalFiles: Int,
        totalBytes: UInt64,
        files: [FileCopyRecord],
        target: TargetReport,
        allTargets: [TargetReport],
        logs: [String]
    ) throws -> ReportOutputURLs {
#if DEBUG
        if testInjectWriteFailure {
            testInjectWriteFailure = false
            throw CocoaError(.fileWriteUnknown)
        }
#endif
        let reportsRoot = OffloadPackageLayout.reportsRoot(outputURL: target.outputURL)
        let checksumsRoot = OffloadPackageLayout.checksumsRoot(outputURL: target.outputURL, mode: target.packageMode)
        let workflowRoot = OffloadPackageLayout.workflowRoot(outputURL: target.outputURL)
        try FileManager.default.createDirectory(at: reportsRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workflowRoot, withIntermediateDirectories: true)

        let reportDate = startedAt
        let pdfURL = reportsRoot.appendingPathComponent(
            OutputFileNamer.fileName(projectName: settings.projectName, date: reportDate, attribute: "Report", extension: "pdf")
        )

        var mhlURL: URL?
        if settings.generateAscMHL {
            // ASC MHL v2.0–compliant generation at the package root. The
            // official `ascmhl` Python tool searches `<root>/ascmhl/`, so
            // this is the path that lets third-party DIT tooling
            // (Pomfort, Silverstack, ASC reference parser) verify the
            // offload directly.
            mhlURL = try AscMHLv2Writer.write(
                outputURL: target.outputURL,
                settings: settings,
                startedAt: startedAt,
                endedAt: endedAt,
                files: files,
                target: target
            )
        }

        let mhlSHA256: String? = mhlURL.flatMap { sha256OfFile(at: $0) }

        try makePDFReport(
            url: pdfURL,
            settings: settings,
            startedAt: startedAt,
            endedAt: endedAt,
            totalFiles: totalFiles,
            totalBytes: totalBytes,
            target: target,
            allTargets: allTargets,
            files: files,
            logs: logs,
            mhlURL: mhlURL,
            mhlSHA256: mhlSHA256
        )

        let csvURL = settings.generateCSVLog ? reportsRoot.appendingPathComponent(
            OutputFileNamer.fileName(projectName: settings.projectName, date: reportDate, attribute: "ChecksumLog", extension: "csv")
        ) : nil
        if let csvURL {
            try makeCSVReport(
                settings: settings,
                startedAt: startedAt,
                endedAt: endedAt,
                files: files,
                target: target,
                allTargets: allTargets
            ).write(to: csvURL, atomically: true, encoding: .utf8)
        }

        let taskData = try makeJSONReportData(
            settings: settings,
            startedAt: startedAt,
            endedAt: endedAt,
            totalFiles: totalFiles,
            totalBytes: totalBytes,
            files: files,
            target: target,
            allTargets: allTargets,
            logs: logs
        )
        try taskData.write(to: workflowRoot.appendingPathComponent("task.json"), options: [.atomic])
        try Data("2\n".utf8).write(to: workflowRoot.appendingPathComponent("layout-version"), options: [.atomic])

        let jsonURL = settings.generateJSONLog ? reportsRoot.appendingPathComponent(
            OutputFileNamer.fileName(projectName: settings.projectName, date: reportDate, attribute: "Report", extension: "json")
        ) : nil
        if let jsonURL {
            try taskData.write(to: jsonURL, options: [.atomic])
        }

        let txtURL = settings.generateTXTBrief ? reportsRoot.appendingPathComponent(
            OutputFileNamer.fileName(projectName: settings.projectName, date: reportDate, attribute: "Brief", extension: "txt")
        ) : nil
        if let txtURL {
            try makeTXTBrief(
                settings: settings,
                startedAt: startedAt,
                endedAt: endedAt,
                totalFiles: totalFiles,
                totalBytes: totalBytes,
                files: files,
                target: target,
                allTargets: allTargets
            ).write(to: txtURL, atomically: true, encoding: .utf8)
        }

        let sidecarURL = settings.writeSidecarChecksum ? checksumsRoot.appendingPathComponent(
            OutputFileNamer.fileName(projectName: settings.projectName, date: reportDate, attribute: "Checksums", extension: "csv")
        ) : nil
        if let sidecarURL {
            try FileManager.default.createDirectory(at: checksumsRoot, withIntermediateDirectories: true)
            try makeChecksumSidecar(files: files, target: target, algorithm: settings.checksumAlgorithm)
                .write(to: sidecarURL, atomically: true, encoding: .utf8)
        }

        try logs.joined(separator: "\n").appending("\n")
            .write(to: workflowRoot.appendingPathComponent("app.log"), atomically: true, encoding: .utf8)

        return ReportOutputURLs(
            mhlURL: mhlURL,
            pdfURL: pdfURL,
            csvURL: csvURL,
            jsonURL: jsonURL,
            txtURL: txtURL,
            sidecarURL: sidecarURL
        )
    }

    private static func sha256OfFile(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func makePDFReport(
        url: URL,
        settings: OffloadSettings,
        startedAt: Date,
        endedAt: Date,
        totalFiles: Int,
        totalBytes: UInt64,
        target: TargetReport,
        allTargets: [TargetReport],
        files: [FileCopyRecord],
        logs: [String],
        mhlURL: URL?,
        mhlSHA256: String?
    ) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        let isChinese = settings.language == .zh
        let layout = PDFReportLayout(mediaBox: mediaBox)
        let paginator = PDFReportPaginator(layout: layout)

        let titleStr = isChinese ? "拷卡报告 / Offload Report" : "Offload Report"
        paginator.addParagraph(titleStr, font: .boldSystemFont(ofSize: 22), spacingAfter: 2)
        let generatedLine = isChinese
            ? "由 321Doit v\(appVersionString) (build \(appBuildNumberString)) 生成 · Generated by 321Doit v\(appVersionString)"
            : "Generated by 321Doit v\(appVersionString) (build \(appBuildNumberString))"
        paginator.addParagraph(generatedLine, color: .darkGray, spacingAfter: 14)

        let successfulFileTargets = files.flatMap(\.targetResults).filter(\.verified).count
        let failedFileTargets = files.flatMap(\.targetResults).filter { !$0.verified }.count
        let failures = files.flatMap { file in
            file.targetResults.compactMap { result -> String? in
                guard result.verified == false else { return nil }
                let targetName = URL(fileURLWithPath: result.rootPath).lastPathComponent
                return "\(targetName.isEmpty ? result.rootPath : targetName) / \(destinationRelativePath(for: file, target: target)): \(result.error ?? "Unknown failure")"
            }
        }

        let summaryRows = [
            (isChinese ? "Project / 项目" : "Project", settings.projectName),
            (isChinese ? "Card / 储存卡编号" : "Card", settings.cardNumber),
            (isChinese ? "Operator / 操作员" : "Operator", settings.operatorName),
            (isChinese ? "Camera / 摄影机编号" : "Camera", settings.camera),
            (isChinese ? "Location / 地点" : "Location", settings.location),
            (isChinese ? "Notes / 备注" : "Notes", settings.notes),
            (isChinese ? "Source / 来源" : "Source", settings.sourceURL.path),
            (isChinese ? "This target / 当前目标" : "This target", target.outputURL.path),
            (isChinese ? "Started / 开始" : "Started", humanDate(startedAt)),
            (isChinese ? "Finished / 结束" : "Finished", humanDate(endedAt)),
            (isChinese ? "Elapsed / 耗时" : "Elapsed", durationString(endedAt.timeIntervalSince(startedAt))),
            (isChinese ? "Files / 文件数" : "Files", "\(totalFiles)"),
            (isChinese ? "Total size / 总容量" : "Total size", formatBytes(totalBytes)),
            (isChinese ? "Hash / 校验算法" : "Hash", settings.checksumAlgorithm.displayName),
            (isChinese ? "Success / Failure / 成功失败" : "Success / Failure", "\(successfulFileTargets) / \(failedFileTargets)"),
            (isChinese ? "Detected card / 自动识别卡类型" : "Detected card", settings.sourceCardProfile.displayName),
            ("LUT", lutStatus(settings: settings, targets: allTargets)),
            (isChinese ? "Resume / 恢复" : "Resume", settings.resumedFromJournal ? "interrupted/resumed" : "fresh run")
        ].filter { !$0.1.isEmpty }

        for (label, value) in summaryRows {
            paginator.addKeyValue(label, value)
        }

        if settings.recordEnvironmentInReport {
            paginator.addKeyValue(isChinese ? "App / 软件版本" : "App", "\(appVersionString) (\(appBuildNumberString))")
            paginator.addKeyValue(isChinese ? "Machine / 机器名称" : "Machine", Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
            paginator.addKeyValue(isChinese ? "macOS / 系统版本" : "macOS", osVersionDisplay())
        }
        paginator.addSpacer(10)

        let tTargetStatus = isChinese ? "Target Status / 目标状态" : "Target Status"
        paginator.addSectionTitle(tTargetStatus)
        for (index, item) in allTargets.enumerated() {
            let color: NSColor = item.state == .failed ? .systemRed : .black
            paginator.addParagraph(
                "Target \(index + 1): \(item.outputURL.path) — \(item.state.rawValue)",
                font: .monospacedSystemFont(ofSize: 9, weight: .regular),
                color: color,
                lineBreakMode: .byCharWrapping
            )
            if let error = item.error {
                paginator.addParagraph("  ERROR: \(error)", font: .monospacedSystemFont(ofSize: 9, weight: .regular), color: .systemRed)
            }
            if let proxyURL = item.proxyURL {
                let tProxies = isChinese ? "ProRes proxies / 代理" : "ProRes proxies"
                paginator.addParagraph("  \(tProxies): \(item.proxyFilesCreated) files -> \(proxyURL.path)", font: .monospacedSystemFont(ofSize: 8, weight: .regular), color: .darkGray)
                if !item.proxyErrors.isEmpty {
                    let tProxyErrors = isChinese ? "Proxy errors / 代理失败" : "Proxy errors"
                    paginator.addParagraph("  \(tProxyErrors): \(item.proxyErrors.count)", font: .monospacedSystemFont(ofSize: 8, weight: .regular), color: .systemRed)
                }
            }
        }

        let proxyFailures = allTargets.flatMap { $0.proxyErrors }

        let tFailures = isChinese ? "Failures / 失败" : "Failures"
        paginator.addSpacer(8)
        paginator.addSectionTitle(tFailures)
        if failures.isEmpty && proxyFailures.isEmpty {
            paginator.addParagraph("None", color: .darkGray)
        } else {
            for failure in failures {
                paginator.addParagraph("✗ \(failure)", font: .monospacedSystemFont(ofSize: 9, weight: .regular), color: .systemRed, lineBreakMode: .byCharWrapping)
            }
            for failure in proxyFailures {
                paginator.addParagraph("✗ Proxy/LUT: \(failure)", font: .monospacedSystemFont(ofSize: 9, weight: .regular), color: .systemRed, lineBreakMode: .byCharWrapping)
            }
        }

        let tRecentLog = isChinese ? "Recent Log / 最近日志" : "Recent Log"
        paginator.addSpacer(8)
        paginator.addSectionTitle(tRecentLog)
        for line in logs.suffix(18) {
            paginator.addParagraph(line, font: .monospacedSystemFont(ofSize: 8, weight: .regular), color: .darkGray, lineBreakMode: .byCharWrapping)
        }

        paginator.addSpacer(8)
        paginator.addSectionTitle(isChinese ? "Manifest Integrity / 清单完整性" : "Manifest Integrity")
        if let mhlURL, let mhlSHA256 {
            paginator.addKeyValue(
                isChinese ? "ASC MHL v2.0" : "ASC MHL v2.0",
                URL(fileURLWithPath: mhlURL.path).lastPathComponent
            )
            paginator.addKeyValue("  SHA-256", mhlSHA256)
        } else {
            paginator.addParagraph(
                isChinese ? "MHL 未生成（已在偏好里关闭）" : "MHL not generated (disabled in preferences).",
                color: .darkGray
            )
        }

        paginator.addSpacer(8)
        paginator.addSectionTitle("File hashes / 文件 Hash")
        let orderedFiles = files.sorted { lhs, rhs in
            let lhsFailed = lhs.targetResults.contains { !$0.verified }
            let rhsFailed = rhs.targetResults.contains { !$0.verified }
            if lhsFailed != rhsFailed { return lhsFailed && !rhsFailed }
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
        for file in orderedFiles {
            let hasFailure = file.targetResults.contains { !$0.verified }
            paginator.addParagraph(
                "\(hasFailure ? "✗" : "✓") \(destinationRelativePath(for: file, target: target))",
                font: .monospacedSystemFont(ofSize: 8, weight: .regular),
                color: hasFailure ? .systemRed : .black,
                lineBreakMode: .byCharWrapping
            )
            paginator.addParagraph("  source: \(file.sourceHash)", font: .monospacedSystemFont(ofSize: 7.5, weight: .regular), color: .darkGray)
            for (targetIndex, result) in file.targetResults.enumerated() {
                let targetName = URL(fileURLWithPath: result.rootPath).lastPathComponent
                let targetLabel = targetName.isEmpty ? result.rootPath : targetName
                let marker = result.verified ? "OK" : "FAIL"
                let hash = result.hash ?? "-"
                let error = result.error.map { " error=\($0)" } ?? ""
                paginator.addParagraph(
                    "  target[\(targetIndex + 1)] \(targetLabel): \(hash) \(marker)\(error)",
                    font: .monospacedSystemFont(ofSize: 7.5, weight: .regular),
                    color: result.verified ? .darkGray : .systemRed,
                    lineBreakMode: .byCharWrapping
                )
            }
        }

        if settings.transcodeProfile.frameExtraction.enabled && settings.transcodeProfile.frameExtraction.embedInPDF {
            let framesRoot = OffloadPackageLayout.thumbnailsRoot(outputURL: target.outputURL)
            if let enumerator = FileManager.default.enumerator(at: framesRoot, includingPropertiesForKeys: nil) {
                var imageURLs: [URL] = []
                for case let fileURL as URL in enumerator {
                    if fileURL.pathExtension.lowercased() == "jpg" || fileURL.pathExtension.lowercased() == "jpeg" {
                        imageURLs.append(fileURL)
                    }
                }

                if !imageURLs.isEmpty {
                    imageURLs.sort(by: { $0.lastPathComponent < $1.lastPathComponent })
                    paginator.addSpacer(10)
                    paginator.addSectionTitle(isChinese ? "Extracted Frames / 截图导出" : "Extracted Frames")
                    paginator.addImages(imageURLs)
                }
            }
        }

        // Operator sign-off block. The PDF stays a static document, so the
        // line below is intended for either pen-and-ink signing on a printed
        // copy, or for downstream digital signing tools (e.g. Preview, Adobe
        // Acrobat) that overlay an X.509-backed signature into a free-form
        // region. Embedding a self-signed PKCS#7 here would require shipping
        // an operator certificate in app preferences — out of scope for now.
        paginator.addSpacer(14)
        paginator.addSectionTitle(isChinese ? "Operator Sign-off / 操作员签收" : "Operator Sign-off")
        paginator.addKeyValue(
            isChinese ? "Operator / 操作员" : "Operator",
            settings.operatorName.isEmpty
                ? (isChinese ? "（未填写）" : "(not provided)")
                : settings.operatorName
        )
        paginator.addParagraph(
            isChinese
                ? "签名 / Signature: ______________________________    日期 / Date: __________________"
                : "Signature: ______________________________    Date: __________________",
            font: .systemFont(ofSize: 10.5),
            spacingBefore: 4,
            spacingAfter: 4
        )
        paginator.addParagraph(
            isChinese
                ? "本签名行可在打印件上手写签字，或在数字签名工具（Preview / Adobe Acrobat）中覆盖签章。"
                : "Sign in ink on a printed copy, or overlay a digital signature using Preview / Adobe Acrobat.",
            font: .systemFont(ofSize: 8.5),
            color: .darkGray
        )

        let pages = paginator.pages
        let generatedAt = Date()
        for (index, page) in pages.enumerated() {
            context.beginPDFPage(nil)
            context.saveGState()
            context.translateBy(x: 0, y: mediaBox.height)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)

            drawPDFHeaderFooter(
                pageIndex: index,
                pageCount: pages.count,
                generatedAt: generatedAt,
                mediaBox: mediaBox,
                settings: settings,
                reportType: titleStr
            )
            for element in page.elements {
                element.draw()
            }

            NSGraphicsContext.restoreGraphicsState()
            context.restoreGState()
            context.endPDFPage()
        }

        context.closePDF()
    }

    private static func drawPDFHeaderFooter(
        pageIndex: Int,
        pageCount: Int,
        generatedAt: Date,
        mediaBox: CGRect,
        settings: OffloadSettings,
        reportType: String
    ) {
        let headerStyle = NSMutableParagraphStyle()
        headerStyle.lineBreakMode = .byTruncatingMiddle
        let header = "321Doit / \(settings.projectName) / \(settings.cardNumber) / \(reportType)"
        let headerAttr = NSAttributedString(string: header, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 9),
            .foregroundColor: NSColor.darkGray,
            .paragraphStyle: headerStyle
        ])
        headerAttr.draw(in: CGRect(x: 36, y: 20, width: mediaBox.width - 72, height: 16))
        NSColor.separatorColor.setStroke()
        NSBezierPath.strokeLine(from: NSPoint(x: 36, y: 42), to: NSPoint(x: mediaBox.width - 36, y: 42))

        let footerStyle = NSMutableParagraphStyle()
        footerStyle.alignment = .center
        footerStyle.lineBreakMode = .byTruncatingMiddle
        let footer = "Page \(pageIndex + 1) / \(pageCount)   \(humanDate(generatedAt))   321Doit \(appVersionString) (\(appBuildNumberString))"
        let footerAttr = NSAttributedString(string: footer, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: NSColor.darkGray,
            .paragraphStyle: footerStyle
        ])
        NSBezierPath.strokeLine(from: NSPoint(x: 36, y: mediaBox.height - 42), to: NSPoint(x: mediaBox.width - 36, y: mediaBox.height - 42))
        footerAttr.draw(in: CGRect(x: 36, y: mediaBox.height - 30, width: mediaBox.width - 72, height: 14))
    }

    private static func lutStatus(settings: OffloadSettings, targets: [TargetReport]) -> String {
        let profile = settings.transcodeProfile
        let lutRequested = profile.lutMode == .applyLUT || profile.lutMode == .cleanAndLUT
        guard lutRequested else { return "Not requested" }
        let path = profile.lutPath ?? ""
        if path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Requested but no LUT path configured"
        }
        let errors = targets.flatMap(\.proxyErrors).filter { $0.localizedCaseInsensitiveContains("lut") }
        if !errors.isEmpty {
            return "Failed / partial failure: \(errors.count) LUT-related errors"
        }
        let created = targets.reduce(0) { $0 + $1.proxyFilesCreated }
        if created > 0 {
            return "Applied: \(URL(fileURLWithPath: path).lastPathComponent)"
        }
        return "Requested: \(URL(fileURLWithPath: path).lastPathComponent)"
    }

    private static func makeCSVReport(
        settings: OffloadSettings,
        startedAt: Date,
        endedAt: Date,
        files: [FileCopyRecord],
        target: TargetReport,
        allTargets: [TargetReport]
    ) -> String {
        var rows: [[String]] = [[
            "project", "card_reel", "source_volume", "target_volume", "target_path",
            "started", "ended", "elapsed_seconds", "algorithm",
            "relative_path", "size", "source_hash", "target_hash", "verified", "error"
        ]]

        for file in files {
            for result in file.targetResults {
                rows.append([
                    settings.projectName,
                    settings.cardNumber,
                    settings.sourceURL.lastPathComponent,
                    URL(fileURLWithPath: result.rootPath).lastPathComponent,
                    result.outputPath,
                    iso8601String(startedAt),
                    iso8601String(endedAt),
                    String(Int(endedAt.timeIntervalSince(startedAt))),
                    settings.checksumAlgorithm.displayName,
                    destinationRelativePath(for: file, target: target),
                    String(file.size),
                    file.sourceHash,
                    result.hash ?? "",
                    result.verified ? "true" : "false",
                    result.error ?? ""
                ])
            }
        }

        return rows.map { row in row.map(csvEscape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static func makeTXTBrief(
        settings: OffloadSettings,
        startedAt: Date,
        endedAt: Date,
        totalFiles: Int,
        totalBytes: UInt64,
        files: [FileCopyRecord],
        target: TargetReport,
        allTargets: [TargetReport]
    ) -> String {
        let failures = files.flatMap(\.targetResults).filter { !$0.verified }
        return """
        321Doit Offload Brief
        Project: \(settings.projectName)
        Card / Reel: \(settings.cardNumber)
        Source volume: \(settings.sourceURL.lastPathComponent)
        Target volume: \(target.rootURL.lastPathComponent)
        Target path: \(target.outputURL.path)
        Started: \(humanDate(startedAt))
        Ended: \(humanDate(endedAt))
        Elapsed: \(durationString(endedAt.timeIntervalSince(startedAt)))
        Total files: \(totalFiles)
        Total size: \(formatBytes(totalBytes))
        Success / Failure: \(files.flatMap(\.targetResults).filter(\.verified).count) / \(failures.count)
        Checksum: \(settings.checksumAlgorithm.displayName)
        Detected card: \(settings.sourceCardProfile.displayName)
        App: \(appVersionString) (\(appBuildNumberString))
        Machine: \(Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
        macOS: \(osVersionDisplay())

        Errors:
        \(failures.isEmpty ? "None" : failures.map { "- \($0.outputPath): \($0.error ?? "Unknown")" }.joined(separator: "\n"))

        """
    }

    private static func makeChecksumSidecar(files: [FileCopyRecord], target: TargetReport, algorithm: ChecksumAlgorithm) -> String {
        var rows = [["relative_path", "algorithm", "source_hash", "size"]]
        rows += files.map { [destinationRelativePath(for: $0, target: target), algorithm.displayName, $0.sourceHash, String($0.size)] }
        return rows.map { row in row.map(csvEscape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static func makeJSONReportData(
        settings: OffloadSettings,
        startedAt: Date,
        endedAt: Date,
        totalFiles: Int,
        totalBytes: UInt64,
        files: [FileCopyRecord],
        target: TargetReport,
        allTargets: [TargetReport],
        logs: [String]
    ) throws -> Data {
        let payload = JSONTaskReport(
            schema: "com.321doit.offload-task",
            schemaVersion: 2,
            taskID: settings.taskID.uuidString,
            projectAssociationMode: settings.projectAssociationMode.rawValue,
            linkedProjectID: settings.linkedProjectID?.uuidString,
            appVersion: appVersionString,
            buildNumber: appBuildNumberString,
            machineName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            macOSVersion: osVersionDisplay(),
            projectName: settings.projectName,
            cardNumber: settings.cardNumber,
            detectedCard: settings.sourceCardProfile.displayName,
            sourcePath: settings.sourceURL.path,
            sourceVolume: settings.sourceURL.lastPathComponent,
            targetPath: target.outputURL.path,
            targetVolume: target.rootURL.lastPathComponent,
            startedAt: iso8601String(startedAt),
            endedAt: iso8601String(endedAt),
            elapsedSeconds: endedAt.timeIntervalSince(startedAt),
            totalFiles: totalFiles,
            totalBytes: totalBytes,
            checksumAlgorithm: settings.checksumAlgorithm.displayName,
            successfulResults: files.flatMap(\.targetResults).filter(\.verified).count,
            failedResults: files.flatMap(\.targetResults).filter { !$0.verified }.count,
            resumedFromJournal: settings.resumedFromJournal,
            lutStatus: lutStatus(settings: settings, targets: allTargets),
            files: files.map { file in
                JSONFileReport(
                    relativePath: destinationRelativePath(for: file, target: target),
                    size: file.size,
                    modifiedAt: iso8601String(file.modifiedAt),
                    sourceHash: file.sourceHash,
                    targets: file.targetResults.map {
                        JSONTargetFileReport(
                            rootPath: $0.rootPath,
                            outputPath: $0.outputPath,
                            copied: $0.copied,
                            verified: $0.verified,
                            targetHash: $0.hash,
                            error: $0.error
                        )
                    }
                )
            },
            errors: files.flatMap { file in
                file.targetResults.compactMap { result in
                    result.verified ? nil : "\(destinationRelativePath(for: file, target: target)): \(result.error ?? "Unknown")"
                }
            } + allTargets.flatMap(\.proxyErrors),
            logs: logs
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    private static func append(
        _ string: String,
        to text: NSMutableAttributedString,
        font: NSFont = .systemFont(ofSize: 11),
        color: NSColor = .black
    ) {
        text.append(NSAttributedString(
            string: string,
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        ))
    }

    private static func destinationRelativePath(for file: FileCopyRecord, target: TargetReport) -> String {
        if let result = file.targetResults.first(where: {
            $0.verified && $0.outputPath.hasPrefix(target.outputURL.path)
        }) {
            return OffloadPackageLayout.targetRelativePath(
                outputURL: target.outputURL,
                fileURL: URL(fileURLWithPath: result.outputPath)
            )
        }
        return file.relativePath
    }

    private static func humanDate(_ date: Date) -> String {
        humanDateFormatterLock.lock()
        defer { humanDateFormatterLock.unlock() }
        return humanDateFormatter.string(from: date)
    }

    private static let humanDateFormatterLock = NSLock()
    private static let humanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private static func durationString(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private static func csvEscape(_ value: String) -> String {
        spreadsheetSafeCSVField(value)
    }
}

private struct PDFReportLayout {
    var mediaBox: CGRect
    var marginX: CGFloat = 36
    var topY: CGFloat = 56
    var bottomY: CGFloat { mediaBox.height - 52 }
    var contentWidth: CGFloat { mediaBox.width - marginX * 2 }
}

private struct PDFReportPage {
    var elements: [PDFReportElement] = []
}

private enum PDFReportElement {
    case text(NSAttributedString, CGRect)
    case image(NSImage, CGRect, NSAttributedString, CGRect)

    func draw() {
        switch self {
        case .text(let attributed, let rect):
            attributed.draw(in: rect)
        case .image(let image, let rect, let caption, let captionRect):
            image.draw(
                in: rect,
                from: NSRect(origin: .zero, size: image.size),
                operation: .sourceOver,
                fraction: 1.0,
                respectFlipped: true,
                hints: [.interpolation: NSImageInterpolation.high]
            )
            caption.draw(in: captionRect)
        }
    }
}

private final class PDFReportPaginator {
    private let layout: PDFReportLayout
    private(set) var pages: [PDFReportPage] = [PDFReportPage()]
    private var y: CGFloat

    init(layout: PDFReportLayout) {
        self.layout = layout
        self.y = layout.topY
    }

    func addSectionTitle(_ text: String) {
        addParagraph(text, font: .boldSystemFont(ofSize: 14), spacingBefore: 4, spacingAfter: 6)
    }

    func addKeyValue(_ key: String, _ value: String) {
        addParagraph(
            "\(key): \(value)",
            font: .systemFont(ofSize: 10.5),
            color: .black,
            lineBreakMode: .byCharWrapping,
            spacingAfter: 2
        )
    }

    func addSpacer(_ height: CGFloat) {
        ensureSpace(height)
        y += height
    }

    func addParagraph(
        _ text: String,
        font: NSFont = .systemFont(ofSize: 11),
        color: NSColor = .black,
        lineBreakMode: NSLineBreakMode = .byWordWrapping,
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat = 3
    ) {
        if spacingBefore > 0 { addSpacer(spacingBefore) }
        let attributed = attributedString(text, font: font, color: color, lineBreakMode: lineBreakMode)
        var height = ceil(attributed.boundingRect(
            with: CGSize(width: layout.contentWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height)
        height = max(height, font.ascender - font.descender + 2)
        let maxContentHeight = max(24, layout.bottomY - layout.topY)
        if height > maxContentHeight {
            height = maxContentHeight
        }
        ensureSpace(height)
        let rect = CGRect(x: layout.marginX, y: y, width: layout.contentWidth, height: height)
        pages[pages.count - 1].elements.append(.text(attributed, rect))
        y += height + spacingAfter
    }

    func addImages(_ urls: [URL]) {
        let spacing: CGFloat = 12
        let columnWidth = (layout.contentWidth - spacing) / 2
        let maxImageHeight: CGFloat = 140
        var column = 0
        var rowStartY = y
        var rowHeight: CGFloat = 0

        for url in urls {
            guard let image = NSImage(contentsOf: url), image.size.width > 0 else { continue }
            let imageHeight = min(maxImageHeight, columnWidth * image.size.height / image.size.width)
            let blockHeight = imageHeight + 18
            if column == 0 {
                ensureSpace(blockHeight)
                rowStartY = y
                rowHeight = blockHeight
            } else if rowStartY + max(rowHeight, blockHeight) > layout.bottomY {
                newPage()
                rowStartY = y
                rowHeight = blockHeight
                column = 0
            }

            let x = layout.marginX + CGFloat(column) * (columnWidth + spacing)
            let imageRect = CGRect(x: x, y: rowStartY, width: columnWidth, height: imageHeight)
            let caption = attributedString(url.lastPathComponent, font: .monospacedSystemFont(ofSize: 8, weight: .regular), color: .darkGray, lineBreakMode: .byTruncatingMiddle)
            let captionRect = CGRect(x: x, y: rowStartY + imageHeight + 3, width: columnWidth, height: 12)
            pages[pages.count - 1].elements.append(.image(image, imageRect, caption, captionRect))

            rowHeight = max(rowHeight, blockHeight)
            if column == 0 {
                column = 1
            } else {
                column = 0
                y = rowStartY + rowHeight + 8
            }
        }
        if column == 1 {
            y = rowStartY + rowHeight + 8
        }
    }

    private func ensureSpace(_ needed: CGFloat) {
        if y + needed > layout.bottomY {
            newPage()
        }
    }

    private func newPage() {
        pages.append(PDFReportPage())
        y = layout.topY
    }

    private func attributedString(
        _ text: String,
        font: NSFont,
        color: NSColor,
        lineBreakMode: NSLineBreakMode
    ) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = lineBreakMode
        style.lineSpacing = 1.2
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style
        ])
    }
}

private struct JSONTaskReport: Encodable {
    var schema: String
    var schemaVersion: Int
    var taskID: String
    var projectAssociationMode: String
    var linkedProjectID: String?
    var appVersion: String
    var buildNumber: String
    var machineName: String
    var macOSVersion: String
    var projectName: String
    var cardNumber: String
    var detectedCard: String
    var sourcePath: String
    var sourceVolume: String
    var targetPath: String
    var targetVolume: String
    var startedAt: String
    var endedAt: String
    var elapsedSeconds: TimeInterval
    var totalFiles: Int
    var totalBytes: UInt64
    var checksumAlgorithm: String
    var successfulResults: Int
    var failedResults: Int
    var resumedFromJournal: Bool
    var lutStatus: String
    var files: [JSONFileReport]
    var errors: [String]
    var logs: [String]
}

private struct JSONFileReport: Encodable {
    var relativePath: String
    var size: UInt64
    var modifiedAt: String
    var sourceHash: String
    var targets: [JSONTargetFileReport]
}

private struct JSONTargetFileReport: Encodable {
    var rootPath: String
    var outputPath: String
    var copied: Bool
    var verified: Bool
    var targetHash: String?
    var error: String?
}
