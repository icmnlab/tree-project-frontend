# Architecture & Codebase Guide

Technical reference for developers maintaining **Sustainable TreeAI**. Describes how features run, which files implement them, and how data flows through the system.

**Audience**: engineers onboarding to the codebase (read this before deployment runbooks).

**Related docs**: `HANDOFF.md` (quick start) · `API_REFERENCE.md` · `backend/openapi/openapi.yaml` (machine-readable API) · `PROJECT_DATA_AND_DOMAIN.md` (domain terms) · `SURVEY_HISTORY.md` (measurement history) · `backend/tests/FRAMEWORK.md` (integration tests)

**Last updated**: 2026-06-29

---

## 1. System overview

```
┌─────────────────┐     HTTPS + JWT      ┌──────────────────────────────────┐
│  Flutter App    │ ───────────────────► │  backend (Node.js / Express)     │
│  tree-project-  │     /api/*           │  PM2 cluster · port 3000         │
│  frontend       │                      │  routes/ → services/ → PostgreSQL │
└────────┬────────┘                      └───────────────┬──────────────────┘
         │                                               │
         │  BLE (on-device)                              │  optional
         ▼                                               ▼
┌─────────────────┐                      ┌──────────────────────────────────┐
│  VLGEO2 device  │                      │  ml_service (FastAPI, optional)  │
│  (tree meter)   │                      │  depth / trunk detection proxy   │
└─────────────────┘                      └──────────────────────────────────┘
         │                                               │
         └──────────────── Cloudinary (photos) ──────────┘
                              PlantNet / LLM APIs (via backend .env)
```

| Layer | Repo | Runtime |
|-------|------|---------|
| Mobile UI | `tree-project-frontend` | Flutter (Android primary) |
| API | `tree-project-backend` | Node 20, Express, PM2 |
| Database | (hosted on deploy server) | PostgreSQL 15+ |
| ML | `backend/ml_service/` | Python FastAPI (optional) |

**Design principle**: business rules live in the **backend**; the app is a thin client (HTTP + local BLE parsing). Secrets and hostnames are injected via `.env` / `--dart-define`, never hard-coded.

---

## 2. Request lifecycle

Every authenticated API call follows this path (`backend/app.js`):

```
Client
  → Nginx (TLS termination, optional)
  → Express
      GET /health          → public, no auth
      POST /webhook/*      → HMAC secret, no JWT
      /api/*
        → ipBlacklistGuard
        → burstLimiter + apiLimiter
        → jwtAuth          (Bearer token from POST /api/login)
        → route handler    (often + requireRole / projectAuth)
        → service layer
        → PostgreSQL (pg pool)
```

| Middleware | File | Purpose |
|------------|------|---------|
| JWT | `middleware/jwtAuth.js` | Validates `Authorization: Bearer <token>` signed with `JWT_SECRET` |
| Roles | `middleware/requireRole.js` | RBAC: 系統管理員 / 業務管理員 / 專案管理員 / 調查管理員 / 調查員 |
| Project scope | `middleware/projectAuth.js` | Restricts data to projects assigned in `user_projects` |
| Rate limit | `middleware/rateLimiter.js` | Burst + per-IP limits; disabled in CI via `DISABLE_RATE_LIMIT` |
| IP blacklist | `middleware/ipBlacklistGuard.js` | Blocks brute-force IPs (`ip_blacklist` table) |

**Login** (`POST /api/login`, `routes/users.js`): body `{ account, password }` → JWT. The field is `account` but matches **`users.username`** (case-sensitive), not display name.

**CORS**: production requires `CORS_ALLOWED_ORIGINS` in `.env` (comma-separated). Mobile apps send no `Origin` header and are allowed.

---

## 3. Database files in Git — why so many?

**Short answer**: yes, this is normal for a mature PostgreSQL app. Not everything is “data”; most files are **schema migrations** versioned as SQL.

### 3.1 Three categories

| Category | Location | In production? | Purpose |
|----------|----------|----------------|---------|
| **Schema migrations** | `backend/database/initial_data/*.pg.sql` (35 numbered steps) | **Yes** — required | CREATE/ALTER tables, triggers, views, reference master data |
| **Dev fixtures** | `backend/dev-fixtures/` | **No** — dev/CI only | ~7000 test trees CSV, demo port boundaries, column maps |
| **Runtime data** | PostgreSQL on server | **No** — not in git | Surveys, users, photos metadata, audit logs |

### 3.2 Why 35+ SQL files instead of one?

Industry-standard reasons (same as Flyway/Liquibase/Alembic, but SQL files + a runner):

1. **Incremental evolution** — each file is one deployable step (`07_backfill…`, `15_tree_survey_measurements…`). Production runs only **pending** files via `schema_migrations` table (`scripts/run_pending_migrations.js`).
2. **Safe rollback story** — you know exactly which change introduced a column or trigger.
3. **Idempotent repair scripts** — e.g. `23_fix_wrong_synonym…` cleans bad rows on existing DBs without manual DBA work.
4. **Reviewability** — PRs show one logical DB change per file.

`scripts/migrate.js` lists the **full ordered sequence** (lines 28–78). Production startup (`app.js`) calls `run_pending_migrations.js` only — **not** the CSV import block.

### 3.3 What reference data *is* shipped in SQL?

These are **master data** (like a country list), not test surveys:

| File | Content | Why in git |
|------|---------|------------|
| `tree_species.pg.sql` | Taiwan tree species catalog (~100 rows) | Dropdown + PlantNet local matching |
| `species_synonyms.pg.sql` | Manual name variants (正榕→九丁榕, etc.) | Field naming consistency |
| `33_tree_status_options.pg.sql` | Built-in tree condition options | Shared UI picklists |
| `users.pg.sql` | **Table only** — no seed accounts | Accounts created via `create_lab_admin.js` |

**Not shipped to production DB**:

| File | Content |
|------|---------|
| `dev-fixtures/tree_survey_data.csv` | ~7000 port-authority **test trees** |
| `dev-fixtures/project_areas_seed.pg.sql` | Demo port area names |
| `dev-fixtures/06_project_boundaries_seed.pg.sql` | Demo boundary polygons |

Controlled by `SKIP_CSV_IMPORT=1` or `NODE_ENV=production` (see `migrate.js` lines 99–122).

### 3.4 Is this “too much” for GitHub?

For a field-survey + carbon app with 2+ years of schema changes, **~50 SQL files is reasonable**. Compare:

- Rails: `db/migrate/` often has 50–200 Ruby migration files
- Django: many apps commit fixtures + migrations
- This repo: plain SQL, no ORM magic — easier to audit

**What would be wrong**: committing production `.env`, user passwords, or multi-GB survey exports. Those stay on the server / Cloudinary.

### 3.5 Core database tables (entity map)

| Table | Role | Main consumers |
|-------|------|----------------|
| `users` | Accounts, roles, login lockout | `routes/users.js` |
| `user_projects` | Which projects a user may access | `middleware/projectAuth.js` |
| `projects` | Canonical project codes and names | tree_survey, boundaries, stats |
| `project_areas` | City / port area hierarchy | map filters, area admin |
| `project_boundaries` | GeoJSON polygons per project | `routes/project_boundaries.js` |
| `tree_species` | Species catalog (master data) | dropdowns, PlantNet matching |
| `species_synonyms` | Alternate names → canonical species | identification, search |
| `tree_survey` | **Current snapshot** per tree (map, list, carbon) | most read APIs |
| `tree_survey_measurements` | **Historical** measurements per tree | maintenance, trends |
| `pending_tree_measurements` | Staging before transfer | BLE batch, field draft |
| `tree_images` | Photo URLs (Cloudinary) + optional measurement link | upload, detail view |
| `tree_status_options` | Condition picklist (built-in + custom) | survey forms |
| `audit_logs` | Login and security events | admin, troubleshooting |
| `ip_blacklist` / `ip_login_attempts` | Brute-force protection | login, rate limit |
| `invites` | Registration invite codes | register flow |
| `chat_logs` | AI conversation history | `routes/ai.js` |

**Important**: `tree_survey.species_id` has **no FK** to `tree_species` — field teams can enter unknown species; PlantNet may auto-insert rows (`speciesIdentificationService.js`).

---

## 4. Backend module map

Base URL: `/api` (except `/health`, `/webhook/*`).

### 4.1 Authentication & users

| Feature | Route file | Key endpoints | DB tables |
|---------|------------|---------------|-----------|
| Login / JWT | `routes/users.js` | `POST /login`, `POST /register` | `users`, `audit_logs` |
| User CRUD | `routes/users.js` | `GET/POST/PUT/DELETE /users` | `users` |
| Invites | `routes/users.js` | `GET/POST /invites` | `invites` |
| Project assignment | `routes/users.js` | `GET/PUT /users/:id/projects` | `user_projects`, `projects` |

Frontend: `lib/screens/login_page.dart`, `lib/services/auth_service.dart`, `lib/admin_page.dart`.

### 4.2 Field survey — pending → transfer workflow

**Why two stages**: BLE batches and manual entry land in **pending** first; **transfer** commits to official `tree_survey` in one transaction (retry-safe, idempotent).

| Step | Backend | Frontend |
|------|---------|----------|
| Batch upload pending | `POST /api/pending-measurements/batch` · `routes/pending_measurements.js:326` | `lib/services/pending_measurement_service.dart`, BLE pages |
| List / edit pending | `GET/PATCH /api/pending-measurements/...` | `pending_measurement_task_page.dart` |
| Transfer to survey | `POST /api/pending-measurements/transfer` · `:905` | transfer UI in survey flow |
| Create tree directly | `POST /api/tree_survey/create_v2` · `routes/treeSurvey.js` | `tree_input_page_v2.dart`, V3 forms |

DB: `pending_tree_measurements` → `tree_survey` + `tree_survey_measurements` (history).

See `SURVEY_HISTORY.md` for snapshot vs history table design.

### 4.3 Maps & boundaries

| Feature | Route file | Endpoints | Notes |
|---------|------------|-----------|-------|
| Map markers | `routes/treeSurvey.js` | `GET /tree_survey/map`, `/map/meta` | Clustered markers, project filter |
| Draw boundary | `routes/project_boundaries.js` | CRUD under `/project-boundaries` | GeoJSON/KML import |
| Project areas | `routes/project_areas.js` | `/project_areas` | City/port area hierarchy |

Frontend: `lib/map_page.dart`, `lib/screens/v3/project_boundary_draw_page.dart`, `lib/services/v3/project_boundary_service.dart`.

Design: `BOUNDARY_SYSTEM_DESIGN.md`.

### 4.4 BLE (VLGEO2)

BLE runs **entirely on the phone** (FlutterBlue Plus). Parsed measurements are sent to the backend as normal pending batch JSON — no Classic Bluetooth on server.

| Layer | File |
|-------|------|
| UART discovery | `lib/utils/ble_uart_discovery.dart` |
| Live session | `lib/screens/ble_live_session_page.dart` |
| Import file | `lib/screens/ble_import_page.dart` |
| Signal parsing | `lib/services/ble_data_processor.dart` |

Guide: `VLGEO2_STD_APPLICATION_GUIDE.md`.

### 4.5 Species identification (PlantNet)

| Layer | File |
|-------|------|
| API route | `routes/speciesIdentification.js` → `POST /api/species/identify` |
| Service | `services/speciesIdentificationService.js` (PlantNet API, local synonym match, auto-add species) |
| Frontend | `lib/screens/species_identification_page.dart` |

Requires `PLANTNET_API_KEY` in `.env`. Uses `tree_species` + `species_synonyms` for normalization.

### 4.6 Photos (Cloudinary)

| Layer | File |
|-------|------|
| Upload route | `routes/tree_images.js` |
| Storage | Cloudinary (URL stored in `tree_images`) |

Requires `CLOUDINARY_*` in `.env`.

### 4.7 Carbon & statistics

| Feature | Route | Service / logic |
|---------|-------|-----------------|
| Dashboard stats | `routes/statistics.js` | Aggregations over `tree_survey` |
| Carbon report | `routes/reports.js`, `routes/ai.js` | `services/carbonCalculationService.js` — see `CARBON_CALCULATION.md` |
| AI sustainability report | `POST /api/reports/ai-sustainability` | LLM + structured prompts |

Frontend: `lib/statistics_page.dart`, `lib/screens/ai_sustainability_report_screen.dart`.

### 4.8 AI chat & agent (optional)

| Feature | Route | Service |
|---------|-------|---------|
| Chat (SSE stream) | `routes/ai.js` | `services/aiChatService.js` |
| Agent tools | `routes/agent.js` | `services/agentService.js`, SQL via `services/sqlQueryService.executeSecureQuery` |

Requires at least one LLM key in `.env`. Guide: `AI_AGENT_GUIDE.md`.

### 4.9 ML trunk / DBH (optional)

| Layer | File |
|-------|------|
| Proxy route | `routes/ml_service.js` |
| Python service | `ml_service/app.py` |
| Config | `ML_SERVICE_URL`, `ML_API_KEY` |

App uploads image → backend → ML service → DBH estimate returned.

### 4.10 Admin & security

| Feature | Route | File |
|---------|-------|------|
| Admin dashboard | `routes/admin.js` | User stats, system ops |
| IP blacklist | `routes/ipBlacklist.js` | `/api/admin/ip-blacklist` |
| CSV import (admin) | `routes/csvImport.js` | Bulk import (not dev CSV) |
| Maintenance lock | `routes/maintenance_locks.js` | Prevents concurrent re-measure |
| Deploy webhook | `routes/webhook.js` | `POST /webhook/deploy` (HMAC, not JWT) |

### 4.11 API quick reference (authenticated unless noted)

All paths prefixed with `/api`. JWT via `Authorization: Bearer <token>` after `POST /api/login`.

| Method | Path | Role (typical) | Route file |
|--------|------|----------------|------------|
| POST | `/login` | public | `users.js` |
| POST | `/register` | public + invite | `users.js` |
| GET | `/tree_survey/map` | project-scoped | `treeSurvey.js` |
| POST | `/tree_survey/create_v2` | 調查管理員 | `treeSurvey.js` |
| PUT | `/tree_survey/update_v2/:id` | 調查管理員 | `treeSurvey.js` |
| POST | `/pending-measurements/batch` | project-scoped | `pending_measurements.js` |
| POST | `/pending-measurements/transfer` | project-scoped | `pending_measurements.js` |
| POST | `/species/identify` | authenticated | `speciesIdentification.js` |
| POST | `/tree-images/upload` | authenticated | `tree_images.js` |
| GET | `/tree_statistics/` | project-scoped | `statistics.js` |
| POST | `/chat` | 調查管理員 | `ai.js` (SSE) |
| GET | `/reports/ai-sustainability` | 調查管理員 | `ai.js` |
| POST | `/agent/chat` | 調查管理員 | `agent.js` |
| POST | `/ml-service/detect` | authenticated | `ml_service.js` |
| GET | `/admin/...` | 業務管理員+ | `admin.js` |

Public (no JWT): `GET /health`, `POST /webhook/deploy` (HMAC), `GET /webhook/status` (`X-Admin-Token`).

Full route mounting: `backend/app.js` lines 98–153.

---

## 5. Frontend structure

```
lib/
├── main.dart                 # App entry, theme, routes
├── config/app_config.dart    # API_BASE_URL from --dart-define
├── screens/                  # Full-page UI (login, BLE, AI, admin, …)
├── services/                 # HTTP clients (api_service.dart wraps Dio/http)
├── models/                   # DTOs (pending_tree_measurement, role_permissions, …)
├── widgets/                  # Reusable UI (maps, BLE panels, dialogs)
└── utils/                    # BLE, boundaries, clustering helpers
```

**API client**: `lib/services/api_service.dart` attaches JWT from `flutter_secure_storage` after login.

**Roles**: `lib/models/role_permissions.dart` mirrors backend RBAC for UI visibility (cards on `home_page.dart`).

---

## 6. Key services (backend business logic)

| Service | Responsibility |
|---------|----------------|
| `services/carbonCalculationService.js` | DBH → carbon storage / sequestration |
| `services/speciesIdentificationService.js` | PlantNet + local catalog merge |
| `services/speciesSynonymService.js` | Synonym maintenance cron |
| `services/sqlQueryService.js` | Agent SQL guardrails |
| `services/projectBoundaryService.js` | Boundary validation, import |
| `utils/cleanup.js` | Scheduled orphan / chat log cleanup (`app.js` cron) |

Prefer adding logic in **services/**, keeping **routes/** thin (validate → call service → JSON).

---

## 7. Testing

| Suite | Location | Count | Runs when |
|-------|----------|-------|-----------|
| Frontend unit/widget | `frontend/test/` | 435 | `flutter test`, CI |
| Backend integration | `backend/tests/` (invariants, contracts, journeys) | 89 | `node tests/runner.js`, CI |
| ML | `ml_service/tests/` | optional | separate |

Backend tests use real HTTP against a throwaway PostgreSQL (see `tests/FRAMEWORK.md`). They encode domain rules (optimistic lock, transfer idempotency, RBAC isolation).

---

## 8. Deployment vs development (code perspective)

| Action | Dev | Production |
|--------|-----|------------|
| Create empty DB | `node scripts/migrate.js` (+ optional CSV) | `SKIP_CSV_IMPORT=1 node scripts/migrate.js` once |
| Apply new schema | re-run migrate or pending runner | `run_pending_migrations.js` on startup + deploy |
| Seed users | `seed_dev_users.js` (admin/12345) | `create_lab_admin.js` only |
| Start server | `npm start` | PM2 `ecosystem.config.js` |
| Auto deploy | manual | `scripts/deploy.sh` via GitHub webhook |

Operational steps: `LAB_DEPLOYMENT_GUIDE.md` (public). School-only VM notes stay in local `project_code/docs/` (not pushed).

---

## 9. Where to start reading code

| Goal | Start here |
|------|------------|
| Understand auth | `routes/users.js`, `middleware/jwtAuth.js` |
| Survey flow | `routes/pending_measurements.js` (transfer), `routes/treeSurvey.js` (create_v2) |
| DB schema order | `scripts/migrate.js` migration list |
| App home & features | `lib/screens/home_page.dart` |
| API wiring | `backend/app.js` route mounts |
| Carbon math | `services/carbonCalculationService.js` + `CARBON_CALCULATION.md` |

---

## 10. Documentation map

| Tier | Documents | Status |
|------|-----------|--------|
| **Architecture (this file)** | System design, modules, DB-in-git FAQ | Canonical — update with code changes |
| **Hub** | `docs/README.md` | Index of all docs |
| **Onboarding** | `HANDOFF.md`, `HANDOFF_SECRETS_CHECKLIST.md` | Maintained |
| **Operations** | `LAB_DEPLOYMENT_GUIDE.md`, `BUILD_GUIDE.md`, checklists | Maintained; full runbook from live VM ops pending |
| **Domain deep-dives** | `SURVEY_HISTORY.md`, `CARBON_CALCULATION.md`, `BOUNDARY_SYSTEM_DESIGN.md`, etc. | Use alongside §4; rewrite individually after code audit |
| **Local-only ops log** | `project_code/docs/DEPLOYMENT_LOG.md` | Not in git; will become public deployment runbook when VM steps are complete |

Pre-rewrite snapshots of all `docs/*.md` files are archived locally at `project_code/docs/archive/frontend-docs-snapshot-20260629/` for diff reference.

---

## 11. Changelog

| Date | Change |
|------|--------|
| 2026-06-29 | Added core DB table map, API quick reference, documentation tier map |
| 2026-06-29 | Initial architecture guide; database-in-git FAQ; feature→file map |
