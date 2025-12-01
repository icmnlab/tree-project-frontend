# 🌳 TreeAI Frontend 交接文件

> **最後更新**: 2024-12-02  
> **版本**: v14.0.0  
> **框架**: Flutter 3.x

---

## 📌 專案概述

**智慧樹木管理系統 (Sustainable TreeAI)** - Flutter 行動應用程式

### GitHub Repository
- **Frontend**: `KyleliuNDHU/tree-project-frontend`
- **Backend**: `KyleliuNDHU/tree-project-backend`

### 技術棧
- **框架**: Flutter 3.x, Dart
- **狀態管理**: Riverpod
- **地圖**: Google Maps Flutter
- **HTTP**: Dio
- **UI 風格**: TIPC 深藍色系

---

## 🎨 UI 設計系統

### 配色方案 (TIPC 風格)

```dart
// lib/constants/colors.dart
static const primary = Color(0xFF0D47A1);      // 深藍色 - 主色
static const secondary = Color(0xFF1976D2);    // 中藍色
static const accent = Color(0xFF00BCD4);       // 青色 - 海洋感
static const background = Color(0xFFE3F2FD);   // 淡藍色背景
```

### 主題設定
主題定義在 `lib/main.dart` 的 `createAppTheme()` 函數中。

---

## 📁 專案結構

```
frontend/
├── lib/
│   ├── main.dart                    # 主程式入口 + 主題
│   ├── constants/
│   │   └── colors.dart              # 配色常數
│   ├── screens/
│   │   ├── home_page.dart           # 首頁
│   │   ├── login_page.dart          # 登入頁
│   │   ├── cities_page.dart         # 城市選擇
│   │   └── project_areas_page.dart  # 專案區域
│   ├── services/
│   │   └── carbon_sink_service.dart # 碳匯計算服務
│   ├── models/
│   │   └── tree_species.dart        # 樹種資料模型
│   ├── ai_assistant_page.dart       # AI 聊天頁面 ⭐
│   ├── map_page.dart                # 地圖頁面 ⭐
│   ├── tree_survey_page.dart        # 樹木調查
│   ├── tree_input_page.dart         # 樹木輸入 (V1)
│   ├── tree_input_page_v2.dart      # 樹木輸入 (V2)
│   ├── statistics_page.dart         # 統計頁面
│   └── admin_page.dart              # 管理後台
├── android/                         # Android 設定
├── ios/                             # iOS 設定
└── assets/                          # 靜態資源
```

---

## 🔧 開發環境設定

### 前置需求
- Flutter SDK 3.x
- Dart SDK
- Android Studio / Xcode
- Google Maps API Key

### 安裝步驟
```bash
cd frontend
flutter pub get
flutter run
```

### 環境變數
在 `lib/config/app_config.dart` 設定 API base URL。

---

## 🚀 近期更新

### UI/UX 改進
- ✅ TIPC 深藍色系配色
- ✅ 漸層背景、彩色陰影、圓角設計
- ✅ AI 聊天支援 Markdown 連結渲染

### 地圖頁面
- ✅ 移除 Android 縮放控制按鈕
- ✅ 新增選單切換功能
- ✅ iOS 權限修復

### iOS 修復
- ✅ DT_TOOLCHAIN_DIR 問題
- ✅ 數字鍵盤小數點輸入
- ✅ deployment target 更新至 14.0

### App Icon
- ✅ Android 圖標加 padding 防止裁切

---

## ⚠️ 已知問題

1. **地圖 Marker 效能** - 大量 Marker 可能卡頓
2. **iOS 權限** - 首次安裝需手動授權
3. **冷啟動慢** - Backend 在 Render 免費方案

---

## 📱 建置指令

### Android
```bash
flutter build apk --release
```

### iOS
```bash
flutter build ios --release
```

---

## 📝 給新 AI 助手的說明

這是一個 Flutter 行動應用，主要頁面：

1. **AI 聊天** (`ai_assistant_page.dart`) - 自然語言查詢
2. **地圖** (`map_page.dart`) - Google Maps 視覺化
3. **樹木調查** (`tree_survey_page.dart`) - CRUD 操作
4. **統計** (`statistics_page.dart`) - 圖表分析
5. **管理後台** (`admin_page.dart`) - 管理功能

UI 使用 **TIPC 深藍色系**，配色定義在 `constants/colors.dart`。
