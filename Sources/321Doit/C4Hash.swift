import CryptoKit
import Foundation

/// C4 (Cinema Content Creation Cloud) ID hash, as defined by ASC MHL v2.0
/// for the chain manifest. C4 = "c4" + base58(SHA-512(payload)) padded to 88 chars
/// using the C4 alphabet, leading-padded with the C4 zero glyph "1".
///
/// Reference: ascmhl Python package (`ascmhl.hasher.C4`).
enum C4Hash {
    private static let alphabet: [Character] = Array(
        "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
    )
    private static let bodyLength = 88
    private static let zero: Character = "1"

    /// Hash a file by streaming, so multi-GB MHL files are handled without
    /// loading the entire payload into memory. (MHLs in practice stay small,
    /// but the streaming form costs nothing extra here.)
    static func hashFile(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA512()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return encode(digest: Array(hasher.finalize()))
    }

    static func hash(data: Data) -> String {
        encode(digest: Array(SHA512.hash(data: data)))
    }

    /// Long division of a 64-byte big-endian integer by 58, repeatedly,
    /// emitting alphabet characters from least-significant to most-significant.
    private static func encode(digest: [UInt8]) -> String {
        var dividend = digest
        var output: [Character] = []
        output.reserveCapacity(bodyLength)

        while dividend.contains(where: { $0 != 0 }) {
            var remainder = 0
            for i in 0..<dividend.count {
                let cur = remainder * 256 + Int(dividend[i])
                dividend[i] = UInt8(cur / 58)
                remainder = cur % 58
            }
            output.append(alphabet[remainder])
        }

        // Pad with the C4 zero glyph and reverse to most-significant first.
        while output.count < bodyLength {
            output.append(zero)
        }
        return "c4" + String(output.reversed())
    }
}
