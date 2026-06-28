# Database Design Guide

Why the schema looks the way it does, and how to explain **49 SQL files** in a handover or review.

**Last reviewed**: 2026-06-29  
**Related**: `DATABASE_SCHEMA.md` (table list) · `DATABASE_NORMALIZATION.md` (denorm rules) · `SURVEY_HISTORY.md` (pending → transfer) · `ARCHITECTURE.md` §3

---

## One-sentence summary

We use **PostgreSQL with versioned SQL migrations**, a **snapshot + history** model for trees, **pending staging** for field BLE batches, and **controlled denormalization** for map/list performance — not one giant dump file.

---

## Design principles

| # | Principle | Why |
|---|-----------|-----|
| 1 | **Schema in git, row data on server** | Reproducible deploys; no user passwords or survey exports in GitHub |
| 2 | **One migration file = one reviewable change** | Same as Flyway/Liquibase; production runs only pending files |
| 3 | **Snapshot for reads, append-only history for audit** | Map and carbon need fast “current value”; compliance needs “who measured when” |
| 4 | **Pending before commit** | Field teams offline / batch BLE; transfer is one transaction |
| 5 | **Master data vs business data** | Species catalog ships with app; tree rows start empty in production |
| 6 | **Field reality over strict FKs** | Unknown species names allowed; catalog is advisory, not blocking |

---

## Entity model (how pieces connect)

```
project_areas          (program / port — e.g. 高雄港)
    │
    └── projects       (zone — stable key: project_code)
            │
            ├── project_boundaries   (GeoJSON polygon per project_code)
            ├── user_projects        (which users see which project_code)
            │
            └── tree_survey          (one row = one tree's CURRENT snapshot)
                    │
                    ├── tree_survey_measurements   (each measurement event)
                    ├── tree_measurement_raw         (instrument JSON at transfer)
                    └── tree_images                  (Cloudinary URL; optional measurement_id)

pending_tree_measurements   (staging — before transfer)
tree_species + species_synonyms   (reference catalog — not FK-enforced on survey)
users + invites + audit_logs + ip_blacklist   (access & security)
```

**Hierarchy naming** (UI vs DB): see `PROJECT_DATA_AND_DOMAIN.md`. Rule for code: **always join on `project_code`**, not display names.

---

## The three tree tables (most important design)

| Table | Analogy | Written when |
|-------|---------|--------------|
| `pending_tree_measurements` | Draft inbox | BLE batch, field draft |
| `tree_survey` | Business card (current) | After transfer, create_v2, update_v2 |
| `tree_survey_measurements` | Diary (append-only) | transfer, create_v2, maintenance re-measure |

**Why not one table?**

- Pending rows can be discarded, edited, or retried without polluting official inventory.
- History must not be overwritten when someone edits a typo on the snapshot (`update_v2` updates snapshot only).
- Carbon and map queries hit one row per tree — no “latest measurement” subquery on every read.

Detail: `SURVEY_HISTORY.md`.

---

## Denormalization (intentional)

`tree_survey` duplicates `project_name`, `species_name`, etc. for:

- Fast list/map/export without 4-way JOINs on every request
- CSV semantics inherited from early field workflows
- Triggers cascade renames from `projects` / `tree_species` to keep caches aligned

Trade-off: display names can drift if master data changes outside normal paths — mitigated by cascade triggers (migrations 10, 11) and admin tools.

Detail: `DATABASE_NORMALIZATION.md`.

---

## Why `tree_survey.species_id` has no FK

Field crews enter names not yet in catalog. PlantNet may auto-insert species. A hard FK would block saves. `tree_species` is a **suggestion list** + carbon coefficients, not a gate.

---

## Security & multi-user tables

| Table | Role |
|-------|------|
| `user_projects` | Row-level scope (with `projectAuth` middleware) |
| `maintenance_tree_locks` | 45-minute exclusive lock for maintenance re-measure |
| `audit_logs` | Login and admin actions |
| `ip_blacklist` / `ip_login_attempts` | Brute-force protection |

Optimistic locking uses `expected_updated_at` on update — not a separate table.

---

## Why 49 SQL files? (handover FAQ)

### 30-second answer

> Most files are **schema migrations**, not data. We evolved the DB over two years — one file per change, like Flyway. Production only runs **new** files. Test tree CSVs are in `dev-fixtures/` and **never** load in production.

### 2-minute answer

| Question | Answer |
|----------|--------|
| Are they all necessary? | **Schema migrations: yes.** Dev CSV (~7000 test trees): **no** for production |
| Why not one `schema.sql`? | Cannot upgrade existing servers incrementally; cannot review one change per PR |
| Is 49 a lot? | Normal for a mature app (Rails apps often have 100+ migrations) |
| What ships to prod empty? | `tree_survey`, `projects`, `users` (admin via script) |
| What ships with seed rows? | `tree_species`, `species_synonyms`, `tree_status_options` (reference only) |

### File types in `database/initial_data/`

| Pattern | Example | Purpose |
|---------|---------|---------|
| `NN_*.pg.sql` | `15_tree_survey_measurements.pg.sql` | Feature migration |
| `00_*.pg.sql` | `00_init_functions.pg.sql` | Shared functions / early normalisation |
| `*_backfill_*.pg.sql` | `17_backfill_tree_survey_measurements.pg.sql` | One-time data heal on existing DBs |
| `*_cascade_trigger.pg.sql` | `10_projects_cascade_trigger.pg.sql` | Rename propagation |
| `*_drop_*.pg.sql` | `22_drop_legacy_rag_and_carbon_tables.pg.sql` | Remove deprecated tables |
| `tree_survey_with_areas.pg.sql` | view | Read-optimised join for reporting |

Runner: `scripts/migrate.js` (full bootstrap) · `scripts/run_pending_migrations.js` (production + app startup).

---

## Production vs development data policy

```
migrate.js
  ├── Always: schema + reference master data
  ├── Production: SKIP_CSV_IMPORT=1 → skip ~7000 test trees
  └── Dev/CI: may import dev-fixtures CSV for map/load tests
```

**Triple guard** against test trees in prod: env flag, “skip if rows exist”, and separate `dev-fixtures/` directory.

Accounts: `users.pg.sql` creates **table only**. First admin: `create_lab_admin.js` — never SQL seed passwords in git.

---

## What we removed over time

Migration `22_drop_legacy_rag_and_carbon_tables.pg.sql` removed static RAG/carbon tables. Carbon is now **computed at write time** via `carbonCalculationService.js` (handbook formulas), stored on `tree_survey` columns.

---

## How to explain design in a meeting

Suggested order:

1. Draw **areas → projects → trees** hierarchy (`project_code` as key).
2. Walk **BLE → pending → transfer → snapshot + history** (one transaction).
3. State **reference data in git, survey data on server**.
4. Answer “49 files?” with **incremental migrations** analogy (Flyway).
5. Point skeptics to **89 backend tests** that assert triggers, lifecycle, transfer guards.

Deep dive docs: this file + `SURVEY_HISTORY.md` + `DATABASE_SCHEMA.md`.

---

## Related

| Topic | Document |
|-------|----------|
| Migration order & table catalog | `DATABASE_SCHEMA.md` |
| Normalization trade-offs | `DATABASE_NORMALIZATION.md` |
| Pending / transfer API | `SURVEY_HISTORY.md` |
| Carbon write path | `CARBON_CALCULATION.md` |
| Boundaries | `BOUNDARY_SYSTEM_DESIGN.md` |
