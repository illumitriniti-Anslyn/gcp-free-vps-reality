# GCP 免費 VPS ＋ 3x-ui VLESS Reality 節點部署手冊

在 Google Cloud 免費額度內部署一台 Debian VPS，安裝官方 3x-ui 面板，開設一個
VLESS + Reality 節點（443 端口），並完成系統級網絡優化與端到端驗收。
本手冊為一次完整實戰的 distilled 紀錄，包含流程中實際踩過的坑與解法。

> 安全鐵則：本倉庫只放流程與腳本，**不放任何真實參數**。伺服器 IP、UUID、
> Reality 密鑰、shortId、面板帳密一律以佔位符表示，只在交付時直接交給使用者，
> 不寫入倉庫、記憶或一般文件。

## 架構總覽

- 雲端：Google Cloud Platform，單一項目、單台 VM
- 機型：e2-micro（Always Free 規格），區域限免費三區之一（美洲）；離亞洲最近為 us-west1
- 系統：Debian 12，開機磁碟 30GB pd-standard，網絡層 STANDARD（免費要求，不可改 Premium）
- 面板：3x-ui（MHSanaei 官方版本），僅綁定 127.0.0.1，經 SSH 隧道存取，不對公網開放
- 節點：VLESS + Reality，TCP 443，flow 為 xtls-rprx-vision，開啟 UDP 與 TCP Fast Open
- 優化：BBR 擁塞控制（fq 隊列）＋ 代理向 sysctl 調優（見 `scripts/sysctl/`）
- 統計：vnstat 只作被動流量統計，不做任何限流

## 費用與免費邊界

1. 先領額度再建機：新帳號 300 美元試用金（90 天）與（若有）AI Pro 每月 10 美元
   開發者額度，先在控制台確認兩筆額度均已入帳才動工。
2. 只用免費邊界：e2-micro、30GB pd-standard、STANDARD 網絡層、免費區域、
   一個項目只開一台 VM。任何一項越界都會開始計費。
3. 預算告警只提醒、不停機：設定約每月 1–10 美元的預算，門檻 50%／90%／100%／150%
   發電郵通知即可；控制台若已有等效預算，不要重複建立。
4. 出站流量現實：免費出站額度只涵蓋特定方向；VM 往中國等亞洲方向的出站按量計費，
   先由試用金與每月額度抵扣，預算告警可能較早響起——這是提醒，不是故障。
5. 外網 IP 預設為臨時 IP：VM 停機再開可能會變，變動後需更新客戶端連結內的 IP。

## 部署步驟

### 1. 建機（Cloud Shell）

建機前先把完整指令回顯核對一次，確認帳號、項目、區域無誤才執行：

```bash
gcloud compute instances create free-e2micro \
  --zone=us-west1-a --machine-type=e2-micro \
  --network-interface=network-tier=STANDARD,stack-type=IPV4_ONLY \
  --image-family=debian-12 --image-project=debian-cloud \
  --boot-disk-size=30GB --boot-disk-type=pd-standard \
  --tags=http-server,https-server \
  --metadata-from-file=startup-script=swap-startup.sh
```

`swap-startup.sh` 內容為建立 1GB swapfile 並寫入 fstab（e2-micro 只有約 1GB 記憶體，
加 swap 可避免裝包或編譯時 OOM）。建機後驗收：項目內恰好一台執行個體、狀態 RUNNING、
磁碟 30GB pd-standard、SSH 可連入、`swapon --show` 有 swap、記下外網 IP。

### 2. 防火牆

GCP 預設網絡未必有 443 放行規則；新建一條專用規則（不要改動預設規則）：

```bash
gcloud compute firewall-rules create allow-node-443 \
  --direction=INGRESS --priority=1000 --network=default \
  --action=ALLOW --rules=tcp:443 --source-ranges=0.0.0.0/0 \
  --target-tags=https-server --description="VLESS Reality node"
```

SSH 的 22 端口沿用預設 `default-allow-ssh`。面板端口不加任何放行規則。

不要加入「屏蔽 CDN 出站」類規則：大量 CDN IP 段被擋會直接妨礙代理節點的正常出站。

### 3. 系統優化（VM 內）

```bash
sudo apt-get update
sudo apt-get install -y curl wget unzip jq vnstat
sudo cp scripts/sysctl/99-bbr.conf scripts/sysctl/99-proxy-tune.conf /etc/sysctl.d/
sudo sysctl --system
sudo systemctl enable --now vnstat
sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc \
       net.ipv4.tcp_fastopen net.ipv4.tcp_slow_start_after_idle
# 期望：bbr / fq / 3 / 0
```

或直接執行 `scripts/server-setup.sh`（內容相同）。調優要點：BBR＋fq 是跨境長鏈路
最關鍵一項；其餘為加大連接隊列與收發緩衝、開啟 TCP Fast Open、關閉空閒後慢啟動重啟。

### 4. 安裝 3x-ui

以 root 執行官方安裝腳本（來源只認 MHSanaei/3x-ui 官方倉庫 master 分支的
install.sh，安裝時會顯示版本與 checksum 核對結果；倉庫頁面：
github.com/MHSanaei/3x-ui）：

```bash
sudo -i
bash <(curl -Ls <官方倉庫 master 分支 install.sh 的原始網址>)
```

互動問題原則：面板端口用隨機值；SSL／憑證／acme 一律拒絕（面板不對公網開放，
不需要憑證）；選項中有「只綁定 127.0.0.1」時答是。安裝程式顯示的面板端口、
隨機路徑、帳號與密碼要逐字記錄，只交給使用者本人。

注意：一般用戶或 `sudo bash <(...)` 可能因權限或程序替換 fd 問題失敗，用 `sudo -i`
取得 root shell 後執行同一官方指令即可，來源與腳本不變。

### 5. 建立節點（必須經面板或其 API 原生建立）

參數基線：

| 項目 | 值 |
|---|---|
| 協議 | VLESS |
| 端口 | 443 |
| 傳輸 | TCP，header type none |
| 安全 | Reality |
| dest / serverNames | www.microsoft.com:443 / www.microsoft.com |
| flow | xtls-rprx-vision |
| sockopt | tcpFastOpen: true |
| sniffing | enabled（http, tls, quic, fakedns） |

密鑰在 VM 內產生、直接用於配置，不要經聊天或終端轉錄傳遞：

```bash
/usr/local/x-ui/bin/xray-linux-amd64 x25519   # Reality 密鑰對
cat /proc/sys/kernel/random/uuid              # 客戶端 UUID
openssl rand -hex 8                           # shortId
```

以 API 操作面板時，v3.11 起所有 POST 都受 CSRF 保護，裸 curl 會回 403 空回應。
正確帶法：先 GET 登入頁，取頁面 `<meta name="csrf-token">` 的值與工作階段 cookie，
其後登入與每個 API 請求都帶 cookie 及標頭 `X-CSRF-Token: <token>`。

**改動後必須重啟 x-ui**：`sudo systemctl restart x-ui`。v3 面板經 API 改動只更新
資料庫，運行配置（`/usr/local/x-ui/bin/config.json`）要待重啟才重新生成並重啟 xray。
重啟後核對：config.json 修改時間已更新、443 入站的 `settings.clients` 數量為 1、
443 由新的 xray 程序監聽。

### 6. 驗收（三層，缺一不可）

1. 機內：`sudo ss -tlnp | grep ':443'` 有 xray 監聽；`systemctl is-active x-ui` 為 active。
2. 機外回落：在另一台機器對伺服器 443 端口發一個普通 HTTPS 請求，未認證連線應被
   回落到 dest 站點，回傳其真實憑證（subject 為 microsoft.com）。
3. 端到端實測（唯一算數的標準）：以真實 Xray 客戶端連入節點查出站 IP，必須等於
   伺服器 IP。直接用 `scripts/client-test.sh`（以環境變數傳入參數），它同時量測
   generate_204 的耗時，測完自動清理。

### 7. 產出客戶端連結

```bash
python3 scripts/make-link.py --server <SERVER_IP> --uuid <UUID> \
  --pbk <PUBLIC_KEY> --sid <SHORT_ID>
```

輸出小火箭可直接導入的 `vless://` 連結與 Clash（mihomo）配置段各一份。

## 故障排查（實戰紀錄）

1. **握手必失敗、未認證連線卻能回落**：多半是生成配置的 `clients` 為空陣列。
   成因是繞過面板直接把 inbound 寫入面板 SQLite 資料庫——v3 面板生成配置時
   不會帶入這種外部寫入的客戶端。解法：刪除該行，改經面板或其 API 原生重建，
   再重啟 x-ui 並核對 clients 數量。
2. **API 回應 success 但運行配置不變**：config.json 修改時間未變、xray 程序未換，
   即面板尚未重載。執行 `sudo systemctl restart x-ui` 後再核對。
3. **面板登入或 API 回 403 空回應**：CSRF 未帶。按第 5 步的帶法處理；
   日誌會出現 `CSRF validation failed` 字樣可資確認。
4. **參數懷疑被改壞**：私鑰可用 `/usr/local/x-ui/bin/xray-linux-amd64 x25519 -i <PRIV>`
   反推公鑰，與客戶端使用的公鑰逐字比對；資料庫、生成配置、反推結果三處一致
   才能排除密鑰問題。本次實戰中三處一致，證明故障與密鑰字元無關，不要先入為主。
5. **經終端傳輸的腳本損壞**：實例為 base64 傳輸解碼失敗、sysctl 檔被壓成
   單行。紀律：任何經轉錄落地的腳本或參數，執行前先以 sha256 核對；
   核對不過即停下重傳，絕不執行來歷或內容未完全確認的腳本（尤其第三方限流／關機腳本）。
6. **REALITY 目標站警告**：xray 日誌可能提示以 www.microsoft.com 為 dest 會提高
   伺服器 IP 被封鎖的機率。可改用其他大型、支援 TLS 1.3 的站點作 dest，
   並同步修改 serverNames 與客戶端 SNI，三處必須一致。

## 安全須知

- 面板只綁 127.0.0.1；管理時經 SSH 隧道：
  `gcloud compute ssh free-e2micro --zone=us-west1-a -- -L 2222:127.0.0.1:<PANEL_PORT>`
  再開瀏覽器連本機 2222 端口加上隨機路徑。
- Reality 私鑰只存在於伺服器資料庫內，不外傳；交付給使用者的只有連結與面板帳密，
  且不在任何倉庫或文件中留存。
- 不安裝未經逐行審查的第三方腳本；流量統計用 vnstat 被動記錄即可，
  是否限流由使用者自行決定，不預設裝限流或自動關機機制。

## 拆除路徑

不再需要時依序處理，刪除類操作執行前必須經使用者明確確認：
停用 x-ui 服務 → 刪除 VM 執行個體 → 檢查並刪除孤兒磁碟與快照 →
釋放未使用的靜態 IP → 視需要刪除防火牆規則與預算。
