import CryptoKit
import Foundation

enum FileVerifier {
    static func verify(_ file: URL, expectedMD5: String?) async throws {
        guard let expectedMD5 else { return }
        try await Task.detached(priority: .utility) {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var hash = Insecure.MD5()
            while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
            let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest.caseInsensitiveCompare(expectedMD5) == .orderedSame else { throw AppFailure(message: "文件校验失败，请重新下载。") }
        }.value
    }
}
