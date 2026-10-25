import Foundation

struct DirectEndpoint: Identifiable, Codable {
    var id: String { ip }
    let ip: String
    var available: Bool
    let latencyMS: Int?
    let downloadVerified: Bool
    var error: String?
    let checkedAt: Date
}
