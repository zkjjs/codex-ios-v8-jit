import XCTest
@testable import GDirectSupport

final class TransferRateMeterTests: XCTestCase {
    func testResumedBytesAreNotCountedAsNewTraffic() {
        var meter = TransferRateMeter()
        meter.reset(completedBytes: 4_000_000, at: 100)
        meter.record(completedBytes: 4_200_000, at: 101)
        XCTAssertEqual(meter.bytesPerSecond(at: 101), 200_000, accuracy: 1)
    }
    func testCounterRestartNeverProducesNegativeOrInflatedSpeed() {
        var meter = TransferRateMeter()
        meter.reset(completedBytes: 1_000_000, at: 10)
        meter.record(completedBytes: 0, at: 11)
        XCTAssertEqual(meter.bytesPerSecond(at: 11), 0)
        meter.record(completedBytes: 100_000, at: 12)
        XCTAssertEqual(meter.bytesPerSecond(at: 12), 100_000, accuracy: 1)
    }
    func testSpeedExpiresWhenNoNewProgressArrives() {
        var meter = TransferRateMeter()
        meter.reset(completedBytes: 0, at: 0)
        meter.record(completedBytes: 1_000, at: 1)
        XCTAssertGreaterThan(meter.bytesPerSecond(at: 1), 0)
        XCTAssertEqual(meter.bytesPerSecond(at: 7), 0)
    }
    func testETAIsOnlyReportedWithKnownRemainingBytesAndCurrentSpeed() {
        var meter = TransferRateMeter()
        meter.reset(completedBytes: 0, at: 0)
        meter.record(completedBytes: 100, at: 1)
        XCTAssertEqual(meter.remainingSeconds(totalBytes: 1_100, completedBytes: 100, at: 1), 10)
        XCTAssertNil(meter.remainingSeconds(totalBytes: 0, completedBytes: 100, at: 1))
        XCTAssertNil(meter.remainingSeconds(totalBytes: 1_100, completedBytes: 100, at: 7))
    }
    func testSameTimestampAndTinyIntervalsDoNotCreateInfiniteRates() {
        var meter = TransferRateMeter()
        meter.reset(completedBytes: 0, at: 10)
        meter.record(completedBytes: 100, at: 10)
        XCTAssertEqual(meter.bytesPerSecond(at: 10), 0)
        meter.record(completedBytes: 200, at: 11)
        XCTAssertEqual(meter.bytesPerSecond(at: 11), 200, accuracy: 1)
    }
}
