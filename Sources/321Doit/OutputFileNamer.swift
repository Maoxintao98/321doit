import Foundation

enum OutputFileNamer {
    private static let timestampLock = NSLock()
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    static func timestamp(_ date: Date) -> String {
        timestampLock.lock()
        defer { timestampLock.unlock() }
        return timestampFormatter.string(from: date)
    }

    static func stem(projectName: String, date: Date, attribute: String) -> String {
        let project = sanitizedComponent(projectName, fallback: "PROJECT")
        let attr = sanitizedComponent(attribute, fallback: "OUTPUT")
        return "\(project)_\(timestamp(date))_\(attr)"
    }

    static func fileName(projectName: String, date: Date, attribute: String, extension ext: String) -> String {
        let cleanExt = ext.trimmingCharacters(in: CharacterSet(charactersIn: ". \n\t"))
        guard !cleanExt.isEmpty else {
            return stem(projectName: projectName, date: date, attribute: attribute)
        }
        return "\(stem(projectName: projectName, date: date, attribute: attribute)).\(cleanExt)"
    }
}
