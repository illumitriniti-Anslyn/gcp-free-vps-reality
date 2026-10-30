# Skill: GCP 免費 VPS ＋ 3x-ui VLESS Reality 節點部署

用途：在 GCP 免費額度內建一台 Debian VPS，裝官方 3x-ui，開 VLESS Reality 節點
（443），完成 BBR 與代理向網絡調優，端到端實測通過後交付小火箭／Clash 連結。
完整手冊見同倉庫 README.md；本文件是執行時的硬規則清單。

## 硬規則（違反任一條即停下）

1. 先領額度再建機：300 美元試用金與（如有）每月 10 美元額度未確認入帳，不建機。
2. 免費邊界不越線：e2-micro、30GB pd-standard、STANDARD 網絡層、免費區域、
   一項目一台 VM。預算告警只提醒不停機；已有等效預算不重複建。
3. 建機前先回顯完整指令核對帳號／項目／區域；刪除類操作必須經使用者明確確認。
4. 登入、綁卡、驗證由使用者親自在頁面完成；不索取密碼、卡號、驗證碼。
   面板與節點憑證只在交付時給使用者，不寫入記憶、倉庫或一般文件。
5. 不執行未經逐行審查的第三方腳本（限流、關機類尤甚）。經終端轉錄落地的
   腳本或參數，執行前必須 sha256 核對；不過即停下重傳。
6. 不加「屏蔽 CDN 出站」防火牆規則（與代理用途衝突）；不預設任何限流機制，
   vnstat 只作被動統計。是否限流由使用者決定。

## 執行順序

1. 核實結算：帳號、項目、試用金與月額度入帳、預算告警存在。
2. 建機：gcloud 守衛參數（見 README）＋ 1GB swap 啟動腳本；驗收 RUNNING、
   磁碟規格、SSH、swap。
3. 防火牆：新建 tcp:443 放行規則（目標標籤 https-server）；22 沿用預設；
   面板端口不放行。
4. 系統優化：apt 裝 curl wget unzip jq vnstat；寫入 99-bbr.conf 與
   99-proxy-tune.conf（scripts/sysctl/）；sysctl --system 後核實
   bbr／fq／tcp_fastopen=3／tcp_slow_start_after_idle=0；enable vnstat。
5. 裝 3x-ui：root shell 執行 MHSanaei 官方 install.sh；SSL 一律拒絕；
   面板只綁 127.0.0.1；逐字記錄面板端口、路徑、帳密。
6. 建節點：密鑰（x25519、uuid、shortId）在 VM 內產生並直接使用。
   只准經面板 UI 或其 API 原生建立 inbound（VLESS／443／Reality／
   dest www.microsoft.com／vision／sockopt tcpFastOpen／sniffing on）。
   **嚴禁直接寫面板 SQLite 資料庫建立 inbound**——v3 生成配置時會丟棄
   外部寫入的客戶端，clients 變空陣列，握手必失敗。
   API 的 POST 需 CSRF：先 GET 登入頁取 meta csrf-token 與 session cookie，
   之後每個請求帶 cookie ＋ `X-CSRF-Token` 標頭。
7. 套用改動：`sudo systemctl restart x-ui`（API 改動只寫資料庫，不重啟不生效）。
   核對 config.json 已重生成、443 入站 clients 數量為 1、xray 程序已換新。
8. 驗收三層：機內 443 監聽；機外未認證連線回落 dest 並回其真實憑證；
   端到端以 scripts/client-test.sh 實測，出站 IP 必須等於伺服器 IP，
   另記 generate_204 耗時。未過端到端，不交付連結。
9. 交付：scripts/make-link.py 產出 vless:// 連結與 Clash 配置段（純文字）；
   附面板隧道存取方式與帳密；收尾清單註明額度、規格合規、防火牆現況、
   臨時 IP 注意、出站計費現實與拆除路徑。

## 排障速查

- 握手失敗＋能回落 → 先查生成配置 clients 是否為空（jq 查 config.json）。
- API success 但配置沒變 → 未重啟 x-ui；看 config.json 修改時間與 xray pid。
- 登入／API 403 空回應 → CSRF 未帶（日誌有 CSRF validation failed）。
- 懷疑密鑰被轉錄改壞 → 以 `xray x25519 -i <PRIV>` 反推公鑰，
  與資料庫、生成配置三處比對後才下結論。
- dest 警告 → 可換其他大型 TLS 1.3 站點，dest／serverNames／客戶端 SNI 三處同步。
