import CryptoKit
import Foundation

/// Standalone CLI that produces Sparkle-compatible Ed25519 signatures and
/// optionally writes a signed appcast.xml entry. Same Curve25519
/// implementation the app uses to verify, so a verification failure on the
/// app side cannot ever blame "different signature algorithm" — drift is
/// physically impossible.
///
/// Usage:
///   SparkleSign generate-keys [<dir>]
///       Create a new Ed25519 key pair. Public key is printed and also
///       written to <dir>/sparkle-public.key (default dir: ./dist).
///       Private key goes to <dir>/sparkle-private.key with mode 0600.
///       Back this file up — losing it means losing the ability to sign
///       updates, and rotating to a new key requires every installed
///       321Doit user to grab a fresh build with the new SUPublicEDKey.
///
///   SparkleSign sign <dmg-path> [--private-key <path>]
///       Print the Sparkle-compatible signature attributes. Reads the
///       private key from --private-key, $SPARKLE_PRIVATE_KEY (base64), or
///       ./dist/sparkle-private.key — first match wins.
///
///   SparkleSign verify <dmg-path> [--public-key <path-or-base64>]
///       Verify a DMG against a public key. Exit 0 on success, 1 on
///       signature failure. Used by package.sh as a sanity check after
///       signing.
///
///   SparkleSign appcast <dmg-path> --version <v> --build <b> \
///                                 --download-url <u> [--release-notes <u>] \
///                                 [--prerelease] [--private-key <path>]
///       Emit an <item> element ready to be appended to appcast.xml.

@main
struct SparkleSignTool {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            print(usage)
            exit(2)
        }
        let rest = Array(args.dropFirst())
        do {
            switch command {
            case "generate-keys":
                try generateKeys(directoryArg: rest.first)
            case "sign":
                try signCommand(args: rest)
            case "verify":
                try verifyCommand(args: rest)
            case "appcast":
                try appcastCommand(args: rest)
            default:
                fputs("Unknown command: \(command)\n\n", stderr)
                fputs(usage, stderr)
                exit(2)
            }
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    // MARK: Commands

    static func generateKeys(directoryArg: String?) throws {
        let dir = URL(fileURLWithPath: directoryArg ?? "dist", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = Curve25519.Signing.PrivateKey()
        let pubB64 = key.publicKey.rawRepresentation.base64EncodedString()
        let privB64 = key.rawRepresentation.base64EncodedString()

        let pubURL = dir.appendingPathComponent("sparkle-public.key")
        let privURL = dir.appendingPathComponent("sparkle-private.key")
        try pubB64.write(to: pubURL, atomically: true, encoding: .utf8)
        try privB64.write(to: privURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privURL.path)

        print("Public key  (commit / paste into build.sh SUPublicEDKey):")
        print(pubB64)
        print()
        print("Public key written to:  \(pubURL.path)")
        print("Private key written to: \(privURL.path)  (mode 0600 — back this up out of band)")
        print()
        print("Reminder: rotating this key requires every installed 321Doit user to upgrade")
        print("to a build that embeds the new SUPublicEDKey before they can receive future updates.")
    }

    static func signCommand(args: [String]) throws {
        let parsed = try ArgParser(args: args)
        guard let dmgPath = parsed.positional.first else {
            throw CLIError("sign requires <dmg-path>")
        }
        let dmgURL = URL(fileURLWithPath: dmgPath)
        let priv = try loadPrivateKey(explicit: parsed.flagValue("--private-key"))
        let data = try Data(contentsOf: dmgURL)
        let sig = try SparkleEdSignature.sign(artifact: data, privateKeyRaw: priv)
        let length = data.count
        // Sparkle convention: print the attributes verbatim so callers can
        // splice them into an existing appcast template.
        print("sparkle:edSignature=\"\(sig)\" length=\"\(length)\"")
    }

    static func verifyCommand(args: [String]) throws {
        let parsed = try ArgParser(args: args)
        guard let dmgPath = parsed.positional.first else {
            throw CLIError("verify requires <dmg-path>")
        }
        let dmgURL = URL(fileURLWithPath: dmgPath)
        let pubKey = try loadPublicKey(explicit: parsed.flagValue("--public-key"))
        guard let sigB64 = parsed.flagValue("--signature") else {
            throw CLIError("verify requires --signature <base64>")
        }
        let data = try Data(contentsOf: dmgURL)
        try SparkleEdSignature.verify(artifact: data, signatureBase64: sigB64, publicKey: pubKey)
        print("OK")
    }

    static func appcastCommand(args: [String]) throws {
        let parsed = try ArgParser(args: args)
        guard let dmgPath = parsed.positional.first else {
            throw CLIError("appcast requires <dmg-path>")
        }
        guard let version = parsed.flagValue("--version") else { throw CLIError("appcast requires --version") }
        guard let build = parsed.flagValue("--build") else { throw CLIError("appcast requires --build") }
        guard let downloadString = parsed.flagValue("--download-url"),
              let downloadURL = URL(string: downloadString) else {
            throw CLIError("appcast requires --download-url <url>")
        }
        let releaseNotesURL = parsed.flagValue("--release-notes")
        let isPrerelease = parsed.has("--prerelease") || version.range(of: "(?i)beta|alpha|rc", options: .regularExpression) != nil

        let dmgURL = URL(fileURLWithPath: dmgPath)
        let data = try Data(contentsOf: dmgURL)
        let priv = try loadPrivateKey(explicit: parsed.flagValue("--private-key"))
        let sig = try SparkleEdSignature.sign(artifact: data, privateKeyRaw: priv)

        let pubDate = sparkleDate(Date())
        var lines: [String] = []
        lines.append("    <item>")
        lines.append("      <title>321Doit \(escapeXMLBasic(version))</title>")
        if let releaseNotesURL {
            lines.append("      <sparkle:releaseNotesLink>\(escapeXMLBasic(releaseNotesURL))</sparkle:releaseNotesLink>")
        }
        lines.append("      <pubDate>\(escapeXMLBasic(pubDate))</pubDate>")
        if isPrerelease {
            lines.append("      <sparkle:channel>beta</sparkle:channel>")
        }
        lines.append("      <enclosure url=\"\(escapeXMLBasic(downloadURL.absoluteString))\"")
        lines.append("                 sparkle:shortVersionString=\"\(escapeXMLBasic(version))\"")
        lines.append("                 sparkle:version=\"\(escapeXMLBasic(build))\"")
        lines.append("                 length=\"\(data.count)\"")
        lines.append("                 type=\"application/octet-stream\"")
        lines.append("                 sparkle:edSignature=\"\(sig)\" />")
        lines.append("    </item>")
        print(lines.joined(separator: "\n"))
    }

    // MARK: Key loading

    static func loadPrivateKey(explicit: String?) throws -> Data {
        if let explicit {
            let url = URL(fileURLWithPath: explicit)
            let raw = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            return try base64Decode(raw, label: "private key")
        }
        if let env = ProcessInfo.processInfo.environment["SPARKLE_PRIVATE_KEY"],
           !env.isEmpty {
            return try base64Decode(env, label: "private key (SPARKLE_PRIVATE_KEY)")
        }
        let defaultPath = URL(fileURLWithPath: "dist/sparkle-private.key")
        if FileManager.default.fileExists(atPath: defaultPath.path) {
            let raw = try String(contentsOf: defaultPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            return try base64Decode(raw, label: "private key")
        }
        throw CLIError("no private key supplied (use --private-key, $SPARKLE_PRIVATE_KEY, or ./dist/sparkle-private.key)")
    }

    static func loadPublicKey(explicit: String?) throws -> Curve25519.Signing.PublicKey {
        if let explicit {
            // Accept both a path and a raw base64 blob — the CLI is for
            // release plumbing, so this dual-form keeps shell scripts terse.
            if FileManager.default.fileExists(atPath: explicit) {
                let raw = try String(contentsOf: URL(fileURLWithPath: explicit), encoding: .utf8)
                return try SparkleEdSignature.makePublicKey(fromBase64: raw)
            }
            return try SparkleEdSignature.makePublicKey(fromBase64: explicit)
        }
        let defaultPath = URL(fileURLWithPath: "dist/sparkle-public.key")
        if FileManager.default.fileExists(atPath: defaultPath.path) {
            let raw = try String(contentsOf: defaultPath, encoding: .utf8)
            return try SparkleEdSignature.makePublicKey(fromBase64: raw)
        }
        throw CLIError("no public key supplied (use --public-key or ./dist/sparkle-public.key)")
    }

    static func base64Decode(_ string: String, label: String) throws -> Data {
        guard let data = Data(base64Encoded: string) else {
            throw CLIError("malformed base64 \(label)")
        }
        return data
    }

    // MARK: XML / date helpers

    static func escapeXMLBasic(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
             .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func escapeXMLBasic(_ url: URL) -> String { escapeXMLBasic(url.absoluteString) }

    static let pubDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss '+0000'"
        return f
    }()

    static func sparkleDate(_ date: Date) -> String {
        pubDateFormatter.string(from: date)
    }

    // MARK: Misc

    static let usage: String = """
    SparkleSign — Sparkle 2.x-compatible Ed25519 signer for 321Doit

    Subcommands:
      generate-keys [<dir>]
      sign <dmg> [--private-key <path>]
      verify <dmg> --signature <base64> [--public-key <path-or-base64>]
      appcast <dmg> --version <v> --build <b> --download-url <u>
                    [--release-notes <u>] [--prerelease]
                    [--private-key <path>]

    Defaults:
      private key path: ./dist/sparkle-private.key (or $SPARKLE_PRIVATE_KEY)
      public key path:  ./dist/sparkle-public.key

    """
}

struct CLIError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct ArgParser {
    let positional: [String]
    private let flags: [String: String]

    init(args: [String]) throws {
        var pos: [String] = []
        var fl: [String: String] = [:]
        var iter = args.makeIterator()
        while let arg = iter.next() {
            if arg.hasPrefix("--") {
                if let next = iter.next(), !next.hasPrefix("--") {
                    fl[arg] = next
                } else {
                    fl[arg] = ""
                    if let next = arg as String?, next.hasPrefix("--") {
                        // re-feed: actually iterators can't be peeked easily; we
                        // accept that flags requiring values *must* have one.
                        // The `has(...)` helper handles boolean-style flags.
                    }
                }
            } else {
                pos.append(arg)
            }
        }
        self.positional = pos
        self.flags = fl
    }

    func flagValue(_ flag: String) -> String? {
        guard let v = flags[flag], !v.isEmpty else { return nil }
        return v
    }

    func has(_ flag: String) -> Bool { flags[flag] != nil }
}
