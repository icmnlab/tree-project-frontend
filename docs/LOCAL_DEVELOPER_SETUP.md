# Local Developer Setup

Files and tools **each developer creates on their machine**. None of these are committed to git.

**Last reviewed**: 2026-06-29  
**Related**: `HANDOFF.md` §3.1, `BUILD_GUIDE.md`, `HANDOFF_SECRETS_CHECKLIST.md`

---

## Principle

| In git | Not in git (you create) |
|--------|-------------------------|
| Source code, docs, `.env.example`, `key.properties.example` | `.env`, `key.properties`, keystores, `local.properties` |
| CI workflows | Personal API keys |

---

## Checklist (first day)

### Tools

| Tool | Verify |
|------|--------|
| Git | `git --version` |
| Flutter 3.x | `flutter doctor` (Android toolchain green) |
| Node 18+ | `node -v` (if running backend locally) |
| PostgreSQL 15+ | Optional if using remote lab DB |
| Windows Developer Mode | Required for Flutter plugins on Windows |

### Git identity

```powershell
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

First `git push` to `icmnlab` → browser login via Git Credential Manager (must be org collaborator).

---

## Backend: `backend/.env`

```powershell
cd tree-project-backend
copy .env.example .env   # Windows
# Edit .env
```

| Variable | Minimum for local dev |
|----------|----------------------|
| `DATABASE_URL` | `postgres://user:pass@localhost:5432/treedb` |
| `JWT_SECRET` | `openssl rand -hex 64` |
| `CORS_ALLOWED_ORIGINS` | `http://localhost:3000` or your Flutter origin |

Optional: Cloudinary, PlantNet, AI keys — features degrade gracefully if empty.

**Production**: never use `seed_dev_users.js`; use `create_lab_admin.js`.

---

## Frontend: Android local files

### `android/local.properties` (auto-generated)

Android Studio or Flutter creates this with `sdk.dir=...`. **Gitignored.** Do not commit.

### `android/key.properties` (you create)

```powershell
cd tree-project-frontend\android
copy key.properties.example key.properties
```

**Debug / daily development** — only Maps key required:

```properties
GOOGLE_MAPS_API_KEY=AIza...your-restricted-key...
```

Signing fields can stay as placeholders; `flutter run` uses `~/.android/debug.keystore` automatically.

**Release APK** — fill signing fields (see `BUILD_GUIDE.md` §Signing). For lab testing only, temporary debug signing is documented in `BUILD_GUIDE.md` §Troubleshooting.

### Debug keystore

| Path | Purpose |
|------|---------|
| `%USERPROFILE%\.android\debug.keystore` | Default debug signing |
| SHA-1 from this keystore | Register in Google Cloud for Maps key restriction |

Obtain SHA-1:

```powershell
& "$env:Program Files\Android\Android Studio\jbr\bin\keytool.exe" -list -v `
  -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android
```

If keystore does not exist yet, run `flutter run` once or generate manually (`HANDOFF.md` §3.1).

---

## Frontend: run-time configuration

Backend URL is **never** hardcoded. Inject at run/build:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
```

For physical device on LAN, use your PC's IP. For Tailscale lab server, use full `*.ts.net` hostname with `/api` suffix (quote the define in PowerShell — see `BUILD_GUIDE.md`).

---

## iOS (optional)

| Item | Location |
|------|----------|
| Signing | Xcode → Runner → Signing & Capabilities |
| Maps key | `GOOGLE_MAPS_API_KEY_IOS` in build settings / xcconfig |
| Bundle ID | `com.sustainable.sustainableTreeai` |

Requires macOS + Apple Developer account for device/release builds.

---

## What each teammate must **not** share

- Copying someone else's `key.properties` (SHA-1 mismatch → blank maps)
- Committing `.env` or keystores
- Reusing production `JWT_SECRET` in personal forks

Use org-owned service accounts for Cloudinary, PlantNet, Google Cloud where possible (`HANDOFF_SECRETS_CHECKLIST.md` §D).

---

## Verify setup

| Check | Command / action |
|-------|------------------|
| Backend health | `curl http://localhost:3000/health` → `OK` |
| Backend tests | `node tests/runner.js` |
| Frontend tests | `flutter test` |
| App login | `flutter run` + dev seed user or lab admin |

---

## Related

- [`ANDROID_RELEASE_AND_PLAY_STORE.md`](./ANDROID_RELEASE_AND_PLAY_STORE.md) — upload keystore & Play Console
- [`BUILD_GUIDE.md`](./BUILD_GUIDE.md) — flags, APK/AAB, troubleshooting
