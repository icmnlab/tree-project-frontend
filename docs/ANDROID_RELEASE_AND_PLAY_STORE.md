# Android Release & Google Play

Release signing, store listing prerequisites, and what is **not** in the repository.

**Last reviewed**: 2026-06-29  
**Package name**: `com.sustainable.treeai`  
**Related**: `BUILD_GUIDE.md`, `HANDOFF_SECRETS_CHECKLIST.md` §G, `LOCAL_DEVELOPER_SETUP.md`

---

## Overview

| Stage | Artifact | Signing | In git? |
|-------|----------|---------|---------|
| Local debug | `flutter run` | Auto debug keystore | No |
| Field lab APK | `flutter build apk --release` | Upload keystore **or** temporary debug keystore | No |
| Play Store | `flutter build appbundle --release` | **Upload keystore** (required) | No |
| Play App Signing | Google re-signs for users | Google-managed app signing key | Google holds |

Lab deployment (2026-06) used a **release APK signed with debug keystore** for speed — acceptable for internal field testing only. **Play Store requires a dedicated upload keystore.**

---

## Files you must create (never commit)

```
frontend/android/
├── key.properties              # passwords + Maps key (from key.properties.example)
├── app/keystore/
│   └── upload-keystore-new.jks   # Play upload key — BACK UP OFFLINE
└── local.properties            # SDK path (Android Studio generates)
```

`.gitignore` already excludes these paths.

---

## Step 1 — Create upload keystore (once per app identity)

```powershell
& "$env:Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v `
  -keystore android\app\keystore\upload-keystore-new.jks `
  -alias tree_app_upload_xu.6 `
  -keyalg RSA -keysize 2048 -validity 10000
```

Store passwords in a password manager. **Loss of this file = cannot update the same Play listing.**

Register **upload** certificate SHA-1 in Google Cloud (in addition to debug SHA-1) if using the same Maps API key for release builds.

---

## Step 2 — `key.properties` for release

```properties
storePassword=<from password manager>
keyPassword=<from password manager>
keyAlias=tree_app_upload_xu.6
storeFile=keystore/upload-keystore-new.jks
GOOGLE_MAPS_API_KEY=AIza...android-restricted-key...
```

`storeFile` is relative to `android/app/` per `build.gradle.kts`.

---

## Step 3 — Build App Bundle (Play Store format)

```powershell
cd frontend
flutter build appbundle --release `
  --build-name=18.10.4 --build-number=26 `
  "--dart-define=API_BASE_URL=https://<your-production-host>/api"
```

**Output**: `build/app/outputs/bundle/release/app-release.aab`

Increment `+BUILD` (`versionCode`) for every Play upload.

---

## Step 4 — Google Play Console checklist

Recipient org should own the Play Developer account ($25 one-time).

| Task | Notes |
|------|-------|
| Create app | Package `com.sustainable.treeai` |
| App signing | Enroll in **Play App Signing**; upload first AAB with upload key |
| Internal testing track | Recommended first upload before production |
| Store listing | Title, short/full description, screenshots (phone + optional tablet) |
| App category | Likely **Business** or **Productivity** / field tool |
| Content rating | Complete questionnaire (IARC) |
| Data safety form | Declare location, photos, device IDs per actual API usage |
| Privacy policy URL | **Required** if collecting location/photos — host on institutional site |
| Target API level | Meet Google Play minimum (check current policy; update `compileSdk` in Gradle as needed) |
| Permissions justification | Camera, location, Bluetooth — align with `AndroidManifest.xml` |

This repo does **not** include store marketing copy or privacy policy text — recipient provides.

---

## Google Maps & Play release

Maps SDK key must allow:

- Package: `com.sustainable.treeai`
- SHA-1: **upload keystore** certificate (not only debug)

Without correct SHA-1, release builds show blank maps even if debug works.

---

## Versioning for Play

| Field | Source |
|-------|--------|
| `versionName` | `pubspec.yaml` e.g. `18.10.4` |
| `versionCode` | `+26` in pubspec → monotonic integer |

Every Play upload must increase `versionCode`. See `BUILD_GUIDE.md` §Versioning.

---

## CI/CD release (optional)

GitHub Actions pattern in `BUILD_GUIDE.md` — store keystore as base64 secret, generate `key.properties` in workflow, build AAB, upload artifact or to Play via `r0adkll/upload-google-play` action.

Secrets needed: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS`, `GOOGLE_MAPS_API_KEY`, `API_BASE_URL`, Play service account JSON (for automated upload).

---

## Lab APK vs Play Store

| Use case | Build | Signing |
|----------|-------|---------|
| Internal lab / Tailscale | `flutter build apk --release` | Upload or temporary debug keystore |
| Google Play | `flutter build appbundle --release` | Upload keystore only |
| CI smoke | `flutter build apk --debug` | Debug |

Documented lab workaround (debug-signed release APK): `BUILD_GUIDE.md` §Troubleshooting — **not for Play upload**.

---

## iOS App Store (future)

Not in scope for current Android-first delivery. When needed:

- Align bundle ID policy (`com.sustainable.sustainableTreeai` today)
- Apple Developer Program, provisioning profiles, App Store Connect listing
- See `BUILD_GUIDE.md` §iOS

---

## Related

- [`HANDOFF_SECRETS_CHECKLIST.md`](./HANDOFF_SECRETS_CHECKLIST.md) §G — keystore backup policy
- [`VERIFICATION_CHECKLIST.md`](./VERIFICATION_CHECKLIST.md) — post-build smoke tests
