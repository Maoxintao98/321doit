import Foundation

struct SecurityScopedAccessToken {
    let url: URL
    let didStart: Bool

    func stop() {
        if didStart {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

enum SecurityScopedBookmarks {
    private static let keyPrefix = "321doit.securityScopedBookmark"

    static func save(url: URL, role: String) {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: key(role: role, path: url.standardizedFileURL.path))
        } catch {
            // Non-sandboxed builds and some system paths may not produce
            // security-scoped bookmarks. Direct file access still works there.
            AppLogger.log(.detailed, category: "bookmarks", "Could not save bookmark for role \(role): \(error.localizedDescription)")
        }
    }

    static func resolvedURL(for url: URL, role: String) -> URL {
        let standardized = url.standardizedFileURL
        guard let data = UserDefaults.standard.data(forKey: key(role: role, path: standardized.path)) else {
            return standardized
        }

        do {
            var stale = false
            let resolved = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if stale {
                save(url: resolved, role: role)
            }
            return resolved.standardizedFileURL
        } catch {
            AppLogger.log(.warning, category: "bookmarks", "Could not resolve bookmark for role \(role); using original path: \(error.localizedDescription)")
            return standardized
        }
    }

    static func startAccessing(urls: [(url: URL, role: String)]) -> [SecurityScopedAccessToken] {
        var seen = Set<String>()
        return urls.compactMap { item in
            let resolved = resolvedURL(for: item.url, role: item.role)
            guard seen.insert(resolved.path).inserted else { return nil }
            return SecurityScopedAccessToken(
                url: resolved,
                didStart: resolved.startAccessingSecurityScopedResource()
            )
        }
    }

    private static func key(role: String, path: String) -> String {
        let escapedPath = path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? path
        return "\(keyPrefix).\(role).\(escapedPath)"
    }
}

/// Explicit folders or mounted disks that Mira may pass to its local MCP
/// helper. Keeping this list separate from ordinary picker history prevents an
/// AI session from inheriting broad file-system access by accident.
enum MiraAuthorizedRoots {
    private static let pathsKey = "321doit.mira.authorized-root-paths"
    private static let bookmarkRole = "mira-authorized-root"

    static func all() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: pathsKey) ?? []
        var seen = Set<String>()
        return paths.compactMap { path in
            let resolved = SecurityScopedBookmarks.resolvedURL(for: URL(fileURLWithPath: path), role: bookmarkRole)
            return seen.insert(resolved.path).inserted ? resolved : nil
        }
    }

    static func add(_ url: URL) {
        let resolved = url.standardizedFileURL
        var paths = UserDefaults.standard.stringArray(forKey: pathsKey) ?? []
        if !paths.contains(resolved.path) {
            paths.append(resolved.path)
            UserDefaults.standard.set(paths, forKey: pathsKey)
        }
        SecurityScopedBookmarks.save(url: resolved, role: bookmarkRole)
    }

    static func remove(_ url: URL) {
        let path = url.standardizedFileURL.path
        let paths = (UserDefaults.standard.stringArray(forKey: pathsKey) ?? []).filter { $0 != path }
        UserDefaults.standard.set(paths, forKey: pathsKey)
        UserDefaults.standard.removeObject(forKey: "321doit.securityScopedBookmark.\(bookmarkRole).\(path.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? path)")
    }
}
