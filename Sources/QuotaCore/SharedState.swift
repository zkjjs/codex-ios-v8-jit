import Foundation

public struct SharedState: Codable, Sendable {
    public var sessionID: UUID?
    public var snapshot: QuotaSnapshot?
    public var message: String?
    public var retryAt: Date?
    public var privacyHidden: Bool
    public init(sessionID: UUID?, snapshot: QuotaSnapshot?, message: String?, retryAt: Date?, privacyHidden: Bool = false) {
        self.sessionID = sessionID
        self.snapshot = snapshot
        self.message = message
        self.retryAt = retryAt
        self.privacyHidden = privacyHidden
    }
    public mutating func apply(_ fresh: QuotaSnapshot, sessionID: UUID, now: Date) {
        guard self.sessionID == sessionID else { return }
        guard snapshot == nil || snapshot!.fetchedAt <= fresh.fetchedAt else { return }
        snapshot = fresh
        // A request started before a concurrent 429 is allowed to finish, but must not
        // remove that response's future Retry-After deadline.
        if retryAt.map({ $0 > now }) != true {
            message = nil
            retryAt = nil
        }
    }
}

extension QuotaSnapshot {
    public func timelineBoundaries(after now: Date) -> [Date] {
        let resets = windows.compactMap(\.resetAt).map { $0.addingTimeInterval(1) }
        let stale = fetchedAt.addingTimeInterval(3601)
        return Set(resets + [stale]).filter { $0 > now && $0 < now.addingTimeInterval(86400) }.sorted()
    }
}

public enum SigningGroups {
    public static func resolve(configured: String, actualDefaultGroup: String?) -> String? {
        guard !configured.isEmpty, !configured.contains("$("), !configured.contains(where: \.isWhitespace) else { return nil }
        func isPrefix(_ text: Substring) -> Bool {
            text.count == 10 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        }
        guard let actualDefaultGroup, let actualPrefix = actualDefaultGroup.split(separator: ".").first,
              isPrefix(actualPrefix) else { return configured }
        let parts = configured.split(separator: ".", maxSplits: 1)
        let suffix = parts.count == 2 && isPrefix(parts[0]) ? String(parts[1]) : configured
        return String(actualPrefix) + "." + suffix
    }
}
