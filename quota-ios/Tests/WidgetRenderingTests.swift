import SwiftUI
import UIKit
import Vision
import WidgetKit
import XCTest
@testable import CodexQuota

final class WidgetRenderingTests: XCTestCase {
    private var snapshot: QuotaSnapshot {
        QuotaSnapshot(version: 1, updatedAt: 100, stale: false, plan: "plus", windows: [
            QuotaWindow(id: "primary", title: "5 小时额度", usedPercent: 69,
                        remainingPercent: 31, windowMinutes: 300, resetsAt: nil),
            QuotaWindow(id: "secondary", title: "每周额度", usedPercent: 40,
                        remainingPercent: 60, windowMinutes: 10080, resetsAt: nil)
        ])
    }

    @MainActor
    func testBlackAndWhiteWidgetsRenderReadableQuota() async throws {
        let entry = QuotaEntry(date: Date(timeIntervalSince1970: 100), snapshot: snapshot, message: nil)
        for dark in [false, true] {
            let image = try render(entry, dark: dark)
            attach(image, name: dark ? "Widget-Black" : "Widget-White")
            let text = try recognizedText(image)
            XCTAssertTrue(text.contains("31%"), "Primary quota is unreadable: \(text)")
            XCTAssertTrue(text.contains("60%"), "Weekly quota is unreadable: \(text)")
        }
    }

    @MainActor
    func testConnectionErrorIsReadable() async throws {
        let entry = QuotaEntry(date: Date(timeIntervalSince1970: 100), snapshot: nil,
                               message: "CHECK ACCESS CODE")
        let image = try render(entry, dark: false)
        attach(image, name: "Widget-Connection-Error")
        XCTAssertTrue(try recognizedText(image).contains("CHECKACCESSCODE"))
    }

    @MainActor
    func testSystemPlaceholderDoesNotExposeExamplePercentages() async throws {
        let entry = QuotaEntry(date: Date(timeIntervalSince1970: 100), snapshot: snapshot,
                               message: nil, preview: true)
        let image = try render(entry, dark: false, redacted: true)
        let text = try recognizedText(image)
        XCTAssertFalse(text.contains("31%"))
        XCTAssertFalse(text.contains("60%"))
    }

    @MainActor
    func testSnapshotReturnsImmediateLoadingStatusWithoutExampleData() async {
        let connection = ServerConnection(server: "https://example.com", accessCode: "private-code")
        let entry = WidgetLoader.initialEntry(connection: connection, manual: true)
        XCTAssertNil(entry.snapshot)
        XCTAssertFalse(entry.preview)
        XCTAssertEqual(entry.message, "正在读取服务器额度…")
    }

    @MainActor
    func testAuthenticationFailureReturnsVisibleStatusNotPreview() async {
        let connection = ServerConnection(server: "https://example.com", accessCode: "private-code")
        let entry = await WidgetLoader.entry(connection: connection, manual: true,
                                            fetch: { _ in throw QuotaError.unauthorized })
        XCTAssertNil(entry.snapshot)
        XCTAssertFalse(entry.preview)
        XCTAssertEqual(entry.message, "查询码不正确或已失效，请重新配对服务器。")
        XCTAssertFalse(entry.message?.contains("private-code") ?? true)
    }

    @MainActor
    func testSuccessfulManualTimelineContainsFetchedQuota() async {
        let connection = ServerConnection(server: "https://example.com", accessCode: "private-code")
        let expected = snapshot
        let entry = await WidgetLoader.entry(connection: connection, manual: true, fetch: { _ in expected })
        XCTAssertEqual(entry.snapshot?.windows.first?.remainingPercent, 31)
        XCTAssertNil(entry.message)
        XCTAssertFalse(entry.preview)
        XCTAssertFalse(WidgetLoader.timeline(entry).entries.isEmpty)
    }

    @MainActor
    private func render(_ entry: QuotaEntry, dark: Bool, redacted: Bool = false) throws -> UIImage {
        let view = QuotaWidgetContent(entry: entry, dark: dark)
            .environment(\.widgetFamily, .systemSmall)
            .environment(\.redactionReasons, redacted ? .placeholder : [])
            .frame(width: 140, height: 140).padding(16)
            .background(dark ? Color(white: 0.07) : Color(white: 0.98))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return try XCTUnwrap(renderer.uiImage)
    }

    private func recognizedText(_ image: UIImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        let cgImage = try XCTUnwrap(image.cgImage)
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined().uppercased().filter { !$0.isWhitespace }
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
