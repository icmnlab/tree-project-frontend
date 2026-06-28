# Database Schema Reference

PostgreSQL schema, migration order, and table catalog for **Sustainable TreeAI**.

**Last reviewed**: 2026-06-29  
**SQL location**: `tree-project-backend/database/initial_data/*.pg.sql`  
**Runner**: `scripts/migrate.js` (full) · `scripts/run_pending_migrations.js` (production incremental)  
**Related**: [`DATABASE_DESIGN.md`](./DATABASE_DESIGN.md) (why & how we designed) · `DATABASE_NORMALIZATION.md` · `ARCHITECTURE.md` §3 · `SURVEY_HISTORY.md`

---

## Overview

| Category | In git? | Applied in production? |
|----------|---------|------------------------|
| Schema migrations | Yes — 49 ordered SQL files | Yes — via `schema_migrations` table |
| Reference master data | Yes — species, statuses, synonyms | Yes |
| Dev fixtures | `dev-fixtures/` | **No** — `SKIP_CSV_IMPORT=1` |
| Survey / user data | PostgreSQL on server | Never in git |

---

## Migration order

Production applies files **in this exact order** (from `scripts/migrate.js`):

| # | File | Purpose |
|---|------|---------|
| 1 | `00_init_functions.pg.sql` | Shared DB functions |
| 2 | `users.pg.sql` | Users table (no seed accounts) |
| 3 | `system_settings_and_audit.pg.sql` | Audit logs |
| 4 | `project_areas.pg.sql` | Port / program areas |
| 5 | `tree_species.pg.sql` | Species master catalog |
| 6 | `tree_survey.pg.sql` | Main tree snapshot table |
| 7 | `00_normalization_schema.pg.sql` | Normalization columns |
| 8 | `tree_management_actions.pg.sql` | Management actions |
| 9–10 | `chat_logs*.pg.sql` | AI chat history |
| 11 | `ml_training_data.pg.sql` | ML correction batches |
| 12 | `z_pending_tree_measurements.pg.sql` | Pending staging |
| 13 | `tree_images.pg.sql` | Photo metadata |
| 14 | `species_synonyms.pg.sql` | Synonym map |
| 15 | `03_user_projects.pg.sql` | User ↔ project scope |
| 16 | `05_ip_blacklist.pg.sql` | IP security |
| 17 | `06a_project_boundaries_schema.pg.sql` | Boundary table schema |
| 18 | `07_backfill_projects_area_id.pg.sql` | Data heal |
| 19 | `08_text_integrity_check.pg.sql` | U+FFFD guard |
| 20–21 | `10_*`, `11_*` cascade triggers | Rename propagation |
| 22 | `12_research_dataset.pg.sql` | Research DBH dataset |
| 23–35 | `13` … `35` | IDs, history, boundaries FK, lifecycle, status catalog, alignment |

**View** (after migrations): `tree_survey_with_areas.pg.sql`

Current head: **migration 35** (`35_backfill_lifecycle_alignment.pg.sql`).

---

## Core tables

### Identity & access

| Table | Purpose |
|-------|---------|
| `users` | Accounts, `role`, lockout, password hash |
| `user_projects` | `(user_id, project_code)` scope |
| `invites` | Registration invite codes |
| `audit_logs` | Login and admin audit trail |
| `ip_blacklist` | Blocked IPs |
| `ip_login_attempts` | Login failure counters |

### Project hierarchy

| Table | Purpose |
|-------|---------|
| `project_areas` | Program / port level (`area_name`) |
| `projects` | Zone level (`project_code`, `name`) |
| `project_boundaries` | GeoJSON polygons per `project_code` |

### Trees & measurements

| Table | Purpose |
|-------|---------|
| `tree_survey` | **Current snapshot** per tree (map, list, carbon) |
| `tree_survey_measurements` | Append-only measurement history |
| `pending_tree_measurements` | Staging before transfer |
| `tree_measurement_raw` | Raw instrument JSON at transfer |
| `tree_images` | Cloudinary URLs; optional `measurement_id` |
| `maintenance_tree_locks` | Concurrent maintenance lock |

### Master data

| Table | Purpose |
|-------|---------|
| `tree_species` | Species catalog + carbon coefficients |
| `species_synonyms` | Alias → canonical species |
| `tree_status_options` | Shared condition picklist |

### AI & ML

| Table | Purpose |
|-------|---------|
| `chat_logs` | AI chat / agent messages |
| `agent_token_usage` | Agent hourly token budget |
| `ml_training_batches` / `ml_training_records` | Correction upload (optional) |
| `research_dataset_entries` | Admin research DBH calibration |

### Legacy removed

Tables from old RAG/carbon static data dropped in migration `22_drop_legacy_rag_and_carbon_tables.pg.sql`. Carbon now computed in `carbonCalculationService.js`.

---

## Key design choices

| Topic | Detail | Doc |
|-------|--------|-----|
| Snapshot vs history | `tree_survey` = current; `tree_survey_measurements` = events | `SURVEY_HISTORY.md` |
| Denormalized names | `project_name`, `species_name` on snapshot | `DATABASE_NORMALIZATION.md` |
| No species FK on survey | Field teams enter unknown names | `SPECIES_AND_PLANTNET.md` |
| Lifecycle | `lifecycle_status`: active / dead / fallen / removed | `utils/treeLifecycle.js` |
| Optimistic lock | `expected_updated_at` on update | `SURVEY_HISTORY.md` |

---

## Dev-only data (never production)

| Asset | Location |
|-------|----------|
| ~7000 test trees CSV | `dev-fixtures/tree_survey_data.csv` |
| Demo boundaries | `dev-fixtures/06_project_boundaries_seed.pg.sql` |
| Demo areas | `dev-fixtures/project_areas_seed.pg.sql` |

Controlled by `SKIP_CSV_IMPORT=1` or production migrate path. See `PROJECT_DATA_AND_DOMAIN.md`.

---

## Operations

```bash
# First-time production (empty DB)
SKIP_CSV_IMPORT=1 node scripts/migrate.js

# After deploy (incremental only)
node scripts/run_pending_migrations.js   # also on app startup in production

# Create admin (not SQL seed)
node scripts/create_lab_admin.js --username labadmin --password '...'
```

---

## Backend code map

| Concern | Primary files |
|---------|----------------|
| Create tree | `controllers/treeSurveyCreateController.js` |
| Transfer pending | `routes/pending_measurements.js` |
| Carbon write | `services/carbonCalculationService.js` |
| Boundaries | `utils/boundaryImport.js`, `routes/project_boundaries.js` |
| Migrations list | `scripts/migrate.js` → `migrationFiles` |

See also: `backend/docs/SOURCE_LAYOUT.md`
