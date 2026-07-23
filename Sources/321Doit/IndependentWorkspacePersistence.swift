import Foundation

extension Notification.Name {
    static let open321DoitProject = Notification.Name("321doit.openProjectURL")
}

enum IndependentWorkspacePersistence {
    private static let restoreKey = "321doit.independentWorkspace.restoreOnLaunch"
    private static let restoreProjectPathKey = "321doit.independentWorkspace.restoreProjectPath"

    static var projectFolderURL: URL {
        applicationSupportURL.appendingPathComponent("IndependentWorkspace", isDirectory: true)
    }

    static var storyboardFolderURL: URL {
        applicationSupportURL.appendingPathComponent("Storyboard", isDirectory: true)
    }

    static var restoreProjectURL: URL {
        if let path = UserDefaults.standard.string(forKey: restoreProjectPathKey) {
            let candidate = URL(fileURLWithPath: path).standardizedFileURL
            if ProjectRepository.isProjectFolder(candidate) {
                return candidate
            }
        }
        return projectFolderURL
    }

    static var shouldRestore: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: restoreKey) != nil {
            return defaults.bool(forKey: restoreKey)
                && ProjectRepository.isProjectFolder(restoreProjectURL)
        }
        return ProjectRepository.isProjectFolder(projectFolderURL)
            || FileManager.default.fileExists(
                atPath: storyboardFolderURL.appendingPathComponent("independent-storyboard.json").path
            )
    }

    static func markForRestore(at projectURL: URL? = nil) {
        UserDefaults.standard.set(true, forKey: restoreKey)
        if let projectURL, projectURL.standardizedFileURL != projectFolderURL.standardizedFileURL {
            UserDefaults.standard.set(projectURL.standardizedFileURL.path, forKey: restoreProjectPathKey)
        } else {
            UserDefaults.standard.removeObject(forKey: restoreProjectPathKey)
        }
    }

    static func discardPersistedData() throws {
        let manager = FileManager.default
        for url in [projectFolderURL, storyboardFolderURL] where manager.fileExists(atPath: url.path) {
            try manager.removeItem(at: url)
        }
        UserDefaults.standard.set(false, forKey: restoreKey)
        UserDefaults.standard.removeObject(forKey: restoreProjectPathKey)
    }

    private static var applicationSupportURL: URL {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("321Doit", isDirectory: true)
    }
}
