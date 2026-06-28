# Secrets & Environment Setup

Configuration inventory for backend, mobile builds, and deployment hosts.

| Field | Value |
|-------|-------|
| **Last reviewed** | 2026-06-29 |
| **Principle** | No secrets in git; inject via `.env` and build-time flags |
| **Templates** | `backend/.env.example`, `backend/ml_service/.env.example`, `frontend/android/key.properties.example` |

**Related**: `BUILD_GUIDE.md`, `LAB_DEPLOYMENT_GUIDE.md`, `HANDOVER_CHECKLIST.md`

---

## Overview

All API keys, hostnames, and credentials are supplied through environment variables or local config files. GitHub stores code and documentation only.

| Layer | Config location |
|-------|-----------------|
| Backend runtime | `backend/.env` on deployment host |
| ML service | `backend/ml_service/.env` |
| Android build | `frontend/android/key.properties` + `--dart-define` |
| iOS build | Xcode `GOOGLE_MAPS_API_KEY_IOS` |

---

## A. Third-party services (backend `.env`)

**Workflow**: Register org-owned account → obtain key → paste into `.env` (from `.env.example`). See §D.

### A.1 Required

| Service | Purpose | Variable | How to obtain |
|---------|---------|----------|---------------|
| PostgreSQL | Primary database | `DATABASE_URL` or `DB_*` | Self-hosted; see `LAB_DEPLOYMENT_GUIDE.md` §3.3 |
| JWT signing | Login tokens | `JWT_SECRET` | `openssl rand -hex 64` on host |
| Google Maps | Map UI (frontend) | `GOOGLE_MAPS_API_KEY` in `key.properties` | Google Cloud Console; §H + `BUILD_GUIDE.md` |

### A.2 Recommended (feature degrades gracefully)

| Service | Purpose | Variables | Sign up |
|---------|---------|-----------|---------|
| Cloudinary | Tree photo storage | `CLOUDINARY_*` (3 vars) | https://cloudinary.com |
| PlantNet | Species ID from photo | `PLANTNET_API_KEY` | https://my.plantnet.org |

Without Cloudinary: photo upload fails. Without PlantNet: `/species/identify` unavailable.

### A.3 Optional (AI features)

At least one LLM provider required for AI chat/agent. Experimental UI hidden by default.

| Service | Variables | Notes |
|---------|-----------|-------|
| OpenAI | `OPENAI_API_KEY` | Default provider; agent model `gpt-5.4-mini` |
| Google Gemini | `GEMINI_API_KEY` | Fallback |
| Anthropic | `Claude_API_KEY` | Fallback |
| SiliconFlow | `SiliconFlow_API_KEY`, `Alt1~3_*` | Optional primary chain |
| Google CSE | `GOOGLE_CSE_API_KEY`, `GOOGLE_CSE_CX` | Agent web search tool only |

### A.4 Self-hosted / generated strings

| Item | Variables | Notes |
|------|-----------|-------|
| ML service | `ML_SERVICE_URL`, `ML_SERVICE_PUBLIC_URL`, `ML_API_KEY` | Same `ML_API_KEY` in backend + ml_service |
| Deploy webhook | `DEPLOY_WEBHOOK_SECRET` | Must match GitHub webhook secret |
| Deploy status | `ADMIN_API_TOKEN` | Optional; header `X-Admin-Token` on `GET /webhook/status` |
| ML training (research) | `KAGGLE_KEY`, `ROBOFLOW_API_KEY` in ml_service | Not needed for production deploy |

**GitHub webhook note**: GitHub cannot reach private Tailscale IPs directly. Public webhook delivery may require **Tailscale Funnel** or a public domain — configure after VM network setup (see local ops log, not in git).

---

## B. Frontend build configuration

| Setting | Where | Required |
|---------|-------|----------|
| `API_BASE_URL` | `--dart-define` | Yes |
| `SELF_SIGNED_TRUSTED_HOSTS` | `--dart-define` | If self-signed TLS |
| `GOOGLE_MAPS_API_KEY` | `android/key.properties` | Yes for maps |
| `GOOGLE_MAPS_API_KEY_IOS` | Xcode build setting | iOS only |
| Feature flags | `ENABLE_*`, harness flags | See `BUILD_GUIDE.md` |

Code defaults: empty base URL and empty TLS trust list — forces explicit injection (`app_config.dart`, `main.dart`).

---

## C. Host and account setup

| Item | Action |
|------|--------|
| GitHub repos | Recipient org owns `tree-project-backend` + `tree-project-frontend`; fresh snapshot per `LAB_DEPLOYMENT_GUIDE.md` §0.1 |
| Deployment host | Ubuntu + SSH keys + PM2 + Nginx |
| TLS | Tailscale `*.ts.net` (`setup_tailscale_tls.sh`) or institutional domain + Let's Encrypt |
| ML public URL | `ML_SERVICE_PUBLIC_URL` for client reachability |

---

## D. Org-owned service accounts

Use **lab/project accounts** on GitHub, Cloudinary, PlantNet, AI platforms, Google Cloud, and Tailscale — not personal developer accounts. Simplifies personnel changes: transfer the org account, not individual keys.

---

## E. Security practices

- Never commit secrets; use password manager or CI secrets
- Restrict API keys by package name + SHA-1 (Maps), IP/domain where supported
- Rotate `JWT_SECRET`, `ADMIN_API_TOKEN`, `DEPLOY_WEBHOOK_SECRET` periodically
- Revoke and reissue any key exposed through insecure channels

---

## F. Application user accounts (not DB seeds)

| Environment | Method |
|-------------|--------|
| Production | `node scripts/create_lab_admin.js` after migrate — strong password |
| Dev / CI | `seed_dev_users.js` — blocked when `NODE_ENV=production` |
| Schema | `users.pg.sql` creates table only; no default users |

Disable or delete legacy seed accounts (`admin`, `test`, etc.) before go-live.

**Login field**: use **`username`** (case-sensitive), not display name.

---

## G. Local backups (never in git)

### Release keystore (critical)

| Item | Path | Risk if lost |
|------|------|--------------|
| Upload keystore | `android/keystore/upload-keystore-new.jks` | Cannot update same Play Store app identity |
| Passwords | Password manager | Same |

**Debug keystore** (`~/.android/debug.keystore`) is disposable — regenerating changes SHA-1; update Maps key restrictions.

| Item | Path |
|------|------|
| Android config | `android/key.properties` |
| Backend secrets | `backend/.env`, `ml_service/.env` |
| Admin roster | Ops runbook (not git) |

Optional backup script (local): `frontend/scripts/handoff_backup.ps1`

---

## H. Google Cloud setup (Maps keys)

Maps only — **no Google OAuth login** in current app (`google_sign_in` not used).

**Known IDs**: Android `com.sustainable.treeai`; iOS `com.sustainable.sustainableTreeai`

### H.1 Create project

1. https://console.cloud.google.com → New Project → name e.g. `tree-project`

### H.2 Enable APIs

Library → enable **Maps SDK for Android** (and iOS if building for iOS)

### H.3 Billing

Link billing account — Maps SDK fails without billing (free tier usually sufficient)

### H.4 Create restricted keys

Credentials → Create API key:

**Android key**

- App restriction: Android app — package `com.sustainable.treeai` + SHA-1 from signing keystore:
  ```bash
  keytool -list -v -keystore <keystore.jks> -alias <alias>
  ```
- API restriction: Maps SDK for Android only
- Add both debug and release SHA-1 if using both

**iOS key**

- App restriction: iOS bundle `com.sustainable.sustainableTreeai`
- API restriction: Maps SDK for iOS only

### H.5 Inject into project

```properties
# android/key.properties (not in git)
GOOGLE_MAPS_API_KEY=AIza...
```

iOS: `GOOGLE_MAPS_API_KEY_IOS` in Xcode/xcconfig. Injection wired in `build.gradle.kts` — see `BUILD_GUIDE.md`.

**Debug vs release**

- `flutter run`: only `GOOGLE_MAPS_API_KEY` needed; uses debug keystore automatically
- `flutter build apk --release`: requires full signing fields in `key.properties`

### H.6 OAuth (not used today)

For future Google Sign-In only:

1. OAuth consent screen → External → scopes `openid`, email, profile
2. OAuth client IDs for Android/iOS with same package/bundle + SHA-1
3. Web client for backend token verification if added later

Current auth: username/password + JWT only.

---

## Quick reference: CORS and APK

When building APK:

```
API_BASE_URL=https://<YOUR_DOMAIN>/api
CORS_ALLOWED_ORIGINS=https://<YOUR_DOMAIN>   # backend .env — must match origin
```

Use trusted TLS (Let's Encrypt or Tailscale `*.ts.net`) — avoid self-signed for production field APKs unless `SELF_SIGNED_TRUSTED_HOSTS` is set.
