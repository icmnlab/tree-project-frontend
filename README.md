# TreeAI Frontend

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.x-blue.svg)](https://dart.dev/)
[![License](https://img.shields.io/badge/License-ISC-yellow.svg)](LICENSE)

智慧樹木管理系統 Flutter 行動應用程式  為臺灣港務公司 (TIPC) 設計。

---

## 目錄

- [功能](#功能)
- [快速開始](#快速開始)
- [專案結構](#專案結構)
- [環境設定](#環境設定)
- [頁面狀態](#頁面狀態)
- [UI 設計系統](#ui-設計系統)
- [建置與發布](#建置與發布)
- [開發指南](#開發指南)
- [常見問題](#常見問題)
- [版本紀錄](#版本紀錄)

---

## 功能

| 功能 | 說明 |
|------|------|
| **樹木調查** | 新增、編輯、查看樹木資料（V2/V3 表單） |
| **AI 助手** | 自然語言查詢（Text-to-SQL，支援 Markdown） |
| **地圖顯示** | Google Maps 樹木位置視覺化 + 專案邊界 |
| **樹種辨識** | Pl@ntNet AI 圖片辨識 |
| **AR 測量** | DBH 測量（GPS 距離模式 + 1.3m 參考線） |
| **BLE 匯入** | 藍牙測量設備批次匯入 |
| **報表匯出** | Excel、PDF 匯出 |
| **統計分析** | 圖表與數據視覺化 |
| **QR Code** | 掃描查詢樹木資訊 |
| **ML 數據同步** | 自動同步訓練數據到後端 |

### 技術特點

- **Riverpod** 狀態管理
- **JWT** 認證
- **TFLite** 裝置端 YOLOv8n-seg 即時偵測
- **三環境切換**  selfHosted / prod / staging

---

## 快速開始

### 前置需求

- Flutter SDK 3.0+
- Dart SDK 3.0+
- Android Studio 或 VS Code

```bash
flutter doctor  # 確認環境
```

### 安裝

```bash
git clone https://github.com/KyleliuNDHU/tree-project-frontend.git
cd tree-project-frontend
flutter pub get
flutter run
```

### 常用指令

```bash
flutter run                    # Debug 模式
flutter run --release          # Release 模式
flutter build apk --release   # 建置 APK
flutter build ios --release    # 建置 iOS
flutter clean                  # 清理
flutter test                   # 執行測試
```

---

## 專案結構

```
frontend/
 lib/
    main.dart                     # 入口 + 主題
    config/
       app_config.dart           # API URL、環境設定
    constants/
       colors.dart               # TIPC 配色
    models/                       # 資料模型
    services/                     # API 呼叫 + 業務邏輯
       api_service.dart          # HTTP 層
       species_identification_service.dart
       carbon_sink_service.dart
       tflite_tracking_service.dart  # 裝置端 ML
       pure_vision_dbh_service.dart  # DBH 測量
       v3/                       # V3 進階服務
           tree_image_service.dart
           conflict_resolution_service.dart
           ar_measurement_integration_service.dart
           project_boundary_service.dart
           ml_data_sync_service.dart
    screens/                      # 頁面
       home_page.dart
       login_page.dart
       scanner_page.dart         # 即時掃描
       species_identification_page.dart
       v3/                       # V3 測量頁面
    widgets/                      # 可重用元件
    routes/                       # 路由
       auth_guard.dart
    themes/                       # 主題
    ai_assistant_page.dart        # AI 聊天
    map_page.dart                 # 地圖
    tree_survey_page.dart         # 調查列表
    tree_input_page_v2.dart       # 新增 (V2)
    tree_edit_page_v2.dart        # 編輯
    statistics_page.dart          # 統計
    admin_page.dart              # 管理後台
    scan_qrcode_page.dart        # QR Code
 assets/                           # 靜態資源
 android/                          # Android 設定
 ios/                              # iOS 設定
 test/                             # 測試（251 案例）
 pubspec.yaml                      # 依賴管理
```

---

## 環境設定

### API 環境切換

設定位於 `lib/config/app_config.dart`。支援三種環境：

| 環境 | URL | 說明 |
|------|-----|------|
| **selfHosted** | `https://100.118.203.75/api` | 自架伺服器（預設） |
| **prod** | `https://tree-app-backend-prod.onrender.com/api` | Render 正式版 |
| **staging** | `https://tree-app-backend-staging.onrender.com/api` | Render 測試版 |

在 Admin 頁面可切換環境（需重啟 App）。

### Google Maps API Key

**Android**  `android/gradle.properties`：
```properties
MAPS_API_KEY=your_api_key
```

**iOS**  `ios/Runner/AppDelegate.swift`：
```swift
GMSServices.provideAPIKey("your_api_key")
```

> `gradle.properties` 和 `key.properties` 已加入 `.gitignore`，不會提交到 Git。

---

## 頁面狀態

>  使用中 |  較少使用 |  已棄用

| 頁面 | 功能 | 狀態 |
|------|------|------|
| `home_page.dart` | 首頁導航 |  |
| `ai_assistant_page.dart` | AI 聊天 (Text-to-SQL) |  |
| `map_page.dart` | 地圖 + 邊界 |  |
| `tree_survey_page.dart` | 調查列表 |  |
| `tree_input_page_v2.dart` | 新增樹木 (V2) |  |
| `tree_edit_page_v2.dart` | 編輯樹木 |  |
| `statistics_page.dart` | 統計圖表 |  |
| `species_identification_page.dart` | 樹種辨識 |  |
| `scanner_page.dart` | 即時 ML 掃描 |  |
| `admin_page.dart` | 管理後台 |  |
| `scan_qrcode_page.dart` | QR Code |  |
| `tree_input_page.dart` | 新增 (V1) |  |

---

## UI 設計系統

TIPC 港務風格 + 生態綠色主題（v16.0.0 建立）。

### 配色

```dart
// lib/constants/colors.dart
portBlue:       #0D47A1   // 主色 - 港務深藍
oceanCyan:      #00BCD4   // 海洋青
forestGreen:    #2E7D32   // 森林綠
leafGreen:      #43A047   // 葉綠
warmOrange:     #FF7043   // 警告橘
sunYellow:      #FFCA28   // 陽光黃
```

### 設計原則
- 極簡現代化、Material 3 + Google Fonts
- 圓角 + 漸層 + 磨砂玻璃效果
- 統一使用 `AppColors` 配色常數

---

## 建置與發布

### Android

```bash
flutter build apk --release
#  build/app/outputs/flutter-apk/app-release.apk

flutter build appbundle --release    # Play Store
#  build/app/outputs/bundle/release/app-release.aab
```

### iOS

```bash
flutter build ios --release
# 在 Xcode 中 Archive  上傳 App Store Connect
```

### 簽名設定

1. 產生 keystore：
```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. 建立 `android/key.properties`（不提交到 Git）

---

## 開發指南

### 新增頁面

```dart
// lib/screens/example_page.dart
import 'package:flutter/material.dart';
import '../constants/colors.dart';

class ExamplePage extends StatelessWidget {
  const ExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('範例')),
      body: Center(
        child: Text('Hello', style: TextStyle(color: AppColors.primary)),
      ),
    );
  }
}
```

### API 呼叫

```dart
import 'package:dio/dio.dart';
import '../config/app_config.dart';

final dio = Dio(BaseOptions(
  baseUrl: AppConfig.baseUrl,
  headers: {'Authorization': 'Bearer $token'},
));

final response = await dio.post('/chat', data: {
  'message': '列出所有樹木',
});
```

### 狀態管理

使用 Riverpod：

```dart
final counterProvider = StateProvider<int>((ref) => 0);

class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(counterProvider);
    return Text('Count: $count');
  }
}
```

---

## 常見問題

| 問題 | 解法 |
|------|------|
| `flutter pub get` 失敗 | `flutter clean && flutter pub cache repair && flutter pub get` |
| Android 建置失敗 | `cd android && ./gradlew clean` |
| iOS 建置失敗 | `cd ios && rm -rf Pods Podfile.lock && pod install --repo-update` |
| Google Maps 不顯示 | 確認 API Key 已設定且啟用 Maps SDK |
| 找不到 key.properties | `android/key.properties` 需手動建立（不在 Git 中） |

---

## 測試

```bash
flutter test               # 所有測試
```

251 個測試案例（V3 測試套件），涵蓋：
- AR DBH 測量整合、BLE 模擬
- 資料庫正規化、衝突解決
- 專案邊界、ID 生成、端到端工作流程

---

## 版本紀錄

完整版本紀錄請見 [CHANGELOG.md](CHANGELOG.md)。

### 主要版本

| 版本 | 日期 | 重點 |
|------|------|------|
| 18.5 | 2026-03-10 | 自架伺服器三環境切換 |
| 18.4 | 2026-02-22 | ML 精度升級 + App 穩定性 |
| 18.3 | 2025-12-14 | 專案管理清理機制 + UX 改進 |
| 18.2 | 2025-12-14 | AR GPS 距離模式 + 安全改進 |
| 18.0 | 2025-12-03 | V3 測試套件 + ML 同步 |
| 17.0 | 2025-12-03 | 專案邊界 + 智慧匹配 |
| 16.0 | 2025-12-02 | UI 全面翻新（TIPC 風格） |
| 15.0 | 2025-12-02 | 樹種辨識 + AI 聊天 |

---

## 授權

ISC License

## 聯絡

- GitHub: [@KyleliuNDHU](https://github.com/KyleliuNDHU)
- Frontend: [tree-project-frontend](https://github.com/KyleliuNDHU/tree-project-frontend)
- Backend: [tree-project-backend](https://github.com/KyleliuNDHU/tree-project-backend)