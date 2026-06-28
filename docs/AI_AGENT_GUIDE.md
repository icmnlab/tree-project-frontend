# AI Agent (Field Assistant)

In-app LLM assistant for field Q&A — **Experimental** (hidden by default).

**Last reviewed against code**: 2026-06-29  
**Status**: Experimental — `ENABLE_EXPERIMENTAL_UI=false` hides home card `ai`

---

## Overview

The assistant sends user messages to the backend, which proxies to an OpenAI-compatible API. It is **not** the same feature as the AI sustainability report (`AI_SUSTAINABILITY_REPORT.md`) — different endpoints and UI.

---

## Enabling in builds

```bash
flutter run --dart-define=ENABLE_EXPERIMENTAL_UI=true
```

Card visibility: `lib/config/app_config.dart` → `isDashboardCardVisible('ai')`.

---

## User flow

1. Home → **AI 助理** (when experimental UI on).
2. Chat UI: `lib/screens/ai_chat_page.dart`.
3. Messages → `POST /api/chat` (SSE stream) or `POST /api/ai/direct-chat`.
4. Optional agent mode → `POST /api/agent/chat` (`routes/agent.js`).
5. Min role: 調查管理員 (`requireRole` on routes).

---

## API

See `API_REFERENCE.md` § AI.

| Method | Path | Auth |
|--------|------|------|
| GET | `/api/llm-options` | 調查+ |
| GET | `/api/chat/sessions` | 調查+ |
| POST | `/api/chat` | 調查+ (SSE) |
| POST | `/api/ai/direct-chat` | 調查+ |
| POST | `/api/agent/chat` | 調查+ |

Backend: `backend/routes/ai.js`, `backend/routes/agent.js`

**Secrets**: `OPENAI_API_KEY`, model name in `.env` — never commit.

---

## Code map

| Layer | File |
|-------|------|
| UI | `lib/screens/ai_chat_page.dart` |
| Service | `lib/services/ai_service.dart` |
| Config | `lib/config/app_config.dart` |
| Backend | `backend/routes/ai.js` |

---

## Operational notes

- Rate limiting applies (`rateLimiter.js`).
- No PII should be sent in prompts unless policy allows — audit for production.
- Feature incomplete for v1 handoff — document behavior, not roadmap promises.

---

## Related

- `EXPERIMENTAL_FEATURES.md` — all hidden cards
- `AI_SUSTAINABILITY_REPORT.md` — carbon narrative report
- `SECRETS_AND_ENV.md` — API keys

---

## Distinction

| Feature | Endpoint | Purpose |
|---------|----------|---------|
| AI Agent | `/api/chat`, `/api/agent/*` | Interactive chat |
| AI Report | `/api/reports/ai-sustainability` | Generated sustainability PDF/HTML narrative |
