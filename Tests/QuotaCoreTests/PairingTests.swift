import XCTest
@testable import QuotaCore
final class PairingTests: XCTestCase {
    func decode(_ url: String, pin: String = String(repeating: "a", count: 64)) throws -> PairingPayload {
        let data = try JSONSerialization.data(withJSONObject: ["server_url":url,"gateway_key":String(repeating:"k",count:48),"certificate_sha256":pin])
        return try JSONDecoder().decode(PairingPayload.self,from:data)
    }
    func testPinnedHTTPSIPAllowed() throws { XCTAssertEqual(try decode("https://52.195.185.75:8765").validatedURL().port,8765) }
    func testPlaintextNotAllowed() throws { XCTAssertThrowsError(try decode("http://example.com").validatedURL()) }
    func testUserInfoAndQueryNotAllowed() throws {
        XCTAssertThrowsError(try decode("https://key@example.com").validatedURL())
        XCTAssertThrowsError(try decode("https://example.com?secret=yes").validatedURL())
    }
    func testMalformedCertificatePinRejected() throws { XCTAssertThrowsError(try decode("https://example.com",pin:"invalid").validatedURL()) }
}
