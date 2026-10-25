# Loon 脚本适配

- [歪麦霸王餐插件](https://raw.githubusercontent.com/zkjjs/codex-ios-v8-jit/loon-scripts/loon/plugins/wmbwc.plugin)
- [晓晓优选插件](https://raw.githubusercontent.com/zkjjs/codex-ios-v8-jit/loon-scripts/loon/plugins/xxyx.plugin)

在 Loon 的插件管理中分别添加上述 Raw URL。开启插件、脚本和 HTTPS 解密，安装并信任 Loon 的 CA 证书。打开对应 App 登录，再进入“我的”，出现“账号已保存”通知后可在 Loon 中手动运行每日任务。不要与原版脚本同时启用，避免重复抓取和运行。

默认定时：歪麦每天 08:10；晓晓每天 08:15，按设备时区。可修改插件的 cron 行后作为本地配置使用。插件包含定时任务；只需抓取时可删除 cron 行。

凭据只存于 Loon 本地的 `wmbwc_data` 和 `xxyx_data`，保持原版数组结构。支持多账号更新；不会打印 token。没有通过真实账号请求线上服务。接口可能随 App 更新，实际完成情况以官方 App 和服务端返回为准。

## 改动

原生使用 Loon 的 `$httpClient`、`$persistentStore`、`$notification`、`$done({})`；抓取失败也放行原始请求与响应。网络超时、HTTP 错误、多账号失败隔离和任务次数做了处理。

歪麦修复原脚本正常 POST 被跳过的问题；AES 协议按来源实现，使用随脚本打包的 CryptoJS 4.2.0（MIT，见 vendor/LICENSE），无需下载或执行远程代码。保留签到、饭票查询和最多六轮任务。

晓晓保留签到、能量查询和未完成任务；移除原版“检查登录”中固定绑定推广账号的行为。已完成任务不会再次执行；单任务最多 20 次，并优先采用服务端 remainingCount。

## 来源与归属

接口参考 Sliverkiss 原脚本，Loon 运行逻辑重新编写，未分发其混淆主体：

- https://gist.github.com/Sliverkiss/49a9ffb2169a2becc33bf4fdbf6eb99a
- https://gist.github.com/Sliverkiss/991a81be1fc8cf2a1937432be68f5521
- Loon 官方 API：https://github.com/Loon0x00/LoonManual/blob/master/docs/cn/script_api.md

## 验证与构建

Node.js 18+，无 npm 运行时依赖：

```sh
node build.cjs
node --test tests/loon.test.cjs
```

离线模拟测试验证抓取、不修改 HTTP 流量、OPTIONS 跳过、账号去重、AES 与签名、定时任务调用、多账号隔离及凭据不写入通知。没有在 Loon 真机登录验证。
