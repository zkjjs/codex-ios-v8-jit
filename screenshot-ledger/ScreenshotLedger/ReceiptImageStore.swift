import UIKit

struct ReceiptImageStore {
    var directory: URL

    static func applicationBase() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let base = root.appendingPathComponent("ScreenshotLedger", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func saveJPEG(_ data: Data, id: UUID) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.86) else {
            throw CocoaError(.coderInvalidValue)
        }
        let filename = "\(id.uuidString).jpg"
        try jpeg.write(to: directory.appendingPathComponent(filename), options: .atomic)
        return filename
    }

    func data(named filename: String) -> Data? {
        guard !filename.isEmpty, !filename.contains("/"), filename != ".", filename != ".." else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(filename))
    }

    func delete(_ filename: String) {
        guard !filename.isEmpty, !filename.contains("/"), filename != ".", filename != ".." else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }
}
