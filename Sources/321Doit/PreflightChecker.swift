import Foundation

enum PreflightChecker {
    static func run(
        projectName: String,
        cardNumber: String,
        operatorName: String,
        sourceURL: URL?,
        targetRoots: [URL],
        outputFolderName: String,
        outputFolderNames: [String]? = nil,
        settings: AppSettings?,
        generateProxies: Bool = false,
        transcodeProfile: TranscodeProfile = .default,
        language: AppLanguage = .system
    ) -> [PreflightCheckResult] {
        var results: [PreflightCheckResult] = []
        let fm = FileManager.default
        let tr: (String, String) -> String = { zh, en in L10n.t(zh, en, language: language) }

        appendRequired(tr("项目名称已填", "Project name filled in"), ok: !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, to: &results)
        appendRequired(tr("卡号 / Reel 已填", "Card / Reel filled in"), ok: !cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, to: &results)
        appendRequired(tr("操作员已填", "Operator filled in"), ok: !operatorName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, to: &results)

        var sourceFiles: [SourceFile] = []
        if let sourceURL {
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir)
            if exists && isDir.boolValue && fm.isReadableFile(atPath: sourceURL.path) {
                results.append(.init(severity: .ok, message: tr("源盘可读", "Source is readable"), detail: sourceURL.path))
                do {
                    sourceFiles = try enumerateSourceFiles(at: sourceURL)
                    if sourceFiles.isEmpty {
                        results.append(.init(severity: .warning, message: tr("来源是空文件夹", "Source folder is empty"), detail: sourceURL.path))
                    } else {
                        let foundMsg = tr("发现 \(sourceFiles.count) 个可拷贝文件", "Found \(sourceFiles.count) file\(sourceFiles.count == 1 ? "" : "s") to copy")
                        results.append(.init(severity: .ok, message: foundMsg, detail: formatBytes(sourceFiles.reduce(0) { $0 + $1.size })))
                    }
                } catch {
                    results.append(.init(
                        severity: .error,
                        message: tr("来源包含不安全的文件路径", "Source contains an unsafe file path"),
                        detail: error.localizedDescription
                    ))
                }
            } else {
                results.append(.init(severity: .error, message: tr("源盘不可读", "Source is not readable"), detail: sourceURL.path))
            }
        } else {
            results.append(.init(severity: .error, message: tr("未选择来源", "No source selected"), detail: nil))
        }

        if targetRoots.isEmpty {
            results.append(.init(severity: .error, message: tr("未选择目标盘", "No destination selected"), detail: nil))
            return results
        }

        let totalBytes = sourceFiles.reduce(UInt64(0)) { $0 + $1.size }
        let checkedOutputFolderNames = outputFolderNames?.isEmpty == false ? outputFolderNames! : [outputFolderName]
        var seenTargets = Set<String>()
        var seenVolumeIds = [String: URL]()
        let sourceVolumeId = sourceURL.flatMap { volumeIdentifier(for: $0) }

        for (index, target) in targetRoots.enumerated() {
            let label = tr("目标盘 \(index + 1)", "Destination \(index + 1)")
            let standardized = target.standardizedFileURL.path
            if seenTargets.contains(standardized) {
                results.append(.init(severity: .error, message: tr("\(label) 重复选择", "\(label) is selected more than once"), detail: target.path))
            } else {
                seenTargets.insert(standardized)
            }

            var isDir: ObjCBool = false
            if fm.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue, fm.isWritableFile(atPath: target.path) {
                results.append(.init(severity: .ok, message: tr("\(label) 可写", "\(label) is writable"), detail: target.path))
            } else {
                results.append(.init(severity: .error, message: tr("\(label) 不可写", "\(label) is not writable"), detail: target.path))
            }

            let capacity = availableCapacity(at: target)
            if capacity > 0 && capacity < totalBytes {
                let detail = tr("需要 \(formatBytes(totalBytes))，可用 \(formatBytes(capacity))", "Need \(formatBytes(totalBytes)), available \(formatBytes(capacity))")
                results.append(.init(severity: .error, message: tr("\(label) 空间不足", "\(label) does not have enough space"), detail: detail))
            } else if capacity > 0 {
                results.append(.init(severity: .ok, message: tr("\(label) 空间充足", "\(label) has enough space"), detail: tr("可用 \(formatBytes(capacity))", "Available \(formatBytes(capacity))")))
            }

            if let sourceURL, isSameOrNested(target, under: sourceURL) || isSameOrNested(sourceURL, under: target) {
                results.append(.init(severity: .error, message: tr("\(label) 与源盘路径互相嵌套", "\(label) is nested with the source path"), detail: target.path))
            } else if let targetVolId = volumeIdentifier(for: target), let srcVolId = sourceVolumeId, targetVolId == srcVolId {
                results.append(.init(severity: .error, message: tr("\(label) 与源盘在同一物理磁盘卷", "\(label) is on the same physical volume as the source"), detail: target.path))
            }

            for folderName in checkedOutputFolderNames {
                let outputURL = target.appendingPathComponent(folderName, isDirectory: true)
                if fm.fileExists(atPath: outputURL.path) {
                    results.append(.init(severity: .warning, message: tr("\(label) 已存在同名卡号目录", "\(label) already has a folder with this card name"), detail: outputURL.path))
                } else {
                    results.append(.init(severity: .ok, message: tr("\(label) 未发现同名卡号", "\(label) has no conflicting card folder"), detail: folderName))
                }
            }

            if isLikelySystemVolume(target) {
                results.append(.init(severity: .warning, message: tr("\(label) 可能是系统盘", "\(label) looks like the system volume"), detail: target.path))
            }

            if let volumeId = volumeIdentifier(for: target) {
                if let previous = seenVolumeIds[volumeId] {
                    let detail = "\(previous.path) / \(target.path)"
                    results.append(.init(severity: .warning, message: tr("\(label) 与另一个目标可能是同一块物理磁盘", "\(label) may share a physical disk with another destination"), detail: detail))
                } else {
                    seenVolumeIds[volumeId] = target
                }
            }

            if let fsName = filesystemName(for: target) {
                if isLikelyFAT32(fsName) {
                    results.append(.init(severity: .warning, message: tr("\(label) 文件系统可能有单文件大小限制", "\(label) filesystem may have a single-file size limit"), detail: fsName))
                    if let large = sourceFiles.first(where: { $0.size > fat32SingleFileLimit }) {
                        let detail = tr(
                            "\(large.relativePath)（\(formatBytes(large.size))）。FAT32 通常不支持单个超过 4GB 的文件，请改用 exFAT / APFS。",
                            "\(large.relativePath) (\(formatBytes(large.size))). FAT32 usually cannot hold a single file larger than 4GB. Use exFAT or APFS instead."
                        )
                        results.append(.init(
                            severity: .error,
                            message: tr("\(label) 不支持 4GB 以上单文件", "\(label) cannot hold single files larger than 4GB"),
                            detail: detail
                        ))
                    }
                } else {
                    results.append(.init(severity: .ok, message: tr("\(label) 文件系统检查", "\(label) filesystem check"), detail: fsName))
                }
            }

            if isNetworkVolume(target) {
                results.append(.init(
                    severity: .warning,
                    message: tr("\(label) 是网络卷宗", "\(label) is a network volume"),
                    detail: tr(
                        "网络存储（NAS/SMB/NFS）速度较慢且不如直连磁盘稳定，建议使用本地外接硬盘。",
                        "Network storage (NAS/SMB/NFS) is slower and less reliable than a direct-attached drive."
                    )
                ))
            }

            if !isCaseSensitiveVolume(target) {
                let conflicts = findCaseConflicts(in: sourceFiles)
                if !conflicts.isEmpty {
                    let sample = conflicts.prefix(3).joined(separator: ", ")
                    results.append(.init(
                        severity: .error,
                        message: tr("\(label) 大小写不敏感，来源存在同名冲突", "\(label) is case-insensitive and source has filename conflicts"),
                        detail: tr(
                            "以下文件在大小写不敏感的目标盘上会互相覆盖：\(sample)",
                            "These files would overwrite each other on a case-insensitive volume: \(sample)"
                        )
                    ))
                }
            }
        }

        let suspicious = sourceFiles.filter {
            $0.relativePath.hasPrefix(".") || $0.relativePath.contains("/.") || $0.size == 0
        }
        if suspicious.isEmpty {
            results.append(.init(severity: .ok, message: tr("未发现隐藏文件/异常文件", "No hidden or empty files found"), detail: nil))
        } else {
            let msg = tr("发现 \(suspicious.count) 个隐藏文件/空文件", "Found \(suspicious.count) hidden or empty file\(suspicious.count == 1 ? "" : "s")")
            results.append(.init(severity: .warning, message: msg, detail: suspicious.prefix(3).map(\.relativePath).joined(separator: ", ")))
        }

        appendFFmpegPreflight(
            generateProxies: generateProxies || transcodeProfile.burnIn.enabled,
            transcodeProfile: transcodeProfile,
            settings: settings,
            language: language,
            to: &results
        )

        return results
    }

    static func hasBlockingErrors(_ results: [PreflightCheckResult]) -> Bool {
        results.contains { $0.severity == .error }
    }

    private static func appendRequired(_ message: String, ok: Bool, to results: inout [PreflightCheckResult]) {
        results.append(.init(severity: ok ? .ok : .error, message: message, detail: nil))
    }

    private static func isLikelySystemVolume(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return isSameOrNested(url, under: URL(fileURLWithPath: "/")) && !url.path.hasPrefix("/Volumes/") && home.hasPrefix(url.path)
    }

    private static func volumeIdentifier(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.volumeIdentifierKey]) else { return nil }
        return values.volumeIdentifier.map { "\($0)" }
    }

    private static func filesystemName(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.volumeLocalizedFormatDescriptionKey]) else { return nil }
        return values.volumeLocalizedFormatDescription
    }

    private static let fat32SingleFileLimit: UInt64 = 4_294_967_295

    private static func isLikelyFAT32(_ filesystemName: String) -> Bool {
        let lower = filesystemName.lowercased()
        if lower.contains("exfat") { return false }
        return lower.contains("fat32") || lower.contains("ms-dos") || lower.contains("msdos")
    }

    private static func isNetworkVolume(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey]) else { return false }
        return values.volumeIsLocal == false
    }

    private static func isCaseSensitiveVolume(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]) else { return true }
        return values.volumeSupportsCaseSensitiveNames ?? true
    }

    private static func findCaseConflicts(in files: [SourceFile]) -> [String] {
        var seen = [String: String]()
        var conflicts: [String] = []
        for file in files {
            let lower = file.relativePath.lowercased()
            if let existing = seen[lower], existing != file.relativePath {
                conflicts.append("\(existing) ↔ \(file.relativePath)")
            } else {
                seen[lower] = file.relativePath
            }
        }
        return conflicts
    }

    private static func appendFFmpegPreflight(
        generateProxies: Bool,
        transcodeProfile: TranscodeProfile,
        settings: AppSettings?,
        language: AppLanguage,
        to results: inout [PreflightCheckResult]
    ) {
        guard generateProxies else { return }
        let tr: (String, String) -> String = { zh, en in L10n.t(zh, en, language: language) }

        var profile = transcodeProfile
        let hasProfilePath = profile.ffmpegPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if !hasProfilePath,
           let configured = settings?.transcode.ffmpegPath,
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.ffmpegPath = configured
        }

        if let ffmpegURL = FFmpegLocator.executableURL(configuredPath: profile.ffmpegPath) {
            results.append(.init(severity: .ok, message: tr("FFmpeg 可用", "FFmpeg is available"), detail: ffmpegURL.path))
            return
        }

        let requiredReasons = ffmpegRequiredReasons(profile, language: language)
        if requiredReasons.isEmpty {
            results.append(.init(
                severity: .error,
                message: tr("未找到 FFmpeg（代理转码需要）", "FFmpeg not found (required for proxy / transcode)"),
                detail: tr(
                    "强烈建议安装 FFmpeg 以保证转码稳定性。请去首选项 -> FFmpeg 中安装。如确实不想安装，请取消勾选“生成代理”。",
                    "Installing FFmpeg is strongly recommended for stable transcoding. Open Preferences -> FFmpeg to install. If you prefer not to install, uncheck \"Generate proxies\"."
                )
            ))
        } else {
            let separator = language.resolved == .zh ? "；" : "; "
            let detailSuffix = tr(
                "。请去首选项 -> FFmpeg 中安装，或关闭对应转码选项后再开始。",
                ". Install via Preferences -> FFmpeg, or disable the related transcode options before starting."
            )
            results.append(.init(
                severity: .error,
                message: tr("未找到 FFmpeg，当前代理/转码设置需要 FFmpeg", "FFmpeg not found; current proxy / transcode settings require FFmpeg"),
                detail: requiredReasons.joined(separator: separator) + detailSuffix
            ))
        }
    }

    private static func ffmpegRequiredReasons(_ profile: TranscodeProfile, language: AppLanguage) -> [String] {
        let tr: (String, String) -> String = { zh, en in L10n.t(zh, en, language: language) }
        var reasons: [String] = []
        if profile.lutMode != .none {
            reasons.append(tr("LUT 烧录", "LUT bake-in"))
        }
        if profile.burnIn.enabled {
            reasons.append(tr("画面烧录", "Burn-in overlay"))
        }
        if profile.codec == .h266 {
            reasons.append(tr("H.266 / VVC 编码", "H.266 / VVC encoding"))
        }
        if profile.codec == .prores4444XQ {
            reasons.append(tr("ProRes 4444 XQ", "ProRes 4444 XQ"))
        }
        if profile.scale != .original {
            reasons.append(tr("代理缩放 / 分辨率变换", "Proxy scaling / resolution change"))
        }
        if profile.attemptRaw {
            reasons.append(tr("RAW / 部分专业格式解码", "RAW / certain pro format decoding"))
        }
        if profile.frameExtraction.enabled && profile.frameExtraction.applyLUT && profile.lutPath?.isEmpty == false {
            reasons.append(tr("截图应用 LUT", "Apply LUT on still extraction"))
        }
        return reasons
    }

}
