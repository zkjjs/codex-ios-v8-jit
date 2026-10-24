#!/bin/bash
set -euo pipefail
if [ "${EUID}" -ne 0 ]; then echo '请用 sudo bash install.sh 或 root 执行。'; exit 1; fi
for binary in python3 openssl systemctl; do
  command -v "$binary" >/dev/null || { echo "缺少 $binary，请先安装该依赖。"; exit 1; }
done
install_root=/opt/codex-quota-bridge
state_root=/var/lib/codex-quota-bridge
if [ -e "$install_root" ] || systemctl cat codex-quota-bridge.service >/dev/null 2>&1; then
  echo '检测到已有安装，已停止，未覆盖或重启现有服务。'; exit 1
fi
script_dir=$(cd -- "$(dirname -- "$0")" && pwd)
public_address="${1:-52.195.185.75}"
if ! python3 - "$public_address" <<'PY'
import ipaddress,sys
ipaddress.IPv4Address(sys.argv[1])
PY
then echo '请提供本机公网 IP 地址。'; exit 1; fi
if ! id codex-quota >/dev/null 2>&1; then
  useradd --system --home-dir "$state_root" --shell /usr/sbin/nologin codex-quota
fi
install -d -m 755 "$install_root"
install -d -o codex-quota -g codex-quota -m 700 "$state_root"
install -m 644 "$script_dir/bridge.py" "$install_root/bridge.py"
cat > "$state_root/tls.cnf" <<TLS
[req]
prompt=no
distinguished_name=dn
x509_extensions=server
[dn]
CN=Codex Quota Bridge
[server]
subjectAltName=IP:$public_address
extendedKeyUsage=serverAuth
keyUsage=critical,digitalSignature,keyEncipherment
basicConstraints=critical,CA:FALSE
TLS
chmod 600 "$state_root/tls.cnf"
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 825 \
  -keyout "$state_root/server.key" -out "$state_root/server.crt" \
  -config "$state_root/tls.cnf" >/dev/null 2>&1
chown codex-quota:codex-quota "$state_root/server.key" "$state_root/server.crt"
chmod 600 "$state_root/server.key" "$state_root/server.crt"
python3 - "$install_root/environment" <<'PY'
import os,secrets,sys
fd=os.open(sys.argv[1],os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
with os.fdopen(fd,'w') as f: f.write('CODEX_QUOTA_KEY='+secrets.token_urlsafe(48)+'\n')
PY
cat > /etc/systemd/system/codex-quota-bridge.service <<'UNIT'
[Unit]
Description=Codex Quota HTTPS Bridge
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=codex-quota
Group=codex-quota
EnvironmentFile=/opt/codex-quota-bridge/environment
ExecStart=/usr/bin/python3 /opt/codex-quota-bridge/bridge.py --directory /var/lib/codex-quota-bridge --cert /var/lib/codex-quota-bridge/server.crt --key /var/lib/codex-quota-bridge/server.key --port 8765
Restart=on-failure
RestartSec=5
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/codex-quota-bridge
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now codex-quota-bridge.service
systemctl --no-pager --full status codex-quota-bridge.service
python3 - "$public_address" "$install_root/environment" "$state_root/server.crt" <<'PY'
import hashlib,json,pathlib,ssl,sys
key=pathlib.Path(sys.argv[2]).read_text().strip().split('=',1)[1]
der=ssl.PEM_cert_to_DER_cert(pathlib.Path(sys.argv[3]).read_text())
pair={'server_url':'https://'+sys.argv[1]+':8765','gateway_key':key,'certificate_sha256':hashlib.sha256(der).hexdigest()}
print('\n请把以下配对 JSON 直接粘贴到 App 的「连接服务器」页面，无需发给他人：\n')
print(json.dumps(pair,ensure_ascii=False))
print('\n若外部无法连接，请在 AWS 安全组放行 TCP 8765（最好只允许你的来源 IP）。本脚本未修改安全组、防火墙、SSH、路由或现有容器。')
PY
