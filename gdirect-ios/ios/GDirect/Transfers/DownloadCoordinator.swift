import BackgroundTasks
import Foundation
import Observation
import UIKit

@MainActor @Observable
final class DownloadCoordinator {
    private(set) var records: [TransferRecord]
    var errorMessage: String?
    private let store: TaskStore
    private let auth: GoogleAuthService
    private let continued = ContinuedDownloadRunner()
    private var cancellations: [UUID: NativeCancellation] = [:]
    private var preparing = Set<UUID>()
    private var finalizing = 0
    private var backgroundEventsFinished = false
    private var backgroundCompletion: (() -> Void)?
    private var lastSaved: [UUID: Date] = [:]
    private var background: BackgroundDownloadEngine!
    let backgroundIdentifier = "\(Bundle.main.bundleIdentifier!).transfers"

    init(store: TaskStore, auth: GoogleAuthService) throws {
        self.store = store
        self.auth = auth
        self.records = try store.load()
        for index in records.indices {
            records[index].recoverAfterLaunch()
            try store.save(records[index])
        }
        background = BackgroundDownloadEngine(root: store.root, identifier: backgroundIdentifier) { [weak self] id, attempt, event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handle(id, attempt: attempt, event) }
            }
        }
        recoverStagedFiles()
        let known = Dictionary(uniqueKeysWithValues: records.filter { $0.engine == .system && $0.state.isActive }.map { ($0.id, $0.attemptID) })
        background.reconcile(known: known) { [weak self] active in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for id in Set(known.keys).subtracting(active) {
                        guard self.record(id)?.state == .running else { continue }
                        self.update(id) { $0.state = .paused; $0.message = "后台会话已结束，点击继续恢复。" }
                    }
                }
            }
        }
    }
    func attachBackgroundCompletion(_ completion: @escaping () -> Void) {
        backgroundCompletion = completion
        finishBackgroundEventsIfReady()
    }
    func add(input: String, name: String, engine: DownloadEngineKind, ip: String?, accountID: String?, export: String? = nil, md5: String? = nil) async {
        let record = TransferRecord(input: input, name: name, accountID: accountID, engine: engine, ip: ip, exportMIME: export)
        do {
            var value = record
            value.expectedMD5 = md5
            try store.save(value)
            records.insert(value, at: 0)
            await resume(value.id)
        } catch { errorMessage = error.localizedDescription }
    }
    func resume(_ id: UUID) async {
        guard !preparing.contains(id), cancellations[id] == nil,
              let record = record(id), record.canResume else { return }
        guard UIApplication.shared.applicationState == .active else {
            errorMessage = "请在 App 前台点击继续下载。"
            return
        }
        if record.engine == .system, let directory = try? store.directory(for: id),
           FileManager.default.fileExists(atPath: directory.appendingPathComponent("received.json").path) {
            update(id) { $0.state = .finalizing }
            recoverStagedFiles()
            if self.record(id)?.state == .finalizing { return }
        }
        preparing.insert(id)
        defer { preparing.remove(id) }
        let attempt = UUID()
        update(id) { $0.state = .queued; $0.message = nil; $0.attemptID = attempt }
        do {
            var request: [String: Any] = ["command": "resolve", "input": record.input, "authenticated": record.accountID != nil]
            if let mime = record.exportMIME { request["export"] = mime }
            let resolved = try await NativeCore.call(request)
            guard let text = resolved["url"] as? String, let url = URL(string: text), BackgroundDownloadEngine.allowed(url) else {
                throw AppFailure(message: "下载地址不受支持。")
            }
            let token = try await record.accountID.mapAsync { try await self.auth.accessToken(accountID: $0) }
            guard self.record(id)?.state == .queued, self.record(id)?.attemptID == attempt else { return }
            update(id) { $0.resolvedURL = url }
            _ = try store.directory(for: id)
            if record.engine == .system {
                var http = URLRequest(url: url)
                if let token { http.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
                let resumeURL = try store.directory(for: id).appendingPathComponent("system-resume.data")
                let resumeData = try? Data(contentsOf: resumeURL)
                // Remove stale recovery data only after it has been read. New pause data replaces it atomically.
                if FileManager.default.fileExists(atPath: resumeURL.path) { try FileManager.default.removeItem(at: resumeURL) }
                update(id) { $0.state = .running }
                background.start(id: id, attempt: attempt, request: http, resumeData: resumeData)
            } else {
                guard let ip = record.ip, !ip.isEmpty else { throw AppFailure(message: "请先扫描或填写可用的直连 IP。") }
                let cancellation = NativeCancellation()
                cancellations[id] = cancellation
                update(id) { $0.state = .waitingForSystem }
                do {
                    try await continued.submit(id: id, name: record.name) { [weak self] task in
                        self?.runDirect(id: id, url: url, task: task, cancellation: cancellation)
                    }
                } catch {
                    cancellations.removeValue(forKey: id)
                    throw error
                }
            }
        } catch { if self.record(id)?.attemptID == attempt { update(id) { $0.state = .failed; $0.message = error.localizedDescription } } }
    }
    func pause(_ id: UUID) {
        guard let value = record(id), value.state.isActive, value.state != .pausing else { return }
        update(id) { $0.state = value.engine == .system ? .pausing : .paused; $0.message = "已暂停，保留下载断点。" }
        if value.engine == .system { background.pause(id: id, attempt: value.attemptID) }
        else {
            cancellations[id]?.cancel()
            continued.cancelPending(id)
            // Active native contexts stay alive until the C callback unwinds.
            if value.state == .waitingForSystem { cancellations.removeValue(forKey: id) }
        }
    }
    func pauseAccount(_ accountID: String) {
        for value in records where value.accountID == accountID && value.state.isActive { pause(value.id) }
    }
    func fileURL(_ record: TransferRecord) -> URL? {
        guard record.state == .completed else { return nil }
        return try? store.file(for: record)
    }
    private func record(_ id: UUID) -> TransferRecord? { records.first { $0.id == id } }
    private func update(_ id: UUID, persist: Bool = true, _ change: (inout TransferRecord) -> Void) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        change(&records[index])
        if persist {
            do { try store.save(records[index]); lastSaved[id] = Date() }
            catch { errorMessage = error.localizedDescription }
        }
    }
    private func progress(_ id: UUID, done: Int64, total: Int64) {
        guard record(id)?.state == .running else { return }
        let persist = Date().timeIntervalSince(lastSaved[id] ?? .distantPast) >= 1
        update(id, persist: persist) { $0.completedBytes = max(0, done); $0.totalBytes = max(0, total) }
    }
    private func runDirect(id: UUID, url: URL, task: BGContinuedProcessingTask, cancellation: NativeCancellation) {
        guard let value = record(id), value.state == .waitingForSystem else {
            task.setTaskCompleted(success: false)
            continued.finished(id)
            cancellations.removeValue(forKey: id)
            return
        }
        task.expirationHandler = { [weak self] in
            cancellation.cancel()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.update(id) { $0.state = .paused; $0.message = "系统结束了后台任务，断点已保留。" } }
            }
        }
        update(id) { $0.state = .running }
        Task {
            var success = false
            defer {
                task.setTaskCompleted(success: success)
                continued.finished(id)
                cancellations.removeValue(forKey: id)
            }
            do {
                let directory = try store.directory(for: id)
                var currentURL = url
                for attempt in 0..<3 {
                    if cancellation.isCancelled { return }
                    var request: [String: Any] = ["command": "download", "url": currentURL.absoluteString,
                        "ip": value.ip ?? "", "directory": directory.path, "name": value.name, "connections": 4]
                    // Acquire a fresh token when the system actually starts the task, not when it was queued.
                    if let accountID = value.accountID { request["token"] = try await auth.accessToken(accountID: accountID) }
                    _ = try await NativeCore.call(request, cancellation: cancellation) { [weak self] done, total in
                        DispatchQueue.main.async {
                            MainActor.assumeIsolated {
                                self?.progress(id, done: done, total: total)
                                task.progress.totalUnitCount = max(0, total)
                                task.progress.completedUnitCount = max(0, done)
                            }
                        }
                    }
                    if cancellation.isCancelled { return }
                    let file = try store.file(for: value)
                    if let confirmation = try await confirmationURL(file: file, base: currentURL, record: value) {
                        guard attempt < 2 else { throw AppFailure(message: "Google 下载确认次数过多。") }
                        try FileManager.default.removeItem(at: file)
                        currentURL = confirmation
                        continue
                    }
                    try await FileVerifier.verify(file, expectedMD5: value.expectedMD5)
                    guard !cancellation.isCancelled else { return }
                    complete(id, file: file)
                    success = true
                    return
                }
            } catch {
                if !cancellation.isCancelled { update(id) { $0.state = .failed; $0.message = error.localizedDescription } }
            }
        }
    }
    private func handle(_ id: UUID?, attempt: UUID?, _ event: BackgroundDownloadEngine.Event) {
        if case .eventsFinished = event {
            backgroundEventsFinished = true
            finishBackgroundEventsIfReady()
            return
        }
        guard let id, let value = record(id), value.acceptsEvent(attempt: attempt) else { return }
        switch event {
        case let .progress(done, total): progress(id, done: done, total: total)
        case let .stopped(data):
            saveResumeData(data, id: id)
            if record(id)?.state == .pausing { update(id) { $0.state = .paused } }
        case let .failed(message, data):
            saveResumeData(data, id: id)
            update(id) { $0.state = .failed; $0.message = message }
        case let .downloaded(file, response):
            guard value.state == .running || value.state == .finalizing else { return }
            update(id) { $0.state = .finalizing }
            finalizing += 1
            Task {
                defer { finalizing -= 1; finishBackgroundEventsIfReady() }
                do {
                    guard let response, (200..<300).contains(response.statusCode), let base = response.url,
                          BackgroundDownloadEngine.allowed(base) else {
                        try? FileManager.default.removeItem(at: file)
                        throw AppFailure(message: "Google 下载失败（HTTP \(response?.statusCode ?? 0)），请检查权限或重新登录。")
                    }
                    guard record(id)?.state == .finalizing, record(id)?.attemptID == attempt else { return }
                    if let confirmed = try await confirmationURL(file: file, base: base, record: value) {
                        defer { try? FileManager.default.removeItem(at: file) }
                        guard value.confirmationAttempts < 2 else { throw AppFailure(message: "Google 下载确认次数过多。") }
                        guard record(id)?.state == .finalizing, record(id)?.attemptID == attempt else { return }
                        update(id) { $0.confirmationAttempts += 1 }
                        update(id) { $0.state = .running }
                        background.start(id: id, attempt: value.attemptID, request: URLRequest(url: confirmed), resumeData: nil)
                        return
                    }
                    try await FileVerifier.verify(file, expectedMD5: value.expectedMD5)
                    guard record(id)?.state == .finalizing, record(id)?.attemptID == attempt else { return }
                    let destination = try store.file(for: value)
                    if file.standardizedFileURL != destination.standardizedFileURL {
                        guard !FileManager.default.fileExists(atPath: destination.path) else { throw AppFailure(message: "目标文件已存在，保留原文件。") }
                        try FileManager.default.moveItem(at: file, to: destination)
                    }
                    complete(id, file: destination)
                } catch { if record(id)?.attemptID == attempt && record(id)?.state == .finalizing { update(id) { $0.state = .failed; $0.message = error.localizedDescription } } }
            }
        case .eventsFinished: break
        }
    }
    private func confirmationURL(file: URL, base: URL, record: TransferRecord) async throws -> URL? {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 512) ?? Data()
        let text = String(decoding: prefix, as: UTF8.self).lowercased()
        guard text.contains("<!doctype html") || text.contains("<html") else { return nil }
        // Only treat HTML from the public download endpoint as a confirmation page.
        // Authenticated Drive may legitimately contain a user-owned HTML file.
        guard record.accountID == nil else { return nil }
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size <= 2 * 1024 * 1024 else { throw AppFailure(message: "Google 返回 HTML 页面，未作为文件保存。") }
        let result = try await NativeCore.call(["command": "confirmation", "html": String(decoding: Data(contentsOf: file), as: UTF8.self), "base": base.absoluteString])
        guard let raw = result["url"] as? String, let url = URL(string: raw), BackgroundDownloadEngine.allowed(url) else { throw AppFailure(message: "Google 返回无效确认页面。") }
        return url
    }
    private func complete(_ id: UUID, file: URL) {
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value ?? 0
        update(id) { $0.state = .completed; $0.message = nil; $0.completedBytes = size; $0.totalBytes = size }
        if let directory = try? store.directory(for: id) { try? FileManager.default.removeItem(at: directory.appendingPathComponent("received.json")) }
        if let value = record(id) { TransferNotifications.completed(value) }
    }
    private func recoverStagedFiles() {
        for value in records where value.engine == .system && value.state.isActive {
            guard let directory = try? store.directory(for: value.id),
                  let data = try? Data(contentsOf: directory.appendingPathComponent("received.json")),
                  let manifest = try? JSONDecoder().decode([String: String].self, from: data),
                  manifest["attempt"] == value.attemptID.uuidString,
                  let text = manifest["url"], let url = URL(string: text),
                  let statusText = manifest["status"], let status = Int(statusText),
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { continue }
            let staged = directory.appendingPathComponent("received-\(value.attemptID.uuidString).tmp")
            let destination = directory.appendingPathComponent(value.name)
            let file = FileManager.default.fileExists(atPath: staged.path) ? staged : destination
            guard FileManager.default.fileExists(atPath: file.path) else { update(value.id) { $0.state = .paused }; continue }
            // Persist a recoverable finalization state before asynchronous hash verification.
            update(value.id) { $0.state = .finalizing }
            handle(value.id, attempt: value.attemptID, .downloaded(file, response))
        }
    }
    private func saveResumeData(_ data: Data?, id: UUID) {
        guard let data else { return }
        do { try data.write(to: store.directory(for: id).appendingPathComponent("system-resume.data"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { errorMessage = "无法保存下载断点。" }
    }
    private func finishBackgroundEventsIfReady() {
        guard backgroundEventsFinished, finalizing == 0, let completion = backgroundCompletion else { return }
        backgroundCompletion = nil
        backgroundEventsFinished = false
        completion()
    }
}

private extension Optional {
    func mapAsync<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let value = self else { return nil }
        return try await transform(value)
    }
}
