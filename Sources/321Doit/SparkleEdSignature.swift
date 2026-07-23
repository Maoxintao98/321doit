import CryptoKit
import Foundation

/// Sparkle 2.x signs each release artifact with Ed25519 (Curve25519). The
/// signature is over the raw bytes of the artifact; verification needs only
/// the public key, which the app embeds in `Info.plist` under
/// `SUPublicEDKey`. CryptoKit's `Curve25519.Signing` is wire-compatible with
/// the format Sparkle's own `sign_update` and `generate_keys` produce.
///
/// Signature wire format: 64 raw bytes (R || S), base64-encoded.
/// Public key wire format: 32 raw bytes, base64-encoded.
enum SparkleEdSignature {
    enum SignatureError: LocalizedError {
        case malformedPublicKey
        case malformedSignature
        case invalidSignature

        var errorDescription: String? {
            switch self {
            case .malformedPublicKey: return "Invalid Sparkle public key (expected 32 raw bytes, base64-encoded)."
            case .malformedSignature: return "Invalid Sparkle signature (expected 64 raw bytes, base64-encoded)."
            case .invalidSignature:   return "Sparkle signature does not verify against the supplied public key."
            }
        }
    }

    static func makePublicKey(fromBase64 base64: String) throws -> Curve25519.Signing.PublicKey {
        guard
            let raw = Data(base64Encoded: base64.trimmingCharacters(in: .whitespacesAndNewlines)),
            raw.count == 32
        else {
            throw SignatureError.malformedPublicKey
        }
        return try Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }

    /// Throws if the signature does not verify or is malformed.
    static func verify(
        artifact: Data,
        signatureBase64: String,
        publicKey: Curve25519.Signing.PublicKey
    ) throws {
        guard
            let sig = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
            sig.count == 64
        else {
            throw SignatureError.malformedSignature
        }
        guard publicKey.isValidSignature(sig, for: artifact) else {
            throw SignatureError.invalidSignature
        }
    }

    /// Used by the `Tools/SparkleSign.swift` CLI when producing release
    /// signatures. The same code path is shared so a verification failure on
    /// the app side cannot ever blame "different signature algorithm" — it
    /// is the same Curve25519 implementation on both ends.
    static func sign(artifact: Data, privateKeyRaw: Data) throws -> String {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyRaw)
        let signature = try key.signature(for: artifact)
        return signature.base64EncodedString()
    }
}
