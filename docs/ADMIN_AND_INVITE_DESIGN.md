# Admin, Invites & RBAC

User administration, invite-based registration, and role-based access control.

**Last reviewed against code**: 2026-06-29

---

## Overview

Five roles (high → low): 系統管理員 → 業務管理員 → 專案管理員 → 調查管理員 → 一般使用者. Backend enforces roles via `middleware/requireRole.js` and project scope via `middleware/projectAuth.js`. Frontend mirrors visibility in `lib/models/role_permissions.dart`.

---

## User flow

| Task | UI | Min role |
|------|-----|----------|
| Login | `login_page.dart` | — |
| Register with invite | `register_page.dart` | public + valid invite |
| Manage users | `admin_page.dart` → `user_form_screen.dart` | 業務管理員 |
| Manage invites | `invite_management_page.dart` | 業務管理員 |
| Audit log | `audit_log_page.dart` | 業務管理員 |
| IP blacklist | `ip_blacklist_page.dart` | 系統管理員 |
| Password resets queue | `pending_password_resets_page.dart` | 業務管理員 |

**Login field**: use **`username`**, not display name (`POST /api/login` body `{ account, password }`).

---

## Invite codes

| Rule | Implementation |
|------|----------------|
| Created by | 業務管理員 or higher |
| Role on invite | Cannot exceed creator's role |
| Project scope | `project_codes[]` → `user_projects` on register |
| Default uses | `max_uses=1` |
| Expiry | `expires_in_days` (1–90) |
| Approval | `requires_approval=true` → `is_active=false` until admin enables |

### API

| Method | Path | Role |
|--------|------|------|
| GET | `/api/invites` | 業務+ |
| POST | `/api/invites` | 業務+ |
| PATCH | `/api/invites/:id/deactivate` | 業務+ |
| DELETE | `/api/invites/:id` | 業務+ |
| POST | `/api/register` | public |

Full list: `API_REFERENCE.md` § Authentication.

---

## User management API

| Method | Path | Role |
|--------|------|------|
| GET/POST | `/api/users` | 業務+ |
| PUT | `/api/users/:id` | 業務+ |
| PUT | `/api/users/:id/status` | 業務+ |
| DELETE | `/api/users/:id` | 業務+ |
| GET/PUT | `/api/users/:userId/projects` | 業務+ |

---

## Code map

| Layer | File |
|-------|------|
| Routes | `backend/routes/users.js` |
| JWT | `backend/middleware/jwtAuth.js` |
| Roles | `backend/middleware/roleAuth.js` |
| Project filter | `backend/middleware/projectAuth.js` |
| Login lockout | `backend/middleware/loginAttemptMonitor.js` |
| IP guard | `backend/middleware/ipBlacklistGuard.js` |
| Audit | `backend/services/auditLogService.js` |
| Frontend auth | `lib/services/auth_service.dart` |
| Frontend invites | `lib/services/invite_service.dart` |
| RBAC UI model | `lib/models/role_permissions.dart` |

Production admin creation: `node scripts/create_lab_admin.js` (not SQL seed). Dev only: `seed_dev_users.js`.

---

## Data model

| Table | Purpose |
|-------|---------|
| `users` | Accounts, `role`, `is_active`, lockout fields |
| `invites` | Codes, role, project_codes, expiry, uses |
| `user_projects` | `(user_id, project_code)` scope |
| `audit_logs` | LOGIN_*, admin actions |
| `ip_blacklist` | Brute-force IP blocks |

---

## Configuration

- `JWT_SECRET` — token signing (required)
- Rate limits — `middleware/rateLimiter.js`; `BURST_LIMIT_MAX` in `.env`

---

## Testing

- `backend/tests/invariants/` — RBAC isolation, login contracts
- Frontend role UI — `test/` widget tests where present

---

## Related

- `API_REFERENCE.md` § Admin
- `SURVEY_HISTORY.md` — field session vs audit (separate concepts)
