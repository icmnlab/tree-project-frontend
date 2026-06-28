# Survey History & Pending Workflow

How field measurements become official tree records and how history is stored over time.

**Last reviewed against code**: 2026-06-29

---

## Overview

Field data follows a **two-stage** pattern:

1. **Pending** — BLE batches and drafts land in `pending_tree_measurements`.
2. **Transfer** — One transaction commits to `tree_survey` + appends `tree_survey_measurements`.

Direct manual create uses `POST /api/tree_survey/create_v2` (writes snapshot + initial history row in one transaction).

---

## User flow

| Flow | Screens | Backend |
|------|---------|---------|
| BLE live → pending | `ble_live_session_page.dart` | `POST /pending-measurements/batch` |
| Edit pending | `pending_measurement_task_page.dart` | GET/PATCH pending |
| Transfer to official | transfer UI in survey flow | `POST /pending-measurements/transfer` |
| Maintenance re-measure | `maintenance_survey_page.dart` | transfer with `survey_mode=maintenance` |
| Manual new tree | `tree_input_page_v2.dart`, V3 forms | `POST /tree_survey/create_v2` |

---

## Data model

| Table | Role |
|-------|------|
| `pending_tree_measurements` | Staging; session-based batches |
| `tree_survey` | **Current snapshot** per tree (map, list, carbon) |
| `tree_survey_measurements` | **Each measurement event** (new / maintenance / snapshot backfill) |
| `tree_measurement_raw` | Raw BLE/GPS JSON at transfer |
| `tree_images` | Photos; optional `measurement_id` link (migration 32) |

### `survey_mode` values

| Value | Meaning |
|-------|---------|
| `new` | New tree (transfer or create_v2) |
| `maintenance` | Re-measure existing `target_tree_id` |
| `snapshot` | Migration 17 baseline backfill only |

### Lifecycle (`lifecycle_status`)

| Value | Carbon counted? | Map display |
|-------|-----------------|-------------|
| `active` | Yes | Normal |
| `dead` / `fallen` / `removed` | No | Grey / retired |

Logic: `backend/utils/treeLifecycle.js`. Endpoints: `POST /tree_survey/:id/retire`, `/restore`.

**Note**: `update_v2` and CSV import update the snapshot only — they do **not** append measurement history (by design; edits vs new measurements).

---

## API

See `API_REFERENCE.md` § Tree survey, § Pending measurements.

Key endpoints:

- `POST /api/pending-measurements/batch`
- `POST /api/pending-measurements/transfer`
- `POST /api/tree_survey/create_v2`
- `PUT /api/tree_survey/update_v2/:id` (optimistic lock via `expected_updated_at`)
- `GET /api/tree_survey/by_id/:id/measurements`

---

## Code map

| Layer | File |
|-------|------|
| Pending routes | `backend/routes/pending_measurements.js` (`transfer` ~line 905) |
| Survey routes | `backend/routes/treeSurvey.js` |
| Create controller | `backend/controllers/treeSurveyCreateController.js` |
| Update controller | `backend/controllers/treeSurveyUpdateController.js` |
| Lifecycle | `backend/utils/treeLifecycle.js` |
| Frontend pending | `lib/services/pending_measurement_service.dart` |
| History panel | `lib/widgets/tree_measurement_history_panel.dart` |

Concurrency: optimistic lock, `X-Request-Id` dedup, advisory locks for ID allocation.

---

## Configuration

- `SKIP_CSV_IMPORT=1` on production DB init (no dev CSV trees)
- `DISABLE_RATE_LIMIT` — CI only

---

## Testing

- `backend/tests/contracts/optimistic_lock.test.js`
- Pending transfer idempotency / journey tests in `backend/tests/`
- Frontend pending tests in `frontend/test/`

---

## Known gaps (documented in code/issues)

- Transfer audit log detail — partial; login/admin audits exist
- Hard delete cascades history — prefer retire over delete

---

## Related

- `CARBON_CALCULATION.md` — only `active` trees in totals
- `VLGEO2_STD_APPLICATION_GUIDE.md` — BLE → pending path
- `PROJECT_DATA_AND_DOMAIN.md` — project/area terminology
