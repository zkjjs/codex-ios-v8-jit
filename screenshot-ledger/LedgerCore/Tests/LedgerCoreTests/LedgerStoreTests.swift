import XCTest
@testable import LedgerCore

final class LedgerStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testRoundTripUpdateAndMonthSummary() throws {
        let url = directory.appendingPathComponent("ledger.json")
        let store = try LedgerStore(fileURL: url)
        let october = entry(cents: 2850, merchant: "星巴克", at: shanghai(2026, 10, 31, 23, 30))
        let november = entry(cents: 5000, merchant: "工资", direction: .income, category: .income, at: shanghai(2026, 11, 1, 0, 30))
        try store.add(october)
        try store.add(november)

        let reloaded = try LedgerStore(fileURL: url)
        XCTAssertEqual(reloaded.entries.map(\.id), [november.id, october.id])

        var changed = october
        changed.merchant = "瑞幸咖啡"
        changed.updatedAt = shanghai(2026, 10, 31, 23, 40)
        try reloaded.update(changed)

        let summary = reloaded.summary(for: shanghai(2026, 10, 15, 0, 0))
        XCTAssertEqual(summary.expenseCents, 2850)
        XCTAssertEqual(summary.incomeCents, 0)
        XCTAssertEqual(summary.balanceCents, -2850)
        XCTAssertEqual(summary.categoryTotals.map(\.category), [.food])

        let persisted = try LedgerStore(fileURL: url)
        XCTAssertEqual(persisted.entries.first { $0.id == october.id }?.merchant, "瑞幸咖啡")
        XCTAssertEqual(persisted.summary(for: shanghai(2026, 11, 2, 0, 0)).incomeCents, 5000)
    }

    func testDeleteAndInvalidValues() throws {
        let store = try LedgerStore(fileURL: directory.appendingPathComponent("ledger.json"))
        let item = entry(cents: 100, merchant: "地铁", category: .transport, at: shanghai(2026, 10, 2, 8, 0))
        try store.add(item)
        try store.delete(id: item.id)
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertThrowsError(try store.delete(id: item.id)) { error in
            XCTAssertEqual(error as? LedgerStoreError, .missingEntry)
        }

        var negative = item
        negative.id = UUID()
        negative.amountCents = -1
        XCTAssertThrowsError(try store.add(negative)) { error in
            XCTAssertEqual(error as? LedgerStoreError, .invalidAmount)
        }
    }

    func testCorruptFileThrows() throws {
        let url = directory.appendingPathComponent("ledger.json")
        try "{".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try LedgerStore(fileURL: url)) { error in
            XCTAssertEqual(error as? LedgerStoreError, .unreadable)
        }
    }

    private func entry(
        cents: Int,
        merchant: String,
        direction: LedgerDirection = .expense,
        category: LedgerCategory = .food,
        at date: Date
    ) -> LedgerEntry {
        LedgerEntry(
            amountCents: cents,
            direction: direction,
            merchant: merchant,
            category: category,
            occurredAt: date,
            createdAt: date,
            updatedAt: date
        )
    }

    private func shanghai(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return LedgerCalendar.shanghai.date(from: components)!
    }
}
