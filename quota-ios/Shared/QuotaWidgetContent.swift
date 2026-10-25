import SwiftUI
import WidgetKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: QuotaSnapshot?
    let message: String?
    var preview = false
}


struct QuotaWidgetContent: View {
    let entry: QuotaEntry
    let dark: Bool
    let family: WidgetFamily
    private var ink: Color { dark ? .white : .black }
    private var stale: Bool { entry.message != nil || entry.snapshot?.isStale(at: entry.date) == true }

    var body: some View {
        content.foregroundStyle(ink)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 10) {
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
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(shortTitle(window)).font(.system(size: 10, weight: .medium))
                        Spacer(minLength: 0)
                        Text("剩余").font(.system(size: 9)).opacity(0.6)
                        Text(window.remainingText + "%")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    }
                    quotaBar(window, height: 4)
                    Text(resetLabel(window))
                        .font(.system(size: 9)).foregroundStyle(ink.opacity(0.65))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
            updateLine(snapshot)
        }
    }

    private func medium(_ snapshot: QuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 22) {
                ForEach(snapshot.windows.prefix(2)) { window in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(shortTitle(window)).font(.system(size: 11, weight: .medium))
                            Text("剩余").font(.system(size: 10)).opacity(0.6)
                        }
                        Text(window.remainingText + "%")
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        quotaBar(window, height: 5)
                        Text(resetLabel(window)).font(.system(size: 10))
                            .foregroundStyle(ink.opacity(0.65)).lineLimit(1).minimumScaleFactor(0.8)
                        if let reset = window.resetDate, !window.awaitingReset(at: entry.date) {
                            HStack(spacing: 3) {
                                Text("距重置")
                                Text(timerInterval: entry.date...reset, countsDown: true)
                                    .monospacedDigit()
                            }.font(.system(size: 9)).foregroundStyle(ink.opacity(0.55)).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
            updateLine(snapshot)
        }
    }

    private func shortTitle(_ window: QuotaWindow) -> String {
        window.title.replacingOccurrences(of: "额度", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func quotaBar(_ window: QuotaWindow, height: CGFloat) -> some View {
        GeometryReader { geometry in
            Capsule().fill(ink.opacity(0.1)).overlay(alignment: .leading) {
                Capsule().fill(ink.opacity(0.85))
                    .frame(width: geometry.size.width * window.progress)
            }
        }.frame(height: height)
    }

    private func resetLabel(_ window: QuotaWindow) -> String {
        guard let reset = window.resetDate else { return "重置时间未知" }
        guard !window.awaitingReset(at: entry.date) else { return "已到重置时间 · 待更新" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: reset) + " 重置"
    }

    private func updateLine(_ snapshot: QuotaSnapshot) -> some View {
        HStack(spacing: 3) {
            if stale {
                Image(systemName: "clock.badge.exclamationmark")
                Text("历史数据 · 待更新")
            } else {
                Text("更新于")
                Text(snapshot.updatedDate, style: .time)
            }
        }.font(.system(size: 8)).foregroundStyle(ink.opacity(0.5)).lineLimit(1)
    }
}
