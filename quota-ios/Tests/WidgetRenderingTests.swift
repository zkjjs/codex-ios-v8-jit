import SwiftUI
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
    func testRealQuotaDoesNotRemainAnInheritedGrayPlaceholder() async throws {
        let entry = QuotaEntry(date: Date(timeIntervalSince1970: 100), snapshot: snapshot, message: nil)
        for dark in [false, true] {
            let clear = try render(entry, dark: dark, redacted: false)
            let inheritedPlaceholder = try render(entry, dark: dark, redacted: true)
            attach(clear, name: dark ? "Widget-Black-Expected" : "Widget-White-Expected")
            attach(inheritedPlaceholder, name: dark ? "Widget-Black-Actual" : "Widget-White-Actual")
            XCTAssertEqual(clear.pngData(), inheritedPlaceholder.pngData(),
                           "A real timeline entry must display quota instead of inherited placeholder blocks")
        }
    }

    @MainActor
    func testConnectionErrorRemainsReadableInsteadOfGrayBlocks() async throws {
        let entry = QuotaEntry(date: Date(timeIntervalSince1970: 100), snapshot: nil,
                               message: "查询码不正确，请编辑小组件")
        let clear = try render(entry, dark: false, redacted: false)
        let inheritedPlaceholder = try render(entry, dark: false, redacted: true)
        attach(inheritedPlaceholder, name: "Widget-Connection-Error")
        XCTAssertEqual(clear.pngData(), inheritedPlaceholder.pngData(),
                       "A failed query must show its status, not a permanent gray placeholder")
    }

    @MainActor
    func testGalleryPlaceholderStillRedactsExamplePercentages() async throws {
        let entry = QuotaEntry(date: Date(timeIntervalSince1970: 100), snapshot: snapshot,
                               message: nil, preview: true)
        let clear = try render(entry, dark: false, redacted: false)
        let placeholder = try render(entry, dark: false, redacted: true)
        XCTAssertNotEqual(clear.pngData(), placeholder.pngData(),
                          "Gallery placeholder data must not be exposed as a real quota")
    }

    @MainActor
    private func render(_ entry: QuotaEntry, dark: Bool, redacted: Bool) throws -> UIImage {
        let view = QuotaWidgetContent(entry: entry, dark: dark)
            .environment(\.widgetFamily, .systemSmall)
            .environment(\.redactionReasons, redacted ? .placeholder : [])
            .frame(width: 140, height: 140).padding(16)
            .background(dark ? Color(white: 0.07) : Color(white: 0.98))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return try XCTUnwrap(renderer.uiImage)
    }

    private func attach(_ image: UIImage, name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
