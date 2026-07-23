import Foundation

struct FFmpegInfo {
    var isAvailable: Bool
    var path: String?
    var version: String
    var architecture: String
    var codecs: [String]

    var summary: String {
        if !isAvailable {
            return "FFmpeg not found (Basic offload still available)"
        }
        return "\(version) (\(architecture)) at \(path ?? "")"
    }
}

enum FFmpegLocator {
    static let defaultPaths = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/opt/local/bin/ffmpeg",
        "/usr/local/homebrew/bin/ffmpeg",
        "/usr/bin/ffmpeg"
    ]

    static func executableURL(configuredPath: String?) -> URL? {
        executableURL(
            configuredPath: configuredPath,
            autoSearchPaths: candidatePaths(),
            requireNativeArchitecture: true
        )
    }

    static func executableURL(configuredPath: String?, autoSearchPaths: [String]) -> URL? {
        executableURL(
            configuredPath: configuredPath,
            autoSearchPaths: autoSearchPaths,
            requireNativeArchitecture: false
        )
    }

    private static func executableURL(
        configuredPath: String?,
        autoSearchPaths: [String],
        requireNativeArchitecture: Bool
    ) -> URL? {
        if let configured = validConfiguredURL(configuredPath),
           !requireNativeArchitecture || supportsRunningArchitecture(configured) {
            return configured
        }

        return autoDetectedURL(
            searchPaths: autoSearchPaths,
            requireNativeArchitecture: requireNativeArchitecture
        )
    }

    static func validatePath(_ path: String) -> Bool {
        return FileManager.default.isExecutableFile(atPath: path)
    }

    static func getInfo(configuredPath: String?, language: AppLanguage) -> FFmpegInfo {
        let debugPaths = candidatePaths()
        let detected = executableURL(configuredPath: configuredPath, autoSearchPaths: debugPaths)

        guard let url = detected else {
            let limit = debugPaths.prefix(5).joined(separator: ", ") + (debugPaths.count > 5 ? "..." : "")
            let configured = configuredPath ?? "nil"
            let notInstalled = L10n.t("未找到 (搜寻了: \(limit)，配置: \(configured))", "Not installed (Searched: \(limit), Config: \(configured))", language: language)
            return FFmpegInfo(isAvailable: false, path: nil, version: notInstalled, architecture: "Unknown", codecs: [])
        }

        var versionStr = "Unknown Version"
        var archStr = "Unknown Arch"

        // Get version
        let process = Process()
        process.executableURL = url
        process.arguments = ["-version"]
        let pipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            let errText = String(data: errData, encoding: .utf8) ?? ""
            let fullText = text + errText
            if let firstLine = fullText.split(separator: "\n").first {
                versionStr = String(firstLine)
            }
        } catch {
            print("FFmpegLocator Error: \(error)")
        }

        // Get arch using 'file' command
        let fileProcess = Process()
        fileProcess.executableURL = URL(fileURLWithPath: "/usr/bin/file")
        fileProcess.arguments = [url.path]
        let filePipe = Pipe()
        fileProcess.standardOutput = filePipe

        do {
            try fileProcess.run()
            fileProcess.waitUntilExit()
            let data = filePipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            if text.contains("Mach-O universal binary") {
                archStr = "Universal"
            } else if text.contains("arm64") {
                archStr = "arm64"
            } else if text.contains("x86_64") {
                archStr = "x86_64"
            }
        } catch {}

        // Get codecs
        var supportedCodecs: [String] = []
        let targetCodecs = ["h264_videotoolbox", "hevc_videotoolbox", "prores_ks", "prores_videotoolbox", "libvvenc"]
        
        let codecsProcess = Process()
        codecsProcess.executableURL = url
        codecsProcess.arguments = ["-encoders"]
        let codecsPipe = Pipe()
        codecsProcess.standardOutput = codecsPipe

        do {
            try codecsProcess.run()
            codecsProcess.waitUntilExit()
            let data = codecsPipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            for codec in targetCodecs {
                if text.contains(codec) {
                    supportedCodecs.append(codec)
                }
            }
        } catch {}

        return FFmpegInfo(isAvailable: true, path: url.path, version: versionStr, architecture: archStr, codecs: supportedCodecs)
    }

    static func versionString(configuredPath: String?, language: AppLanguage) -> String {
        let info = getInfo(configuredPath: configuredPath, language: language)
        return info.summary
    }

    private static func validConfiguredURL(_ configuredPath: String?) -> URL? {
        guard let configuredPath else { return nil }
        let trimmed = configuredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir), isDir.boolValue {
            let candidate = URL(fileURLWithPath: trimmed).appendingPathComponent("ffmpeg")
            return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
        }

        return FileManager.default.isExecutableFile(atPath: trimmed) ? URL(fileURLWithPath: trimmed) : nil
    }

    private static func autoDetectedURL(
        searchPaths: [String],
        requireNativeArchitecture: Bool
    ) -> URL? {
        for searchPath in searchPaths {
            let url = URL(fileURLWithPath: searchPath)
            if FileManager.default.isExecutableFile(atPath: url.path),
               !requireNativeArchitecture || supportsRunningArchitecture(url) {
                return url
            }
        }
        return nil
    }

    /// Checks Mach-O slices without launching the candidate. This avoids
    /// triggering Rosetta merely because an old Intel-only FFmpeg happens to
    /// be earlier in PATH on an Apple Silicon Mac.
    private static func supportsRunningArchitecture(_ url: URL) -> Bool {
        #if arch(arm64)
        let required = "arm64"
        #elseif arch(x86_64)
        let required = "x86_64"
        #else
        return false
        #endif

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
        process.arguments = ["-archs", url.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return false }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let architectures = String(decoding: data, as: UTF8.self)
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
            return architectures.contains(required)
        } catch {
            return false
        }
    }

    private static func candidatePaths() -> [String] {
        var paths: [String] = []
        var seen = Set<String>()
        func append(_ path: String) {
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            if seen.insert(standardized).inserted {
                paths.append(standardized)
            }
        }

        defaultPaths.forEach(append)

        // Prefer the copy shipped with the current app over legacy copies
        // previously installed into Application Support.
        if let resourceURL = Bundle.main.resourceURL {
            append(resourceURL.appendingPathComponent("Tools/ffmpeg").path)
        }

        append("/Library/Application Support/321Doit/Tools/ffmpeg")

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let nsHome = NSHomeDirectory()
        
        let homes = [home, nsHome, "/Users/" + NSUserName()]
        for h in homes {
            [
                "\(h)/.homebrew/bin/ffmpeg",
                "\(h)/homebrew/bin/ffmpeg",
                "\(h)/.local/bin/ffmpeg",
                "\(h)/Library/Application Support/321Doit/Tools/ffmpeg"
            ].forEach(append)
        }

        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            envPath
                .split(separator: ":")
                .map(String.init)
                .filter { !$0.isEmpty }
                .map { "\($0)/ffmpeg" }
                .forEach(append)
        }

        var brewCandidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
            "/usr/local/homebrew/bin/brew"
        ]
        for h in homes {
            brewCandidates.append("\(h)/.homebrew/bin/brew")
            brewCandidates.append("\(h)/homebrew/bin/brew")
        }
        
        for brew in brewCandidates {
            let brewURL = URL(fileURLWithPath: brew)
            if FileManager.default.isExecutableFile(atPath: brewURL.path) {
                append(brewURL.deletingLastPathComponent().appendingPathComponent("ffmpeg").path)
            }
        }
        return paths
    }
}
