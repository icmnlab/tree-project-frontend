# Documentation Coverage Audit

Honest map of **what is documented** vs **what exists on GitHub**. Use with `CODEBASE_INVENTORY.md` for file counts.

**Audit date**: 2026-06-29  
**Method**: Directory inventory + doc cross-reference (not line-by-line proofreading of every historical sentence)

---

## Executive answer

| Question | Answer |
|----------|--------|
| Are all **production** flows documented? | **Yes** — module guides + ARCHITECTURE + API_REFERENCE |
| Is every **source file** named in a doc? | **Layers yes, every file no** — 129 Dart files are grouped by directory/feature, not one page per file (standard at Google/Amazon scale) |
| Were **old README/docs** read word-for-word? | **Rewritten against code**, with local archive snapshot for diff; research files kept intentionally |
| Database documented? | **Yes** — `DATABASE_DESIGN.md` + `DATABASE_SCHEMA.md` + `DATABASE_NORMALIZATION.md` + ARCHITECTURE §3 |
| Controllers / services documented? | **Yes** — `backend/docs/SOURCE_LAYOUT.md` |
| All GitHub files in scope? | **Application + ops yes**; binary assets, lockfiles, CI YAML summarized below |

**Not done (deferred)**: Phase 4 VM-specific runbook (SSH/webhook/Funnel) until school-side verification.

**Documentation set complete** for handover except Phase 4 ops (2026-06-29).

---

## Documentation stack (Western big-tech pattern)

```
docs/README.md          ← Hub (single entry)
ARCHITECTURE.md         ← System design
CODEBASE_INVENTORY.md   ← Feature/file catalog
API_REFERENCE.md        ← Human API catalog
backend/openapi/        ← Machine API catalog
DATABASE_DESIGN.md     ← Why 49 files + entity model (handover FAQ)
DATABASE_SCHEMA.md     ← Migration order + table catalog
backend/docs/SOURCE_LAYOUT.md ← Backend layer catalog
<Module guides>.md      ← One per domain
<Runbooks>.md           ← Deploy, build, verify, field SOP
RESEARCH_REFERENCE.md   ← Non-production research tier
DOCUMENTATION_RETENTION.md ← Delete vs keep policy
```

**Hyperlink rule**: hub links down; module guides link up to ARCHITECTURE + API_REFERENCE; backend README points to frontend `docs/` (single canonical copy).

---

## Coverage by repository area

### Frontend (`tree-project-frontend`)

| Area | Files (approx) | Documented in |
|------|----------------|---------------|
| `lib/screens/` | 29 | CODEBASE_INVENTORY §3, ARCHITECTURE §5, module guides |
| `lib/services/` | 45 | CODEBASE_INVENTORY §3.4, ARCHITECTURE |
| `lib/utils/`, `widgets/`, `models/` | 35+ | ARCHITECTURE §5, BLE/ boundary guides |
| `lib/config/` | 3 | BUILD_GUIDE, LOCAL_DEVELOPER_SETUP, EXPERIMENTAL_FEATURES |
| `test/` | 28 | HANDOFF §5, VERIFICATION §2 |
| `assets/` | models, COA JSON | BUILD_GUIDE, CARBON_CALCULATION, ml_service |
| `android/`, `ios/` | native | BUILD_GUIDE, HANDOFF_SECRETS §H |
| `docs/` | 30+ md | README hub |
| Root README | 1 | Quick start → points to `docs/` |

### Backend (`tree-project-backend`)

| Area | Files (approx) | Documented in |
|------|----------------|---------------|
| `routes/` | 24 | API_REFERENCE, SOURCE_LAYOUT, openapi.yaml |
| `controllers/` | 8 | SOURCE_LAYOUT |
| `services/` | 16 | SOURCE_LAYOUT, ARCHITECTURE §6, module guides |
| `middleware/` | 7 | SOURCE_LAYOUT, ARCHITECTURE §2 |
| `utils/` | 11 | SOURCE_LAYOUT |
| `database/initial_data/` | 49 SQL | DATABASE_SCHEMA, ARCHITECTURE §3 |
| `scripts/` | 20+ | SOURCE_LAYOUT, LAB_DEPLOYMENT |
| `tests/` | 39 | tests/FRAMEWORK.md |
| `ml_service/` | Python | ml_service/README.md |
| `dev-fixtures/` | CSV/SQL | PROJECT_DATA_AND_DOMAIN, DATABASE_SCHEMA |
| `data/` | geojson, COA | SOURCE_LAYOUT (geo.js), CARBON |
| `openapi/` | yaml | openapi/README.md |
| `config/` | db | HANDOFF_SECRETS, LAB_DEPLOYMENT |

### Intentionally light documentation

| Area | Why |
|------|-----|
| `node_modules/`, `.dart_tool/`, `build/` | Generated; not in git |
| `package-lock.json`, `pubspec.lock` | Standard lockfiles |
| `.github/workflows/` | CI described in HANDOFF §5; workflow is self-explanatory |
| Individual migration SQL bodies | Named + ordered in DATABASE_SCHEMA; details in SQL comments |
| Every test case | Listed by area in VERIFICATION + test file names in FRAMEWORK |

---

## Old docs vs current (archive snapshot)

Local archive: `project_code/docs/archive/frontend-docs-snapshot-20260629/` (21 files, **not in git**).

| Old file | Current status |
|----------|----------------|
| All 21 snapshot `.md` files | Superseded by Western rewrites (2026-06-29) |
| Missing from snapshot (new) | SPECIES_AND_PLANTNET, EXPERIMENTAL_FEATURES, VISUAL_MEASUREMENT, AI_SUSTAINABILITY_REPORT, DATABASE_SCHEMA, SOURCE_LAYOUT, RESEARCH_REFERENCE, this file, openapi |

Content from old ops-heavy Chinese prose was **merged** into English runbooks, not copied verbatim.

---

## Gaps & maintenance rules

| Gap | Severity | Action |
|-----|----------|--------|
| OpenAPI request/response schemas | **By design — shallow** | Documented in `OPENAPI_SCOPE.md`; deepen when external codegen needed |
| Per-endpoint RBAC in OpenAPI | **By design** | `API_REFERENCE.md` + middleware code |
| VM webhook/Funnel steps | Medium | Phase 4 after school |
| Play Store / upload keystore | Low | **`ANDROID_RELEASE_AND_PLAY_STORE.md`** added |

**When code changes**: update ARCHITECTURE + API_REFERENCE + openapi regen + affected module guide in same PR.

---

## Related

- [`DOCUMENTATION_RETENTION.md`](./DOCUMENTATION_RETENTION.md)
- [`RESEARCH_REFERENCE.md`](./RESEARCH_REFERENCE.md)
