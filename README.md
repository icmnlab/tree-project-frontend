# 🌳 TreeAI Frontend - 智慧樹木管理系統前端

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.x-blue.svg)](https://dart.dev/)
[![License](https://img.shields.io/badge/License-ISC-yellow.svg)](LICENSE)

> 基於大語言模型的永續發展分析平台 - Flutter 行動應用程式

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
- 🎨 **TIPC 風格** - 深藍色系專業介面
- 🤖 **AI 助手** - 自然語言查詢資料
- 🗺️ **地圖視覺化** - Google Maps 整合
- 📊 **統計圖表** - 數據分析視覺化

---

## ✨ 功能特色

### 主要功能

| 功能 | 說明 |
|------|------|
| 🌲 **樹木調查** | 新增、編輯、查看樹木資料 |
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

## � 功能狀態總覽

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
│   │   └── carbon_sink_service.dart # 碳匯計算服務
│   │
│   ├── screens/                    # 📱 頁面（子頁面）
│   │   ├── home_page.dart          # 首頁
│   │   ├── login_page.dart         # 登入頁
│   │   ├── cities_page.dart        # 城市選擇
│   │   └── project_areas_page.dart # 專案區域
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
