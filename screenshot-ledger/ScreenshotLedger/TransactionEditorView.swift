import SwiftUI
import UIKit
import LedgerCore

struct TransactionEditorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft: TransactionDraft
    @FocusState private var amountFocused: Bool

    init(draft: TransactionDraft) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    screenshot
                    if draft.pendingImageData != nil && draft.amountText.isEmpty {
                        Text("没有认出金额，请对照截图填写。")
                            .font(.subheadline)
                            .foregroundStyle(Theme.expense)
                    }
                    amountField
                    Picker("收支", selection: $draft.direction) {
                        Text("支出").tag(LedgerDirection.expense)
                        Text("收入").tag(LedgerDirection.income)
                    }
                    .pickerStyle(.segmented)
                    labeledField("商户", text: $draft.merchant)
                    Picker("分类", selection: $draft.category) {
                        ForEach(LedgerCategory.allCases, id: \.self) { category in
                            Label(category.title, systemImage: category.symbol).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    DatePicker("时间", selection: $draft.occurredAt)
                    labeledField("支付方式", text: $draft.paymentMethod)
                    labeledField("备注", text: $draft.note)
                    if !draft.rawText.isEmpty {
                        DisclosureGroup("识别原文") {
                            Text(draft.rawText)
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 6)
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                    }
                    Button {
                        model.save(draft)
                    } label: {
                        Text("保存到账本")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.expense)
                    .disabled(Money.cents(from: draft.amountText) == nil)
                    if model.pendingCount > 1 {
                        Text("保存或取消后，继续下一张截图。")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                    Text("只有点保存，这笔账和截图才会留在手机里。")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .padding(20)
            }
            .background(Theme.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { model.editor = nil }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { amountFocused = false }
                }
            }
        }
    }

    private var title: String {
        if !draft.isNew { return "编辑" }
        if draft.pendingImageData != nil { return "确认这笔账" }
        return "记一笔"
    }

    @ViewBuilder
    private var screenshot: some View {
        if let image = previewImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1)
                )
        }
    }

    private var previewImage: UIImage? {
        if let data = draft.pendingImageData, !data.isEmpty, let image = UIImage(data: data) {
            return image
        }
        if let name = draft.imageFilename, let data = model.imageData(named: name), let image = UIImage(data: data) {
            return image
        }
        return nil
    }

    private var amountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("金额")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            TextField("0.00", text: $draft.amountText)
                .keyboardType(.decimalPad)
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.ink)
                .focused($amountFocused)
            if let cents = Money.cents(from: draft.amountText) {
                Text(Money.signedYuan(cents: cents, direction: draft.direction))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(draft.direction == .expense ? Theme.expense : Theme.income)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }

    private func labeledField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
            TextField(title, text: text)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.ink)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }
}
