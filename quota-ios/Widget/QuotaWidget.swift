import SwiftUI
import WidgetKit
import AppIntents

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
    private var paper: Color { dark ? Color(white: 0.07) : Color(white: 0.98) }

    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                QuotaWidgetContent(entry: entry, dark: dark)
                    .containerBackground(for: .widget) { paper }
            } else {
                QuotaWidgetContent(entry: entry, dark: dark).padding(16).background(paper)
            }
        }.widgetURL(URL(string: "codexquota://open"))
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
