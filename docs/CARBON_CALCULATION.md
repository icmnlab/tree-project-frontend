# Carbon Calculation

How above-ground biomass and CO₂ equivalents are computed from tree measurements.

**Last reviewed against code**: 2026-06-29

---

## Overview

Carbon totals aggregate **active** trees only (`lifecycle_status = 'active'`). Retired trees (dead/fallen/removed) are excluded from dashboard and report sums.

Formula chain: DBH + height + species → biomass (allometric equation) → carbon fraction → CO₂ equivalent.

---

## User flow

| Surface | Screen | API / mechanism |
|---------|--------|-----------------|
| Statistics page | `statistics_page.dart` | `GET /api/tree_statistics` → `data.carbon` |
| Tree create/update preview | input forms | Client: `HandbookCarbonService` |
| Persisted value | — | Written on create/transfer/update via backend service |
| AI sustainability report | `ai_sustainability_report_screen.dart` (Experimental) | `GET /api/reports/ai-sustainability` + `tree_statistics` for context |

There is **no** dedicated `/api/carbon/*` router — totals come from stored `tree_survey.carbon_storage` rows.

---

## Calculation logic

| Step | Implementation |
|------|----------------|
| Species equation | `tree_species` columns + `carbonCalculationService.js` |
| Missing species | Fallback generic equation or skip (logged) |
| DBH source | `tree_survey.dbh_cm` snapshot |
| Height source | `tree_survey.height_m` snapshot |
| Lifecycle filter | `treeLifecycle.js` helpers |

Backend service: `backend/services/carbonCalculationService.js` (handbook Ch.6 stepwise)  
Aggregation route: `backend/routes/statistics.js` → mount `/api/tree_statistics`

---

## API

| Method | Path | Notes |
|--------|------|-------|
| GET | `/api/tree_statistics` | `data.carbon`: `total_carbon`, `avg_carbon`, annual fields; active trees only |
| GET | `/api/tree_statistics?areas=…` | Filter by `project_location` |

See `API_REFERENCE.md` § Statistics. Per-tree values appear on tree survey GET responses as `carbon_storage`.

---

## Code map

| Layer | File |
|-------|------|
| Backend calc | `backend/services/carbonCalculationService.js` |
| Write paths | `controllers/treeSurveyCreateController.js`, `treeSurveyUpdateController.js`, `routes/pending_measurements.js` (transfer) |
| Aggregation | `backend/routes/statistics.js` |
| Lifecycle filter | inline in statistics query + `backend/utils/treeLifecycle.js` |
| Frontend preview | `lib/services/handbook_carbon_service.dart`, `carbon_calculation_service.dart` |
| UI | `lib/statistics_page.dart` |

---

## Data model

| Table | Role |
|-------|------|
| `tree_survey` | Input DBH/height/species; `lifecycle_status` |
| `tree_species` | Allometric coefficients |
| `tree_survey_measurements` | Historical values (carbon uses snapshot, not full history replay) |

---

## Configuration

No separate carbon env vars — depends on species catalog migrations and active tree set.

---

## Testing

- Backend carbon unit tests in `backend/tests/` (if present)
- Invariant: retired trees excluded — verify via lifecycle tests

---

## Related

- `SURVEY_HISTORY.md` — snapshot vs measurement history
- `AI_SUSTAINABILITY_REPORT.md` — narrative report over same aggregates (Experimental)
- `PROJECT_DATA_AND_DOMAIN.md` — project scoping
