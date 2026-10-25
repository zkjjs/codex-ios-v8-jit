import SwiftUI

private struct DriveFile: Decodable, Identifiable {
    let id: String
    let name: String
    let mimeType: String
    let size: String?
    let resourceKey: String?
    let md5Checksum: String?
    var folder: Bool { mimeType == "application/vnd.google-apps.folder" }
    var googleDocument: Bool { mimeType.hasPrefix("application/vnd.google-apps.") && !folder }
    var input: String {
        var parts = URLComponents(string: "https://drive.google.com/file/d/\(id)/view")!
        if let resourceKey { parts.queryItems = [URLQueryItem(name: "resourcekey", value: resourceKey)] }
        return parts.url!.absoluteString
    }
}

struct DriveBrowserView: View {
    let model: AppModel
    let folderID: String
    let title: String
    @State private var files: [DriveFile] = []
    @State private var page: String?
    @State private var loading = false
    @State private var message: String?
    @State private var loadedAccount: String?
    var body: some View {
        List {
            if model.auth.accountID == nil {
                ContentUnavailableView("登录以浏览云盘", systemImage: "person.crop.circle", description: Text("前往设置登录 Google；也可以直接粘贴公开链接下载。"))
            }
            if let message { Text(message).foregroundStyle(.red) }
            ForEach(files) { file in
                if file.folder {
                    NavigationLink { DriveBrowserView(model: model, folderID: file.id, title: file.name) }
                    label: { Label(file.name, systemImage: "folder") }
                } else {
                    Button {
                        guard let coordinator = model.coordinator, let account = model.auth.accountID else { return }
                        Task {
                            await coordinator.add(input: file.input, name: file.name + (file.googleDocument ? ".pdf" : ""),
                                engine: model.engine, ip: model.engine == .direct ? model.directIP : nil, accountID: account,
                                export: file.googleDocument ? "application/pdf" : nil, md5: file.googleDocument ? nil : file.md5Checksum)
                        }
                    } label: { Label(file.name, systemImage: "arrow.down.document") }
                }
            }
            if loading { ProgressView() }
            if page != nil { Button("加载更多") { Task { await load(reset: false) } }.disabled(loading) }
        }
        .navigationTitle(title)
        .task(id: model.auth.accountID) { await load(reset: true) }
        .refreshable { await load(reset: true) }
    }
    private func load(reset: Bool) async {
        guard !loading else { return }
        guard let account = model.auth.accountID else { files = []; page = nil; return }
        loading = true
        defer { loading = false }
        if reset || loadedAccount != account { files = []; page = nil }
        message = nil
        do {
            let token = try await model.auth.accessToken(accountID: account)
            var request: [String: Any] = ["command": "list", "folder": folderID, "token": token]
            if model.engine == .direct && !model.directIP.isEmpty { request["ip"] = model.directIP }
            if let page { request["page"] = page }
            let output = try await NativeCore.call(request)
            guard model.auth.accountID == account else { return }
            let data = try JSONSerialization.data(withJSONObject: output["files"] ?? [])
            let values = try JSONDecoder().decode([DriveFile].self, from: data)
            let existing = Set(files.map(\.id))
            files += values.filter { !existing.contains($0.id) }
            page = output["nextPageToken"] as? String
            loadedAccount = account
        } catch { message = error.localizedDescription }
    }
}
