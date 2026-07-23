import AppKit
import Foundation

// MARK: - Application detection

enum HandoffAppDetector {
    static let resolveBundleID = "com.blackmagic-design.DaVinciResolve"
    /// Apple currently ships both identifiers in the field. Creator Studio
    /// builds use `com.apple.FinalCutApp`; older/App Store builds use the
    /// historical `com.apple.FinalCut` identifier.
    static let finalCutBundleIDs = ["com.apple.FinalCutApp", "com.apple.FinalCut"]
    static let resolveAppPath = "/Applications/DaVinci Resolve/DaVinci Resolve.app"
    static let finalCutAppPaths = [
        "/Applications/Final Cut Pro.app",
        "/Applications/Final Cut Pro Creator Studio.app"
    ]

    static func resolveAppURL() -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: resolveBundleID) {
            return url
        }
        let path = resolveAppPath
        return FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    static func finalCutAppURL() -> URL? {
        for bundleID in finalCutBundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
               isApplication(url, acceptedBundleIDs: finalCutBundleIDs) {
                return url
            }
        }
        for path in finalCutAppPaths {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if isApplication(url, acceptedBundleIDs: finalCutBundleIDs) { return url }
        }

        // Launch Services/Spotlight can lag immediately after an install or
        // rename. Scan only the two standard Applications directories and
        // validate bundle identifiers; do not accept an app by filename alone.
        let fm = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        for root in roots {
            guard let candidates = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            if let match = candidates.first(where: {
                $0.pathExtension.lowercased() == "app" && isApplication($0, acceptedBundleIDs: finalCutBundleIDs)
            }) {
                return match
            }
        }
        return nil
    }

    static func isResolveInstalled() -> Bool { resolveAppURL() != nil }
    static func isFinalCutInstalled() -> Bool { finalCutAppURL() != nil }

    private static func isApplication(_ url: URL, acceptedBundleIDs: [String]) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier,
              acceptedBundleIDs.contains(identifier),
              let executableURL = bundle.executableURL else { return false }
        return FileManager.default.isExecutableFile(atPath: executableURL.path)
    }
}

// MARK: - Resolve launcher

struct ResolveLaunchResult {
    var ok: Bool
    var projectName: String?
    var importedOriginals: Int
    var linkedProxies: Int
    var missingProxies: [String]
    var failedProxyLinks: [String]
    var failedMedia: [String]
    var warnings: [String]
    var rawOutput: String
    var errorCode: String?
    var errorMessage: String?
}

enum HandoffResolveLauncher {

    enum LaunchError: LocalizedError {
        case appNotFound
        case scriptMissing(URL)
        case scriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .appNotFound:
                return "DaVinci Resolve not found. Install DaVinci Resolve first, or build only the handoff package."
            case .scriptMissing(let url):
                return "Resolve import script not found: \(url.path)"
            case .scriptFailed(let detail):
                return "Resolve script failed to run: \(detail)"
            }
        }
    }

    /// Launch / activate DaVinci Resolve (if installed) and run resolve_import.py.
    /// Returns the parsed result emitted by the script's `321DOIT_RESULT_BEGIN/END` block.
    static func sendToResolve(scriptURL: URL) async throws -> ResolveLaunchResult {
        guard let appURL = HandoffAppDetector.resolveAppURL() else {
            throw LaunchError.appNotFound
        }
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw LaunchError.scriptMissing(scriptURL)
        }

        try await ensureResolveRunning(appURL: appURL)
        return try await runScript(scriptURL: scriptURL)
    }

    private static func ensureResolveRunning(appURL: URL) async throws {
        let workspace = NSWorkspace.shared
        let alreadyRunning = workspace.runningApplications.contains {
            $0.bundleIdentifier == HandoffAppDetector.resolveBundleID
        }
        if !alreadyRunning {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            cfg.addsToRecentItems = false
            cfg.promptsUserIfNeeded = false
            _ = try await workspace.openApplication(at: appURL, configuration: cfg)
            // Resolve takes a few seconds before its scripting bridge accepts
            // calls. Poll up to ~20s with a soft check.
            for _ in 0..<20 {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                if workspace.runningApplications.contains(where: { $0.bundleIdentifier == HandoffAppDetector.resolveBundleID }) {
                    break
                }
            }
            // Give Resolve a moment past the splash screen even when "running" returns true.
            try await Task.sleep(nanoseconds: 3_000_000_000)
        } else {
            // Already running — bring it forward so the user sees the import.
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            _ = try await workspace.openApplication(at: appURL, configuration: cfg)
        }
    }

    private static func runScript(scriptURL: URL) async throws -> ResolveLaunchResult {
        let process = Process()
        process.launchPath = "/usr/bin/env"

        var environment = ProcessInfo.processInfo.environment
        let api = "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting"
        let lib = "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so"
        environment["RESOLVE_SCRIPT_API"] = api
        environment["RESOLVE_SCRIPT_LIB"] = lib
        let modulesPath = "\(api)/Modules"
        if let existing = environment["PYTHONPATH"], !existing.isEmpty {
            environment["PYTHONPATH"] = "\(existing):\(modulesPath)"
        } else {
            environment["PYTHONPATH"] = modulesPath
        }
        process.environment = environment
        process.arguments = ["python3", scriptURL.path]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw LaunchError.scriptFailed(error.localizedDescription)
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<ResolveLaunchResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                let stdout = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
                let stderr = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
                let combined = (String(data: stdout, encoding: .utf8) ?? "") + "\n" + (String(data: stderr, encoding: .utf8) ?? "")
                cont.resume(returning: parseResult(rawOutput: combined))
            }
        }
    }

    private static func parseResult(rawOutput: String) -> ResolveLaunchResult {
        let begin = "321DOIT_RESULT_BEGIN"
        let end = "321DOIT_RESULT_END"

        guard let beginRange = rawOutput.range(of: begin),
              let endRange = rawOutput.range(of: end, range: beginRange.upperBound..<rawOutput.endIndex) else {
            return ResolveLaunchResult(
                ok: false,
                projectName: nil,
                importedOriginals: 0,
                linkedProxies: 0,
                missingProxies: [],
                failedProxyLinks: [],
                failedMedia: [],
                warnings: [],
                rawOutput: rawOutput,
                errorCode: "RESOLVE_NOT_RUNNING",
                errorMessage: "DaVinci Resolve scripting bridge is not available."
            )
        }

        let payloadString = rawOutput[beginRange.upperBound..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = payloadString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return ResolveLaunchResult(
                ok: false,
                projectName: nil,
                importedOriginals: 0,
                linkedProxies: 0,
                missingProxies: [],
                failedProxyLinks: [],
                failedMedia: [],
                warnings: [],
                rawOutput: rawOutput,
                errorCode: "INVALID_RESULT",
                errorMessage: "Resolve script returned a malformed result."
            )
        }

        let ok = json["ok"] as? Bool ?? false
        let projectName = json["projectName"] as? String
        let importedOriginals = json["importedOriginals"] as? Int ?? 0
        let linkedProxies = json["linkedProxies"] as? Int ?? 0
        let warnings = (json["warnings"] as? [String]) ?? []
        let errorCode = json["errorCode"] as? String
        let errorMessage = json["message"] as? String

        let missingProxies: [String] = (json["missingProxies"] as? [[String: Any]] ?? []).compactMap { dict in
            guard let path = dict["proxyPath"] as? String else { return nil }
            return path
        }
        let failedProxyLinks: [String] = (json["failedProxyLinks"] as? [[String: Any]] ?? []).compactMap { dict in
            let proxy = dict["proxyPath"] as? String ?? ""
            let err = dict["error"] as? String ?? ""
            return proxy.isEmpty ? nil : "\(proxy) — \(err)"
        }
        let failedMedia: [String] = (json["failedMedia"] as? [[String: Any]] ?? []).compactMap { dict in
            let path = dict["path"] as? String ?? ""
            let reason = dict["reason"] as? String ?? ""
            return path.isEmpty ? nil : "\(path) — \(reason)"
        }

        return ResolveLaunchResult(
            ok: ok,
            projectName: projectName,
            importedOriginals: importedOriginals,
            linkedProxies: linkedProxies,
            missingProxies: missingProxies,
            failedProxyLinks: failedProxyLinks,
            failedMedia: failedMedia,
            warnings: warnings,
            rawOutput: rawOutput,
            errorCode: errorCode,
            errorMessage: errorMessage
        )
    }
}

// MARK: - Final Cut Pro launcher

enum HandoffFinalCutLauncher {

    enum LaunchError: LocalizedError {
        case appNotFound
        case fileMissing(URL)
        case openFailed

        var errorDescription: String? {
            switch self {
            case .appNotFound:
                return "Final Cut Pro not found. Install Final Cut Pro first, or build only the handoff package."
            case .fileMissing(let url):
                return "FCPXML file not found: \(url.path)"
            case .openFailed:
                return "Final Cut Pro import file was generated but could not be opened automatically. Double-click the .fcpxmld manually, or use File > Import > XML inside Final Cut Pro."
            }
        }
    }

    /// Open the .fcpxmld bundle in Final Cut Pro. Falls back to compat .fcpxml if needed.
    static func sendToFinalCut(fcpxmldURL: URL, compatURL: URL?) async throws {
        guard let appURL = HandoffAppDetector.finalCutAppURL() else {
            throw LaunchError.appNotFound
        }
        let primary = fcpxmldURL
        let fallback = compatURL

        if FileManager.default.fileExists(atPath: primary.path) {
            do {
                try await openWith(appURL: appURL, file: primary)
                return
            } catch {
                if let fallback, FileManager.default.fileExists(atPath: fallback.path) {
                    do {
                        try await openWith(appURL: appURL, file: fallback)
                        return
                    } catch {
                        throw LaunchError.openFailed
                    }
                }
                throw LaunchError.openFailed
            }
        }
        if let fallback, FileManager.default.fileExists(atPath: fallback.path) {
            try await openWith(appURL: appURL, file: fallback)
            return
        }
        throw LaunchError.fileMissing(primary)
    }

    private static func openWith(appURL: URL, file: URL) async throws {
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        cfg.addsToRecentItems = true
        _ = try await NSWorkspace.shared.open([file], withApplicationAt: appURL, configuration: cfg)
    }
}
