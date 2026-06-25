# 獨立部署指南（實驗室 / 自有主機）

> 目標：在自有主機上獨立建置並運行整套系統，**不依賴任何特定個人的 GitHub／雲端帳號**。

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
