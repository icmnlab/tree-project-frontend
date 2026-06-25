# 接手開發者入門（從零裝機到可改程式）

> **適用**：實驗室新接手、需自建環境並接續開發。  
> **單一技術入口**仍為 [`HANDOFF.md`](HANDOFF.md)；本檔只整理**建議順序**與**第一天要做的事**。

---

## 1. 讀文件順序（約半天）

| 順序 | 文件 | 目的 |
|------|------|------|
| 1 | [`HANDOFF.md`](HANDOFF.md) §1、§2、§8.1 | 系統是什麼、兩 repo、四種新增路徑 |
| 2 | [`LAB_DEPLOYMENT_GUIDE.md`](LAB_DEPLOYMENT_GUIDE.md) §0、§3 | 從零部署主機與 DB |
| 3 | [`HANDOFF_SECRETS_CHECKLIST.md`](HANDOFF_SECRETS_CHECKLIST.md) | 金鑰與帳號（**自建**，不接舊 key） |
| 4 | [`BUILD_GUIDE.md`](BUILD_GUIDE.md) | 建置 Android APK |
| 5 | [`VERIFICATION_CHECKLIST.md`](VERIFICATION_CHECKLIST.md) | 部署後逐項驗證 |
| 6 | [`MANUAL_DATA_ENTRY.md`](MANUAL_DATA_ENTRY.md) | 手動新增／編輯（補 FIELD_SURVEY 未涵蓋部分） |
| 7 | 領域專題（按需） | `FIELD_SURVEY_SOP.md`（BLE 現場）、`CARBON_CALCULATION.md`、`DATABASE_NORMALIZATION.md` |

---

## 2. 從零裝機檢查表（接手方）

### 2.1 取得程式碼

- [ ] Clone `tree-project-frontend`、`tree-project-backend`（各為獨立 repo）
- [ ] 確認 `LICENSE`、`AUTHORS.md`、`CONTRIBUTION_RECORD.md` 存在

### 2.2 後端 + 資料庫（開發機）

```bash
cd tree-project-backend
cp .env.example .env          # 填 DATABASE_URL、JWT_SECRET、CORS
npm ci
node scripts/migrate.js       # 開發庫可匯入測試樹；正式庫見 LAB_DEPLOYMENT
node scripts/seed_dev_users.js   # 僅開發／CI；勿用於 production
npm start                     # http://localhost:3000/health
```

- [ ] `/health` 回 200
- [ ] `node tests/runner.js --list` 可列出測試（可選跑一輪）

### 2.3 前端（開發機）

```bash
cd tree-project-frontend
flutter pub get
flutter run --dart-define=API_BASE_URL=http://<後端IP>:3000/api
```

- [ ] 可登入（開發庫：`admin` / `12345`，須先 seed）
- [ ] `flutter test` 通過（目標 435）

### 2.4 正式／實驗室主機

依 [`LAB_DEPLOYMENT_GUIDE.md`](LAB_DEPLOYMENT_GUIDE.md) §0 完整流程：

- [ ] fresh snapshot push（§0.1）
- [ ] 金鑰輪替（§0.2、`HANDOFF_SECRETS_CHECKLIST.md`）
- [ ] PM2 + webhook（§0.3–0.4）
- [ ] `create_lab_admin.js` 建管理員（§0.5，**勿**用 seed_dev_users）
- [ ] Release APK + `VERIFICATION_CHECKLIST.md`

---

## 3. 接續開發：先認這條主路徑

現場 **P0** 寫庫路徑（口試／維護必記）：

```
首頁 → VLGEO2 現場連線 (BleLiveSessionPage)
  → pending (POST /api/pending-measurements/...)
  → 整合表單 (IntegratedTreeFormPage)
  → transfer (POST /api/pending-measurements/transfer)
  → PostgreSQL tree_survey + 歷次
```

| 層 | 入口檔 |
|----|--------|
| 前端 | `lib/screens/ble_live_session_page.dart` |
| API 客戶端 | `lib/services/pending_measurement_service.dart` |
| 後端 | `routes/pending_measurements.js` |
| DB | `tree_survey`、`tree_survey_measurements`、`pending_tree_measurements` |

其他新增路徑見 [`HANDOFF.md`](HANDOFF.md) §8.1、[`MANUAL_DATA_ENTRY.md`](MANUAL_DATA_ENTRY.md)。

---

## 4. 改程式後的最低驗證

| 變更 | 建議 |
|------|------|
| 後端 API / DB | `node tests/runner.js`；新增 migration 只走 `run_pending_migrations.js`（正式） |
| 前端 UI | `flutter test`；相關畫面手動走一輪 |
| 部署 | push `main` → webhook → 查 `/health` 與 `deploy.log` |

CI：兩 repo 的 `.github/workflows/ci.yml`（push/PR 自動跑）。

---

## 5. 實驗性功能（預設正式 APK 關閉）

見 [`HANDOFF.md`](HANDOFF.md) §12：`ENABLE_EXPERIMENTAL_UI=false` 時隱藏 AI 助理、碳匯 LLM 報告等；程式保留，需金鑰與實驗建置才啟用。

---

## 6. 聯絡與歸屬

- 原始開發與交接前維護：見 `AUTHORS.md`、`CONTRIBUTION_RECORD.md`
- 維運與主機自交接日起由接手方負責
