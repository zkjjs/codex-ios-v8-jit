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
            if let reset = window.resetDate, !window.awaitingReset(at: entry.date) {
                Text(timerInterval: entry.date...reset, countsDown: true).monospacedDigit()
            } else {
                Text(window.resetDate == nil ? "重置时间未知" : "等待额度更新")
            }
        }.font(.system(size: 10)).foregroundStyle(ink.opacity(0.6)).lineLimit(1)
    }
}
