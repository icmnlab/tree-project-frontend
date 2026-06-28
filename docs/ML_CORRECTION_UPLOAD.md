# ML Correction Upload (Optional)

Background upload of user corrections when auto-suggested DBH, species, or carbon values are overridden.

**Last reviewed against code**: 2026-06-29  
**Status**: **Disabled by default** — not required for production surveys

---

## Overview

When enabled, the V3 ML data collector records diffs between auto-computed and user-entered values and batches them to the backend for model improvement research.

This is **separate** from the admin **research dataset** flow (tape-measure circumference + distance + photos). Prefer research dataset for clean DBH calibration data.

---

## Two training-data mechanisms

| Mechanism | Purpose | Default |
|-----------|---------|---------|
| Research dataset (admin) | Tape measure + distance + photo for DBH α,β calibration | Admin-only, on demand |
| ML correction upload | Background diffs when user overrides auto values | **Off** |

Research dataset: `routes/research_dataset.js`, `admin_research_dataset_page.dart`.  
See `VISUAL_MEASUREMENT.md` § Research dataset.

---

## Enabling

```bash
flutter run --dart-define=ENABLE_ML_CORRECTION_UPLOAD=true
```

Build flag: `lib/config/app_config.dart` → `enableMlCorrectionUpload`.

When on:

- V3 services page shows **修正紀錄上傳** card (`v3_services_page.dart`)
- Collector: `lib/services/v3/ml_data_collector.dart`
- Upload interval: ~30 minutes to `POST /api/ml-training/batch`

---

## User flow

1. User edits auto DBH / species / carbon in V3-integrated forms.
2. `MLDataCollector` records `{ auto_values, user_values, difference, context }`.
3. Periodic batch upload → backend stores in `ml_training_batches` / `ml_training_records`.
4. Admin export: routes under `ml_training_data.js` (≥業務管理員).

---

## API

Mount: `/api/ml-training` · `routes/ml_training_data.js`

| Method | Path | Role |
|--------|------|------|
| POST | `/api/ml-training/batch` | Device batch upload |
| POST | `/api/ml-training/image` | Optional image attachment |

See `API_REFERENCE.md` § ML training data.

---

## Code map

| Layer | File |
|-------|------|
| Flag | `lib/config/app_config.dart` |
| Collector | `lib/services/v3/ml_data_collector.dart` |
| Upload service | `lib/services/v3/ml_data_sync_service.dart` |
| UI | `lib/screens/v3/v3_services_page.dart` |
| Backend | `backend/routes/ml_training_data.js` |

Record types include `carbonCalculation`, DBH correction, species correction (see route `chk_record_type` constraint).

---

## Data model

| Table | Purpose |
|-------|---------|
| `ml_training_batches` | Upload batch metadata |
| `ml_training_records` | Individual correction rows (JSONB diffs) |

Tables created on first use via route initializer.

---

## Operational notes

- **Do not enable** for routine port surveys — adds background traffic and stores field edits.
- For DBH research, use **research dataset** instead of correction upload.
- Gated by same experimental-adjacent build flags as V3; home card `v3` hidden unless `ENABLE_EXPERIMENTAL_UI=true`, but correction flag is independent.

---

## Related

- `EXPERIMENTAL_FEATURES.md` — V3 card visibility
- `VISUAL_MEASUREMENT.md` — ML pipeline overview
- `backend/ml_service/README.md` — inference service (separate from correction upload)
