import Foundation

public enum Money {
    /// Parses a yuan amount typed or copied by a person. Returns cents, never a negative value.
    public static func cents(from text: String) -> Int? {
        var body = text
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: "元", with: "")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !body.hasPrefix("-") else { return nil }
        body = body.trimmingCharacters(in: CharacterSet(charactersIn: "+"))
        if !body.contains("."), body.filter({ $0 == "," }).count == 1 {
            let pieces = body.split(separator: ",", omittingEmptySubsequences: false)
            if pieces.count == 2, (1...2).contains(pieces[1].count), pieces[1].allSatisfy(\.isNumber) {
                body = pieces.joined(separator: ".")
            }
        }
        body = body.replacingOccurrences(of: ",", with: "")
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        guard let yuan = Int(parts[0]), yuan >= 0, yuan < 10_000_000 else { return nil }
        var fraction = 0
        if parts.count == 2 {
            let frac = String(parts[1])
            if frac.isEmpty {
                fraction = 0
            } else if frac.count <= 2, frac.allSatisfy(\.isNumber), let digits = Int(frac) {
                fraction = frac.count == 1 ? digits * 10 : digits
            } else {
                return nil
            }
        }
        return yuan * 100 + fraction
    }

    public static func plain(cents: Int) -> String {
        let absolute = abs(cents)
        return String(format: "%d.%02d", absolute / 100, absolute % 100)
    }

    public static func signedYuan(cents: Int, direction: LedgerDirection) -> String {
        let prefix = direction == .expense ? "-" : "+"
        return "\(prefix)¥\(plain(cents: cents))"
    }
}
