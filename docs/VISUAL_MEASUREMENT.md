# Visual Measurement & ML

On-device and server-assisted **DBH (diameter at breast height)** measurement paths. Distinct from **VLGEO2 BLE** field workflow.

| Field | Value |
|-------|-------|
| **Status** | Mixed — scanner demo **experimental/hidden**; ML proxy **optional** |
| **Dashboard** | `test_scan` hidden unless `ENABLE_EXPERIMENTAL_UI=true` |
| **V3 settings** | `v3` card hidden; ML sync/calibration in `v3_services_page.dart` |

**Last reviewed against code**: 2026-06-29

---

## Overview

Three measurement sources in the product:

| Source | Accuracy use | Network |
|--------|--------------|---------|
| VLGEO2 BLE | Primary field | BLE + API for upload |
| Manual / form entry | Primary field | API |
| Camera / ML | Demo & research | Optional ML service |

---

## 1. Scanner demo (`ScannerPage`)

**Card**: `test_scan` — **hidden by default**.

| Layer | File |
|-------|------|
| UI | `lib/screens/scanner_page.dart` |
| On-device pipeline | `lib/services/pure_vision_dbh_service.dart`, `tflite_tracking_service.dart` |
| AR helper | `lib/services/ar_measurement_service.dart`, `dbh_measurement_engine.dart` |

Uses local TFLite model (`assets/ml/tree_trunk_seg.tflite`) for trunk segmentation demo. Returns `MeasurementResult` to caller — useful for UX experiments, not the main production survey path.

**Enable**: `--dart-define=ENABLE_EXPERIMENTAL_UI=true`

---

## 2. ML service proxy (server)

Optional FastAPI service in `backend/ml_service/`. Backend proxies requests — App does not call Python directly except via configured URL.

| Layer | File |
|-------|------|
| Proxy routes | `backend/routes/ml_service.js` |
| Python app | `backend/ml_service/app.py` |
| Frontend URL | `AppConfig.mlServiceUrl` (from login response or `TREE_ML_SERVICE_URL`) |

API: `/api/ml-service/measure-dbh`, `/auto-measure-dbh`, etc. — see `API_REFERENCE.md`.

**Configuration**:

```bash
# backend/.env
ML_SERVICE_URL=http://127.0.0.1:8100
ML_SERVICE_PUBLIC_URL=https://<ml-host>
ML_API_KEY=<shared-secret>   # same in ml_service/.env
```

---

## 3. V3 services page (hidden)

**Card**: `v3` → `lib/screens/v3_services_page.dart`

Calibration, ML data sync, conflict resolution — ties to:

- `lib/services/v3/ml_data_sync_service.dart`
- `lib/services/v3/ml_data_collector.dart`
- `backend/routes/ml_training_data.js`

Research / correction upload gated by `ENABLE_ML_CORRECTION_UPLOAD` (default false). See `ML_CORRECTION_UPLOAD.md` for upload semantics.

---

## 4. Research dataset (admin)

Admin collection of tape-measured DBH + photos for model training:

- API: `/api/admin/research-dataset/*`
- UI: `lib/admin_research_dataset_page.dart`

Separate from production survey records.

---

## Testing

| Area | Tests |
|------|-------|
| Pure vision math | `frontend/test/` (where present) |
| ML proxy | `backend/tests/` + `ml_service/tests/` |
| BLE (not visual) | `VLGEO2` guides + BLE unit tests |

---

## Related docs

- `EXPERIMENTAL_FEATURES.md` — visibility flags
- `ML_CORRECTION_UPLOAD.md` — correction upload flag
- `DBH_MEASUREMENT_RESEARCH_V2.md` — research notes (reference)
- `backend/ml_service/README.md` — deploy ML host

---

## Changelog

| Date | Change |
|------|--------|
| 2026-06-29 | Initial module guide; experimental vs optional ML clarified |
