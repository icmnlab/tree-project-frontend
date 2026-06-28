# Project Data & Domain Model

Terminology for projects, areas, CSV dev data, and production data flows.

**Last reviewed against code**: 2026-06-29

---

## Overview

Three layers appear in UI and database:

```
project_areas (專案 / port program)
    └── projects (區 / zone, keyed by project_code)
            └── tree_survey (individual trees)
            └── project_boundaries (optional polygon)
```

Stable join key: **`project_code`** (not display name).

---

## Dev CSV (`tree_survey_data.csv`)

| Item | Detail |
|------|--------|
| Location | `backend/dev-fixtures/tree_survey_data.csv` |
| Size | ~7000 rows (port authority test trees) |
| Loaded by | `node scripts/migrate.js` only when `SKIP_CSV_IMPORT` unset |
| Production | **Never** — use `SKIP_CSV_IMPORT=1` or `run_pending_migrations.js` only |

### Column mapping

| CSV header | DB column | Meaning |
|------------|-----------|---------|
| `program_name` | `project_location` | Port program → links `project_areas` |
| `block_name` | `project_name` | Zone name → `projects.name` |
| `project_code` | `project_code` | Stable key |

Mapping: `scripts/migrate.js` → `CSV_HEADER_TO_DB`.

---

## Production data sources

| Source | Mechanism |
|--------|-----------|
| Field survey | pending → transfer, create_v2 |
| Maintenance | maintenance transfer |
| Admin CSV | `POST /api/admin/import-csv/*` |
| Dev seed | **Not on production** |

---

## Dev boundary seed

`dev-fixtures/06_project_boundaries_seed.pg.sql` — convex hull from CSV tree points. Applied only via `seed_dev_boundaries.js` in dev/CI, not production migrations.

---

## Code map

| Layer | File |
|-------|------|
| Migrate / CSV | `backend/scripts/migrate.js` |
| Projects API | `backend/routes/projects.js` |
| Areas API | `backend/routes/project_areas.js` |
| Domain helpers | `backend/utils/projectCatalog.js`, `domainAliases.js` |
| Frontend scope | `lib/models/project_scope.dart`, `project_scope_store.dart` |

---

## Species catalog

Master data in git SQL (`tree_species.pg.sql`, `species_synonyms.pg.sql`) — not survey data. PlantNet may auto-add species via `speciesIdentificationService.js`.

API: `/api/species/*`, `/api/tree_species/*`.

---

## Related

- `BOUNDARY_SYSTEM_DESIGN.md`
- `DATABASE_NORMALIZATION.md`
- `ARCHITECTURE.md` §3 — what belongs in git vs DB

---

## Changelog

| Date | Change |
|------|--------|
| 2026-06-29 | Western rewrite; dev vs prod data paths clarified |
