import Foundation
import WidgetKit
import OSLog

enum WidgetLoader {
    private static let log = Logger(subsystem: "com.zkjjs.codexquota", category: "WidgetTimeline")

    // WidgetKit snapshots must be quick. Networking belongs in the timeline request.
    static func initialEntry(connection: ServerConnection? = nil, manual: Bool = false) -> QuotaEntry {
        guard (connection ?? SharedStore.widgetConnection()) != nil else {
            return QuotaEntry(date: .now, snapshot: nil, message: configurationHint)
        }
        return QuotaEntry(date: .now, snapshot: manual ? nil : SharedStore.loadSnapshot(),
                          message: "正在读取服务器额度…")
    }

    static var configurationHint: String {
        if #available(iOS 17.0, *) { return "长按 → 编辑小组件，填写查询码" }
        return "打开 App 配对；当前签名需支持 App Groups"
    }

    static func entry(connection: ServerConnection? = nil, manual: Bool = false,
                      fetch: (ServerConnection) async throws -> QuotaSnapshot = {
                          try await QuotaClient.fetch($0, timeout: 12)
                      }) async -> QuotaEntry {
        guard let connection = connection ?? SharedStore.widgetConnection() else {
            log.info("timeline.noConfiguration")
            return QuotaEntry(date: .now, snapshot: nil, message: configurationHint)
        }
        log.info("timeline.begin manual=\(manual, privacy: .public)")
        do {
            let value = try await fetch(connection)
            if !manual { SharedStore.saveSnapshot(value) }
            log.info("timeline.success windows=\(value.windows.count, privacy: .public)")
            return QuotaEntry(date: .now, snapshot: value, message: nil)
        } catch {
            // Never log credentials or the error's URL, and never mix manual-server caches.
            log.error("timeline.failed; returning a visible status entry")
            let cached = manual ? nil : SharedStore.loadSnapshot()
            return QuotaEntry(date: .now, snapshot: cached, message: error.localizedDescription)
        }
    }

    static func timeline(_ entry: QuotaEntry) -> Timeline<QuotaEntry> {
        let refresh = entry.date.addingTimeInterval(entry.snapshot == nil ? 120 : 900)
        let entries = QuotaSchedule.dates(snapshot: entry.snapshot, now: entry.date).map {
            QuotaEntry(date: $0, snapshot: entry.snapshot, message: entry.message)
        }
        return Timeline(entries: entries, policy: .after(refresh))
    }
}
