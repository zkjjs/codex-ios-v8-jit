import Foundation
import SQLite3

/// Main-actor owner; each state update is one SQLite transaction. No OAuth tokens are stored here.
@MainActor
final class TaskStore {
    let root: URL
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(root: URL? = nil) throws {
        self.root = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("gdirect", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let path = self.root.appendingPathComponent("state.sqlite3").path
        guard sqlite3_open(path, &database) == SQLITE_OK else { throw AppFailure(message: "无法打开下载数据库。") }
        do {
            try execute("PRAGMA journal_mode=WAL;")
            try execute("CREATE TABLE IF NOT EXISTS transfers(id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL);")
            try execute("PRAGMA user_version=1;")
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path)
            var resource = self.root
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try resource.setResourceValues(values)
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }
    deinit { sqlite3_close(database) }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw AppFailure(message: "下载数据库写入失败。") }
    }
    func save(_ record: TransferRecord) throws {
        let data = try JSONEncoder().encode(record)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "INSERT OR REPLACE INTO transfers(id,payload) VALUES(?,?);", -1, &statement, nil) == SQLITE_OK else { throw AppFailure(message: "无法保存下载任务。") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_text(statement, 1, record.id.uuidString, -1, transient) == SQLITE_OK else { throw AppFailure(message: "无法保存任务编号。") }
        let bound = data.withUnsafeBytes { bytes in sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(bytes.count), transient) }
        guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw AppFailure(message: "无法写入下载进度，下载应暂停后重试。") }
    }
    func load() throws -> [TransferRecord] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT payload FROM transfers;", -1, &statement, nil) == SQLITE_OK else { throw AppFailure(message: "无法读取下载任务。") }
        defer { sqlite3_finalize(statement) }
        var records: [TransferRecord] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(statement, 0) else { throw AppFailure(message: "下载记录为空。") }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            records.append(try JSONDecoder().decode(TransferRecord.self, from: data))
            result = sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw AppFailure(message: "读取下载数据库失败。") }
        return records.sorted { $0.createdAt > $1.createdAt }
    }
    func directory(for id: UUID) throws -> URL {
        let url = root.appendingPathComponent("transfers", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return url
    }
    func file(for record: TransferRecord) throws -> URL { try directory(for: record.id).appendingPathComponent(record.name) }
}
