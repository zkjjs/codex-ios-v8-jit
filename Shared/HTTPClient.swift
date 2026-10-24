import Foundation
import QuotaCore

struct ServiceError: LocalizedError {
    let status: Int
    let retryAt: Date?
    var errorDescription: String? {
        switch status {
        case 409: return "请先在服务器上完成账号登录。"
        case 401: return "登录已失效，请重新登录。"
        case 403: return "服务拒绝访问。请检查账号是否已开启设备码登录，或稍后更换可用网络重试。"
        case 404: return "当前授权方式或额度接口暂不可用。"
        case 429: return "请求过于频繁，已暂停刷新，稍后会重试。"
        default: return "服务暂时不可用（HTTP \(status)）。"
        }
    }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
