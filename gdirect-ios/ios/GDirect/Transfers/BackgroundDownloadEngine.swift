import Foundation

/// Delegate methods run on one operation queue. Temporary download files are moved before returning.
final class BackgroundDownloadEngine: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    enum Event {
        case progress(Int64, Int64)
        case downloaded(URL, HTTPURLResponse?)
        case stopped(Data?)
        case failed(String, Data?)
        case eventsFinished
    }
    private let root: URL
    private let emit: (UUID?, UUID?, Event) -> Void
    private let lock = NSLock()
    private var stopped = Set<String>()
    private var session: URLSession!

    init(root: URL, identifier: String, emit: @escaping (UUID?, UUID?, Event) -> Void) {
        self.root = root
        self.emit = emit
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = 4
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }
    func start(id: UUID, attempt: UUID, request: URLRequest, resumeData: Data?) {
        let task: URLSessionDownloadTask
        if let resumeData { task = session.downloadTask(withResumeData: resumeData) }
        else { task = session.downloadTask(with: request) }
        task.taskDescription = "\(id.uuidString):\(attempt.uuidString)"
        task.resume()
    }
    func pause(id: UUID, attempt: UUID) {
        let key = "\(id.uuidString):\(attempt.uuidString)"
        lock.lock(); stopped.insert(key); lock.unlock()
        session.getAllTasks { [weak self] tasks in
            let matches = tasks.compactMap { $0 as? URLSessionDownloadTask }.filter { $0.taskDescription == key }
            if matches.isEmpty { self?.emit(id, attempt, .stopped(nil)) }
            for task in matches {
                task.cancel { data in self?.emit(id, attempt, .stopped(data)) }
            }
        }
    }
    func reconcile(known: [UUID: UUID], completion: @escaping (Set<UUID>) -> Void) {
        session.getAllTasks { tasks in
            var active = Set<UUID>()
            for task in tasks {
                guard let description = task.taskDescription, let (id, attempt) = Self.identity(description), known[id] == attempt else {
                    task.cancel()
                    continue
                }
                active.insert(id)
            }
            completion(active)
        }
    }
    private static func identity(_ description: String) -> (UUID, UUID)? {
        let pieces = description.split(separator: ":")
        guard pieces.count == 2, let id = UUID(uuidString: String(pieces[0])), let attempt = UUID(uuidString: String(pieces[1])) else { return nil }
        return (id, attempt)
    }
    private func identity(_ task: URLSessionTask) -> (UUID, UUID)? { task.taskDescription.flatMap(Self.identity) }
    private func isStopped(_ task: URLSessionTask) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped.contains(task.taskDescription ?? "")
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if let (id, attempt) = identity(downloadTask), !isStopped(downloadTask) { emit(id, attempt, .progress(totalBytesWritten, totalBytesExpectedToWrite)) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let (id, attempt) = identity(downloadTask), !isStopped(downloadTask) else { return }
        do {
            let directory = root.appendingPathComponent("transfers", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            let staging = directory.appendingPathComponent("received-\(attempt.uuidString).tmp")
            try FileManager.default.moveItem(at: location, to: staging)
            // Persist final response metadata beside the staged bytes before dispatching to the app.
            if let response = downloadTask.response as? HTTPURLResponse {
                let manifest = ["attempt": attempt.uuidString, "url": response.url?.absoluteString ?? "", "status": String(response.statusCode)]
                try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("received.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            emit(id, attempt, .downloaded(staging, downloadTask.response as? HTTPURLResponse))
        } catch { emit(id, attempt, .failed("无法保存下载文件，检查剩余空间。", nil)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let (id, attempt) = identity(task), let error else { return }
        if isStopped(task) { return } // cancel(byProducingResumeData:) owns the pause event.
        let nsError = error as NSError
        let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        let message = "后台下载中断（\(nsError.code)），可点击继续重试。"
        emit(id, attempt, .failed(message, resumeData))
    }
    // Background URLSession follows redirects itself; its redirect delegate is not called.
    // Do not claim a per-hop allowlist here. Validate the final response before committing bytes.
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) { emit(nil, nil, .eventsFinished) }

    static func allowed(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              let host = url.host else { return false }
        return ["drive.google.com", "drive.usercontent.google.com", "www.googleapis.com", "content.googleapis.com", "drive.googleapis.com"].contains(host) || host.hasSuffix(".googleusercontent.com")
    }
}
