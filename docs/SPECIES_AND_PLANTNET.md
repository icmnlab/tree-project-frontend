# Species Catalog & PlantNet Identification

Master species data, survey autocomplete, and photo-based identification.

**Last reviewed against code**: 2026-06-29  
**Status**: Stable — home card `species` visible by default (not gated by `ENABLE_EXPERIMENTAL_UI`)

---

## Overview

Two related systems:

1. **Catalog** — `tree_species` master table in PostgreSQL; forms use `/api/tree_species/*` for search and create.
2. **PlantNet identification** — user photo → external API → optional GBIF/iNaturalist enrichment → user picks result → may add to catalog.

Survey trees store **`species_name`** on `tree_survey` (denormalized display); catalog is source of truth for coefficients used in carbon calculation.

---

## User flow

| Task | Screen | API |
|------|--------|-----|
| Identify from photo | `species_identification_page.dart` | `POST /api/species/identify` |
| Search external names | same page | `GET /api/species/search` |
| Pick species in survey form | integrated / manual forms | `GET /api/tree_species/search` or `/enhanced` |
| Add new species to catalog | admin / form flow | `POST /api/tree_species` |
| Frequent species for project | form helpers | `GET /api/tree_survey/common_species/:projectCode` |

---

## PlantNet identify flow

```
Photo (multipart image)
  → POST /api/species/identify { organ, lang }
  → speciesIdentificationService.identifySpecies()
  → PlantNet API (PLANTNET_API_KEY)
  → optional GBIF enrich
  → JSON { primaryResult, alternatives, ... }
  → user confirms → tree_survey.species_name or POST tree_species
```

| Field | Values |
|-------|--------|
| `organ` | `leaf`, `flower`, `fruit`, `bark`, `auto` (default) |
| `lang` | `zh`, `en` (default `zh`) |
| Max upload | 10 MB, image/* only |

---

## API

See `API_REFERENCE.md` § Tree species & statuses, § Species identification.

### Catalog (`routes/treeSpecies.js`)

| Method | Path | Role |
|--------|------|------|
| GET/POST | `/api/tree_species` | JWT / 調查+ |
| GET | `/api/tree_species/search`, `/enhanced`, `/next_number` | JWT |
| GET/POST | `/api/tree_species/synonyms/report`, `/synonyms/merge` | 調查+ / 系統管理員 |

### Identification (`routes/speciesIdentification.js`)

| Method | Path | Role |
|--------|------|------|
| POST | `/api/species/identify` | JWT |
| GET | `/api/species/search` | JWT (iNaturalist) |
| GET | `/api/species/gbif/:name` | JWT |
| GET | `/api/species/inaturalist/:id` | JWT |
| GET | `/api/species/status` | JWT |

---

## Code map

| Layer | File |
|-------|------|
| Identify routes | `backend/routes/speciesIdentification.js` |
| Identify service | `backend/services/speciesIdentificationService.js` |
| Catalog routes | `backend/routes/treeSpecies.js` |
| SQL seed | `backend/database/initial_data/tree_species.pg.sql`, `species_synonyms.pg.sql` |
| Frontend identify UI | `lib/screens/species_identification_page.dart` |
| Frontend identify API | `lib/services/species_identification_service.dart` |
| Frontend catalog | `lib/services/species_service.dart` |

---

## Data model

| Table | Purpose |
|-------|---------|
| `tree_species` | Master list; carbon-related columns |
| `species_synonyms` | Alias merge support |
| `tree_survey.species_name` | Snapshot on each tree |

PlantNet may suggest names not yet in catalog — `POST /api/tree_species` adds them when authorized.

---

## Configuration

| Env var | Purpose |
|---------|---------|
| `PLANTNET_API_KEY` | Required for `/species/identify` in production |
| GBIF / iNaturalist | Public APIs; rate limits apply |

See `HANDOFF_SECRETS_CHECKLIST.md`.

---

## Testing

- Manual: upload leaf photo on device with network
- Backend: species route tests in `backend/tests/` where present
- Without API key: `/species/status` reports unavailable; identify returns error

---

## Related

- `CARBON_CALCULATION.md` — species drives allometric lookup
- `PROJECT_DATA_AND_DOMAIN.md` — catalog vs survey data
- `EXPERIMENTAL_FEATURES.md` — `species` card is **not** experimental
