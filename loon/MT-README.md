# 美团精简 · Loon

原作者 TG@ZenMoFiShi / ZenmoFeiShi；原配置针对美团 App 12.67.403。

导入 `plugins/MT.plugin`，开启插件、脚本、重写及 HTTPS 解密，并安装信任 Loon CA。

要求 Loon 3.5.3（1008）或更新版本：DOMAIN-WILDCARD 用于原配置的 mquic-*.meituan.com，未扩大成整个美团域名拦截。

保留 46 条域名/IP 拦截、2 条 URL 拦截、8 条响应脚本规则和 7 个 MITM 主机；不擅自增加 no-resolve。

脚本原生使用 $request/$response/$done，可在 Loon 运行；镜像处理逻辑未改。仅本地模拟响应验证，不代表真机所有美团版本均有效；非 JSON、未知结构和处理失败保持原响应。

原配置：https://raw.githubusercontent.com/ZenmoFeiShi/Qx/refs/heads/main/MT.snippet
原脚本：https://raw.githubusercontent.com/ZenmoFeiShi/Qx/refs/heads/main/MT.js
Loon 文档：https://nsloon.app/en/docs/Rule/domain_rule/
