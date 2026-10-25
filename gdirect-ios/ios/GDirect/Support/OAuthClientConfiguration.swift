import Foundation

struct OAuthClientConfiguration {
    enum Issue: Equatable { case missingClientID, bundleMismatch, missingCallbackScheme }
    let clientID: String
    let expectedBundleID: String
    let actualBundleID: String
    let callbackSchemes: [String]

    var reversedClientID: String { clientID.split(separator: ".").reversed().joined(separator: ".") }
    var issue: Issue? {
        guard clientID.range(of: #"^[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$"#, options: .regularExpression) != nil else { return .missingClientID }
        guard !expectedBundleID.isEmpty, actualBundleID == expectedBundleID else { return .bundleMismatch }
        guard callbackSchemes.contains(reversedClientID) else { return .missingCallbackScheme }
        return nil
    }
}
