import Foundation

// Shared checksum vocabulary used by all 321Doit tools and integrations.
// It lives outside the large model layer so copy, verify, and future modules
// share one stable definition.

enum ChecksumAlgorithm: String, Codable, CaseIterable, Identifiable {
    case xxhash64, md5, sha1, sha256

    var id: String { rawValue }

    var label: (String, String) {
        switch self {
        case .xxhash64: return ("xxHash64", "xxHash64")
        case .md5:      return ("MD5", "MD5")
        case .sha1:     return ("SHA-1", "SHA-1")
        case .sha256:   return ("SHA-256", "SHA-256")
        }
    }

    var displayName: String {
        label.0
    }

    var mhlHashType: String {
        switch self {
        case .xxhash64: return "xxh64"
        case .md5:      return "md5"
        case .sha1:     return "sha1"
        case .sha256:   return "sha256"
        }
    }
}

enum XXHash64Implementation: String, Codable, CaseIterable, Identifiable {
    case automatic
    case highPerformance
    case compatibility

    var id: String { rawValue }

    var label: (String, String) {
        switch self {
        case .automatic:
            return ("自动", "Automatic")
        case .highPerformance:
            return ("高性能模式（C shim）", "High performance (C shim)")
        case .compatibility:
            return ("兼容模式（Swift reference）", "Compatibility (Swift reference)")
        }
    }

    var usesCShim: Bool {
        switch self {
        case .automatic, .highPerformance:
            return true
        case .compatibility:
            return false
        }
    }
}

func formatHash(_ value: UInt64) -> String {
    String(format: "%016llx", value)
}
