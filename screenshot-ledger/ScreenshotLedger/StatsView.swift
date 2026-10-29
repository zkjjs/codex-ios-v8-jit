import SwiftUI
import LedgerCore

struct StatsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let summary = model.summary(for: model.visibleMonth)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        statTile(title: "支出", cents: summary.expenseCents, color: Theme.expense)
                        statTile(title: "收入", cents: summary.incomeCents, color: Theme.income)
                    }
                    if summary.categoryTotals.isEmpty {
                        Text("这个月还没有支出，所以没有分类。")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 12)
                    } else {
                        VStack(spacing: 14) {
                            ForEach(summary.categoryTotals, id: \.category) { item in
                                categoryRow(item, total: summary.expenseCents)
                            }
                        }
                        .padding(16)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Theme.line, lineWidth: 1)
                        )
                    }
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle("统计")
            .safeAreaInset(edge: .top, spacing: 0) {
                MonthPager(month: $model.visibleMonth)
                    .padding(.horizontal, 12)
                    .background(Theme.paper)
            }
        }
    }

    private func statTile(title: String, cents: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            Text("¥\(Money.plain(cents: cents))")
                .font(.title2.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }

    private func categoryRow(_ item: CategoryTotal, total: Int) -> some View {
        let fraction = total > 0 ? Double(item.amountCents) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(item.category.title, systemImage: item.category.symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("¥\(Money.plain(cents: item.amountCents))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.line)
                Capsule()
                    .fill(Theme.expense)
                    .scaleEffect(x: CGFloat(max(fraction, 0.03)), y: 1, anchor: .leading)
            }
            .frame(height: 8)
            .clipShape(Capsule())
        }
    }
}
