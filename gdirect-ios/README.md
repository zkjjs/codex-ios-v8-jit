# gdirect iOS

面向 iOS 27 的 Google Drive 下载客户端。SwiftUI 界面、Rust 解析与网络核心、静态 libaria2 直连引擎。

**当前状态：v0.2.0 已通过 Xcode 27.1 Release Archive 编译、12 项 Swift 辅助测试及 9 项 iOS 模拟器测试，生成带图标的未签名 IPA。Google 登录仍缺真实 iOS OAuth 客户端 ID；后台下载与端点可用性仍需真机网络验收。**

[下载本次 IPA](https://github.com/zkjjs/codex-ios-v8-jit/actions/runs/40178803897/artifacts/12593965083) · [构建记录](https://github.com/zkjjs/codex-ios-v8-jit/actions/runs/40178803897)

## 编译 IPA

需要安装匹配 iOS 27 SDK 的 Xcode、Rust、XcodeGen，以及 Apple Silicon Mac（脚本目前输出 arm64 真机和 arm64 模拟器切片）。

```bash
brew install xcodegen
./scripts/build-unsigned-ipa.sh
```

输出：`build/GDirect-unsigned.ipa`。这是未签名安装包，安装前需签名。

已准备 `.github/workflows/build-ios.yml`，可在具有 iOS 27 SDK 的 GitHub macOS runner 上手动构建并下载 artifact；本次已在 `zkjjs/codex-ios-v8-jit` 的独立分支 `codex/ios-build/gdirect-20261025` 完成云端构建；源码位于 `gdirect-ios/`，默认分支保持原样。

要直接导出签名 IPA，设置 `GDIRECT_TEAM_ID`、`GDIRECT_EXPORT_OPTIONS`（Xcode 导出配置 plist 路径），再执行 `./scripts/archive-ios.sh`。签名证书及 provisioning profile 需要在 Mac 上配置。

Google 登录还需在 `ios/Config.local.xcconfig` 配置自己的 iOS OAuth 客户端：

```text
GDIRECT_BUNDLE_ID = your.bundle.id
GOOGLE_CLIENT_ID = your-client-id.apps.googleusercontent.com
GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.your-client-id
```

同时在 Google Cloud 项目启用 Drive API，配置相同 Bundle ID 的 iOS OAuth 客户端，并授予测试账户访问。未配置时可使用公开分享链接下载。

## 后台下载

- 系统模式使用后台 URLSession，交给系统管理，不需要 App 保持前台。
- 固定 IP 模式复用上游 aria2 路由补丁，使用 BGContinuedProcessingTask；系统提供进度及取消界面。
- 系统模式使用正常域名网络，不替代固定 IP 直连。后台会话由系统自动处理 HTTP 重定向；完成时会检查最终来源。严格逐次重定向白名单在原生直连引擎内执行。
- 系统暂停/取消或进程退出后保留任务记录与引擎专属断点；恢复需再次获得系统执行机会。
- 完成提醒使用本地通知；拒绝通知权限不影响下载。实时活动不是保活手段。

详见 [实施计划](docs/superpowers/plans/2026-10-25-ios-background-download.md) 和 [验收记录](docs/verification/ios27-acceptance.md)。

## 本地核心验证

```bash
cargo test --manifest-path core/Cargo.toml --locked
cargo build --manifest-path core/Cargo.toml --release --locked
```

Linux 默认构建不含 aria2 原生引擎；iOS 构建脚本显式开启 `aria2` feature。Linux 核心测试成功不代表 iOS App 或后台下载已验证。

## 移植范围

已提取链接/resourceKey/确认页解析，新增 Rust C ABI，移植目录分页、元数据、IP 探测与原生下载桥。v0.2.0 新增下载速度/ETA、本地下载文件删除、默认关闭的剪贴板链接检测与点击粘贴、IP 文本/JSON 导入、逐项探测结果与缓存、默认/深色/单色图标。Google 登录增加缺失配置、回调及重签名 Bundle ID 检查和立即可见的错误反馈。

上传、File Provider、网络变更后自动端点失效、完整账户切换、目录离线缓存及更多异常恢复仍待后续完善。12 项 Swift 辅助测试、9 项 iOS 存储/恢复测试已在 GitHub Actions 通过。

上游：https://github.com/mizorewww/gdirect ，基线 `d260f5d`。许可证 GPL-2.0-or-later，见 LICENSE 和 THIRD_PARTY_NOTICES.md。
