# HANDOFF

接手時建議順序：**[`ONBOARDING_READING_PATH.md`](./ONBOARDING_READING_PATH.md)**（GitHub 怎麼看）→ §1 系統概覽 → **`ARCHITECTURE.md`** → §4 本機啟動 → §5 測試 → §8 領域重點。本機必建檔案見 **`LOCAL_DEVELOPER_SETUP.md`**；Play 上架見 **`ANDROID_RELEASE_AND_PLAY_STORE.md`**。正式環境部署見 `LAB_DEPLOYMENT_GUIDE.md`（需到校/VM）；金鑰與帳號見 `HANDOFF_SECRETS_CHECKLIST.md`。

**最後修訂**：2026-06-29。

---

## 0. 版權與主要貢獻者

本專案**原始開發與交接前主要維護**由 **KyleliuNDHU**（GitHub）完成，涵蓋前後端應用、PostgreSQL schema 與 migration、BLE／碳匯／邊界等核心功能、測試框架，以及 `docs/` 交接文件與選用的 `ml_service/` 視覺 DBH 管線。

| 項目 | 說明 |
|------|------|
| **授權** | MIT License；著作權人見 `LICENSE`（`Copyright (c) 2025 KyleliuNDHU`） |
| **歸屬文件（不可刪）** | **`AUTHORS.md`**、**`LICENSE`** |
| **推送至接手方 GitHub** | **建議 fresh snapshot**（`git checkout --orphan`），**不帶舊 commit 歷史**，避免開發期私有資訊外洩；步驟見 `LAB_DEPLOYMENT_GUIDE.md` §0.1 或 `scripts/prepare_fresh_handover.ps1` |
| **貢獻證明** | 接手方 repo 歸屬以 **`AUTHORS.md` + `LICENSE`** 為準（GitHub `icmnlab` 目前僅顯示一位 contributor，符合 fresh snapshot）；交付方本機私人封存完整 `git log` |
| **接手方義務** | 依 MIT 可修改程式碼，但**須保留** `LICENSE` 版權聲明與歸屬文件；刪除或偽造歸屬違反授權條款 |

> 本節釐清**著作權與開發歸屬**；維運責任、主機與 API 金鑰自交接日起由接手方負責（見 `HANDOVER_CHECKLIST.md`、`HANDOFF_SECRETS_CHECKLIST.md`）。

---

## 1. 這是什麼系統

**永續碳匯樹木管理系統（Sustainable TreeAI）**：通用的樹木調查與碳匯管理系統（目標使用單位：國立東華大學環境學院）。
庫內的港務造林地資料只是開發/CI 測試資料（後端 repo 的 `dev-fixtures/`），正式上線**不會**匯入，系統也沒有針對該批資料的特殊邏輯。

- **前端**：Flutter App（Android 為主），現場調查、地圖、BLE 連 VLGEO2 測樹儀、AI 助理。
- **後端**：Node.js + Express + PostgreSQL，提供 API、整批/現場量測資料寫入、專案/邊界/碳匯計算。
- **ML 服務（選用）**：樹幹偵測 / 深度估計代理（獨立服務，後端透過 `ML_SERVICE_URL` 代理）。

### Repository layout

本專案以**兩個獨立 Git repository** 交付；clone 後請分別在各自 repo 根目錄執行建置與部署（§4）。

| Repository | 內容 |
|------------|------|
| `<GITHUB_OWNER>/tree-project-frontend` | Flutter App；交接文件位於 `docs/`（含本檔） |
| `<GITHUB_OWNER>/tree-project-backend` | Node.js API、PostgreSQL migrations、`ml_service/`（選用 ML） |

---

## 2. 目錄結構

以下以各 repository **根目錄**為準（clone 後資料夾名稱通常與 GitHub repo 名稱相同）。

### 2.1 後端（`tree-project-backend`）

```
tree-project-backend/           # repo 根目錄
├── app.js                      # 入口；prod 開機自動跑 pending migration
├── routes/ services/ middleware/ config/
├── database/initial_data/*.pg.sql   # schema/migration SQL（依序）
├── scripts/                    # migrate.js / run_pending_migrations.js / deploy.sh ...
├── dev-fixtures/               # 開發/CI 用種子（tree_survey_data.csv 等）
├── ml_service/                 # 選用 ML 服務（Python / FastAPI）
├── tests/                      # 整合測試框架（runner.js + invariants/journeys/contracts）
└── .github/workflows/ci.yml    # 後端 CI
```

### 2.2 前端（`tree-project-frontend`）

```
tree-project-frontend/          # repo 根目錄
├── lib/                        # screens/ services/ widgets/ models/ config/
├── docs/                       # 交接文件（含本檔）
├── test/                       # 單元/Widget 測試（flutter test）
└── .github/workflows/ci.yml    # 前端 CI
```

---

## 3. 環境需求

| 項目 | 版本 |
|------|------|
| Node.js | 18+（CI 用 18；prod 建議 20 LTS） |
| PostgreSQL | 15+ |
| Flutter | stable（Dart SDK `>=3.0.0 <4.0.0`） |
| Python / CUDA | 僅 ML 服務需要（選用） |

### 3.1 接手開發者要「自己安裝／自己建立」的東西（清單＋規則）

> 原則：**程式碼進 git；金鑰、密碼、簽章、本機路徑不進 git**（`.gitignore` 已涵蓋 `.env`、`key.properties`、`*.jks`）。
> 下列每人各自一份，不要互傳、不要 commit。

**A. 要安裝的工具**
| 工具 | 用途 | 備註 |
|------|------|------|
| Git for Windows | 版控 + 認證 | 內含 Credential Manager（首次 push 跳瀏覽器登入自己的帳號） |
| Flutter SDK + Android Studio | 跑 App | 含 Android SDK、JDK17；`flutter doctor` 全綠 |
| **Windows 開發人員模式** | Flutter plugin 需要 symlink | `設定 → 系統 → 開發人員選項` 開啟，或執行 `start ms-settings:developers` |
| Node.js 20 LTS | 後端（要本機跑後端才需要） | |
| PostgreSQL 15+ | 後端 DB（連遠端 DB 則免裝） | |

**B. 要自己「打 / 建立」的設定（每人一份，不進 git）**
| 項目 | 在哪 | 怎麼設 | 規則 |
|------|------|--------|------|
| Git 身分 | 全域 | `git config --global user.name/user.email`（填自己的） | commit 會掛自己名字 |
| GitHub 認證 | 首次 push | 跳瀏覽器登入自己帳號；或帳號+PAT | 需先被加為 `icmnlab` collaborator |
| 自己的 Google Maps 金鑰 | Google Cloud `tree-project` | 見 `HANDOFF_SECRETS_CHECKLIST.md` §H | 綁「套件名 `com.sustainable.treeai` + 自己的 debug SHA-1」 |
| debug keystore | `~/.android/debug.keystore` | 首次 build 自動產生，或手動 `keytool -genkeypair`（見下） | 用來取 SHA-1 |
| 前端 `android/key.properties` | 前端 repo | **debug 只需 `GOOGLE_MAPS_API_KEY=` 一行**；release 才加簽章欄 | 不進 git |
| 後端 `.env` | 後端 repo | 由 `.env.example` 複製，填 `DATABASE_URL`、`JWT_SECRET`（`openssl rand -hex 64`）等 | 不進 git；機密放這裡 |

**C. 規則**
- 機密一律放 `.env` / `key.properties` / 密碼管理器，**永不 commit**。
- 分支：從 `main` 開 `feat/*`，PR 合回（見 §6.3）。
- 每人用**自己的** GitHub 帳號與 Maps 金鑰（SHA-1 綁自己的 keystore）。

> 手動建立 debug keystore（若首次 build 前就想取 SHA-1）：
> ```powershell
> & "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v `
>   -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android -keypass android `
>   -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 `
>   -dname "CN=Android Debug,O=Android,C=US"
> ```

---

## 4. 本機跑起來

### 4.1 後端

在 **後端 repository 根目錄**（`tree-project-backend/`）執行：

```bash
cp .env.example .env          # 填 DATABASE_URL（或 DB_*）、JWT_SECRET、CORS
npm ci
node scripts/migrate.js       # 全新空庫：建 schema（不含使用者；可選 dev-fixtures CSV）
node scripts/seed_dev_users.js   # 開發／CI 專用：建立 admin/12345 等測試帳（勿用於 production）
npm start                     # http://localhost:3000  （/health 可測活）
```
- 本機若連「無 SSL」的 Postgres，`.env` 設 `DB_SSL=false`。
- `migrate.js` 是「全新空庫」用（會匯入 `dev-fixtures/tree_survey_data.csv`，約 7000 筆港務測試樹）；
  不想匯入測試樹設 `SKIP_CSV_IMPORT=1`。**正式環境永遠不要跑 `migrate.js`**（見 §6）。

### 4.2 前端

在 **前端 repository 根目錄**（`tree-project-frontend/`）執行：

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://<後端IP>:3000/api
```
API 位址由建置期 `--dart-define=API_BASE_URL` 注入（見 `lib/config/app_config.dart`），不要寫死。

### 4.3 首次建置檢查

開發機（兩 repo 皆需 clone）：

- [ ] 後端：`npm ci` → `migrate.js` → `seed_dev_users.js` → `npm start` → `GET /health` 回 200
- [ ] 前端：`flutter pub get` → `flutter run --dart-define=API_BASE_URL=http://<後端IP>:3000/api` → 以 `admin` / `12345` 登入
- [ ] 前端：`flutter test` 通過（435）
- [ ] 後端（選用）：`node tests/runner.js --list` 可列出整合測試

實驗室／正式主機勿使用 `seed_dev_users.js`；依 `LAB_DEPLOYMENT_GUIDE.md` §0 部署，管理員以 `create_lab_admin.js` 建立。部署後依 `VERIFICATION_CHECKLIST.md` 驗收。

### 4.4 接續開發時的主路徑

現場 BLE 寫庫路徑（維護與除錯時優先熟悉）：

```
BleLiveSessionPage → POST /api/pending-measurements/...
  → IntegratedTreeFormPage → POST /api/pending-measurements/transfer
  → tree_survey + tree_survey_measurements
```

| 層 | 檔案 |
|----|------|
| 前端畫面 | `lib/screens/ble_live_session_page.dart` |
| 前端 API | `lib/services/pending_measurement_service.dart` |
| 後端路由 | `routes/pending_measurements.js` |

手動新增與編輯見 §8.1；現場操作見 `FIELD_SURVEY_SOP.md`。

---

## 5. 測試與 CI

### 5.1 後端整合測試（`tests/runner.js`）

在**後端 repository 根目錄**執行。針對「跑起來的 server + DB」做契約/旅程/不變式測試，每個 case 自建資料並清理。
```bash
# 需要：一個已 migrate 的 DB + 一個正在跑的 server
$env:TEST_BASE_URL="http://localhost:3001/api"   # PowerShell
node tests/runner.js                 # 全部
node tests/runner.js --section=contracts
node tests/runner.js --list          # 只列出 case
```
- 預設登入 `admin/12345`（需先跑 `seed_dev_users.js`；**正式庫**用 `create_lab_admin.js` 自建管理員，並在 `.env` 或 CI 設 `TEST_ADMIN_USER`/`TEST_ADMIN_PASS`）。
- 需直連 DB 的 invariants 用 `TEST_DB_URL`（或 `DATABASE_URL`）；沒設則自動 skip。
- 寫測試規範見後端 repo 的 `tests/FRAMEWORK.md`。

### 5.2 前端測試

在**前端 repository 根目錄**執行：

```bash
flutter test                 # 全套（目前 435 pass）
```

### 5.3 CI（GitHub Actions，push / PR 觸發）
| Repo | Workflow | 內容 |
|------|----------|------|
| `tree-project-backend` | `.github/workflows/ci.yml` | 起 `postgres:15` → `migrate.js` → `seed_dev_users.js` → 啟 server → `tests/runner.js`（**89 cases**） |
| `tree-project-frontend` | `.github/workflows/ci.yml` | `flutter pub get` → `analyze`（advisory）→ `flutter test`（435 pass） |

完整開發流程（分支、PR、CI 門檻）：**`DEVELOPMENT_WORKFLOW.md`**。

CI 專用環境變數（在 workflow 內設，正式環境**不要**設）：
- `DB_SSL=false`：連 CI 的無 SSL Postgres。
- `DISABLE_RATE_LIMIT=true`：localhost 大量請求不被限流／IP 黑名單擋。
- `OPENAI_API_KEY` / `GEMINI_API_KEY`=dummy：避免模組載入即建 AI client 而崩潰（見 §9 故障排除）。

---

## 6. 部署（正式環境）

正式機在 `/opt/tree-app/backend`，以 **PM2** 跑 process `tree-backend`（port 3000）。

### 6.1 自動部署（GitHub webhook）
push 到 `main` → GitHub webhook 打 `POST /webhook/deploy`（HMAC 用 `DEPLOY_WEBHOOK_SECRET` 驗簽）→ 執行 `scripts/deploy.sh`：
1. 記錄當前 commit 當 rollback 點
2. `git pull origin main`
3. `npm install --production`
4. **增量** migration：`node scripts/run_pending_migrations.js`（不重新 COPY CSV）
5. `pm2 reload tree-backend`（zero-downtime）
6. `/health` 驗證，失敗自動 rollback

部署日誌：`/opt/tree-app/logs/deploy.log`（`GET /webhook/status` 可看尾段，需 `ADMIN_API_TOKEN`）。

### 6.2 手動部署 / 排錯
```bash
ssh <lab-host>
cd /opt/tree-app/backend
./scripts/deploy.sh              # 正常（pull + 增量 migration + reload）
./scripts/deploy.sh --dry-run    # 只拉取不重啟
pm2 logs tree-backend            # 看後端 log
pm2 reload tree-backend          # 手動重載
```

> **migrate.js vs run_pending_migrations.js**
> - `migrate.js`：全新空庫一次建好（含 CSV）。**只用於開發/CI/全新庫**。
> - `run_pending_migrations.js`：用 `schema_migrations` 表只跑新增量。**正式部署一律走這支**。
> - 兩支共用 `migrationFiles` 清單；新增 migration 請加進 `scripts/migrate.js` 的清單並照編號排序。

### 6.3 Git 協作流程（分支與 PR）

採 **GitHub Flow**（小團隊最簡單、業界常用）：`main` 永遠保持可部署，功能在短命分支開發、用 PR 合回。

**分支規則**
- 長期分支只有 **`main`**（受保護：需 PR + CI 綠燈才能合、禁止 force push）。
- 功能分支**由開發者自己在要動工時才開**，不需事先建一堆空分支。命名：`feat/xxx`、`fix/xxx`、`chore/xxx`。

**帳號與權限**
- 每位開發者用**自己的 GitHub 帳號**；由 repo 擁有者（`icmnlab`）在 **Settings → Collaborators** 把他加為協作者（Write）。
- 推送後 **commit 會標記各自的作者身分**（誰寫的就掛誰），歷史貢獻不會被覆蓋。

**新成員第一次設定（onboarding，一次性）**
```bash
# 1) 設定自己的 git 身分（顯示在 commit 上）
git config --global user.name  "你的名字"
git config --global user.email "你的GitHub信箱"

# 2) 認證 GitHub（用 Git 內建 Credential Manager，不需安裝 gh）
#    安裝「Git for Windows」即內含 Git Credential Manager。
#    第一次 git clone / git push 私有操作時，會自動跳出瀏覽器 → 登入自己的 GitHub 帳號 → 完成。
#    （憑證會存進 Windows「認證管理員」，之後免再登入。）
#
#    若沒跳瀏覽器、出現帳密輸入：帳號填自己的 GitHub 名稱、密碼貼 Personal Access Token
#      （PAT 申請：GitHub → Settings → Developer settings → Personal access tokens，勾 repo 權限；不要用登入密碼）。
#    要換成別的帳號：控制台 → 認證管理員 → Windows 認證 → 刪除 git:https://github.com，下次操作會重新登入。
#    （選用）若已裝 GitHub CLI，也可改用 gh auth login；沒裝就用上面瀏覽器登入即可。

# 3) clone 專案（接受 collaborator 邀請後）
git clone https://github.com/icmnlab/tree-project-backend.git
git clone https://github.com/icmnlab/tree-project-frontend.git

# 4) 之後依本檔 §4「本機跑起來」安裝相依、建 .env / key.properties
```

**標準流程**
```bash
git checkout main && git pull origin main      # 先同步最新
git checkout -b feat/ble-export                 # 開功能分支
# ...改程式、commit...
git add -A && git commit -m "feat: BLE 量測匯出 CSV"
git push -u origin feat/ble-export              # 推分支
# 到 GitHub 開 Pull Request → CI 跑測試 → review → Merge 進 main
git checkout main && git pull                    # 合併後本地同步
git branch -d feat/ble-export                     # 刪掉已合併的本地分支
```

**常用 git 操作**
```bash
git status                       # 看當前變更
git log --oneline -10            # 看近期提交
git diff                         # 看未暫存的差異
git pull origin main             # 同步遠端
git stash / git stash pop        # 暫存未完成的修改去切分支
git restore <file>               # 丟棄某檔的本地修改
```

> 有設部署 webhook 時：**只有合併進 `main` 會觸發正式機部署**；功能分支與 PR 不會。

**第一次 push 常見狀況**（用 feature branch 就安全）：瀏覽器登入、403 權限、PAT — 見 `DEVELOPMENT_WORKFLOW.md` §「First push — scenarios」。**不要**第一次就推 `main`；`git checkout -b chore/...` → push → PR 為標準做法。

---

## 7. 環境變數速查（後端）

完整範本見後端 repo 的 `.env.example`。重點：

| 變數 | 必要性 | 說明 |
|------|--------|------|
| `DATABASE_URL`（或 `DB_HOST/PORT/NAME/USER/PASSWORD`） | 必要 | DB 連線 |
| `JWT_SECRET` | 必要（prod 開機檢查） | 登入簽 JWT；`openssl rand -hex 64` |
| `PORT` | 選用 | 預設 3000 |
| `NODE_ENV` | 選用 | `production` 才會開機自動 migration + 嚴格 env 檢查 |
| `CORS_ALLOWED_ORIGINS` | 建議 | 逗號分隔來源白名單 |
| `DB_SSL` / `DB_SSL_REJECT_UNAUTHORIZED` / `PGSSLMODE` | 選用 | SSL 控制（見 `config/pgSsl.js`） |
| `DEPLOY_WEBHOOK_SECRET` / `ADMIN_API_TOKEN` | 部署用 | webhook 驗簽 / 部署狀態查詢 |
| `ML_SERVICE_URL` / `ML_SERVICE_PUBLIC_URL` / `ML_API_KEY` | ML 用 | ML 代理 |
| `CLOUDINARY_*`（三項） | 照片用 | 樹木影像儲存 |
| `OPENAI_API_KEY` / `GEMINI_API_KEY` / `Claude_API_KEY` / `PLANTNET_API_KEY` / `GOOGLE_CSE_*` | 選用 | AI / 樹種辨識 / 搜尋；未設則對應功能停用 |
| `SKIP_CSV_IMPORT` | 選用 | `migrate.js` 是否跳過匯入測試樹（正式庫建議 1） |

前端：`--dart-define=API_BASE_URL=...`、`--dart-define=ML_SERVICE_URL=...`（見 `lib/config/app_config.dart`）。

---

## 8. 資料模型與領域重點（指路）

### ⚠️ 詞彙對照表（必讀，2026-06-11 全面換詞）

依會議決定，**畫面顯示詞彙**已全面改為「專案/區」二層；**程式碼、資料庫、API 鍵一律未改**。維護時務必對照：

| 畫面詞（新） | 舊畫面詞 | 程式 / DB / API（不變） | 英文 UI |
|---|---|---|---|
| **專案**（上層） | 區位／專案區位 | `project_areas`、`area_name`、JSON 鍵 `專案區位`、`project_location` | Project |
| **區**（下層） | 專案 | `projects`、`project_code`、JSON 鍵 `專案名稱`／`專案代碼`、`project_name` | Block |

- 也就是說：程式裡的 `project`/`專案名稱` 對應畫面上的「**區**」；`area`/`專案區位` 對應畫面上的「**專案**」。
- **角色名稱不在換詞範圍**：`專案管理員` 等五個角色是 DB 值，維持原字。
- 後端回傳的中文錯誤訊息仍可能用舊詞（顯示頻率低，列為接手者待辦）。

### 8.1 四種新增與一種編輯（寫庫路徑）

| 路徑 | APP 入口 | 畫面 | API | 歷次量測 |
|------|----------|------|-----|----------|
| VLGEO2 現場連線 | 首頁「現場連線」 | `BleLiveSessionPage` → `IntegratedTreeFormPage` | pending → `POST /transfer` | ✅ |
| 藍牙批次／待測量 | 「藍牙匯入」→「待測量任務」 | `BleImportPage` / `PendingMeasurementTaskPage` | 同上 | ✅ |
| 智慧模式 | 樹木調查 → 新增 → 智慧 | `ManualInputPageV3` | `POST /create_v2` | ✅ |
| 快速模式 | 樹木調查 → 新增 → 快速 | `TreeInputPageV2` | `POST /create_v2` | ✅ |
| 編輯 | 樹木詳情 → 編輯 | `TreeEditPageV2` | `PUT /update_v2/:id` | ❌ 刻意不寫 |

**BLE 與手動的差異**：BLE／待測量先寫入 `pending_tree_measurements`，表單完成後 `transfer` 進正式庫。智慧／快速跳過 pending，直接 `create_v2` 寫入 `tree_survey`（並寫首筆歷次）。編輯只更新主檔，不新增歷次；重測請走 BLE 或待測量。

**智慧 vs 快速**：兩者皆走 `create_v2`；智慧（V3）步驟較完整，快速（V2）欄位較精簡。快速模式多送 `tree_remark`／`survey_notes` 分欄（見 `manual_input_page_v3.dart`）。

**程式入口**：

| 模式 | 前端 | 後端 |
|------|------|------|
| 智慧 | `lib/screens/v3/manual_input_page_v3.dart` | `routes/treeSurvey.js` |
| 快速 | `lib/tree_input_page_v2.dart` | 同上 |
| 編輯 | `lib/tree_edit_page_v2.dart` | `update_v2` |
| 共用 HTTP | `lib/services/api_service.dart` 及各 domain service | — |

**欄位對齊**：樹種、座標、樹高、DBH、樹況、碳儲量、生命週期四路一致；BLE 另寫 `tree_measurement_raw` 與歷次 `instrument_*`；手動路徑不寫儀器附表。詳細歷次語意見 `SURVEY_HISTORY.md`。

**ID**：`create_v2` 與 transfer 新樹皆用 `pg_advisory_xact_lock(1)` 產生 `ST-`／`PT-`；trigger 09 補 `project_id`。現場連線每棵 transfer 後以 `id_mapping` 回正式 id（`lib/utils/transfer_result.dart`）。

### 8.2 藍牙：BLE 與 Classic Bluetooth（勿混淆）

| 技術 | APP 是否使用 | 用途 |
|------|-------------|------|
| **BLE**（`flutter_blue_plus`，NUS GATT） | ✅ **唯一實作** | 逐棵 `$PHGF` 量測、整檔 `DATA.CSV` 批次 |
| **Classic Bluetooth SPP**（`VLGEO2_*_COM`，標準 GGA/RMC） | ❌ **未實作** | 僅 `test/vlgeo2_ble_analysis/` 研究腳本；儀器 GPS 串流走此通道 |
| **手機 GPS**（Geolocator） | ✅ 現場正式方案 | 樹旁定位；BLE 逐棵 SEND **不帶** GGA 座標 |

程式內 `BleLiveNmeaAssembler` 名稱易誤解：組裝的是 **BLE 上的 Haglöf `$PHGF` 量測句**，不是 Classic SPP 的衛星 NMEA。見 `VLGEO2_STD_APPLICATION_GUIDE.md` §「藍牙通道」。

### 8.3 領域專門文件

- **資料庫正規化 / schema**：`DATABASE_NORMALIZATION.md`
- **專案邊界系統**（手繪／貼座標／匯入 KML·GeoJSON／convex-hull 建議邊界）：`BOUNDARY_SYSTEM_DESIGN.md`（輸入方式見 §3.5）
- **碳匯計算**：`CARBON_CALCULATION.md`
- **樹種目錄與 PlantNet 辨識**：`SPECIES_AND_PLANTNET.md`（首頁卡預設可見）
- **四種新增輸入 + 編輯寫庫對照**：見本檔 **§8.1**；歷次機制見 `SURVEY_HISTORY.md`
- **VLGEO2 BLE 整合**（NUS、PHGF、CSV；**非** Classic SPP）：`VLGEO2_STD_APPLICATION_GUIDE.md`；解析 `ble_live_packet_decoder.dart` / `ble_data_processor.dart`
- **AI Agent / 文字轉 SQL**：`AI_AGENT_GUIDE.md`（Experimental）
- **實驗功能總覽**（隱藏卡片、build flag）：`EXPERIMENTAL_FEATURES.md`
- **視覺量測 / V3 ML**：`VISUAL_MEASUREMENT.md`（Experimental）
- **AI 永續報告**：`AI_SUSTAINABILITY_REPORT.md`（Experimental）
- **ML 自架（選用）**：後端 repo 的 `ml_service/README.md`（YOLO iGPU + DA3 NPU；`start.ps1 -Preset da3`）

---

## 9. 故障排除（踩過的雷）

| 症狀 | 原因 / 解法 |
|------|------------|
| 後端開機即 `OpenAIError: OPENAI_API_KEY ... missing` 後崩潰重啟 | `routes/ai.js`、`geminiService.js` 在模組載入就建 AI client。prod 要設真金鑰；CI 設 dummy。 |
| 全新空庫 `migrate.js` 在 migration 16 報 `relation "project_boundaries" does not exist` | 已修：`06a_project_boundaries_schema.pg.sql`（schema-only）建表。若再遇到缺表，檢查 `migrationFiles` 順序。 |
| 連本機/CI Postgres 報 SSL 錯 | 設 `DB_SSL=false`（或 `PGSSLMODE=disable`）。 |
| 測試大量 429 / IP 被封 | CI/本機跑 runner 設 `DISABLE_RATE_LIMIT=true`。 |
| 部署後 `/health` 失敗 | `deploy.sh` 會自動 rollback；看 `/opt/tree-app/logs/deploy.log` 與 `pm2 logs tree-backend`。 |
| 維護鎖相關崩潰 | 取 client 用 `db.pool.connect()` 而非 `db.connect()`（曾因此 unhandledRejection 打掛 process）。 |

> 設計決策的「為什麼」記錄在 `CHANGELOG.md`（problem→solution 條目）。

---

## 10. 文件索引

| 文件 | 用途 |
|------|------|
| **`HANDOFF.md`（本檔）** | 快速上手：本機啟動、測試、部署索引 |
| **`ARCHITECTURE.md`** | **程式架構**：功能怎麼跑、對應檔案/API、資料庫 SQL 為何這麼多（歐美常見技術文件風格） |
| **`docs/README.md`** | **文件索引 hub**（Start here、topic 分類、documentation status） |
| **`CODEBASE_INVENTORY.md`** | **程式清單**：129 Dart / 168 JS / 145 API / 13 首頁功能 — 撰寫文件時防遺漏 |
| **`API_REFERENCE.md`** | **REST API 目錄**（依模組分類，歐美常見 API Reference 風格） |
| `AUTHORS.md` | 著作權與主要貢獻者（fresh push 須保留） |
| `LAB_DEPLOYMENT_GUIDE.md` | 實驗室獨立部署（fresh snapshot、webhook、PM2） |
| `BUILD_GUIDE.md` | Android APK 建置 |
| `HANDOFF_SECRETS_CHECKLIST.md` | 金鑰、帳號、網址交接清單 |
| `HANDOVER_CHECKLIST.md` | 交接當日事項 |
| `VERIFICATION_CHECKLIST.md` | 部署後實機驗證 |
| `FIELD_SURVEY_SOP.md` | 現場調查操作（含 BLE 與手動新增） |
| `PROJECT_DATA_AND_DOMAIN.md` | CSV、專案／區語意 |
| `SURVEY_HISTORY.md` | 歷次量測機制 |
| `ADMIN_AND_INVITE_DESIGN.md` | 管理後台與邀請碼 |
| `VLGEO2_STD_APPLICATION_GUIDE.md` | VLGEO2 BLE 整合（見 §8.2） |
| `DATABASE_NORMALIZATION.md` / `BOUNDARY_SYSTEM_DESIGN.md` / `CARBON_CALCULATION.md` / `SPECIES_AND_PLANTNET.md` | 子系統設計 |
| `ML_CORRECTION_UPLOAD.md` | ML 修正紀錄上傳（預設關閉） |
| `AI_AGENT_GUIDE.md` | AI 對話／Agent（Experimental，§12） |
| `EXPERIMENTAL_FEATURES.md` | 實驗 UI 開關與隱藏卡片 |
| `VISUAL_MEASUREMENT.md` | 視覺 DBH、Scanner、V3 ML sync |
| `AI_SUSTAINABILITY_REPORT.md` | AI 永續報告（Experimental） |
| `ML_CORRECTION_UPLOAD.md` | ML 校正資料上傳 |
| `HANDOFF_EXTERNAL_GNSS_AND_BLE.md` | 外接 GNSS 技術存檔（已取消採購） |
| `tests/FRAMEWORK.md`（後端 repo） | 後端整合測試寫法 |
| `ml_service/README.md`（後端 repo） | 選用 ML 服務 |

根目錄 `README.md`（前後端各一）為快速入門與技術棧說明。

> 歷史性分析/舊版交接文件已於 2026-06-11 整理移出 repo（原 `docs/history/`、各 roadmap/計畫文件），備份於專案擁有者本機 `handover_backup_20260611/`。

---

## 11. 待辦與下一步

**交接日**：照 `LAB_DEPLOYMENT_GUIDE.md` §0「交接日流程」一次做完（fresh push → 金鑰輪替 → 部署 → webhook → 驗收）。

> 詳細開發流水帳（每輪改了什麼、commit）在開發者本機的 `WORK_STATUS.md`，不隨 repo 交付。下列為交接者真正需要知道的**未決項**。

### 11.1 需先決策才實作（牽涉需求／權限／資料模型）

| 項目 | 現況 | 待決定 |
|------|------|--------|
| 「待維護」跨場/跨天的判定 | 目前僅單場記憶體集合；資料面 `tree_survey_measurements.survey_time` 已就緒（不需改 schema） | 門檻 N（碳匯年度盤點常用 12 個月）、是否對齊到「區」層級 |
| 歷次紀錄的編輯／刪除 | 歷次目前唯增（量測=不可竄改）；CSV/手動編輯刻意不寫歷次 | 是否開放編輯軌跡（需新 API + 權限） |
| 邊界輸入「方式 2（含座標圖檔）」 | UI 預留「即將推出」；GeoTIFF/世界檔未實作 | 待學院提供範例檔再評估 |

### 11.2 開放工程待辦（非阻擋，依效益）

- `GET /projects` 合併「只有邊界、無 `projects` 列」的專案，讓前端各頁移除 client-side merge。
- 重疊邊界時的使用者選擇 UX（目前多邊形相交取第一個）。
- 效能：`map/meta`、`project_areas` 依縣市查詢為全表掃描 → 預聚合/快取（地圖 marker 已做 viewport 剔除＋聚合）。
- 弱網離線佇列（pending／照片 dedup）。
- Staging + `FIXTURE_PROJECT_CODE` harness，讓環境相依測試不再 SKIP。
- 平台/建置警告清理：Flutter Kotlin Built-in 遷移、Impeller opt-out deprecated。
- 長期資料模型演進：邊界主鍵改 `project_code`、`tree_survey` 反規範快取欄漸進 VIEW 化（見 `DATABASE_NORMALIZATION.md`）。

### 11.3 已知限制／小債（交接者須知）

- **AI Agent／對話**：預設停用、首頁入口隱藏；穩定版不依賴、缺金鑰不影響其餘功能（見 `AI_AGENT_GUIDE.md`）。
- **Admin API 金鑰**：休眠功能，`validateApiKey` 未被任何路由呼叫，全站走 JWT（見 §12）。
- **系統管理員與 `user_projects`**：`seed_dev_users.js`／`create_lab_admin.js` **皆不**寫入 `user_projects`；使用者管理 UI 顯示「關聯專案／區」為空屬**預期**。API 層 `projectAuthFilter` 對 `系統管理員`、`業務管理員` bypass，不需手動指派區。僅 `調查管理員`、`專案管理員` 等需 `user_projects`。
- **地圖 → 樹木詳情欄位全「無」**（2026-06-30 現場重現路徑）：**現場量測**填表提交 → 轉入 `tree_survey` → 從**地圖頁**點新樹 marker →「查看完整詳情」。根因：`GET /api/tree_survey/map` 為效能只回 id、座標、樹種名等**精簡欄位**（見 `routes/treeSurvey.js` `/map` SELECT）；詳情頁若未 refetch 會全「無」。已修：`tree_survey_detail_page.dart` 進頁 `GET /tree_survey/by_id/:id`（PR #1 **`47d8cff` 已 merge**）；**需新 APK**。若 refetch 後樹高／胸徑仍「無」，查 DB `dbh_cm`/`tree_height_m` 是否 NULL（transfer 未寫入量測）。診斷 SQL：本機 `project_code/docs/DEPLOYMENT_LOG.md` §G.1、§K。
- **ST-1 樹種編號顯示「無」**（2026-06-30 正式空庫現場）：量測 ST-1～ST-3 後，詳情**樹種名稱**可能有值，**樹種編號**「無」。根因：transfer 僅用 `species_name` 精確查 `tree_species`，未 `toTraditional`、未查 `species_synonyms`。**非阻擋交接**；修復 runbook（optional）：`DEVELOPMENT_WORKFLOW.md` §Guided exercise；本機 ops §K、§M.5。
- **維護轉移覆寫 `tree_survey`**：對「web 編輯 vs 現場轉移並行」無樂觀鎖；設計上**現場儀器值優先**，列為觀察。
- **外接 GNSS**：已決議不採購、不續做；現場 GPS 一律手機樹旁取樣（見 `HANDOFF_EXTERNAL_GNSS_AND_BLE.md`）。
- 後端測試有 1 個 `four_bugs` TODO 案 skip（非阻擋）。
- 偶發 UI：進地圖頁極偶發 controller disposed race（未能穩定重現）；少數 RenderFlex overflow 視覺警告待 DevTools 定位。

### 11.4 真人／硬體驗證（無法自動化）

藍牙實機收 PHGF、雙機同場（維護鎖 409、`expected_updated_at` 樂觀鎖）、相機／視覺 DBH、T4 等 — 見 `VERIFICATION_CHECKLIST.md`。可自動化者已轉測試（§0.0「已自動化覆蓋」對照表），實機可降為抽查。

---

## 12. 保留但未掛載／實驗性功能（給後續開發者）

交接原則：**正式現場 APK 預設只暴露穩定功能；實驗性入口保留程式碼，預設從首頁隱藏**（見 `lib/config/app_config.dart`、`BUILD_GUIDE.md` 的 `ENABLE_EXPERIMENTAL_UI`）。

### 12.1 首頁預設隱藏的儀表板卡片

`ENABLE_EXPERIMENTAL_UI=false`（**預設**）時隱藏：`test_scan`、`ai`、`report`、`v3`。  
設為 `true` 建置後四卡恢復；AI／報告另需後端 LLM 金鑰。樹種辨識（`species`）不受此旗標影響。

| 功能 | 程式碼位置 | 狀態 |
|------|-----------|------|
| AI 對話（樹木問答） | `screens/ai_chat_page.dart`、`routes/ai.js` | **程式保留**；首頁卡預設隱藏；見 `AI_AGENT_GUIDE.md` |
| AI 永續報告 | `/ai-sustainability-report`、`routes/ai.js` | **程式保留**；首頁卡預設隱藏；見 `AI_SUSTAINABILITY_REPORT.md` |
| 視覺 DBH（純視覺量測） | `scanner_page.dart`、`pure_vision_dbh_service.dart`、`ml_service/` | **整合表單/編輯內可用**；首頁「掃描測試」卡預設隱藏；見 `VISUAL_MEASUREMENT.md`、`DBH_PURE_VISION_RESEARCH.md` |
| AR 量測 | `services/ar_measurement_service.dart`、`services/v3/ar_measurement_integration_service.dart`（零引用，整合範例） | 程式碼保留，未主打 |
| WebSocket 即時掃描 | `services/scanner_service.dart`（零引用；對接 ml_service `/ws/scan`） | 程式碼保留，未掛載 |
| ML 訓練資料收集 | 後端 `routes/ml_training_data.js` | 保留 |
| 研究資料集（DBH 校準） | `routes/research_dataset.js`、`admin_research_dataset_page.dart` | **系統管理員限定**；捲尺實測周長+拍攝距離+照片，供距離偏差 α,β 校正與 leakage-free 評估集；研究階段，配合 `DBH_PURE_VISION_RESEARCH.md` |
| 樹木調查頁（unscoped 模式） | `tree_survey_page.dart` | 底部分頁已移除（與列表重疊）；**保留**供專案/區下鑽與首頁「樹木調查」卡片使用 |
| 自動多邊形邊界建議 | 後端 boundarySuggest | 通用功能、需使用者確認後才寫入 |
| 邊界輸入（貼座標 / 匯入 KML·KMZ·GeoJSON / .txt·.csv 座標檔） | `boundary_input.dart` / `boundaryImport.js` / `POST /project-boundaries/import` | 預覽→確認→儲存；TWD97/TM2 自動轉 WGS84；.txt/.csv 由前端 `boundary_input.dart` 解析；方式 2（含座標圖檔）UI 預留 |
| 邊界匯出 KML | `GET /project-boundaries/export.kml` / `download_service.dart` | 邊界頁右上「匯出 KML」；可用 Google Earth 開啟、再匯入讀回 |
| 樹木生命週期（淘汰/復原） | `tree_survey.lifecycle_status` / `utils/treeLifecycle.js` / `POST /tree_survey/:id/retire`·`/restore` | 淘汰木不計入活立木碳匯（見 `CARBON_CALCULATION.md`）；保留歷史/照片；可復原 |
| 樹況選單目錄（內建+自訂可共享） | `tree_status_options`（migration 33） / `routes/tree_statuses.js` / `services/tree_status_service.dart` | 新增/維護表單動態下拉；可自打新狀況寫回共用選單；`lifecycle` 決定是否活立木（枯立木=dead） |
| 照片歷史 | `tree_images.measurement_id` / `GET /tree-images/tree/:id?measurement_id=`·`?latest=1` | 各次量測照片綁定該次歷史；歷史面板逐次縮圖、詳情頁顯示最新照 |
| API 密鑰（admin 產生/列表/刪除） | `routes/admin.js` `/apikeys` / `config/apiKeys.js` | **休眠功能**：`validateApiKey` 未被任何路由/中介層呼叫，產生之金鑰目前無驗證效力（全站走 JWT）。交接後若需對外程式化存取，須實作 `apiKeyAuth` 中介層；否則建議移除 admin 入口 |
| 年碳吸存推估 | `tree_survey_measurements` 歷次快照已就緒（含 create_v2 首筆） | 演算法（存量差分）待累積多期資料後實作，見 `CARBON_CALCULATION.md` |

已刪除（被新版完全取代的死碼，不建議復活）：V1 手動輸入頁（被 V3 整合表單取代）、`/ai-assistant` 重複路由、`ble_live` 死分支。
