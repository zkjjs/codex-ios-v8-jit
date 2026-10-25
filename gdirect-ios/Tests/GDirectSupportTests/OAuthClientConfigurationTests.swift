import XCTest
@testable import GDirectSupport

final class OAuthClientConfigurationTests: XCTestCase {
    let client = "123456789-example.apps.googleusercontent.com"
    let scheme = "com.googleusercontent.apps.123456789-example"

    func testPlaceholderDoesNotPretendLoginIsAvailable() {
        let config = OAuthClientConfiguration(clientID: "configure-ios-oauth.apps.googleusercontent.com", expectedBundleID: "org.gdirect.ios", actualBundleID: "org.gdirect.ios", callbackSchemes: [])
        XCTAssertEqual(config.issue, .missingClientID)
    }
    func testReSignedBundleMismatchIsDetectedBeforeLaunchingGoogleSDK() {
        let config = OAuthClientConfiguration(clientID: client, expectedBundleID: "org.gdirect.ios", actualBundleID: "changed.by.signer", callbackSchemes: [scheme])
        XCTAssertEqual(config.issue, .bundleMismatch)
    }
    func testMissingCallbackSchemeIsReportedBeforeSDKException() {
        let config = OAuthClientConfiguration(clientID: client, expectedBundleID: "org.gdirect.ios", actualBundleID: "org.gdirect.ios", callbackSchemes: ["wrong"])
        XCTAssertEqual(config.issue, .missingCallbackScheme)
    }
    func testValidConfigurationUsesExactReversedClientID() {
        let config = OAuthClientConfiguration(clientID: client, expectedBundleID: "org.gdirect.ios", actualBundleID: "org.gdirect.ios", callbackSchemes: [scheme])
        XCTAssertNil(config.issue)
        XCTAssertEqual(config.reversedClientID, scheme)
    }
}
