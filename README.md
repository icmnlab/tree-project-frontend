# TreeAI Frontend

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue.svg)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.x-blue.svg)](https://dart.dev/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> **Sustainable TreeAI** -- Cross-platform mobile application for AI-driven urban tree inventory and carbon analysis.

A Flutter-based field survey app for Taiwan International Ports Corporation (TIPC). Features on-device ML inference (YOLOv8n-seg), AI-powered natural language data queries, automated species identification, and real-time tree trunk measurement via monocular depth estimation.

---

## Table of Contents

- [Features](#features)
- [Screenshots](#screenshots)
- [Tech Stack](#tech-stack)
- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [Configuration](#configuration)
- [Build & Deploy](#build--deploy)
- [Testing](#testing)
- [UI Design System](#ui-design-system)
- [License](#license)

---

## Features

| Feature | Description |
|---------|-------------|
| **Tree Survey** | Create, edit, and view tree records with V2/V3 smart forms |
| **AI Assistant** | Natural language queries (Text-to-SQL) with Markdown rendering |
| **AI Agent** | Autonomous reasoning agent for carbon analysis and data exploration |
| **Map View** | Google Maps with tree markers, project boundaries (GeoJSON), and clustering |
| **Species Identification** | Pl@ntNet AI photo recognition with GBIF/iNaturalist cross-reference |
| **AR Measurement** | DBH measurement via GPS distance mode + 1.3m breast height reference line |
| **ML Scanner** | Real-time on-device YOLOv8n-seg tree trunk detection (TFLite) |
| **BLE Import** | Bluetooth Low Energy batch import from field measurement devices |
| **Report Export** | Excel and PDF report generation and download |
| **Statistics** | Interactive charts and data visualization |
| **QR Code** | Scan to query tree records |
| **CSV Import** | Batch data import from spreadsheets |
| **Carbon Display** | Per-tree and per-project carbon sequestration metrics |

### On-Device ML Models

| Model | Task | Format |
|-------|------|--------|
| YOLOv8n-seg | Tree trunk segmentation | TFLite (8-bit quantized) |
| MobileNet SSD | General object detection | TFLite |
| Object Labeler | Scene classification | TFLite |

### Cloud ML (via Backend Proxy)

| Model | Task | Provider |
|-------|------|----------|
| Depth Pro (350M params) | Monocular depth estimation | Self-hosted FastAPI |
| SAM 2.1 Small (46M params) | Instance segmentation | Self-hosted FastAPI |
| DeepSeek-V3 / GPT-4.1 / Gemini 2.5 | Text-to-SQL generation | SiliconFlow / OpenAI / Google |

---

## Screenshots

*See the app in action on the [Google Play Store](#) or build from source.*

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Framework** | Flutter 3.x, Dart 3.x |
| **State Management** | Riverpod |
| **HTTP Client** | Dio |
| **Maps** | Google Maps Flutter |
| **ML Inference** | TFLite Flutter, Google ML Kit |
| **Camera** | camera, image_picker |
| **Bluetooth** | flutter_blue_plus |
| **Location** | geolocator, geocoding |
| **Storage** | shared_preferences, path_provider |
| **Charts** | fl_chart |
| **QR Code** | mobile_scanner |
| **PDF/Excel** | open_file (download & open) |
| **Auth** | JWT (via backend API) |

---

## Getting Started

### Prerequisites

- Flutter SDK 3.0+
- Dart SDK 3.0+
- Android Studio or VS Code with Flutter extension

```bash
flutter doctor  # Verify environment
```

### Installation

```bash
git clone https://github.com/KyleliuNDHU/tree-project-frontend.git
cd tree-project-frontend
flutter pub get
flutter run
```

### Common Commands

| Command | Description |
|---------|-------------|
| `flutter run` | Debug mode |
| `flutter run --release` | Release mode |
| `flutter build apk --release` | Build Android APK |
| `flutter build appbundle --release` | Build Android App Bundle (Play Store) |
| `flutter build ios --release` | Build iOS |
| `flutter clean` | Clean build artifacts |
| `flutter test` | Run unit tests |

---

## Project Structure

```
lib/
+-- main.dart                          # App entry point, theme, routing
+-- config/
|   +-- app_config.dart                # API URL, environment switching
+-- constants/
|   +-- colors.dart                    # TIPC port-themed color palette
+-- models/                            # Data models
+-- services/                          # API calls & business logic (24 files)
|   +-- api_service.dart               # HTTP layer (Dio + JWT)
|   +-- ai_service.dart                # AI chat & agent integration
|   +-- auth_service.dart              # Authentication
|   +-- species_identification_service.dart
|   +-- carbon_sink_service.dart       # Carbon calculation display
|   +-- carbon_calculation_service.dart
|   +-- ble_data_processor.dart        # BLE device communication
|   +-- tflite_tracking_service.dart   # On-device ML inference
|   +-- pure_vision_dbh_service.dart   # DBH measurement pipeline
|   +-- tree_image_service.dart        # Photo upload
|   +-- conflict_resolution_service.dart
|   +-- ar_measurement_integration_service.dart
|   +-- project_boundary_service.dart
|   +-- ml_data_sync_service.dart      # Training data sync
|   +-- ...
+-- screens/                           # UI pages (17 files)
|   +-- home_page.dart                 # Navigation hub
|   +-- login_page.dart                # JWT authentication
|   +-- ai_chat_page.dart              # AI assistant + agent
|   +-- scanner_page.dart              # Real-time ML scanning
|   +-- map_page.dart                  # Google Maps view
|   +-- tree_survey_page.dart          # Tree list
|   +-- tree_input_page_v2.dart        # Create tree (smart form)
|   +-- tree_edit_page_v2.dart         # Edit tree
|   +-- species_identification_page.dart
|   +-- statistics_page.dart           # Charts & analytics
|   +-- csv_import_page.dart           # Batch CSV import
|   +-- ble_import_page.dart           # BLE device import
|   +-- manual_input_page.dart         # Manual measurement input
|   +-- admin_page.dart                # Admin panel
|   +-- scan_qrcode_page.dart          # QR code scanner
|   +-- ...
+-- widgets/                           # Reusable components
+-- routes/
|   +-- auth_guard.dart                # Route protection
+-- themes/                            # Theme configuration
assets/
+-- ml/                                # TFLite models
|   +-- tree_trunk_seg.tflite          # YOLOv8n-seg (tree trunk)
|   +-- mobilenet_ssd.tflite           # General object detection
|   +-- labels.txt                     # Detection labels
|   +-- tree_trunk_labels.txt          # Trunk segmentation labels
+-- tree_species_tw.json               # Taiwan tree species database
+-- icons/                             # App icons
android/                               # Android platform config
ios/                                    # iOS platform config
test/                                   # Unit & widget tests
```

---

## Configuration

### API Environment

Configured in `lib/config/app_config.dart`. Supports three environments:

| Environment | Description |
|-------------|-------------|
| **selfHosted** | Self-hosted Ubuntu server (default, requires Tailscale VPN) |
| **prod** | Cloud production (Render) |
| **staging** | Cloud staging (Render) |

Environment can be switched from the Admin page (requires app restart).

### Google Maps API Key

**Android:** Add to `android/gradle.properties`:
```properties
MAPS_API_KEY=your_api_key
```

**iOS:** Add to `ios/Runner/AppDelegate.swift`:
```swift
GMSServices.provideAPIKey("your_api_key")
```

> Both `gradle.properties` and `key.properties` are in `.gitignore` and not committed to version control.

---

## Build & Deploy

### Android APK

```bash
# Debug APK (for testing)
flutter build apk --debug

# Release APK (for distribution)
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

# App Bundle (for Google Play Store)
flutter build appbundle --release
# Output: build/app/outputs/bundle/release/app-release.aab
```

### iOS

```bash
flutter build ios --release
# Open in Xcode -> Archive -> Upload to App Store Connect
```

### Signing (Android)

1. Generate keystore:
```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. Create `android/key.properties` (not committed to Git):
```properties
storePassword=<password>
keyPassword=<password>
keyAlias=upload
storeFile=<path>/upload-keystore.jks
```

### Android Configuration

| Setting | Value |
|---------|-------|
| Application ID | `com.sustainable.treeai` |
| Min SDK | 24 (Android 7.0) |
| Target SDK | 35 (Android 15) |
| NDK | 27.0 |
| Java | 11 |

---

## Testing

```bash
flutter test               # Run all tests
flutter test test/v3/       # Run V3 test suite only
```

Test coverage includes:
- AR DBH measurement integration
- BLE device simulation and data processing
- Database normalization validation
- Conflict resolution logic
- Project boundary calculations
- ID generation and uniqueness
- End-to-end survey workflows

---

## UI Design System

TIPC port-themed design with ecological green accents.

### Color Palette

| Color | Hex | Usage |
|-------|-----|-------|
| Port Blue | `#0D47A1` | Primary -- navigation, headers |
| Ocean Cyan | `#00BCD4` | Secondary -- accents, links |
| Forest Green | `#2E7D32` | Ecological -- carbon, trees |
| Leaf Green | `#43A047` | Success states |
| Warm Orange | `#FF7043` | Warnings, alerts |
| Sun Yellow | `#FFCA28` | Highlights |

### Design Principles

- Material 3 with Google Fonts (Noto Sans TC)
- Rounded corners, gradients, frosted glass effects
- Consistent use of `AppColors` constants throughout
- Responsive layout for phones and tablets
- Dark mode support

---

## License

[MIT License](LICENSE)

## Related

- **Backend:** [tree-project-backend](https://github.com/KyleliuNDHU/tree-project-backend) -- Node.js REST API + ML service
- **Author:** [@KyleliuNDHU](https://github.com/KyleliuNDHU) -- National Dong Hwa University
