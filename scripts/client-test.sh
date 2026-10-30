#!/usr/bin/env bash
# 端到端實測：以真實 Xray 客戶端連入節點，驗證出站 IP 與延遲。
# 必填環境變數：SERVER_IP、UUID、PUBLIC_KEY、SHORT_ID
# 可選：SNI（預設 www.microsoft.com）、FLOW（預設 xtls-rprx-vision）、PORT（預設 443）
set -euo pipefail

: "${SERVER_IP:?set SERVER_IP}"
: "${UUID:?set UUID}"
: "${PUBLIC_KEY:?set PUBLIC_KEY}"
: "${SHORT_ID:?set SHORT_ID}"
SNI="${SNI:-www.microsoft.com}"
FLOW="${FLOW:-xtls-rprx-vision}"
PORT="${PORT:-443}"

TMP="$(mktemp -d)"
XPID=""
cleanup() {
  [ -n "$XPID" ] && kill "$XPID" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

cd "$TMP"
curl -sL -o xray.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"
unzip -o xray.zip >/dev/null
chmod +x xray

cat > client.json <<EOF
{"inbounds":[{"port":10808,"listen":"127.0.0.1","protocol":"socks","settings":{"udp":true}}],"outbounds":[{"protocol":"vless","settings":{"vnext":[{"address":"$SERVER_IP","port":$PORT,"users":[{"id":"$UUID","encryption":"none","flow":"$FLOW"}]}]},"streamSettings":{"network":"tcp","security":"reality","realitySettings":{"serverName":"$SNI","fingerprint":"chrome","publicKey":"$PUBLIC_KEY","shortId":"$SHORT_ID"}}}]}
EOF

./xray run -c client.json > xray.log 2>&1 &
XPID=$!
sleep 4

echo -n "egress IP: "
curl -s --max-time 15 --socks5-hostname 127.0.0.1:10808 https://api.ipify.org; echo
echo "expected : $SERVER_IP"
curl -s -o /dev/null --max-time 15 --socks5-hostname 127.0.0.1:10808 \
  -w 'generate_204: %{http_code} time: %{time_total}s\n' \
  https://www.google.com/generate_204
