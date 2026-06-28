# API Reference

REST API for **Sustainable TreeAI** backend (`tree-project-backend`).

**Base URL**: `https://<host>/api` (set in App via `--dart-define=API_BASE_URL=.../api`)  
**Auth**: `Authorization: Bearer <JWT>` on all `/api/*` routes unless noted  
**Public**: `GET /health`, `POST /webhook/deploy`, `GET /webhook/status`  
**Source of truth**: `backend/routes/*.js`, mounts in `backend/app.js`

**Related**: `ARCHITECTURE.md` (middleware chain) · `CODEBASE_INVENTORY.md` (endpoint counts)

**Last updated**: 2026-06-29 · **145 endpoints**

---

## Conventions

### Request / response

- JSON body for POST/PUT/PATCH unless file upload (`multipart/form-data`).
- Success: `{ "success": true, ... }` (pattern varies by route).
- Errors: HTTP status + `{ "success": false, "message": "..." }`.
- Login field is **`account`** (maps to `users.username`, case-sensitive).

### Middleware order (`/api/*`)

`ipBlacklistGuard` → `burstLimiter` → `apiLimiter` → `jwtAuth` → route handler (+ optional `requireRole` / `projectAuth`).

### Role shorthand in tables

| Abbrev | Role |
|--------|------|
| public | No JWT (login/register only) |
| JWT | Any authenticated user |
| 調查+ | 調查管理員 or higher |
| 專案+ | 專案管理員 or higher |
| 業務+ | 業務管理員 or higher |
| 系統 | 系統管理員 |
| project | JWT + project scope filter |

---

## Public endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/health` | none | Liveness probe; returns `OK` |
| POST | `/webhook/deploy` | HMAC `X-Hub-Signature-256` | GitHub push → runs `deploy.sh` |
| GET | `/webhook/status` | header `X-Admin-Token` | Tail of deploy log |

---

## Authentication & users

Mount: `routes/users.js` at `/api`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/login` | public | Issue JWT; body `{ account, password }` |
| POST | `/api/register` | public | Register with invite code |
| POST | `/api/password-reset-request` | public | Request password reset |
| POST | `/api/password-reset` | public | Complete reset |
| GET | `/api/users` | 業務+ | List users |
| POST | `/api/users` | 業務+ | Create user |
| PUT | `/api/users/:id` | 業務+ | Update user |
| PUT | `/api/users/:id/status` | 業務+ | Enable/disable |
| DELETE | `/api/users/:id` | 業務+ | Delete user |
| GET | `/api/users/:userId/projects` | 業務+ | User's project assignments |
| PUT | `/api/users/:userId/projects` | 業務+ | Set project assignments |
| GET | `/api/invites` | 業務+ | List invite codes |
| POST | `/api/invites` | 業務+ | Create invite |
| PATCH | `/api/invites/:inviteId/deactivate` | 業務+ | Deactivate invite |
| DELETE | `/api/invites/:inviteId` | 業務+ | Delete invite |
| GET | `/api/pending-password-resets` | 業務+ | Pending reset queue |

---

## Projects & areas

| Method | Path | Auth | Route file |
|--------|------|------|------------|
| GET | `/api/projects` | JWT | `projects.js` |
| GET | `/api/projects/by_area/:area` | JWT | `projects.js` |
| GET | `/api/projects/by_name/:name` | JWT | `projects.js` |
| GET | `/api/projects/by_code/:code` | JWT | `projects.js` |
| POST | `/api/projects/add` | 業務+ | `projects.js` |
| DELETE | `/api/projects/:code` | 業務+ | `projects.js` |
| GET | `/api/project_areas` | JWT | `project_areas.js` |
| POST | `/api/project_areas` | 業務+ | `project_areas.js` |
| PUT | `/api/project_areas/:id` | 業務+ | `project_areas.js` |
| DELETE | `/api/project_areas/:id` | 業務+ | `project_areas.js` |
| GET | `/api/project_areas/county_by_coords` | JWT | `project_areas.js` |
| POST | `/api/project_areas/cleanup` | 系統 | `project_areas.js` |

---

## Tree survey (official records)

Mount: `/api/tree_survey` · `routes/treeSurvey.js`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/tree_survey` | project | List trees (filtered) |
| GET | `/api/tree_survey/map/meta` | project | Map metadata |
| GET | `/api/tree_survey/map` | project | Map markers |
| GET | `/api/tree_survey/by_id/:id` | project | Single tree |
| GET | `/api/tree_survey/by_id/:id/measurements` | project | Measurement history |
| GET | `/api/tree_survey/by_project/:projectNameOrCode` | project | Trees by project |
| GET | `/api/tree_survey/by_area/:areaName` | project | Trees by area |
| POST | `/api/tree_survey/create_v2` | 調查+ | Create tree (current API) |
| PUT | `/api/tree_survey/update_v2/:id` | 調查+ | Update with optimistic lock |
| POST | `/api/tree_survey/batch_import` | 調查+ | Batch import |
| POST | `/api/tree_survey/import` | 專案+ | File import |
| GET | `/api/tree_survey/template` | JWT | Download import template |
| DELETE | `/api/tree_survey/:id` | 專案+ | Delete tree |
| DELETE | `/api/tree_survey/placeholder/:id` | 專案+ | Delete placeholder |
| POST | `/api/tree_survey/:id/retire` | 調查+ | Mark dead/removed |
| POST | `/api/tree_survey/:id/restore` | 調查+ | Restore retired |
| GET | `/api/tree_survey/next_system_number` | 調查+ | Next ID |
| GET | `/api/tree_survey/next_project_number/:projectCode` | 調查+ | Next project-scoped ID |
| GET | `/api/tree_survey/common_species/:projectCode` | JWT | Frequent species for project |

---

## Pending measurements (staging → transfer)

Mount: `/api/pending-measurements` · `routes/pending_measurements.js`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/pending-measurements/batch` | project | Upload BLE/manual batch |
| GET | `/api/pending-measurements/sessions` | project | List sessions |
| GET | `/api/pending-measurements/trees` | project | Pending trees list |
| GET | `/api/pending-measurements/stats/overview` | project | Stats |
| GET | `/api/pending-measurements/:id` | project | Single pending row |
| PATCH | `/api/pending-measurements/:id` | project | Edit pending |
| POST | `/api/pending-measurements/transfer` | project | **Commit to tree_survey** (transaction) |
| PATCH | `/api/pending-measurements/session/:sessionId/project` | project | Reassign session project |
| DELETE | `/api/pending-measurements/session/:sessionId` | project | Delete session |

---

## Project boundaries

Mount: `/api/project-boundaries` · `routes/project_boundaries.js` (13 endpoints)

Key paths: `GET/POST /`, `GET/DELETE /:projectName`, `GET/DELETE /by_code/:projectCode`, `POST /import`, `POST /check`, `POST /suggest`, `GET /export.kml`, `POST /batch_match`, `POST /find_project`, `GET /status/:projectName`.

---

## Tree species & statuses

| Method | Path | Auth | Route |
|--------|------|------|-------|
| GET/POST | `/api/tree_species` | JWT / 調查+ | `treeSpecies.js` |
| GET | `/api/tree_species/search`, `/enhanced`, `/next_number` | JWT | `treeSpecies.js` |
| GET/POST | `/api/tree_species/synonyms/report`, `/synonyms/merge` | 調查+ | `treeSpecies.js` |
| GET/POST | `/api/tree-statuses` | JWT / 調查+ | `tree_statuses.js` |

---

## Species identification (PlantNet)

Mount: `/api/species` · `routes/speciesIdentification.js`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/species/identify` | JWT | Photo → species (PlantNet + local match) |
| GET | `/api/species/search` | JWT | Search catalog |
| GET | `/api/species/gbif/:name` | JWT | GBIF lookup |
| GET | `/api/species/inaturalist/:id` | JWT | iNaturalist lookup |
| GET | `/api/species/status` | JWT | Service status |

Requires `PLANTNET_API_KEY` in `.env`.

---

## Tree images (Cloudinary)

Mount: `/api/tree-images` · `routes/tree_images.js`

| Method | Path | Auth |
|--------|------|------|
| POST | `/api/tree-images/upload` | JWT |
| GET | `/api/tree-images/:id` | JWT |
| GET | `/api/tree-images/tree/:treeId` | JWT |
| DELETE | `/api/tree-images/:id` | JWT |

---

## Statistics & reports

| Method | Path | Auth | Route |
|--------|------|------|-------|
| GET | `/api/tree_statistics` | project | `statistics.js` |
| GET | `/api/export/excel` | JWT | `reports.js` |
| GET | `/api/export/pdf` | JWT | `reports.js` |
| GET | `/api/sustainability_report` | JWT | `reports.js` |

---

## AI chat & sustainability reports

Mount: `routes/ai.js` at `/api`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/api/llm-options` | 調查+ | Available models |
| GET | `/api/chat/sessions` | 調查+ | List chat sessions |
| GET | `/api/chat/sessions/:sessionId` | 調查+ | Session messages |
| DELETE | `/api/chat/sessions/:sessionId` | 調查+ | Delete session |
| POST | `/api/chat` | 調查+ | **SSE stream** chat |
| POST | `/api/ai/direct-chat` | 調查+ | Non-stream chat |
| GET | `/api/reports/ai-sustainability` | 調查+ | AI carbon report |
| GET | `/api/reports/ai-sustainability/pdf` | 調查+ | PDF export |
| GET | `/api/download/:filename` | 調查+ | Download generated file |

---

## AI agent

Mount: `/api/agent` · `routes/agent.js`

| Method | Path | Auth |
|--------|------|------|
| POST | `/api/agent/chat` | 調查+ |
| GET | `/api/agent/status` | 調查+ |
| GET | `/api/agent/models` | 調查+ |

---

## ML service proxy

Mount: `/api/ml-service` · `routes/ml_service.js`

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/ml-service/status`, `/health`, `/config` | Service info |
| POST | `/api/ml-service/measure-dbh` | Manual DBH measure |
| POST | `/api/ml-service/auto-measure-dbh` | Auto pipeline |
| POST | `/api/ml-service/auto-measure-dbh-multi` | Multi-trunk |
| POST | `/api/ml-service/debug/depth-at-point` | Debug depth |

Requires `ML_SERVICE_URL` + `ML_API_KEY`.

---

## ML training data (research)

Mount: `/api/ml-training` · `routes/ml_training_data.js` — batch upload, statistics, export, image, analysis.

---

## Maintenance locks

Mount: `/api/maintenance-locks` · `routes/maintenance_locks.js`

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/maintenance-locks` | List active locks |
| POST | `/api/maintenance-locks/:treeId` | Acquire lock |
| DELETE | `/api/maintenance-locks/:treeId` | Release lock |

---

## Tree management actions

Mount: `/api/tree-management/actions` · `routes/management.js` — generate, list, update, delete management actions.

---

## Location helpers

| Method | Path | Route |
|--------|------|-------|
| POST | `/api/location/validate` | `location.js` |
| POST | `/api/location/suggest_area` | `location.js` |

---

## Admin

Mount: `/api/admin` · `routes/admin.js`

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/api/admin/run-script` | 系統 | Run approved maintenance script |
| POST | `/api/admin/backup` | 系統 | DB backup |
| POST | `/api/admin/restore` | 系統 | DB restore |
| POST/GET/DELETE | `/api/admin/apikeys` | 系統 | API key CRUD |
| GET | `/api/admin/audit-logs` | 業務+ | Audit trail |
| GET | `/api/admin/reports/ai-sustainability` | 系統 | Admin report variant |

### Admin sub-routes

| Mount | File | Endpoints |
|-------|------|-----------|
| `/api/admin/import-csv` | `csvImport.js` | preview, execute |
| `/api/admin/ip-blacklist` | `ipBlacklist.js` | list, stats, add, delete |
| `/api/admin/research-dataset` | `research_dataset.js` | CRUD + export.csv |

---

## OpenAPI (future)

Western teams often publish **`openapi.yaml`** for Swagger UI and client codegen. This markdown catalog is the interim source of truth until an OpenAPI spec is added (see `CODEBASE_INVENTORY.md` Phase 3).

To verify an endpoint against code:

```bash
cd backend
grep -n "router\.\(get\|post\|put\|patch\|delete\)" routes/<file>.js
```

---

## Changelog

| Date | Change |
|------|--------|
| 2026-06-29 | Initial catalog: 145 endpoints from route audit |
