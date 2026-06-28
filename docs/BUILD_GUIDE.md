# Build & Release Guide

**Current version:** `18.10.4+26` (see `pubspec.yaml`)

---

## Overview

This Flutter app targets field survey and carbon-management workflows on Android and iOS. All environment-specific values—backend URLs, TLS trust rules, feature flags, and map credentials—are injected at build or run time. Nothing personal or deployment-specific is hardcoded in source.

**Zero-hardcoding principle**

| Category | Injected via | Source of truth |
|----------|--------------|-----------------|
| Backend API base URL | `--dart-define=API_BASE_URL` | `lib/config/app_config.dart` |
| Self-signed TLS hosts | `--dart-define=SELF_SIGNED_TRUSTED_HOSTS` | `lib/main.dart` |
| ML service URL (optional) | `--dart-define=TREE_ML_SERVICE_URL` or backend login response | `lib/config/app_config.dart` |
| Feature flags | `--dart-define=ENABLE_*` | `lib/config/app_config.dart` |
| Verification harness | `--dart-define=RUN/SKIP_VERIFICATION_HARNESS`, `FIXTURE_PROJECT_CODE` | `lib/debug/app_verification_harness.dart` |
| Google Maps API key | `android/key.properties` or CI project property | `android/app/build.gradle.kts` → `AndroidManifest.xml` |
| Release signing | `android/key.properties` (keystore fields) | Not in repo |

If `API_BASE_URL` is omitted, the app cannot reach the backend. If the Google Maps key is missing or misconfigured, map screens render blank. See [HANDOFF_SECRETS_CHECKLIST.md](./HANDOFF_SECRETS_CHECKLIST.md) for the full secrets inventory.

Experimental UI surfaces are documented in [EXPERIMENTAL_FEATURES.md](./EXPERIMENTAL_FEATURES.md).

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Flutter SDK 3.x | Match CI; run `flutter --version` and `flutter doctor` |
| Android toolchain | JDK 17, Android SDK |
| iOS toolchain | macOS, Xcode (for iOS builds only) |
| Google Maps API key | Required for map, boundary draw, and maintenance map screens |
| Release keystore | Required for signed Android release builds (see [Signing](#signing)) |

Working directory for all commands below: `project_code/frontend`.

---

## Repository vs local secrets

| In repository (handoff-safe) | **Not** in repository (create locally) |
|------------------------------|----------------------------------------|
| `android/app/build.gradle.kts`, `AndroidManifest.xml`, `build.gradle.kts` | `android/local.properties` (SDK path; `.gitignore`d) |
| `android/key.properties.example` (template) | `android/key.properties` (signing passwords + `GOOGLE_MAPS_API_KEY`) |
| `ios/Podfile`, `ios/Runner/Info.plist` (permissions; `GMSApiKey` from build variable) | Release keystore (`*.jks`), Xcode Signing & Capabilities |
| `pubspec.yaml`, Dart source | Apple Developer account, Maps iOS key (`GOOGLE_MAPS_API_KEY_IOS` in Xcode or xcconfig) |

**Rule:** build scripts and application code live in the repo; keys, signing material, and local SDK paths do not. Details: [HANDOFF_SECRETS_CHECKLIST.md](./HANDOFF_SECRETS_CHECKLIST.md) §B.

---

## Development run

List devices, then run against a target backend:

```powershell
cd frontend
flutter devices
flutter run -d <device-id> --dart-define=API_BASE_URL=https://<your-host>/api
```

### Self-signed TLS (Tailscale, LAN IP)

Hosts with self-signed certificates require an explicit trust list or TLS validation fails:

```powershell
flutter run -d <device-id> `
  --dart-define=API_BASE_URL=https://<your-host>/api `
  --dart-define=SELF_SIGNED_TRUSTED_HOSTS=.ts.net,100.x.x.x
```

Suffix entries starting with `.` (e.g. `.ts.net`) trust the entire tailnet domain.

### Field testing (release + adb logcat)

```powershell
flutter run -d <device-id> --release `
  --dart-define=API_BASE_URL=https://<your-host>/api `
  --dart-define=SELF_SIGNED_TRUSTED_HOSTS=.ts.net `
  --dart-define=ENABLE_FIELD_LOGS=true
```

---

## Build flags reference

All flags are compile-time `--dart-define` values read via `String.fromEnvironment` / `bool.fromEnvironment`.

| Flag | Required | Default | Description |
|------|:--------:|---------|-------------|
| `API_BASE_URL` | Yes | *(empty)* | Backend API base, e.g. `https://host/api`. Empty base URL logs a startup warning and breaks API calls. |
| `SELF_SIGNED_TRUSTED_HOSTS` | Conditional | *(empty)* | Comma-separated host allowlist for self-signed TLS. Supports exact hosts (`100.x.x.x`) and suffixes (`.ts.net`). Empty = standard TLS only. Defined in `lib/main.dart`. |
| `TREE_ML_SERVICE_URL` | No | *(empty)* | ML service URL for local/test APKs. Normally synced from backend after login; build-time override appends `/api/v1`. |
| `ENABLE_FIELD_LOGS` | No | `false` | Emit field-measurement diagnostics to adb logcat (including in release). |
| `ENABLE_ML_CORRECTION_UPLOAD` | No | `false` | Upload user override corrections (DBH, species, etc.) for research pipelines. |
| `ENABLE_EXPERIMENTAL_UI` | No | `false` | Show experimental dashboard cards: `test_scan`, `ai`, `report`, `v3`. See [EXPERIMENTAL_FEATURES.md](./EXPERIMENTAL_FEATURES.md). |
| `RUN_VERIFICATION_HARNESS` | No | `false` | Force startup verification harness in release builds. Debug builds run it by default. |
| `SKIP_VERIFICATION_HARNESS` | No | `false` | Disable harness in debug builds. |
| `FIXTURE_PROJECT_CODE` | No | *(empty)* | Project code for QA fixture tree checks in the harness (requires login + seeded data). |

**Harness behavior** (`lib/debug/app_verification_harness.dart`):

- Debug: runs unless `SKIP_VERIFICATION_HARNESS=true`
- Release: runs only when `RUN_VERIFICATION_HARNESS=true`
- Fixture section skipped unless logged in and `FIXTURE_PROJECT_CODE` is set

**Example — full flag set:**

```powershell
flutter run -d <device-id> --release `
  --dart-define=API_BASE_URL=https://<your-host>/api `
  --dart-define=SELF_SIGNED_TRUSTED_HOSTS=.ts.net `
  --dart-define=TREE_ML_SERVICE_URL=https://<ml-host> `
  --dart-define=ENABLE_FIELD_LOGS=true `
  --dart-define=ENABLE_ML_CORRECTION_UPLOAD=false `
  --dart-define=ENABLE_EXPERIMENTAL_UI=true `
  --dart-define=RUN_VERIFICATION_HARNESS=true `
  --dart-define=FIXTURE_PROJECT_CODE=<your-area-code>
```

---

## Android APK release build

```powershell
cd frontend
flutter build apk --release --build-name=18.10.4 --build-number=26 `
  --dart-define=API_BASE_URL=https://<your-host>/api
```

**Output:** `build/app/outputs/flutter-apk/app-release.apk`

Add `--split-per-abi` to produce per-ABI APKs with smaller download size. The Google Maps key is injected from `key.properties` (see [Google Maps API key](#google-maps-api-key)); it does not go in `--dart-define`.

---

## iOS build

```bash
cd frontend
flutter build ios --release --build-name=18.10.4 --build-number=26 \
  --dart-define=API_BASE_URL=https://<your-host>/api
```

Archive and distribute via Xcode (Product → Archive → Distribute App).

| Platform | Identifier |
|----------|------------|
| Android `applicationId` | `com.sustainable.treeai` |
| iOS Bundle ID | `com.sustainable.sustainableTreeai` |

---

## Google Maps API key

The app uses `google_maps_flutter` for map view, project boundary drawing, and maintenance maps. A valid platform-restricted key is required; otherwise maps render blank or gray.

### Setup

1. **Google Cloud Console** — enable **Maps SDK for Android** (and **Maps SDK for iOS** for iOS builds).
2. Create an **API key** with application restrictions:
   - **Android:** package `com.sustainable.treeai` + signing certificate **SHA-1**
   - **iOS:** bundle ID restriction
3. Obtain SHA-1:
   ```powershell
   keytool -list -v -keystore <keystore.jks> -alias <alias>
   ```
4. Write the key to `frontend/android/key.properties` (gitignored; template: `android/key.properties.example`):
   ```properties
   GOOGLE_MAPS_API_KEY=AIza...your-key...
   ```
   CI alternative: `flutter build apk -PGOOGLE_MAPS_API_KEY=AIza...`

### Injection path (no source changes needed)

`android/app/build.gradle.kts` reads `key.properties` → sets `manifestPlaceholders["GOOGLE_MAPS_API_KEY"]` → `AndroidManifest.xml` meta-data `com.google.android.geo.API_KEY`.

### iOS

`ios/Runner/Info.plist` references `$(GOOGLE_MAPS_API_KEY_IOS)`. Set the value in Xcode build settings or an xcconfig file. Confirm `GMSServices.provideAPIKey` is invoked in `AppDelegate`.

> Restrict keys by platform, package/bundle, and SHA-1. Never commit keys to git.

---

## key.properties

Full example (signing + Maps):

```properties
storePassword=<YOUR_KEYSTORE_PASSWORD>
keyPassword=<YOUR_KEY_PASSWORD>
keyAlias=tree_app_upload_xu.6
storeFile=keystore/upload-keystore-new.jks
GOOGLE_MAPS_API_KEY=AIza...your-key...
```

Deliver passwords and keys through a secrets manager (1Password, CI secrets, environment variables)—not through commits or chat.

---

## Signing

### Recommended layout

```
project_code/frontend/android/
├── app/keystore/upload-keystore-new.jks   # do not commit
└── key.properties                          # do not commit
```

### .gitignore entries

```gitignore
android/key.properties
android/keystore/
*.jks
*.keystore
```

### Verify signing

```powershell
cd frontend
flutter build apk --release --dart-define=API_BASE_URL=https://<your-host>/api
```

### iOS signing

- **Development:** Xcode → Runner target → Signing & Capabilities → *Automatically manage signing* → select Team
- **Release:** Create provisioning profile in Apple Developer Portal → select in Xcode → Product → Archive → Distribute App

---

## CI/CD example

GitHub Actions workflow for tagged releases:

```yaml
name: Build Release
on:
  push:
    tags: ['v*']
jobs:
  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.x'
      - name: Decode keystore
        run: echo "${{ secrets.KEYSTORE_BASE64 }}" | base64 -d > android/app/keystore/upload-keystore-new.jks
      - name: Create key.properties
        run: |
          echo "storePassword=${{ secrets.KEYSTORE_PASSWORD }}" >> android/key.properties
          echo "keyPassword=${{ secrets.KEY_PASSWORD }}" >> android/key.properties
          echo "keyAlias=${{ secrets.KEY_ALIAS }}" >> android/key.properties
          echo "storeFile=keystore/upload-keystore-new.jks" >> android/key.properties
          echo "GOOGLE_MAPS_API_KEY=${{ secrets.GOOGLE_MAPS_API_KEY }}" >> android/key.properties
      - name: Build APK
        run: |
          flutter build apk --release \
            --build-name=18.10.4 --build-number=26 \
            --dart-define=API_BASE_URL=${{ secrets.API_BASE_URL }}
      - uses: actions/upload-artifact@v4
        with:
          name: app-release.apk
          path: build/app/outputs/flutter-apk/app-release.apk
```

Store `KEYSTORE_BASE64`, signing passwords, `GOOGLE_MAPS_API_KEY`, and `API_BASE_URL` as repository or environment secrets.

---

## Versioning

Format: `MAJOR.MINOR.PATCH+BUILD` (Semantic Versioning + monotonic build counter).

| Segment | When to increment |
|---------|-------------------|
| `MAJOR` (e.g. 18 → 19) | Breaking changes, major UI redesign |
| `MINOR` (e.g. .9 → .10) | New features, backward compatible |
| `PATCH` (e.g. .0 → .1) | Bug fixes, minor adjustments |
| `+BUILD` (e.g. +26) | Every store/field release; maps to Android `versionCode` and iOS build number |

Keep `pubspec.yaml` in sync with release artifacts:

```yaml
version: 18.10.4+26
```

Override at build time with `--build-name` and `--build-number` when needed.

---

## Troubleshooting

### Map blank or gray

- `key.properties` missing `GOOGLE_MAPS_API_KEY`
- Maps SDK for Android/iOS not enabled in Google Cloud Console
- API key restrictions mismatch (wrong package name, SHA-1, or bundle ID)

See [Google Maps API key](#google-maps-api-key).

### App cannot reach backend / infinite loading

- `--dart-define=API_BASE_URL` not passed at build or run time
- Self-signed host not listed in `SELF_SIGNED_TRUSTED_HOSTS`

### `Failed host lookup: '<truncated-host>'` (e.g. `https://vm121-standar`)

Shell truncated `API_BASE_URL` during build; the APK baked in an incomplete URL.

**Fix (PowerShell):** quote the entire define argument:

```powershell
flutter build apk --release "--dart-define=API_BASE_URL=https://<full-host>.ts.net/api"
```

Include the trailing `/api`. For Tailscale deployments, use `*.ts.net` hostnames (not `100.x` IPs—TLS cert will not match). Enable MagicDNS on the device. Verify in mobile browser: `https://<full-host>.ts.net/health` should return `OK`.

### `Keystore file not found`

Confirm keystore path exists and `storeFile` in `key.properties` uses a path relative to `android/app/` (e.g. `keystore/upload-keystore-new.jks`).

### `Key password is incorrect`

Check for trailing whitespace or newline characters in `key.properties` values.

### iOS `No signing certificate`

Verify Apple Developer account membership, Keychain certificates, and re-download the provisioning profile.

### `Gradle build daemon has been stopped: since the JVM garbage collector is thrashing`

Gradle JVM ran out of memory. Flutter's `Upgrading gradle.properties` migrator may have overwritten `android/gradle.properties`, removing `org.gradle.jvmargs` and `android.useAndroidX=true` (often accompanied by `[!] Your app isn't using AndroidX.`).

Restore sufficient heap settings, stop the daemon, clean, and rebuild:

```properties
org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=2G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError
android.useAndroidX=true
android.enableJetifier=true
android.builtInKotlin=false
android.newDsl=false
```

Heap guidance: `-Xmx4G` on machines with ≥16 GB RAM; `-Xmx2G` on 8 GB machines. After editing:

```powershell
cd android; .\gradlew --stop; cd ..
flutter clean
flutter build apk --release --dart-define=API_BASE_URL=https://<your-host>/api
```

### Release signing fails but you only need field testing

Release builds always read signing fields from `key.properties`; there is no debug fallback. To sign release with the debug keystore temporarily (SHA-1 must match the key registered in Google Cloud for maps to work):

```properties
storePassword=android
keyPassword=android
keyAlias=androiddebugkey
storeFile=debug.keystore
```

Copy `debug.keystore` to `android/app/`. **Do not use for Play Store upload**—create a dedicated upload keystore for production. See [HANDOFF_SECRETS_CHECKLIST.md](./HANDOFF_SECRETS_CHECKLIST.md) §G.

### `Could not close incremental caches ... this and base files have different roots`

Non-fatal warning; safe to ignore if the build ends with `√ Built build\app\outputs\flutter-apk\app-release.apk`.

**Cause:** project and pub cache on different drives (e.g. project on `D:\`, pub cache on `C:\Users\<user>\AppData\Local\Pub\Cache`). Kotlin incremental compilation cannot compute cross-drive relative paths and falls back to full compilation.

**Mitigation:** colocate project and pub cache on the same drive, or set `PUB_CACHE` to a path on the project drive. Does not affect build output.

### `unable to find directory entry in pubspec.yaml: ...\assets\images\`

`pubspec.yaml` declares an asset directory that does not exist (git does not track empty folders). Build succeeds; add files or create the directory if runtime code references assets inside it.

---

## Related documentation

| Document | Purpose |
|----------|---------|
| [ONBOARDING_READING_PATH.md](./ONBOARDING_READING_PATH.md) | Reading order; GitHub entry point |
| [LOCAL_DEVELOPER_SETUP.md](./LOCAL_DEVELOPER_SETUP.md) | `.env`, `key.properties`, keystores |
| [ANDROID_RELEASE_AND_PLAY_STORE.md](./ANDROID_RELEASE_AND_PLAY_STORE.md) | Play Store release checklist |
| [HANDOFF_SECRETS_CHECKLIST.md](./HANDOFF_SECRETS_CHECKLIST.md) | Secrets inventory and handoff checklist |
| [EXPERIMENTAL_FEATURES.md](./EXPERIMENTAL_FEATURES.md) | Experimental UI flags and dashboard cards |
| `lib/config/app_config.dart` | Runtime config and feature flags |
| `lib/main.dart` | TLS trust override |
| `lib/debug/app_verification_harness.dart` | Startup verification harness |
