import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import LedgerCore

struct LedgerHomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summaryCard
                        .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if groups.isEmpty {
                    Section {
                        emptyState
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                } else {
                    ForEach(groups) { group in
                        Section(LedgerDateText.day.string(from: group.day)) {
                            ForEach(group.entries) { entry in
                                Button {
                                    model.beginEdit(entry)
                                } label: {
                                    entryRow(entry)
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button("删除", role: .destructive) {
                                        model.delete(id: entry.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("截屏记账")
            .safeAreaInset(edge: .top, spacing: 0) {
                MonthPager(month: $model.visibleMonth)
                    .padding(.horizontal, 12)
                    .background(Theme.paper)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.beginManualEntry()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("手动记账")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "photo")
                    }
                    .accessibilityLabel("从相册选择截图")
                }
            }
            .onChange(of: pickerItem) { item in
                guard let item else { return }
                Task {
                    if let imported = try? await item.loadTransferable(type: ImportedScreenshot.self) {
                        await MainActor.run {
                            model.importImage(imported.data)
                        }
                    } else {
                        await MainActor.run {
                            model.alertMessage = "这张图片没有读出来。"
                        }
                    }
                    await MainActor.run { pickerItem = nil }
                }
            }
        }
    }

    private var monthEntries: [LedgerEntry] {
        model.entries(in: model.visibleMonth)
    }

    private var groups: [DayGroup] {
        let calendar = LedgerCalendar.shanghai
        let grouped = Dictionary(grouping: monthEntries) { entry in
            calendar.startOfDay(for: entry.occurredAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            DayGroup(day: day, entries: grouped[day] ?? [])
        }
    }

    private var summaryCard: some View {
        let summary = model.summary(for: model.visibleMonth)
        return VStack(alignment: .leading, spacing: 10) {
            Text("支出")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Money.plain(cents: summary.expenseCents))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("元")
                    .font(.headline)
                    .foregroundStyle(Theme.muted)
            }
            HStack {
                Text("收入 ¥\(Money.plain(cents: summary.incomeCents))")
                Spacer()
                Text("结余 \(balanceText(summary.balanceCents))")
            }
            .font(.subheadline)
            .foregroundStyle(Theme.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这个月还没有账")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("从相册选择微信、支付宝或银行的支付截图。金额和商户会先填好，你确认后才记入账本。识别在这台手机上完成，截图不会上传。")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
    }

    private func entryRow(_ entry: LedgerEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.category.symbol)
                .font(.body)
                .foregroundStyle(Theme.expense)
                .frame(width: 36, height: 36)
                .background(Theme.paper)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.merchant.isEmpty ? "未填写商户" : entry.merchant)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(entry.category.title) · \(LedgerDateText.time.string(from: entry.occurredAt))")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Text(Money.signedYuan(cents: entry.amountCents, direction: entry.direction))
                .font(.body.weight(.semibold))
                .foregroundStyle(entry.direction == .expense ? Theme.expense : Theme.income)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func balanceText(_ cents: Int) -> String {
        let prefix = cents > 0 ? "+" : cents < 0 ? "-" : ""
        return "\(prefix)¥\(Money.plain(cents: cents))"
    }
}

private struct ImportedScreenshot: Transferable {
    var data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            ImportedScreenshot(data: data)
        }
    }
}

private struct DayGroup: Identifiable {
    var day: Date
    var entries: [LedgerEntry]
    var id: Date { day }
}
