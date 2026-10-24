import XCTest
@testable import QuotaCore

final class CacheTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func snapshot() throws -> QuotaSnapshot {
        try JSONDecoder().decode(UsageResponse.self, from: Data(#"{"rate_limit":{"primary_window":{"used_percent":25,"reset_at":1800007200}}}"#.utf8)).snapshot(at: now)
    }
    func testOverlappingSuccessPreservesNewerThrottle() throws {
        let id = UUID()
        var state = SharedState(sessionID: id, snapshot: nil, message: "限流", retryAt: now.addingTimeInterval(120))
        state.apply(try snapshot(), sessionID: id, now: now)
        XCTAssertNotNil(state.snapshot)
        XCTAssertEqual(state.retryAt, now.addingTimeInterval(120))
    }
    func testLogoutAndNewSessionRejectOldCompletion() throws {
        var state = SharedState(sessionID: UUID(), snapshot: nil, message: nil, retryAt: nil)
        state.apply(try snapshot(), sessionID: UUID(), now: now)
        XCTAssertNil(state.snapshot)
    }
    func testWidgetTimelineIncludesFreshnessExpiryWithoutNetwork() throws {
        let dates = try snapshot().timelineBoundaries(after: now)
        XCTAssertEqual(dates, [now.addingTimeInterval(3601), now.addingTimeInterval(7201)])
    }
    func testResigningPreservesConfiguredSharedGroupSuffix() {
        XCTAssertEqual(SigningGroups.resolve(configured: "OLDTEAM123.com.custom.quota.shared", actualDefaultGroup: "NEWTEAM456.com.custom.app"), "NEWTEAM456.com.custom.quota.shared")
        XCTAssertEqual(SigningGroups.resolve(configured: "com.custom.quota.shared", actualDefaultGroup: "NEWTEAM456.com.custom.app"), "NEWTEAM456.com.custom.quota.shared")
        XCTAssertNil(SigningGroups.resolve(configured: "$(AppIdentifierPrefix)missing", actualDefaultGroup: nil))
    }
}
