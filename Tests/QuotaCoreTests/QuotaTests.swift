import XCTest
@testable import QuotaCore

final class QuotaTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    func decode(_ json: String) throws -> QuotaSnapshot {
        try JSONDecoder().decode(UsageResponse.self, from: Data(json.utf8)).snapshot(at: now)
    }
    func testRealWireFormatAndRemaining() throws {
        let result = try decode(#"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":25,"limit_window_seconds":18000,"reset_at":1800003600},"secondary_window":{"used_percent":90,"limit_window_seconds":604800,"reset_at":1800086400}}}"#)
        XCTAssertEqual(result.windows.count, 2)
        XCTAssertEqual(result.windows[0].remainingPercent, 75)
        XCTAssertEqual(result.windows[1].remainingPercent, 10)
        XCTAssertEqual(result.nextReset(after: now), now.addingTimeInterval(3600))
        XCTAssertEqual(result.plan, "plus")
    }
    func testMissingWindowsRemainUnknown() throws {
        XCTAssertTrue(try decode(#"{"plan_type":"plus","rate_limit":null}"#).windows.isEmpty)
        let result = try decode(#"{"rate_limit":{"primary_window":{"reset_at":1800003600}}}"#)
        XCTAssertNil(result.windows.first?.remainingPercent)
        XCTAssertNil(result.windows.first?.durationSeconds)
    }
    func testClampsOutOfRangePercentages() throws {
        let result = try decode(#"{"rate_limit":{"primary_window":{"used_percent":150},"secondary_window":{"used_percent":-4}}}"#)
        XCTAssertEqual(result.windows.map(\.remainingPercent), [0, 100])
    }
    func testElapsedResetNeverReplenishes() throws {
        let result = try decode(#"{"rate_limit":{"primary_window":{"used_percent":100,"reset_at":1799999999}}}"#)
        XCTAssertEqual(result.windows.first?.remainingPercent, 0)
        XCTAssertNil(result.nextReset(after: now))
        XCTAssertTrue(result.windows[0].needsResetRefresh(at: now))
    }
    func testMissingAndZeroResetNotDates() throws {
        let result = try decode(#"{"rate_limit":{"primary_window":{"used_percent":10},"secondary_window":{"reset_at":0}}}"#)
        XCTAssertTrue(result.windows.allSatisfy { $0.resetAt == nil })
    }
    func testEarliestFutureResetAcrossWindows() throws {
        let result = try decode(#"{"rate_limit":{"primary_window":{"reset_at":1799999999},"secondary_window":{"reset_at":1800000600}}}"#)
        XCTAssertEqual(result.nextReset(after: now), now.addingTimeInterval(600))
    }
    func testIgnoresAdditionalBucketsForMainAccountQuota() throws {
        let result = try decode(#"{"rate_limit":null,"additional_rate_limits":[{"metered_feature":"other","rate_limit":{"primary_window":{"used_percent":70}}}]}"#)
        XCTAssertTrue(result.windows.isEmpty)
    }
    func testSnapshotRoundTrip() throws {
        let result = try decode(#"{"plan_type":"plus","rate_limit":{"secondary_window":{"used_percent":10,"reset_at":1800000600}}}"#)
        let data = try JSONEncoder().encode(result)
        XCTAssertEqual(try JSONDecoder().decode(QuotaSnapshot.self, from: data), result)
    }
    func testDeviceCodeAliasesAndIntervals() throws {
        let a = try JSONDecoder().decode(DeviceCode.self, from: Data(#"{"device_auth_id":"id","usercode":"A-B","interval":"5"}"#.utf8))
        let b = try JSONDecoder().decode(DeviceCode.self, from: Data(#"{"device_auth_id":"id","user_code":"A-B","interval":7}"#.utf8))
        XCTAssertEqual(a.userCode, b.userCode)
        XCTAssertEqual(a.interval, 5)
        XCTAssertEqual(b.interval, 7)
    }
    func testRetryAfterSecondsAndDate() {
        XCTAssertEqual(RetryPolicy.delay(header: "120", now: now), 120)
        XCTAssertEqual(RetryPolicy.delay(header: "nonsense", now: now), 60)
        XCTAssertEqual(RetryPolicy.delay(header: "-5", now: now), 60)
        XCTAssertEqual(RetryPolicy.delay(header: "Thu, 01 Jan 1970 00:02:00 GMT", now: Date(timeIntervalSince1970: 0)), 120)
    }
}
