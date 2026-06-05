# 現場測試資料集（歷史 + 維護）

業界常見做法：**fixture seed script**（可重複、可清理、不污染正式資料）。

## 建立測試樹（5 棵）

| 標籤 | 用途 | 歷次筆數 |
|------|------|----------|
| HIST-1 | 樹詳情／歷史面板 | 3 |
| HIST-2 | 歷史面板 | 2 |
| MAINT-1～3 | 維護量測地圖／清單 | 1～2 |

座標以你提供的 **GPS 為中心**，偏移約 20–40 m，方便現場維護流程。

標記：`[QA-FIXTURE:field-test]`（清理時依此刪除）

---

## 1. 從 Windows 執行

先在手機或地圖取得目前 GPS，並確認 App 場次裡 **區（Block）的 project_code**。

```powershell
cd c:\projects\tree_project\project_code\frontend

# 預覽（不寫入）
python test/field_test_dataset/seed_field_test_dataset.py --lat 24.15 --lon 120.65 --project-code 你的專案代碼

# 寫入
python test/field_test_dataset/seed_field_test_dataset.py --lat 24.15 --lon 120.65 --project-code 你的專案代碼 --apply

# 清理
python test/field_test_dataset/seed_field_test_dataset.py --cleanup --apply
```

需 `backend/.env` 內有 `DATABASE_URL`（與正式後端相同 DB）。

或直接：

```powershell
cd c:\projects\tree_project\project_code\backend
node scripts/seed_field_test_dataset.js --lat=24.15 --lon=120.65 --project-code=XXX --apply
```

---

## 2. App 驗證（release + 日誌）

```powershell
flutter run --release --dart-define=ENABLE_FIELD_LOGS=true --dart-define=RUN_VERIFICATION_HARNESS=true --dart-define=FIXTURE_PROJECT_CODE=你的專案代碼
```

| 步驟 | 操作 |
|------|------|
| 歷史 | 樹木調查 → 搜尋 `QA-FIXTURE` 或點 HIST 樹 → 詳情底部歷次 |
| 維護 | 維護量測 → **相同專案／區** → 地圖應見附近標記 → 選 MAINT-1 重測 |
| 日誌 | BLE 頁複製日誌；PC 端 `adb logcat -s BleLive FieldGPS VERIFY` |

啟動時 harness 會自動檢查 `QA-FIXTURE` 是否存在（需已登入）。

---

## 3. 單元測試

```bash
cd frontend
flutter test test/field_test_dataset/field_test_dataset_test.dart
```
