# 截屏记账

一个 iOS 16 记账应用。你从相册选一张支付截图，或在系统分享里把它交给「截屏记账」。手机上的文字识别会填好金额、商户、时间和支付方式。你核对后再保存。账和图片只留在这台手机上。

支持微信、支付宝账单和银行扣款短信这类版式。认不出金额时，确认页会让你手填。

## 隐私

- 不会在后台截屏，也不会读取其他 App 的数据。
- 识别用系统 Vision，不联网。
- 不使用沙箱外权限。分享扩展和主 App 只用 App Group 交接你主动分享的那张图。

## 在 Mac 上导出 IPA

这台构建环境没有 Xcode，不能直接产出已签名的 IPA。在 Mac 上：

1. 用 Xcode 16 打开 `ScreenshotLedger.xcodeproj`。
2. 给 **ScreenshotLedger** 和 **ShareExtension** 都选中你的 Team。两个目标都要带上 App Group `group.dev.snapledger.shared`。
3. 连接 iPhone，直接 Run。或选 Product → Archive，再 Distribute App → Debugging，导出 IPA。
4. 也可以运行：

```sh
DEVELOPMENT_TEAM=你的TeamID sh scripts/archive-ipa.sh
```

个人免费签名如果签不上 App Group，可以先从两个 entitlements 里去掉 `com.apple.security.application-groups`。相册导入仍然可用，系统分享里的入口需要 App Group。

最低系统是 iOS 16。

## 测试解析和账本

金额解析和本地账本不依赖手机：

```sh
cd LedgerCore
swift test
```
