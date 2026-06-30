# Research & Experimental Documentation

Documents that describe **research, cancelled scope, or in-progress features** — not production operator runbooks.

**Last reviewed**: 2026-06-29

---

## What are "research files"?

In this repo, **research tier** docs capture:

- Thesis / experiment planning (DBH vision accuracy, model comparisons)
- Cancelled procurement decisions (external GNSS)
- Historical design iterations superseded by current code

They are **kept in git** so future developers understand *why* certain paths were chosen or abandoned. They are **not** the first place to read for deploying or operating the system.

**Western practice**: label as `Research` or `Archived` in the doc hub (`docs/README.md`); production docs link to `VISUAL_MEASUREMENT.md` or `ml_service/README.md` instead.

---

## Research tier index

| Document | Status | Read this for |
|----------|--------|---------------|
| [`DBH_MEASUREMENT_RESEARCH_V2.md`](./DBH_MEASUREMENT_RESEARCH_V2.md) | Research archive (2026-02) | DA3 + YOLO roadmap; **production** → `VISUAL_MEASUREMENT.md`, `backend/ml_service/README.md` |
| [`DBH_PURE_VISION_RESEARCH.md`](./DBH_PURE_VISION_RESEARCH.md) | Research archive (V1, 2025-07) | Early mobile-only vision DBH notes |
| [`HANDOFF_EXTERNAL_GNSS_AND_BLE.md`](./HANDOFF_EXTERNAL_GNSS_AND_BLE.md) | Cancelled scope | Why external GNSS was not procured; phone GPS is canonical |
| [`ML_CORRECTION_UPLOAD.md`](./ML_CORRECTION_UPLOAD.md) | Optional feature (off by default) | Background ML correction upload flag |
| [`test/vlgeo2_ble_analysis/README.md`](../test/vlgeo2_ble_analysis/README.md) | Dev analysis scripts | BLE packet research; not production |

---

## Experimental tier (code exists, UI hidden by default)

| Document | Build flag |
|----------|------------|
| [`EXPERIMENTAL_FEATURES.md`](./EXPERIMENTAL_FEATURES.md) | `ENABLE_EXPERIMENTAL_UI` |
| [`VISUAL_MEASUREMENT.md`](./VISUAL_MEASUREMENT.md) | Scanner, ML sync |
| [`AI_SUSTAINABILITY_REPORT.md`](./AI_SUSTAINABILITY_REPORT.md) | Home card `report` |
| [`AI_AGENT_GUIDE.md`](./AI_AGENT_GUIDE.md) | Home card `ai` |

---

## Production tier (start here)

| Audience | Entry |
|----------|-------|
| Developers | [`ARCHITECTURE.md`](./ARCHITECTURE.md) → [`HANDOFF.md`](./HANDOFF.md) |
| API consumers | [`API_REFERENCE.md`](./API_REFERENCE.md) · [openapi.yaml](https://github.com/icmnlab/tree-project-backend/blob/main/openapi/openapi.yaml) |
| DBAs / backend | [`DATABASE_SCHEMA.md`](./DATABASE_SCHEMA.md) |
| Backend layers | [SOURCE_LAYOUT.md](https://github.com/icmnlab/tree-project-backend/blob/main/docs/SOURCE_LAYOUT.md) |
| Field crews | [`FIELD_SURVEY_SOP.md`](./FIELD_SURVEY_SOP.md) |
| Deploy | [`LAB_DEPLOYMENT_GUIDE.md`](./LAB_DEPLOYMENT_GUIDE.md) |

---

## Can research files be deleted?

**Optional.** Prefer:

1. Keep in git with clear **Research** label (current approach), or
2. Move to local `project_code/docs/archive/` and add a one-line pointer in this file

Do **not** delete without updating links in `HANDOFF.md` §12 and `VISUAL_MEASUREMENT.md`.

See [`DOCUMENTATION_RETENTION.md`](./DOCUMENTATION_RETENTION.md).

---

## Related

- [`DOCUMENTATION_COVERAGE.md`](./DOCUMENTATION_COVERAGE.md) — what is documented vs code-only
- [`CODEBASE_INVENTORY.md`](./CODEBASE_INVENTORY.md) — file counts
