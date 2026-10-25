import Foundation
import AppIntents

@available(iOS 17.0, *)
enum WidgetConnectionMode: String, AppEnum {
    case app
    case manual

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "配置来源"
    static var caseDisplayRepresentations: [WidgetConnectionMode: DisplayRepresentation] = [
        .app: "使用 App 内已保存的连接",
        .manual: "手动输入服务器和查询码"
    ]
}

@available(iOS 17.0, *)
struct WidgetConnectionSelection {
    let connection: ServerConnection?
    let manual: Bool
    let error: String?

    static func resolve(mode: WidgetConnectionMode, server: String?, accessCode: String?,
                        sharedConnection: ServerConnection?) -> Self {
        if mode == .app {
            guard let sharedConnection else {
                return Self(connection: nil, manual: false,
                    error: "未读取到 App 配置，请打开 App 配对并确认共享配置可用")
            }
            return Self(connection: sharedConnection, manual: false, error: nil)
        }
        let code = accessCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let address = server?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !code.isEmpty else {
            return Self(connection: nil, manual: true, error: "手动模式：请填写查询码")
        }
        return Self(connection: ServerConnection(server: address.isEmpty ? ServerConnection.defaultServer : address,
                    accessCode: code), manual: true, error: nil)
    }
}
