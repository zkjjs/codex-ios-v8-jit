import Foundation

enum DownloadEngineKind: String, Codable, CaseIterable {
    case system, direct
    var title: String { self == .system ? "系统后台下载" : "固定 IP 直连" }
}

enum TransferState: String, Codable {
    case queued, waitingForSystem, running, finalizing, pausing, deleting, paused, completed, failed, cancelled
    var title: String {
        switch self {
        case .queued: "等待开始"
        case .waitingForSystem: "等待系统调度"
        case .running: "下载中"
        case .finalizing: "正在校验文件"
        case .pausing: "正在保存断点"
        case .deleting: "正在删除本地文件"
        case .paused: "已暂停，可继续"
        case .completed: "已完成"
        case .failed: "下载失败"
        case .cancelled: "已取消"
        }
    }
    var isActive: Bool { [.queued, .waitingForSystem, .running, .finalizing, .pausing].contains(self) }
}

struct TransferRecord: Identifiable, Codable {
    let id: UUID
    let input: String
    let name: String
    let accountID: String?
    let engine: DownloadEngineKind
    let ip: String?
    var exportMIME: String?
    var resolvedURL: URL?
    var expectedMD5: String?
    var state: TransferState = .queued
    var completedBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var message: String?
    var createdAt = Date()
    var confirmationAttempts = 0
    var attemptID = UUID()
    var recoveryVersion = 1

    init(input: String, name: String, accountID: String?, engine: DownloadEngineKind, ip: String?, exportMIME: String? = nil) {
        self.id = UUID()
        self.input = input
        self.name = Self.safeName(name)
        self.accountID = accountID
        self.engine = engine
        self.ip = ip
        self.exportMIME = exportMIME
    }
    var fraction: Double? {
        totalBytes > 0 ? min(1, max(0, Double(completedBytes) / Double(totalBytes))) : nil
    }
    var canResume: Bool { [.queued, .paused, .failed, .cancelled].contains(state) }
    func acceptsEvent(attempt: UUID?) -> Bool { attemptID == attempt }
    mutating func pauseForExpiration(attempt: UUID) {
        guard attemptID == attempt, state == .running else { return }
        state = .paused
        message = "系统结束了后台任务，断点已保留。"
    }
    mutating func recoverAfterLaunch() {
        if state == .pausing || state == .deleting { state = .paused }
        if engine == .direct && state.isActive {
            state = .paused
            message = "上次直连任务已中断，点击继续以恢复下载。"
        }
    }
    static func safeName(_ input: String) -> String {
        let normalized = input.replacingOccurrences(of: "\\", with: "/")
        let tail = normalized.components(separatedBy: "/").last ?? ""
        let clean = String(tail.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined().prefix(120))
        return clean.isEmpty || clean == "." || clean == ".." ? "download" : clean
    }
}

struct AppFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
