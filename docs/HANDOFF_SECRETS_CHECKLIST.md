# 機密與環境設定指南（Secrets & Environment Setup）

> 本系統所有金鑰、主機位址、帳號都以**環境變數／設定檔**提供，不寫死在程式碼裡。
> GitHub 只放程式碼與文件；真實金鑰一律放 `.env`（已被 `.gitignore` 忽略）或本機設定檔。
>
> 本指南說明「需要設定哪些、各放在哪裡、去哪裡申請」。依此設定即可讓系統在任何新環境完整運作。
> 範本檔：`backend/.env.example`、`backend/ml_service/.env.example`、`frontend/android/key.properties.example`。

---

## A. 第三方 API 與服務申請指南（交接者逐項申請，填進 `backend/.env`）

> 流程：到平台註冊帳號 → 取得金鑰 → 貼進 `backend/.env`（複製自 `.env.example`）對應變數。
> 建議用「單位／專案專用帳號」申請（見 §D），日後人員異動只需移交帳號。

### A-1 必要（不設則系統無法正常運作）

| 服務 | 用途 | `.env` 變數 | 去哪申請 / 產生 | 備註 |
|------|------|-------------|-----------------|------|
| PostgreSQL（自架） | 主資料庫 | `DATABASE_URL` 或 `DB_*` | 部署主機自建（不需向外申請） | 建庫見 `LAB_DEPLOYMENT_GUIDE.md` §3.3 |
| JWT（自產） | 登入 token 簽章 | `JWT_SECRET` | 主機執行 `openssl rand -hex 64` 貼上 | 不需申請；務必夠長夠亂 |
| Google Maps（前端） | 地圖頁面 | `GOOGLE_MAPS_API_KEY`（放 `android/key.properties`，非 `.env`） | https://console.cloud.google.com → 啟用「Maps SDK for Android」→ 建 API 金鑰 | **務必**用「套件名 + SHA-1」限制；從新增專案開始的完整步驟見 **§H**，注入機制見 `BUILD_GUIDE.md` §3 |

### A-2 建議（缺了對應功能停用，主流程仍可運作）

| 服務 | 用途 | `.env` 變數 | 去哪申請 | 備註 |
|------|------|-------------|----------|------|
| Cloudinary | 樹木照片雲端儲存 | `CLOUDINARY_CLOUD_NAME` / `CLOUDINARY_API_KEY` / `CLOUDINARY_API_SECRET` | https://cloudinary.com/users/register_free | 免費額度通常足夠；三項缺一不可；缺則無法上傳照片 |
| PlantNet | 拍照自動辨識樹種 | `PLANTNET_API_KEY` | https://my.plantnet.org/signup | 免費（有每日次數上限）；缺則無自動辨識 |

### A-3 選用（AI 對話 / Agent；至少設定一個才會開啟 AI 功能）

| 服務 | 用途 | `.env` 變數 | 去哪申請 | 備註 |
|------|------|-------------|----------|------|
| OpenAI | AI 對話 / Agent（預設供應商） | `OPENAI_API_KEY` | https://platform.openai.com/api-keys | 付費；預設模型 `gpt-5.4-mini` |
| Google Gemini | AI 備援 | `GEMINI_API_KEY` | https://aistudio.google.com/app/apikey | 有免費額度 |
| Anthropic Claude | AI 備援 | `Claude_API_KEY` | https://console.anthropic.com/ | 付費 |
| SiliconFlow | 便宜模型供應商 | `SiliconFlow_API_KEY`（可再加 `Alt1~3_SiliconFlow_API_KEY` 輪替） | https://siliconflow.cn/ | 程式會優先用它、失敗自動轉 OpenAI |
| Google CSE | Agent 網路搜尋工具 | `GOOGLE_CSE_API_KEY` + `GOOGLE_CSE_CX` | https://programmablesearchengine.google.com/ | 缺則 search 工具回提示，其餘 agent 功能仍可用 |

### A-4 自架 / 自訂字串（不需向外申請）

| 項目 | 用途 | `.env` 變數 | 怎麼來 | 備註 |
|------|------|-------------|--------|------|
| ML Service | 視覺測胸徑（選用） | `ML_SERVICE_URL` / `ML_SERVICE_PUBLIC_URL` / `ML_API_KEY` | 自架 `ml_service` | `ML_API_KEY` 在 backend 與 ml_service 兩邊填**同一串**；見 `ml_service/README.md` |
| 自動部署 webhook | GitHub push 觸發部署 | `DEPLOY_WEBHOOK_SECRET` | 自訂隨機字串 | 與 GitHub repo webhook 設定一致 |
| 部署診斷端點 | `GET /webhook/status` | `ADMIN_API_TOKEN` | 自訂隨機字串 | 選用；不設則該端點回 401 |
| ML 訓練資料 | 重新訓練模型才需要 | `KAGGLE_KEY` / `ROBOFLOW_API_KEY`（放 `ml_service/.env`） | kaggle.com / roboflow.com | 一般部署不需要 |

---

## B. 前端建置需要的設定

於建置／執行時提供（詳見 `BUILD_GUIDE.md`）：

| 設定 | 放在哪 | 說明 | 必要性 |
|------|--------|------|--------|
| `API_BASE_URL` | `--dart-define` | 後端 API base，如 `https://host/api` | **必要** |
| `SELF_SIGNED_TRUSTED_HOSTS` | `--dart-define` | 信任自簽憑證主機（逗號分隔，可用 `.ts.net` 後綴）；正式憑證則免 | 視情況 |
| `GOOGLE_MAPS_API_KEY` | `android/key.properties` | 地圖頁必需；Google Cloud Console 申請，須綁套件名 + SHA-1（見 `BUILD_GUIDE.md` §3） | **必要（地圖）** |
| iOS 地圖金鑰 | Xcode build setting `GOOGLE_MAPS_API_KEY_IOS` | iOS 版地圖 | 視平台 |

> 程式碼已零硬編碼：`app_config.defaultBaseUrl` 預設空字串、`main.dart` 自簽信任清單預設空，皆由上述設定注入。

---

## C. 主機 / 帳號設定

| 項目 | 說明 |
|------|------|
| GitHub repo | 部署來源（`tree-project-backend` / `tree-project-frontend`）＋ webhook；設為你自己的 repo（fresh push 步驟見 `LAB_DEPLOYMENT_GUIDE.md` §0.1） |
| 部署主機 | Ubuntu 主機 + SSH 帳號與公鑰；Nginx 反向代理 + PM2（見 `LAB_DEPLOYMENT_GUIDE.md`） |
| 私有網路 / 憑證 | 原部署採 Tailscale 提供 `*.ts.net` 有效憑證（`scripts/setup_tailscale_tls.sh`）；可改用任何網域 + 正式 TLS 憑證 |
| ML 服務位址 | `backend/.env` → `ML_SERVICE_PUBLIC_URL` 設為你的 ML 主機（若啟用 ML） |

---

## D. 建議：使用單位 / 專案專用帳號

為避免服務綁定到特定個人，建議在各平台（GitHub、Cloudinary、PlantNet、各 AI 平台、Google Cloud、Tailscale）申請一組**單位／專案專用帳號**持有金鑰與資源。如此長期維運與人員異動時只需移交該帳號，不必逐項重設。

---

## E. 安全注意事項

- 金鑰**切勿** commit 進 git；以安全管道（1Password、CI secrets、加密檔）保管與傳遞。
- API 金鑰務必在平台端加上**用途／網域／套件 + SHA-1 限制**，避免被盜用計費。
- 建議定期輪替 `JWT_SECRET`、`ADMIN_API_TOKEN`、`DEPLOY_WEBHOOK_SECRET`。
- 若任一金鑰曾透過不安全管道傳遞或疑似外流，請到對應平台**作廢並重新申請**。

---

## F. 使用者帳號（非 DB 種子）

- **`users.pg.sql` 僅建表**，不寫入任何帳號。
- **正式環境**：migrate 完成後執行 `node scripts/create_lab_admin.js --username ... --password ...`（強密碼，部署者自行決定）。
- **開發／CI**：`node scripts/seed_dev_users.js`（建立 `admin/12345` 等；`NODE_ENV=production` 會拒絕執行）。
- 舊環境若仍有歷史 seed 帳號，上線前請停用或刪除，只保留正式管理員。

---

## G. 本機 / 離線備份（不進 Git）

> ★★★ **最重要：release / upload keystore（上架簽章金鑰）** ★★★
> - 檔案：`android/keystore/upload-keystore-new.jks`（alias `tree_app_upload_xu.6`）＋它的 `storePassword/keyPassword`。
> - **一旦遺失，已上架到 Google Play 的 App 就無法再用同一身分更新**（除非有開 Play App Signing 走金鑰重設流程，曠日廢時）。
> - 請務必：①離線備份這個 `.jks` 與密碼到密碼管理器／安全儲存；②交接時當面移交；③**絕不** commit 進 git。
> - **debug keystore**（`~/.android/debug.keystore`）相反——它是**可拋棄**的，每台開發機各自一份、只用於開發；遺失重建即可（但重建後 SHA-1 會變，需重新加進 Maps 金鑰限制）。

| 項目 | 路徑 | 重要性 |
|------|------|--------|
| **release/upload keystore** | `android/keystore/*.jks` + 密碼 | ★ 上架命脈，務必備份 |
| Android 設定/金鑰 | `android/key.properties` | 每人一份；含 Maps 金鑰 |
| 後端機密 | `backend/.env`、`backend/ml_service/.env` | 部署機一份 |
| 管理員帳號 / 邀請碼清單 | 後台維運文件 | |

自動備份：`cd frontend; powershell -ExecutionPolicy Bypass -File scripts\handoff_backup.ps1`
（輸出至 `G:\TreeAI-Handoff\yyyyMMdd_HHmm\`，排除 build 與機密檔）。

---

## H. 附錄：Google Cloud 專案設定（地圖金鑰，從新增專案開始）

> 本專案地圖（地圖頁、邊界繪製、維護地圖）以 `google_maps_flutter` 顯示，**只需要 Maps 的 API 金鑰，不需要 Google 登入 / OAuth**。
> 下面 H-1～H-5 是「從零建立 Google Cloud 專案到拿到可用金鑰」的完整步驟；H-6（OAuth）目前用不到，僅未來要加「Google 登入」才需要，附上怎麼填供參考。
>
> 對應已知值：Android applicationId = `com.sustainable.treeai`；iOS bundle id = `com.sustainable.sustainableTreeai`。

### H-1 建立專案
1. 開 https://console.cloud.google.com → 上方專案選單 → **新增專案（New Project）**。
2. 專案名稱：`tree-project`；機構 / 父項資源：**無組織（No organization）**→ 建立。

### H-2 啟用必要 API
左側「API 和服務 → 程式庫」搜尋並啟用：
- **Maps SDK for Android**（Android 地圖必需）
- **Maps SDK for iOS**（iOS 地圖才需要）

### H-3 啟用帳單（重要，否則地圖會灰底）
- 「帳單（Billing）」→ 連結一個帳單帳戶（Google 有每月免費額度，一般用量內不收費）。
- 沒有連結帳單時，Maps SDK 會回錯誤、地圖顯示空白／灰底。

### H-4 建立並限制 API 金鑰
「API 和服務 → 憑證 → 建立憑證 → API 金鑰」，建一把給 Android、一把給 iOS（分開比較好控管）：

**Android 金鑰**
- 應用程式限制：選 **Android 應用程式** → 新增項目：
  - 套件名稱：`com.sustainable.treeai`
  - SHA-1 憑證指紋：用你的簽章 keystore 取得：
    ```bash
    keytool -list -v -keystore <keystore.jks> -alias <alias>
    ```
    （debug 與 release 各一組 SHA-1，建議都加；debug 預設在 `~/.android/debug.keystore`，密碼 `android`）
- API 限制：選 **限制金鑰** → 只勾 **Maps SDK for Android**。

**iOS 金鑰**
- 應用程式限制：選 **iOS 應用程式** → Bundle ID：`com.sustainable.sustainableTreeai`
- API 限制：只勾 **Maps SDK for iOS**。

### H-5 把金鑰填進專案（不進 git）
- Android：`frontend/android/key.properties`（範本 `key.properties.example`）：
  ```properties
  GOOGLE_MAPS_API_KEY=AIza...你的Android金鑰...
  ```
- iOS：Xcode build setting / xcconfig 設 `GOOGLE_MAPS_API_KEY_IOS=AIza...你的iOS金鑰...`
- 注入機制已設定好，不必改程式（詳見 `BUILD_GUIDE.md` §3）。

> **在誰的電腦、用哪把 keystore？**
> - 建金鑰是在**瀏覽器**（`console.cloud.google.com`），任何電腦皆可，建議登入**單位/團隊 Google 帳號**（勿綁個人）。
> - Android 金鑰的 **SHA-1 要對應「實際簽 APK 的那把 keystore」**：
>   - 接手者用自己的新 keystore → 把**他的 SHA-1** 加進金鑰限制。
>   - 沿用現有 release keystore（連 keystore 一起移交）→ SHA-1 不變，且舊使用者可無痛更新。
>
> **金鑰命名建議（建立 API 金鑰時的「名稱」欄）**：`tree-project Android Maps Key`（iOS 之後做時用 `tree-project iOS Maps Key`）。名稱只是標籤，可自訂。
>
> **`flutter run`（debug）vs release 的 key.properties**（依 `android/app/build.gradle.kts`）：
> - **debug（`flutter run`）只需要 `GOOGLE_MAPS_API_KEY` 一行**；debug 會自動用系統 `~/.android/debug.keystore` 簽，**不需**填 `storeFile/keyAlias/storePassword/keyPassword`。
> - 簽章那幾欄只有 **release**（`flutter build apk --release`）才會用到，且 `storeFile` 路徑相對於 `android/app/`。
>
> **可以先給對方什麼？**
> - **套件名** `com.sustainable.treeai`：固定值，現在就能給。
> - **SHA-1**：取決於 keystore——
>   - 開發階段：用各人的 **debug keystore**（`~/.android/debug.keystore`，密碼 `android`），每台電腦 SHA-1 不同，要各自加進限制（或開發另用一把不加限制的金鑰）。
>   - 上架/正式：用 **release keystore** 的 SHA-1（若沿用現有的就先取出給對方）。
> - 取 SHA-1 指令：`keytool -list -v -keystore <keystore> -alias <alias>`（輸出裡的 `SHA1:` 那行）。

### H-6 OAuth 設定（本專案目前用不到；未來加「Google 登入」才需要）

> 現況：程式碼無 `google_sign_in`、無 `google-services.json`，登入走自家帳密 + JWT。
> 以下僅在「日後要支援 Google 帳號登入」時才設定，照填即可：

1. **OAuth 同意畫面（OAuth consent screen）**
   - User Type：**外部（External）**（無組織只能選這個）→ 建立。
   - 應用程式名稱：`tree-project`；使用者支援電子郵件：你的信箱；開發人員聯絡資訊：你的信箱。
   - 範圍（Scopes）：加 `openid`、`.../auth/userinfo.email`、`.../auth/userinfo.profile`（只是要識別使用者的話這三個就夠）。
   - 測試使用者（Test users）：發布狀態維持「測試中」時，把要登入的 Google 帳號加進來。
2. **建立 OAuth 用戶端 ID（Credentials → 建立憑證 → OAuth client ID）**
   - Android：套件名 `com.sustainable.treeai` + SHA-1（同 H-4）。
   - iOS：Bundle ID `com.sustainable.sustainableTreeai`。
   - 若後端要驗證 Google token：另建一個 **Web application** 用戶端，取得 client_id / client_secret 放後端 `.env`（本專案目前無此需求）。
