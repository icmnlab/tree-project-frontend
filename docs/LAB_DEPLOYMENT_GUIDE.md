# Lab Deployment Runbook

| Field | Value |
|-------|-------|
| **Purpose** | Deploy and operate the TreeAI backend stack on lab-owned infrastructure without dependency on any individual developer account |
| **Audience** | Lab operators, sysadmins, handover recipients |
| **Scope** | Proxmox VM quick start, Ubuntu production runbook, TLS, redeploy, operations, troubleshooting |
| **Related docs** | `HANDOFF.md`, `HANDOFF_SECRETS_CHECKLIST.md`, `VERIFICATION_CHECKLIST.md`, `AUTHORS.md`, `LICENSE` |
| **Production path** | `/opt/tree-app/backend` (fixed; do not rename) |

---

## Overview

Deploy the full TreeAI stack—Node.js API, PostgreSQL, Nginx reverse proxy, PM2 process manager—on lab-owned hardware. The system must run independently of any specific person's GitHub or cloud accounts.

**Two repositories** (clone and operate separately):

| Repository | Contents |
|------------|----------|
| `tree-project-backend` | Node.js API, migrations, `scripts/deploy.sh`, `ml_service/` (optional) |
| `tree-project-frontend` | Flutter Android app; deployment docs in `docs/` |

**Canonical attribution**: `LICENSE` and **`AUTHORS.md`**. Fresh handover pushes must preserve both files.

**Health check endpoint**: `GET /health` returns plain text `OK` (public, no JWT). Do **not** use `/api/health`—all `/api/*` routes require JWT and return `401` without a token.

---

## Security

### Non-negotiable rules

| Rule | Action |
|------|--------|
| No secrets in git | Never commit passwords, API tokens, private IPs, or `.env` |
| Secrets live in two places only | ① `backend/.env` on the deployment host ② personal password manager |
| Use placeholders in docs | Replace `<SERVER_IP>`, `<YOUR_DOMAIN>`, `<TAILNET>`, `<DB_PASSWORD>`, etc. with your values |
| No personal accounts on prod | Do not log into personal GitHub or cloud accounts on the deployment host |
| Production admin creation | Use `create_lab_admin.js` only; never run `seed_dev_users.js` in production |

### Secret rotation at handover

Rotate all keys per `HANDOFF_SECRETS_CHECKLIST.md` §A before go-live. Revoke old keys held by prior developers.

---

## Architecture

### Single-host lab topology

```
┌─────────────────┐     Wi‑Fi / LAN      ┌──────────────────────────────┐
│ Field Android   │ ──────────────────► │ Lab host (Ubuntu VM)          │
│ Flutter App     │                     │  • Node backend :3000         │
└─────────────────┘                     │  • PostgreSQL                 │
                                        │  • ML service (optional GPU)  │
                                        │  • Nginx reverse proxy :443   │
                                        └──────────────────────────────┘
```

### Component roles

| Component | Role |
|-----------|------|
| **Ubuntu 22.04 / 24.04 LTS** | Backend OS (runs inside Proxmox VM) |
| **Proxmox VE** | Hypervisor; Web UI at `https://<PVE_HOST>:8006` |
| **PostgreSQL 16** | Primary datastore (trees, projects, users) |
| **Node.js 20 LTS** | Express API runtime |
| **PM2** | Process supervisor; app name `tree-backend`, cluster ×2, auto-restart |
| **Nginx** | TLS termination, reverse proxy to `:3000`, rate-limit headers |
| **Tailscale** | Private mesh VPN + free `*.ts.net` trusted TLS certs (recommended for lab) |
| **Let's Encrypt / certbot** | Public-domain TLS (preferred for institutional deployment) |
| **UFW** | Host firewall (SSH, HTTP/HTTPS only) |
| **`.env`** | Runtime secrets (DB, JWT, API keys); not in git |
| **GitHub webhook** | Optional push-triggered deploy via `scripts/deploy.sh` |

### Independence checklist

| Item | Requirement |
|------|-------------|
| Source code | Lab-owned GitHub repo or release tarball; no `.env` |
| Database | Lab-hosted PostgreSQL; run `scripts/migrate.js` |
| System admin | Created via `create_lab_admin.js` (not personal email) |
| Field user accounts | `POST /api/invites` or in-app admin |
| App API URL | Build-time `API_BASE_URL` dart-define |
| ML service | `ML_SERVICE_URL` in `.env`; separate from personal Tailscale |
| TLS | Trusted cert required for Android (see TLS Options) |

### Design constraints

- Do not embed JWT, DB passwords, or ML API keys in the APK.
- Backend `app.js` sets `trust proxy`; Nginx must pass `X-Forwarded-For` for rate limiting and IP blacklist.
- Tree photos stored in Cloudinary; DB backup covers relational data.

---

## Prerequisites

| Requirement | Version / notes |
|-------------|-----------------|
| OS | Ubuntu 22.04 or 24.04 LTS |
| Node.js | 20 LTS |
| PostgreSQL | 15+ (guide tested with 16) |
| Nginx | Latest from apt |
| PM2 | Global install via npm |
| Proxmox VE | For lab VM provisioning (optional if bare metal) |
| Tailscale account | If using `*.ts.net` TLS |
| Flutter SDK | On build machine for APK (not required on server) |
| GitHub repo | Lab-owned `tree-project-backend` (+ frontend for APK build) |

**Access required before starting**:

- Proxmox Web UI credentials (do not document in git)
- VM SSH user (`<VM_USER>`) and network reachability
- Lab GitHub repo clone URL
- Secret values per `HANDOFF_SECRETS_CHECKLIST.md` §A

---

## Handover Day

Complete once when transferring the system to a new organization. Sections map to legacy §0.1–0.7.

### 0.1 Push fresh snapshot to recipient GitHub

Do **not** push full development history—old commits may contain private IPs, credentials, or debug artifacts.

Create a clean single-commit history (**repeat for both backend and frontend repos**). Attribution is declared in `LICENSE` and **`AUTHORS.md`**.

**PowerShell (recommended)**:

```powershell
cd backend   # or frontend
.\scripts\prepare_fresh_handover.ps1
git remote add recipient https://github.com/<RECIPIENT>/tree-project-backend.git
git push recipient handover:main
git checkout main
```

**Manual (bash)**:

```bash
cd frontend   # or backend
git checkout main && git pull
git checkout --orphan handover
git add -A
git commit -m "Initial handover snapshot (2026-06)

Copyright (c) 2025 KyleliuNDHU. See LICENSE and AUTHORS.md.

Original development and primary maintenance by KyleliuNDHU.
Fresh history push without prior commit log."
git remote add recipient https://github.com/<RECIPIENT>/tree-project-frontend.git
git push recipient handover:main
git checkout main
```

**Outgoing party only** (local evidence; do not upload to recipient):

```bash
git log --oneline --decorate > handover_evidence_git_log.txt
git shortlog -sn > handover_evidence_shortlog.txt
```

CI runs automatically on push (workflows require no GitHub Secrets).

### 0.2 Rotate all secrets

Follow `HANDOFF_SECRETS_CHECKLIST.md` §A: revoke old keys, issue new keys, populate `backend/.env` (from `.env.example`). Google Maps key goes in `frontend/android/key.properties` (from `key.properties.example`).

### 0.3 Deploy backend host

Execute [Production Runbook](#production-runbook) §3.1–3.10. Run migrate with `SKIP_CSV_IMPORT=1`. Start PM2.

### 0.4 Configure deploy webhook

GitHub repo → **Settings → Webhooks → Add webhook**:

| Field | Value |
|-------|-------|
| Payload URL | `https://<YOUR_DOMAIN>/webhook/deploy` |
| Content type | `application/json` |
| Secret | Must match `DEPLOY_WEBHOOK_SECRET` in `backend/.env` |
| Events | Just the push event |

Push to `main` triggers `scripts/deploy.sh` (see [Redeploy / Webhook](#redeploy--webhook)).

> **Note (public internet)**: GitHub webhooks require the deployment host to be reachable from the public internet. If the VM is Tailscale-only, configure **Tailscale Funnel** or an institutional reverse proxy. Detailed Funnel setup is deferred to post–on-campus VM work; document the chosen ingress path in local ops notes.

### 0.5 Create production admin

The `users` table has no pre-seeded accounts. After migrate completes:

```bash
cd /opt/tree-app/backend
node scripts/create_lab_admin.js \
  --username labadmin \
  --password '<STRONG_PASSWORD>' \
  --display 'Lab Administrator'
```

| Rule | Detail |
|------|--------|
| Run once | Duplicate username throws an error |
| Never in production | `seed_dev_users.js` (creates `admin/12345` weak test accounts) |
| Legacy seed cleanup | Deactivate or delete historical `admin`/`test`/`tt2` accounts if present |

### 0.6 Build APK and validate TLS

See [APK Build](#apk-build) and [Verification](#verification).

**Android TLS requirement**: The device rejects self-signed certificates. `API_BASE_URL` must point to a **trusted** cert (Let's Encrypt or Tailscale `*.ts.net`). Self-signed or raw IP HTTPS causes `CERTIFICATE_VERIFY_FAILED` and blocks all API calls.

### 0.7 Handover day checklist

- [ ] Both repos fresh-pushed; CI green on `main`
- [ ] `HANDOFF_SECRETS_CHECKLIST.md` §A keys rotated
- [ ] Backend deployed; `GET /health` returns `OK`
- [ ] Webhook deploy tested (push trivial change → auto deploy)
- [ ] Admin created via `create_lab_admin.js`; legacy seed accounts removed/disabled
- [ ] APK built and field login verified on physical device
- [ ] `VERIFICATION_CHECKLIST.md` completed
- [ ] No residual personal-account access (Tailscale, GitHub webhook, cloud services)
- [ ] `main` branch protection enabled with required CI check

---

## Quick Start — Proxmox VM

End-to-end procedure for redeploying on a Proxmox VE VM. For rationale and tunables, see [Production Runbook](#production-runbook).

**Placeholders**: `<PVE_HOST>` = Proxmox host; `<VM_USER>` = Linux login; `<YOUR_DOMAIN>` = app-facing hostname; `<TAILNET>` = Tailscale tailnet name.

### Step 0 — Access Proxmox and boot VM

1. Open `https://<PVE_HOST>:8006`; authenticate with lab-provided credentials (realm: `Proxmox VE authentication` or `Linux PAM`).
2. Select target VM in left tree → **Start**.
3. Open **>_ Console** for web terminal, or run `ip a` in console then `ssh <VM_USER>@<SERVER_IP>` from workstation.
4. Verify OS: `lsb_release -a` (expect Ubuntu 22.04 or 24.04 LTS).

### Step 1 — Install system packages

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl ufw nginx postgresql postgresql-contrib
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
node -v          # expect v20.x
sudo npm install -g pm2
```

### Step 2 — Create PostgreSQL database and user

```bash
sudo -u postgres psql <<'SQL'
CREATE USER treeapp WITH PASSWORD '<DB_PASSWORD>';
CREATE DATABASE treedb OWNER treeapp;
GRANT ALL PRIVILEGES ON DATABASE treedb TO treeapp;
SQL
```

### Step 3 — Clone code to `/opt/tree-app`

```bash
sudo mkdir -p /opt/tree-app/logs
sudo chown -R "$USER" /opt/tree-app
cd /opt/tree-app
git clone https://github.com/<ORG>/tree-project-backend.git backend
cd backend
npm install --production
```

### Step 4 — Configure `.env`

```bash
cd /opt/tree-app/backend
cp .env.example .env
nano .env
```

Minimum required (full list: `HANDOFF_SECRETS_CHECKLIST.md` §A):

```ini
NODE_ENV=production
PORT=3000
DATABASE_URL=postgres://treeapp:<DB_PASSWORD>@localhost:5432/treedb
DB_SSL=false
JWT_SECRET=<output of: openssl rand -hex 64>
CORS_ALLOWED_ORIGINS=https://<YOUR_DOMAIN>
# Optional: deploy webhook only
DEPLOY_WEBHOOK_SECRET=<random string>
```

### Step 5 — Initialize database and admin

```bash
cd /opt/tree-app/backend
SKIP_CSV_IMPORT=1 node scripts/migrate.js
node scripts/create_lab_admin.js \
  --username labadmin \
  --password '<STRONG_PASSWORD>' \
  --display 'Lab Administrator'
```

Post-migrate state: business tables empty; reference data (species, aliases, condition enums) loaded.

### Step 6 — Start PM2 and enable boot persistence

```bash
cd /opt/tree-app/backend
pm2 start ecosystem.config.js     # name=tree-backend, cluster ×2
pm2 save
pm2 startup systemd               # run the sudo command it prints
curl -sf http://127.0.0.1:3000/health   # expect 200, body OK
```

### Step 7 — Nginx reverse proxy and TLS

```bash
sudo nano /etc/nginx/sites-available/tree-app   # template: Production Runbook §3.8
sudo ln -s /etc/nginx/sites-available/tree-app /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

TLS (pick one):

```bash
# A. Institutional domain + Let's Encrypt (preferred)
sudo certbot --nginx -d <YOUR_DOMAIN>

# B. Tailscale *.ts.net certificate (lab / mesh)
# Enable HTTPS Certificates in Tailscale admin console first.
# Pass full ts.net hostname as argument (do not rely on auto-detection):
sudo bash scripts/setup_tailscale_tls.sh <hostname>.<TAILNET>.ts.net
```

### Step 8 — Firewall

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
```

### Step 9 — Build field APK

One-time on **build machine** (signing keys not in git):

- Populate `frontend/android/key.properties` with `GOOGLE_MAPS_API_KEY` (see `HANDOFF_SECRETS_CHECKLIST.md` §H).
- Set `API_BASE_URL` to match Step 7:
  - Tailscale: `https://<hostname>.<TAILNET>.ts.net/api`
  - Let's Encrypt: `https://<YOUR_DOMAIN>/api`
- `CORS_ALLOWED_ORIGINS` in backend `.env` must match the same origin (scheme + host).

```bash
cd frontend
flutter build apk --release \
  --dart-define=API_BASE_URL=https://<YOUR_DOMAIN>/api
# Self-signed hosts only (not needed for Tailscale or Let's Encrypt):
#   --dart-define=SELF_SIGNED_TRUSTED_HOSTS=<host>
```

### Step 10 — Acceptance

```bash
curl https://<YOUR_DOMAIN>/health    # no -k; expect 200 and body OK
```

| Check | Expected |
|-------|----------|
| TLS | No certificate error without `-k` |
| Body | Plain text `OK` |
| Path | `/health` (not `/api/health`) |

Complete `VERIFICATION_CHECKLIST.md`.

---

## Production Runbook

Detailed Ubuntu procedure. All paths assume `/opt/tree-app/backend`.

### 3.1 System requirements

| Item | Version / notes |
|------|-----------------|
| OS | Ubuntu 22.04 or 24.04 LTS |
| Node.js | 20 LTS |
| PostgreSQL | 15+ |
| Reverse proxy | Nginx |
| Process manager | PM2 cluster mode, 2 workers |
| ML (optional) | Python 3.10+, GPU; see `ml_service/README.md` |

### 3.2 Install system packages

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl ufw nginx postgresql postgresql-contrib
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
node -v   # expect v20.x
sudo npm install -g pm2
```

### 3.3 Create PostgreSQL database and user

```bash
sudo -u postgres psql <<'SQL'
CREATE USER treeapp WITH PASSWORD '<DB_PASSWORD>';
CREATE DATABASE treedb OWNER treeapp;
GRANT ALL PRIVILEGES ON DATABASE treedb TO treeapp;
SQL
```

Connection string: `DATABASE_URL=postgres://treeapp:<DB_PASSWORD>@localhost:5432/treedb` with `DB_SSL=false` for localhost.

### 3.4 Clone code to `/opt/tree-app`

```bash
sudo mkdir -p /opt/tree-app/logs
sudo chown -R "$USER" /opt/tree-app
cd /opt/tree-app
git clone https://github.com/<ORG>/tree-project-backend.git backend
cd backend
npm install --production
```

Clone **lab-owned** repo only. Fresh snapshot procedure: [Handover Day §0.1](#01-push-fresh-snapshot-to-recipient-github).

### 3.5 Configure `.env`

```bash
cd /opt/tree-app/backend
cp .env.example .env
nano .env
```

```ini
NODE_ENV=production
PORT=3000
DATABASE_URL=postgres://treeapp:<DB_PASSWORD>@localhost:5432/treedb
DB_SSL=false
JWT_SECRET=<openssl rand -hex 64>
CORS_ALLOWED_ORIGINS=https://<YOUR_DOMAIN>
# Optional: deploy webhook
DEPLOY_WEBHOOK_SECRET=<random string>
# Optional: GET /webhook/status log access; omit → endpoint returns 401
ADMIN_API_TOKEN=<random string>
```

Full variable list: `HANDOFF_SECRETS_CHECKLIST.md` §A.

### 3.6 Initialize database and admin

```bash
cd /opt/tree-app/backend
SKIP_CSV_IMPORT=1 node scripts/migrate.js
node scripts/create_lab_admin.js \
  --username labadmin \
  --password '<STRONG_PASSWORD>' \
  --display 'Lab Administrator'
```

Never run `seed_dev_users.js` in production (`NODE_ENV=production` blocks it regardless).

### 3.7 Start PM2 and enable boot persistence

```bash
cd /opt/tree-app/backend
pm2 start ecosystem.config.js
pm2 save
pm2 startup systemd
curl -sf http://127.0.0.1:3000/health
```

Logs: `/opt/tree-app/logs/backend-out-*.log`, `backend-error-*.log`.

### 3.8 Nginx reverse proxy template

Save as `/etc/nginx/sites-available/tree-app`:

```nginx
server {
    listen 443 ssl;
    server_name <YOUR_DOMAIN>;

    ssl_certificate     /opt/tree-app/ssl/fullchain.pem;   # see TLS Options
    ssl_certificate_key /opt/tree-app/ssl/privkey.pem;

    client_max_body_size 12M;   # tree photo uploads (backend limit 10M)

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/tree-app /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

`POST /webhook/deploy` uses the same vhost. Legacy separate `:8443` listener is not required.

### 3.9 TLS certificates

See [TLS Options](#tls-options). Android requires a trusted certificate.

### 3.10 Firewall

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
```

### 3.11 Deploy webhook

Configure per [Handover Day §0.4](#04-configure-deploy-webhook). Push to `main` runs:

`pull` → `npm install --production` → `run_pending_migrations.js` → `pm2 reload` → health check → rollback on failure.

Mechanism details: `HANDOFF.md` §6.1.

### 3.12 Database backup cron

```bash
crontab -e
# Daily 03:00
0 3 * * * /opt/tree-app/backend/scripts/backup_db.sh >> /opt/tree-app/logs/backup.log 2>&1
```

Tree photos reside in Cloudinary; DB backup covers primary relational data.

### 3.13 Build and distribute APK

See [APK Build](#apk-build). Run `VERIFICATION_CHECKLIST.md` before field rollout.

---

## TLS Options

Android rejects self-signed certificates. Choose one path.

### Option A — Institutional domain + Let's Encrypt (production preferred)

```bash
sudo certbot --nginx -d <YOUR_DOMAIN>
```

- `API_BASE_URL=https://<YOUR_DOMAIN>/api`
- `CORS_ALLOWED_ORIGINS=https://<YOUR_DOMAIN>`

### Option B — Tailscale `*.ts.net` certificate (lab / mesh)

**Prerequisites**: Tailscale installed on VM; HTTPS Certificates enabled in Tailscale admin console.

**Recommended (nginx rate limits + security headers preserved)**:

```bash
cd /opt/tree-app/backend
sudo bash scripts/setup_tailscale_tls.sh <hostname>.<TAILNET>.ts.net
```

| Requirement | Detail |
|-------------|--------|
| Argument mandatory | Pass full `*.ts.net` hostname; auto-detection fails silently under `set -o pipefail` |
| Cert validity | ~90 days; cron at `/etc/cron.d/tree-tls-renew` |
| Cert paths | `/opt/tree-app/ssl/ts.crt`, `ts.key` |
| Nginx backup path | `/opt/tree-app/nginx-conf-backups/` — **never** under `sites-enabled/` |

**Quick alternative (bypasses nginx rate limits; operator-level, no sudo)**:

```bash
tailscale serve --bg --https 443 http://127.0.0.1:3000
# Disable: tailscale serve --https=443 off
```

**Manual equivalent**:

```bash
sudo tailscale cert \
  --cert-file /opt/tree-app/ssl/ts.crt \
  --key-file /opt/tree-app/ssl/ts.key \
  <hostname>.<TAILNET>.ts.net
# Update nginx server_name and ssl_certificate paths, then:
sudo nginx -t && sudo systemctl reload nginx
```

- `API_BASE_URL=https://<hostname>.<TAILNET>.ts.net/api`

### Option C — Self-signed (not recommended)

Requires `--dart-define=SELF_SIGNED_TRUSTED_HOSTS=<host>` at APK build. Field devices will fail TLS verification without this flag.

### TLS validation

```bash
curl https://<YOUR_DOMAIN>/health    # no -k; expect OK, no cert error
```

---

## APK Build

Execute on a **build machine**, not the production server.

### Prerequisites

| File | Purpose |
|------|---------|
| `frontend/android/key.properties` | `GOOGLE_MAPS_API_KEY` (required for map screen) |
| Backend `.env` | `CORS_ALLOWED_ORIGINS` must match APK origin |

### Build command

```bash
cd frontend
flutter build apk --release \
  --dart-define=API_BASE_URL=https://<YOUR_DOMAIN>/api
```

| Deployment type | `API_BASE_URL` |
|-----------------|----------------|
| Let's Encrypt | `https://<YOUR_DOMAIN>/api` |
| Tailscale | `https://<hostname>.<TAILNET>.ts.net/api` |

APK contains no personal keys or tokens. Distribute to field surveyors via lab-approved channel.

### App config reference

Inspect `lib/config/app_config.dart` and build-time `dart-define` values. Lab can retarget API endpoint without source changes.

---

## Verification

### Health check

```bash
curl https://<YOUR_DOMAIN>/health
```

| Endpoint | Auth | Expected |
|----------|------|----------|
| `GET /health` | None | `200`, body `OK` |
| `GET /api/health` | JWT required | `401` without token — **not** a failure indicator |

A `401` on `/api/*` with valid TLS still proves nginx → backend connectivity. Use `/health` for automated checks.

### Full checklist

Run every item in `VERIFICATION_CHECKLIST.md` after initial deploy and after each major release.

---

## Redeploy / Webhook

### Automatic (webhook configured)

Push to `main`. Host executes `scripts/deploy.sh`:

1. `git pull`
2. `npm install --production`
3. `node scripts/run_pending_migrations.js`
4. `pm2 reload ecosystem.config.js`
5. Health check
6. Rollback on failure

### Manual redeploy

```bash
cd /opt/tree-app/backend
git pull
npm install --production
node scripts/run_pending_migrations.js
pm2 reload ecosystem.config.js
curl -sf http://127.0.0.1:3000/health
```

---

## Operations / Logs

### Routine status

```bash
pm2 status
pm2 logs tree-backend
sudo systemctl status nginx postgresql
df -h
```

### PM2 logs (process name: `tree-backend`)

```bash
pm2 status
pm2 logs tree-backend
pm2 logs tree-backend --lines 200
pm2 logs tree-backend --err
pm2 logs tree-backend --out
pm2 describe tree-backend
ls -l /opt/tree-app/logs
tail -n 100 /opt/tree-app/logs/backend-error-0.log
```

### Nginx logs

```bash
sudo tail -n 100 /var/log/nginx/access.log
sudo tail -n 100 /var/log/nginx/error.log
sudo nginx -t
sudo ss -ltnp | grep ':443'
```

### Backend / TLS self-test (on VM)

```bash
curl -sf http://127.0.0.1:3000/health
curl https://<hostname>.<TAILNET>.ts.net/health
```

### Diagnostic decision tree

| Observation | Likely cause | Next action |
|-------------|--------------|-------------|
| No new lines in `pm2 logs` during app use | Network/DNS between phone and VM | Check Tailscale, MagicDNS, `API_BASE_URL` |
| Nginx `access.log` shows `/api/*` with 4xx/5xx | Backend application error | `pm2 logs tree-backend --err` |
| Login returns "account not found" | DB missing user or input mismatch | See [Login Troubleshooting](#login-troubleshooting) |

### Known non-fatal log noise

`Key (typname, typnamespace)=(schema_migrations, ...) already exists` (PostgreSQL `23505`): idempotent migration retry on restart. Safe to ignore if PM2 status is `online` and out-log shows successful PostgreSQL connection.

---

## Login Troubleshooting

### List users

```bash
cd /opt/tree-app/backend
node scripts/list_users.js
psql "<DATABASE_URL>" -c "SELECT username, role, is_active FROM users;"
```

Create admin (production):

```bash
node scripts/create_lab_admin.js \
  --username labadmin \
  --password '<STRONG_PASSWORD>' \
  --display 'Lab Administrator'
```

Never use `seed_dev_users.js` on production databases.

### Symptom: "Account not found" but user exists in DB

Login query: `WHERE username = $1` (**case-sensitive**).

| Cause | Fix |
|-------|-----|
| User entered **display name** instead of **username** | Login field must be `labadmin`, not display label |
| Mobile keyboard capitalized first letter | Ensure all lowercase, no leading/trailing spaces |
| Script run from wrong directory | `cd /opt/tree-app/backend` before `node scripts/*.js` |

### Audit evidence

```bash
psql "<DATABASE_URL>" -c \
  "SELECT created_at, username, ip_address, details FROM audit_logs \
   WHERE action='LOGIN_FAILED' ORDER BY created_at DESC LIMIT 5;"
```

### Isolate backend vs client input

```bash
curl -s -X POST https://<YOUR_DOMAIN>/api/login \
  -H "Content-Type: application/json" \
  -d '{"account":"labadmin","password":"<PASSWORD>"}'
```

| Response | Interpretation |
|----------|----------------|
| `success:true` + token | Backend OK; fix phone input |
| "Account not found" | Verify `DATABASE_URL` in `.env` |

### Password reset

`create_lab_admin.js` inserts only; does not update existing passwords.

```bash
psql "<DATABASE_URL>" -c "DELETE FROM users WHERE username='labadmin';"
node scripts/create_lab_admin.js \
  --username labadmin \
  --password '<NEW_PASSWORD>' \
  --display 'Lab Administrator'
```

---

## Account / IP Management

Use `<DATABASE_URL>` from `backend/.env` (`postgres://<user>:<pass>@localhost:5432/<db>`).

### A. Deactivate or delete account

```bash
# Preferred: soft disable
psql "<DATABASE_URL>" -c \
  "UPDATE users SET is_active=false WHERE username='<USERNAME>';"

# Hard delete (may fail on FK constraints)
psql "<DATABASE_URL>" -c \
  "DELETE FROM users WHERE username='<USERNAME>';"
```

### B. Unlock account (login lockout)

After 5 failed passwords → 30-minute lock (`middleware/loginAttemptMonitor.js`).

```bash
psql "<DATABASE_URL>" -c \
  "UPDATE users SET is_active=true, login_attempts=0, last_attempt_time=NULL \
   WHERE username='<USERNAME>';"
```

Auto-unlock occurs after 30 minutes without manual intervention.

### C. Rate limits and IP blacklist

**In-memory rate limiter** (`middleware/rateLimiter.js`; cleared on process restart):

| Limiter | Limit |
|---------|-------|
| `apiLimiter` | 500 req / 15 min |
| `loginLimiter` | 50 req / hour |
| `aiLimiter` | 30 req / hour |
| `burstLimiter` | 60 req / 10 sec |

| Action | Command / config |
|--------|------------------|
| Clear in-memory counters | `pm2 reload tree-backend` |
| Raise burst ceiling | `BURST_LIMIT_MAX=120` in `.env`, then reload |
| Disable limits (test/CI only) | `DISABLE_RATE_LIMIT=true` — **never in production** |

**Persistent IP blacklist** (`ip_blacklist` table; triggered by burst abuse or ≥30 login failures/hour):

```bash
psql "<DATABASE_URL>" -c \
  "SELECT ip, locked_until, reason, offense_count FROM ip_blacklist ORDER BY updated_at DESC;"

psql "<DATABASE_URL>" -c "DELETE FROM ip_blacklist WHERE ip='<IP>';"

psql "<DATABASE_URL>" -c \
  "UPDATE ip_blacklist SET locked_until=NOW() WHERE ip='<IP>';"

psql "<DATABASE_URL>" -c "DELETE FROM ip_login_attempts WHERE ip='<IP>';"
```

Admin API alternative: `GET/POST /api/admin/ip-blacklist` (requires admin JWT). Direct `psql` is fastest on-host.

---

## Nginx / TLS Troubleshooting

### Issue 1 — `setup_tailscale_tls.sh` silent exit; `nginx -t` cannot find `ts.crt`

| Field | Detail |
|-------|--------|
| **Symptom** | Script produces no output; nginx fails on missing cert |
| **Cause** | Auto-detection pipeline (`grep \| head`) fails under `set -e -o pipefail` |
| **Fix** | Pass hostname explicitly: `sudo bash scripts/setup_tailscale_tls.sh <hostname>.<TAILNET>.ts.net` |

### Issue 2 — `conflicting server name` / `could not build server_names_hash`

| Field | Detail |
|-------|--------|
| **Symptom** | `nginx -t` reports duplicate `server_name` |
| **Cause** | Backup files in `/etc/nginx/sites-enabled/` (nginx includes all files in that directory) |
| **Immediate fix** | `sudo rm -f /etc/nginx/sites-enabled/tree-app.bak.*` |
| **Verify** | `ls -l /etc/nginx/sites-enabled/` — only `tree-app` symlink should remain |
| **Permanent fix** | Script stores backups in `/opt/tree-app/nginx-conf-backups/` |

```bash
sudo rm -f /etc/nginx/sites-enabled/tree-app.bak.*
ls -l /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

If a legitimately long domain exceeds hash bucket size:

```bash
sudo sed -i 's/^http {/http {\n    server_names_hash_bucket_size 128;/' /etc/nginx/nginx.conf
sudo nginx -t && sudo systemctl reload nginx
```

### Issue 3 — `/api/health` returns `401 Unauthorized`

| Field | Detail |
|-------|--------|
| **Symptom** | `401 {"success":false,"message":"..."}` on health probe |
| **Cause** | JWT middleware on all `/api/*` routes |
| **Fix** | Probe `GET /health` instead |
| **Interpretation** | Any HTTP response without TLS error confirms nginx → backend path |

```bash
curl https://<YOUR_DOMAIN>/health    # expect: OK
```

---

## Backup

### Automated daily backup

Cron entry (see Production Runbook §3.12):

```bash
0 3 * * * /opt/tree-app/backend/scripts/backup_db.sh >> /opt/tree-app/logs/backup.log 2>&1
```

### Scope

| Asset | Location | Backup method |
|-------|----------|---------------|
| PostgreSQL | localhost | `backup_db.sh` (`pg_dump`) |
| Tree photos | Cloudinary | Provider-side; not on VM disk |
| Nginx config | `/etc/nginx/sites-available/tree-app` | Manual or config-mgmt; backups in `/opt/tree-app/nginx-conf-backups/` |
| TLS certs | `/opt/tree-app/ssl/` | Regenerable via certbot or `setup_tailscale_tls.sh` |
| Application code | GitHub | Source of truth is remote repo |

### Restore procedure (outline)

1. Restore PostgreSQL dump: `psql` or `pg_restore` into `treedb`.
2. Verify `schema_migrations` table version matches expected release.
3. Run `node scripts/run_pending_migrations.js` if deploying newer code atop older dump.
4. `pm2 reload ecosystem.config.js`.
5. Validate `GET /health`.

Document org-specific RPO/RTO in local ops notes.

---

## Dev test data, database reset, and code sync

Lab VM runs **Ubuntu**. All commands below are **bash on the server** unless labeled **Windows (dev PC)**.

### Policy: three kinds of data

| Kind | Example | Load on production VM? |
|------|---------|-------------------------|
| **Schema + reference** | tree species, status options, synonyms | Yes (via migrations) |
| **Dev CSV (~7000 trees)** | `dev-fixtures/tree_survey_data.csv` | **Only for deliberate QA** — never for real go-live |
| **Real survey data** | Field BLE / manual entry | Normal operation |

**Why separate?** The CSV is port-authority **test inventory** for map/load/regression. Production should start empty and fill from field work. `migrate.js` has triple guards: production deploy uses `run_pending_migrations.js` only; `SKIP_CSV_IMPORT=1`; skip if `tree_survey` already has rows.

### Load dev CSV (~7000 test trees) for QA

**When**: Empty `tree_survey` table and you **intentionally** want demo map data on the lab VM.

**Option A — Full rebuild with CSV** (wipes everything):

```bash
cd /opt/tree-app/backend
CONFIRM=YES SKIP_CSV_IMPORT=0 ./scripts/reset_fresh_db.sh
node scripts/create_lab_admin.js --username labadmin --password '<STRONG>' --display 'Lab Admin'
# Optional demo boundaries (not in migrate):
node scripts/seed_dev_boundaries.js
pm2 reload tree-backend
```

**Option B — Fresh empty DB, then migrate with CSV** (only if `tree_survey` is empty):

```bash
cd /opt/tree-app/backend
# Do NOT set SKIP_CSV_IMPORT
node scripts/migrate.js
```

**Option C — Small field-test fixtures** (GPS near phone, maintenance/history scenarios):

```bash
cd /opt/tree-app/backend
node scripts/seed_field_test_dataset.js --lat=24.15 --lon=120.65 --project-code=TIPC-XX
node scripts/seed_field_test_dataset.js --lat=24.15 --lon=120.65 --project-code=TIPC-XX --apply
# Cleanup when done:
node scripts/seed_field_test_dataset.js --cleanup --apply
```

**Verify import**:

```bash
psql "$DATABASE_URL" -c "SELECT COUNT(*) FROM tree_survey;"
psql "$DATABASE_URL" -c "SELECT project_location, COUNT(*) FROM tree_survey GROUP BY 1 ORDER BY 2 DESC LIMIT 5;"
curl -sf http://127.0.0.1:3000/health
```

**Windows (dev PC)** — same CSV logic on local Postgres:

```powershell
cd tree-project-backend
# .env with local DATABASE_URL
node scripts/migrate.js          # imports CSV if tree_survey empty
# OR skip CSV:
$env:SKIP_CSV_IMPORT="1"; node scripts/migrate.js
```

### Reset database after QA (back to clean production-like state)

**Why**: Remove ~7000 test trees and any QA edits before handover or go-live demo.

```bash
cd /opt/tree-app/backend
CONFIRM=YES SKIP_CSV_IMPORT=1 ./scripts/reset_fresh_db.sh
node scripts/create_lab_admin.js --username labadmin --password '<STRONG>' --display 'Lab Admin'
pm2 reload tree-backend
curl -sf http://127.0.0.1:3000/health
psql "$DATABASE_URL" -c "SELECT COUNT(*) FROM tree_survey;"   # expect 0
```

| After reset | State |
|-------------|--------|
| `tree_survey`, `projects`, `users` | Empty |
| `tree_species`, `species_synonyms`, `tree_status_options` | Reference seeds restored |
| Admin | **Must recreate** with `create_lab_admin.js` — never `seed_dev_users.js` on prod VM |

**Never** run `seed_dev_users.js` on the lab production VM (creates weak `admin/12345`).

### Sync server when GitHub is ahead

**Yes — the backend on the VM should pull** when `icmnlab/tree-project-backend` has newer commits.

**Check before pull** (on Ubuntu VM):

```bash
cd /opt/tree-app/backend
git remote -v
git fetch origin
git log --oneline HEAD..origin/main    # commits you are missing
git status
```

**Recommended — use deploy script** (pull + npm + incremental migration + PM2 + health + rollback):

```bash
cd /opt/tree-app/backend
bash scripts/deploy.sh
```

**Manual equivalent**:

```bash
cd /opt/tree-app/backend
git pull origin main
npm install --production
node scripts/run_pending_migrations.js    # NOT migrate.js on existing prod DB
pm2 reload ecosystem.config.js
curl -sf http://127.0.0.1:3000/health
```

| Command | Use on live VM with data? |
|---------|---------------------------|
| `git pull` + `run_pending_migrations.js` | **Yes** — normal updates |
| `migrate.js` | **No** — full bootstrap; CSV risk if `SKIP_CSV_IMPORT` unset |
| `deploy.sh --full-migrate` | **No** except empty DB disaster recovery |

### Recipient / developer machine (GitHub ahead of local)

Same pattern on **Windows or Ubuntu dev PC**:

```bash
cd tree-project-backend   # or tree-project-frontend
git fetch origin
git log --oneline HEAD..origin/main
git pull origin main
```

First-time clone (after collaborator invite):

```bash
git clone https://github.com/icmnlab/tree-project-backend.git
git clone https://github.com/icmnlab/tree-project-frontend.git
```

First push from a new developer: see `DEVELOPMENT_WORKFLOW.md` and `HANDOFF.md` §6.3 (Git Credential Manager / PAT).

---

## Enable SSH on Ubuntu VM (one-time)

**Why**: Tailscale reaches the VM, but port 22 needs `openssh-server`. Previously only Proxmox Console was used.

**On VM** (Proxmox Console or existing SSH):

```bash
sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
sudo ufw allow OpenSSH
systemctl is-active ssh
ss -ltnp | grep ':22'
```

**From Windows dev PC** (PowerShell — connectivity test only):

```powershell
Test-NetConnection 100.116.125.118 -Port 22
ssh vm121@100.116.125.118
# or
ssh vm121@vm121-standard-pc-i440fx-piix-1996.tail146e6a.ts.net
```

**From Ubuntu/macOS**:

```bash
ssh vm121@100.116.125.118
```

Document actual output in local `project_code/docs/DEPLOYMENT_LOG.md` (not git).

---

## Webhook + Tailscale Funnel (Ubuntu VM)

**Why Funnel**: GitHub webhook servers are on the public internet. Tailscale alone does not expose the VM to GitHub; Funnel publishes nginx `:443` or use manual `git pull` + `deploy.sh`.

### Step 1 — Pull latest backend first

```bash
cd /opt/tree-app/backend
git fetch origin && git pull origin main
npm install --production
pm2 reload tree-backend
```

### Step 2 — Generate secrets in `.env`

```bash
cd /opt/tree-app/backend
WEBHOOK_SECRET=$(openssl rand -hex 32)
ADMIN_TOKEN=$(openssl rand -hex 32)
echo "DEPLOY_WEBHOOK_SECRET=$WEBHOOK_SECRET"
echo "ADMIN_API_TOKEN=$ADMIN_TOKEN"
nano .env    # paste values; save
pm2 reload tree-backend
```

Store values in password manager. **Do not commit `.env`.**

### Step 3 — Tailscale Funnel (requires tailnet admin)

```bash
sudo tailscale funnel --bg --https=443 http://127.0.0.1:443
sudo tailscale funnel status
```

### Step 4 — GitHub webhook

Repo `icmnlab/tree-project-backend` → **Settings → Webhooks → Add webhook**:

| Field | Value |
|-------|-------|
| Payload URL | `https://<hostname>.<TAILNET>.ts.net/webhook/deploy` |
| Content type | `application/json` |
| Secret | Same as `DEPLOY_WEBHOOK_SECRET` |
| Events | Just the push event |

### Step 5 — Verify (Ubuntu on VM)

```bash
curl -sf http://127.0.0.1:3000/health
tail -n 30 /opt/tree-app/logs/deploy.log
pm2 logs tree-backend --lines 30
```

**From Windows** (webhook status — use `curl.exe`):

```powershell
curl.exe -s -H "X-Admin-Token: <ADMIN_TOKEN>" https://<hostname>.<TAILNET>.ts.net/webhook/status
```

Unsigned POST should return `401 Invalid signature` (proves route works):

```powershell
curl.exe -s -X POST https://<hostname>.<TAILNET>.ts.net/webhook/deploy -H "Content-Type: application/json" -d "{}"
```

### Step 6 — DB backup cron (optional, same session)

```bash
crontab -e
# add:
0 3 * * * /opt/tree-app/backend/scripts/backup_db.sh >> /opt/tree-app/logs/backup.log 2>&1
```

**Alternative without Funnel**: Manual deploy only — `bash scripts/deploy.sh` after each `git pull`. Document choice in local ops log.

---

## Deferred Web Portal

**Status (2026-06)**: Deferred. In-app admin screens cover user management, invite codes, and project administration. A standalone browser admin portal is **out of scope** for current handover.

If required later, recommended approach: React-Admin or Refine consuming existing REST + JWT APIs—not a custom from-scratch portal.

### Would-be feature map (future reference)

| Feature | Description |
|---------|-------------|
| Users and invites | Create surveyors, reset passwords, deactivate accounts |
| Projects and areas | CRUD `projects` / `project_areas` |
| Project boundaries | Map view, GeoJSON import, suggested boundary triggers |
| Survey data | Query, CSV export, row correction |
| System settings | ML URL, backup, CORS, maintenance mode |

Suggested priority if revived: P0 users + invites → P1 projects/boundaries → P2 backup/export UI.

---

## Appendix — Glossary

| Term | Definition |
|------|------------|
| `<SERVER_IP>` | VM or host IPv4/IPv6 address on lab network |
| `<YOUR_DOMAIN>` | App-facing hostname (institutional FQDN or `*.ts.net`) |
| `<TAILNET>` | Tailscale tailnet identifier in `*.ts.net` hostnames |
| `<PVE_HOST>` | Proxmox hypervisor address |
| `<VM_USER>` | Linux account on deployment VM |
| `<DB_PASSWORD>` | PostgreSQL role password for `treeapp` |
| `<ORG>` | Lab GitHub organization or user owning the repo |
| **Fresh snapshot** | Orphan-branch single-commit push without prior git history |
| **`tree-backend`** | PM2 process name (`ecosystem.config.js`) |
| **`SKIP_CSV_IMPORT=1`** | Migrate flag: schema + reference data only; no dev tree CSV |
| **`/health`** | Public liveness endpoint; returns plain text `OK` |
| **Tailscale Funnel** | Exposes Tailscale service to public internet (for GitHub webhooks) |
| **CORS** | `CORS_ALLOWED_ORIGINS` must match APK `API_BASE_URL` origin |
| **Cloudinary** | External object storage for tree photos |

### Related documents

| Document | Purpose |
|----------|---------|
| `AUTHORS.md` | Canonical attribution (preserve on handover) |
| `LICENSE` | MIT license and copyright |
| `HANDOFF.md` | System overview, local dev, webhook mechanism |
| `HANDOFF_SECRETS_CHECKLIST.md` | Secret inventory and rotation |
| `DEVELOPMENT_WORKFLOW.md` | Branch, PR, CI, recipient pull |
| `LOCAL_DEVELOPER_SETUP.md` | First-time dev machine setup |
| `ml_service/README.md` | Optional ML service setup |
