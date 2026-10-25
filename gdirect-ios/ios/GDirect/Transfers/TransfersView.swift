import SwiftUI

struct TransfersView: View {
    @Bindable var coordinator: DownloadCoordinator
    let model: AppModel
    @State private var adding = false
    var body: some View {
        List {
            if let error = coordinator.errorMessage {
                Section { Text(error).foregroundStyle(.red) }
            }
            if coordinator.records.isEmpty {
                ContentUnavailableView("还没有下载", systemImage: "arrow.down.circle", description: Text("粘贴 Google Drive 分享链接，或登录后从云盘下载。"))
            }
            ForEach(coordinator.records) { record in
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.name).font(.headline).lineLimit(2)
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
                    if let message = record.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        if record.state.isActive {
                            Button("暂停", systemImage: "pause") { coordinator.pause(record.id) }.disabled(record.state == .pausing)
                        } else if record.state != .completed {
                            Button("继续", systemImage: "play") { Task { await coordinator.resume(record.id) } }
                        }
                        if let file = coordinator.fileURL(record) {
                            ShareLink(item: file) { Label("分享 / 保存到文件", systemImage: "square.and.arrow.up") }
                        }
                    }.buttonStyle(.bordered)
                }.padding(.vertical, 4)
            }
        }
        .navigationTitle("下载")
        .toolbar { Button("添加下载", systemImage: "plus") { adding = true } }
        .sheet(isPresented: $adding) { AddDownloadView(model: model, coordinator: coordinator) }
    }
}

private struct AddDownloadView: View {
    let model: AppModel
    let coordinator: DownloadCoordinator
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
            .navigationTitle("添加下载")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}
