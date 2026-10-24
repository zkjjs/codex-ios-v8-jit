import SwiftUI
import QuotaCore

extension Color {
    static let quotaMint = Color(red: 0.15, green: 0.76, blue: 0.57)
    static let quotaBlue = Color(red: 0.32, green: 0.59, blue: 0.96)
}

struct QuotaRing: View {
    let percent: Double?
    var compact = false
    var tint: Color = .quotaMint
    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.14), lineWidth: compact ? 7 : 13)
            Circle()
                .trim(from: 0, to: (percent ?? 0) / 100)
                .stroke(tint.gradient, style: StrokeStyle(lineWidth: compact ? 7 : 13, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(percent.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(.system(size: compact ? 29 : 64, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text(percent == nil ? "未知" : "剩余 %")
                    .font(compact ? .caption2 : .subheadline).foregroundStyle(.secondary)
            }.padding(compact ? 9 : 20)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("剩余额度")
        .accessibilityValue(percent.map { "百分之\(Int($0.rounded()))" } ?? "未知")
    }
}

struct ResetLabel: View {
    let window: QuotaWindow
    let now: Date
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 6) {
            if let reset = window.resetAt {
                Text(reset, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                    .font(compact ? .caption2 : .subheadline).fontWeight(.medium)
                if reset > now {
                    HStack(spacing: 3) {
                        if !compact { Text("距重置") }
                        Text(timerInterval: now...reset, countsDown: true)
                            .monospacedDigit().lineLimit(1)
                    }
                    .font(compact ? .caption2 : .caption).foregroundStyle(.secondary)
                } else {
                    Text("已到重置时间 · 待更新")
                        .font(.caption2).foregroundStyle(.orange).lineLimit(2)
                }
            } else {
                Text("重置时间未知").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct GlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            content.background(.regularMaterial, in: .rect(cornerRadius: 24))
        }
    }
}
