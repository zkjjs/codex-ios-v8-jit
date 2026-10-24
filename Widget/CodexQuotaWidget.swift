import SwiftUI
import WidgetKit
import QuotaCore

struct QuotaEntry: TimelineEntry {
    let date: Date
    let state: SharedState?
    let unavailable: Bool
}

struct QuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: Date(), state: nil, unavailable: false)
    }
    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(QuotaEntry(date: Date(), state: try? SnapshotStore.shared.read(), unavailable: !SnapshotStore.shared.available))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        Task {
            await fetchIfPossible()
            let now = Date()
            let state = try? SnapshotStore.shared.read()
            let unavailable = !SnapshotStore.shared.available
            var entries = [QuotaEntry(date: now, state: state, unavailable: unavailable)]
            // Entries at reset boundaries change the text to pending without inventing a new balance.
            for boundary in state?.snapshot?.timelineBoundaries(after: now) ?? [] {
                entries.append(QuotaEntry(date: boundary, state: state, unavailable: unavailable))
            }
            var refresh = now.addingTimeInterval(1800)
            if let next = state?.snapshot?.nextReset(after: now) { refresh = min(refresh, next.addingTimeInterval(5)) }
            if let retry = state?.retryAt { refresh = max(refresh, retry) }
            completion(Timeline(entries: entries, policy: .after(refresh)))
        }
    }
    private func fetchIfPossible() async {
        let cache = SnapshotStore.shared
        guard let state = try? cache.read(), let id = state.sessionID else { return }
        if let retry = state.retryAt, retry > Date() { return }
        // Do not repeat an app refresh that just populated the widget.
        if let snapshot = state.snapshot, Date().timeIntervalSince(snapshot.fetchedAt) < 60,
           !snapshot.windows.contains(where: { $0.needsResetRefresh(at: Date()) }) { return }
        do {
            guard let grant: WidgetGrant = try SecureStore.read("widget-grant", shared: true), grant.sessionID == id else {
                try? cache.failure("请打开应用同步登录", retryAt: nil, sessionID: id)
                return
            }
            guard grant.expiresAt.timeIntervalSinceNow > 60 else {
                try? cache.failure("请打开应用续期登录", retryAt: nil, sessionID: id)
                return
            }
            let fresh = try await HTTPClient.shared.usage(accessToken: grant.accessToken, accountID: grant.accountID)
            try cache.write(fresh, sessionID: id)
        } catch {
            let service = error as? ServiceError
            let message = service?.status == 401 ? "请打开应用重新登录" : "暂未同步 · 显示上次数据"
            let retry = service?.retryAt ?? Date().addingTimeInterval(300)
            try? cache.failure(message, retryAt: retry, sessionID: id)
        }
    }
}

struct QuotaWidgetView: View {
    let entry: QuotaEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "terminal").foregroundStyle(Color.quotaMint)
                Text("Codex").font(.caption.weight(.bold))
                Spacer(minLength: 0)
                if let snapshot = entry.state?.snapshot {
                    Text((snapshot.plan ?? "").uppercased()).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            if entry.unavailable { empty("请检查签名权限", detail: "需保留 App Groups 和小组件扩展") }
            else if entry.state?.privacyHidden == true { empty("额度已隐藏", detail: "打开应用可调整显示设置") }
            else if entry.state?.sessionID == nil { empty("连接你的账号", detail: "点按打开应用登录") }
            else if let snapshot = entry.state?.snapshot, !snapshot.windows.isEmpty {
                if family == .systemSmall { small(snapshot) }
                else { medium(snapshot) }
            } else { empty("等待额度数据", detail: entry.state?.message ?? "点按打开应用同步") }
        }
        .padding(14)
        .containerBackground(for: .widget) { Color(uiColor: .secondarySystemGroupedBackground) }
        .widgetURL(URL(string: "codexquota://refresh"))
        .privacySensitive()
    }
    private func small(_ snapshot: QuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let window = snapshot.windows.first {
                HStack(spacing: 9) {
                    QuotaRing(percent: window.remainingPercent, compact: true).frame(width: 60, height: 60)
                    Text(window.title).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                ResetLabel(window: window, now: entry.date, compact: true)
            }
            footer(snapshot)
        }
    }
    private func medium(_ snapshot: QuotaSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(Array(snapshot.windows.prefix(2))) { window in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 9) {
                        QuotaRing(percent: window.remainingPercent, compact: true, tint: window.id == "primary" ? .quotaMint : .quotaBlue)
                            .frame(width: 55, height: 55)
                        Text(window.title).font(.caption.weight(.medium)).lineLimit(2)
                    }
                    Text(window.resetAt != nil && window.resetAt == snapshot.nextReset(after: entry.date) ? "最近重置" : "下次重置")
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                    ResetLabel(window: window, now: entry.date, compact: true)
                    if window.id == snapshot.windows.first?.id { footer(snapshot) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    private func footer(_ snapshot: QuotaSnapshot) -> some View {
        HStack(spacing: 3) {
            Circle().fill(entry.state?.message != nil || snapshot.isStale(at: entry.date) ? Color.orange : Color.quotaMint).frame(width: 4, height: 4)
            Text(entry.state?.message ?? (snapshot.isStale(at: entry.date) ? "待更新" : "已同步"))
                .lineLimit(1)
            Text(snapshot.fetchedAt, format: .dateTime.hour().minute()).lineLimit(1)
        }.font(.system(size: 8)).foregroundStyle(.secondary)
    }
    private func empty(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CodexQuotaWidget: Widget {
    let kind = "CodexQuotaWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaProvider()) { QuotaWidgetView(entry: $0) }
            .configurationDisplayName("Codex 额度")
            .description("剩余额度、下一次重置时间和倒计时。")
            .supportedFamilies([.systemSmall, .systemMedium])
            .contentMarginsDisabled()
    }
}

@main
struct CodexQuotaWidgets: WidgetBundle {
    var body: some Widget { CodexQuotaWidget() }
}
