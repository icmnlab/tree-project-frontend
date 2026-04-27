# sustainable_treeai

Flutter app for field tree survey, carbon-sink analysis, and on-site DBH
measurement. Talks to `tree-project-backend` over HTTPS.

## Stack

- Flutter SDK >= 3.0, Dart >= 3.0
- State management: `flutter_riverpod` + `provider`
- HTTP: `dio` + `http`, SSE via `flutter_client_sse`
- Storage: `shared_preferences`, `flutter_secure_storage`
- Maps: `google_maps_flutter` (primary), `flutter_map` + `latlong2` (fallback)
- Camera / scanning: `camera` (forced Camera2 via `camera_android`), `mobile_scanner`, `image_picker`
- BLE: `flutter_blue_plus` (specific pin `1.32.0`)
- On-device ML: `tflite_flutter`, `google_mlkit_object_detection`
- Sensors: `geolocator`, `sensors_plus`, `permission_handler`
- Reports: `pdf`, `excel`, `fl_chart`, `flutter_markdown`

App version is tracked in `pubspec.yaml` (`version: 18.3.2+10`).

## Quick start

```bash
flutter pub get
flutter run                  # picks up the only environment (selfHosted)
```

The first launch loads `AppConfig` from `SharedPreferences`. There is currently
one environment (`Environment.selfHosted`) pointing at the Tailscale-hosted
backend:

```
https://richardhualienserver.tail124a1b.ts.net/api
```

The historical Render staging/prod environments were retired 2026-04; the
`enum` is kept for forward compatibility (see `lib/config/app_config.dart`).

## Configuration

User-controlled settings live in `SharedPreferences`:

| Key | Set from | Used for |
|-----|----------|----------|
| `environment` | `lib/config/app_config.dart` | Backend selection (currently always `selfHosted`) |
| `self_hosted_ml_url` | API Key Management page | Custom ML Service URL (e.g. ngrok tunnel) |
| `ml_api_key` | API Key Management page | `X-ML-API-Key` for the ML Service |
| `auth_token` | Login flow | JWT for the backend |

There is no compile-time `.env`; everything is configured at runtime through
the in-app management page.

## Project structure

```
frontend/
├── lib/
│   ├── main.dart                  # Riverpod ProviderScope + AppConfig.initialize
│   ├── config/                    # AppConfig (environment / URLs)
│   ├── constants/                 # Static strings, enums
│   ├── routes/                    # Route table
│   ├── themes/                    # ThemeData
│   ├── models/                    # Plain Dart DTOs
│   ├── services/                  # Networking + business services (24 modules)
│   ├── widgets/                   # Reusable UI parts
│   ├── screens/                   # Top-level pages (see below)
│   ├── utils/                     # Helpers, formatters
│   ├── tree_input_page_v2.dart    # V2 manual entry
│   ├── tree_edit_page_v2.dart     # V2 edit form
│   ├── tree_list_page.dart
│   ├── tree_survey_page.dart
│   ├── tree_survey_detail_page.dart
│   ├── project_trees_page.dart
│   ├── statistics_page.dart
│   ├── map_page.dart
│   └── admin_page.dart
├── assets/                        # Images, fonts, on-device ML models
├── android/   ios/   web/   windows/   linux/   macos/
├── test/
└── pubspec.yaml
```

### Screens (`lib/screens/`)

- `login_page.dart` — JWT login.
- `home_page.dart` — landing dashboard.
- `ai_chat_page.dart` — chat with the backend AI assistant + Agent (SSE streaming).
- `species_identification_page.dart` — image-based species ID.
- `scanner_page.dart` — live DBH scan (WebSocket frames to ML service).
- `manual_input_page.dart`, `manual_input_page_v2.dart` — keyboard / Stepper entry.
- `csv_import_page.dart` — admin CSV import.
- `ble_import_page.dart` — BLE measurement device import.
- `cities_page.dart`, `project_areas_page.dart` — area / project browsing.
- `pending_measurement_task_page.dart` — work queue.
- `ai_sustainability_report_screen.dart` — AI-generated report viewer.
- `api_key_management_screen.dart` — runtime ML URL / API key configuration.
- `ip_blacklist_page.dart` — admin tool.
- `user_form_screen.dart` — user CRUD.
- `v3_services_page.dart`, `v3/` — V3 workflow entry points.

### Services (`lib/services/`)

The networking layer is split into per-domain services that wrap `dio` /
`http`. They handle auth header injection, base URL resolution from
`AppConfig`, and JSON shaping. New API calls should be added here, not
inline in widgets.

## Permissions / native config

- Android: `android/app/build.gradle` controls `minSdk` / `targetSdk`. Camera2
  is forced because some LEGACY devices crash on CameraX with three use cases.
- iOS: `ios/Runner/Info.plist` declares camera, location, BLE, and photo
  library usage strings.
- Runtime requests: `permission_handler` (camera, location, bluetooth,
  storage). The login flow asks for the minimum set; deeper screens request
  more on demand.

## Build

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release         # Android
flutter build appbundle --release   # Play Store
flutter build ios --release         # iOS (needs macOS + Xcode)
flutter build web --release         # Web
```

App icons are generated by `flutter_launcher_icons`:

```bash
flutter pub run flutter_launcher_icons:main
```

(See `flutter_launcher_icons_android.yaml` for the Android-specific config.)

## Testing

Tests live under `test/` and use the standard `flutter_test` + `test`
packages. Run with `flutter test`.

## License

See `LICENSE`.
