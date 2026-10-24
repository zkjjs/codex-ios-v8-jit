# 日本服务器模式

这是独立的单用户额度服务。iPhone 仅连接你配置的 HTTPS 地址；OpenAI OAuth 凭证保存在服务器的专用目录，不回传给手机。服务使用随机配对密钥，App 校验你从服务器取得的 TLS 证书 SHA-256 指纹，支持公网 IP 和自签证书，不需要新域名。

## 安装

依赖：Ubuntu 上现有的 python3、openssl、systemd；无 Python 第三方依赖。确认公网 IP 仍为 `52.195.185.75` 后，在解压后的目录执行：

```bash
sudo bash install.sh 52.195.185.75
```

安装位置 `/opt/codex-quota-bridge`，私有状态 `/var/lib/codex-quota-bridge`，服务 `codex-quota-bridge.service`，HTTPS 端口 `8765`。检测到已有同名安装会停止，不会覆盖或重启它。安装会创建专用系统用户并启动新服务，不修改 SSH、防火墙、路由或生产容器。

如手机不能连入，在 AWS 安全组允许 TCP 8765，来源尽量限制到自己使用的公网 IP。不要把 OAuth 凭证或配对密钥放进 GitHub。安装完成会在你自己的终端输出配对 JSON，把它粘贴到新版 App 的连接服务器页面即可。

App 点击登录后显示设备码，打开 OpenAI 官方网页完成授权，返回 App 即可。服务器会轮询授权结果并保存令牌。服务端同步仍受 OpenAI 账号与网络情况影响；此前设备授权接口返回 200，并不等于已完成真实账号授权或额度读取。

## 检查与恢复

```bash
sudo systemctl status codex-quota-bridge --no-pager
sudo journalctl -u codex-quota-bridge -n 30 --no-pager
```

恢复误复制的配对参数：公网地址使用原值，配对密钥位于 `/opt/codex-quota-bridge/environment`，证书位于 `/var/lib/codex-quota-bridge/server.crt`。不要把这些私有文件发给他人。

停用新服务的回滚命令（由你明确决定后执行）：`sudo systemctl disable --now codex-quota-bridge`。停用不会删除账号文件。只有确认不再需要授权时，才通过 App 的「退出服务器账号」清除服务端账号。

## 存储与信任

账号 JSON 以 0600 权限存于仅服务用户可访问的 0700 目录，与官方 CLI auth.json 类似，并非额外加密的保险库。对本机 root 的信任是部署前提。TLS 私钥和配对密钥权限受限。自签证书有效期 825 天，之后应有计划地更新证书并重新配对；不得通过禁用证书校验来解决证书错误。

小组件仍需签名保留 Widget Extension、App Groups 和共享 Keychain；服务器模式不能替代 iOS 的签名权限。
