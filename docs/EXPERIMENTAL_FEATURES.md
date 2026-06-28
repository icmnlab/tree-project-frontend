# Experimental & Hidden Features

Features that **exist in code** but are **hidden from the default production dashboard** or require extra configuration. Document them so future developers can continue work without reverse-engineering the repo.

**Last reviewed against code**: 2026-06-29

---

## Policy (Western practice)

| Situation | Document? | How |
|-----------|-----------|-----|
| Shipped, default-visible | Yes | Module guide + `ARCHITECTURE.md` |
| **Hidden by build flag, code retained** | **Yes** | This file + dedicated module doc with `Status: Experimental` |
| Removed from code | Delete or archive doc | — |
| Research notes only | `docs/*_RESEARCH*.md`, not handover-critical | Mark as Reference |

Stable field workflows (BLE live, pending transfer, map, survey) do **not** depend on experimental features. Missing LLM/ML keys does not break core survey operations.

---

## Dashboard visibility

Source: `lib/config/app_config.dart`

```dart
// Default release APK: false
static const bool enableExperimentalUi = bool.fromEnvironment(
  'ENABLE_EXPERIMENTAL_UI',
  defaultValue: false,
);

static const Set<String> experimentalDashboardCardIds = {
  'test_scan',   // Visual DBH demo (ScannerPage)
  'ai',          // AI chat / agent
  'report',      // AI sustainability report
  'v3',          // V3 calibration / ML sync settings
};
```

| Card ID | UI title | Visible by default? | Module doc |
|---------|----------|---------------------|------------|
| `field_survey` | VLGEO2 現場連線 | Yes | `VLGEO2_STD_APPLICATION_GUIDE.md` |
| `maintenance` | 維護量測 | Yes | `SURVEY_HISTORY.md` |
| `ble` | 藍牙匯入 | Yes | `VLGEO2_STD_APPLICATION_GUIDE.md` |
| `pending` | 待測量任務 | Yes | `SURVEY_HISTORY.md` |
| `survey` | 樹木調查 | Yes | `SURVEY_HISTORY.md` |
| `map` | 樹木地圖 | Yes | `BOUNDARY_SYSTEM_DESIGN.md` |
| `cities` | 區管理 | Yes | `PROJECT_DATA_AND_DOMAIN.md` |
| `stats` | 統計圖表 | Yes | `CARBON_CALCULATION.md` |
| `species` | 樹種辨識 | Yes | `API_REFERENCE.md` § Species |
| **`report`** | 碳匯報告 | **No** | `AI_SUSTAINABILITY_REPORT.md` |
| **`test_scan`** | 掃描測試 Demo | **No** | `VISUAL_MEASUREMENT.md` |
| **`ai`** | AI 助理 | **No** | `AI_AGENT_GUIDE.md` |
| **`v3`** | 系統設定 | **No** | `VISUAL_MEASUREMENT.md` § V3 |

### Enable hidden cards (development build)

```bash
flutter run --dart-define=ENABLE_EXPERIMENTAL_UI=true \
  --dart-define=API_BASE_URL=https://<host>/api
```

---

## Feature summary

| Feature | Backend required? | Env / keys | Status |
|---------|-------------------|------------|--------|
| AI sustainability report | Yes | `OPENAI_API_KEY` or other LLM | Experimental, hidden card |
| AI chat / agent | Yes | LLM keys; optional `GOOGLE_CSE_*` | Experimental, hidden card |
| Visual DBH scan demo | Optional ML | `ML_SERVICE_URL`, `ML_API_KEY`; on-device TFLite | Experimental, hidden card |
| V3 ML sync / calibration | Optional | `ENABLE_ML_CORRECTION_UPLOAD`, ML URL | Experimental, hidden card |
| PlantNet species ID | Yes | `PLANTNET_API_KEY` | **Stable** (card visible) |

---

## Related build flags

| Flag | Default | Purpose |
|------|---------|---------|
| `ENABLE_EXPERIMENTAL_UI` | `false` | Show hidden dashboard cards |
| `ENABLE_ML_CORRECTION_UPLOAD` | `false` | Upload user correction data for ML research |
| `ENABLE_FIELD_LOGS` | `false` | Verbose field logging in release |
| `TREE_ML_SERVICE_URL` | empty | ML service base URL at build time |

---

## Changelog

| Date | Change |
|------|--------|
| 2026-06-29 | Initial catalog of hidden dashboard cards and documentation policy |
