# Dev Data, Reset, and Git Sync

Load test CSV (~7000 trees), wipe and rebuild the database, pull when GitHub is ahead, and recipient first-time setup.

**Last reviewed**: 2026-06-29  
**Related**: `DATABASE_DESIGN.md` · `DEVELOPMENT_WORKFLOW.md` · `LAB_DEPLOYMENT_GUIDE.md` · `backend/dev-fixtures/README.md`

---

## Golden rules

| Environment | Load `tree_survey_data.csv`? | Migration command |
|-------------|------------------------------|-------------------|
| **Lab VM (field/production-like)** | **No** — real survey data only | `run_pending_migrations.js` via `deploy.sh` |
| **Local dev / CI** | **Yes** — on empty DB for map/load tests | `migrate.js` (no `SKIP_CSV_IMPORT`) |
| **Lab VM demo only** | Only after explicit **full reset** + `SKIP_CSV_IMPORT=0` | `reset_fresh_db.sh` — **destroys all trees** |

**Why**: CSV is Port Authority **test** trees (`dev-fixtures/tree_survey_data.csv`, ~7000 rows). Production and lab handover must not silently import them. Triple guard in `migrate.js`: `SKIP_CSV_IMPORT`, `run_pending_migrations` never runs CSV, skip if `tree_survey` already has rows.

---

## 1. Load dev test CSV (local Windows or test Postgres)

**Use when**: you want map/statistics/carbon regression against ~7000 seeded trees on **your machine**, not on the lab VM serving the App.

### Prerequisites

- PostgreSQL running locally (or a disposable `tree_test` database)
- `backend/.env` with `DATABASE_URL=postgres://...@localhost:5432/treedb`
- **Do not** set `SKIP_CSV_IMPORT` (or set `SKIP_CSV_IMPORT=0`)

### Steps

```powershell
cd tree-project-backend
npm ci
# Fresh empty database (drop/create DB in psql if re-running):
#   DROP DATABASE treedb; CREATE DATABASE treedb OWNER treeapp;

node scripts/migrate.js
```

**What happens** (in order):

1. All 49 schema SQL files run  
2. `dev-fixtures/project_areas_seed.pg.sql` loads demo port areas  
3. `dev-fixtures/tree_survey_data.csv` COPY into `tree_survey` (~7000 rows)  
4. View `tree_survey_with_areas` created  

Optional dev accounts and boundaries:

```powershell
node scripts/seed_dev_users.js          # admin / 12345 — dev & CI only
node scripts/seed_dev_boundaries.js       # demo KML boundaries — optional
npm start
curl http://localhost:3000/health
```

Verify row count:

```bash
psql "$DATABASE_URL" -c "SELECT COUNT(*) FROM tree_survey;"
# Expect ~7000 if CSV loaded
```

**Flutter**: point App at local API:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
```

### CSV already loaded / re-import

If `tree_survey` has rows, `migrate.js` **skips CSV** automatically. To reload CSV on dev:

```bash
cd tree-project-backend
CONFIRM=YES SKIP_CSV_IMPORT=0 ./scripts/reset_fresh_db.sh   # Linux / Git Bash / VM
node scripts/seed_dev_users.js
```

On Windows without bash, drop schema manually then `node scripts/migrate.js` with empty DB.

---

## 2. Lab VM — do **not** import CSV on normal deploy

The lab server at `/opt/tree-app/backend` was built with:

```bash
SKIP_CSV_IMPORT=1 node scripts/migrate.js
```

Ongoing updates use **`deploy.sh`** → `run_pending_migrations.js` only (no CSV).

**If you only need latest code/docs on the VM** (GitHub ahead of server):

```bash
ssh vm121@100.116.125.118    # after openssh installed; Tailscale up
cd /opt/tree-app/backend
git fetch origin
git log HEAD..origin/main --oneline    # see commits you are missing
git pull origin main
bash scripts/deploy.sh                 # pull + npm + pending migrations + pm2 reload + health
```

**Why `deploy.sh` not raw `git pull` alone**: installs deps, runs **incremental** migrations, reloads PM2, health check, auto-rollback on failure.

Frontend on VM: usually **not** cloned for serving — APK is built on dev PC. If you keep a frontend clone for docs:

```bash
cd /path/to/tree-project-frontend
git pull origin main
```

---

## 3. Reset lab database to empty (after testing)

**Warning**: deletes **all** trees, users, pending, audit logs in `public` schema.

```bash
cd /opt/tree-app/backend
CONFIRM=YES SKIP_CSV_IMPORT=1 ./scripts/reset_fresh_db.sh
node scripts/create_lab_admin.js --username <admin> --password '<strong-pass>' --display 'Lab Admin'
pm2 reload tree-backend
curl -sf http://127.0.0.1:3000/health
```

**Why `SKIP_CSV_IMPORT=1` on lab**: after reset you want empty business data + reference seeds (species, status options), not 7000 test trees.

### Reset **and** load test CSV on VM (demo only — rare)

```bash
CONFIRM=YES SKIP_CSV_IMPORT=0 ./scripts/reset_fresh_db.sh
node scripts/create_lab_admin.js ...
pm2 reload tree-backend
```

Use only for internal demos; field handover should use empty `tree_survey`.

---

## 4. GitHub is newer than laptop or server — sync checklist

### On VM (backend)

| Step | Command | Why |
|------|---------|-----|
| 1 | `git fetch origin` | See remote without merging |
| 2 | `git status` / `git log HEAD..origin/main --oneline` | Confirm behind |
| 3 | `git pull origin main` | Get latest code + docs |
| 4 | `bash scripts/deploy.sh` | Apply migrations + restart safely |

If `deploy.sh` says "Already up to date" after pull, you were only missing unpushed local commits — check you pulled `origin main` not a stale remote.

### On recipient / your dev PC (each repo)

```bash
git checkout main
git pull origin main
```

Backend after pull (local dev):

```bash
npm ci
node scripts/run_pending_migrations.js   # if DB already exists
# OR full rebuild: CONFIRM=YES SKIP_CSV_IMPORT=1 ./scripts/reset_fresh_db.sh
```

Frontend after pull:

```bash
flutter pub get
flutter test
```

**Two repos** — pull **both** `tree-project-frontend` and `tree-project-backend`.

---

## 5. Recipient first-time setup (clone → develop → first push)

Documented in detail: `DEVELOPMENT_WORKFLOW.md`, `HANDOFF.md` §6.3, `LOCAL_DEVELOPER_SETUP.md`.

### One-time

```bash
git config --global user.name "Name"
git config --global user.email "email@example.com"
# Accept icmnlab collaborator invite, then:
git clone https://github.com/icmnlab/tree-project-backend.git
git clone https://github.com/icmnlab/tree-project-frontend.git
```

First `git push` opens browser (Git Credential Manager) or use PAT.

### Daily

```bash
git checkout main && git pull origin main
git checkout -b feat/my-feature
# edit, test locally
git add -A && git commit -m "feat: description"
git push -u origin feat/my-feature
# Open PR on GitHub → wait for CI → merge
```

**First push does not require special flags** — same as any branch push after collaborator access.

---

## 6. migrate.js vs run_pending_migrations.js

| Script | When | CSV? |
|--------|------|------|
| `migrate.js` | Empty DB: local dev, CI, **first** lab install | Only if `SKIP_CSV_IMPORT` unset and `tree_survey` empty |
| `run_pending_migrations.js` | Production, lab deploy, app startup in prod | **Never** |

Adding a new SQL file: append to `migrationFiles[]` in `migrate.js` — both scripts share the list.

---

## 7. Phase 4 ops (SSH, webhook)

Generic steps: `LAB_DEPLOYMENT_GUIDE.md`.  
Live commands, IPs, and command output: local `project_code/docs/DEPLOYMENT_LOG.md` (not in git).

Summary:

1. Install `openssh-server` on VM (one-time)  
2. `git pull` + `deploy.sh` on backend  
3. Set `DEPLOY_WEBHOOK_SECRET`, `ADMIN_API_TOKEN` in `.env`  
4. Tailscale Funnel (if GitHub must reach webhook from public internet)  
5. GitHub repo → Webhook → `POST .../webhook/deploy`  
6. Test push to `main` → check `/opt/tree-app/logs/deploy.log`

---

## Related scripts

| Script | Purpose |
|--------|---------|
| `scripts/reset_fresh_db.sh` | DROP schema + migrate + pending |
| `scripts/deploy.sh` | Production pull + pending migrate + PM2 |
| `scripts/seed_dev_users.js` | Dev admin/12345 |
| `scripts/seed_dev_boundaries.js` | Demo boundaries |
| `scripts/create_lab_admin.js` | Production/lab admin (required after reset) |
