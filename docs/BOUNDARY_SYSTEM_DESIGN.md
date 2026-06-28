# Project Boundaries

GeoJSON polygons that define project areas for map display, GPS auto-matching, and coordinate validation.

**Last reviewed against code**: 2026-06-29

---

## Terminology (UI vs database)

| UI label (current) | DB table | Key field |
|--------------------|----------|-----------|
| 專案 (port program) | `project_areas` | `area_name` |
| 區 (sample zone) | `projects` | `project_code`, `name` |
| 邊界 polygon | `project_boundaries` | GeoJSON, linked by `project_code` |

Historical docs may use old wording — **trust this table** when reading code.

---

## Overview

1. **Projects** (`projects`) and **boundaries** (`project_boundaries`) are separate — creating a project does **not** auto-create a polygon.
2. **No boundary** → manual project selection allowed; GPS auto-match will not assign that project.
3. **With boundary** → matching, validation, map overlay, BLE assignment use polygon; cache must refresh after edits.

Coordinator: `lib/services/v3/project_boundary_coordinator.dart`

---

## User flow

| Step | Page | Behavior |
|------|------|----------|
| Draw boundary | `project_boundary_draw_page.dart` | Save → `afterBoundaryMutation()` |
| Map view | `map_page.dart` | `forMapDisplay(forceRefresh: true)` |
| V3 auto-match | `manual_input_page_v3.dart` | `beforeAutoMatch()` |
| BLE import assign | `ble_import_page.dart` | `getAllBoundaries(forceRefresh: true)` |
| Logout | — | `ProjectBoundaryService.clearCache()` |

---

## API

Mount: `/api/project-boundaries` — 13 endpoints. See `API_REFERENCE.md` § Project boundaries.

Common operations:

- `POST /import` — KML/KMZ/GeoJSON
- `POST /check` — point-in-polygon
- `GET /by_code/:projectCode`
- `GET /export.kml`

---

## Code map

| Layer | File |
|-------|------|
| Routes | `backend/routes/project_boundaries.js` |
| Validation / import | `backend/utils/boundaryImport.js`, `boundarySuggest.js` |
| Frontend service | `lib/services/v3/project_boundary_service.dart` |
| Coordinator | `lib/services/v3/project_boundary_coordinator.dart` |
| Map UI | `lib/map_page.dart`, `boundary_status_banner.dart` |

Migrations: `06a_project_boundaries_schema.pg.sql`, `18_project_boundaries_fk.pg.sql`, `30_project_boundaries_source.pg.sql`.

---

## Data model

| Table | Notes |
|-------|-------|
| `project_boundaries` | Polygon geometry; FK to `projects.project_code` (migration 18) |
| `projects` | Canonical project metadata |
| `project_areas` | Higher-level area (e.g. port name) |

Dev-only seed polygons: `dev-fixtures/06_project_boundaries_seed.pg.sql` — **not** applied in production migrations.

---

## Configuration

- `BOUNDARY_IMPORT_MAX_MB` — upload size limit (default 5 MB)

---

## Testing

- Boundary import / match tests in `backend/tests/`
- Frontend boundary coordinator tests where present

---

## Related

- `PROJECT_DATA_AND_DOMAIN.md` — CSV / dev seed context
- `DATABASE_NORMALIZATION.md` — deliberate denormalized name caches on `tree_survey`
