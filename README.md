# Codex 额度

中文 iPhone 应用：ChatGPT 账号设备码 OAuth、Codex 剩余额度、原生 Liquid Glass、桌面小组件和重置倒计时。首版不需要自建服务，不发送推理请求。

## 安装

在 Actions 构建产物中下载 `CodexQuota-unsigned.ipa`，通过支持扩展和 App Groups 的签名方式签名。这个文件没有 Apple 签名，不能直接点开安装。

小组件要求：主 App 和 `CodexQuotaWidget.appex` 同团队签名，保留相同 App Group 和共享 Keychain 权限。若重签工具改了 Bundle ID，应同时映射两个 Info.plist 中的 `AppGroupIdentifier`、`SharedKeychainGroup`，以及两份签名权限中的对应值。仅能保留主 App 的签名方式无法完整支持本项目。

1. 打开「Codex 额度」，点「使用 ChatGPT 登录」。
2. 在应用显示的授权码处复制代码，点「前往 OpenAI 授权」。账号密码只在官方网页输入。
3. 完成授权后返回应用。设备码不可用时，在 ChatGPT 安全设置中开启设备码授权。
4. 确认取得真实额度，再长按桌面 → 编辑 → 添加小组件 → Codex 额度。

## 数据语义

- `used_percent` 转换为剩余百分比，限制到 0–100；缺失数据不伪装成零或满额。
- 额度周期长度以服务返回为准，包括短周期、周周期及单窗口账号。
- 使用服务端 Unix 时间显示当地重置日期与倒计时。到点后显示待更新，不自动补满额度。
- 主应用负责刷新令牌；小组件仅使用当前访问令牌。过期时打开主应用续期。
- 小组件申请约 30 分钟或重置后刷新，实际执行由 iOS 决定。网络失败保留旧快照并显示状态。
- 退出登录清除本机凭证和快照。配置不支持共享权限时，主应用显示明确提示。

## 构建

需要 macOS、Xcode 26+、XcodeGen。Swift 5 language mode，最低 iOS 26。

```bash
swift test
bash scripts/build.sh
```

脚本生成 Xcode 项目、编译 iPhoneOS App 和 Widget Extension、验证 IPA 结构，再编译模拟器版本并在有可用运行时的情况下截图。产物位于 `dist/`。可在 Xcode 中设置自己的 Team、Bundle ID、`APP_GROUP_ID` 与共享钥匙串组，进行正式签名。

## 验证边界

自动化测试和编译不能代替本人账号授权及真实设备签名验证。OAuth 参考官方开源 Codex 的设备码流程，复用其公开客户端标识；不是已经获得第三方 OAuth 客户端注册的承诺。直接额度后端属于内部接口，未来可能变化、限制第三方访问或要求额外验证；届时显示实际错误，不生成虚假额度。应用不收集、不代理密码或令牌。

依据：
- https://learn.chatgpt.com/docs/auth
- https://learn.chatgpt.com/docs/app-server
- https://github.com/openai/codex/blob/main/codex-rs/login/src/device_code_auth.rs
- https://github.com/openai/codex/blob/main/codex-rs/login/src/auth/manager.rs
- https://github.com/openai/codex/blob/main/codex-rs/backend-client/src/client/rate_limit_resets.rs
