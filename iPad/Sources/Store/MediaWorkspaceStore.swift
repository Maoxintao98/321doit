import AVFoundation
import CryptoKit
import Foundation
import UIKit

@MainActor
final class MediaWorkspaceStore: ObservableObject {
    @Published var sourceDirectory: URL?
    @Published var primaryDestination: URL?
    @Published var secondaryDestination: URL?
    @Published var offloadProgress = 0.0
    @Published var offloadStatus = ""
    @Published var isOffloading = false
    @Published var lastOffloadReport: URL?

    @Published var conversionInput: URL?
    @Published var conversionPreset: iPadConversionPreset = .review
    @Published var conversionStatus = ""
    @Published var isConverting = false
    @Published var conversionOutput: URL?

    func startOffload(projectName: String, language: AppLanguage) {
        guard let sourceDirectory, let primaryDestination else { return }
        let destinations = [primaryDestination, secondaryDestination].compactMap { $0 }
        isOffloading = true
        UIApplication.shared.isIdleTimerDisabled = true
        offloadProgress = 0
        offloadStatus = L10n.t("正在读取卡片…", "Reading card…", language: language)

        Task {
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    try OffloadService.run(
                        source: sourceDirectory,
                        destinations: destinations,
                        projectName: projectName
                    ) { completed, total, name in
                        Task { @MainActor [weak self] in
                            self?.offloadProgress = total == 0 ? 0 : Double(completed) / Double(total)
                            self?.offloadStatus = name
                        }
                    }
                }.value
                lastOffloadReport = report
                offloadProgress = 1
                offloadStatus = L10n.t("拷卡完成，所有文件已通过 SHA-256 校验",
                                       "Offload complete. Every file passed SHA-256 verification.",
                                       language: language)
            } catch {
                offloadStatus = L10n.t("拷卡失败：\(error.localizedDescription)",
                                       "Offload failed: \(error.localizedDescription)",
                                       language: language)
            }
            isOffloading = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    func startConversion(language: AppLanguage) {
        guard let conversionInput else { return }
        isConverting = true
        conversionOutput = nil
        conversionStatus = L10n.t("正在转换…", "Converting…", language: language)
        let preset = conversionPreset

        Task {
            do {
                let output = try await MediaConversionService.convert(input: conversionInput, preset: preset)
                conversionOutput = output
                conversionStatus = L10n.t("转换完成", "Conversion complete", language: language)
            } catch {
                conversionStatus = L10n.t("转换失败：\(error.localizedDescription)",
                                          "Conversion failed: \(error.localizedDescription)",
                                          language: language)
            }
            isConverting = false
        }
    }
}

enum iPadConversionPreset: String, CaseIterable, Identifiable {
    case review
    case hevc
    case original

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .review: return L10n.t("审片 · H.264 1080p", "Review · H.264 1080p", language: language)
        case .hevc: return L10n.t("高质量 · HEVC", "High quality · HEVC", language: language)
        case .original: return L10n.t("快速重封装", "Fast passthrough", language: language)
        }
    }

    var exportPreset: String {
        switch self {
        case .review: return AVAssetExportPreset1920x1080
        case .hevc: return AVAssetExportPresetHEVCHighestQuality
        case .original: return AVAssetExportPresetPassthrough
        }
    }

    var fileType: AVFileType {
        switch self {
        case .review, .hevc: return .mp4
        case .original: return .mov
        }
    }
}

private enum MediaConversionService {
    static func convert(input: URL, preset: iPadConversionPreset) async throws -> URL {
        let scoped = input.startAccessingSecurityScopedResource()
        defer { if scoped { input.stopAccessingSecurityScopedResource() } }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MediaExports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = input.deletingPathExtension().lastPathComponent
        let output = uniqueURL(in: directory, base: "\(base)_\(preset.rawValue)",
                               extension: preset.fileType == .mov ? "mov" : "mp4")

        let asset = AVURLAsset(url: input)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset.exportPreset) else {
            throw MediaWorkspaceError.unsupported
        }
        guard session.supportedFileTypes.contains(preset.fileType) else {
            throw MediaWorkspaceError.unsupported
        }
        session.shouldOptimizeForNetworkUse = preset != .original
        try await session.export(to: output, as: preset.fileType)
        return output
    }

    private static func uniqueURL(in directory: URL, base: String, extension ext: String) -> URL {
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(suffix)").appendingPathExtension(ext)
            suffix += 1
        }
        return candidate
    }
}

private enum OffloadService {
    struct Report: Codable {
        var app = "321Doit iPad"
        var createdAt = Date()
        var source: String
        var destinations: [String]
        var algorithm = "SHA-256"
        var totalBytes: UInt64
        var files: [FileRecord]
    }

    struct FileRecord: Codable {
        var relativePath: String
        var bytes: UInt64
        var sha256: String
    }

    static func run(
        source: URL,
        destinations: [URL],
        projectName: String,
        progress: @escaping @Sendable (Int, Int, String) -> Void
    ) throws -> URL {
        let sourceScoped = source.startAccessingSecurityScopedResource()
        let destinationScopes = destinations.map { $0.startAccessingSecurityScopedResource() }
        defer {
            if sourceScoped { source.stopAccessingSecurityScopedResource() }
            for (index, scoped) in destinationScopes.enumerated() where scoped {
                destinations[index].stopAccessingSecurityScopedResource()
            }
        }

        let files = try regularFiles(under: source)
        guard !files.isEmpty else { throw MediaWorkspaceError.emptySource }
        let sourcePath = source.standardizedFileURL.path
        let destinationPaths = destinations.map { $0.standardizedFileURL.path }
        guard Set(destinationPaths).count == destinationPaths.count else {
            throw MediaWorkspaceError.duplicateDestination
        }
        guard destinationPaths.allSatisfy({ $0 != sourcePath && !$0.hasPrefix(sourcePath + "/") }) else {
            throw MediaWorkspaceError.invalidDestination
        }
        let requiredBytes = try files.reduce(UInt64(0)) { total, file in
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            return total + UInt64(size)
        }
        for destination in destinations {
            let capacity = try destination.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage ?? 0
            guard capacity <= 0 || UInt64(capacity) >= requiredBytes else {
                throw MediaWorkspaceError.insufficientSpace(destination.lastPathComponent)
            }
        }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let project = sanitize(projectName)
        let card = sanitize(source.lastPathComponent)
        let roots = try destinations.map { destination -> URL in
            let root = destination.appendingPathComponent("\(project)_\(card)_\(stamp)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return root
        }

        var records: [FileRecord] = []
        var totalBytes: UInt64 = 0
        for (index, file) in files.enumerated() {
            let relative = relativePath(file, under: source)
            let sourceHash = try sha256(file)
            let values = try file.resourceValues(forKeys: [.fileSizeKey])
            let bytes = UInt64(values.fileSize ?? 0)

            for root in roots {
                let output = root.appendingPathComponent(relative)
                try FileManager.default.createDirectory(
                    at: output.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: file, to: output)
                guard try sha256(output) == sourceHash else {
                    throw MediaWorkspaceError.verificationFailed(relative)
                }
            }
            records.append(FileRecord(relativePath: relative, bytes: bytes, sha256: sourceHash))
            totalBytes += bytes
            progress(index + 1, files.count, relative)
        }

        let report = Report(
            source: source.lastPathComponent,
            destinations: destinations.map(\.lastPathComponent),
            totalBytes: totalBytes,
            files: records)
        let data = try JSONEncoder.prettyISO.encode(report)
        for root in roots {
            let url = root.appendingPathComponent("321Doit-Offload-Report.json")
            try data.write(to: url, options: .atomic)
        }
        let localReports = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OffloadReports", isDirectory: true)
        try FileManager.default.createDirectory(at: localReports, withIntermediateDirectories: true)
        let localReport = localReports.appendingPathComponent("\(project)_\(card)_\(stamp).json")
        try data.write(to: localReport, options: .atomic)
        return localReport
    }

    private static func regularFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        else { return [] }
        return try enumerator.compactMap { value in
            guard let url = value as? URL,
                  try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            else { return nil }
            return url
        }
    }

    private static func relativePath(_ url: URL, under root: URL) -> String {
        String(url.path.dropFirst(root.path.hasSuffix("/") ? root.path.count : root.path.count + 1))
    }

    private static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func sanitize(_ value: String) -> String {
        let cleaned = value.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: "-")
        return cleaned.isEmpty ? "Untitled" : cleaned
    }
}

enum MediaWorkspaceError: LocalizedError {
    case noDestination
    case emptySource
    case duplicateDestination
    case invalidDestination
    case insufficientSpace(String)
    case unsupported
    case exportFailed
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noDestination: return "No destination selected."
        case .emptySource: return "The source folder contains no files."
        case .duplicateDestination: return "Primary and secondary destinations must be different."
        case .invalidDestination: return "A destination cannot be the source or a folder inside it."
        case .insufficientSpace(let name): return "Not enough free space on \(name)."
        case .unsupported: return "This file cannot be converted with the selected preset."
        case .exportFailed: return "The media export did not complete."
        case .verificationFailed(let path): return "Verification failed: \(path)"
        }
    }
}
