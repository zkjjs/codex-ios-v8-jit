# gdirect iOS IPA 客户端实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. 本文为规划交付，所有实施项尚未完成。

**Goal:** 在 iOS 27 上实现登录 Google Drive、浏览和下载，切后台和锁屏后能够继续下载，并显示进度及完成提醒。

**Architecture:** SwiftUI 客户端配合 Rust 核心及静态 libaria2。系统后台 URLSession 承担可使用正常域名网络的后台传输；固定 IP 直连使用 libaria2，并优先验证 BGContinuedProcessingTask 的持续后台执行能力。两种引擎共用持久化任务模型，不能假定两者的断点文件能够互换。

**Tech Stack:** Swift、SwiftUI、Foundation URLSession、BackgroundTasks、ActivityKit（按需）、UserNotifications、Keychain、Rust、SQLite、libaria2。

**Spec:** 本文包含需求基线；依据用户已明确的“后台下载优先”要求，以及上游 https://github.com/mizorewww/gdirect 提交 d260f5d 的源码检查。

## 需求基线与约束

- iOS 27 为首轮开发和真机验收目标；最低支持版本先设为 iOS 27。
- 首版包含登录、目录浏览、公开链接下载、已授权文件下载、Google 文档导出、下载任务及文件导出。
- 后台下载是首版验收条件，实时活动与通知只负责展示和提醒，不作为保活机制。
- 固定 IP 后台下载尚未实测；普通网络后台下载成功不能证明直连模式成功。
- 系统可以拒绝、排队或终止持续后台任务；必须保存断点并如实展示等待或暂停状态。
- 不承诺强制退出 App 后自定义下载引擎继续运行。
- 固定 IP 时保留原始域名的 SNI、Host 和证书验证；不关闭 TLS 校验，不携带令牌跳转到未授权域名。
- 凭据使用 Keychain；SQLite 只保存账户引用、任务、缓存和端点数据。
- 首版不移植桌面挂载；文件导入导出通过系统文件接口实现。
- IPA 构建、签名和真机验收需要 macOS、匹配的 Xcode/SDK、开发签名及设备；当前 Linux 环境不能完成这些验证。

## 方案取舍

推荐 SwiftUI + Rust + aria2，保留已有链接解析、直连探测和续传能力。全 Swift 重写会重新实现核心下载逻辑；SwiftUI + C++ aria2 则需要重写现有 Rust 业务。推荐方案为技术判断，用户明确的是后台下载结果，不是特定框架。

## 移植清单

| 上游模块 | 处理方式 |
| --- | --- |
| src/drive.rs | 复用链接、resourceKey、导出地址和确认页解析，保留域名校验测试 |
| src/scan.rs | 移植 IP 候选与 TLS/API/下载探测；加入取消、并发预算、网络变更失效；移除对单一固定探测文件的强依赖 |
| src/api.rs | 拆出目录与元数据逻辑；删除 gcloud 子进程依赖，改为移动端 TokenProvider |
| src/download.rs | 保留解析和下载流程，注入沙盒路径、任务回调、取消与错误类型 |
| native/bridge.cc、vendor/* | 保留 aria2 固定 IP 补丁；静态交叉编译；关闭信号处理；首版串行引擎会话，避免全局路由变量冲突 |
| src/store.rs | 复用 SQLite 思路，新增迁移、账户隔离、任务状态、引擎类型、恢复信息；删除明文 token 存储 |
| src/upload.rs | 第二阶段移植 8 MiB 分块与会话恢复，接入安全作用域文件访问 |
| src/tui.rs、src/main.rs | 替换为 SwiftUI 与 App 生命周期集成 |
| src/mount.rs | 不直接移植 rclone/NFS/FUSE；后续独立实现 File Provider |
| build.rs、scripts/build-libaria2.sh | 新增 iOS 真机与模拟器构建，输出静态库/XCFramework；不得链接桌面二进制 |

## Review Focus

1. 原始网络无法访问 Google 域名时，后台 URLSession 不能被误报为直连下载兜底。
2. 后台任务排队、过期或用户取消时，进度与落盘断点一致。
3. 两种引擎的恢复信息不兼容，切换不能破坏已有文件或静默重新下载。
4. 锁屏后的文件保护和 Keychain 可访问性必须允许已授权任务运行，并符合账户退出行为。
5. 重定向、令牌过期、磁盘不足和网络切换不得造成凭据泄露或损坏文件。

## 实施任务

### 1. 后台下载技术验证：先证明最关键路径

**创建文件：** `ios/GDirect/App/GDirectApp.swift`、`ios/GDirect/Transfers/BackgroundDownloadEngine.swift`、`ios/GDirect/Transfers/ContinuedDownloadRunner.swift`、`core/Cargo.toml`、`core/src/lib.rs`、`scripts/build-ios-core.sh`、`docs/verification/background-download.md`。

**接口：** `DownloadEngine.start(_ request: DownloadRequest) async throws -> UUID`、`cancel(_ id: UUID) async`；事件包含任务 ID、已完成字节、总字节（可未知）、状态和错误。

- [ ] 构建最小 iOS App、arm64 真机 Rust/aria2 库和模拟器库；确认 SDK availability 与所需注册配置。
- [ ] 用后台 URLSession 完成独立大文件下载，记录切后台、锁屏、系统重新唤起和完成回调。
- [ ] 将用户前台发起的固定 IP 下载接入 BGContinuedProcessingTask；接入进度、过期与取消回调。
- [ ] 在目标网络中真机运行至少 30 分钟或至下载完成，对比文件大小与校验值；覆盖 Wi-Fi 与蜂窝。
- [ ] 在普通域名网络不可用、固定 IP 可用的环境单独验证，记录引擎及实际连接目标。
- [ ] 如固定 IP 持续后台方案失败，记录明确失败原因，继续验证可用系统机制；不得把普通后台下载包装成直连成功。

### 2. 持久化任务与引擎调度

**创建文件：** `ios/GDirect/Transfers/DownloadCoordinator.swift`、`ios/GDirect/Transfers/DownloadRequest.swift`、`ios/GDirect/Storage/TaskStore.swift`、`ios/GDirectTests/TransferRecoveryTests.swift`。

**接口：** `DownloadRequest` 包含 fileID、账户引用、目标路径和路由策略；持久化引擎类型与恢复信息版本。状态为 queued/running/waitingForSystem/paused/completed/failed/cancelled。

- [ ] 编写恢复测试：取消不丢断点、进程重启恢复、引擎不兼容拒绝复用、磁盘不足停止写入。
- [ ] 实现 SQLite 迁移与任务事件原子落盘；首版 aria2 仅一个活跃会话，单文件内部多连接。
- [ ] 对系统任务拒绝、排队和过期实现真实状态转换，接入网络变化后的端点重新验证。
- [ ] 验证所有恢复测试通过；模拟中断后下载文件校验一致。

### 3. Google 登录与 Drive 浏览

**创建文件：** `ios/GDirect/Auth/GoogleAuthService.swift`、`ios/GDirect/Auth/KeychainTokenStore.swift`、`ios/GDirect/Drive/DriveBrowserView.swift`、`core/src/token_provider.rs`、`ios/GDirectTests/AuthTransferTests.swift`。

**接口：** `TokenProvider.accessToken(accountID: String) async throws -> String`；Rust 调用由桥接层取得短期访问令牌，不直接访问 Keychain。

- [ ] 配置 iOS OAuth 客户端与回调，使用 Google 支持的原生登录流程，确定浏览已有文件所需 scope。
- [ ] 移植目录分页、元数据、缓存和文档导出，接入统一下载请求。
- [ ] 测试 401 刷新、授权撤销、多账户隔离、锁屏读取及退出账户后取消关联传输。
- [ ] 在真机完成“登录→进入目录→下载私有文件→锁屏→完成”的端到端验收。

### 4. 进度展示、通知与文件导出

**创建文件：** `ios/GDirect/Transfers/TransfersView.swift`、`ios/GDirect/Transfers/TransferNotifications.swift`、`ios/GDirect/Files/FileExporter.swift`；如系统任务进度展示不足，再创建 `ios/GDirectActivity/DownloadActivity.swift`。

- [ ] 展示等待、下载、暂停、失败与完成；总大小未知时不显示虚假百分比。
- [ ] 接入系统持续任务进度；按需增加锁屏/灵动岛实时活动，控制更新频率。
- [ ] 完成通知在拒绝通知权限时不影响下载，通知不包含令牌或敏感下载 URL。
- [ ] 文件完成后提供预览、分享与导出，测试同名文件、大文件和沙盒访问。

### 5. IPA 交付与最终验收

**创建文件：** `scripts/archive-ios.sh`、`docs/verification/ios27-acceptance.md`、`THIRD_PARTY_NOTICES.md`。

- [ ] 在 macOS CI/本机构建 Release Archive，记录 Xcode、SDK、目标系统及静态依赖版本。
- [ ] 配置 Bundle ID、签名和导出方式，导出可安装 IPA；记录 GPL-2.0-or-later 与依赖许可证、对应源码和构建资料。
- [ ] 安装 Release IPA，在 iOS 27 真机复测锁屏大文件下载、网络切换、后台取消、恢复和完成提醒。
- [ ] 分别记录普通后台与固定 IP 后台的结果、耗时和限制；验证通过后才能声明对应能力完成。

## 官方参考

- 持续后台任务：https://developer.apple.com/documentation/BackgroundTasks/performing-long-running-tasks-on-ios-and-ipados
- 系统后台下载：https://developer.apple.com/documentation/foundation/downloading-files-in-the-background
- 实时活动：https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- Google 原生授权：https://developers.google.com/identity/protocols/oauth2/native-app
