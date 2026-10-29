import Foundation

/// Turns OCR text from a payment screenshot into a receipt the person can confirm.
///
/// Amounts are scored from the words in front of them. 实付 beats 订单金额, and 余额 / 优惠 are discarded.
/// Nothing is saved here; the app only stores a record after the person confirms it.
public enum ReceiptParser {
    public static func parse(lines: [String], now: Date = Date()) -> ParsedReceipt {
        parse(text: lines.joined(separator: "\n"), now: now)
    }

    public static func parse(text: String, now: Date = Date()) -> ParsedReceipt {
        let normalized = normalize(text)
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        let body = lines.joined(separator: "\n")
        let amount = bestAmount(in: body)
        let direction = amount?.direction ?? globalDirection(in: body)
        let names = names(in: lines, amountLine: amount?.lineIndex)
        let occurredAt = date(in: body, now: now)
        let method = paymentMethod(in: lines, text: body)
        let category = guessCategory(
            merchant: names.merchant,
            note: names.note,
            text: body,
            direction: direction
        )
        return ParsedReceipt(
            amountCents: amount?.cents,
            direction: direction,
            merchant: names.merchant,
            category: category,
            occurredAt: occurredAt,
            paymentMethod: method,
            note: names.note,
            rawText: body
        )
    }

    public static func guessCategory(
        merchant: String,
        note: String,
        text: String,
        direction: LedgerDirection
    ) -> LedgerCategory {
        let haystack = [merchant, note, text].joined(separator: "\n").lowercased()
        let rules: [(LedgerCategory, [String])] = [
            (.transfer, ["转账", "红包", "还款"]),
            (.medical, ["医院", "药店", "药房", "挂号", "门诊", "医保", "诊所"]),
            (.transport, ["滴滴", "高德打车", "地铁", "公交", "铁路", "12306", "加油", "停车", "曹操", "出租", "哈啰", "高铁", "机票", "石化", "石油"]),
            (.food, ["餐饮", "美团", "饿了么", "咖啡", "奶茶", "星巴克", "瑞幸", "肯德基", "麦当劳", "食堂", "烧烤", "火锅", "饭店", "外卖", "餐厅"]),
            (.housing, ["房租", "水费", "电费", "燃气", "物业", "暖气", "话费"]),
            (.entertainment, ["电影", "猫眼", "游戏", "腾讯视频", "爱奇艺", "优酷", "网易云", "bilibili", "b站"]),
            (.shopping, ["淘宝", "天猫", "京东", "拼多多", "超市", "便利", "盒马", "沃尔玛", "百货", "抖音"]),
        ]
        for (category, words) in rules where words.contains(where: { haystack.contains($0) }) {
            return category
        }
        return direction == .income ? .income : .other
    }

    private struct AmountHit {
        var cents: Int
        var location: Int
        var lineIndex: Int
        var direction: LedgerDirection?
        var score: Int
    }

    private struct FoundName {
        var merchant: String
        var note: String
    }

    private static let merchantLabels = ["商户全称", "商户名称", "收款方全称", "收款方", "交易对方", "对方户名", "商家名称", "商家"]
    private static let productLabels = ["商品说明", "商品名称", "商品"]
    private static let methodLabels = ["支付方式", "付款方式"]
    private static let otherLabels = ["支付时间", "交易时间", "付款时间", "创建时间", "当前状态", "收单机构", "账单详情", "交易单号", "商户单号", "订单号", "转账单号"]
    private static let methodTokens = ["微信支付", "支付宝", "云闪付", "数字人民币", "余额宝", "花呗", "零钱通", "零钱", "信用卡", "储蓄卡", "银行卡"]
    private static let statusValues: Set<String> = ["支付成功", "付款成功", "交易成功", "退款成功", "收款成功", "已完成", "成功", "已收款", "待支付"]
    private static let fullDatePattern = #"(\d{4})\s*[年\-/\.]\s*(\d{1,2})\s*[月\-/\.]\s*(\d{1,2})\s*日?(?:\s*(\d{1,2})\s*[:：]\s*(\d{2})(?:\s*[:：]\s*(\d{2}))?)?"#
    private static let monthDayPattern = #"(?:^|[^\d])(\d{1,2})\s*月\s*(\d{1,2})\s*日\s*(\d{1,2})\s*[:：]\s*(\d{2})(?:\s*[:：]\s*(\d{2}))?"#

    private static func bestAmount(in text: String) -> AmountHit? {
        let ns = text as NSString
        var hits: [AmountHit] = []
        hits += currencyHits(in: ns, pattern: #"¥\s*([0-9]{1,7}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)"#, bonus: 40)
        hits += currencyHits(in: ns, pattern: #"人民币\s*([0-9]{1,7}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)\s*元"#, bonus: 50)
        hits += currencyHits(in: ns, pattern: #"(?:^|[^\d.])([0-9]{1,7}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)\s*元"#, bonus: 20)
        hits += bareHits(in: ns)
        return hits.filter { $0.score > 0 }.max { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score < rhs.score }
            return lhs.location < rhs.location
        }
    }

    private static func currencyHits(in ns: NSString, pattern: String, bonus: Int) -> [AmountHit] {
        allMatches(pattern: pattern, in: ns).compactMap { match in
            guard let raw = match.groups.first ?? nil, let cents = absoluteCents(raw) else { return nil }
            let numberRange = match.groupRanges.first ?? match.full
            return makeHit(cents: cents, range: numberRange, sign: nil, bonus: bonus, in: ns)
        }
    }

    private static func bareHits(in ns: NSString) -> [AmountHit] {
        let pattern = #"(?:^|\n|\s)([+-])?([0-9]{1,7}(?:,[0-9]{3})*\.[0-9]{2})(?=$|[^\d])"#
        return allMatches(pattern: pattern, in: ns).compactMap { match in
            guard match.groups.count >= 2, let raw = match.groups[1], let cents = absoluteCents(raw) else { return nil }
            let numberRange = match.groupRanges.count >= 2 ? match.groupRanges[1] : match.full
            let line = lineText(containing: numberRange, in: ns)
            let bareLine = line.trimmingCharacters(in: .whitespaces)
            let window = windowBefore(numberRange, in: ns)
            let keywords = ["金额", "支付", "支出", "收入", "实付", "付款", "收款", "退款", "消费", "扣款", "¥"]
            let lineIsOnlyNumber = bareLine == raw || bareLine == "-\(raw)" || bareLine == "+\(raw)" || bareLine == "¥\(raw)"
            guard lineIsOnlyNumber || keywords.contains(where: { window.contains($0) || line.contains($0) }) else {
                return nil
            }
            return makeHit(cents: cents, range: numberRange, sign: match.groups[0], bonus: lineIsOnlyNumber ? 35 : 25, in: ns)
        }
    }

    private static func makeHit(cents: Int, range: NSRange, sign: String?, bonus: Int, in ns: NSString) -> AmountHit {
        let window = windowBefore(range, in: ns)
        let keyword = closestKeyword(in: window)
        let score = bonus + keyword.score
        var direction = keyword.direction ?? direction(in: window)
        if direction == nil {
            if sign == "+" { direction = .income }
            if sign == "-" { direction = .expense }
        }
        return AmountHit(
            cents: cents,
            location: range.location,
            lineIndex: lineIndex(of: range.location, in: ns),
            direction: direction,
            score: score
        )
    }

    private static func names(in lines: [String], amountLine: Int?) -> FoundName {
        var merchant = labeledValue(in: lines, labels: merchantLabels) ?? ""
        var product = labeledValue(in: lines, labels: productLabels)
        if merchant.isEmpty, let directed = firstGroup(pattern: #"向\s*(.{1,24}?)\s*付款"#, in: lines.joined(separator: "\n")) {
            merchant = cleanName(directed)
        }
        if merchant.isEmpty, let productName = product {
            merchant = productName
            product = nil
        }
        if merchant.isEmpty, let amountLine {
            var candidates: [String] = []
            if amountLine + 1 < lines.count {
                candidates.append(contentsOf: lines[(amountLine + 1)...])
            }
            if amountLine > 0 {
                candidates.append(contentsOf: lines[..<amountLine].reversed())
            }
            for line in candidates {
                if isNoise(line) { continue }
                merchant = cleanName(line)
                if !merchant.isEmpty { break }
            }
        }
        let note = product.flatMap { value in value == merchant ? nil : value } ?? ""
        return FoundName(merchant: merchant, note: note)
    }

    private static func paymentMethod(in lines: [String], text: String) -> String {
        let labeled = labeledValue(in: lines, labels: methodLabels) ?? ""
        let platform = detectPlatform(in: text)
        let token = methodTokens.first { candidate in
            guard text.contains(candidate) else { return false }
            return candidate != platform
        }
        if !labeled.isEmpty {
            if let platform, !labeled.contains(platform) {
                return "\(platform) · \(labeled)"
            }
            return labeled
        }
        if let platform, let token, token != platform, !platform.contains(token) {
            return "\(platform) · \(token)"
        }
        return platform ?? token ?? ""
    }

    private static func detectPlatform(in text: String) -> String? {
        let markers = ["微信支付", "支付宝", "云闪付"]
        let found = markers.compactMap { marker -> (String, Range<String.Index>)? in
            guard let range = text.range(of: marker) else { return nil }
            return (marker, range)
        }
        return found.min { $0.1.lowerBound < $1.1.lowerBound }?.0
    }

    private static func date(in text: String, now: Date) -> Date? {
        let calendar = LedgerCalendar.shanghai
        if let hit = firstDate(pattern: fullDatePattern, in: text, calendar: calendar, now: now, includesYear: true) {
            return hit
        }
        return firstDate(pattern: monthDayPattern, in: text, calendar: calendar, now: now, includesYear: false)
    }

    private static func firstDate(
        pattern: String,
        in text: String,
        calendar: Calendar,
        now: Date,
        includesYear: Bool
    ) -> Date? {
        let ns = text as NSString
        let matches = allMatches(pattern: pattern, in: ns)
        let hits: [(date: Date, rank: Int, location: Int)] = matches.compactMap { match in
            let values = match.groups.compactMap { $0 }
            guard values.count >= 3 else { return nil }
            let numbers = values.compactMap { Int($0) }
            guard numbers.count >= 3 else { return nil }
            var year: Int
            var month: Int
            var day: Int
            var hour = 0
            var minute = 0
            var second = 0
            var cursor = 0
            if includesYear {
                year = numbers[0]
                month = numbers[1]
                day = numbers[2]
                cursor = 3
            } else {
                year = calendar.component(.year, from: now)
                month = numbers[0]
                day = numbers[1]
                cursor = 2
            }
            let hasTime = numbers.count >= cursor + 2
            if hasTime {
                hour = numbers[cursor]
                minute = numbers[cursor + 1]
                if numbers.count >= cursor + 3 { second = numbers[cursor + 2] }
            }
            guard let date = makeDate(year: year, month: month, day: day, hour: hour, minute: minute, second: second, calendar: calendar) else {
                return nil
            }
            let resolved = includesYear ? date : rollBackFuture(date, now: now, calendar: calendar)
            let window = windowBefore(match.full, length: 8, in: ns)
            let nearLabel = window.contains("时间") ? 2 : 0
            let timeRank = hasTime ? 1 : 0
            return (resolved, nearLabel + timeRank, match.full.location)
        }
        return hits.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank > rhs.rank }
            return lhs.location < rhs.location
        }.first?.date
    }

    private static func rollBackFuture(_ date: Date, now: Date, calendar: Calendar) -> Date {
        let days = calendar.dateComponents([.day], from: now, to: date).day ?? 0
        guard days > 31, let adjusted = calendar.date(byAdding: .year, value: -1, to: date) else {
            return date
        }
        return adjusted
    }

    private static func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int,
        calendar: Calendar
    ) -> Date? {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date
    }

    private static func globalDirection(in text: String) -> LedgerDirection {
        if ["退款成功", "已退款", "收款成功", "已收款"].contains(where: text.contains) {
            return .income
        }
        return .expense
    }

    /// The label closest to the amount wins, so an earlier 优惠 does not hide a later 实付.
    private static func closestKeyword(in window: String) -> (score: Int, direction: LedgerDirection?) {
        let rules: [(String, Int, LedgerDirection?)] = [
            ("余额", -300, nil),
            ("优惠", -120, nil),
            ("立减", -120, nil),
            ("折扣", -120, nil),
            ("抵扣", -120, nil),
            ("实付款", 160, .expense),
            ("实付", 160, .expense),
            ("支付金额", 160, .expense),
            ("付款金额", 160, .expense),
            ("扣款金额", 160, .expense),
            ("收款金额", 160, .income),
            ("退款金额", 160, .income),
            ("收入金额", 160, .income),
            ("订单金额", 30, nil),
            ("原价", 30, nil),
            ("商品金额", 30, nil),
            ("退款", 80, .income),
            ("收款", 80, .income),
            ("收入", 80, .income),
            ("转入", 80, .income),
            ("入账", 80, .income),
            ("支出", 80, .expense),
            ("扣款", 80, .expense),
            ("消费", 80, .expense),
            ("付款", 80, .expense),
            ("支付", 80, .expense),
            ("转出", 80, .expense),
        ]
        var best: (end: String.Index, length: Int, score: Int, direction: LedgerDirection?)?
        for (word, score, direction) in rules {
            var search = window.startIndex
            while let range = window.range(of: word, range: search..<window.endIndex) {
                let longerAtSameEnd = best?.end == range.upperBound && word.count > (best?.length ?? 0)
                if best == nil || range.upperBound > best!.end || longerAtSameEnd {
                    best = (range.upperBound, word.count, score, direction)
                }
                if range.upperBound == window.endIndex { break }
                search = window.index(after: range.lowerBound)
            }
        }
        return (best?.score ?? 0, best?.direction)
    }

    private static func direction(in window: String) -> LedgerDirection? {
        if ["退款", "收款", "收入", "转入", "入账"].contains(where: window.contains) { return .income }
        if ["支出", "扣款", "消费", "付款", "支付", "转出"].contains(where: window.contains) { return .expense }
        return nil
    }

    private static func labeledValue(in lines: [String], labels: [String]) -> String? {
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            for label in labels where trimmed.hasPrefix(label) {
                var rest = trimmed.dropFirst(label.count)
                while let first = rest.first, "：: \t-—".contains(first) {
                    rest.removeFirst()
                }
                let inline = cleanName(String(rest))
                if !inline.isEmpty { return inline }
                let next = index + 1
                if next < lines.count, !isLabelLine(lines[next]) {
                    let value = cleanName(lines[next])
                    if !value.isEmpty { return value }
                }
            }
        }
        return nil
    }

    private static func isLabelLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let labels = merchantLabels + productLabels + methodLabels + otherLabels
        return labels.contains { trimmed == $0 || trimmed.hasPrefix($0) }
    }

    private static func isNoise(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || isLabelLine(trimmed) || statusValues.contains(trimmed) { return true }
        if methodTokens.contains(trimmed) { return true }
        if trimmed.contains("单号") { return true }
        let ns = trimmed as NSString
        for pattern in [fullDatePattern, monthDayPattern] {
            if let match = firstMatch(pattern: pattern, in: ns), match.full.length * 10 > ns.length * 6 {
                return true
            }
        }
        let hasCJK = trimmed.contains { character in
            guard let value = character.unicodeScalars.first?.value else { return false }
            return (0x4E00...0x9FFF).contains(value)
        }
        if !hasCJK && trimmed.contains(where: \.isNumber) { return true }
        return false
    }

    private static func cleanName(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = text.first, "：: \t-—".contains(first) {
            text.removeFirst()
        }
        text = text.trimmingCharacters(in: .whitespaces)
        if statusValues.contains(text) || text.isEmpty { return "" }
        if text.count > 40 { text = String(text.prefix(40)) }
        return text
    }

    private static func absoluteCents(_ raw: String) -> Int? {
        Money.cents(from: raw)
    }

    private static func normalize(_ raw: String) -> String {
        let unified = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var mapped = ""
        for scalar in unified.unicodeScalars {
            switch scalar.value {
            case 0xFF10...0xFF19:
                mapped.append(Character(UnicodeScalar(scalar.value - 0xFF10 + 0x30)!))
            case 0xFF0E:
                mapped.append(".")
            case 0xFF0C:
                mapped.append(",")
            case 0xFFE5:
                mapped.append("¥")
            default:
                mapped.append(Character(scalar))
            }
        }
        let chars = Array(mapped)
        var output: [Character] = []
        for (index, char) in chars.enumerated() {
            let isGap = char != "\n" && char.isWhitespace
            if isGap {
                let previous = index > 0 ? chars[index - 1] : nil
                let next = index + 1 < chars.count ? chars[index + 1] : nil
                if let previous, let next {
                    if isCJK(previous) && isCJK(next) { continue }
                    if isNumberPiece(previous) && isNumberPiece(next) { continue }
                    if previous == "¥" && next.isNumber { continue }
                }
                output.append(" ")
                continue
            }
            output.append(char)
        }
        return String(output)
    }

    private static func isCJK(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first?.value, character.unicodeScalars.count == 1 else { return false }
        return (0x4E00...0x9FFF).contains(value)
    }

    private static func isNumberPiece(_ character: Character) -> Bool {
        character.isNumber || character == "." || character == ","
    }

    private struct TextMatch {
        var full: NSRange
        var groups: [String?]
        var groupRanges: [NSRange]
    }

    private static func allMatches(pattern: String, in ns: NSString) -> [TextMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(location: 0, length: ns.length)
        return regex.matches(in: ns as String, range: range).map { result in
            var groups: [String?] = []
            var groupRanges: [NSRange] = []
            if result.numberOfRanges > 1 {
                for index in 1..<result.numberOfRanges {
                    let group = result.range(at: index)
                    groupRanges.append(group)
                    if group.location == NSNotFound {
                        groups.append(nil)
                    } else {
                        groups.append(ns.substring(with: group))
                    }
                }
            }
            return TextMatch(full: result.range, groups: groups, groupRanges: groupRanges)
        }
    }

    private static func firstMatch(pattern: String, in ns: NSString) -> TextMatch? {
        allMatches(pattern: pattern, in: ns).first
    }

    private static func firstGroup(pattern: String, in text: String) -> String? {
        let ns = text as NSString
        guard let match = firstMatch(pattern: pattern, in: ns) else { return nil }
        return match.groups.first ?? nil
    }

    private static func windowBefore(_ range: NSRange, length: Int = 32, in ns: NSString) -> String {
        guard range.location != NSNotFound, range.location > 0 else { return "" }
        let start = max(0, range.location - length)
        return ns.substring(with: NSRange(location: start, length: range.location - start))
    }

    private static func lineIndex(of location: Int, in ns: NSString) -> Int {
        guard location > 0 else { return 0 }
        let prefix = ns.substring(with: NSRange(location: 0, length: min(location, ns.length)))
        return prefix.reduce(into: 0) { count, character in
            if character == "\n" { count += 1 }
        }
    }

    private static func lineText(containing range: NSRange, in ns: NSString) -> String {
        let lineStart: Int
        if range.location > 0 {
            let found = ns.range(
                of: "\n",
                options: .backwards,
                range: NSRange(location: 0, length: range.location)
            )
            lineStart = found.location == NSNotFound ? 0 : found.location + 1
        } else {
            lineStart = 0
        }
        let tail = NSRange(location: min(range.location, ns.length), length: max(ns.length - range.location, 0))
        let lineEnd = ns.range(of: "\n", range: tail).location
        let end = lineEnd == NSNotFound ? ns.length : lineEnd
        guard end >= lineStart else { return "" }
        return ns.substring(with: NSRange(location: lineStart, length: end - lineStart))
    }
}
