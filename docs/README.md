# Documentation

Documentation for **Sustainable TreeAI** (`tree-project-frontend` + `tree-project-backend`).

## Start here

| Priority | Document | When to read |
|----------|----------|--------------|
| 1 | **[ARCHITECTURE.md](./ARCHITECTURE.md)** | Onboarding: how the system works, file map, APIs, database in Git |
| 2 | **[HANDOFF.md](./HANDOFF.md)** | Run locally, run tests, find other docs |
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

### Integrations

| Document | Purpose |
|----------|---------|
| `VLGEO2_STD_APPLICATION_GUIDE.md` | VLGEO2 BLE meter |
| `AI_AGENT_GUIDE.md` | AI chat and agent (optional) |
| `ML_CORRECTION_UPLOAD.md` | ML correction data upload |

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

We are migrating to **Western-style technical docs**: one canonical architecture guide (`ARCHITECTURE.md`) plus focused topic docs. Older handover-style files remain in this folder while they are reviewed against the codebase.

| Status | Files |
|--------|-------|
| **Canonical (reviewed)** | `ARCHITECTURE.md`, `HANDOFF.md`, `LAB_DEPLOYMENT_GUIDE.md`, `BUILD_GUIDE.md`, `HANDOFF_SECRETS_CHECKLIST.md` |
| **Topic docs (use with ARCHITECTURE)** | Domain, BLE, carbon, AI, boundary docs listed above |
| **Pending full rewrite** | Will be updated file-by-file after code verification; superseded snapshots kept locally under `project_code/docs/archive/` (not in git) |

Production deployment runbooks derived from real VM operations will be published here after school-side steps (SSH, webhook, Funnel) are completed and verified. Until then, placeholders live in local ops logs only.

## Contributing to docs

1. **Code changes** → update `ARCHITECTURE.md` if routes, tables, or flows change.
2. **Domain detail** → update the relevant topic doc; link from `ARCHITECTURE.md` §4.
3. **Secrets / hosts** → use placeholders in git; never commit `.env` values.
4. **Style** → imperative headings, tables for mappings, explain *why* for non-obvious decisions.
