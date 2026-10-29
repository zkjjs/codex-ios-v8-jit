import Foundation

public final class LedgerStore {
    public private(set) var entries: [LedgerEntry]
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let manager = FileManager.default
        if !manager.fileExists(atPath: fileURL.path) {
            entries = []
            return
        }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            entries = []
            return
        }
        do {
            entries = try decoder.decode(LedgerFile.self, from: data).entries
        } catch {
            throw LedgerStoreError.unreadable
        }
        sortEntries()
    }

    public func add(_ entry: LedgerEntry) throws {
        guard entry.amountCents >= 0 else { throw LedgerStoreError.invalidAmount }
        entries.append(entry)
        sortEntries()
        try persist()
    }

    public func update(_ entry: LedgerEntry) throws {
        guard entry.amountCents >= 0 else { throw LedgerStoreError.invalidAmount }
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else {
            throw LedgerStoreError.missingEntry
        }
        entries[index] = entry
        sortEntries()
        try persist()
    }

    public func delete(id: UUID) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            throw LedgerStoreError.missingEntry
        }
        entries.remove(at: index)
        try persist()
    }

    public func entries(inMonthOf date: Date, calendar: Calendar = LedgerCalendar.shanghai) -> [LedgerEntry] {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return [] }
        return entries.filter { interval.contains($0.occurredAt) }
    }

    public func summary(for date: Date, calendar: Calendar = LedgerCalendar.shanghai) -> MonthSummary {
        var expense = 0
        var income = 0
        var buckets: [LedgerCategory: Int] = [:]
        for entry in entries(inMonthOf: date, calendar: calendar) {
            switch entry.direction {
            case .expense:
                expense += entry.amountCents
                buckets[entry.category, default: 0] += entry.amountCents
            case .income:
                income += entry.amountCents
            }
        }
        let totals = buckets
            .map { CategoryTotal(category: $0.key, amountCents: $0.value) }
            .sorted { lhs, rhs in
                if lhs.amountCents != rhs.amountCents { return lhs.amountCents > rhs.amountCents }
                return lhs.category.title < rhs.category.title
            }
        return MonthSummary(expenseCents: expense, incomeCents: income, categoryTotals: totals)
    }

    private func sortEntries() {
        entries.sort { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt > rhs.occurredAt }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(LedgerFile(entries: entries))
        try data.write(to: fileURL, options: .atomic)
    }
}

private struct LedgerFile: Codable {
    var entries: [LedgerEntry]
}
