#!/usr/bin/env bash
# VM 內系統準備：裝包、BBR 與代理向 sysctl 調優、vnstat 被動統計。
# 用法：在 clone 下來的倉庫根目錄執行 bash scripts/server-setup.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

sudo apt-get update
sudo apt-get install -y curl wget unzip jq vnstat

sudo cp "$DIR/sysctl/99-bbr.conf" /etc/sysctl.d/99-bbr.conf
sudo cp "$DIR/sysctl/99-proxy-tune.conf" /etc/sysctl.d/99-proxy-tune.conf
sudo sysctl --system

sudo systemctl enable --now vnstat

echo "== verify (expect: bbr / fq / 3 / 0) =="
sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc \
       net.ipv4.tcp_fastopen net.ipv4.tcp_slow_start_after_idle
systemctl is-active vnstat
