# 獨立部署指南（實驗室 / 自有主機）

> 目標：在自有主機上獨立建置並運行整套系統，**不依賴任何特定個人的 GitHub／雲端帳號**。

> ⚠️ **安全鐵則**：帳號、密碼、API token、伺服器內網 IP **絕對不要寫進本檔或任何 git 追蹤的檔案**（本 repo 會推上 GitHub）。
> 機密只放：①部署主機的 `backend/.env`、②你個人的密碼管理器。文中一律用 `<...>` 佔位符代表「你要自己填的值」。

---

## 部署用到的工具是什麼（白話對照）

| 工具 | 一句話說明 | 在本系統的角色 |
|------|------------|----------------|
| **Ubuntu** | Linux 作業系統 | 後端主機的 OS（跑在 Proxmox 虛擬機裡） |
| **Proxmox VE** | 虛擬機管理平台 | 實驗室用它開出我們的 Ubuntu VM（`https://<host>:8006` 管理） |
| **PostgreSQL** | 關聯式資料庫 | 存所有資料（樹木、專案、使用者…）；本系統用 v16 |
| **Node.js** | JavaScript 執行環境 | 跑後端程式（Express API）；用 v20 LTS |
| **npm** | Node 套件管理器 | `npm install` 安裝後端相依套件 |
| **PM2** | Node 程式的「常駐管理員」 | 讓後端開機自啟、崩潰自動重啟、多核心並行（cluster）、看 log；程序名 `tree-backend` |
| **nginx** | 反向代理 / 網頁伺服器 | 對外收 443(HTTPS) 轉給後端 3000；負責 TLS、限速、安全標頭 |
| **Tailscale** | 零設定的私有網路（VPN）+ 免費 `*.ts.net` 憑證 | 讓手機與 VM 在同一虛擬內網直接互連；並提供**受信任 HTTPS 憑證**（手機不必信任自簽憑證）。本次採用 |
| **ngrok** | 把內網服務開一個公開臨時網址 | Tailscale 的替代方案（免費網址會變）；本次**未採用** |
| **Let's Encrypt / certbot** | 免費正式 TLS 憑證 | 若改用「機構網域」對外時的發憑證工具（Tailscale 方案則不需要） |
| **UFW** | Ubuntu 防火牆 | 只開放必要連接埠（SSH、HTTP/HTTPS） |
| **`.env`** | 環境變數設定檔 | 放資料庫連線、JWT 密鑰、各 API 金鑰；**不進 git** |
| **GitHub webhook** | git push 時通知主機 | 觸發 `deploy.sh` 自動部署（選用） |

---

## 重新部署完整流程（Proxmox VM｜從零照著做）

> 適用情境：拿到實驗室一台 **Proxmox VE 虛擬機**（Web 管理介面 `https://<PVE_HOST>:8006`），要把整套後端重新部署上線。
> 這節是「不用思考、從上到下照打」的版本；每一步「為什麼這樣做、可調參數」見下方 **§3 Ubuntu runbook**。
> 名詞：`<PVE_HOST>` = Proxmox 主機位址；`<VM_USER>` = 進到 VM 後的 Linux 帳號；`<你的網域>` = App 連線網址。

### 步驟 0：登入 Proxmox、開機並進入 VM
1. 瀏覽器開 `https://<PVE_HOST>:8006`，用實驗室給的 Proxmox 帳號／密碼登入（Realm 視設定選 `Proxmox VE authentication` 或 `Linux PAM`）。憑證**不要**寫進任何檔案。
2. 左側樹狀選單點到你的虛擬機（例如名稱含 `VM121` 那台）→ 上方 **Start** 開機。
3. 進入系統：點 **>_ Console** 開網頁終端機登入；或先在 Console 內 `ip a` 查到 VM 的 IP，再用自己電腦 `ssh <VM_USER>@<VM_IP>` 連線（之後操作較方便）。
4. 確認 OS 版本：`lsb_release -a`（本指南支援 Ubuntu 22.04 / 24.04 LTS）。

### 步驟 1：安裝系統套件
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl ufw nginx postgresql postgresql-contrib
# Node.js 20 LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
node -v          # 應為 v20.x
sudo npm install -g pm2
```

### 步驟 2：建立 PostgreSQL 資料庫與使用者
```bash
sudo -u postgres psql <<'SQL'
CREATE USER treeapp WITH PASSWORD '<DB_密碼>';
CREATE DATABASE treedb OWNER treeapp;
GRANT ALL PRIVILEGES ON DATABASE treedb TO treeapp;
SQL
```

### 步驟 3：取得程式碼到 `/opt/tree-app`
```bash
sudo mkdir -p /opt/tree-app/logs
sudo chown -R "$USER" /opt/tree-app
cd /opt/tree-app
git clone https://github.com/<你的帳號>/tree-project-backend.git backend
cd backend
npm install --production
```

### 步驟 4：設定 `.env`（機密只放這裡）
```bash
cd /opt/tree-app/backend
cp .env.example .env
nano .env
```
至少填入（完整清單見 `HANDOFF_SECRETS_CHECKLIST.md` §A）：
```ini
NODE_ENV=production
PORT=3000
DATABASE_URL=postgres://treeapp:<DB_密碼>@localhost:5432/treedb
DB_SSL=false
JWT_SECRET=<用 openssl rand -hex 64 產生一串貼上>
CORS_ALLOWED_ORIGINS=https://<你的網域>
# 選用：自動部署 webhook 才需要
DEPLOY_WEBHOOK_SECRET=<自訂隨機字串>
```

### 步驟 5：建資料庫結構 + 建立管理員
```bash
cd /opt/tree-app/backend
SKIP_CSV_IMPORT=1 node scripts/migrate.js        # 正式庫：只建 schema + 參考資料，不匯入測試樹
node scripts/create_lab_admin.js --username labadmin --password '<強密碼>' --display '實驗室管理員'
```
> 全新部署後：業務資料（樹木、專案、使用者）為空；參考資料（樹種、別名、樹況選單）已隨系統載入。

### 步驟 6：用 PM2 啟動 + 開機自啟
```bash
cd /opt/tree-app/backend
pm2 start ecosystem.config.js     # name=tree-backend, cluster ×2
pm2 save
pm2 startup systemd               # 依輸出貼上它給的那行 sudo 指令
curl -sf http://127.0.0.1:3000/health   # 應回 200
```

### 步驟 7：Nginx 反向代理 + TLS 憑證
```bash
sudo nano /etc/nginx/sites-available/tree-app   # 內容見 §3.8 範本（把 server_name 換成你的網域）
sudo ln -s /etc/nginx/sites-available/tree-app /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```
TLS（手機端必須是有效憑證，否則 App 全部 API 連不上）擇一：
```bash
# A. 機構網域 + Let's Encrypt（最佳）
sudo certbot --nginx -d <你的網域>
# B. Tailscale *.ts.net 憑證（內網方便）
#    先到 Tailscale 後台啟用 HTTPS Certificates，再用 `tailscale status` 查出本機 *.ts.net 全名，
#    並「當參數傳入」（不要靠腳本自動偵測，原因見本指南「Nginx / TLS 疑難排解」）：
sudo bash scripts/setup_tailscale_tls.sh <你的主機>.<tailnet>.ts.net
```

### 步驟 8：防火牆
```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
```

### 步驟 9：建置 APK 給調查員
```bash
cd frontend
flutter build apk --release --dart-define=API_BASE_URL=https://<你的網域>/api
# 若為自簽憑證主機才加：--dart-define=SELF_SIGNED_TRUSTED_HOSTS=<host>
```

### 步驟 10：驗收
```bash
# 公開健康檢查端點（不需 token），成功回純文字 OK
curl https://<你的網域>/health        # 不要加 -k；回 200 且無憑證錯誤 = 手機會信任憑證
```
- **為什麼用 `/health` 而不是 `/api/health`**：健康檢查掛在 `backend/app.js` 的 `app.get('/health', ...)`，是公開端點、回純文字 `OK`。`/api/*` 底下的路由都掛了 JWT 驗證中介層，未帶 token 會回 `401 {"success":false,"message":"未授權：缺少 JWT token"}`——所以打 `/api/health` 會誤判成失敗。重點是「**有回應且憑證不報錯**」就代表 TLS→nginx→後端整條鏈路通。
- 再跑一輪 `VERIFICATION_CHECKLIST.md`。

### 之後「改了程式要重新部署」怎麼做
- **有設 webhook**：直接 `git push` 到 `main`，主機 `deploy.sh` 會自動 pull→install→增量 migration→reload→health→失敗自動 rollback。
- **手動部署**：
  ```bash
  cd /opt/tree-app/backend
  git pull
  npm install --production
  node scripts/run_pending_migrations.js   # 只跑沒套過的 migration
  pm2 reload ecosystem.config.js
  curl -sf http://127.0.0.1:3000/health
  ```

### VM 常用維運
```bash
pm2 status                 # 看後端有沒有在跑
pm2 logs tree-backend      # 看後端日誌
sudo systemctl status nginx postgresql
df -h                      # 看硬碟空間
```

### Nginx / TLS 疑難排解（實戰踩過的坑）
> 以下三點是這次實際部署遇到並解決的問題，照著做可避免重蹈覆轍。

**1) `setup_tailscale_tls.sh` 執行後完全無輸出、`nginx -t` 報找不到 `ts.crt`**
- 原因：腳本未帶參數時會自動偵測 `*.ts.net` 名稱（`tailscale status --json | grep ... | head -1`）。在 `set -e -o pipefail` 下，`head` 先關管線使 `grep` 收到 SIGPIPE（非零），整條 pipeline 被判失敗，腳本在產憑證前就**無聲中止**。
- 解法：**把 `*.ts.net` 全名當參數傳入**，跳過自動偵測：
  ```bash
  sudo bash scripts/setup_tailscale_tls.sh <你的主機>.<tailnet>.ts.net
  ```

**2) `nginx -t` 報 `conflicting server name ...` + `could not build server_names_hash`**
- 原因：舊版腳本把備份檔存成 `/etc/nginx/sites-enabled/tree-app.bak.<時間>`，而 nginx 會 `include sites-enabled/*` **載入該資料夾每一個檔**，於是 `tree-app` 與 `tree-app.bak.*` 有相同 `server_name` → 衝突且 hash 表建不起來。
- 立即解法：刪掉 sites-enabled 內的備份檔，再測試 + 重載：
  ```bash
  sudo rm -f /etc/nginx/sites-enabled/tree-app.bak.*
  ls -l /etc/nginx/sites-enabled/        # 應只剩 tree-app 一個檔
  sudo nginx -t && sudo systemctl reload nginx
  ```
- 永久修復：腳本已改成把備份寫到 `/opt/tree-app/nginx-conf-backups/`（不在 nginx include 範圍）。
- 若是單一長網域真的撞到 hash 上限，再加大 bucket：
  ```bash
  sudo sed -i 's/^http {/http {\n    server_names_hash_bucket_size 128;/' /etc/nginx/nginx.conf
  sudo nginx -t && sudo systemctl reload nginx
  ```

**3) `curl .../api/health` 回 `401 未授權：缺少 JWT token`（其實不是錯）**
- 原因：`/api/*` 路由都掛 JWT 驗證中介層，沒帶 token 一律回 401。後端用 `.env` 的 `JWT_SECRET` 來簽發與驗證登入後的 token；驗收階段不會有 token，所以打 `/api/*` 必然 401。
- 正確驗收：改打公開端點 `/health`（`app.js` 的 `app.get('/health', ...)`，回純文字 `OK`）：
  ```bash
  curl https://<你的網域>/health        # 預期：OK
  ```
- 重點：能回應（401 或 OK）且**憑證不報錯**，就代表 TLS→nginx→後端整條鏈路是通的。

---

## 0. 首次部署流程（一次做完）

> 情境：在自己的 GitHub repo 與部署主機上，從零建立整套系統。

### 0.1 推送程式碼到接手方 GitHub（fresh snapshot，不帶舊歷史）

**不要**把開發用 repo 的完整 `git push` 給接手方——舊 commit 可能含開發期私有 IP、帳號、除錯訊息等。

改用「單一乾淨快照」開新歷史（**兩個 repo 各做一次**）。歸屬由 `LICENSE`、`AUTHORS.md`、`CONTRIBUTION_RECORD.md` 載明，不靠舊 `git log`。

**PowerShell（建議）**：

```powershell
cd backend   # 或 frontend
.\scripts\prepare_fresh_handover.ps1
git remote add recipient https://github.com/<RECIPIENT>/tree-project-frontend.git
git push recipient handover:main
git checkout main
```

**或手動（bash）**：

```bash
cd frontend
git checkout main && git pull
git checkout --orphan handover
git add -A
git commit -m "Initial handover snapshot (2026-06)

Copyright (c) 2025 KyleliuNDHU. See LICENSE, AUTHORS.md, CONTRIBUTION_RECORD.md.

Original development and primary maintenance by KyleliuNDHU.
Fresh history push without prior commit log."
git remote add recipient https://github.com/<RECIPIENT>/tree-project-frontend.git
git push recipient handover:main
git checkout main
```

**交付方（推送前）**：在本機私人匯出開發歷史作個人證明，**不要**上傳給接手方：

```bash
git log --oneline --decorate > handover_evidence_git_log.txt
git shortlog -sn > handover_evidence_shortlog.txt
```

推上去後 CI 會自動跑（workflow 不依賴 GitHub Secrets，零設定即可綠）。

### 0.2 金鑰全部重新申請

依 `HANDOFF_SECRETS_CHECKLIST.md` §A 逐項作廢舊金鑰、申請新金鑰，填入部署主機的 `backend/.env`
（範本 `backend/.env.example`）。Google Maps key 填 `frontend/android/key.properties`（範本 `key.properties.example`）。

### 0.3 部署主機（見本指南 §3）

照 §3 安裝依賴、建 DB、跑 `migrate.js`（正式庫設 `SKIP_CSV_IMPORT=1`）、PM2 啟動。

### 0.4 設定自動部署 webhook

實驗室 GitHub repo → Settings → Webhooks → Add webhook：
- Payload URL：`https://<部署主機>/webhook/deploy`
- Content type：`application/json`
- Secret：與主機 `backend/.env` 的 `DEPLOY_WEBHOOK_SECRET` 一致（自訂隨機字串）
- 事件：Just the push event

之後 push 到 `main` 即自動部署（機制見 `HANDOFF.md` §6.1）。

### 0.5 建立管理員（正式環境）

`users` 表**不**含預寫種子。首次部署 migrate 完成後：

```bash
node scripts/create_lab_admin.js --username labadmin --password '<強密碼>' --display '實驗室管理員'
```

- 僅在空庫或需新增管理員時執行；username 重複會報錯。
- **勿**在 production 執行 `seed_dev_users.js`（該腳本僅供本機／CI，會建立 `admin/12345` 等弱密碼測試帳）。
- 若舊庫仍有歷史 seed 帳號（`admin`/`test`/`tt2`），建議停用或刪除後只保留 `create_lab_admin` 建立的帳號。

### 0.6 建置 APK 與驗收

```bash
cd frontend
flutter build apk --release --dart-define=API_BASE_URL=https://<部署主機>/api
```
最後跑一輪 `VERIFICATION_CHECKLIST.md`，並在 GitHub 設定 `main` 分支保護（required CI check）。

> ⚠️ **手機端 TLS 必須是「受信任的有效憑證」**
> Android 預設**拒絕自簽憑證**。若 `API_BASE_URL` 指向自簽憑證的主機（例如直接用
> `https://<IP>/api`，憑證 CN=IP、自簽），App 啟動自檢會出現：
> `CERTIFICATE_VERIFY_FAILED: self signed certificate`，**所有 API 都連不上**。
>
> 正確做法（擇一）：
> 1. **機構網域 + 正式憑證**（最佳）：用學校／圖資中心的網域 + Let's Encrypt（certbot），
>    `API_BASE_URL=https://tree.example.edu.tw/api`。
> 2. **Tailscale 有效憑證**（內網/測試很方便，免費自動簽發）：
>    - 快速法（免 sudo，operator 即可，但繞過 nginx 速率限制）：
>      ```bash
>      tailscale serve --bg --https 443 http://127.0.0.1:3000   # 關閉：tailscale serve --https=443 off
>      ```
>      App 指向 `https://<主機>.<tailnet>.ts.net/api`。
>    - 正式法（保留 nginx 速率限制／安全標頭，需 sudo）：**一鍵腳本**
>      ```bash
>      sudo bash scripts/setup_tailscale_tls.sh   # 自動偵測 ts.net 名稱、產憑證、改 nginx（含備份/測試/回滾）、設 90 天 renew cron
>      ```
>      手動等效步驟：`sudo tailscale cert --cert-file /opt/tree-app/ssl/ts.crt --key-file /opt/tree-app/ssl/ts.key <主機>.<tailnet>.ts.net` →
>      nginx `server_name` 加該 ts.net 名稱、`ssl_certificate` 指向 ts.crt/ts.key → `sudo nginx -t && sudo systemctl reload nginx`。
>      （Tailscale 憑證約 90 天，腳本已設 `/etc/cron.d/tree-tls-renew` 自動續期。）
> 用 `curl https://<主機>/api/health`（**不要加 `-k`**）回 200/401 且無憑證錯誤，即代表手機會信任。

### 0.7 交接日 checklist

- [ ] 兩 repo fresh push 完成、CI 綠
- [ ] `HANDOFF_SECRETS_CHECKLIST.md` §A 金鑰全部輪替完
- [ ] 後端部署完成、`/health` OK
- [ ] webhook 自動部署測試一次（push 小變更 → 自動上線）
- [ ] 管理員以 `create_lab_admin.js` 建立（非 DB 種子）；舊 seed 帳號已停用或刪除
- [ ] APK 建置並在實機登入成功
- [ ] `VERIFICATION_CHECKLIST.md` 跑過一輪
- [ ] 確認無任何個人帳號殘留存取（Tailscale／GitHub webhook／雲端服務）

---

## 1. 架構建議（單機實驗室）

```
┌─────────────────┐     Wi‑Fi / LAN      ┌──────────────────────────────┐
│ 調查員 Android   │ ──────────────────► │ 實驗室主機（Windows/Linux）    │
│ Flutter App     │                     │  • Node 後端 :3000             │
└─────────────────┘                     │  • PostgreSQL                │
                                        │  • ML 服務（可選 GPU 機）     │
                                        │  • Nginx 反向代理（建議）      │
                                        └──────────────────────────────┘
```

- **不要**把 JWT、DB 密碼、ML API Key 寫死在 App；使用建置時注入或首次啟動設定。
- 程式碼以**你自己的 GitHub repo** 為準（見 §0.1 fresh push）；不要在部署主機登入任何個人開發帳號。

---

## 2. 獨立性檢查表（不綁定特定個人帳號）

| 項目 | 做法 |
|------|------|
| 原始碼 | 以 release 壓縮包或實驗室 git 伺服器為準，不含 `.env` |
| 資料庫 | 實驗室自建 PostgreSQL，執行 `backend/scripts/migrate.js` |
| 系統管理員 | 部署腳本建立 **lab-admin**（非個人信箱） |
| 調查員帳號 | `POST /api/invites` 發邀請碼，或管理 Web 建立 |
| App 連線位址 | `frontend` 建置參數 / `assets/config.json` 指向實驗室 IP |
| ML 服務 | 實驗室 `.env` 的 `ML_SERVICE_URL`，與個人 Tailscale 分離 |
| 憑證 | 內網可用自簽 + App 僅信任該 CA（或 HTTP 僅限實驗室 VLAN） |

---

## 3. Ubuntu 主機從零搭建（runbook）

> 情境：拿到一台乾淨的 Ubuntu 22.04 / 24.04 LTS 主機，從安裝套件到後端上線。
> 指令以 `sudo` 為前提；`<...>` 都是你要替換的值。後端正式目錄固定為 `/opt/tree-app/backend`
> （`ecosystem.config.js`、`scripts/deploy.sh` 皆寫死此路徑，請勿改名）。

### 3.1 系統需求

| 項目 | 版本 / 說明 |
|------|-------------|
| OS | Ubuntu 22.04 或 24.04 LTS |
| Node.js | 20 LTS |
| PostgreSQL | 15+ |
| 反向代理 | Nginx |
| 行程管理 | PM2（cluster 模式，2 workers） |
| （可選）ML | Python 3.10+、GPU；見 `ml_service/README.md` |

### 3.2 安裝系統套件

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl ufw nginx postgresql postgresql-contrib

# Node.js 20 LTS（NodeSource）
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
node -v   # 應為 v20.x

# PM2（全域）
sudo npm install -g pm2
```

### 3.3 建立 PostgreSQL 資料庫與使用者

```bash
sudo -u postgres psql <<'SQL'
CREATE USER treeapp WITH PASSWORD '<DB_密碼>';
CREATE DATABASE treedb OWNER treeapp;
GRANT ALL PRIVILEGES ON DATABASE treedb TO treeapp;
SQL
```

之後 `.env` 的連線字串即：`DATABASE_URL=postgres://treeapp:<DB_密碼>@localhost:5432/treedb`。
（本機同主機連線通常免 SSL，`.env` 設 `DB_SSL=false`。）

### 3.4 取得程式碼到 `/opt/tree-app`

```bash
sudo mkdir -p /opt/tree-app/logs
sudo chown -R "$USER" /opt/tree-app
cd /opt/tree-app
git clone https://github.com/<你的帳號>/tree-project-backend.git backend
cd backend
npm install --production
```

> fresh snapshot push（不帶舊歷史）見 §0.1；正式上線請 clone **你自己的** repo，主機上不要登入任何個人開發帳號。

### 3.5 設定 `.env`

```bash
cd /opt/tree-app/backend
cp .env.example .env
nano .env
```

至少填入（完整清單見 `HANDOFF_SECRETS_CHECKLIST.md` §A）：

```ini
NODE_ENV=production
PORT=3000
DATABASE_URL=postgres://treeapp:<DB_密碼>@localhost:5432/treedb
DB_SSL=false
JWT_SECRET=<openssl rand -hex 64 產生>
CORS_ALLOWED_ORIGINS=https://<你的網域>
# 以下選用：用自動部署 webhook 才需要
DEPLOY_WEBHOOK_SECRET=<自訂隨機字串>
# 選用：只給 GET /webhook/status 讀部署 log；不設則該端點回 401，不影響系統
ADMIN_API_TOKEN=<自訂隨機字串>
```

### 3.6 初始化資料庫與管理員

```bash
cd /opt/tree-app/backend
SKIP_CSV_IMPORT=1 node scripts/migrate.js          # 正式庫：只建 schema，不匯入測試樹
node scripts/create_lab_admin.js \
  --username labadmin --password '<強密碼>' --display '實驗室管理員'
```

> ⚠️ 正式環境**永遠不要**跑 `seed_dev_users.js`（會建 `admin/12345` 弱密碼）；`NODE_ENV=production` 時該腳本也會拒絕執行。

### 3.7 用 PM2 啟動並設定開機自啟

```bash
cd /opt/tree-app/backend
pm2 start ecosystem.config.js        # name=tree-backend, cluster ×2, log → /opt/tree-app/logs
pm2 save                             # 記住目前行程清單
pm2 startup systemd                  # 依輸出複製貼上它給的那行 sudo 指令
curl -sf http://127.0.0.1:3000/health   # 應回 200
```

### 3.8 Nginx 反向代理（範本）

對外只開 Nginx，由它轉發到本機 `:3000`。把下列存成 `/etc/nginx/sites-available/tree-app` 後啟用：

```nginx
server {
    listen 443 ssl;
    server_name <你的網域或 *.ts.net>;

    ssl_certificate     /opt/tree-app/ssl/fullchain.pem;   # 見 §3.9
    ssl_certificate_key /opt/tree-app/ssl/privkey.pem;

    client_max_body_size 12M;   # 樹木照片上傳（後端限 10M）

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/tree-app /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

> 後端 `app.js` 已 `trust proxy`，會用 `X-Forwarded-For` 判斷來源 IP（速率限制／黑名單需要）。
> GitHub webhook 路徑 `POST /webhook/deploy` 走同一個反代即可（原部署另用 `:8443`，非必要）。

### 3.9 TLS 憑證

手機端**必須**是受信任的有效憑證，否則 App 全部 API 連不上（見 §0.6 的警告）。兩種做法：
- **機構網域 + Let's Encrypt**（最佳）：`sudo certbot --nginx -d <你的網域>`。
- **Tailscale `*.ts.net` 憑證**（內網方便）：`sudo bash scripts/setup_tailscale_tls.sh`（自動產憑證、改 nginx、設 90 天續期 cron）。

### 3.10 防火牆

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
```

### 3.11 自動部署 webhook

GitHub repo → Settings → Webhooks，Payload URL 指向 `https://<主機>/webhook/deploy`，Secret 與 `.env` 的 `DEPLOY_WEBHOOK_SECRET` 一致（細節見 §0.4）。之後 push 到 `main` 會觸發 `scripts/deploy.sh`：pull → `npm install` → `run_pending_migrations.js` → `pm2 reload` → health check → 失敗自動 rollback。

### 3.12 資料庫備份（每日 cron）

```bash
crontab -e
# 每日 03:00 備份（腳本見 backend/scripts/backup_db.sh）
0 3 * * * /opt/tree-app/backend/scripts/backup_db.sh >> /opt/tree-app/logs/backup.log 2>&1
```

樹木照片存於 Cloudinary（雲端），DB 備份即涵蓋主要資料。

### 3.13 建置並分發 APK

```bash
cd frontend
flutter build apk --release \
  --dart-define=API_BASE_URL=https://<你的網域>/api
# 自簽憑證主機才需要：--dart-define=SELF_SIGNED_TRUSTED_HOSTS=<host>
```

APK 給調查員安裝；**不含**任何個人金鑰或 token。最後跑一輪 `VERIFICATION_CHECKLIST.md`。

---

## 4. 設定檔位置（App）

檢查 `lib/config/app_config.dart` 與建置時 `dart-define`，確保實驗室可改 API 位址而無需改程式碼。

---

## 5. 管理用 Web UI（**已決定 defer，非必做**）

> 2026-06 決議：App 內建管理後台（admin 頁）已涵蓋使用者/邀請碼/專案管理需求，
> 獨立瀏覽器版 Web portal **刻意不做**；未來若有需求，建議用 React-Admin/Refine 接現有 REST+JWT，非手刻。

教授／管理員需要**不改程式**即可：

| 功能 | 說明 |
|------|------|
| 使用者與邀請碼 | 建立調查員、重設密碼、停用帳號 |
| 專案與專案區 | CRUD `projects` / `project_areas` |
| 專案邊界 | 地圖檢視／匯入 GeoJSON／觸發建議邊界 |
| 待測量 / 樹木資料 | 查詢、匯出 CSV、修正錯誤列 |
| 系統設定 | ML URL、備份、CORS、維護模式 |

**建議技術**：後端同 repo 加 `admin-portal/`（React/Vue）或輕量 `ejs` 管理頁，共用既有 JWT + `requireRole('業務管理員')` API。

**優先順序**：P0 使用者+邀請 → P1 專案/邊界檢視 → P2 資料庫備份與匯出。

---

## 6. 備份與還原

- 每日 `pg_dump` 實驗室 DB
- 上傳樹木影像目錄一併備份
- 文件化還原：`psql` + migrate 版本號

---

## 7. 與本輪程式修復的關係

部署新版本後請執行 `docs/VERIFICATION_CHECKLIST.md` 全部勾選一次。
