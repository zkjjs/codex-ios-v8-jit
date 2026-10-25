import Foundation

enum QuotaSchedule {
    static func dates(snapshot: QuotaSnapshot?, now: Date) -> [Date] {
        var dates = [now]
        if let snapshot {
            dates += snapshot.windows.compactMap(\.resetDate)
                .map { $0.addingTimeInterval(1) }.filter { $0 > now }
            let staleAt = snapshot.updatedDate.addingTimeInterval(901)
            if staleAt > now { dates.append(staleAt) }
        }
        return Array(Set(dates)).sorted()
    }
}
