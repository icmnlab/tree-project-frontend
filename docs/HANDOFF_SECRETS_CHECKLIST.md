# 交接前必換清單（機密 / 個人化設定）

> 目的：交接給下一棒（或建立專用帳號）前，把**所有跟原作者本人綁定**的金鑰、網址、帳號替換成接手者自己申請的。
> 原則：GitHub 只放程式碼與文件；真實金鑰一律放 `.env`（已被 `.gitignore` 忽略）或本機檔，另行加密交付。

---

## A. 必須「輪替/重新申請」的金鑰（曾寫在 `.env` 類檔，視為已外洩）

下列服務的金鑰請到各平台**作廢舊的、申請新的**，填入新的 `.env`：

| 服務 | 用途 | 變數（在 `backend/.env`） | 申請處 |
|------|------|--------------------------|--------|
| PostgreSQL | 資料庫 | `DB_PASSWORD` / `DATABASE_URL` | 自架 DB 重設密碼 |
| JWT | 登入簽章 | `JWT_SECRET` | `openssl rand -hex 64` |
| Cloudinary | 樹木照片 | `CLOUDINARY_API_KEY` / `_API_SECRET` | cloudinary.com |
| PlantNet | 樹種辨識 | `PLANTNET_API_KEY` | my.plantnet.org |
| Gemini / OpenAI / Claude / SiliconFlow | AI 功能（選用） | `GEMINI_API_KEY` 等 | 各 AI 平台 |
| ML Service | 後端↔ML 驗證 | `ML_API_KEY`（backend + ml_service 兩邊一致） | 自訂字串 |
| Admin Token | 部署診斷 | `ADMIN_API_TOKEN` | 自訂字串 |
| GitHub Webhook | 自動部署 | `DEPLOY_WEBHOOK_SECRET` | GitHub repo webhook 設定 |
| Kaggle / Roboflow | ML 訓練資料（選用） | `KAGGLE_KEY` / `ROBOFLOW_API_KEY`（`ml_service/.env`） | kaggle.com / roboflow.com |
| Google Maps | 地圖 | `GOOGLE_MAPS_API_KEY`（`android/key.properties`） | Google Cloud Console，須綁 package + SHA-1 |

> 範本：`backend/.env.example`、`backend/ml_service/.env.example`、`android/key.properties.example`。

---

## B. 必須「改成自己主機」的個人化網址 / IP

| 位置 | 目前值（原作者） | 交接時改成 |
|------|------------------|------------|
| `frontend/lib/config/app_config.dart` → `defaultBaseUrl` | `https://richardhualienserver.tail124a1b.ts.net/api` | 接手者後端網址；或清空，改用 `--dart-define=API_BASE_URL=...` |
| `frontend/lib/main.dart` → `SelfHostedHttpOverrides` | 信任 `100.118.203.75`、`100.81.214.9`、`*.ts.net` | 移除個人 Tailscale IP；`.ts.net` 規則視新部署是否續用 Tailscale 決定保留與否 |
| `backend/.env` → `ML_SERVICE_PUBLIC_URL` | 原作者 Tailscale / ngrok | 新 ML 主機位址 |
| 文件中的 Tailscale 主機名 / SSH IP | `richardhualienserver`、`kyleliu@100.118.203.75` | 新主機；見 `UBUNTU_SSH_ACCESS.md` |

> 前端連線方式：`flutter run --dart-define=API_BASE_URL=https://新主機/api`（不帶則用程式內 `defaultBaseUrl`）。

---

## C. 必須「換成接手者帳號」的服務 / 倉庫

| 項目 | 目前 | 交接動作 |
|------|------|----------|
| GitHub repo | `KyleliuNDHU/tree-project-backend`、`tree-project-frontend` | 轉移所有權或 fork 到接手者帳號，更新 remote 與 webhook |
| Tailscale tailnet | `KyleliuNDHU@` | 接手者建立自己的 tailnet 或建立專用帳號 |
| 伺服器 Linux 帳號 | `kyleliu@`（Ubuntu） | 建立接手者帳號與 SSH 公鑰 |
| 種子使用者 | `backend/database/initial_data/users.pg.sql` 內含真實姓名 + bcrypt | 全新部署請改用新的管理員種子帳密 |

---

## D. 交接時建議建立「專案專用帳號」（取代個人帳號）

為避免綁定個人，建議申請一組**專案專用**帳號（如 `tree-project@…`）來持有：GitHub、Tailscale、Cloudinary、PlantNet、各 AI 平台、Google Cloud。如此後續交接只需移交該帳號，不必逐一輪替。

---

## E. 本機備份（不進 Git）

| 項目 | 路徑 |
|------|------|
| Android 簽章 | `android/key.properties` + `*.jks` |
| 後端機密 | `backend/.env`、`backend/ml_service/.env` |
| 管理員帳號 / 邀請碼清單 | 後台交付文件 |

自動備份：`cd frontend; powershell -ExecutionPolicy Bypass -File scripts\handoff_backup.ps1`
（輸出 `G:\TreeAI-Handoff\yyyyMMdd_HHmm\`，排除 build 與機密檔）。
