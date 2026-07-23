import AppKit
import CryptoKit
import Darwin
import Foundation

/// Sparkle-compatible "check for updates" implementation. It speaks the same
/// `appcast.xml` format and Ed25519 signing scheme that Sparkle 2.x does, but
/// without bundling the `Sparkle.framework` binary — verification runs on
/// CryptoKit. The exact verified artifact is cached locally and opened; the
/// browser is never asked to download a second, potentially different file.
///
/// Why not the full Sparkle framework: Sparkle's in-app installer wants a
/// stable Apple Team ID to validate the new bundle's code signature against
/// the running one. 321Doit ships ad-hoc-signed (no Apple Developer ID), so
/// the in-app install path would need to be told to skip that check, which
/// undermines the security story Sparkle provides. Sending the user to the
/// signed-and-verified DMG keeps the trust path honest.
///
/// Forward path: when the app gains a paid Developer ID, dropping
/// `Sparkle.framework` in is mechanical — the appcast format is identical
/// and the Ed25519 keys carry over.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()

    private var inflight: Task<Void, Never>?

    /// Result from a single appcast fetch + verify pass.
    struct Update {
        var version: String
        var build: String?
        var releaseNotesURL: URL?
        var verifiedArtifactURL: URL
        var lengthBytes: Int?
        var publishedAt: String?
    }

    enum CheckError: LocalizedError {
        case missingFeedURL
        case missingPublicKey
        case feedFetchFailed(URL, Error)
        case malformedAppcast(String)
        case noEnclosure
        case signatureFailure(String)
        case artifactCacheFailure(String)

        var errorDescription: String? {
            switch self {
            case .missingFeedURL:
                return "No SUFeedURL configured in Info.plist."
            case .missingPublicKey:
                return "No SUPublicEDKey configured in Info.plist — refusing to fetch updates without a verification key."
            case .feedFetchFailed(let url, let error):
                return "Could not fetch update feed at \(url.absoluteString): \(error.localizedDescription)"
            case .malformedAppcast(let detail):
                return "Update feed could not be parsed: \(detail)"
            case .noEnclosure:
                return "Update feed has no enclosure (download URL)."
            case .signatureFailure(let detail):
                return "Update signature did not verify: \(detail). Aborting — refusing to point you at an untrusted download."
            case .artifactCacheFailure(let detail):
                return "The verified update could not be saved locally: \(detail)"
            }
        }
    }

    /// Triggered by the menu item, by `autoCheckForUpdates` once on launch
    /// (if enabled), and from preferences. Coalesces concurrent requests.
    func checkForUpdates(receiveBeta: Bool, presentNoUpdate: Bool) {
        if let inflight, !inflight.isCancelled { return }
        inflight = Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.inflight = nil } }
            do {
                let update = try await self.runCheck(receiveBeta: receiveBeta)
                guard update != nil || presentNoUpdate else { return }
                await MainActor.run { self.presentUpdateAvailable(update) }
            } catch CheckError.missingFeedURL where !presentNoUpdate {
                // Silent skip when launched-on-startup and feed isn't configured yet.
                return
            } catch {
                await MainActor.run { self.presentError(error, presentNoUpdate: presentNoUpdate) }
            }
        }
    }

    // MARK: - Network + verification

    private func runCheck(receiveBeta: Bool) async throws -> Update? {
        guard
            let feedString = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            !feedString.isEmpty,
            let feedURL = URL(string: feedString)
        else {
            throw CheckError.missingFeedURL
        }
        guard
            let pubKeyB64 = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
            !pubKeyB64.isEmpty
        else {
            throw CheckError.missingPublicKey
        }

        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try SparkleEdSignature.makePublicKey(fromBase64: pubKeyB64)
        } catch {
            throw CheckError.malformedAppcast("invalid SUPublicEDKey: \(error.localizedDescription)")
        }

        let xmlData: Data
        do {
            (xmlData, _) = try await URLSession.shared.data(from: feedURL)
        } catch {
            throw CheckError.feedFetchFailed(feedURL, error)
        }

        let entries = try AppcastParser.parse(xmlData: xmlData)
        let candidates = entries
            .filter { receiveBeta || !$0.isPrerelease }
            .sorted(by: {
                Self.releaseCompare(
                    version: $0.version,
                    build: $0.build,
                    toVersion: $1.version,
                    build: $1.build
                ) == .orderedDescending
            })

        guard let newest = candidates.first else { return nil }

        guard Self.releaseCompare(
            version: newest.version,
            build: newest.build,
            toVersion: appVersionString,
            build: appBuildNumberString
        ) == .orderedDescending else {
            return nil
        }

        let verifiedArtifactURL = try await verifiedArtifact(
            for: newest,
            publicKey: publicKey
        )

        return Update(
            version: newest.version,
            build: newest.build,
            releaseNotesURL: newest.releaseNotesURL,
            verifiedArtifactURL: verifiedArtifactURL,
            lengthBytes: newest.lengthBytes,
            publishedAt: newest.pubDate
        )
    }

    // MARK: - Verified artifact cache

    private func verifiedArtifact(
        for entry: AppcastParser.Entry,
        publicKey: Curve25519.Signing.PublicKey
    ) async throws -> URL {
        let fileManager = FileManager.default
        let cacheRoot: URL
        do {
            let caches = try fileManager.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            cacheRoot = caches.appendingPathComponent("321Doit/VerifiedUpdates", isDirectory: true)
            try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        } catch {
            throw CheckError.artifactCacheFailure(error.localizedDescription)
        }

        let signatureID = SHA256.hash(data: Data(entry.signature.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        let remoteName = entry.downloadURL.lastPathComponent.isEmpty ? "321Doit-update.dmg" : entry.downloadURL.lastPathComponent
        let cachedURL = cacheRoot.appendingPathComponent("\(signatureID)-\(remoteName)")

        if fileManager.fileExists(atPath: cachedURL.path) {
            do {
                try verifyArtifact(at: cachedURL, signature: entry.signature, publicKey: publicKey)
                try clearQuarantineFromVerifiedArtifact(at: cachedURL)
                return cachedURL
            } catch {
                try? fileManager.removeItem(at: cachedURL)
            }
        }

        let temporaryURL: URL
        do {
            let (downloadedURL, response) = try await URLSession.shared.download(from: entry.downloadURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            temporaryURL = downloadedURL
        } catch {
            throw CheckError.feedFetchFailed(entry.downloadURL, error)
        }

        do {
            try verifyArtifact(at: temporaryURL, signature: entry.signature, publicKey: publicKey)
            if fileManager.fileExists(atPath: cachedURL.path) {
                try fileManager.removeItem(at: cachedURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: cachedURL)
            try clearQuarantineFromVerifiedArtifact(at: cachedURL)
            return cachedURL
        } catch let error as CheckError {
            throw error
        } catch let error as SparkleEdSignature.SignatureError {
            throw CheckError.signatureFailure(error.localizedDescription)
        } catch {
            throw CheckError.artifactCacheFailure(error.localizedDescription)
        }
    }

    private func verifyArtifact(
        at url: URL,
        signature: String,
        publicKey: Curve25519.Signing.PublicKey
    ) throws {
        let artifact = try Data(contentsOf: url, options: [.mappedIfSafe])
        try SparkleEdSignature.verify(
            artifact: artifact,
            signatureBase64: signature,
            publicKey: publicKey
        )
    }

    /// Ed25519 verification is the trust boundary for ad-hoc releases. Once
    /// the exact cached DMG has passed that check, remove only its quarantine
    /// attribute so the enclosed PKG can open normally. Manual browser
    /// downloads remain subject to Gatekeeper and the usual right-click Open
    /// flow because they did not pass through this verifier.
    private func clearQuarantineFromVerifiedArtifact(at url: URL) throws {
        let result = url.path.withCString { path in
            "com.apple.quarantine".withCString { name in
                removexattr(path, name, 0)
            }
        }
        if result != 0 && errno != ENOATTR {
            throw CheckError.artifactCacheFailure(
                "verified the update, but could not clear its quarantine attribute (errno \(errno))"
            )
        }
    }

    /// Compare semantic-ish version strings. Pure function, safely callable
    /// from any actor — used by the test suite directly without hopping to
    /// the main actor.
    nonisolated static func versionCompare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        if lhs == rhs { return .orderedSame }
        // Trim leading "v" if a tag-style version snuck in.
        let l = lhs.hasPrefix("v") ? String(lhs.dropFirst()) : lhs
        let r = rhs.hasPrefix("v") ? String(rhs.dropFirst()) : rhs
        return l.compare(r, options: [.numeric])
    }

    nonisolated static func releaseCompare(
        version lhsVersion: String,
        build lhsBuild: String?,
        toVersion rhsVersion: String,
        build rhsBuild: String?
    ) -> ComparisonResult {
        let versionResult = versionCompare(lhsVersion, rhsVersion)
        guard versionResult == .orderedSame else { return versionResult }
        let lhs = lhsBuild?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        let rhs = rhsBuild?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        if lhs == rhs { return .orderedSame }
        return lhs.compare(rhs, options: [.numeric])
    }

    // MARK: - UI presentation

    private func presentUpdateAvailable(_ update: Update?) {
        guard let update else {
            presentNoUpdate()
            return
        }
        let alert = NSAlert()
        let releaseLabel = update.build.map { "\(update.version) (build \($0))" } ?? update.version
        alert.messageText = "321Doit \(releaseLabel) is available"
        var info = "You have \(appVersionString) (build \(appBuildNumberString))."
        if let bytes = update.lengthBytes {
            info += "\nDownload size: \(formatBytes(UInt64(bytes)))"
        }
        if let date = update.publishedAt {
            info += "\nPublished: \(date)"
        }
        info += "\n\nThe download was verified against the embedded Sparkle public key (Ed25519) before you were shown this dialog."
        alert.informativeText = info
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Verified Installer")
        if update.releaseNotesURL != nil {
            alert.addButton(withTitle: "Release Notes")
        }
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(update.verifiedArtifactURL)
        case .alertSecondButtonReturn where update.releaseNotesURL != nil:
            if let url = update.releaseNotesURL { NSWorkspace.shared.open(url) }
        default:
            break
        }
    }

    private func presentNoUpdate() {
        let alert = NSAlert()
        alert.messageText = "321Doit is up to date"
        alert.informativeText = "You're running version \(appVersionString) (build \(appBuildNumberString))."
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func presentError(_ error: Error, presentNoUpdate: Bool) {
        guard presentNoUpdate else {
            // Silent on automatic launch-on-startup checks. Logging only.
            NSLog("[321Doit] Update check failed silently: \(error.localizedDescription)")
            AppLogger.log(.warning, category: "update", "Automatic update check failed: \(error.localizedDescription)")
            return
        }
        AppLogger.log(.error, category: "update", "Manual update check failed: \(error.localizedDescription)")
        let alert = NSAlert()
        alert.messageText = "Update check failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

/// Tiny appcast XML parser using `XMLParser`. We deliberately avoid
/// pulling in a third-party RSS/Atom library — the appcast schema is
/// narrow and stable.
///
/// Internal (not private) so smoke tests can exercise the parser without
/// having to set up Bundle.main and URLSession plumbing.
enum AppcastParser {
    struct Entry {
        var version: String
        var build: String?
        var pubDate: String?
        var releaseNotesURL: URL?
        var downloadURL: URL
        var signature: String
        var lengthBytes: Int?
        var isPrerelease: Bool
    }

    static func parse(xmlData: Data) throws -> [Entry] {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: xmlData)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        guard parser.parse() else {
            let detail = parser.parserError?.localizedDescription ?? "unknown XMLParser error"
            throw UpdateChecker.CheckError.malformedAppcast(detail)
        }
        if delegate.entries.isEmpty {
            throw UpdateChecker.CheckError.malformedAppcast("no <item> entries with valid <enclosure> in feed")
        }
        return delegate.entries
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var entries: [Entry] = []

        private var currentVersion: String?
        private var currentBuild: String?
        private var currentPubDate: String?
        private var currentReleaseNotes: URL?
        private var currentDownload: URL?
        private var currentSignature: String?
        private var currentLength: Int?
        private var currentIsPrerelease = false

        private var inItem = false
        private var captureBuffer = ""
        private var captureCurrent = false

        func parser(_ parser: XMLParser,
                    didStartElement elementName: String,
                    namespaceURI: String?,
                    qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            switch elementName {
            case "item":
                resetItem()
                inItem = true
            case "enclosure" where inItem:
                if let urlString = attributeDict["url"], let url = URL(string: urlString) {
                    currentDownload = url
                }
                if let v = attributeDict["sparkle:shortVersionString"], !v.isEmpty {
                    currentVersion = v
                }
                if let v = attributeDict["sparkle:version"], !v.isEmpty {
                    currentBuild = v
                }
                if let sig = attributeDict["sparkle:edSignature"], !sig.isEmpty {
                    currentSignature = sig
                }
                if let len = attributeDict["length"], let bytes = Int(len) {
                    currentLength = bytes
                }
            case "sparkle:releaseNotesLink", "releaseNotesLink", "title", "pubDate", "sparkle:shortVersionString", "sparkle:version":
                captureBuffer = ""
                captureCurrent = inItem
            case "sparkle:channel" where inItem:
                captureBuffer = ""
                captureCurrent = true
            default:
                captureCurrent = false
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if captureCurrent {
                captureBuffer.append(string)
            }
        }

        func parser(_ parser: XMLParser,
                    didEndElement elementName: String,
                    namespaceURI: String?,
                    qualifiedName qName: String?) {
            let trimmed = captureBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            switch elementName {
            case "sparkle:releaseNotesLink", "releaseNotesLink":
                if let url = URL(string: trimmed) { currentReleaseNotes = url }
            case "pubDate":
                currentPubDate = trimmed
            case "sparkle:shortVersionString" where currentVersion == nil:
                currentVersion = trimmed
            case "sparkle:version" where currentBuild == nil:
                currentBuild = trimmed
            case "sparkle:channel":
                let lower = trimmed.lowercased()
                if lower.contains("beta") || lower.contains("alpha") || lower.contains("nightly") {
                    currentIsPrerelease = true
                }
            case "item":
                if let v = currentVersion,
                   let url = currentDownload,
                   let sig = currentSignature {
                    entries.append(Entry(
                        version: v,
                        build: currentBuild,
                        pubDate: currentPubDate,
                        releaseNotesURL: currentReleaseNotes,
                        downloadURL: url,
                        signature: sig,
                        lengthBytes: currentLength,
                        isPrerelease: currentIsPrerelease || v.range(of: "(?i)beta|alpha|rc", options: .regularExpression) != nil
                    ))
                }
                resetItem()
                inItem = false
            default:
                break
            }
            captureCurrent = false
            captureBuffer = ""
        }

        private func resetItem() {
            currentVersion = nil
            currentBuild = nil
            currentPubDate = nil
            currentReleaseNotes = nil
            currentDownload = nil
            currentSignature = nil
            currentLength = nil
            currentIsPrerelease = false
        }
    }
}
