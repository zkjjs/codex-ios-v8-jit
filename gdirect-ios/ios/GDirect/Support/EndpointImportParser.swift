import Foundation

enum EndpointImportParser {
    static func parse(_ text: String) throws -> [String] {
        guard text.utf8.count <= 1_048_576 else { throw ImportError.tooLarge }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var values: [String]
        if trimmed.hasPrefix("[") || trimmed.hasPrefix("{") {
            let json = try JSONSerialization.jsonObject(with: Data(trimmed.utf8))
            let array: [Any]?
            if let object = json as? [String: Any] { array = (object["endpoints"] ?? object["candidates"]) as? [Any] }
            else { array = json as? [Any] }
            guard let array else { throw ImportError.invalidFormat }
            values = try array.map {
                if let ip = $0 as? String { return ip }
                if let entry = $0 as? [String: Any], let ip = entry["ip"] as? String { return ip }
                throw ImportError.invalidFormat
            }
        } else {
            values = trimmed.components(separatedBy: .newlines).flatMap {
                ($0.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
                    .split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
            }
        }
        guard !values.isEmpty, values.count <= 256 else { throw ImportError.invalidCount }
        var seen = Set<String>()
        return try values.map { raw in
            let ip = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard ip.range(of: #"^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$|^[0-9A-Fa-f]*:[0-9A-Fa-f:]+$"#, options: .regularExpression) != nil else { throw ImportError.invalidFormat }
            return ip
        }.filter { seen.insert($0).inserted }
    }
    enum ImportError: LocalizedError {
        case tooLarge, invalidFormat, invalidCount
        var errorDescription: String? {
            switch self {
            case .tooLarge: "IP 列表不能超过 1 MiB。"
            case .invalidFormat: "请导入 IP 地址列表，支持每行一个 IP 的文本或 endpoints/candidates JSON。"
            case .invalidCount: "每次检测需要 1–256 个候选 IP。"
            }
        }
    }
}
