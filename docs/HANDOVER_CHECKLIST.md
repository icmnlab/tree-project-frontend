# Handover Checklist

Sign-off checklist for code, secrets, database, and deployment transfer.

**Last reviewed**: 2026-06-29  
**Target versions**: App `18.10.4+26`; DB migrations ≥ 35

**See also**: `HANDOFF.md`, `HANDOFF_SECRETS_CHECKLIST.md`, `LAB_DEPLOYMENT_GUIDE.md`, `VERIFICATION_CHECKLIST.md`

---

## Attribution (deliverer)

Original development by **KyleliuNDHU**. Copyright and scope: **`AUTHORS.md`** + **`LICENSE`**.

- Recipient GitHub (`icmnlab`) uses a **fresh snapshot** (orphan commit, no full dev history).
- Deliverer retains private `git log` archive locally — not pushed to recipient.
Attribution: **`AUTHORS.md`** + **`LICENSE`**. Deliverer keeps private `git log` archive locally.

Procedure: `LAB_DEPLOYMENT_GUIDE.md` §0.1 or `scripts/prepare_fresh_handover.ps1`.

---

## 0. Snapshot (deliverer fills in)

| Item | Value |
|------|-------|
| Backend repo / commit | __________________________ |
| Frontend repo / commit | __________________________ |
| Backend tests | `node tests/runner.js` → ___ pass / ___ fail (89 cases) |
| Frontend tests | `flutter test` → ___ pass |
| Production URL / deploy method | __________________________ |

---

## 1. Code and documentation (deliverer)

- [ ] `main` latest; CI green (both repos)
- [ ] No uncommitted secrets; `.env` / keystores gitignored
- [ ] Version aligned (`pubspec.yaml`, `CHANGELOG.md`)
- [ ] Docs reviewed: `HANDOFF.md`, `ARCHITECTURE.md`, `VERIFICATION_CHECKLIST.md`, `FIELD_SURVEY_SOP.md`
- [ ] Root contains `LICENSE`, `AUTHORS.md`
- [ ] Fresh snapshot pushed to recipient org; deliverer private history archived
- [ ] **Contribution model documented**: internal team — clone `icmnlab`, feature branch + PR, **protected `main`** (`DEVELOPMENT_WORKFLOW.md`)

---

## 1b. Developer access (recipient org admin)

- [ ] Branch protection on `main` in both repos (require PR + CI; no force push)
- [ ] Each developer: **org member** or **Collaborator (Write)** on both repos
- [ ] First-push exercise: feature branch → push to org → PR → CI → merge (`DEVELOPMENT_WORKFLOW.md`)
- [ ] Fork workflow documented only for **external** contributors without org access

---

## 2. Secrets and accounts

Full detail: **`HANDOFF_SECRETS_CHECKLIST.md`**.

| Item | Owner after handover |
|------|----------------------|
| Source repos | Recipient org |
| Production DB data | Transfer via `pg_dump`; recipient rotates DB password |
| Linux SSH | Recipient creates accounts; deliverer removes own keys |
| Third-party API keys | Recipient creates new; deliverer revokes old |
| `JWT_SECRET`, ML keys, webhook secrets | Recipient generates |
| Google Maps keys | Recipient keys bound to their app signing |
| Android keystore | Transfer securely **or** recipient creates new |
| Admin user | Recipient runs `create_lab_admin.js` |

- [ ] All keys rotated / recreated by recipient
- [ ] No personal hostnames or credentials in git
- [ ] ML env aligned: `ML_SERVICE_URL`, `ML_SERVICE_PUBLIC_URL`, matching `ML_API_KEY` on backend + ml_service

---

## 3. Database

- [ ] Production: `SKIP_CSV_IMPORT=1` or migrations-only path
- [ ] Schema at migration ≥ 35
- [ ] Backup taken before cutover
- [ ] Recipient confirms restore procedure

---

## 4. Deployment (recipient — VM steps may follow school access)

- [ ] Backend PM2 + `/health` OK
- [ ] Nginx / TLS per `LAB_DEPLOYMENT_GUIDE.md`
- [ ] Webhook deploy (when SSH + Funnel ready — see local ops log, not in git)
- [ ] APK built with production `API_BASE_URL`
- [ ] `VERIFICATION_CHECKLIST.md` passed on lab devices

---

## 5. Sign-off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Deliverer | | | |
| Recipient | | | |

---

## Related

- `AUTHORS.md` — copyright and handover terms
- `HANDOFF.md` §11 — open engineering items post-handover
