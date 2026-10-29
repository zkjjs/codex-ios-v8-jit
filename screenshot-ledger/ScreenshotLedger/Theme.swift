import SwiftUI
import LedgerCore

enum Theme {
    static let paper = Color(red: 0.973, green: 0.957, blue: 0.933)
    static let ink = Color(red: 0.145, green: 0.125, blue: 0.102)
    static let muted = Color(red: 0.455, green: 0.416, blue: 0.365)
    static let line = Color(red: 0.886, green: 0.851, blue: 0.792)
    static let card = Color.white
    static let expense = Color(red: 0.761, green: 0.318, blue: 0.169)
    static let income = Color(red: 0.176, green: 0.435, blue: 0.369)
}

enum LedgerDateText {
    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = LedgerCalendar.shanghai.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = LedgerCalendar.shanghai.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

struct MonthPager: View {
    @Binding var month: Date

    var body: some View {
        HStack {
            Button {
                shift(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            Spacer()
            Text(title)
                .font(.headline)
            Spacer()
            Button {
                shift(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(!canGoForward)
        }
        .foregroundStyle(Theme.ink)
    }

    private var title: String {
        let parts = LedgerCalendar.shanghai.dateComponents([.year, .month], from: month)
        return "\(parts.year ?? 0)年\(parts.month ?? 0)月"
    }

    private var canGoForward: Bool {
        let calendar = LedgerCalendar.shanghai
        let today = calendar.dateComponents([.year, .month], from: Date())
        let shown = calendar.dateComponents([.year, .month], from: month)
        if shown.year != today.year { return (shown.year ?? 0) < (today.year ?? 0) }
        return (shown.month ?? 0) < (today.month ?? 0)
    }

    private func shift(_ value: Int) {
        guard value < 0 || canGoForward else { return }
        if let next = LedgerCalendar.shanghai.date(byAdding: .month, value: value, to: month) {
            month = next
        }
    }
}
