# OpenAPI Scope & Schema Policy

What our OpenAPI spec contains today, what **“schema deepening”** would mean, and why we intentionally keep it shallow for this handover.

**Last reviewed**: 2026-06-29  
**Spec**: `backend/openapi/openapi.yaml`  
**Generator**: `backend/scripts/generate_openapi.js`  
**Human catalog**: [`API_REFERENCE.md`](./API_REFERENCE.md)

---

## What we have today

| Layer | Covered? | Source |
|-------|----------|--------|
| Paths + HTTP methods | Yes | Auto-generated from `routes/*.js` |
| Path parameters (`{id}`) | Yes | From Express route strings |
| `bearerAuth` security scheme | Yes | Default on `/api/*` |
| Public routes (`/health`, webhooks) | Yes | Marked `security: []` |
| **Request body JSON schemas** | **No** | Not inferred by generator |
| **Response JSON schemas** | **No** | Only stub `ErrorResponse` |
| Per-endpoint RBAC roles | **No** | Documented in `API_REFERENCE.md` + code |
| SSE streaming (`POST /api/chat`) | **No** | JSON responses only in practice |

**146 operations** listed — sufficient for Postman import, smoke testing, and “what exists?” discovery.

Regenerate after route changes:

```bash
cd tree-project-backend
node scripts/generate_openapi.js
```

---

## What is “OpenAPI schema deepening”?

In OpenAPI 3, a **schema** describes the shape of JSON: field names, types, required fields, enums, nested objects.

**Shallow spec (current)**:

```yaml
post:
  summary: Create tree v2
  # no requestBody schema — reader must read controller or API_REFERENCE
```

**Deepened spec (optional future work)**:

```yaml
post:
  requestBody:
    content:
      application/json:
        schema:
          $ref: '#/components/schemas/TreeSurveyCreateV2'
  responses:
    '201':
      content:
        application/json:
          schema:
            $ref: '#/components/schemas/TreeSurveyRow'
```

**Schema deepening** = adding `components/schemas` for major DTOs (`TreeSurvey`, `PendingBatch`, `LoginRequest`, …) and wiring them to each operation.

### What it enables

- Postman / Swagger UI **example bodies** and validation
- Client code generation (TypeScript, Dart) from one spec
- Contract tests that validate response shape against schema

### What it costs

- Maintenance: every API field change needs spec + code + often `API_REFERENCE.md`
- Generator complexity: Express has no types — schemas are hand-written or need JSDoc/TypeScript migration
- RBAC and business rules still live in code — OpenAPI cannot replace `requireRole` docs

---

## Decision for this project (Western handover standard)

| Choice | Rationale |
|--------|-----------|
| **Keep shallow OpenAPI** | Handover team is same org maintaining Flutter + Node; human `API_REFERENCE.md` + **89 backend contract tests** are the source of truth |
| **Do not block handover on full schemas** | Google/Amazon internal APIs often ship “catalog-only” OpenAPI first; deep schemas added when external consumers or codegen appear |
| **Regenerate paths on every route PR** | Cheap, prevents drift |
| **Deepen selectively later** | When a **new external client** (third-party integrator, public API) needs codegen |

This is **documented scope**, not a gap we forgot.

---

## If you deepen later (playbook)

1. Pick high-traffic modules first: `login`, `tree_survey/create_v2`, `pending-measurements/transfer`
2. Add `components/schemas` in `openapi.yaml` or extend `generate_openapi.js` with a `schemas/` JSON folder
3. Mirror changes in `API_REFERENCE.md`
4. Optional: Spectral lint rule — “POST must have requestBody”

Do **not** duplicate secrets, internal admin tokens, or webhook HMAC details in schemas.

---

## Related

| Topic | Document |
|-------|----------|
| Endpoint list + roles | `API_REFERENCE.md` |
| Regenerate + Postman | `backend/openapi/README.md` |
| Contract tests | `backend/tests/FRAMEWORK.md`, `tests/contracts/` |
