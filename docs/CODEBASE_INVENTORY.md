# Codebase Inventory

Complete catalog of source files and product features for **Sustainable TreeAI**. Use this checklist when writing or reviewing documentation so nothing is omitted.

**Audit date**: 2026-06-29  
**Repos**: `tree-project-frontend` · `tree-project-backend`  
**Method**: file counts from local clone; API list extracted from `backend/routes/*.js` + `app.js` mounts

---

## 1. Executive summary

| Metric | Frontend | Backend |
|--------|----------|---------|
| Application source files | **129** `.dart` (`lib/`) | **168** `.js` (excl. `node_modules`) |
| Test files | **28** `.dart` | **39** `.js` |
| HTTP API endpoints | — | **145** (143 under `/api` + 2 under `/webhook`) |
| Route modules | — | **24** files |
| Service modules | **45** `.dart` | **16** `.js` |
| DB migration SQL | — | **49** files in `database/initial_data/` |
| Documentation (git) | **22+** `.md` in `docs/` | README, `tests/FRAMEWORK.md`, `ml_service/` |

**Product surface**: **13** home dashboard cards + **2** bottom-nav tabs + **admin** console + auth flows.

---

## 2. Western documentation stack (target state)

Industry practice for a system this size:

| Layer | Document | Status |
|-------|----------|--------|
| Hub | `docs/README.md` | Done |
| Architecture | `ARCHITECTURE.md` | Done (overview, middleware, DB-in-git) |
| **Inventory (this file)** | `CODEBASE_INVENTORY.md` | Done |
| **API reference** | `API_REFERENCE.md` | Done (endpoint catalog) |
| Module guides | One doc per domain (survey, boundaries, AI, …) | **Phase 2** — rewrite topic docs against code |
| OpenAPI spec | `openapi.yaml` (optional, generated or hand-maintained) | **Phase 3** — future |
| Runbooks | Deployment from verified VM ops | **Phase 4** — after school-side steps |
| ADRs | Only for major decisions | As needed |

**Rule**: when code changes routes, tables, or user-visible flows → update `ARCHITECTURE.md`, `API_REFERENCE.md`, and the relevant module guide in the same PR.

---

## 3. Frontend inventory (`lib/`)

### 3.1 By directory

| Directory | Files | Role |
|-----------|-------|------|
| `screens/` | 29 | Full-page UI (login, BLE, map, admin, AI, …) |
| `services/` | 45 | HTTP clients, BLE parsers, business helpers |
| `utils/` | 18 | BLE, map clustering, boundaries, sessions |
| `widgets/` | 11+ | Reusable UI (BLE panels, dialogs, search) |
| `models/` | 6 | DTOs, RBAC definitions |
| `config/` | 3 | `app_config.dart` (API URL injection) |
| Root (`lib/*.dart`) | 11 | `main.dart`, map/list/survey pages, `admin_page.dart`, themes |

### 3.2 Home dashboard features (13 cards)

Source: `lib/screens/home_page.dart` (`_allCards`, lines ~174–189).

| Card ID | Title | Category | Primary screen / flow |
|---------|-------|----------|------------------------|
| `field_survey` | VLGEO2 現場連線 | field | `ble_live_session_page.dart` |
| `maintenance` | 維護量測 | field | `maintenance_survey_page.dart` |
| `ble` | 藍牙匯入 | field | `ble_import_page.dart` |
| `pending` | 待測量任務 | field | `pending_measurement_task_page.dart` |
| `survey` | 樹木調查 | data | `tree_survey_page.dart`, V3 forms |
| `map` | 樹木地圖 | data | `map_page.dart` |
| `cities` | 區管理 | data | `cities_page.dart`, `project_areas_page.dart` |
| `stats` | 統計圖表 | analysis | `statistics_page.dart` |
| `report` | 碳匯報告 | analysis | `ai_sustainability_report_screen.dart` |
| `test_scan` | 掃描測試 Demo | more | `scanner_page.dart` |
| `species` | 樹種辨識 | more | `species_identification_page.dart` |
| `ai` | AI 助理 | more | `ai_chat_page.dart` |
| `v3` | 系統設定 | more | `v3_services_page.dart` |

Bottom nav: **Dashboard** · **Tree list** (`tree_list_page.dart`).

### 3.3 Admin & auth screens (not on dashboard)

| Screen | File | Backend area |
|--------|------|--------------|
| Login | `login_page.dart` | `POST /api/login` |
| Register | `register_page.dart` | `POST /api/register` |
| Forgot password | `forgot_password_page.dart` | password-reset routes |
| Admin hub | `admin_page.dart` | `/api/admin/*`, users, invites |
| User form | `user_form_screen.dart` | `/api/users` |
| Invites | `invite_management_page.dart` | `/api/invites` |
| Audit log | `audit_log_page.dart` | `/api/admin/audit-logs` |
| IP blacklist | `ip_blacklist_page.dart` | `/api/admin/ip-blacklist` |
| CSV import | `csv_import_page.dart` | `/api/admin/import-csv` |
| Role permissions | `role_permissions_page.dart` | UI mirror of `role_permissions.dart` |
| Research dataset | `admin_research_dataset_page.dart` | `/api/admin/research-dataset` |
| System settings | `system_settings_page.dart` | local prefs + API keys |

### 3.4 Frontend services → API mapping (primary)

| Service file | Calls (typical) |
|--------------|-----------------|
| `auth_service.dart` | `/api/login`, token storage |
| `api_service.dart` | Shared HTTP + JWT header |
| `user_service.dart` | `/api/users`, invites |
| `tree_service.dart` | `/api/tree_survey/*` |
| `pending_measurement_service.dart` | `/api/pending-measurements/*` |
| `project_service.dart` | `/api/projects/*` |
| `project_area_service.dart` | `/api/project_areas/*` |
| `v3/project_boundary_service.dart` | `/api/project-boundaries/*` |
| `species_identification_service.dart` | `/api/species/*` |
| `v3/tree_image_service.dart` | `/api/tree-images/*` |
| `ai_service.dart` | `/api/chat`, reports |
| `admin_service.dart` | `/api/admin/*` |
| `ble_*` (local) | No direct API — uploads via pending/batch |

BLE stack (on-device only): `ble_data_processor.dart`, `ble_packet_decoder.dart`, `ble_live_packet_decoder.dart`, `ble_uart_discovery.dart`.

---

## 4. Backend inventory

### 4.1 Layer counts

| Layer | Count | Location |
|-------|-------|----------|
| Routes | 24 | `routes/*.js` |
| Services | 16 | `services/*.js` |
| Controllers | 8 | `controllers/*.js` |
| Middleware | 7 | `middleware/*.js` |
| Utils | 11 | `utils/*.js` |
| Scripts | 20+ | `scripts/*.js`, `scripts/*.sh` |
| ML service | Python | `ml_service/` (optional) |

### 4.2 API modules (endpoint counts)

| Module | Endpoints | Route file | Doc phase |
|--------|-----------|------------|-----------|
| Tree survey | 19 | `treeSurvey.js` | P2 |
| Users & auth | 16 | `users.js` | P2 |
| Project boundaries | 13 | `project_boundaries.js` | P2 |
| AI chat & reports | 9 | `ai.js` | P2 |
| Admin | 9 | `admin.js` | P2 |
| Pending measurements | 9 | `pending_measurements.js` | P2 |
| Tree species | 7 | `treeSpecies.js` | P2 |
| ML proxy | 7 | `ml_service.js` | P2 |
| Projects | 6 | `projects.js` | P2 |
| Project areas | 6 | `project_areas.js` | P2 |
| ML training data | 5 | `ml_training_data.js` | P3 |
| Species ID | 5 | `speciesIdentification.js` | P2 |
| Tree images | 4 | `tree_images.js` | P2 |
| Tree management | 4 | `management.js` | P3 |
| Research dataset | 4 | `research_dataset.js` | P3 |
| IP blacklist | 4 | `ipBlacklist.js` | P2 |
| Agent | 3 | `agent.js` | P2 |
| Reports export | 3 | `reports.js` | P2 |
| Maintenance locks | 3 | `maintenance_locks.js` | P2 |
| Tree statuses | 2 | `tree_statuses.js` | P2 |
| Location | 2 | `location.js` | P3 |
| CSV import | 2 | `csvImport.js` | P2 |
| Webhook | 2 | `webhook.js` | P4 (runbook) |
| Statistics | 1 | `statistics.js` | P2 |
| **Total** | **145** | | |

Full path list: **`API_REFERENCE.md`**.

### 4.3 Database artifacts in git

| Type | Count | Notes |
|------|-------|-------|
| Migration / schema SQL | 49 | Ordered in `scripts/migrate.js` |
| Dev fixtures | 5+ | `dev-fixtures/` — not for production |
| Views | 1 | `tree_survey_with_areas.pg.sql` |

See `ARCHITECTURE.md` §3 for what is required vs optional.

---

## 5. RBAC (5 roles)

Defined in `middleware/roleAuth.js` and mirrored in `frontend/lib/models/role_permissions.dart`.

| Level | Role | Typical API access |
|-------|------|-------------------|
| 5 | 系統管理員 | All admin + maintenance scripts |
| 4 | 業務管理員 | Users, invites, CSV, areas |
| 3 | 專案管理員 | Boundaries, delete trees, import |
| 2 | 調查管理員 | Create/update trees, AI, pending transfer |
| 1 | 一般使用者 | Read scoped data, field entry |

Most `/api/*` routes require JWT; many add `requireRole(...)` or `projectAuthFilter`.

---

## 6. Documentation writing plan (phased)

### Phase 1 — Catalog (complete)

- [x] `ARCHITECTURE.md`
- [x] `CODEBASE_INVENTORY.md` (this file)
- [x] `API_REFERENCE.md`

### Phase 2 — Module guides (rewrite topic docs, verify against code)

Priority order by user-facing impact:

1. Auth & RBAC → merge into `ADMIN_AND_INVITE_DESIGN.md`
2. Survey & pending → `SURVEY_HISTORY.md`
3. Boundaries → `BOUNDARY_SYSTEM_DESIGN.md`
4. BLE → `VLGEO2_STD_APPLICATION_GUIDE.md`
5. Species & PlantNet → new section in API ref + topic doc
6. Carbon → `CARBON_CALCULATION.md`
7. AI / Agent → `AI_AGENT_GUIDE.md`

Each module doc template (Western style):

- **Overview** — what problem it solves  
- **User flow** — App screens  
- **API** — link to `API_REFERENCE.md` section  
- **Code map** — routes, services, key functions  
- **Data model** — tables and fields  
- **Configuration** — env vars  
- **Testing** — which test files cover it  

### Phase 3 — OpenAPI (optional)

Generate or maintain `backend/openapi.yaml` for Swagger UI / Postman import. Not required for handover but standard at larger companies.

### Phase 4 — Deployment runbook

Convert local `DEPLOYMENT_LOG.md` ops into public `LAB_DEPLOYMENT_GUIDE.md` after VM steps verified.

---

## 7. Verification checklist (for doc authors)

Before marking a module doc "reviewed":

- [ ] Every endpoint in the route file appears in `API_REFERENCE.md`
- [ ] Role requirements match `requireRole` / `projectAuth` in code
- [ ] Frontend screen → service → API path chain is documented
- [ ] DB tables match current migrations
- [ ] No references to removed features (Classic BT server, ngrok if using Tailscale, etc.)

---

## 8. Changelog

| Date | Change |
|------|--------|
| 2026-06-29 | Initial inventory: 129 Dart, 168 JS, 145 endpoints, 13 dashboard cards |
