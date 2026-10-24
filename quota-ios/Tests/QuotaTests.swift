import XCTest
@testable import CodexQuota

final class QuotaTests: XCTestCase {
    func testDecodeRealSnapshotAndMissingReset() throws {
        let data = Data("""
        {"version":1,"updatedAt":100,"stale":false,"plan":"plus","windows":[
        {"id":"primary","title":"5 小时额度","usedPercent":69,"remainingPercent":31,"windowMinutes":300,"resetsAt":null}]}
        """.utf8)
        let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: data)
        XCTAssertEqual(snapshot.windows[0].remainingPercent, 31)
        XCTAssertNil(snapshot.windows[0].resetDate)
        XCTAssertEqual(snapshot.updatedDate, Date(timeIntervalSince1970: 100))
    }

    func testPastResetWaitsForNewData() {
        let window = QuotaWindow(id: "primary", title: "5 小时额度", usedPercent: 69,
                                 remainingPercent: 31, windowMinutes: 300, resetsAt: 100)
        XCTAssertTrue(window.awaitingReset(at: Date(timeIntervalSince1970: 101)))
        XCTAssertFalse(window.awaitingReset(at: Date(timeIntervalSince1970: 99)))
        XCTAssertEqual(window.remainingPercent, 31)
    }

    func testMissingWindowsStayEmptyAndStalenessUsesOriginalTime() throws {
        let data = Data(#"{"version":1,"updatedAt":100,"stale":true,"plan":null,"windows":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: data)
        XCTAssertTrue(snapshot.windows.isEmpty)
        XCTAssertTrue(snapshot.isStale(at: Date(timeIntervalSince1970: 101)))
        XCTAssertEqual(snapshot.updatedDate, Date(timeIntervalSince1970: 100))
    }

    func testOldSnapshotIsStaleEvenWithoutServerFlag() throws {
        let data = Data(#"{"version":1,"updatedAt":100,"stale":false,"plan":"plus","windows":[]}"#.utf8)
        let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: data)
        XCTAssertTrue(snapshot.isStale(at: Date(timeIntervalSince1970: 1100)))
        XCTAssertFalse(snapshot.isStale(at: Date(timeIntervalSince1970: 101)))
    }

    func testProgressIsBoundedAndMissingConfigurationFails() {
        let window = QuotaWindow(id: "x", title: "x", usedPercent: 0,
                                 remainingPercent: 120, windowMinutes: nil, resetsAt: nil)
        XCTAssertEqual(window.progress, 1)
        XCTAssertThrowsError(try ServerConnection(server: "http://example.com", accessCode: "x").validatedURL())
        XCTAssertThrowsError(try ServerConnection(server: "https://example.com", accessCode: "").validatedURL())
    }
}
