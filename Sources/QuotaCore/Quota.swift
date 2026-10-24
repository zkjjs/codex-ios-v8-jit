import Foundation

public struct QuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let usedPercent: Double?
    public let durationSeconds: Int?
    public let resetAt: Date?
    public var remainingPercent: Double? { usedPercent.map { min(100, max(0, 100 - $0)) } }
    public func needsResetRefresh(at date: Date) -> Bool { resetAt.map { $0 <= date } ?? false }
    public var title: String {
        guard let durationSeconds else { return id == "primary" ? "主要额度" : "长期额度" }
        if durationSeconds == 604800 { return "每周额度" }
        if durationSeconds % 86400 == 0 { return "\(durationSeconds / 86400) 天额度" }
        if durationSeconds % 3600 == 0 { return "\(durationSeconds / 3600) 小时额度" }
        return "\(max(1, durationSeconds / 60)) 分钟额度"
    }
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public let plan: String?
    public let windows: [QuotaWindow]
    public let fetchedAt: Date
    public func nextReset(after date: Date) -> Date? {
        windows.compactMap(\.resetAt).filter { $0 > date }.min()
    }
    public func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(fetchedAt) > 3600 || windows.contains { $0.needsResetRefresh(at: date) }
    }
}

public struct UsageResponse: Decodable, Sendable {
    struct Limits: Decodable, Sendable {
        let primary: WireWindow?
        let secondary: WireWindow?
        enum CodingKeys: String, CodingKey { case primary = "primary_window", secondary = "secondary_window" }
    }
    struct WireWindow: Decodable, Sendable {
        let used: Double?
        let duration: Int?
        let reset: Double?
        enum CodingKeys: String, CodingKey { case used = "used_percent", duration = "limit_window_seconds", reset = "reset_at" }
        func window(id: String) -> QuotaWindow {
            QuotaWindow(id: id, usedPercent: used?.isFinite == true ? used : nil,
                        durationSeconds: duration.flatMap { $0 > 0 ? $0 : nil },
                        resetAt: reset.flatMap { $0 > 0 && $0.isFinite ? Date(timeIntervalSince1970: $0) : nil })
        }
    }
    let plan: String?
    let limits: Limits?
    enum CodingKeys: String, CodingKey { case plan = "plan_type", limits = "rate_limit" }
    public func snapshot(at date: Date) -> QuotaSnapshot {
        QuotaSnapshot(plan: plan, windows: [limits?.primary?.window(id: "primary"), limits?.secondary?.window(id: "secondary")].compactMap { $0 }, fetchedAt: date)
    }
}

public struct DeviceCode: Decodable, Sendable {
    public let deviceAuthID: String
    public let userCode: String
    public let interval: Double
    public let createdAt: Date
    public var expiresAt: Date { createdAt.addingTimeInterval(15 * 60) }
    public var verificationURL: URL { URL(string: "https://auth.openai.com/codex/device")! }
    enum CodingKeys: String, CodingKey {
        case deviceAuthID = "device_auth_id", userCode = "user_code", alternateCode = "usercode", interval
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceAuthID = try container.decode(String.self, forKey: .deviceAuthID)
        userCode = try container.decodeIfPresent(String.self, forKey: .userCode) ?? container.decode(String.self, forKey: .alternateCode)
        let seconds = (try? container.decode(Double.self, forKey: .interval))
            ?? (try? container.decode(String.self, forKey: .interval)).flatMap(Double.init) ?? 5
        interval = min(60, max(5, seconds))
        createdAt = Date()
    }
}

public enum RetryPolicy {
    public static func delay(header: String?, now: Date) -> TimeInterval {
        guard let header else { return 60 }
        if let seconds = Double(header), seconds.isFinite, seconds >= 0 { return max(1, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: header), date > now { return date.timeIntervalSince(now) }
        return 60
    }
}
