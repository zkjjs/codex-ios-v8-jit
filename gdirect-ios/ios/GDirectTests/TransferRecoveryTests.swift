import XCTest
@testable import GDirect

@MainActor
final class TransferRecoveryTests: XCTestCase {
    func testStorePersistsEngineAndAccountWithoutToken() throws {
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

    func testUnexpectedTerminationPausesDirectWorkButKeepsSystemWork() {
        var direct = TransferRecord(input: "abc", name: "test", accountID: nil, engine: .direct, ip: "8.8.8.8")
        direct.state = .running
        direct.recoverAfterLaunch()
        XCTAssertEqual(direct.state, .paused)
        var system = TransferRecord(input: "abc", name: "test", accountID: nil, engine: .system, ip: nil)
        system.state = .running
        system.recoverAfterLaunch()
        XCTAssertEqual(system.state, .running)
    }

    func testSafeFilenameCannotEscapeTaskDirectory() {
        XCTAssertEqual(TransferRecord.safeName("../../private/file.zip"), "file.zip")
        XCTAssertEqual(TransferRecord.safeName(".."), "download")
        XCTAssertFalse(TransferRecord.safeName("a\\b\u{0}.zip").contains("\\"))
    }

    func testResumeWaitsForCancellationAcknowledgment() {
        var record = TransferRecord(input: "abc", name: "test", accountID: nil, engine: .system, ip: nil)
        record.state = .pausing
        XCTAssertFalse(record.canResume)
        record.state = .paused
        XCTAssertTrue(record.canResume)
    }

    func testEventsFromPreviousAttemptCannotChangeResumedTask() {
        var record = TransferRecord(input: "abc", name: "test", accountID: nil, engine: .system, ip: nil)
        let previous = record.attemptID
        record.attemptID = UUID()
        XCTAssertFalse(record.acceptsEvent(attempt: previous))
        XCTAssertTrue(record.acceptsEvent(attempt: record.attemptID))
    }

    func testUnknownSizeHasNoPercentage() {
        let record = TransferRecord(input: "abc", name: "file", accountID: nil, engine: .system, ip: nil)
        XCTAssertNil(record.fraction)
    }
}
