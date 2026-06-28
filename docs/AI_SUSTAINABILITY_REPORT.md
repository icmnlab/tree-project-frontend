# AI Sustainability Report

Generates a narrative **carbon / sustainability report** from live database statistics using an LLM.

| Field | Value |
|-------|-------|
| **Status** | Experimental — dashboard card hidden by default (`report`) |
| **Requires** | LLM API key in backend `.env`; `ENABLE_EXPERIMENTAL_UI=true` to show card |
| **Stable alternative** | `GET /api/sustainability_report` (non-AI export) in `reports.js` |

**Last reviewed against code**: 2026-06-29

---

## Overview

The report combines aggregated tree statistics (counts, carbon totals by area) with an LLM-generated narrative. It is **not** required for field survey or official carbon accounting — those use `handbookCarbonService.js` formulas documented in `CARBON_CALCULATION.md`.

---

## User flow

1. Build with `--dart-define=ENABLE_EXPERIMENTAL_UI=true` (or enable in dev).
2. Home → **碳匯報告** card → `AiSustainabilityReportScreen`.
3. User selects project areas; app loads stats then requests AI narrative.
4. Optional: download PDF via authenticated URL.

---

## API

| Method | Path | Role | Description |
|--------|------|------|-------------|
| GET | `/api/tree_statistics` | project-scoped | Stats input for report UI |
| GET | `/api/reports/ai-sustainability` | 調查管理員+ | JSON report body |
| GET | `/api/reports/ai-sustainability/pdf` | 調查管理員+ | PDF download |

See `API_REFERENCE.md` § AI chat & reports.

---

## Code map

| Layer | File |
|-------|------|
| UI | `lib/screens/ai_sustainability_report_screen.dart` |
| HTTP | `lib/services/api_service.dart` |
| Routes | `backend/routes/ai.js` |
| Controller | `backend/controllers/aiReportController.js` |
| Carbon stats filter | `lifecycle_status = 'active'` (see `CARBON_CALCULATION.md`) |
| LLM | `services/llmProviderService.js` |

Dashboard gating: `AppConfig.experimentalDashboardCardIds` includes `'report'`.

---

## Configuration

Backend `.env` (at least one):

- `OPENAI_API_KEY` (default provider path)
- Or `GEMINI_API_KEY`, `SiliconFlow_API_KEY`, etc.

Without keys: endpoint returns error; **core app still works**.

---

## Testing

- Manual: enable experimental UI, open report screen with valid JWT and LLM key.
- Backend: covered indirectly via `agentDataTools` / report controller paths in integration tests where configured.

---

## Future development notes

- Keep report narrative separate from audited carbon formulas (`carbon_storage` field rules).
- Do not expose pricing / carbon credit market claims (prompt guards in agent/report layer).
- When promoting to stable: remove `'report'` from `experimentalDashboardCardIds` and update `EXPERIMENTAL_FEATURES.md`.
