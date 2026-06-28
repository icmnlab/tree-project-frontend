# Documentation

Documentation for **Sustainable TreeAI** (`tree-project-frontend` + `tree-project-backend`).

**New to the project?** Start with **[ONBOARDING_READING_PATH.md](./ONBOARDING_READING_PATH.md)** — reading order, what to understand vs look up, and how GitHub docs relate to in-person handover.

## Start here

| Priority | Document | When to read |
|----------|----------|--------------|
| 0 | **[ONBOARDING_READING_PATH.md](./ONBOARDING_READING_PATH.md)** | Where to start on GitHub; day-by-day plan |
| 1 | **[ARCHITECTURE.md](./ARCHITECTURE.md)** | Onboarding: how the system works, file map, APIs, database in Git |
| 2 | **[CODEBASE_INVENTORY.md](./CODEBASE_INVENTORY.md)** | Full file/feature catalog (129 Dart, 168 JS, 145 APIs) |
| 3 | **[API_REFERENCE.md](./API_REFERENCE.md)** | All REST endpoints by module |
| 4 | **[DATABASE_SCHEMA.md](./DATABASE_SCHEMA.md)** | Migrations, tables, dev vs production data |
| 5 | **[HANDOFF.md](./HANDOFF.md)** | Run locally, run tests, find other docs |
| 6 | **[HANDOFF_SECRETS_CHECKLIST.md](./HANDOFF_SECRETS_CHECKLIST.md)** | API keys and `.env` setup |
| 7 | **[LAB_DEPLOYMENT_GUIDE.md](./LAB_DEPLOYMENT_GUIDE.md)** | Deploy to a production server |

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

### Backend repo

| Document | Purpose |
|----------|---------|
| `backend/README.md` | Backend quick start and architecture diagram |
| `backend/docs/SOURCE_LAYOUT.md` | Controllers, services, middleware, utils catalog |
| `backend/openapi/openapi.yaml` | OpenAPI 3.0 spec (Postman / Swagger) |
| `backend/openapi/README.md` | How to regenerate and import the spec |
| `backend/tests/FRAMEWORK.md` | Integration test framework |
| `backend/ml_service/README.md` | Optional ML service |

### Meta

| Document | Purpose |
|----------|---------|
| `DOCUMENTATION_RETENTION.md` | Which docs must stay vs may be archived |
| `DOCUMENTATION_COVERAGE.md` | Honest audit: GitHub files vs documented scope |

## Documentation status (2026-06-29)

Western-style technical docs: one canonical architecture guide plus focused topic and experimental module guides.

| Status | Files |
|--------|-------|
| **Canonical (reviewed 2026-06-29)** | `ARCHITECTURE.md`, `CODEBASE_INVENTORY.md`, `API_REFERENCE.md`, `HANDOFF.md`, `LAB_DEPLOYMENT_GUIDE.md`, `BUILD_GUIDE.md`, `HANDOFF_SECRETS_CHECKLIST.md` |
| **Topic guides (reviewed 2026-06-29)** | Domain, BLE, carbon, species, ML — see table above |
| **Operations (reviewed 2026-06-29)** | `FIELD_SURVEY_SOP.md`, `VERIFICATION_CHECKLIST.md`, `HANDOVER_CHECKLIST.md` |
| **Experimental (reviewed 2026-06-29)** | `EXPERIMENTAL_FEATURES.md`, `VISUAL_MEASUREMENT.md`, `AI_SUSTAINABILITY_REPORT.md`, `AI_AGENT_GUIDE.md` |
| **OpenAPI (2026-06-29)** | `backend/openapi/openapi.yaml` + `openapi/README.md` |
| **Backend catalog (2026-06-29)** | `backend/docs/SOURCE_LAYOUT.md`, `DATABASE_SCHEMA.md` |
| **Onboarding (2026-06-29)** | `ONBOARDING_READING_PATH.md`, `LOCAL_DEVELOPER_SETUP.md`, `ANDROID_RELEASE_AND_PLAY_STORE.md` |
| **Meta (2026-06-29)** | `RESEARCH_REFERENCE.md`, `DOCUMENTATION_COVERAGE.md`, `DOCUMENTATION_RETENTION.md` |
| **Research / reference** | DBH research notes, external GNSS — see `RESEARCH_REFERENCE.md` |

Production deployment steps from live VM operations will be merged into `LAB_DEPLOYMENT_GUIDE.md` after school-side SSH/webhook work. Until then, sensitive ops notes stay local-only.

## Contributing to docs

1. **Code changes** → update `ARCHITECTURE.md` if routes, tables, or flows change.
2. **Domain detail** → update the relevant topic doc; link from `ARCHITECTURE.md` §4.
3. **Secrets / hosts** → use placeholders in git; never commit `.env` values.
4. **Style** → imperative headings, tables for mappings, explain *why* for non-obvious decisions.
