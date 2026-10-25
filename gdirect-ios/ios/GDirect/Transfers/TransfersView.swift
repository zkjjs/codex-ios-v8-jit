import SwiftUI

struct TransfersView: View {
    @Bindable var coordinator: DownloadCoordinator
    let model: AppModel
    @State private var adding = false
    @State private var pastedInput = ""
    @State private var deleting: TransferRecord?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
        List {
            if let error = coordinator.errorMessage {
                Section { Text(error).foregroundStyle(.red) }
            }
            if coordinator.records.isEmpty {
                ContentUnavailableView("还没有下载", systemImage: "arrow.down.circle", description: Text("粘贴 Google Drive 分享链接，或登录后从云盘下载。"))
            }
            if model.clipboardDetectionEnabled && model.clipboardHasLink {
                Section {
                    HStack {
                        Label("剪贴板中可能有链接", systemImage: "link")
                        Spacer()
                        PasteButton(payloadType: String.self) { values in
                            guard let value = values.first else { return }
                            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task {
                                do {
                                    _ = try await NativeCore.call(["command": "resolve", "input": text, "authenticated": false])
                                    pastedInput = text
                                    adding = true
                                } catch { coordinator.errorMessage = "剪贴板中没有可识别的 Google Drive 文件链接。" }
                            }
                        }.labelStyle(.titleAndIcon)
                    }
                }
            }
            ForEach(coordinator.records) { record in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        Text(record.name).font(.headline).lineLimit(2)
                        Spacer()
                        Menu {
                            Button("删除本地文件", systemImage: "trash", role: .destructive) { deleting = record }
                        } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("文件操作") }
                            .disabled(record.state == .deleting)
                    }
                    HStack {
                        Text(record.state.title)
                        Spacer()
                        Text(record.engine.title)
                    }.font(.caption).foregroundStyle(.secondary)
                    if let fraction = record.fraction { ProgressView(value: fraction) }
                    else if record.state.isActive { ProgressView() }
                    Text(ByteCountFormatter.string(fromByteCount: record.completedBytes, countStyle: .file)
                         + (record.totalBytes > 0 ? " / " + ByteCountFormatter.string(fromByteCount: record.totalBytes, countStyle: .file) : ""))
                        .font(.caption).monospacedDigit()
                    if record.state == .running {
                        HStack {
                            Text(TransferRateMeter.speedLabel(coordinator.speed(for: record.id))).fontWeight(.semibold)
                            Spacer()
                            if let seconds = coordinator.remainingSeconds(for: record.id), seconds < 31_536_000 {
                                Text("预计剩余 " + durationLabel(seconds))
                            }
                        }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                    if record.state == .deleting { ProgressView("正在清理本地文件…") }
                    if let message = record.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        if record.state.isActive {
                            Button("暂停", systemImage: "pause") { coordinator.pause(record.id) }.disabled(record.state == .pausing)
                        } else if record.canResume {
                            Button("继续", systemImage: "play") { Task { await coordinator.resume(record.id) } }
                        }
                        if let file = coordinator.fileURL(record) {
                            ShareLink(item: file) { Label("分享 / 保存到文件", systemImage: "square.and.arrow.up") }
                        }
                    }.buttonStyle(.bordered)
                }.padding(.vertical, 4)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("删除", systemImage: "trash", role: .destructive) { deleting = record }.disabled(record.state == .deleting)
                }
            }
        }
        .navigationTitle("下载")
        .toolbar { Button("添加下载", systemImage: "plus") { pastedInput = ""; adding = true } }
        .sheet(isPresented: $adding) { AddDownloadView(model: model, coordinator: coordinator, initialInput: pastedInput) }
        .confirmationDialog("删除本地文件？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除本地文件", role: .destructive) {
                if let record = deleting { coordinator.deleteLocal(record.id) }
                deleting = nil
            }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("将删除“\(deleting?.name ?? "")”的本地文件、断点和下载记录，云盘原文件会保留。") }
        }
    }
    private func durationLabel(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded(.up)))
        if value >= 3600 { return "\(value / 3600)小时\((value % 3600) / 60)分钟" }
        if value >= 60 { return "\(value / 60)分\(value % 60)秒" }
        return "\(value)秒"

    }
}

private struct AddDownloadView: View {
    let model: AppModel
    let coordinator: DownloadCoordinator
    let initialInput: String
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var name = "download"
    @State private var useAccount = false
    @State private var submitted = false
    var body: some View {
        NavigationStack {
            Form {
                Section("文件") {
                    TextField("Google Drive 分享链接或文件 ID", text: $input)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    PasteButton(payloadType: String.self) { values in
                        if let value = values.first { input = value.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    TextField("保存的文件名", text: $name)
                    if model.auth.accountID != nil { Toggle("使用已登录账户下载", isOn: $useAccount) }
                }
                Section {
                    LabeledContent("下载方式", value: model.engine.title)
                    Button("开始下载") {
                        submitted = true
                        let account = useAccount ? model.auth.accountID : nil
                        Task { await coordinator.add(input: input.trimmingCharacters(in: .whitespacesAndNewlines), name: name,
                            engine: model.engine, ip: model.engine == .direct ? model.directIP.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                            accountID: account) }
                        dismiss()
                    }.disabled(submitted || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { input = initialInput }
            .navigationTitle("添加下载")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}
