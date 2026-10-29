import SwiftUI
import LedgerCore

struct TransactionDraft: Identifiable {
    var id: UUID
    var amountText: String
    var direction: LedgerDirection
    var merchant: String
    var category: LedgerCategory
    var occurredAt: Date
    var paymentMethod: String
    var note: String
    var rawText: String
    var imageFilename: String?
    var pendingImageData: Data?
    var pendingFile: URL?
    var createdAt: Date
    var isNew: Bool

    init(parsed: ParsedReceipt, imageData: Data?, pendingFile: URL?, now: Date) {
        id = UUID()
        amountText = parsed.amountCents.map { Money.plain(cents: $0) } ?? ""
        direction = parsed.direction
        merchant = parsed.merchant
        category = parsed.category
        occurredAt = parsed.occurredAt ?? now
        paymentMethod = parsed.paymentMethod
        note = parsed.note
        rawText = parsed.rawText
        imageFilename = nil
        pendingImageData = imageData
        pendingFile = pendingFile
        createdAt = now
        isNew = true
    }

    init(entry: LedgerEntry) {
        id = entry.id
        amountText = Money.plain(cents: entry.amountCents)
        direction = entry.direction
        merchant = entry.merchant
        category = entry.category
        occurredAt = entry.occurredAt
        paymentMethod = entry.paymentMethod
        note = entry.note
        rawText = entry.rawText
        imageFilename = entry.imageFilename
        pendingImageData = nil
        pendingFile = nil
        createdAt = entry.createdAt
        isNew = false
    }

    static func manual(now: Date) -> TransactionDraft {
        TransactionDraft(
            parsed: ParsedReceipt(
                amountCents: nil,
                direction: .expense,
                merchant: "",
                category: .other,
                occurredAt: now,
                paymentMethod: "",
                note: "",
                rawText: ""
            ),
            imageData: nil,
            pendingFile: nil,
            now: now
        )
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var transactions: [LedgerEntry] = []
    @Published var visibleMonth = Date()
    @Published var editor: TransactionDraft?
    @Published var isReading = false
    @Published var alertMessage: String?
    @Published private(set) var pendingCount = 0

    private var store: LedgerStore?
    private var images: ReceiptImageStore?
    private var pendingFileForEditor: URL?

    init() {
        do {
            let base = try ReceiptImageStore.applicationBase()
            images = ReceiptImageStore(directory: base.appendingPathComponent("images", isDirectory: true))
            store = try LedgerStore(fileURL: base.appendingPathComponent("ledger.json"))
            transactions = store?.entries ?? []
        } catch {
            alertMessage = "账本打不开。"
        }
        refreshPendingCount()
    }

    func entries(in month: Date) -> [LedgerEntry] {
        store?.entries(inMonthOf: month) ?? []
    }

    func summary(for month: Date) -> MonthSummary {
        store?.summary(for: month) ?? MonthSummary(expenseCents: 0, incomeCents: 0, categoryTotals: [])
    }

    func beginManualEntry() {
        pendingFileForEditor = nil
        editor = .manual(now: Date())
    }

    func beginEdit(_ entry: LedgerEntry) {
        pendingFileForEditor = nil
        editor = TransactionDraft(entry: entry)
    }

    func importImage(_ data: Data, pendingFile: URL? = nil) {
        guard !isReading else { return }
        guard !data.isEmpty else {
            alertMessage = "这张截图是空的。"
            return
        }
        if let previous = editor?.pendingFile, previous != pendingFile {
            try? FileManager.default.removeItem(at: previous)
        }
        isReading = true
        Task {
            let lines = await OCRService.recognizeLines(in: data)
            let parsed = ReceiptParser.parse(lines: lines)
            isReading = false
            pendingFileForEditor = pendingFile
            editor = TransactionDraft(parsed: parsed, imageData: data, pendingFile: pendingFile, now: Date())
            refreshPendingCount()
        }
    }

    func consumePendingImports() {
        refreshPendingCount()
        guard editor == nil, !isReading else { return }
        guard let file = AppGroup.pendingFiles().first else { return }
        guard let data = try? Data(contentsOf: file), !data.isEmpty else {
            try? FileManager.default.removeItem(at: file)
            consumePendingImports()
            return
        }
        importImage(data, pendingFile: file)
    }

    func save(_ draft: TransactionDraft) {
        guard let store, let images else {
            alertMessage = "账本打不开。"
            return
        }
        guard let cents = Money.cents(from: draft.amountText) else {
            alertMessage = "请填写金额。"
            return
        }
        var filename = draft.imageFilename
        if let data = draft.pendingImageData, !data.isEmpty {
            do {
                if let oldName = draft.imageFilename {
                    images.delete(oldName)
                }
                filename = try images.saveJPEG(data, id: draft.id)
            } catch {
                alertMessage = "截图没有保存下来。"
                return
            }
        }
        let entry = LedgerEntry(
            id: draft.id,
            amountCents: cents,
            direction: draft.direction,
            merchant: draft.merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            category: draft.category,
            occurredAt: draft.occurredAt,
            paymentMethod: draft.paymentMethod.trimmingCharacters(in: .whitespacesAndNewlines),
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
            rawText: draft.rawText,
            imageFilename: filename,
            createdAt: draft.createdAt,
            updatedAt: Date()
        )
        do {
            if draft.isNew {
                try store.add(entry)
            } else {
                try store.update(entry)
            }
        } catch {
            alertMessage = "这笔账没有写入。"
            return
        }
        if let file = draft.pendingFile {
            try? FileManager.default.removeItem(at: file)
            if pendingFileForEditor == file {
                pendingFileForEditor = nil
            }
        }
        transactions = store.entries
        visibleMonth = draft.occurredAt
        editor = nil
    }

    func delete(id: UUID) {
        guard let store else { return }
        let filename = transactions.first { $0.id == id }?.imageFilename
        do {
            try store.delete(id: id)
            if let filename {
                images?.delete(filename)
            }
            transactions = store.entries
        } catch {
            alertMessage = "没有删掉这笔账。"
        }
    }

    func editorDismissed() {
        if let file = pendingFileForEditor {
            try? FileManager.default.removeItem(at: file)
            pendingFileForEditor = nil
        }
        refreshPendingCount()
        consumePendingImports()
    }

    func imageData(named filename: String) -> Data? {
        images?.data(named: filename)
    }

    private func refreshPendingCount() {
        pendingCount = AppGroup.pendingFiles().count
    }
}
