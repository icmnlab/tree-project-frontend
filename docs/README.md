# Documentation

Documentation for **Sustainable TreeAI** (`tree-project-frontend` + `tree-project-backend`).

## Start here

| Priority | Document | When to read |
|----------|----------|--------------|
| 1 | **[ARCHITECTURE.md](./ARCHITECTURE.md)** | Onboarding: how the system works, file map, APIs, database in Git |
| 2 | **[CODEBASE_INVENTORY.md](./CODEBASE_INVENTORY.md)** | Full file/feature catalog (129 Dart, 168 JS, 145 APIs) — use so nothing is missed |
| 3 | **[API_REFERENCE.md](./API_REFERENCE.md)** | All REST endpoints by module |
| 4 | **[HANDOFF.md](./HANDOFF.md)** | Run locally, run tests, find other docs |
| 3 | **[HANDOFF_SECRETS_CHECKLIST.md](./HANDOFF_SECRETS_CHECKLIST.md)** | API keys and `.env` setup |
| 4 | **[LAB_DEPLOYMENT_GUIDE.md](./LAB_DEPLOYMENT_GUIDE.md)** | Deploy to a production server |

## By topic

### Operations

| Document | Purpose |
|----------|---------|
| `LAB_DEPLOYMENT_GUIDE.md` | Server provisioning, PM2, nginx, TLS |
| `BUILD_GUIDE.md` | Android APK build |
| `VERIFICATION_CHECKLIST.md` | Post-deploy smoke tests |
| `HANDOVER_CHECKLIST.md` | Handover day tasks |
| `FIELD_SURVEY_SOP.md` | Field survey procedures (BLE + manual) |

### Domain & data model

| Document | Purpose |
|----------|---------|
| `PROJECT_DATA_AND_DOMAIN.md` | Project / area terminology, CSV semantics |
| `SURVEY_HISTORY.md` | Snapshot vs measurement history tables |
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

### Research (reference)

| Document | Purpose |
|----------|---------|
| `DBH_MEASUREMENT_RESEARCH_V2.md` | DBH measurement research notes |
| `DBH_PURE_VISION_RESEARCH.md` | Vision-only DBH research |
| `HANDOFF_EXTERNAL_GNSS_AND_BLE.md` | External GNSS (cancelled procurement) |

### Backend repo

| Document | Purpose |
|----------|---------|
| `backend/README.md` | Backend quick start and architecture diagram |
| `backend/tests/FRAMEWORK.md` | Integration test framework |
| `backend/ml_service/README.md` | Optional ML service |

## Documentation status (2026-06-29)

Western-style technical docs: one canonical architecture guide plus focused topic and experimental module guides.

| Status | Files |
|--------|-------|
| **Canonical (reviewed)** | `ARCHITECTURE.md`, `CODEBASE_INVENTORY.md`, `API_REFERENCE.md`, `HANDOFF.md`, `LAB_DEPLOYMENT_GUIDE.md`, `BUILD_GUIDE.md`, `HANDOFF_SECRETS_CHECKLIST.md` |
| **Topic guides (reviewed 2026-06-29)** | Domain, BLE, carbon, species, ML — see table above |
| **Operations (reviewed 2026-06-29)** | `FIELD_SURVEY_SOP.md`, `VERIFICATION_CHECKLIST.md`, `HANDOVER_CHECKLIST.md` |
| **Experimental (reviewed 2026-06-29)** | `EXPERIMENTAL_FEATURES.md`, `VISUAL_MEASUREMENT.md`, `AI_SUSTAINABILITY_REPORT.md`, `AI_AGENT_GUIDE.md` |
| **Research / reference** | DBH research notes, external GNSS handoff — not production paths |

Production deployment runbooks derived from real VM operations will be published here after school-side steps (SSH, webhook, Funnel) are completed and verified. Until then, placeholders live in local ops logs only.

## Contributing to docs

1. **Code changes** → update `ARCHITECTURE.md` if routes, tables, or flows change.
2. **Domain detail** → update the relevant topic doc; link from `ARCHITECTURE.md` §4.
3. **Secrets / hosts** → use placeholders in git; never commit `.env` values.
4. **Style** → imperative headings, tables for mappings, explain *why* for non-obvious decisions.
