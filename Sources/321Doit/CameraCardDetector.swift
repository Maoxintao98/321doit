import Foundation

struct CameraCardProfile: Codable, Equatable {
    var maker: String
    var deviceHint: String
    var evidence: [String]
    var mediaRootRelativePath: String? = nil

    init(maker: String, deviceHint: String, evidence: [String], mediaRootRelativePath: String? = nil) {
        self.maker = maker
        self.deviceHint = deviceHint
        self.evidence = evidence
        self.mediaRootRelativePath = mediaRootRelativePath
    }

    private enum CodingKeys: String, CodingKey {
        case maker, deviceHint, evidence, mediaRootRelativePath
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maker = try c.decodeIfPresent(String.self, forKey: .maker) ?? "Unknown"
        deviceHint = try c.decodeIfPresent(String.self, forKey: .deviceHint) ?? "Unknown media card"
        evidence = try c.decodeIfPresent([String].self, forKey: .evidence) ?? []
        mediaRootRelativePath = try c.decodeIfPresent(String.self, forKey: .mediaRootRelativePath)
    }

    static let unknown = CameraCardProfile(
        maker: "Unknown",
        deviceHint: "Unknown media card",
        evidence: [],
        mediaRootRelativePath: nil
    )

    var displayName: String {
        if maker == "Unknown" { return deviceHint }
        return "\(maker) · \(deviceHint)"
    }
}

private final class CameraCardDetectionCache: @unchecked Sendable {
    private let lock = NSLock()
    private var profiles: [String: (date: Date, profile: CameraCardProfile)] = [:]
    private var counts: [String: (date: Date, count: Int)] = [:]
    private let ttl: TimeInterval = 30

    func profile(for key: String) -> CameraCardProfile? {
        lock.lock()
        defer { lock.unlock() }
        guard let cached = profiles[key], Date().timeIntervalSince(cached.date) < ttl else {
            profiles.removeValue(forKey: key)
            return nil
        }
        return cached.profile
    }

    func store(profile: CameraCardProfile, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        profiles[key] = (Date(), profile)
    }

    func count(for key: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard let cached = counts[key], Date().timeIntervalSince(cached.date) < ttl else {
            counts.removeValue(forKey: key)
            return nil
        }
        return cached.count
    }

    func store(count: Int, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        counts[key] = (Date(), count)
    }
}

enum CameraCardDetector {
    private static let cache = CameraCardDetectionCache()

    static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "mxf", "avi", "mkv", "mts", "m2ts",
        "r3d", "braw", "ari", "arx", "arri", "crm", "rmf", "dng"
    ]

    static func detect(sourceURL: URL) -> CameraCardProfile {
        let key = cacheKey(sourceURL)
        if let cached = cache.profile(for: key) {
            return cached
        }
        let profile = detectUncached(sourceURL: sourceURL)
        cache.store(profile: profile, for: key)
        return profile
    }

    private static func detectUncached(sourceURL: URL) -> CameraCardProfile {
        let fm = FileManager.default

        func exists(_ relativePath: String) -> Bool {
            fm.fileExists(atPath: sourceURL.appendingPathComponent(relativePath).path)
        }

        func containsExtension(_ exts: Set<String>, maxFiles: Int = 500) -> Bool {
            guard let enumerator = fm.enumerator(
                at: sourceURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return false }
            var scanned = 0
            for case let url as URL in enumerator {
                scanned += 1
                if scanned > maxFiles { break }
                if exts.contains(url.pathExtension.lowercased()) { return true }
            }
            return false
        }

        if exists("PRIVATE/M4ROOT/CLIP") || exists("PRIVATE/M4ROOT") {
            return CameraCardProfile(maker: "Sony", deviceHint: "XAVC / M4ROOT card", evidence: ["PRIVATE/M4ROOT"], mediaRootRelativePath: "PRIVATE/M4ROOT")
        }
        if exists("M4ROOT/CLIP") || exists("M4ROOT") {
            return CameraCardProfile(maker: "Sony", deviceHint: "XAVC / M4ROOT card", evidence: ["M4ROOT"], mediaRootRelativePath: "M4ROOT")
        }
        if exists("XDROOT") {
            return CameraCardProfile(maker: "Sony", deviceHint: "XDCAM / XDROOT card", evidence: ["XDROOT"], mediaRootRelativePath: "XDROOT")
        }
        if exists("PRIVATE/SONY/PRO/CLIPROOT") {
            return CameraCardProfile(maker: "Sony", deviceHint: "XAVC / CLIPROOT card", evidence: ["PRIVATE/SONY/PRO/CLIPROOT"], mediaRootRelativePath: "PRIVATE/SONY/PRO/CLIPROOT")
        }
        if exists("CLIPROOT") {
            return CameraCardProfile(maker: "Sony", deviceHint: "XAVC / CLIPROOT card", evidence: ["CLIPROOT"], mediaRootRelativePath: "CLIPROOT")
        }
        if exists("CONTENTS/CLIPS001") {
            return CameraCardProfile(maker: "Canon", deviceHint: "XF / Cinema EOS card", evidence: ["CONTENTS/CLIPS001"], mediaRootRelativePath: "CONTENTS")
        }
        if exists("PRIVATE/AVCHD") {
            return CameraCardProfile(maker: "Sony/Panasonic/Canon", deviceHint: "AVCHD card", evidence: ["PRIVATE/AVCHD"], mediaRootRelativePath: "PRIVATE/AVCHD")
        }
        if exists("CONTENTS/VIDEO") && exists("CONTENTS/AUDIO") && exists("CONTENTS/CLIP") {
            return CameraCardProfile(maker: "Panasonic", deviceHint: "P2 card", evidence: ["CONTENTS/VIDEO", "CONTENTS/AUDIO", "CONTENTS/CLIP"], mediaRootRelativePath: "CONTENTS")
        }
        if exists("PRIVATE/PANA_GRP") {
            return CameraCardProfile(maker: "Panasonic", deviceHint: "PANA_GRP card", evidence: ["PRIVATE/PANA_GRP"], mediaRootRelativePath: "PRIVATE/PANA_GRP")
        }
        if exists("DCIM/100GOPRO") || exists("DCIM/101GOPRO") {
            return CameraCardProfile(maker: "GoPro", deviceHint: "GoPro DCIM card", evidence: ["DCIM/*GOPRO"], mediaRootRelativePath: "DCIM")
        }
        if exists("DCIM/100MEDIA") || exists("MISC/THM") {
            return CameraCardProfile(maker: "DJI", deviceHint: "DJI Drone / Osmo card", evidence: ["DCIM/100MEDIA / MISC"], mediaRootRelativePath: "DCIM")
        }
        if containsExtension(["r3d"]) || hasFolderSuffix(sourceURL: sourceURL, suffix: ".RDC") {
            return CameraCardProfile(maker: "RED", deviceHint: "RED camera media", evidence: [".RDC / .R3D"], mediaRootRelativePath: firstFolderSuffix(sourceURL: sourceURL, suffix: ".RDC"))
        }
        if containsExtension(["braw"]) {
            return CameraCardProfile(maker: "Blackmagic Design", deviceHint: "BRAW media", evidence: [".braw"], mediaRootRelativePath: nil)
        }
        if containsExtension(["ari", "arx", "arri"]) {
            return CameraCardProfile(maker: "ARRI", deviceHint: "ARRIRAW media", evidence: [".ari / .arx"], mediaRootRelativePath: nil)
        }
        if containsExtension(["crm", "rmf"]) {
            return CameraCardProfile(maker: "Canon", deviceHint: "Cinema RAW Light / RMF media", evidence: [".crm / .rmf"], mediaRootRelativePath: nil)
        }
        if exists("DCIM") {
            return CameraCardProfile(maker: "Generic", deviceHint: "DCIM camera card", evidence: ["DCIM"], mediaRootRelativePath: "DCIM")
        }

        return .unknown
    }

    static func videoFileCount(sourceURL: URL, maxFiles: Int = 5_000) -> Int {
        let key = "\(cacheKey(sourceURL))|\(maxFiles)"
        if let cached = cache.count(for: key) {
            return cached
        }
        guard let enumerator = FileManager.default.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else { return 0 }

        var count = 0
        var scanned = 0
        for case let url as URL in enumerator {
            scanned += 1
            if scanned > maxFiles { break }
            if videoExtensions.contains(url.pathExtension.lowercased()) {
                count += 1
            }
        }
        cache.store(count: count, for: key)
        return count
    }

    private static func cacheKey(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func hasFolderSuffix(sourceURL: URL, suffix: String) -> Bool {
        firstFolderSuffix(sourceURL: sourceURL, suffix: suffix) != nil
    }

    private static func firstFolderSuffix(sourceURL: URL, suffix: String) -> String? {
        guard let enumerator = FileManager.default.enumerator(
            at: sourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        for case let url as URL in enumerator {
            if url.lastPathComponent.uppercased().hasSuffix(suffix.uppercased()) {
                return relativePath(from: sourceURL, to: url)
            }
        }
        return nil
    }
}
