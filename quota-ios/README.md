# Codex 额度 · iOS

SwiftUI App + 黑白小组件，只查询服务器上**已经登录**的 Codex 账号。iOS 16+ 可用，iOS 26 使用原生 Liquid Glass。后端不会调用模型、消耗推理额度或兑换重置券。

## 下载和自行签名

在本仓库 Actions 中打开 **Build Codex Quota IPA** 的成功记录，下载 `CodexQuota-unsigned-IPA` 并解压。使用自己的签名工具签名 `CodexQuota-unsigned.ipa`，保留 `PlugIns/CodexQuotaWidget.appex` 并同时签名扩展。App 的 bundle ID 为 `com.zkjjs.codexquota`，扩展为 `com.zkjjs.codexquota.widget`。

只有主 App 被签名、扩展被删除或扩展签名失败时，小组件不会显示。不要把“构建成功”等同于“任意签名工具都支持全部 entitlement”。IPA 本身不包含 Apple 证书、服务器查询码或 OpenAI 凭据。

## 连接服务器

1. 打开 App → 配对服务器。
2. 默认地址为 `https://cfinal.com/codex-quota`，填写部署时生成的**只读查询码**。
3. 点击“连接并读取额度”。主界面显示实际额度窗口、剩余百分比、当地时区重置时间、倒计时及最后更新时间。
4. 长按桌面，添加“Codex · 黑色”或“Codex · 白色”，支持小号和中号。

查询码是读取服务器账号额度的凭证，请私下保存。它不是 OpenAI 的 access token。

## 小组件签名兼容

- 签名支持 App Groups 时，两个 target 都保留 `group.com.zkjjs.codexquota`，App 配对后小组件自动读取配置。自有开发者账号应为自己的 bundle ID 创建对应 App Group，并同时修改 `SharedStore.group` 和 `project.yml`。
- 签名工具重写 App Group 名称时，必须让源码 group 与实际 entitlement 一致，否则不能自动共享。
- iOS 17+ 不支持 App Groups 的签名也可使用：长按小组件 → 编辑小组件，填写服务器地址和只读查询码。两种颜色的小组件分别配置，查询码只由 WidgetKit 保存在本机配置中。
- iOS 16 的小组件需要有效的共享 App Group，不能通过 iOS 17 的编辑配置兜底。
- 断开 App 不会自动删除手动填写的小组件查询码；请移除对应小组件或清空其配置。轮换服务端查询码可以使旧配置全部失效。

小组件按系统调度尝试约 15 分钟更新，系统可能推迟刷新；倒计时由系统绘制。额度过期后显示“等待额度更新”，不会把额度推测为 100%。失败时旧数据会保留原始时间并显示待更新。

App 使用原生液态玻璃，小组件适配系统桌面的透明/着色渲染。全彩模式下分别是黑、白主题；系统透明/着色模式可以接管背景颜色。

## 本地编译（Mac / Xcode 26+）

```bash
brew install xcodegen
xcodegen generate --spec quota-ios/project.yml
xcodebuild -project quota-ios/CodexQuota.xcodeproj -scheme CodexQuota \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath quota-ios/build-device CODE_SIGNING_ALLOWED=NO build
bash quota-ios/scripts/package-ipa.sh \
  quota-ios/build-device/Build/Products/Release-iphoneos/CodexQuota.app quota-ios/out
```

工作流会选择 runner 上已安装的 Xcode 26+，编译真机产物，在 iPhone 模拟器运行模型测试，再打包未签名 IPA。Linux 主机不能执行 Xcode 编译。

## 后端部署

后端仅依赖 Python 3 标准库以及已登录的 `codex` CLI。应由有权访问既有 Codex 认证目录的账号运行；不要从其他账号复制或导出 OAuth 凭据。

```bash
python3 -m unittest discover -s quota-ios/backend/tests -v
sudo install -d -m 700 /opt/codex-quota
sudo install -m 600 quota-ios/backend/quota_service.py /opt/codex-quota/quota_service.py
```

在 `/etc/codex-quota.env` 私下设置至少 32 字符的随机 `QUOTA_ACCESS_CODE`，权限设为 `0600`。可选设置 `CODEX_BIN` 指向 CLI，或者设置 `CODEX_HOME` 选择已经登录的认证目录；不要把值提交到 Git。现有服务器使用 `backend/codex-quota.service`，只监听 `127.0.0.1:18427`。

在既有 HTTPS server 中新增路由，不替换其他业务：

```nginx
location ^~ /codex-quota/ {
    proxy_pass http://127.0.0.1:18427/;
    proxy_set_header Host $host;
    proxy_set_header Authorization $http_authorization;
    proxy_read_timeout 40s;
    access_log off;
}
```

`GET /health` 只返回进程健康状态；`GET /v1/quota` 需要 `Authorization: Bearer <查询码>`，未经授权返回 401。所有响应禁止缓存。服务端缓存 60 秒以避免多台设备重复唤起 Codex。首次查询失败返回 503；存在历史结果则返回 `stale: true`，保留原始 `updatedAt`。`/health` 不代表上游 Codex 一定可用。

API 只返回套餐、额度窗口、百分比、重置时间和数据更新时间，过滤账号 ID、OAuth 凭据及重置券 ID。TLS 必须有效。App 不跟随 HTTP 重定向转发查询码。

## 测试与限制

- Python 测试覆盖真实协议结构、空值和非法数据、缓存、授权及故障响应。
- XCTest 覆盖数据解码、缺失重置时间、过期窗口、数据时效和 HTTPS 配置校验。
- 真机签名、添加小组件和外观验收需要在实际设备上完成；未实测前不声称通过。
- 原仓库的 Codex/JIT 构建与测试保持不变，本产品位于独立目录及工作流。
