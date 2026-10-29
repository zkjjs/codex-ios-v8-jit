import Foundation

public enum LedgerDirection: String, Codable, Equatable {
    case expense
    case income

    public var title: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        }
    }
}

public enum LedgerCategory: String, Codable, CaseIterable, Equatable {
    case food
    case transport
    case shopping
    case housing
    case entertainment
    case medical
    case transfer
    case income
    case other

    public var title: String {
        switch self {
        case .food: return "餐饮"
        case .transport: return "交通"
        case .shopping: return "购物"
        case .housing: return "居住"
        case .entertainment: return "娱乐"
        case .medical: return "医疗"
        case .transfer: return "转账"
        case .income: return "收入"
        case .other: return "其他"
        }
    }

    public var symbol: String {
        switch self {
        case .food: return "fork.knife"
        case .transport: return "tram"
        case .shopping: return "bag"
        case .housing: return "house"
        case .entertainment: return "film"
        case .medical: return "cross.case"
        case .transfer: return "arrow.left.arrow.right"
        case .income: return "arrow.down.left"
        case .other: return "circle.grid.2x2"
        }
    }
}

public struct LedgerEntry: Codable, Identifiable, Equatable {
    public var id: UUID
    public var amountCents: Int
    public var direction: LedgerDirection
    public var merchant: String
    public var category: LedgerCategory
    public var occurredAt: Date
    public var paymentMethod: String
    public var note: String
    public var rawText: String
    public var imageFilename: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        amountCents: Int,
        direction: LedgerDirection,
        merchant: String,
        category: LedgerCategory,
        occurredAt: Date,
        paymentMethod: String = "",
        note: String = "",
        rawText: String = "",
        imageFilename: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.amountCents = amountCents
        self.direction = direction
        self.merchant = merchant
        self.category = category
        self.occurredAt = occurredAt
        self.paymentMethod = paymentMethod
        self.note = note
        self.rawText = rawText
        self.imageFilename = imageFilename
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ParsedReceipt: Equatable {
    public var amountCents: Int?
    public var direction: LedgerDirection
    public var merchant: String
    public var category: LedgerCategory
    public var occurredAt: Date?
    public var paymentMethod: String
    public var note: String
    public var rawText: String

    public init(
        amountCents: Int?,
        direction: LedgerDirection,
        merchant: String,
        category: LedgerCategory,
        occurredAt: Date?,
        paymentMethod: String,
        note: String,
        rawText: String
    ) {
        self.amountCents = amountCents
        self.direction = direction
        self.merchant = merchant
        self.category = category
        self.occurredAt = occurredAt
        self.paymentMethod = paymentMethod
        self.note = note
        self.rawText = rawText
    }

    public var recognizedAmount: Bool { amountCents != nil }
}

public struct CategoryTotal: Equatable {
    public var category: LedgerCategory
    public var amountCents: Int

    public init(category: LedgerCategory, amountCents: Int) {
        self.category = category
        self.amountCents = amountCents
    }
}

public struct MonthSummary: Equatable {
    public var expenseCents: Int
    public var incomeCents: Int
    public var categoryTotals: [CategoryTotal]

    public init(expenseCents: Int, incomeCents: Int, categoryTotals: [CategoryTotal]) {
        self.expenseCents = expenseCents
        self.incomeCents = incomeCents
        self.categoryTotals = categoryTotals
    }

    public var balanceCents: Int { incomeCents - expenseCents }
}

public enum LedgerCalendar {
    public static var shanghai: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .gmt
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }
}

public enum LedgerStoreError: Error, Equatable {
    case unreadable
    case invalidAmount
    case missingEntry
}
