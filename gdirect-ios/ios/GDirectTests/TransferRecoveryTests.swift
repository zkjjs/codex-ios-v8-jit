import XCTest
@testable import GDirect

@MainActor
final class TransferRecoveryTests: XCTestCase {
    func testStorePersistsEngineAndAccountWithoutToken() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try TaskStore(root: root)
        var record = TransferRecord(input: "abc", name: "test.zip", accountID: "account-a", engine: .direct, ip: "8.8.8.8")
        record.state = .paused
        record.completedBytes = 1024
        try store.save(record)
        let loaded = try store.load()
        XCTAssertEqual(loaded.first?.id, record.id)
        XCTAssertEqual(loaded.first?.engine, .direct)
        XCTAssertEqual(loaded.first?.accountID, "account-a")
        XCTAssertEqual(loaded.first?.completedBytes, 1024)
        XCTAssertNil(String(data: try JSONEncoder().encode(record), encoding: .utf8)?.range(of: "accessToken"))
    }

    func testUnexpectedTerminationPausesDirectWorkButKeepsSystemWork() async {
        var direct = TransferRecord(input: "abc", name: "test", accountID: nil, engine: .direct, ip: "8.8.8.8")
        direct.state = .running
        direct.recoverAfterLaunch()
        XCTAssertEqual(direct.state, .paused)
        var system = TransferRecord(input: "abc", name: "test", accountID: nil, engine: .system, ip: nil)
        system.state = .running
        system.recoverAfterLaunch()
        XCTAssertEqual(system.state, .running)
    }

    func testSafeFilenameCannotEscapeTaskDirectory() async {
        XCTAssertEqual(TransferRecord.safeName("../../private/file.zip"), "file.zip")
        XCTAssertEqual(TransferRecord.safeName(".."), "download")
        XCTAssertFalse(TransferRecord.safeName("a\\b\u{0}.zip").contains("\\"))
    }

    func testResumeWaitsForCancellationAcknowledgment() async {
        var record = TransferRecord(input: "abc", name: "test", accountID: nil, engine: .system, ip: nil)
        record.state = .pausing
        XCTAssertFalse(record.canResume)
        record.state = .paused
        XCTAssertTrue(record.canResume)
    }

    func testEventsFromPreviousAttemptCannotChangeResumedTask() async {
        var record = TransferRecord(input: "abc", name: "test", accountID: nil, engine: .system, ip: nil)
        let previous = record.attemptID
        record.attemptID = UUID()
        XCTAssertFalse(record.acceptsEvent(attempt: previous))
        XCTAssertTrue(record.acceptsEvent(attempt: record.attemptID))
    }

    func testUnknownSizeHasNoPercentage() async {
        let record = TransferRecord(input: "abc", name: "file", accountID: nil, engine: .system, ip: nil)
        XCTAssertNil(record.fraction)
    }
    func testDeletingOneLocalTransferPreservesOtherRecordsAndFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try TaskStore(root: root)
        let first = TransferRecord(input: "file-a", name: "same.zip", accountID: "account", engine: .system, ip: nil)
        let second = TransferRecord(input: "file-b", name: "same.zip", accountID: "account", engine: .system, ip: nil)
        try store.save(first)
        try store.save(second)
        let firstFile = try store.file(for: first)
        let secondFile = try store.file(for: second)
        try Data("first".utf8).write(to: firstFile)
        try Data("second".utf8).write(to: secondFile)
        try store.removeLocalTransfer(first.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstFile.path))
        XCTAssertEqual(try Data(contentsOf: secondFile), Data("second".utf8))
        XCTAssertEqual(try store.load().map(\.id), [second.id])
    }
    func testEndpointResultsSurviveStoreReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let store = try TaskStore(root: root)
            try store.saveEndpoints([DirectEndpoint(ip: "8.8.8.8", available: false, latencyMS: nil, downloadVerified: false, error: "连接超时", checkedAt: Date())])
        }
        let reopened = try TaskStore(root: root)
        XCTAssertEqual(try reopened.loadEndpoints().first?.ip, "8.8.8.8")
        XCTAssertEqual(try reopened.loadEndpoints().first?.error, "连接超时")
    }

    func testLateExpirationCannotOverrideDeletionCompletionOrNewAttempt() async {
        var record = TransferRecord(input: "abc", name: "file", accountID: nil, engine: .direct, ip: "8.8.8.8")
        let attempt = record.attemptID
        for state in [TransferState.deleting, .completed] {
            record.state = state
            record.pauseForExpiration(attempt: attempt)
            XCTAssertEqual(record.state, state)
        }
        record.state = .running
        record.attemptID = UUID()
        record.pauseForExpiration(attempt: attempt)
        XCTAssertEqual(record.state, .running)
        record.pauseForExpiration(attempt: record.attemptID)
        XCTAssertEqual(record.state, .paused)
    }

}
