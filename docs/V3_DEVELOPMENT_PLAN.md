# V3 開發計劃書

> 📅 建立日期：2024-12-03
> 🎯 目標：自動化測量工作流程、提升數據品質、支援多人協作

---

## 📋 目錄

1. [核心理念](#核心理念)
2. [兩階段測量工作流程](#兩階段測量工作流程)
3. [手動輸入欄位分析](#手動輸入欄位分析)
4. [專案區域地圖標示系統](#專案區域地圖標示系統)
5. [樹種辨識整合](#樹種辨識整合)
6. [影像記錄系統](#影像記錄系統)
7. [機器學習數據收集](#機器學習數據收集)
8. [多人協作與 Race Condition 處理](#多人協作與-race-condition-處理)
9. [待完成項目與測試清單](#待完成項目與測試清單)
10. [檔案結構規劃](#檔案結構規劃)

---

## 核心理念

### 設計原則
1. **兼容式開發**：V3 獨立於 V2，可隨時切換
2. **自動化優先**：盡可能減少手動輸入
3. **數據可追溯**：所有輸入皆有記錄，支援日後驗證
4. **多人協作安全**：解決 race condition 問題

### V3 vs V2 差異
| 項目 | V2 | V3 |
|------|----|----|
| 流程設計 | 功能逐步增加 | 完整重新設計 |
| 樹種辨識 | 分離功能 | 整合到測量流程 |
| 影像管理 | 無 | 完整記錄系統 |
| 數據收集 | 僅結果 | 過程+結果+修正記錄 |
| 多人協作 | 基本支援 | 完整鎖定機制 |

---

## 兩階段測量工作流程

### 階段 1：VLGEO2 位置測量
```
測量員 A 在現場
    ↓
使用 VLGEO2 測量每棵樹
    ↓
設備記錄：
  - 樹木座標 (x, y) ← 已知
  - 水平距離 (horizontal_distance)
  - 方位角 (azimuth)
  - 俯仰角 (pitch)
  - 樹高 (height)
    ↓
BLE 傳輸到 APP
    ↓
選擇「儲存到待測量」
    ↓
系統自動計算：測量員（測站）位置
```

### 階段 2：AR DBH 測量 + 樹種辨識
```
測量員 B 打開 APP
    ↓
進入「待測量任務」頁面
    ↓
羅盤導航到測站位置
    ↓
到達後，系統提示可以開始測量
    ↓
[整合流程] 拍攝樹木照片
    ↓
同時處理：
  ├─ AR 計算 DBH（參考物件比例法）
  ├─ AI 辨識樹種（可選）
  └─ AI 分析狀況（可選，需驗證模型可用性）
    ↓
結果預填，使用者確認/修改
    ↓
儲存（含影像）
    ↓
下一棵樹
```

### 測站位置計算公式
```dart
// 已知：樹木座標、水平距離、方位角
// 求：測量員（測站）位置

// 方位角是從測量員看向樹木的方向
// 所以測量員在樹木的「反方向」

reverseAzimuth = (azimuth + 180) % 360

// 使用 Haversine 公式反推
stationLat = treeLat - (horizontalDistance / 111320) * cos(reverseAzimuth * π / 180)
stationLon = treeLon - (horizontalDistance / (111320 * cos(treeLat * π / 180))) * sin(reverseAzimuth * π / 180)
```

---

## 手動輸入欄位分析

### 欄位來源分類

| 欄位 | 來源 | V3 自動化方案 | 處理位置 |
|------|------|--------------|----------|
| **tree_id** | 系統生成 | ✅ 後端生成 | `backend/routes/treeSurvey.js` |
| **x_coord / y_coord** | VLGEO2 | ✅ BLE 傳輸 | `ble_data_processor.dart` |
| **tree_height** | VLGEO2 | ✅ BLE 傳輸 | `ble_data_processor.dart` |
| **dbh_cm** | AR 測量 | ✅ 參考物件法 | `ar_measurement_service.dart` |
| **species_id / name** | AI 辨識 | ⚡ 可選自動 | `species_identification_service.dart` |
| **status** | AI 分析 | ⚠️ 待驗證模型 | `tree_condition_service.dart` (新建) |
| **project_name** | 座標比對 | ✅ 自動匹配區域 | `project_area_matcher.dart` (新建) |
| **project_code** | 專案關聯 | ✅ 自動填入 | 同上 |
| **area_id** | 專案關聯 | ✅ 自動填入 | 同上 |
| **tree_remark** | 使用者 | ❌ 手動輸入 | 各 input 頁面 |
| **survey_remark** | 使用者 | ❌ 手動輸入 | 各 input 頁面 |
| **note** | 使用者 | ❌ 手動輸入 | 各 input 頁面 |

### 各頁面手動輸入項目

#### `pending_measurement_task_page.dart` (待測量任務 - 整合模式)
```
一體化處理：
- DBH 測量 (AR 自動 / 手動修改)
- 樹種辨識 (AI 建議 / 手動選擇)
- 狀況評估 (AI 建議 / 手動輸入)
- 備註 (手動輸入)
```

#### `manual_input_page_v3.dart` (手動輸入 - 分離模式)
```
分開處理（給沒有使用 VLGEO2 的情況）：
Step 1: 基本資料 (座標、專案選擇)
Step 2: 樹種選擇 (搜尋 / AI 辨識)
Step 3: 測量數據 (DBH、樹高)
Step 4: 狀態評估
Step 5: 備註與照片
```

### 流程差異圖

```
[待測量任務] - 整合模式
┌─────────────────────────────────────┐
│  一次拍照完成：                      │
│  ┌─────┐                            │
│  │ 📷  │ → DBH + 樹種 + 狀況        │
│  └─────┘                            │
│  使用者確認後提交                    │
└─────────────────────────────────────┘

[Input 頁面] - 分離模式
┌─────────────────────────────────────┐
│  Step 1: 📍 位置                    │
│  Step 2: 🌳 樹種 (可拍照辨識)       │
│  Step 3: 📏 DBH (可 AR 測量)        │
│  Step 4: 📋 狀況                    │
│  Step 5: 📝 備註 + 📷 照片          │
└─────────────────────────────────────┘
```

---

## 專案區域地圖標示系統

### 功能需求

1. **在地圖上繪製專案區域**（不規則多邊形）
2. **兩種專案狀態**：
   - 未劃定區域：樹木座標不受限制
   - 已劃定區域：樹木必須在區域內才能加入
3. **區域驗證規則**：
   - 新劃區域必須包含該專案所有現有樹木
   - 否則需重新繪製或放棄

### 資料結構

```sql
-- 擴展 projects 表
ALTER TABLE projects ADD COLUMN IF NOT EXISTS
  boundary GEOMETRY(POLYGON, 4326),  -- 區域邊界 (PostGIS)
  boundary_defined BOOLEAN DEFAULT FALSE,
  boundary_defined_at TIMESTAMP;

-- 或使用 JSONB 存儲頂點
ALTER TABLE projects ADD COLUMN IF NOT EXISTS
  boundary_vertices JSONB;  -- [{lat, lon}, {lat, lon}, ...]
```

### Flutter 實作

```dart
// lib/services/v3/project_boundary_service.dart

class ProjectBoundaryService {
  /// 檢查座標是否在專案區域內
  bool isPointInProject(double lat, double lon, String projectName);
  
  /// 根據座標自動匹配專案
  Future<ProjectMatch?> autoMatchProject(double lat, double lon);
  
  /// 驗證新區域是否包含所有現有樹木
  Future<bool> validateBoundary(String projectName, List<LatLng> vertices);
  
  /// 儲存專案區域
  Future<void> saveBoundary(String projectName, List<LatLng> vertices);
}
```

### 批次匯入流程

```
CSV 資料匯入
    ↓
遍歷每棵樹的座標
    ↓
┌─ 座標在已知專案區域內？
│   ├─ YES → 自動填入 project_name, project_code, area_id
│   └─ NO  → 加入「未匹配列表」
    ↓
處理未匹配樹木
    ├─ 讓使用者選擇專案
    ├─ 或建立新專案
    └─ 可選：當場繪製區域
```

### 地圖繪製 UI

```dart
// lib/screens/v3/project_boundary_editor.dart

class ProjectBoundaryEditorPage extends StatefulWidget {
  final String projectName;
  final List<LatLng>? existingBoundary;
  final List<LatLng>? existingTreeLocations; // 用於驗證
  
  // UI 功能：
  // 1. 點擊地圖新增頂點
  // 2. 拖曳頂點調整位置
  // 3. 長按頂點刪除
  // 4. 即時顯示區域形狀
  // 5. 顯示現有樹木位置（紅點 = 區域外，綠點 = 區域內）
  // 6. 驗證按鈕：檢查是否包含所有樹木
}
```

---

## 樹種辨識整合

### 模型來源選項

1. **Plant.id API**（付費，準確度高）
2. **Google Cloud Vision**（付費）
3. **TensorFlow Lite 本地模型**（離線可用，需訓練）
4. **自建模型**（需大量標記數據）

### 整合位置

| 場景 | 頁面 | 觸發方式 |
|------|------|----------|
| 待測量任務 | `pending_measurement_task_page.dart` | 拍照時自動 |
| 手動輸入 | `manual_input_page_v3.dart` | 可選按鈕 |
| 樹木編輯 | `tree_edit_page_v3.dart` | 可選按鈕 |
| 獨立辨識 | `species_identification_page.dart` | 現有功能 |

### 狀況辨識（待驗證）

```dart
// 可能的樹木狀況類別
enum TreeCondition {
  healthy,      // 健康
  diseased,     // 有病蟲害
  damaged,      // 受損
  dead,         // 枯死
  leaning,      // 傾斜
  pruned,       // 已修剪
}

// 需要驗證的模型：
// 1. Google Cloud Vision - 無專門樹木狀況模型
// 2. Custom Vision (Azure) - 需自行訓練
// 3. OpenAI Vision API - 可嘗試 prompt engineering
// 
// 結論：目前無現成可用模型，建議：
// - V3 初期：使用者手動輸入
// - 累積照片+標記後：訓練自己的模型
```

---

## 影像記錄系統

### 需求

1. **每棵樹保存測量時的照片**
2. **照片與樹木數據關聯**
3. **支援離線儲存，有網路時同步**
4. **在實驗室可查看照片進行數據驗證**

### 資料結構

```sql
CREATE TABLE tree_images (
  id SERIAL PRIMARY KEY,
  tree_survey_id INTEGER REFERENCES tree_survey(id),
  pending_measurement_id INTEGER REFERENCES pending_tree_measurements(id),
  image_type VARCHAR(50),  -- 'measurement', 'species_id', 'condition', 'general'
  image_path TEXT,         -- 本地路徑 or 雲端 URL
  thumbnail_path TEXT,
  captured_at TIMESTAMP,
  uploaded_at TIMESTAMP,
  metadata JSONB,          -- 拍攝參數、GPS、etc
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 儲存策略

```
拍攝照片
    ↓
儲存到本地 (app_documents/tree_images/{tree_id}/)
    ↓
產生縮圖 (用於列表顯示)
    ↓
記錄到本地 SQLite
    ↓
有網路時 → 上傳到雲端 (S3 / Firebase Storage)
    ↓
更新資料庫記錄
```

### Flutter 實作

```dart
// lib/services/v3/tree_image_service.dart

class TreeImageService {
  /// 儲存測量照片
  Future<String> saveMeasurementImage(String treeId, File image);
  
  /// 獲取樹木的所有照片
  Future<List<TreeImage>> getTreeImages(String treeId);
  
  /// 同步本地照片到雲端
  Future<void> syncPendingUploads();
  
  /// 匯出照片 (用於實驗室分析)
  Future<File> exportTreeImages(List<String> treeIds);
}
```

---

## 機器學習數據收集

### 收集時機

> **當使用者修改自動計算的值時，記錄原始值和修改後的值**

### 收集範圍

| 欄位 | 自動計算來源 | 記錄內容 |
|------|-------------|----------|
| dbh_cm | AR 測量 | 原始值、修改值、參考物件類型、照片 |
| species_id | AI 辨識 | 原始辨識結果、信心度、修改後的樹種 |
| status | AI 分析 | 原始分析、修改值 |
| x_coord / y_coord | VLGEO2 | 原始值、GPS 校正值（如有修改）|
| station position | 公式計算 | 計算值、實際 GPS（如有）|

### 資料結構

```sql
CREATE TABLE ml_training_data (
  id SERIAL PRIMARY KEY,
  
  -- 關聯
  tree_survey_id INTEGER,
  pending_measurement_id INTEGER,
  
  -- 欄位資訊
  field_name VARCHAR(50),  -- 'dbh_cm', 'species_id', etc.
  
  -- 自動值
  auto_value TEXT,
  auto_confidence DOUBLE PRECISION,
  auto_method VARCHAR(50),  -- 'ar_reference', 'ai_vision', 'formula'
  auto_metadata JSONB,      -- 額外參數
  
  -- 使用者修改
  user_value TEXT,
  user_modified BOOLEAN DEFAULT FALSE,
  modification_reason TEXT,  -- 可選：使用者說明為何修改
  
  -- 環境資訊
  device_info JSONB,        -- 手機型號、相機參數
  location_accuracy DOUBLE PRECISION,
  light_condition VARCHAR(20),  -- 'sunny', 'cloudy', 'shade'
  
  -- 影像關聯
  related_image_ids INTEGER[],
  
  -- 時間
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- AR 測量專用欄位
CREATE TABLE ar_measurement_training (
  id SERIAL PRIMARY KEY,
  ml_training_data_id INTEGER REFERENCES ml_training_data(id),
  
  -- 參考物件資訊
  reference_object_type VARCHAR(50),  -- 'a4_paper', 'id_card', 'coin_50'
  reference_actual_size_cm DOUBLE PRECISION,
  reference_pixel_width INTEGER,
  
  -- 測量資訊
  tree_pixel_width INTEGER,
  distance_to_tree_m DOUBLE PRECISION,
  camera_angle_deg DOUBLE PRECISION,
  
  -- 照片
  measurement_image_path TEXT,
  
  -- 計算過程
  pixels_per_cm DOUBLE PRECISION,
  calculated_dbh_cm DOUBLE PRECISION,
  final_dbh_cm DOUBLE PRECISION
);
```

### 標準參考物件

為了機器學習數據的一致性，限定以下參考物件：

| 物件 | 寬度 (cm) | 優點 | 缺點 |
|------|----------|------|------|
| **A4 紙** | 21.0 | 容易取得、標準化 | 易皺、風大不穩 |
| **身分證** | 8.56 | 隨身攜帶、堅硬 | 較小，遠距離誤差大 |
| **50 元硬幣** | 2.8 | 隨身攜帶 | 太小，不建議 |
| **專用測量卡** ⭐ | 15.0 | 自製、有刻度 | 需額外準備 |

建議：製作專用測量卡（15x10 cm 塑膠卡），印有刻度線，便於校準。

### 數據匯出

```dart
// lib/services/v3/ml_data_export_service.dart

class MLDataExportService {
  /// 匯出訓練數據 (CSV 格式)
  Future<File> exportTrainingData({
    DateTime? startDate,
    DateTime? endDate,
    String? fieldName,
    bool onlyModified = true,
  });
  
  /// 匯出 AR 測量數據（含影像）
  Future<File> exportARMeasurementData();
  
  /// 統計分析
  Future<Map<String, dynamic>> getAccuracyStatistics();
}
```

---

## 多人協作與 Race Condition 處理

### 問題場景

```
測量員 A                    測量員 B
    │                          │
    ├── 讀取 Tree #1 ──────────┤
    │                          ├── 讀取 Tree #1
    ├── 修改 DBH = 25 ─────────┤
    │                          ├── 修改 DBH = 30
    ├── 提交 ──────────────────┤
    │         ← 成功            ├── 提交
    │                          │         ← 覆蓋 A 的數據！
```

### 解決方案

#### 1. 樂觀鎖 (Optimistic Locking)

```sql
ALTER TABLE pending_tree_measurements 
ADD COLUMN version INTEGER DEFAULT 1;

-- 更新時檢查版本
UPDATE pending_tree_measurements 
SET dbh_cm = 25, version = version + 1
WHERE id = 1 AND version = 1;
-- 如果 affected_rows = 0，表示被其他人修改過
```

#### 2. 悲觀鎖 (Pessimistic Locking)

```sql
ALTER TABLE pending_tree_measurements ADD COLUMN
  locked_by INTEGER REFERENCES users(id),
  locked_at TIMESTAMP;

-- 開始編輯時鎖定
UPDATE pending_tree_measurements 
SET locked_by = :user_id, locked_at = NOW()
WHERE id = 1 AND (locked_by IS NULL OR locked_at < NOW() - INTERVAL '5 minutes');

-- 完成後解鎖
UPDATE pending_tree_measurements 
SET locked_by = NULL, locked_at = NULL
WHERE id = 1 AND locked_by = :user_id;
```

#### 3. 任務分配機制

```dart
// 每人只能看到分配給自己的樹木
class TaskAssignmentService {
  /// 分配任務給使用者
  Future<void> assignTrees(String userId, List<int> treeIds);
  
  /// 獲取我的任務
  Future<List<PendingTreeMeasurement>> getMyTasks(String userId);
  
  /// 自動分配（按距離）
  Future<void> autoAssignByProximity(String sessionId);
}
```

### 推薦方案

**V3 採用：悲觀鎖 + 任務分配**

```
批次匯入完成
    ↓
管理員分配任務
    ├─ 測量員 A → Tree 1-50
    └─ 測量員 B → Tree 51-100
    ↓
各自只能看到自己的任務
    ↓
開始編輯時自動鎖定（5分鐘）
    ↓
完成後自動解鎖
    ↓
如果超時未完成 → 自動解鎖，其他人可接手
```

---

## 待完成項目與測試清單

### 🔴 Phase 2 待完成項目（當前）

| 項目 | 狀態 | 說明 |
|------|------|------|
| AR 測量服務 | ✅ 已建立 | `ar_measurement_service.dart` |
| AR 測量頁面 | ✅ 已建立 | `ar_dbh_measurement_page.dart` |
| 待測量資料模型 | ✅ 已建立 | `pending_tree_measurement.dart` |
| 待測量服務 | ✅ 已建立 | `pending_measurement_service.dart` |
| 任務導航頁面 | ✅ 已建立 | `pending_measurement_task_page.dart` |
| 後端 API | ✅ 已建立 | `pending_measurements.js` |
| 資料庫遷移 | ✅ 已建立 | `pending_tree_measurements.pg.sql` |
| tree_edit_page_v2 整合 | ✅ 已完成 | AR 按鈕 |
| manual_input_page_v2 整合 | ✅ 已完成 | AR 按鈕 |
| BLE 匯入整合 | ✅ 已完成 | 「儲存到待測量」選項 |
| **模擬測試** | ⏳ 待進行 | 使用 Tree_app_equipment_info 數據 |
| **測站位置計算驗證** | ⏳ 待進行 | 數學公式驗證 |

### 🟡 V3 待開發項目

| 項目 | 優先級 | 說明 |
|------|--------|------|
| 專案區域地圖標示 | 高 | 多邊形繪製、自動匹配 |
| 影像記錄系統 | 高 | 照片儲存、同步、匯出 |
| ML 數據收集 | 中 | 修改記錄、訓練數據 |
| 樹種辨識整合 | 中 | 與測量流程合併 |
| 多人協作鎖定 | 高 | Race condition 處理 |
| 狀況 AI 分析 | 低 | 需驗證模型可用性 |
| 離線模式優化 | 中 | 本地 SQLite 同步 |

### 🧪 測試計劃

#### 單元測試
```
test/v3/
├── unit/
│   ├── station_position_calculation_test.dart  ← 測站位置計算
│   ├── ar_measurement_service_test.dart
│   ├── project_boundary_service_test.dart
│   └── ml_data_collector_test.dart
├── integration/
│   ├── two_stage_workflow_test.dart  ← 完整流程模擬
│   └── multi_user_sync_test.dart
└── simulation/
    └── ble_data_simulation_test.dart  ← 使用實際封包數據
```

---

## 檔案結構規劃

```
frontend/lib/
├── models/
│   └── v3/
│       ├── pending_tree_measurement.dart    (已存在，移動)
│       ├── tree_image.dart
│       ├── ml_training_record.dart
│       └── project_boundary.dart
├── services/
│   └── v3/
│       ├── ar_measurement_service.dart      (已存在，移動)
│       ├── pending_measurement_service.dart (已存在，移動)
│       ├── tree_image_service.dart
│       ├── ml_data_collector.dart
│       ├── project_boundary_service.dart
│       ├── task_assignment_service.dart
│       └── species_integration_service.dart
├── screens/
│   └── v3/
│       ├── ar_dbh_measurement_page.dart     (已存在，移動)
│       ├── pending_measurement_task_page.dart (已存在，移動)
│       ├── manual_input_page_v3.dart
│       ├── tree_edit_page_v3.dart
│       ├── project_boundary_editor.dart
│       └── ml_data_dashboard.dart
└── widgets/
    └── v3/
        ├── ar_overlay_widget.dart
        ├── compass_navigator.dart
        ├── polygon_drawer.dart
        └── image_capture_button.dart

backend/
├── routes/
│   └── v3/
│       ├── pending_measurements.js (已存在，移動)
│       ├── project_boundaries.js
│       ├── tree_images.js
│       └── ml_training_data.js
└── database/
    └── initial_data/
        ├── pending_tree_measurements.pg.sql (已存在)
        ├── tree_images.pg.sql
        ├── ml_training_data.pg.sql
        └── project_boundaries.pg.sql

test/
└── v3_simulation/
    ├── two_stage_measurement_test.dart
    ├── ble_packet_simulation.dart
    └── test_data/
        └── sample_ble_packets.bin
```

---

## 附錄：測站位置計算驗證

### 數學公式

給定：
- 樹木座標 $(T_{lat}, T_{lon})$
- 水平距離 $d$ (公尺)
- 方位角 $\theta$ (度，從北順時針)

求測站座標 $(S_{lat}, S_{lon})$：

$$
\theta_{reverse} = (\theta + 180) \mod 360
$$

$$
S_{lat} = T_{lat} - \frac{d}{111320} \times \cos(\theta_{reverse} \times \frac{\pi}{180})
$$

$$
S_{lon} = T_{lon} - \frac{d}{111320 \times \cos(T_{lat} \times \frac{\pi}{180})} \times \sin(\theta_{reverse} \times \frac{\pi}{180})
$$

### 驗證方法

1. **對稱性測試**：從測站計算到樹木，再從樹木反推測站，應得相同結果
2. **特殊角度測試**：
   - 方位角 0° (正北) → 測站在樹木正南方
   - 方位角 90° (正東) → 測站在樹木正西方
3. **實際數據驗證**：使用 VLGEO2 封包中的數據

---

> 📝 **維護說明**：此文件為 V3 開發的主要參考，請在實作過程中持續更新。

---

## 實作進度 (2025-12-03 更新)

### ✅ 已完成

| 功能 | 檔案 | 說明 |
|------|------|------|
| ML 數據收集服務 | `lib/services/v3/ml_data_collector.dart` | 719行，完整實作 |
| 數據過濾服務 | `lib/services/v3/data_filter_service.dart` | 563行，完整實作 |
| 專案邊界服務 | `lib/services/v3/project_boundary_service.dart` | 448行，Ray Casting 演算法 + 5分鐘快取 |
| 專案邊界 API | `backend/routes/project_boundaries.js` | 493行，turf.js 多邊形操作 |
| 地圖繪製邊界 | `lib/screens/v3/project_boundary_draw_page.dart` | 755行，拖曳頂點、驗證邊界 |
| 地圖多邊形顯示 | `lib/map_page.dart` | 整合專案邊界多邊形、切換按鈕、邊界清單 |
| 新樹木座標驗證 | `lib/tree_input_page_v2.dart` | 提交前驗證座標是否在專案邊界內 |
| 批次匯入自動匹配 | `lib/screens/manual_input_page_v2.dart` | BLE 匯入自動根據座標匹配專案 |
| **V3 影像記錄系統** | `lib/services/v3/tree_image_service.dart` | 488行，本地儲存 + 雲端佇列同步 |
| **衝突解決服務** | `lib/services/v3/conflict_resolution_service.dart` | 690行，Optimistic Lock + 版本號 |
| **AR 測量整合服務** | `lib/services/v3/ar_measurement_integration_service.dart` | 574行，校準資料 + 信心度估算 |
| **BLE 模擬測試服務** | `lib/services/v3/ble_simulation_service.dart` | 747行，模擬設備 + 測試情境 |

### ⏳ 待完成

| 功能 | 優先級 | 說明 |
|------|--------|------|
| 後端影像上傳 API | 中 | 需要 multer + S3/Firebase Storage |
| 後端 V3 衝突處理 API | 中 | 需要資料庫 version 欄位 |
| 前端 UI 整合 | 低 | 將 V3 服務整合到現有頁面 |

