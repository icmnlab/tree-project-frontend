# 🌳 TreeAI Frontend - 智慧樹木管理系統前端

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.x-blue.svg)](https://dart.dev/)
[![License](https://img.shields.io/badge/License-ISC-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-17.1.0-green.svg)](https://github.com/KyleliuNDHU/tree-project-frontend)

> 基於大語言模型的永續發展分析平台 - Flutter 行動應用程式

---

## 📦 版本紀錄

### v17.1.0 (2025-12-04) - V3 進階服務層 🛠️

#### 🆕 新增功能
- **V3 影像記錄系統** - 樹木照片本地儲存與雲端同步
  - `TreeImageService` - 影像管理服務（本地優先）
  - 支援多種照片類型：全景、樹幹、DBH 測量、樹冠、損傷
  - 佇列上傳機制，離線時自動暫存
- **V3 衝突解決機制** - Optimistic Lock 版本控制
  - `ConflictResolutionService` - 資料衝突檢測與解決
  - 自動重試佇列，支援多人協作同步
  - 衝突對話框 UI 元件
- **AR 測量整合服務** - 增強版 AR DBH 測量
  - `ARMeasurementIntegrationService` - 校準資料與信心度估算
  - 支援快速測量、參照物測量、多角度測量
  - 品質等級評估 (A-F)
- **BLE 模擬測試服務** - 開發環境專用
  - `BLESimulationService` - 模擬 BLE 設備數據
  - 預定義測試情境：單株測量、多株測量、間歇連線
  - 控制面板 Widget 便於開發測試

#### 🔧 V3 服務層擴充
| 服務 | 檔案 | 行數 | 說明 |
|------|------|------|------|
| 影像記錄 | `tree_image_service.dart` | 488 | 本地儲存 + 雲端同步 |
| 衝突解決 | `conflict_resolution_service.dart` | 690 | Optimistic Lock |
| AR 整合 | `ar_measurement_integration_service.dart` | 574 | 校準 + 信心度 |
| BLE 模擬 | `ble_simulation_service.dart` | 747 | 開發測試用 |

#### 📋 變更清單
| 類型 | 說明 |
|------|------|
| feat | 新增 V3 影像記錄系統 (`tree_image_service.dart`) |
| feat | 新增衝突解決服務 (`conflict_resolution_service.dart`) |
| feat | 新增 AR 測量整合服務 (`ar_measurement_integration_service.dart`) |
| feat | 新增 BLE 模擬測試服務 (`ble_simulation_service.dart`) |
| docs | 更新 `V3_DEVELOPMENT_PLAN.md` 實作進度 |

---

### v17.0.0 (2025-12-03) - V3 專案邊界與智慧匹配 🗺️

#### 🆕 新增功能
- **專案邊界管理** - 使用者可在地圖上手動繪製專案邊界多邊形
  - `ProjectBoundaryDrawPage` - 地圖繪製介面，支援拖曳調整頂點
  - `ProjectBoundaryService` - 本地 Ray Casting 演算法快速檢測
  - 5 分鐘快取機制，減少 API 請求
- **座標驗證機制** - 新增樹木時自動檢查座標是否在專案邊界內
  - 有邊界的專案：座標必須在邊界內（可選擇強制提交）
  - 無邊界的專案：不受座標限制
- **批次匯入自動匹配** - BLE 批次匯入時根據座標自動匹配專案名稱
  - 自動填入 `project_name` 和 `project_code`
  - 顯示匹配結果統計 SnackBar

#### 🔧 V3 服務層
- `lib/services/v3/project_boundary_service.dart` - 專案邊界服務
- `lib/services/v3/ml_data_collector.dart` - ML 數據收集服務
- `lib/services/v3/data_filter_service.dart` - 數據過濾服務

#### 📋 變更清單
| 類型 | 說明 |
|------|------|
| feat | 新增 `project_boundary_service.dart` 專案邊界服務 |
| feat | 新增 `project_boundary_draw_page.dart` 地圖繪製頁面 |
| feat | `map_page.dart` 整合專案邊界多邊形顯示 |
| feat | `tree_input_page_v2.dart` 新增座標邊界驗證 |
| feat | `manual_input_page_v2.dart` 新增自動專案匹配 |
| fix | 修復 `ai_chat_page.dart` warningOrange 顏色錯誤 |
| fix | 修復 `ai_assistant_page.dart` warningOrange 顏色錯誤 |

---

### v16.0.1 (2025-12-02) - 錯誤修復 🔧

#### 🔧 修復
- **FAB 遮擋問題** - 修復 FloatingActionButton 被底部導航遮擋的問題
- **後端 OpenAI 兼容性** - 新增 `getTokenLimitParams()` helper 函數
  - 支援 o1/o3 系列模型使用 `max_completion_tokens` 參數
  - 舊版模型 (gpt-4, gpt-4-turbo 等) 仍使用 `max_tokens`（向後兼容）
- **圖片上傳錯誤處理** - 改進 multer fileFilter 錯誤回應格式

#### 📋 變更清單
| 類型 | 說明 |
|------|------|
| fix | `tree_survey_page.dart` FAB 底部邊距調整 |
| fix | `ai.js` OpenAI API 參數兼容性 |
| fix | `speciesIdentification.js` multer 錯誤處理 |
| fix | `openaiController.js` 新增 helper 函數 |
| fix | `aiReportController.js` 新增 helper 函數 |

---

### v16.0.0 (2025-12-02) - 極簡現代化介面重構 🎨

#### 🎨 UI 全面翻新
- **統一設計系統** - 建立 TIPC 港務風格 + 生態綠色主題
  - 全新配色系統 (`colors.dart`)：港務藍、森林綠、海洋青
  - 現代化主題 (`app_theme.dart`)：Material 3 + Google Fonts
  - 圓角設計、漸層效果、玻璃擬態風格
- **首頁重新設計** - 磨砂玻璃底部導航、漸層 AppBar、功能卡片
- **統計頁面優化** - 修復圖表文字重疊問題、旋轉標籤、現代化圖表卡片
- **登入頁面美化** - 藍色漸層背景、動畫效果、玻璃擬態登入卡片
- **樹木列表優化** - 現代化搜尋框、標籤篩選、計數顯示
- **調查頁面更新** - 統一 AppBar 風格、改進空狀態顯示
- **地圖頁面整合** - 漸層標題欄、統一視覺風格

#### 🔧 改進
- 所有頁面採用統一的 `AppColors` 配色
- 移除冗餘的顏色定義，統一使用設計系統
- 改善動畫過渡效果
- 優化載入狀態顯示

#### 📋 變更清單
| 類型 | 說明 |
|------|------|
| style | 新增 `constants/colors.dart` 設計系統配色 |
| style | 新增 `themes/app_theme.dart` 現代化主題 |
| style | 重構 `home_page.dart` 極簡現代化設計 |
| fix | 修復 `statistics_page.dart` 圖表文字重疊 |
| style | 美化 `login_page.dart` 登入介面 |
| style | 優化 `tree_list_page.dart` 列表頁面 |
| style | 優化 `tree_survey_page.dart` 調查頁面 |
| style | 優化 `map_page.dart` 地圖頁面 |

---

### v15.0.0 (2025-12-02) - 重大更新 🎉

#### 🌿 新增功能
- **樹種辨識功能** - 整合 Pl@ntNet + GBIF + iNaturalist 三合一 API
  - 拍照或從相簿選擇圖片進行辨識
  - 顯示辨識結果含學名、信心度
  - 自動標記臺灣原生種
- **AI 聊天頁面** - 全新智慧對話介面
- **BLE 解碼器優化** - 改進藍芽封包處理效能

#### 🔧 改進
- Text-to-SQL 功能優化
- 測試腳本整理至 `archived_test_scripts/` 資料夾
- 程式碼架構重構

#### 📋 變更清單
| 類型 | 說明 |
|------|------|
| feat | 樹種辨識頁面 (`species_identification_page.dart`) |
| feat | 樹種辨識服務 (`species_identification_service.dart`) |
| feat | AI 聊天頁面 (`ai_chat_page.dart`) |
| refactor | BLE 封包解碼器重構 (`ble_packet_decoder.dart`) |
| chore | 測試腳本歸檔整理 |

---

## 📋 目錄

- [專案簡介](#-專案簡介)
- [功能特色](#-功能特色)
- [畫面截圖](#-畫面截圖)
- [快速開始](#-快速開始)
- [專案結構](#-專案結構)
- [設定說明](#-設定說明)
- [UI 設計系統](#-ui-設計系統)
- [建置與發布](#-建置與發布)
- [開發指南](#-開發指南)
- [常見問題](#-常見問題)

---

## 📖 專案簡介

TreeAI 是一個智慧樹木管理系統的行動應用程式，專為臺灣港務公司 (TIPC) 設計：

- 📱 **跨平台** - 支援 Android 和 iOS
- 🎨 **TIPC 風格** - 深藍色系專業介面，搭配生態綠色主題
- 🤖 **AI 助手** - 自然語言查詢資料
- 🗺️ **地圖視覺化** - Google Maps 整合
- 📊 **統計圖表** - 數據分析視覺化

---

## ✨ 功能特色

### 主要功能

| 功能 | 說明 |
|------|------|
| 🌲 **樹木調查** | 新增、編輯、查看樹木資料 |
| 🌿 **樹種辨識** | Pl@ntNet AI 圖片辨識 ⭐ NEW |
| 🤖 **AI 聊天** | 自然語言查詢（支援 Markdown） |
| 🗺️ **地圖顯示** | 樹木位置視覺化 |
| 📊 **統計分析** | 圖表與數據分析 |
| 📷 **QR Code** | 掃描查詢樹木資訊 |
| 📄 **報表匯出** | PDF、Excel 匯出 |
| 🔐 **管理後台** | 管理員功能面板 |

### 技術特點

- 🎯 **Riverpod** 狀態管理
- 🔒 **JWT** 認證機制
- 📍 **Geolocator** 定位服務
- 📸 **Image Picker** 圖片選擇
- 💾 **Secure Storage** 安全儲存

---

## 🎨 UI 設計系統 (v16.0.0 新增)

### 配色方案

```dart
// TIPC 港務色系
portBlue: #0D47A1      // 主色 - 港務深藍
oceanCyan: #00BCD4     // 海洋青
skyBlue: #42A5F5       // 天空藍

// 生態綠色系
forestGreen: #2E7D32   // 森林綠
leafGreen: #43A047     // 葉綠
natureGreen: #66BB6A   // 自然綠

// 輔助色
warmOrange: #FF7043    // 溫暖橘
sunYellow: #FFCA28     // 陽光黃
creativePurple: #7E57C2 // 創意紫
```

### 設計原則
- **極簡現代化** - 簡潔清晰的介面設計
- **一致性** - 統一的視覺語言和交互模式
- **可存取性** - 適當的對比度和字體大小
- **動態效果** - 流暢的動畫過渡

---

## 📱 功能狀態總覽

> 🟢 上線使用中 | 🟡 可用但較少使用 | 🔴 已棄用/停用 | ⚠️ 開發中

### 頁面狀態

| 頁面檔案 | 功能說明 | 狀態 | 備註 |
|----------|----------|------|------|
| `home_page.dart` | 首頁導航 | 🟢 | 主要入口 |
| `ai_assistant_page.dart` | AI 聊天 | 🟢 | 核心功能，Text-to-SQL |
| `map_page.dart` | 地圖顯示 | 🟢 | Google Maps 整合 |
| `tree_survey_page.dart` | 樹木調查列表 | 🟢 | 支援篩選、分頁 |
| `tree_survey_detail_page.dart` | 調查詳情 | 🟢 | |
| `tree_input_page_v2.dart` | 樹木新增 (V2) | 🟢 | 建議使用此版本 |
| `tree_edit_page_v2.dart` | 樹木編輯 | 🟢 | |
| `statistics_page.dart` | 統計圖表 | 🟢 | |
| `admin_page.dart` | 管理後台 | 🟢 | 僅管理員可見 |
| `scan_qrcode_page.dart` | QR Code 掃描 | 🟢 | 掃描查詢樹木 |
| `species_identification_page.dart` | 樹種辨識 | 🟢 | Pl@ntNet AI ⭐ NEW |
| `ai_chat_page.dart` | AI 對話 | 🟢 | 新介面 ⭐ NEW |
| `login_page.dart` | 登入頁面 | 🟢 | |
| `tree_input_page.dart` | 樹木新增 (V1) | 🟡 | 舊版，保留相容 |

### API 連線狀態

| 功能 | 對應 Backend API | 狀態 |
|------|------------------|------|
| 登入驗證 | `POST /api/login` | 🟢 |
| AI 聊天 | `POST /api/chat` | 🟢 |
| 樹木列表 | `GET /api/tree_survey` | 🟢 |
| 地圖資料 | `GET /api/tree_survey/map` | 🟢 |
| 統計資料 | `GET /api/tree_statistics` | 🟢 |
| 報表匯出 | `GET /api/export/excel` | 🟢 |
| 樹種辨識 | `POST /api/species/identify` | 🟢 | ⭐ NEW |

---

## �📸 畫面截圖

| 首頁 | AI 聊天 | 地圖 | 統計 |
|:----:|:------:|:----:|:----:|
| ![Home](assets/screenshots/home.png) | ![Chat](assets/screenshots/chat.png) | ![Map](assets/screenshots/map.png) | ![Stats](assets/screenshots/stats.png) |

> 💡 截圖資料夾需要自行新增：`assets/screenshots/`

---

## 🚀 快速開始

### 前置需求

- **Flutter SDK** 3.0.0 以上
- **Dart SDK** 3.0.0 以上
- **Android Studio** 或 **VS Code**
- **Xcode**（僅 macOS，用於 iOS 開發）

### 檢查環境

```bash
flutter doctor
```

確保所有項目都是 ✅

### 安裝步驟

```bash
# 1. 複製專案
git clone https://github.com/KyleliuNDHU/tree-project-frontend.git
cd tree-project-frontend

# 2. 安裝依賴
flutter pub get

# 3. 執行應用程式
flutter run
```

### 常用指令

```bash
flutter run                    # 執行（Debug 模式）
flutter run --release          # 執行（Release 模式）
flutter build apk              # 建置 Android APK
flutter build ios              # 建置 iOS
flutter clean                  # 清理建置檔案
flutter pub get                # 安裝依賴
flutter pub upgrade            # 更新依賴
```

---

## 📁 專案結構

```
frontend/
├── lib/                            # 📂 主要程式碼
│   ├── main.dart                   # 🚀 主程式入口 + 主題設定
│   │
│   ├── config/                     # ⚙️ 設定
│   │   └── app_config.dart         # API URL、環境設定
│   │
│   ├── constants/                  # 🎨 常數
│   │   └── colors.dart             # TIPC 配色常數 ⭐
│   │
│   ├── models/                     # 📋 資料模型
│   │   └── tree_species.dart       # 樹種模型
│   │
│   ├── services/                   # 🔧 服務層
│   │   ├── carbon_sink_service.dart # 碳匯計算服務
│   │   └── species_identification_service.dart # 樹種辨識服務 ⭐ NEW
│   │
│   ├── screens/                    # 📱 頁面（子頁面）
│   │   ├── home_page.dart          # 首頁
│   │   ├── login_page.dart         # 登入頁
│   │   ├── cities_page.dart        # 城市選擇
│   │   ├── project_areas_page.dart # 專案區域
│   │   └── species_identification_page.dart # 樹種辨識 ⭐ NEW
│   │
│   ├── widgets/                    # 🧩 可重用元件
│   │
│   ├── routes/                     # 🛣️ 路由
│   │   └── auth_guard.dart         # 認證守衛
│   │
│   ├── themes/                     # 🎨 主題
│   │
│   │── ai_assistant_page.dart      # 🤖 AI 聊天頁面 ⭐
│   ├── map_page.dart               # 🗺️ 地圖頁面 ⭐
│   ├── tree_survey_page.dart       # 🌲 樹木調查列表
│   ├── tree_survey_detail_page.dart # 📄 調查詳情
│   ├── tree_input_page.dart        # ✏️ 樹木輸入 (V1)
│   ├── tree_input_page_v2.dart     # ✏️ 樹木輸入 (V2)
│   ├── tree_edit_page_v2.dart      # 📝 樹木編輯
│   ├── statistics_page.dart        # 📊 統計頁面
│   ├── admin_page.dart             # 🔐 管理後台
│   └── scan_qrcode_page.dart       # 📷 QR Code 掃描
│
├── assets/                         # 📦 靜態資源
│   ├── data/                       # 資料檔案
│   ├── icons/                      # 圖標
│   └── images/                     # 圖片
│
├── android/                        # 🤖 Android 設定
│   ├── app/
│   │   ├── build.gradle.kts        # 建置設定
│   │   └── src/main/
│   │       ├── AndroidManifest.xml # 權限設定
│   │       └── res/                # 資源檔案
│   └── key.properties              # 簽名金鑰（不要提交！）
│
├── ios/                            # 🍎 iOS 設定
│   ├── Runner/
│   │   ├── Info.plist              # 權限設定
│   │   └── AppDelegate.swift       # 應用委託
│   ├── Podfile                     # CocoaPods 依賴
│   └── Podfile.lock                # 依賴鎖定
│
├── test/                           # 🧪 測試
│   └── widget_test.dart            # Widget 測試
│
├── pubspec.yaml                    # 📦 依賴管理
└── pubspec.lock                    # 依賴鎖定
```

---

## ⚙️ 設定說明

### API 設定

API 設定位於 `lib/config/app_config.dart`，採用單例模式支援環境切換：

```dart
// lib/config/app_config.dart
enum Environment { prod, staging }

class AppConfig {
  // 正式環境
  static const String prodUrl = 'https://tree-app-backend-prod.onrender.com/api';
  
  // 測試環境
  static const String stagingUrl = 'https://tree-app-backend-staging.onrender.com/api';
}
```

#### 環境切換功能 ⭐

- **正式版 (Prod)**: `https://tree-app-backend-prod.onrender.com/api`
- **測試版 (Staging)**: `https://tree-app-backend-staging.onrender.com/api`

使用者可在管理後台頁面切換環境，切換後需重啟 App。

### Google Maps API Key

#### Android
編輯 `android/app/src/main/AndroidManifest.xml`：

```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_ANDROID_API_KEY"/>
```

#### iOS
編輯 `ios/Runner/AppDelegate.swift`：

```swift
GMSServices.provideAPIKey("YOUR_IOS_API_KEY")
```

### 如何取得 Google Maps API Key

1. 前往 [Google Cloud Console](https://console.cloud.google.com/)
2. 建立新專案或選擇現有專案
3. 啟用 **Maps SDK for Android** 和 **Maps SDK for iOS**
4. 建立 API 金鑰
5. 建議設定 API 金鑰限制（應用程式限制）

---

## 🎨 UI 設計系統

### 配色方案（TIPC 風格）

```dart
// lib/constants/colors.dart
class AppColors {
  static const primary = Color(0xFF0D47A1);      // 深藍色 - 主色
  static const secondary = Color(0xFF1976D2);    // 中藍色
  static const accent = Color(0xFF00BCD4);       // 青色 - 海洋感
  static const background = Color(0xFFE3F2FD);   // 淡藍色背景
  static const text = Color(0xFF212121);         // 主要文字
  static const secondaryText = Color(0xFF757575); // 次要文字
  static const error = Color(0xFFD32F2F);        // 錯誤
  static const success = Color(0xFF0288D1);      // 成功
  static const warning = Color(0xFFFFA000);      // 警告
}
```

### 使用配色

```dart
import 'package:sustainable_treeai/constants/colors.dart';

// 使用方式
Container(
  color: AppColors.primary,
  child: Text(
    'Hello',
    style: TextStyle(color: AppColors.text),
  ),
)
```

### 主題設定

主題定義在 `lib/main.dart` 的 `createAppTheme()` 函數中，包含：

- AppBar 樣式
- Button 樣式
- Input 樣式
- Card 樣式
- Text 樣式

---

## 📦 建置與發布

### Android APK

```bash
# Debug APK
flutter build apk --debug

# Release APK
flutter build apk --release

# APK 位置
# build/app/outputs/flutter-apk/app-release.apk
```

### Android App Bundle（上架 Play Store）

```bash
flutter build appbundle --release

# AAB 位置
# build/app/outputs/bundle/release/app-release.aab
```

### iOS

```bash
# 需要在 macOS 上執行
flutter build ios --release

# 然後在 Xcode 中 Archive 並上傳到 App Store Connect
```

### 簽名設定（Android）

1. 產生 keystore：
```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. 建立 `android/key.properties`：
```properties
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=upload
storeFile=../upload-keystore.jks
```

3. 在 `android/app/build.gradle.kts` 中引用（已設定）

---

## 👨‍💻 開發指南

### 新增頁面

1. 在 `lib/` 或 `lib/screens/` 建立新的 dart 檔案
2. 建立 StatelessWidget 或 StatefulWidget
3. 在 `main.dart` 或路由中註冊

**範例：**

```dart
// lib/screens/example_page.dart
import 'package:flutter/material.dart';
import '../constants/colors.dart';

class ExamplePage extends StatelessWidget {
  const ExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('範例頁面'),
      ),
      body: Center(
        child: Text(
          'Hello World!',
          style: TextStyle(color: AppColors.primary),
        ),
      ),
    );
  }
}
```

### 呼叫 API

使用 Dio 套件：

```dart
import 'package:dio/dio.dart';
import '../config/app_config.dart';

final dio = Dio(BaseOptions(
  baseUrl: AppConfig.baseUrl,
  headers: {'Authorization': 'Bearer $token'},
));

// GET 請求
final response = await dio.get('/tree_survey');

// POST 請求
final response = await dio.post('/chat', data: {
  'message': '列出所有樹木',
});
```

### 狀態管理（Riverpod）

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 定義 Provider
final counterProvider = StateProvider<int>((ref) => 0);

// 使用 Provider
class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(counterProvider);
    return Text('Count: $count');
  }
}
```

---

## ❓ 常見問題

### Q: `flutter pub get` 失敗？

```bash
flutter clean
flutter pub cache repair
flutter pub get
```

### Q: Android 建置失敗？

確認：
1. `android/local.properties` 中的 SDK 路徑正確
2. Gradle 版本相容
3. 執行 `cd android && ./gradlew clean`

### Q: iOS 建置失敗？

```bash
cd ios
rm -rf Pods Podfile.lock
pod install --repo-update
cd ..
flutter clean
flutter run
```

### Q: Google Maps 不顯示？

確認：
1. API Key 已正確設定
2. Google Cloud 專案已啟用 Maps SDK
3. API Key 限制設定正確

### Q: 權限問題？

確認 `AndroidManifest.xml` 和 `Info.plist` 中的權限設定：

**Android 權限：**
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.CAMERA"/>
```

**iOS 權限（Info.plist）：**
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>需要位置權限以顯示您的位置</string>
<key>NSCameraUsageDescription</key>
<string>需要相機權限以掃描 QR Code</string>
```

---

## 📚 學習資源

### Flutter 官方資源
- [Flutter 官方文件](https://docs.flutter.dev/)
- [Flutter Cookbook](https://docs.flutter.dev/cookbook)
- [Flutter Widget 目錄](https://docs.flutter.dev/development/ui/widgets)

### 推薦學習路線
1. Dart 基礎語法
2. Flutter Widget 基礎
3. 狀態管理（Riverpod）
4. 網路請求（Dio）
5. 本地儲存
6. 導航與路由

---

## 🤝 貢獻指南

1. Fork 專案
2. 建立功能分支 (`git checkout -b feature/AmazingFeature`)
3. 提交變更 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 開啟 Pull Request

---

## 📄 授權

本專案使用 ISC 授權條款

---

## 📞 聯絡資訊

- **GitHub**: [@KyleliuNDHU](https://github.com/KyleliuNDHU)
- **專案連結**: [tree-project-frontend](https://github.com/KyleliuNDHU/tree-project-frontend)
- **後端專案**: [tree-project-backend](https://github.com/KyleliuNDHU/tree-project-backend)

---

<p align="center">
  Made with ❤️ using Flutter
</p>
