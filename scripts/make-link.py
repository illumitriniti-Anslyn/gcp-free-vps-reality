#!/usr/bin/env python3
"""由節點參數產出小火箭 vless:// 連結與 Clash(mihomo) 配置段。

用法：
  python3 make-link.py --server <IP> --uuid <UUID> --pbk <PUBLIC_KEY> --sid <SHORT_ID>
可選：--port 443 --sni www.microsoft.com --name Reality-443 --flow xtls-rprx-vision
"""
import argparse

p = argparse.ArgumentParser()
p.add_argument("--server", required=True)
p.add_argument("--uuid", required=True)
p.add_argument("--pbk", required=True)
p.add_argument("--sid", required=True)
p.add_argument("--port", default="443")
p.add_argument("--sni", default="www.microsoft.com")
p.add_argument("--name", default="Reality-443")
p.add_argument("--flow", default="xtls-rprx-vision")
a = p.parse_args()

link = (
    f"vless://{a.uuid}@{a.server}:{a.port}"
    f"?encryption=none&security=reality&sni={a.sni}&fp=chrome"
    f"&pbk={a.pbk}&sid={a.sid}&type=tcp&flow={a.flow}#{a.name}"
)
print(link)
print()
print("proxies:")
print(f'  - name: "{a.name}"')
print("    type: vless")
print(f"    server: {a.server}")
print(f"    port: {a.port}")
print(f"    uuid: {a.uuid}")
print("    network: tcp")
print("    udp: true")
print("    tls: true")
print(f"    flow: {a.flow}")
print(f"    servername: {a.sni}")
print("    reality-opts:")
print(f"      public-key: {a.pbk}")
print(f"      short-id: {a.sid}")
print("    client-fingerprint: chrome")
