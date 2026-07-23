import Foundation

/// Emits an ASC MHL v2.0–compliant generation. Output goes to
/// `{outputURL}/ascmhl/`, the canonical location the official `ascmhl`
/// tool searches when invoked with the offload root.
///
/// Schema notes (intentionally minimal — chosen empirically to satisfy
/// `ascmhl info` + `ascmhl diff` exit code 0 on the reference 1.2 release):
///   - Root: `<hashlist version="2.0" xmlns="urn:ASC:MHL:v2.0">`
///   - `<creatorinfo>` requires `<creationdate>`, `<hostname>`, `<tool>`.
///   - `<processinfo>` declares the offload as `in-place` and lists the
///     gitignore-style patterns the official traverser should skip when
///     re-walking the package on verification.
///   - Each `<hash>` carries `<path size=… lastmodificationdate=…>` plus a
///     hash element named after the algorithm (`<xxh64>`, `<sha256>` …).
///   - Chain (`ascmhl_chain.xml`) holds a per-generation `<c4>` of the .mhl,
///     which the official parser uses to detect tampering of historic
///     generations on disk.
enum AscMHLv2Writer {
    /// Patterns excluded from the manifest. These cover 321Doit's report and
    /// workflow side-cars so the official `ascmhl diff` does not flag them as
    /// "files not in manifest" when verifying a freshly-written package.
    static let defaultIgnorePatterns: [String] = [
        ".DS_Store",
        "ascmhl",
        "ascmhl/",
        "03_REPORTS/",
        "04_CHECKSUMS/",
        "REPORTS/",
        "CHECKSUMS/",
        "_321Doit/",
        ".321doit/",
        "06_THUMBNAILS/",
        "02_PROXIES/",
        "05_HANDOFF/",
        "THUMBNAILS/",
        "PROXIES/",
        "INTEGRATIONS/"
    ]

    @discardableResult
    static func write(
        outputURL: URL,
        settings: OffloadSettings,
        startedAt: Date,
        endedAt: Date,
        files: [FileCopyRecord],
        target: TargetReport
    ) throws -> URL {
        let dir = OffloadPackageLayout.ascMHLRoot(
            outputURL: outputURL,
            mode: target.packageMode,
            cardNumber: settings.cardNumber
        )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let existingCount = countExistingMHL(in: dir)
        let generationNumber = existingCount + 1
        let stem = OutputFileNamer.stem(projectName: settings.projectName, date: endedAt, attribute: "MHL")
        let mhlName = String(
            format: "%04d_%@.mhl",
            generationNumber,
            stem
        )
        let mhlURL = dir.appendingPathComponent(mhlName)
        let chainURL = dir.appendingPathComponent("ascmhl_chain.xml")

        let xml = renderMHL(
            settings: settings,
            startedAt: startedAt,
            endedAt: endedAt,
            files: files,
            target: target
        )
        try xml.write(to: mhlURL, atomically: true, encoding: .utf8)

        // Rebuild the chain from the on-disk MHLs (now including the one we
        // just wrote). Doing this every time is O(n) in the C4 hash of each
        // MHL; in practice n stays at 1 for fresh offloads and grows only on
        // resumed runs, so this is fast enough not to need caching.
        let entries = try gatherChainEntries(in: dir)
        try renderChain(entries: entries).write(to: chainURL, atomically: true, encoding: .utf8)

        return mhlURL
    }

    // MARK: XML rendering

    private static func renderMHL(
        settings: OffloadSettings,
        startedAt: Date,
        endedAt: Date,
        files: [FileCopyRecord],
        target: TargetReport
    ) -> String {
        var lines: [String] = []
        lines.reserveCapacity(files.count * 4 + 32)
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<hashlist version=\"2.0\" xmlns=\"urn:ASC:MHL:v2.0\">")
        lines.append("  <creatorinfo>")
        lines.append("    <creationdate>\(iso8601String(endedAt))</creationdate>")
        let hostName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        lines.append("    <hostname>\(escapeXML(hostName))</hostname>")
        lines.append("    <tool version=\"\(escapeXML(appVersionString))\">\(escapeXML(appName))</tool>")
        if !settings.operatorName.isEmpty {
            lines.append("    <author role=\"DIT\">\(escapeXML(settings.operatorName))</author>")
        }
        if !settings.location.isEmpty {
            lines.append("    <location>\(escapeXML(settings.location))</location>")
        }
        if !settings.notes.isEmpty {
            lines.append("    <comment>\(escapeXML(settings.notes))</comment>")
        }
        lines.append("  </creatorinfo>")

        lines.append("  <processinfo>")
        lines.append("    <process>in-place</process>")
        lines.append("    <ignore>")
        for pattern in defaultIgnorePatterns {
            lines.append("      <pattern>\(escapeXML(pattern))</pattern>")
        }
        lines.append("    </ignore>")
        lines.append("  </processinfo>")

        lines.append("  <hashes>")
        let hashTag = settings.checksumAlgorithm.mhlHashType
        let hashDate = iso8601String(endedAt)
        for file in files {
            let path = OffloadPackageLayout.isLegacyLayout(outputURL: target.outputURL)
                ? destinationRelativePath(for: file, target: target)
                : file.relativePath
            let mtime = iso8601String(file.modifiedAt)
            lines.append("    <hash>")
            lines.append("      <path size=\"\(file.size)\" lastmodificationdate=\"\(mtime)\">\(escapeXML(path))</path>")
            lines.append("      <\(hashTag) action=\"original\" hashdate=\"\(hashDate)\">\(escapeXML(file.sourceHash))</\(hashTag)>")
            lines.append("    </hash>")
        }
        lines.append("  </hashes>")
        lines.append("</hashlist>")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func renderChain(entries: [(generation: Int, filename: String, c4: String)]) -> String {
        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<ascmhldirectory xmlns=\"urn:ASC:MHL:DIRECTORY:v2.0\">")
        for entry in entries {
            lines.append("  <hashlist sequencenr=\"\(entry.generation)\">")
            lines.append("    <path>\(escapeXML(entry.filename))</path>")
            lines.append("    <c4>\(escapeXML(entry.c4))</c4>")
            lines.append("  </hashlist>")
        }
        lines.append("</ascmhldirectory>")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: Chain bookkeeping

    private static func countExistingMHL(in directory: URL) -> Int {
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return entries.filter { $0.pathExtension.lowercased() == "mhl" }.count
    }

    private static func gatherChainEntries(in directory: URL) throws -> [(generation: Int, filename: String, c4: String)] {
        let entries = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let mhls = entries
            .filter { $0.pathExtension.lowercased() == "mhl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var out: [(generation: Int, filename: String, c4: String)] = []
        for url in mhls {
            let name = url.lastPathComponent
            let prefix = String(name.prefix(4))
            guard let n = Int(prefix) else { continue }
            let c4 = try C4Hash.hashFile(at: url)
            out.append((n, name, c4))
        }
        return out
    }

    // MARK: Path helpers

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
}
