# Changelog

所有主要版本變更記錄。

---

## v18.6.0 (2026-06-13) — 邊界匯出 KML + 自動重排升級 + 手動繪製防呆

- **邊界匯出 KML（`project_boundary_draw_page`）**：已有邊界的區，右上角新增「匯出（分享）」圖示 → 下載 `<區名>.kml`，Android 以 Google Earth 開啟；沿用 `DownloadService`（JWT/TLS/`OpenFilex`）。與「匯入 KML」形成雙向流。
- **自動重排升級（`lib/utils/boundary_input.dart`）**：新增 `reorderByNearestNeighbor`（最近鄰連線，對細長/部分凹形較佳）與 `tryAutoReorder`（先角度、仍自相交再最近鄰）。貼座標/匯入預覽的「依角度重排」改為「自動重排」，無法消除時明確提示需手動調整。
- **手動繪製自相交防呆**：手動點選/拖曳頂點若畫出交叉，按「儲存」時跳出對話框可「自動重排」（與貼座標/匯入一致），不再只回後端 400「儲存失敗」。
- **測試/樣本/文件**：新增 `sample_boundary_complex.kml`（凹形 KML）；新增重排單元測試（蝴蝶結修復、最近鄰起點、合法多邊形）；後端新增匯出契約測試（KML 內容、lng,lat 序、404）；更新驗證清單 B9/B16/B17/B18/B19、`BOUNDARY_SYSTEM_DESIGN.md`、`boundary_samples/README.md`。

---

## v18.5.4 (2026-06-13) — 邀請碼管理強化 + 邊界亂序測試

- **邀請碼管理（`invite_management_page`）**：
  - **依建立日期分組顯示**：清單以 `created_at` 分日期標題，卡片顯示建立時間。
  - **刪除紀錄**：新增「刪除紀錄」（呼叫後端 `DELETE /invites/:id`，破壞性操作有二次確認）；原「停用」與「複製」整併進右側選單（`PopupMenuButton`）。
  - **綁定區改 V2 式「選單樣式」**：用 `ExpansionTile` 收合成可展開的選單，內含搜尋 + 勾選清單，維持多選；未選時預設展開。
- **邊界座標亂序**：新增 `docs/boundary_samples/coords_scrambled_convex.txt`（亂序凸四邊形）示範「自相交偵測 + 依角度重排」；新增單元測試（魚塭 9 點凹多邊形不自相交、亂序凸形可重排修復）。文件補充座標順序說明（凹形亂序需正確順序或匯入 KML/GeoJSON）。

---

## v18.5.3 (2026-06-13) — 後台對話框生命週期 + Row 溢出修復

實機 `flutter run` log 在「專案/區管理」頁仍出現 `RenderFlex overflowed 14px`、`TextEditingController used after disposed`、`_dependents.isEmpty`、`Tried to build dirty widget in the wrong build scope`。根因為這些頁面仍沿用「`showDialog` 後立即 `dispose`（或 `whenComplete` dispose）」的舊寫法：

- **`project_areas_admin_page.dart`**：
  - 標題列 `Row`（「專案管理」+ 重新整理/新增按鈕）在窄螢幕溢出 → 標題改用 `Expanded + TextOverflow.ellipsis`，按鈕 `Row` 設 `mainAxisSize.min`。
  - 新增/編輯表單抽成 `_AreaFormDialog`（StatefulWidget），controller 於其 `dispose()` 釋放。
- **`admin_page.dart`**：
  - 「建立區」抽成 `_CreateProjectDialog`（StatefulWidget，下拉加 `isExpanded`）。
  - 「確認刪除區」抽成 `_DeleteProjectConfirmDialog`（StatefulWidget）。
- 至此所有含 `TextEditingController` 的對話框都改為自有生命週期的 StatefulWidget，杜絕「dispose 後重建」連鎖錯誤。

---

## v18.5.2 (2026-06-13) — 貼座標對話框生命週期修復

實機 `flutter run` log 觀察到一串執行期例外，根因為「貼上座標」對話框：

- **修復 `TextEditingController was used after being disposed`（及連鎖 `_dependents.isEmpty` / `Tried to build dirty widget in the wrong build scope` / `Duplicate GlobalKeys`）**：原本在 `await showDialog` 後立即 `controller.dispose()`，對話框退場動畫仍會重建子樹而存取已釋放的 controller。改將對話框抽成獨立 `_PasteCoordinatesDialog`（StatefulWidget），controller 由其 `dispose()` 在路由完全移除後才釋放。
- **修復 `RenderFlex overflowed by 26 pixels on the right`**：對話框內「無法判斷時順序」的 `Row`（標籤 + `DropdownButton`）在窄螢幕溢出；`DropdownButton` 改以 `Expanded` 包裹並設 `isExpanded: true`。
- **測試樣本**：新增複雜（凹）多邊形樣本 `docs/boundary_samples/coords_complex_pond.txt` 與 `sample_boundary_complex.geojson`（環境學院魚塭 9 點），驗證系統可畫非四方形/凹形且不自相交。

---

## v18.5.1 (2026-06-13) — 邊界匯入 UX 修正

- **檔案選擇器相容性**：`project_boundary_draw_page` 匯入改用 `FileType.any` + Dart 端副檔名驗證（原 `FileType.custom` 在部分 Android 檔案選擇器下會把 `.kml/.kmz/.geojson` 過濾掉，只剩圖片/音訊可選）；選到非支援格式時明確提示。
- **移除未開放選單**：拿掉「匯入含座標圖檔（即將推出）」的方式 2 預留項，避免顯示不可用功能造成混淆（方式 2 待學院提供範例檔再評估）。

---

## v18.5.0 (2026-06-13) — 邊界輸入方式擴充（貼座標 + GIS 匯入）

依環境學院需求，區邊界繪製頁 `project_boundary_draw_page` 新增多種輸入方式（沿用「預覽→確認→儲存」流程）：

- **貼上座標（方式 1）**：新增 `lib/utils/boundary_input.dart` 解析座標清單，支援括號/逗號/空白分隔；以數值範圍自動判斷 `lng,lat` 或 `lat,lng`，無法判斷時可選假設順序；偵測自相交並提供「依角度重排」；明確回報無法解析的行。
- **匯入 KML/KMZ/GeoJSON（方式 3）**：以 `file_picker` 選檔上傳後端解析，預覽顯示偵測到的座標系統（WGS84 / TWD97 轉換）、頂點數、面積與警告。
- **含座標圖檔（方式 2）**：UI 預留選項，顯示「即將推出」（待學院提供範例檔後實作）。
- `ProjectBoundary` 模型加 `source`；`project_boundary_service` 加 `importBoundaryFile`；儲存時回報 `source`，界外樹木明確確認後帶 `allowTreesOutside`。
- 測試：`test/boundary_input_test.dart`（9 案例：順序判斷、收尾去重、錯誤行回報、自相交與重排）。

## v18.4.0 (2026-06-11) — 交接整備：repo 清理 + 版本同步

- repo 清理（研究遺留移至外部備份 `handover_backup_20260611/`）：
  - `test/Tree_app_equipment_info/`（BLE 逆向研究約 98 檔）移出；測試所需 `DATA_2.CSV`、`VLGEO2_BLE_PROTOCOL.md` 保留於 `test/fixtures/vlgeo2/`。
  - `test/vlgeo2_ble_analysis/` 精簡：保留 `docs/`、verify 腳本、可安裝韌體（交接文件依賴）；分析產物、raw captures、多版韌體移出。
  - 未引用 assets 移出（ChatGPT 中間產物圖 ×3、重複 app icon ×5、mobilenet 三檔、`coa_table_6_4.json`）；`pubspec.yaml` 移除空 `assets/data/` 宣告。
  - 死碼移出：`custom_dropdown.dart`、`species_card.dart`、`tree_species.dart`、`tipc_kp_lookup.g.dart`。
  - 根目錄一次性腳本移出：`convert_shp.py`、`flutter_launcher_icons_android.yaml`、`devtools_options.yaml`。
- 版本號自 18.3.2 起累積的變更（06-10 地圖聚合、06-11 詞彙互換）一併納入本版。

## (2026-06-11) — 全面詞彙互換：畫面顯示改「專案/區」

依會議決定，階層詞彙全面對齊：舊「區位／專案區位」→ 畫面顯示「**專案**」（上層）；舊「專案」→ 畫面顯示「**區**」（下層）。

- **範圍**：28 檔、約 330 處 UI 顯示字串（標籤、標題、提示、SnackBar、InfoWindow、統計圖表、l10n 中英文值）。
- **不變**（嚴格保留）：API 中文 JSON 鍵（`專案名稱`/`專案區位`/`專案代碼`…）、DB 欄位、變數/路由名、**角色名稱**（`專案管理員` 等五角色為 DB 值）、log 字串。
- 英文 UI 統一：上層 Project、下層 Block（原 map 等處誤用 Zone 已統一）。
- `tree_list_page.dart`：排序鍵與顯示文字脫鉤（`_sortDisplayLabels` 對映，排序仍用後端資料鍵）。
- 詞彙對照表寫入 `HANDOFF.md` §8（維護必讀）。
- 測試：修 `ble_simulation_test.dart` 高頻壓測在全套件併發下的 flaky（固定 sleep 改為達標輪詢）。415 測試全綠。


## (2026-06-10) — 地圖聚合改 Dart 端實作 + UX 修正

### 地圖標記聚合（取代原生 ClusterManager）
- 實機重現：plugin 原生 `ClusterManager` 在 7000+ 標記時觸發 Android `RejectedExecutionException`（每 addItem 觸發一次 re-cluster AsyncTask、塞爆 128 佇列）。
- `lib/utils/tree_marker_cluster.dart`（新）：Dart 端網格聚合（螢幕約 80px 網格、質心座標、k 標籤、依數量分級圓點大小）；單元測試 `test/tree_marker_cluster_test.dart`（含 7000 點 <100ms 效能保險、不丟點守恆）。
- `lib/map_page.dart`：
  - zoom < 16 → 聚合圓點（畫布繪製數字圖示、依標籤快取）；點擊圓點 +2.5 zoom 漸進放大。
  - zoom ≥ 16 → **一律個別標記**（保證「放大後看得到定位點」），同座標疊點沿用 spiderfy 展開；個別模式視窗外剔除 + 2000 保險絲。
  - `onCameraIdle` 跨聚合門檻或 zoom 變化 ≥0.5 才重建（避免平移過度重繪）。

### UX
- 地圖右下「顯示所有標記」FAB：無標記/未就緒時原本靜默不動（使用者以為壞掉）→ 改 SnackBar 回饋 + log。
- 地圖縣市/專案下拉選單：固定白底面板上釘住深色箭頭/文字（修暗色主題下白箭頭白字看不到）。
- 邀請碼建立對話框：綁定專案改「可搜尋 + 限高捲動清單 + 已選計數」（原本 40+ 專案攤平整個對話框）。

> 後端同步：`create_v2` 手動新增（智慧/快速模式）同步寫入 `tree_survey_measurements` 首筆歷次快照（survey_mode='new'），與 BLE/維護 transfer 行為一致。

### 邀請碼：區位選擇簡化
- `invite_management_page.dart`：移除「區位備註（逗號分隔）」文字欄——與區位 chips 雙向同步、易誤觸且僅供紀錄；現在區位由勾選的專案自動帶出 chips，警示文案改中性說明（權限以「綁定專案」為準）。

### 暗色模式：專案/區選擇欄位配色
- `field_session_setup.dart`、`tree_edit_page_v2.dart`、`tree_input_page_v2.dart` 共 8 處欄位：`fillColor` 原寫死淺青 `teal.shade50`，暗色主題下白色箭頭/輸入文字落在淺底上看不到 → 改依主題切換（暗色用 `teal.shade900`）。

### 導覽簡化（0d-A 拍板執行）
- 底部導覽 3→2 頁：移除「調查」分頁（與「列表」職責重疊、列表能力為超集）。
- `tree_survey_page.dart` 程式碼保留：仍服務專案/區位下鑽與首頁「樹木調查」卡片（手動新增入口）。
- `HANDOFF.md` 新增 §12「保留但未掛載／實驗性功能」清單（AI 對話/報告、視覺 DBH/ml_service、AR、ML 訓練資料收集等都保留給後續開發者）。

---

## (2026-06-10) — 多人安全 P0（前端側）+ UI 修正

### 多人安全（深度稽核 #2/#4/#8）
- `lib/utils/session_id.dart`（新）：測量批次 ID 改「日期前綴+96-bit 安全亂數」防碰撞；`PendingMeasurementService.generateSessionId()` 與 SMOKE 批次同步改用。
- `lib/screens/pending_measurement_task_page.dart`：新增 `_claimedTaskId`，dispose／放棄／取消只把**本機 claim** 的任務還原 pending，不再誤打回其他裝置的 in_progress。
- `lib/screens/maintenance_survey_page.dart`：清單達 500 筆上限時顯示橙色警告列（取代靜默截斷）。

### UI
- `lib/admin_page.dart`：專案管理標題列改 `Expanded`，修窄螢幕 RenderFlex overflow（14px）。

> 後端同步：pending 擁有權（created_by_user_id + 403 NOT_OWNER）+ by_project/by_area 查詢上限；契約測試 `pending_ownership.test.js`。

---

## v18.5.1 (2026-04-28) — V3 species refactor + docs cleanup

### V3 樹種辨識
- `lib/screens/v3/integrated_tree_form_page.dart` · `lib/screens/v3/manual_input_page_v3.dart`
  - 顯示名稱改用學名 (`scientificNameWithoutAuthor`)；中文俗名只在 snackbar 提示
  - 移除手動「新增樹種」按鈕；改在提交時用 `_ensureSpeciesId()` 自動建檔（先 server-side searchSpecies → 找不到才 POST /tree_species）
  - TextFormField onChanged 編輯時自動清掉舊 _speciesId，避免誤套到別的樹

### AI Chat
- `lib/screens/ai_chat_page.dart`：修掉之前的 chat-leak

### 公開文件清理
- README 加完整架構圖（Flutter ↔ backend ↔ ml_service 雙路徑），已升級為 Mermaid
- 移除 README/CHANGELOG 內所有硬寫的 Tailscale hostname/IP

---

## v18.5.0 (2026-03-10) - Self-Hosted Server Support

### 自架伺服器支援
- 新增 `Environment.selfHosted` → 自架伺服器（預設；實際主機由 `lib/config/app_config.dart` 決定，不在 repo 中以明碼公開）
- Admin UI 改為 3 環境切換按鈕（selfHosted / prod / staging）
- 各環境獨立圖示與顏色標識

### 變更檔案
| 類型 | 檔案 | 說明 |
|------|------|------|
| feat | `lib/config/app_config.dart` | 新增 selfHosted 環境 |
| feat | `lib/admin_page.dart` | 3 環境切換 UI |

---

## v18.4.0 (2026-02-22) - App Stabilization & ML Precision Upgrade

### 測量與精準度
- EXIF 焦距提取與 GPS 保護機制
- 多相片融合 UI (Multi-shot fusion)
- Stakeout 導航 + 拍照指南 (Photo Guide)

### UX 優化
- Dashboard UX 翻新：三區塊分類 + 拖曳排序
- BLE 測量 pipeline：race conditions 修復 + Fused Location
- Type Cast Safety 強化
- 中英雙語 Key 支援

---

## v18.3.2 (2025-12-14) - 專案管理邏輯修正

- V2/V3 退出時自動清理未提交的專案區位、專案名稱、樹種
- 追蹤 `_createdAreaIds`、`_createdProjectCodes`、`_createdSpeciesIds`
- WillPopScope 詢問清理

---

## v18.3.1 (2025-12-14) - UX 改進與程式碼清理

- 匯出按鈕 Loading 動畫（Admin、列表、永續報告）
- V3 手動輸入提交按鈕 Loading
- 移除 6 個未使用 imports、修復 linter warnings

---

## v18.3.0 (2025-12-14) - 編譯修復

- 修復 IntegratedTreeFormPage 路由編譯錯誤
- 修復 download_service.dart 正則表達式
- 修復 main.dart import 路徑

---

## v18.2.0 (2025-12-14) - AR 測量優化與安全改進

- AR 測量 GPS 距離模式（Haversine 公式）
- 虛擬 1.3m DBH 測量線
- Google Maps API Key 移至 gradle.properties（安全）
- 新增 `geolocator`、`camera` 套件

---

## v18.1.0 (2025-01-14) - V3 進階服務 UI 整合

- V3 進階服務管理頁面（影像、衝突、AR 校準、ML 同步）
- 首頁「進階服務」入口

---

## v18.0.0 (2025-12-03) - V3 測試套件與 ML 同步

- ML 數據同步服務（WiFi 優先、批次上傳、自動重試）
- V3 測試套件：251 個測試案例 (8,258 行)

---

## v17.1.0 (2025-12-04) - V3 進階服務層

- 影像記錄系統（本地優先 + 雲端同步）
- 衝突解決機制（Optimistic Lock）
- AR 測量整合服務（校準 + 信心度）
- BLE 模擬測試服務

---

## v17.0.0 (2025-12-03) - 專案邊界與智慧匹配

- 地圖手動繪製專案邊界多邊形
- 座標驗證（Ray Casting 演算法）
- BLE 批次匯入自動匹配專案

---

## v16.0.0 (2025-12-02) - 極簡現代化介面重構

- TIPC 港務風格 + 生態綠色主題
- 全新配色系統 + Material 3 + Google Fonts
- 首頁、統計、登入、列表、地圖全面翻新

---

## v15.0.0 (2025-12-02) - 樹種辨識 + AI 聊天

- Pl@ntNet + GBIF + iNaturalist 三合一樹種辨識
- 全新 AI 聊天頁面
- BLE 解碼器優化
