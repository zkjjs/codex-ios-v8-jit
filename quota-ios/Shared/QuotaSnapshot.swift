import Foundation

struct QuotaSnapshot: Codable {
    let version: Int
    let updatedAt: TimeInterval
    let stale: Bool
    let plan: String?
    let windows: [QuotaWindow]

    var updatedDate: Date { Date(timeIntervalSince1970: updatedAt) }
    func isStale(at date: Date = Date()) -> Bool { stale || date.timeIntervalSince(updatedDate) > 900 }

    static let preview = QuotaSnapshot(version: 1, updatedAt: Date().timeIntervalSince1970,
        stale: false, plan: "plus", windows: [
            QuotaWindow(id: "primary", title: "5 小时额度", usedPercent: 69,
                        remainingPercent: 31, windowMinutes: 300,
                        resetsAt: Date().addingTimeInterval(7200).timeIntervalSince1970),
            QuotaWindow(id: "secondary", title: "每周额度", usedPercent: 40,
                        remainingPercent: 60, windowMinutes: 10080,
                        resetsAt: Date().addingTimeInterval(345600).timeIntervalSince1970)
        ])
}

struct QuotaWindow: Codable, Identifiable {
    let id: String
    let title: String
    let usedPercent: Double
    let remainingPercent: Double
    let windowMinutes: Double?
    let resetsAt: TimeInterval?

    var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
    var progress: Double { min(1, max(0, remainingPercent / 100)) }
    var remainingText: String { String(format: "%.0f", remainingPercent) }
    func awaitingReset(at date: Date = Date()) -> Bool {
        guard let resetDate else { return false }
        return resetDate <= date
    }
}
