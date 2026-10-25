import SwiftUI
import UIKit

struct GoogleLoginHelpView: View {
    let configuration: OAuthClientConfiguration
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Google 登录需要应用自己的 iOS OAuth 客户端配置。本安装包尚未配置完成时，无法打开有效的 Google 授权。")
                    Text("如果你是普通使用者，请向安装包提供者索取已配置 Google 登录的版本。")
                }
                Section("构建此 App 时配置") {
                    Text("1. 在 Google Cloud 启用 Drive API，创建 iOS 类型的 OAuth 客户端。")
                    Text("2. Bundle ID 必须匹配下方的 App 标识；配置 OAuth 同意页面，并添加测试账户（若项目仍处于测试模式）。")
                    Text("3. 将客户端 ID 写入构建配置，再重新编译。无需提供客户端密钥。")
                    LabeledContent("当前 App 标识", value: configuration.actualBundleID).textSelection(.enabled)
                    Button("复制 App 标识") { UIPasteboard.general.string = configuration.actualBundleID }
                    Link("打开 Google Cloud 凭据页面", destination: URL(string: "https://console.cloud.google.com/apis/credentials")!)
                    Link("查看 Google 官方配置说明", destination: URL(string: "https://developers.google.com/identity/sign-in/ios/start-integrating")!)
                }
                Section { Text("重新签名时若修改 App 标识，也需要使用匹配的新 OAuth 配置；保持钥匙串权限才能保存登录凭据。") }
            }
            .navigationTitle("Google 登录配置")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
