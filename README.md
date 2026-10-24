# Codex 额度 1.1 — 日本服务器版

原生 SwiftUI Liquid Glass、Codex 账号额度、小号/中号 WidgetKit 小组件、下次重置时间和倒计时。

新版数据路径：`iPhone / Widget → 你的 HTTPS 服务器 → OpenAI`。服务端负责设备码 OAuth、续期及额度查询。手机仅持有访问服务器的配对信息，OpenAI 令牌不回传手机。

## 先部署，再配对

查看 [Server/README.md](Server/README.md)。下载并解压服务器安装包，在日本 Ubuntu 服务器上执行 `sudo bash install.sh 52.195.185.75`。安装是新服务，不修改 SSH、路由、防火墙或现有容器；检测到已有安装会停下，不自动覆盖。

在 AWS 安全组允许自己的手机访问 TCP 8765。将终端输出的配对 JSON 粘贴进 App → 设置 → 连接服务器，保存后再点 ChatGPT 登录。账号密码只在 OpenAI 官方网页输入。正常拿到额度后再添加桌面小组件。

## 签名

IPA 没有 Apple 签名，需签名安装。签名工具必须保留 `CodexQuotaWidget.appex`、App Groups、共享 Keychain，并映射 Info.plist 中的对应组标识。服务器模式无法替代 iOS 的签名权限。

## 网络信任

支持 IP 地址和自签证书。配对信息中的完整证书 SHA-256 指纹由你从服务器终端取得；应用按配置的地址、端口和指纹匹配服务器，并使用该证书作为显式信任锚，检查有效期和主机名；不接受任意证书，不跟随重定向，不允许 HTTP 明文地址。

为允许私有自签证书，App 和 Widget 的 ATS 配置使用自定义信任；BridgeClient 负责强制 HTTPS、TLS 1.2+、精确证书固定和主机名校验。不要增加未使用同等校验的通用网络入口。

## 构建与验证

macOS / Xcode 26+ / XcodeGen，最低 iOS 26，Swift 5 language mode：

```bash
python3 -m unittest discover -s Server/tests -v
swift test
bash scripts/build.sh
```

Swift 测试包含真实本机 HTTPS 服务的证书固定、错误证书和错误密钥检查。额度与重置逻辑保留此前的未知值、过期和限流测试。`CAPTURE_UI=1` 可生成模拟器画面。

服务器访问设备授权接口返回 200，只证明接口连通；真实账号授权、服务器部署、iPhone 实际签名权限和 WidgetKit 调度仍需在你的设备/服务器完成验证。当前开发环境无法 SSH 到日本服务器，不能把安装包准备完成称作已部署。
