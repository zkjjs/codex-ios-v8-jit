import Foundation

enum AppGroupError: Error {
    case unavailable
}

enum AppGroup {
    static let identifier = "group.dev.snapledger.shared"
    static let pendingDirectoryName = "PendingImports"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static func pendingDirectory() -> URL? {
        guard let containerURL else { return nil }
        let directory = containerURL.appendingPathComponent(pendingDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func savePending(_ data: Data) throws -> URL {
        guard let directory = pendingDirectory() else { throw AppGroupError.unavailable }
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("img")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func pendingFiles() -> [URL] {
        guard let directory = pendingDirectory() else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "img" }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return left < right
            }
    }
}
