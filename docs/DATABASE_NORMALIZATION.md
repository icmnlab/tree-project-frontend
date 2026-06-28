# Database Normalization

Why the schema mixes normalized FKs with deliberate denormalization on `tree_survey`.

**Last reviewed against code**: 2026-06-29

---

## Overview

The database is **mostly normalized** for master data (`projects`, `users`, `tree_species`) but **denormalizes display names** on `tree_survey` for read performance and offline-friendly exports. This is intentional — not technical debt to "fix" without a migration plan.

---

## Normalized core

| Entity | Table | Join key |
|--------|-------|----------|
| Project zone | `projects` | `project_code` |
| Port program | `project_areas` | `area_name` / area id |
| User scope | `user_projects` | `(user_id, project_code)` |
| Species | `tree_species` | `species_id` |
| Measurement history | `tree_survey_measurements` | `tree_id` FK |

---

## Deliberate denormalization on `tree_survey`

| Column | Source of truth | Why duplicated |
|--------|-----------------|----------------|
| `project_name` | `projects.name` | List/map queries without JOIN |
| `project_location` | `project_areas` | CSV legacy + display |
| `species_name` | `tree_species` | Export and map labels |
| Snapshot DBH/height | latest measurement | Current state for map/carbon |

**Updates**: `update_v2` and transfer rewrite snapshot fields; they do not always sync back to master tables (species may remain in catalog separately).

---

## History vs snapshot

| Table | Purpose |
|-------|---------|
| `tree_survey` | One row per tree — **current** state |
| `tree_survey_measurements` | Append-only measurement events |
| `tree_measurement_raw` | Raw instrument JSON at transfer |

See `SURVEY_HISTORY.md`.

---

## Boundaries

`project_boundaries.project_code` → FK to `projects` (migration 18). Geometry stored in boundary table, not on `projects`.

---

## Migrations

49 SQL files under `backend/migrations/`. Production path: `run_pending_migrations.js` (no CSV import).

Naming: `NN_description.pg.sql`.

---

## Code map

| Layer | File |
|-------|------|
| Migrations | `backend/migrations/*.pg.sql` |
| Migrate runner | `backend/scripts/migrate.js`, `run_pending_migrations.js` |
| Schema docs | inline comments in migration files |

---

## When to normalize further

Only if:

1. Display names drift from master data frequently, **and**
2. You add a sync job or trigger, **and**
3. Performance testing shows JOIN cost matters at your scale.

Until then, document denormalized fields in API responses and treat master tables as canonical for admin edits.

---

## Related

- `PROJECT_DATA_AND_DOMAIN.md`
- `SURVEY_HISTORY.md`
- `ARCHITECTURE.md`
