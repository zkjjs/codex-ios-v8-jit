import SwiftUI
import WidgetKit
import AppIntents

struct QuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: QuotaSnapshot?
    let message: String?
    var preview = false
}

enum WidgetLoader {
    static func entry(connection: ServerConnection? = nil, manual: Bool = false) async -> QuotaEntry {
        guard let connection = connection ?? SharedStore.widgetConnection() else {
            return QuotaEntry(date: .now, snapshot: nil, message: "打开 App 配对服务器")
        }
        do {
            let value = try await QuotaClient.fetch(connection)
            return QuotaEntry(date: .now, snapshot: value, message: nil)
        } catch {
            // Never show a different server's cache for a manually configured widget.
            let cached = manual ? nil : SharedStore.loadSnapshot()
            return QuotaEntry(date: .now, snapshot: cached, message: error.localizedDescription)
        }
    }

    static func timeline(_ entry: QuotaEntry) -> Timeline<QuotaEntry> {
        let refresh = entry.date.addingTimeInterval(900)
        let dates = QuotaSchedule.dates(snapshot: entry.snapshot, now: entry.date)
        let entries = dates.sorted().map { QuotaEntry(date: $0, snapshot: entry.snapshot, message: entry.message) }
        return Timeline(entries: entries, policy: .after(refresh))
    }
}

struct LegacyProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { .init(date: .now, snapshot: .preview, message: nil, preview: true) }
    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(await WidgetLoader.entry()) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        Task { completion(WidgetLoader.timeline(await WidgetLoader.entry())) }
    }
}

@available(iOS 17.0, *)
struct QuotaConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "服务器连接"
    static var description = IntentDescription("默认使用 App 的共享连接。签名不支持 App Groups 时，可在这里填写服务器和只读查询码。")

    @Parameter(title: "服务器地址（可选）") var server: String?
    @Parameter(title: "只读查询码（可选）") var accessCode: String?
}

@available(iOS 17.0, *)
struct ConfigurableProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { .init(date: .now, snapshot: .preview, message: nil, preview: true) }
    func snapshot(for configuration: QuotaConfiguration, in context: Context) async -> QuotaEntry {
        if context.isPreview { return placeholder(in: context) }
        return await load(configuration)
    }
    func timeline(for configuration: QuotaConfiguration, in context: Context) async -> Timeline<QuotaEntry> {
        WidgetLoader.timeline(await load(configuration))
    }
    private func load(_ configuration: QuotaConfiguration) async -> QuotaEntry {
        let server = configuration.server?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let code = configuration.accessCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !server.isEmpty || !code.isEmpty {
            guard !code.isEmpty else { return .init(date: .now, snapshot: nil, message: "编辑小组件，填写查询码") }
            return await WidgetLoader.entry(connection: .init(server: server.isEmpty ? ServerConnection.defaultServer : server,
                                                             accessCode: code), manual: true)
        }
        return await WidgetLoader.entry()
    }
}

struct QuotaWidgetView: View {
    let entry: QuotaEntry
    let dark: Bool
    @Environment(\.widgetFamily) private var family
    private var ink: Color { dark ? .white : .black }
    private var paper: Color { dark ? Color(white: 0.07) : Color(white: 0.98) }
    private var stale: Bool { entry.message != nil || entry.snapshot?.isStale(at: entry.date) == true }

    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                content.containerBackground(for: .widget) { paper }
            } else { content.padding(16).background(paper) }
        }.foregroundStyle(ink)
            .widgetURL(URL(string: "codexquota://open"))
            .privacySensitive()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 10 : 12) {
            HStack {
                Text("CODEX").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2)
                Spacer(minLength: 3)
                if entry.preview { Text("示例").font(.system(size: 9)) }
                else if stale { Image(systemName: "clock.badge.exclamationmark").font(.caption2) }
                else { Circle().fill(ink.opacity(0.65)).frame(width: 5, height: 5) }
            }.foregroundStyle(ink.opacity(0.65))
            if let snapshot = entry.snapshot, !snapshot.windows.isEmpty {
                if family == .systemSmall { small(snapshot) }
                else { medium(snapshot) }
            } else {
                Spacer(minLength: 0)
                Text(entry.message ?? "暂无额度信息").font(.caption).lineLimit(3)
                Text("点击打开 App").font(.system(size: 10)).opacity(0.5)
                Spacer(minLength: 0)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func small(_ snapshot: QuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(snapshot.windows.prefix(2)) { window in
                HStack(alignment: .firstTextBaseline) {
                    Text(window.title).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    Text(window.remainingText + "%").font(.system(size: 27, weight: .light, design: .rounded))
                        .monospacedDigit().minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
            if let window = snapshot.windows.first { resetLine(window) }
            if stale { Text("历史数据 · 待更新").font(.system(size: 9)).opacity(0.6) }
        }
    }

    private func medium(_ snapshot: QuotaSnapshot) -> some View {
        HStack(alignment: .top, spacing: 22) {
            ForEach(snapshot.windows.prefix(2)) { window in
                VStack(alignment: .leading, spacing: 7) {
                    Text(window.title).font(.system(size: 11)).opacity(0.6)
                    Text(window.remainingText + "%")
                        .font(.system(size: 37, weight: .light, design: .rounded)).monospacedDigit()
                        .minimumScaleFactor(0.6).lineLimit(1)
                    GeometryReader { geometry in
                        Capsule().fill(ink.opacity(0.12)).overlay(alignment: .leading) {
                            Capsule().fill(ink.opacity(0.8)).frame(width: geometry.size.width * window.progress)
                        }
                    }.frame(height: 3)
                    resetLine(window)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.overlay(alignment: .bottomTrailing) {
            if stale { Text("待更新").font(.system(size: 8)).opacity(0.5).offset(y: 13) }
        }
    }

    private func resetLine(_ window: QuotaWindow) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.clockwise")
            if let reset = window.resetDate, reset > entry.date {
                Text(timerInterval: entry.date...reset, countsDown: true).monospacedDigit()
            } else {
                Text(window.resetDate == nil ? "重置时间未知" : "等待额度更新")
            }
        }.font(.system(size: 10)).foregroundStyle(ink.opacity(0.6)).lineLimit(1)
    }
}

@available(iOS 17.0, *)
struct ConfigurableQuotaWidget: Widget {
    let dark: Bool
    init() { dark = true }
    init(dark: Bool) { self.dark = dark }
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: dark ? "CodexQuotaBlack" : "CodexQuotaWhite", intent: QuotaConfiguration.self,
                               provider: ConfigurableProvider()) { entry in
            QuotaWidgetView(entry: entry, dark: dark)
        }
        .configurationDisplayName(dark ? "Codex · 黑色" : "Codex · 白色")
        .description("服务器 Codex 剩余额度与重置倒计时")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct LegacyQuotaWidget: Widget {
    let dark: Bool
    init() { dark = true }
    init(dark: Bool) { self.dark = dark }
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: dark ? "CodexQuotaBlack" : "CodexQuotaWhite", provider: LegacyProvider()) { entry in
            QuotaWidgetView(entry: entry, dark: dark)
        }
        .configurationDisplayName(dark ? "Codex · 黑色" : "Codex · 白色")
        .description("服务器 Codex 剩余额度与重置倒计时")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CodexQuotaWidgets: WidgetBundle {
    var body: some Widget { compatibleWidgets() }

    private func compatibleWidgets() -> some Widget {
        if #available(iOS 17.0, *) {
            return WidgetBundleBuilder.buildBlock(
                ConfigurableQuotaWidget(dark: true), ConfigurableQuotaWidget(dark: false))
        } else {
            return WidgetBundleBuilder.buildBlock(
                LegacyQuotaWidget(dark: true), LegacyQuotaWidget(dark: false))
        }
    }
}
