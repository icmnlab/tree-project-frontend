# 樹木調查系統 — 接手開發 / 部署 / 維運手冊

> 目的：讓下一位接手者能在不依賴原作者的情況下，理解系統、建置環境、部署、並繼續開發。
> 維護原則：本檔與 GitHub `main` 為準；改動流程或設定請同步更新本檔。
> 最後更新：2026-06-05（P2 現場補強、歷次量測、2NF migration、併發修補已完成）  
> 待辦追蹤：`docs/DEVELOPMENT_BACKLOG.md`

---

## 0. 系統一句話

VLGEO2 測距儀以 **BLE 逐棵 SEND** 把「樹高 / 距離 / 方位」傳到 Flutter APP；
APP 於每棵樹旁取 **手機 GPS** 作為樹木座標，填整合表單後 **上傳自架後端**。

```
VLGEO2 ──BLE PHGF──▶ Flutter APP ──HTTP──▶ 自架後端（圖資中心 / Tailscale）
   (樹高/HD/方位)        + 手機 GPS 座標            + ML Service（樹種/DBH 視覺）
```

---

## 1. 倉庫與分支

| 項目 | 內容 |
|------|------|
| 前端 Repo | https://github.com/KyleliuNDHU/tree-project-frontend |
| 後端 Repo | https://github.com/KyleliuNDHU/tree-project-backend |
| 主分支 | `main`（開發前先 `git pull`） |
| 部署方式 | push 到 GitHub `main` 後，後端在圖資中心主機自動部署（見 §7） |

---

## 2. 開發環境建置（前端 Flutter）

```bash
git clone https://github.com/KyleliuNDHU/tree-project-frontend.git
cd tree-project-frontend
flutter pub get
flutter doctor          # Android toolchain 需正常；Windows 桌面非必須
flutter run             # Android 實機優先（BLE + GPS 需實機）
```

- 已驗證版本：**Flutter 3.44.0 / Dart 3.12.0（stable）**
- `flutter doctor` 若僅 Visual Studio C++ 缺漏 → 不影響 Android 開發
- BLE 與 GPS 功能 **必須用 Android 實機測試**，模擬器無法測

### 必要權限（已在 AndroidManifest）
- 藍牙（BLE 掃描 / 連線）
- 位置（GPS；Android 12+ 需精確位置 + 藍牙掃描權限）

---

## 3. 建置 / 簽章 / 金鑰（接手最容易卡的地方）

以下檔案 **不在 Git**（已 `.gitignore`），必須由原作者另外交付：

| 檔案 / 設定 | 用途 | 取得方式 |
|-------------|------|----------|
| `android/key.properties` | 放 **GOOGLE_MAPS_API_KEY** 與 release 簽章設定 | 向原作者索取，或自行重建（見下） |
| `android/app/debug-keystore.jks` | Android 簽章金鑰 | 向原作者索取；或 `keytool` 自行產生新的 |
| Google Maps API Key | 地圖顯示（`com.google.android.geo.API_KEY`） | Google Cloud Console 自行申請（見 §8） |

`android/app/build.gradle.kts` 會從 `key.properties` 讀 `GOOGLE_MAPS_API_KEY` 注入 Manifest 佔位符 `${GOOGLE_MAPS_API_KEY}`。

### key.properties 範例（自行建立）
```properties
storeFile=debug-keystore.jks
storePassword=你的密碼
keyAlias=你的alias
keyPassword=你的密碼
GOOGLE_MAPS_API_KEY=AIza...（你自己的 Google Maps 金鑰）
```

> 若沒有金鑰：地圖頁會空白，但 BLE 量測 / GPS / 上傳仍可運作。

---

## 4. 後端連線設定（重要：與原作者環境綁定）

目前後端 URL **寫死** 在 `lib/config/app_config.dart`：

```dart
baseUrl = 'https://richardhualienserver.tail124a1b.ts.net/api';
```

- 這是 **Tailscale**（私有網路）位址，接手者要嘛 **加入同一個 Tailscale 帳號/網路**，要嘛 **改成圖資中心部署後的新網址**。
- **ML Service URL** 不寫死：登入後由後端 config 回傳，或建置時 `--dart-define=TREE_ML_SERVICE_URL=...`。

> 接手第一步若連不上後端，先確認這條 `baseUrl` 是否仍有效、是否需改成圖資中心新位址。

---

## 5. 儀器韌體（VLGEO2）

| 項目 | 內容 |
|------|------|
| 機器型號 | **VLGEO2_3190**，目前 STD **V3.7** |
| 韌體備份（已在 repo） | `test/vlgeo2_ble_analysis/firmware_backup/VLGEO2_3190_20260531/STD V37.VL7` |
| 可安裝版本 | `firmware_backup/installable/STD V39.VL7` |
| 還原步驟 | 見 `firmware_backup/RESTORE_CHECKLIST.md` |
| 勿安裝（未購 license） | `BAF V14.VL7`、`Pile V25.VL7`（見 `downloads/README_LICENSED.md`） |

> **關於 `d:\PRG\STD V37.VL7`**：這就是機器目前的 STD V3.7 韌體，**repo 已有同一份備份**，不需要再額外提供。
> 若要確認兩者一致，可比對 `firmware_backup/VLGEO2_3190_20260531/STD V37.VL7` 的雜湊。

---

## 6. BLE 協議 — 逐棵量測時儀器 SEND 什麼

### 6.1 兩種傳輸模式（韌體刻意二選一）

| 模式 | 儀器設定 | BLE 送出內容 | 有無 GPS |
|------|----------|--------------|----------|
| **逐棵即時（本系統用）** | MEMORY **關** | `$PHGF,HVV,...` NMEA 文字句 | **無 GPS** |
| 整檔匯出 | MEMORY **開** → SEND FILES | 整份 `DATA.CSV`（含 LAT/LON） | 有 GPS，但非逐棵即時 |

### 6.2 逐棵 SEND 的實際封包（`BleLiveNmeaAssembler` / `BleLiveNmeaParser`）

實機 VLGEO2_3190 經 BLE 送的是 **手冊 §9.2 的 NMEA 文字**（不是 §9.3 純 20-byte 二進位）：

```
$PHGF,HVV,<HD>,<HD單位>,<AZ>,<AZ單位>,<PITCH>,<單位>,<SD>,<單位>,<H>,<單位>[,<遠距直徑>,CM]*<checksum>
```

| 欄位 | 意義 |
|------|------|
| HD | 水平距離（m） |
| AZ | 方位角（度） |
| PITCH | 傾角（度） |
| SD | 斜距（m） |
| H | 樹高（m） |
| 第 13–14 欄 | Geo2 V3.7+ 擴充：Remote Diameter（遠距直徑，cm）；`0.0,CM` = 未量 |

- **GPS 不在 PHGF 封包內**（20-byte 塞不下 NMEA；且逐棵 BLE 通道不送 GPS）。
- BLE TX：**實機 `VLGEO2_3190` PHGF 由 NUS `6E400003-...` 送出**；Haglof `9E010000-...` 多為 §9.3 前綴。APP 已改 **NUS 優先訂閱**（`ble_live_session_page.dart`）。
- 連續多棵時，第二棵起常見 §9.3 前綴與 `$PHGF` 黏在同一 notify、無換行 → 已用正則切句修復（見 `ble_live_packet_decoder.dart` 與 `test/ble_live_nmea_test.dart`）。
- 電腦端驗證：`test/vlgeo2_ble_analysis/verify_vlgeo2_gps_ble.py`（2026-06 實測 12 棵連續 SEND 通過）。

### 6.3 能不能在逐棵量測時用「儀器內建 GPS」？

**結論：不能（在目前 BLE 逐棵流程下）。** 詳見 `test/vlgeo2_ble_analysis/docs/`：

- 2026-05-31 實測：MEMORY 關 + BLE 逐棵 SEND → 12/12 棵收到 PHGF，**0 句 GGA/RMC**。
- USB `DATA.CSV`（MEMORY 開）才有 LAT/LON，但非逐棵即時。
- Classic 藍牙 `_COM`（手冊 §4.6.2）理論可串流 GPS，但 Mac 實測 0 byte。

→ 因此本系統 **座標改用手機 GPS**（會議決議；外接 GNSS 模組方案已放棄、不採購）。

---

## 7. 現場測量流程與各情況處理

### 7.1 主流程（`FieldSurveyFlowPage` → `BleLiveSessionPage`）

```
進入現場連線 → 掃描並連 VLGEO2
   ↓ (第一棵前)
場次設定：選 專案 → 區(Block) → 場次名稱（整場共用）
   ↓ (每棵循環)
儀器 SEND → APP 收 PHGF → 樹旁取手機 GPS → 整合表單(拍照/DBH/樹種) → 提交
   ↓
回連線畫面 → 下一棵
```

- GPS **一律樹木位置**（`gpsSource = 'tree'`，不再讓使用者選測站/樹旁 — 2026-05-28 會議）。
- **場中換專案／區**：連線頁 AppBar「切換專案／區」；若本場已完成樹木會先警示（之後 SEND 歸新專案／區）。

### 7.1b 維護量測（`MaintenanceSurveyPage`）

```
場次設定（專案＋區）→ 清單或地圖選樹 → 底部確認 → BLE 重測
                                    └→ 或「新增樹木」走初測流程
```

- 地圖：區內有 GPS 的樹顯示標記；點選後底部單確認再進 BLE。
- 維護 transfer：`survey_mode=maintenance` + `target_tree_id` → 更新 `tree_survey` 並 **追加** `tree_survey_measurements` 歷次。

### 7.2 已處理的情況（程式現況）

| 情況 | 處理 |
|------|------|
| 偵測到整檔 EOT（誤開 MEMORY） | 橘色提示「請關 ENABLE MEM，勿用 SEND FILES」，忽略該封包 |
| 上一棵還沒填完又按 SEND | `_isProcessingTree` 鎖定 + 提示「請先完成目前這棵」 |
| **未取得 GPS / 取消定位** | 保留 PHGF；橘色橫幅 **「重測 GPS」**（無需再按 SEND）；可放棄此棵 |
| 重複 notify | 同步加鎖避免重複建立任務 |
| 上傳失敗 / 無任務 ID | snackbar 提示，中止本棵 |
| 表單提交成功 | 計數 +1，綠色提示；自動轉移到正式樹木資料 |
| 表單取消 / 未完成 | 任務退回 `pending`，留在待測量列表可續測 |
| 連線中斷 | 自動重連（最多 5 次、指數退避）；表單處理中則完成後再重連；可「立即重連」或改選裝置 |

### 7.3 表單送出後，待測量任務還會留紀錄嗎？

| 結果 | 待測量任務（pending）狀態 |
|------|---------------------------|
| **提交成功 + 轉移成功** | **不留**：該筆 `transferToTreeSurvey` 移到正式 `tree_survey`，從待測量消失 |
| 提交成功但轉移失敗（如斷網） | 暫留（待重試）；可日後再轉移 |
| 表單取消 / 未完成 | **保留**為 `pending`，可在「待測量任務」續測 |

> 轉移是 **以 sessionId 整批** 轉移；同場次已完成的紀錄會一起進正式資料表。

### 7.4 歷次量測與 ID 顯示

| 項目 | 說明 |
|------|------|
| 歷次表 | `tree_survey_measurements`（migration `15_*`） |
| 寫入時機 | 每次 transfer（`new` / `maintenance`）追加一列；`tree_survey` 仍為最新快照 |
| 舊樹 baseline | migration `17_*` 為無歷次之既有樹補一筆 `snapshot` |
| 查詢 API | `GET /api/tree_survey/by_id/:id/measurements?limit&offset` |
| UI | `TreeMeasurementHistoryPanel`（樹詳情、整合表單、維護選樹底部預覽） |

**ID 顯示慣例**（`lib/utils/tree_id_display.dart`）：

- 現場列表／地圖：專案樹號 **純數字**（`PT-123` → `123`）
- 系統樹號：小字完整 `ST-xxx`；DB 仍存完整前綴

---

## 7.5 後端併發與資料完整性（2026-06）

| 項目 | 說明 |
|------|------|
| transfer | `FOR UPDATE` 鎖 completed 列，避免重複 INSERT |
| CSV 匯入 | 任一笔失敗 → 全批 ROLLBACK |
| XLSX `/import` | `pg_advisory_xact_lock(1)` + 逐專案權限 |
| pending PATCH | `updated_at` 樂觀鎖 |
| tree_images / management / reports | `projectAuth` 或 owner 專案檢查 |
| 2NF 邊界 | migration `16_*` 回填 `project_boundaries.project_code` |

---

## 8. 與「個人帳號 / 金鑰」綁定，接手前必須移轉

| 綁定項目 | 現況 | 移轉動作 |
|----------|------|----------|
| **後端 baseUrl（Tailscale）** | 寫死於 `app_config.dart` 指向原作者私有主機 | 加入同 Tailscale 網路，或改為圖資中心正式網址 |
| **Google Maps API Key** | 放在 `android/key.properties`（未進 Git） | 接手者用自己的 Google Cloud 專案申請新金鑰填入 |
| **Android 簽章 keystore** | `debug-keystore.jks` + `key.properties`（未進 Git） | 索取原檔，或產生新 keystore（會改變 App 簽章身分） |
| **GitHub repo 權限** | 原作者帳號 KyleliuNDHU | 加入接手者為 collaborator，或移轉 repo |
| **後端管理帳號 / 邀請碼** | 後台管理帳密、註冊邀請碼 | 由原作者建立新管理員帳號交付，並更換密碼 |
| **ML Service URL** | 登入後由後端回傳或 `--dart-define` | 確認圖資中心部署後的 ML 位址 |
| **圖資中心主機 / Port** | 簡老師協調，連線細節未定 | 取得 SSH/部署權限與對外 Port |

> 安全提醒：金鑰、keystore、邀請碼 **不要** commit 進 Git（`.gitignore` 已涵蓋 `key.properties`、`*.jks`、`apiKeys.json`、`local.properties`、`android/gradle.properties`）。

---

## 9. 後續開發優先序

| 優先 | 項目 | 狀態 |
|------|------|------|
| P0 | 現場逐棵連線、GPS 樹旁、名詞對齊 | ✅ |
| P0 | BLE 第二棵 SEND、電腦端 12 棵驗證 | ✅ |
| P2 | 維護量測、地圖、斷線重連、GPS 重測、場中換區 | ✅ |
| P2 | 歷次量測 schema / API / UI | ✅ |
| P2 | 2NF 邊界 code 回填、歷次 baseline | ✅ migration `16_*` `17_*` |
| 中優先 | 併發 / 權限 / CSV rollback | ✅ |
| P1 | 完整使用者操作手冊（非技術） | ✅ `FIELD_SURVEY_SOP.md` |
| P1 | 2026-05-28 會議紀錄 | ✅ `MEETING_MINUTES_20260528.md` |
| 暫緩 | 批次藍牙匯入擴充 | 保留現狀 |
| 取消 | 外接 GNSS（LG290P） | 不採購 |

執行 migration：`cd backend && node scripts/migrate.js`（或重啟後端觸發 `pending_measurements` 冪等 SQL）。

---

## 10. 相關文件索引

| 路徑 | 內容 |
|------|------|
| `docs/SYSTEM_HANDOFF_MANUAL.md` | **本檔**：部署 / 設定 / 接手 |
| `docs/FIELD_SURVEY_SOP.md` | **現場調查員操作 SOP**（非技術） |
| `docs/MEETING_MINUTES_20260528.md` | 2026-05-28 會議紀錄與決議對照 |
| `docs/DEVELOPMENT_BACKLOG.md` | 開發待辦與完成項勾選 |
| `docs/DATABASE_NORMALIZATION.md`（repo `docs/`） | 2NF 說明與演進 |
| `test/Tree_app_equipment_info/VLGEO2_BLE_PROTOCOL.md` | BLE 協議深度解析 |
| `lib/screens/maintenance_survey_page.dart` | 維護量測（清單＋地圖） |
| `lib/widgets/tree_measurement_history_panel.dart` | 歷次量測 UI |
| `lib/screens/csv_import_page.dart` | 管理員 CSV 匯入 |
| `lib/admin_research_dataset_page.dart` | 研究用 DBH 校準資料蒐集 |
| `test/vlgeo2_ble_analysis/docs/VLGEO2_GPS_SOLUTION.md` | 儀器 GPS 實測結論 |
| `test/vlgeo2_ble_analysis/firmware_backup/RESTORE_CHECKLIST.md` | 韌體還原 |
| `docs/HANDOFF_EXTERNAL_GNSS_AND_BLE.md` | 外接 GNSS 研究（已放棄方案，保留供參考） |
| `lib/screens/ble_live_session_page.dart` | 現場逐棵連線主流程 |
| `lib/screens/v3/integrated_tree_form_page.dart` | 整合表單 + 自動轉移 |
| `lib/services/pending_measurement_service.dart` | 待測量任務 / 轉移 / 上傳 |
| `lib/config/app_config.dart` | 後端 / ML 連線設定 |
