import XCTest
@testable import GDirectSupport

final class EndpointImportParserTests: XCTestCase {
    func testImportsCommentedTextAndDeduplicatesCandidates() throws {
        let ips = try EndpointImportParser.parse("# exported candidates\n183.56.143.147\n8.8.8.8 # candidate\n183.56.143.147")
        XCTAssertEqual(ips, ["183.56.143.147", "8.8.8.8"])
    }
    func testImportsDesktopStyleJSONEndpointRecords() throws {
        XCTAssertEqual(try EndpointImportParser.parse(#"{"endpoints":[{"ip":"8.8.8.8","latency_ms":20},"2001:4860:4860::8888"]}"#), ["8.8.8.8", "2001:4860:4860::8888"])
    }
    func testRejectsURLsAndOversizedListsBeforeProbing() {
        XCTAssertThrowsError(try EndpointImportParser.parse("https://google.com"))
        XCTAssertThrowsError(try EndpointImportParser.parse((0..<257).map { "8.8.8.\($0)" }.joined(separator: "\n")))
    }
}
