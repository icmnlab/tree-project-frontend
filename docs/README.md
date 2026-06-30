# Documentation

Documentation for **Sustainable TreeAI** (`tree-project-frontend` + `tree-project-backend`).

---

## Start here (read in this order)

| Step | Document | Who |
|------|----------|-----|
| **1** | **[ONBOARDING_READING_PATH.md](./ONBOARDING_READING_PATH.md)** | Everyone — day plan, what to read vs skip |
| **2** | **[HANDOFF.md](./HANDOFF.md)** §1–§5 | Developers — run locally, tests, repo layout |
| **3** | **[ARCHITECTURE.md](./ARCHITECTURE.md)** | Developers — system story, data flow, file map |
| **4** | **[DEVELOPMENT_WORKFLOW.md](./DEVELOPMENT_WORKFLOW.md)** | Developers — fork, branch, PR, CI, daily loop |
| **5** | Topic guides below | When you touch that feature |
| **Ops / deploy** | **[LAB_DEPLOYMENT_GUIDE.md](./LAB_DEPLOYMENT_GUIDE.md)** | VM operators |
| **Field crews** | **[FIELD_SURVEY_SOP.md](./FIELD_SURVEY_SOP.md)** | Surveyors (Chinese-friendly) |

**Repo roots**: [frontend README.md](../README.md) and [backend README.md](https://github.com/icmnlab/tree-project-backend/blob/main/README.md) are **code READMEs** (stack, build). The **documentation hub is this file** — do not start from scattered markdown elsewhere.

**Language**: English is the canonical language for architecture, API, and workflow docs (Western eng-team standard). Some operational docs (`HANDOFF.md`, `FIELD_SURVEY_SOP.md`) mix Chinese for the Taiwan lab. See [Language policy](#language-policy) below.

---

| Priority | Document | When to read |
|----------|----------|--------------|
| 0 | **[ONBOARDING_READING_PATH.md](./ONBOARDING_READING_PATH.md)** | Where to start on GitHub; day-by-day plan |
| 1 | **[ARCHITECTURE.md](./ARCHITECTURE.md)** | Onboarding: how the system works, file map, APIs, database in Git |
| 2 | **[CODEBASE_INVENTORY.md](./CODEBASE_INVENTORY.md)** | Full file/feature catalog (129 Dart, 168 JS, 145 APIs) |
| 3 | **[API_REFERENCE.md](./API_REFERENCE.md)** | All REST endpoints by module |
| 4 | **[DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md)** | Migrations, tables, dev vs production data |
| 5 | **[HANDOFF.md](./HANDOFF.md)** | Run locally, run tests, find other docs |
| 6 | **[DEVELOPMENT_WORKFLOW.md](./DEVELOPMENT_WORKFLOW.md)** | Git branch, PR, CI gates, daily dev loop |
| 7 | **[HANDOFF_SECRETS_CHECKLIST.md](./HANDOFF_SECRETS_CHECKLIST.md)** | API keys and `.env` setup |
| 8 | **[LAB_DEPLOYMENT_GUIDE.md](./LAB_DEPLOYMENT_GUIDE.md)** | Deploy to a production server |

## By topic

### Operations

| Document | Purpose |
|----------|---------|
| `LAB_DEPLOYMENT_GUIDE.md` | Server provisioning, PM2, nginx, TLS |
| `BUILD_GUIDE.md` | Android APK build |
| `LOCAL_DEVELOPER_SETUP.md` | `.env`, `key.properties`, debug keystore (not in git) |
| `ANDROID_RELEASE_AND_PLAY_STORE.md` | Upload keystore, AAB, Play Console checklist |
| `VERIFICATION_CHECKLIST.md` | Post-deploy smoke tests |
| `HANDOVER_CHECKLIST.md` | Handover day tasks |
| `FIELD_SURVEY_SOP.md` | Field survey procedures (BLE + manual) |

### Domain & data model

| Document | Purpose |
|----------|---------|
| `PROJECT_DATA_AND_DOMAIN.md` | Project / area terminology, CSV semantics |
| `SURVEY_HISTORY.md` | Snapshot vs measurement history tables |
| `DATABASE_DESIGN.md` | **Why** 49 SQL files, entity model, design principles (start here for DB questions) |
| `DATABASE_SCHEMA.md` | Migration order and table catalog |
| `DATABASE_NORMALIZATION.md` | Normalization rules |
| `BOUNDARY_SYSTEM_DESIGN.md` | Project boundaries |
| `ADMIN_AND_INVITE_DESIGN.md` | Admin UI and invite codes |
| `CARBON_CALCULATION.md` | Carbon formulas |
| `SPECIES_AND_PLANTNET.md` | Species catalog and PlantNet ID |

### Integrations

| Document | Purpose |
|----------|---------|
| `VLGEO2_STD_APPLICATION_GUIDE.md` | VLGEO2 BLE meter |
| `AI_AGENT_GUIDE.md` | AI chat and agent (Experimental) |
| `ML_CORRECTION_UPLOAD.md` | ML correction data upload |

### Experimental / in-progress features

Hidden by default (`ENABLE_EXPERIMENTAL_UI=false`). **Document anyway** — mark status so handover teams know what exists in code.

| Document | Purpose |
|----------|---------|
| `EXPERIMENTAL_FEATURES.md` | Build flag, hidden home cards, doc policy |
| `VISUAL_MEASUREMENT.md` | Scanner, pure-vision DBH, V3 ML sync |
| `AI_SUSTAINABILITY_REPORT.md` | AI-generated carbon sustainability report |

### Research (reference — not production SOP)

Start with **[RESEARCH_REFERENCE.md](./RESEARCH_REFERENCE.md)** for tier definitions.

| Document | Purpose |
|----------|---------|
| `RESEARCH_REFERENCE.md` | Index: research vs experimental vs production docs |
| `DBH_MEASUREMENT_RESEARCH_V2.md` | DBH vision research archive (2026-02) |
| `DBH_PURE_VISION_RESEARCH.md` | Vision-only DBH research (V1) |
| `HANDOFF_EXTERNAL_GNSS_AND_BLE.md` | External GNSS (cancelled procurement) |

### Backend repo ([tree-project-backend](https://github.com/icmnlab/tree-project-backend))

| Document | Purpose |
|----------|---------|
| [README.md](https://github.com/icmnlab/tree-project-backend/blob/main/README.md) | Backend quick start and architecture diagram |
| [docs/SOURCE_LAYOUT.md](https://github.com/icmnlab/tree-project-backend/blob/main/docs/SOURCE_LAYOUT.md) | Controllers, services, middleware, utils catalog |
| [openapi/openapi.yaml](https://github.com/icmnlab/tree-project-backend/blob/main/openapi/openapi.yaml) | OpenAPI 3.0 spec (Postman / Swagger) |
| [OPENAPI_SCOPE.md](./OPENAPI_SCOPE.md) | What OpenAPI includes; schema deepening policy |
| [openapi/README.md](https://github.com/icmnlab/tree-project-backend/blob/main/openapi/README.md) | How to regenerate and import the spec |
| [tests/FRAMEWORK.md](https://github.com/icmnlab/tree-project-backend/blob/main/tests/FRAMEWORK.md) | Integration test framework |
| [ml_service/README.md](https://github.com/icmnlab/tree-project-backend/blob/main/ml_service/README.md) | Optional ML service |

### Meta

| Document | Purpose |
|----------|---------|
| `DOCUMENTATION_RETENTION.md` | Which docs must stay vs may be archived |
| `DOCUMENTATION_COVERAGE.md` | Honest audit: GitHub files vs documented scope |

## Documentation status (2026-07-01)

Western-style technical docs: one canonical architecture guide plus focused topic and experimental module guides.

| Status | Files |
|--------|-------|
| **Hub & onboarding (2026-07-01)** | `README.md` (this file), `ONBOARDING_READING_PATH.md`, `DEVELOPMENT_WORKFLOW.md` |
| **Canonical (reviewed 2026-06-29)** | `ARCHITECTURE.md`, `CODEBASE_INVENTORY.md`, `API_REFERENCE.md`, `HANDOFF.md`, `LAB_DEPLOYMENT_GUIDE.md`, `BUILD_GUIDE.md`, `HANDOFF_SECRETS_CHECKLIST.md` |
| **Topic guides (reviewed 2026-06-29)** | Domain, BLE, carbon, species, ML — see table above |
| **Operations (reviewed 2026-06-29; VM Phase 4 verified 2026-07-01)** | `FIELD_SURVEY_SOP.md`, `VERIFICATION_CHECKLIST.md`, `HANDOVER_CHECKLIST.md`, `LAB_DEPLOYMENT_GUIDE.md` §Phase 4 |
| **Experimental (reviewed 2026-06-29)** | `EXPERIMENTAL_FEATURES.md`, `VISUAL_MEASUREMENT.md`, `AI_SUSTAINABILITY_REPORT.md`, `AI_AGENT_GUIDE.md` |
| **OpenAPI (2026-06-29)** | `backend/openapi/openapi.yaml` + `openapi/README.md` |
| **Backend catalog (2026-06-29)** | `backend/docs/SOURCE_LAYOUT.md`, `DATABASE_DESIGN.md`, `DATABASE_SCHEMA.md` |
| **Meta (2026-06-29)** | `RESEARCH_REFERENCE.md`, `DOCUMENTATION_COVERAGE.md`, `DOCUMENTATION_RETENTION.md` |

**Lab VM ops with real IPs/passwords**: local-only `project_code/docs/DEPLOYMENT_LOG.md` (not in git). Public runbook: `LAB_DEPLOYMENT_GUIDE.md` (placeholders only).

## Language policy

| Language | Use for | Examples |
|----------|---------|----------|
| **English (canonical in git)** | Architecture, API catalog, CI/workflow, deployment runbooks, module guides | `ARCHITECTURE.md`, `API_REFERENCE.md`, `DEVELOPMENT_WORKFLOW.md`, `LAB_DEPLOYMENT_GUIDE.md` |
| **Chinese (mixed, where helpful)** | Local handover prose, field SOP, audit notes inside `HANDOFF.md` | `HANDOFF.md` §4–§6, `FIELD_SURVEY_SOP.md` |
| **Not maintained** | Full duplicate Chinese translation of every English doc | Avoid — doubles drift risk |

This matches common practice at international product teams with a local field org: **one source of truth in English**, localized only where operators need it.

## Contributing to docs

1. **Code changes** → update `ARCHITECTURE.md` if routes, tables, or flows change.
2. **Domain detail** → update the relevant topic doc; link from `ARCHITECTURE.md` §4.
3. **Secrets / hosts** → use placeholders in git; never commit `.env` values.
4. **Style** → imperative headings, tables for mappings, explain *why* for non-obvious decisions.
