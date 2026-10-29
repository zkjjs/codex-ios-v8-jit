import XCTest
@testable import LedgerCore

final class ReceiptParserTests: XCTestCase {
    private var now: Date!

    override func setUp() {
        super.setUp()
        now = shanghai(2026, 10, 29, 12, 0)
    }

    func testWeChatPaymentSuccess() {
        let receipt = parse("""
        微信支付
        支付成功
        ¥28.50
        星巴克咖啡
        支付时间
        2026-10-29 21:30:12
        支付方式
        零钱
        """)

        XCTAssertEqual(receipt.amountCents, 2850)
        XCTAssertEqual(receipt.direction, .expense)
        XCTAssertEqual(receipt.merchant, "星巴克咖啡")
        XCTAssertEqual(receipt.category, .food)
        XCTAssertEqual(receipt.paymentMethod, "微信支付 · 零钱")
        assertDate(receipt.occurredAt, 2026, 10, 29, 21, 30, 12)
    }

    func testAlipayPrefersActualPaid() {
        let receipt = parse("""
        支付宝
        付款成功
        订单金额
        ¥128.00
        优惠
        ¥10.00
        实付款
        ¥118.00
        收款方
        某某餐厅
        支付时间
        2026年10月29日 12:01:05
        """)

        XCTAssertEqual(receipt.amountCents, 11800)
        XCTAssertEqual(receipt.direction, .expense)
        XCTAssertEqual(receipt.merchant, "某某餐厅")
        XCTAssertEqual(receipt.category, .food)
        XCTAssertEqual(receipt.paymentMethod, "支付宝")
        assertDate(receipt.occurredAt, 2026, 10, 29, 12, 1, 5)
    }

    func testBillDetailUsesMerchantFullNameAndProductNote() {
        let receipt = parse("""
        商户消费
        商户全称
        杭州某某餐饮有限公司
        商品
        牛肉面
        -32.00
        当前状态
        支付成功
        支付时间
        2026年3月1日 18:22:01
        """)

        XCTAssertEqual(receipt.amountCents, 3200)
        XCTAssertEqual(receipt.merchant, "杭州某某餐饮有限公司")
        XCTAssertEqual(receipt.note, "牛肉面")
        XCTAssertEqual(receipt.category, .food)
        assertDate(receipt.occurredAt, 2026, 3, 1, 18, 22, 1)
    }

    func testBankSMSIgnoresBalance() {
        let receipt = parse("您尾号6612的储蓄卡于10月29日21:30支出人民币88.00元，余额123.45元。")

        XCTAssertEqual(receipt.amountCents, 8800)
        XCTAssertEqual(receipt.direction, .expense)
        XCTAssertEqual(receipt.paymentMethod, "储蓄卡")
        XCTAssertEqual(receipt.merchant, "")
        assertDate(receipt.occurredAt, 2026, 10, 29, 21, 30, 0)
    }

    func testBalanceAloneIsNotAnAmount() {
        let receipt = parse("""
        账户余额
        ¥1,234.56
        """)
        XCTAssertNil(receipt.amountCents)
    }

    func testRefundIsIncome() {
        let receipt = parse("""
        退款成功
        ¥20.00
        星巴克
        """)
        XCTAssertEqual(receipt.amountCents, 2000)
        XCTAssertEqual(receipt.direction, .income)
        XCTAssertEqual(receipt.category, .food)
        XCTAssertEqual(receipt.merchant, "星巴克")
    }

    func testCommaAndFullwidthAmounts() {
        XCTAssertEqual(parse("支付成功\n¥1,280.50\n京东").amountCents, 128050)
        XCTAssertEqual(parse("支付成功\n￥２８．５０\n瑞幸咖啡").amountCents, 2850)
    }

    func testSpacedOCRText() {
        let receipt = parse("""
        支 付 成 功
        ¥ 2 8 . 5 0
        星 巴 克
        """)
        XCTAssertEqual(receipt.amountCents, 2850)
        XCTAssertEqual(receipt.merchant, "星巴克")
        XCTAssertEqual(receipt.category, .food)
    }

    func testMerchantBeforeAmount() {
        let receipt = parse("""
        滴滴出行
        支付成功
        ¥36.80
        """)
        XCTAssertEqual(receipt.amountCents, 3680)
        XCTAssertEqual(receipt.merchant, "滴滴出行")
        XCTAssertEqual(receipt.category, .transport)
    }

    func testTransferIncome() {
        let receipt = parse("""
        微信转账
        已收款
        +200.00
        张三
        """)
        XCTAssertEqual(receipt.amountCents, 20000)
        XCTAssertEqual(receipt.direction, .income)
        XCTAssertEqual(receipt.category, .transfer)
        XCTAssertEqual(receipt.merchant, "张三")
    }

    func testMonthDayWithoutYearRollsBackWhenTooFarAhead() {
        let january = shanghai(2026, 1, 15, 9, 0)
        let receipt = ReceiptParser.parse(text: "收款成功\n¥50.00\n12月20日 08:00", now: january)
        XCTAssertEqual(receipt.direction, .income)
        assertDate(receipt.occurredAt, 2025, 12, 20, 8, 0, 0)
    }

    func testEmptyTextHasNoAmount() {
        let receipt = parse("   \n")
        XCTAssertNil(receipt.amountCents)
        XCTAssertEqual(receipt.direction, .expense)
        XCTAssertEqual(receipt.category, .other)
        XCTAssertEqual(receipt.merchant, "")
    }

    func testMoneyParsing() {
        XCTAssertEqual(Money.cents(from: "28.5"), 2850)
        XCTAssertEqual(Money.cents(from: "28"), 2800)
        XCTAssertEqual(Money.cents(from: "¥1,280.50"), 128050)
        XCTAssertEqual(Money.cents(from: "28,50"), 2850)
        XCTAssertEqual(Money.cents(from: "28."), 2800)
        XCTAssertNil(Money.cents(from: ""))
        XCTAssertNil(Money.cents(from: "12.345"))
        XCTAssertNil(Money.cents(from: "-1"))
        XCTAssertNil(Money.cents(from: "abc"))
        XCTAssertEqual(Money.plain(cents: 2850), "28.50")
        XCTAssertEqual(Money.signedYuan(cents: 2850, direction: .expense), "-¥28.50")
        XCTAssertEqual(Money.signedYuan(cents: 500, direction: .income), "+¥5.00")
    }

    private func parse(_ text: String) -> ParsedReceipt {
        ReceiptParser.parse(text: text, now: now)
    }

    private func assertDate(
        _ date: Date?,
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let date else {
            XCTFail("missing date", file: file, line: line)
            return
        }
        let parts = LedgerCalendar.shanghai.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        XCTAssertEqual(parts.year, year, file: file, line: line)
        XCTAssertEqual(parts.month, month, file: file, line: line)
        XCTAssertEqual(parts.day, day, file: file, line: line)
        XCTAssertEqual(parts.hour, hour, file: file, line: line)
        XCTAssertEqual(parts.minute, minute, file: file, line: line)
        XCTAssertEqual(parts.second, second, file: file, line: line)
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
