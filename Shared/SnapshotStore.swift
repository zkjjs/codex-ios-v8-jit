import Foundation
import Darwin
import QuotaCore

struct SnapshotStore {
    static let shared = SnapshotStore()
    var root: URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }
    var available: Bool { root != nil }
    private func locked<T>(_ body: (URL) throws -> T) throws -> T {
        guard let root else { throw AppError.message("小组件共享容器不可用。签名需保留 App Groups 与小组件扩展。") }
        let lockURL = root.appendingPathComponent("quota.lock")
        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw AppError.message("无法访问小组件共享容器。") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw AppError.message("暂时无法同步小组件。") }
        defer { flock(fd, LOCK_UN) }
        return try body(root.appendingPathComponent("quota-state.json"))
    }
    private func load(_ url: URL) throws -> SharedState {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return SharedState(sessionID: nil, snapshot: nil, message: nil, retryAt: nil)
        }
        return try JSONDecoder().decode(SharedState.self, from: Data(contentsOf: url))
    }
    func read() throws -> SharedState { try locked { try load($0) } }
    func update(_ change: (inout SharedState) throws -> Void) throws {
        try locked { url in
            var state = try load(url)
            try change(&state)
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
    func begin(sessionID: UUID) throws {
        try update { state in
            if state.sessionID != sessionID {
                state = SharedState(sessionID: sessionID, snapshot: nil, message: nil, retryAt: nil, privacyHidden: state.privacyHidden)
            }
        }
    }
    func write(_ snapshot: QuotaSnapshot, sessionID: UUID) throws {
        try update { state in
            state.apply(snapshot, sessionID: sessionID, now: Date())
        }
    }
    func failure(_ message: String, retryAt: Date?, sessionID: UUID) throws {
        try update { state in
            guard state.sessionID == sessionID else { return }
            state.message = message
            if let retryAt { state.retryAt = max(state.retryAt ?? retryAt, retryAt) }
        }
    }
    func clear() throws {
        try update { $0 = SharedState(sessionID: nil, snapshot: nil, message: nil, retryAt: nil, privacyHidden: $0.privacyHidden) }
    }
}
