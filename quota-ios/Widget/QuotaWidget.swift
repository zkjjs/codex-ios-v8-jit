import SwiftUI
import WidgetKit
import AppIntents

struct LegacyProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { .init(date: .now, snapshot: .preview, message: nil, preview: true) }
    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        completion(WidgetLoader.initialEntry())
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
        let resolved = resolve(configuration)
        if let error = resolved.error { return .init(date: .now, snapshot: nil, message: error) }
        return WidgetLoader.initialEntry(connection: resolved.connection, manual: resolved.manual)
    }
    func timeline(for configuration: QuotaConfiguration, in context: Context) async -> Timeline<QuotaEntry> {
        WidgetLoader.timeline(await load(configuration))
    }
    private func resolve(_ configuration: QuotaConfiguration) -> (connection: ServerConnection?, manual: Bool, error: String?) {
        let server = configuration.server?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let code = configuration.accessCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !server.isEmpty || !code.isEmpty else { return (nil, false, nil) }
        guard !code.isEmpty else { return (nil, true, "编辑小组件，填写查询码") }
        return (.init(server: server.isEmpty ? ServerConnection.defaultServer : server, accessCode: code), true, nil)
    }
    private func load(_ configuration: QuotaConfiguration) async -> QuotaEntry {
        let resolved = resolve(configuration)
        if let error = resolved.error { return .init(date: .now, snapshot: nil, message: error) }
        return await WidgetLoader.entry(connection: resolved.connection, manual: resolved.manual)
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

// Each Widget type has one immutable identity. Do not register one type twice with
// a different stored color: WidgetKit may reconstruct it through init().
struct BlackQuotaWidget: Widget {
    var body: some WidgetConfiguration {
        quotaConfiguration(kind: "CodexQuotaBlackV2", dark: true)
            .configurationDisplayName("Codex · 黑色")
            .description("服务器 Codex 剩余额度与重置倒计时")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WhiteQuotaWidget: Widget {
    var body: some WidgetConfiguration {
        quotaConfiguration(kind: "CodexQuotaWhiteV2", dark: false)
            .configurationDisplayName("Codex · 白色")
            .description("服务器 Codex 剩余额度与重置倒计时")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private func quotaConfiguration(kind: String, dark: Bool) -> some WidgetConfiguration {
    if #available(iOS 17.0, *) {
        return AppIntentConfiguration(kind: kind, intent: QuotaConfiguration.self,
                                      provider: ConfigurableProvider()) { entry in
            QuotaWidgetView(entry: entry, dark: dark)
        }
    } else {
        return StaticConfiguration(kind: kind, provider: LegacyProvider()) { entry in
            QuotaWidgetView(entry: entry, dark: dark)
        }
    }
}

@main
struct CodexQuotaWidgets: WidgetBundle {
    var body: some Widget {
        BlackQuotaWidget()
        WhiteQuotaWidget()
    }
}
