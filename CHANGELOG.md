# Changelog

Production deployments of www.jabranandco.com. Newest first.
Rollback any release with Vercel → Deployments → the previous one → Instant Rollback.

## Unreleased — `jabran/backend-hardening`

Engineering foundation and reliability release. No change to the look,
wording or features of the website, CRM or portal, and no database change.
Full detail: [docs/AUDIT-2026-11-12.md](docs/AUDIT-2026-11-12.md).

**Added**
- `crm-financial-settings.html` — the Financial Settings module the CRM menu
  already linked to (subscriptions, fixed expenses, cost categories, change
  history), built on existing tables and permissions.
- All 12 Supabase Edge Functions under version control (`supabase/functions/`),
  with `supabase/config.toml` pinning each function's `verify_jwt`.
- Quality gate `npm run check` and GitHub Actions CI.
- Codebase map: `npm run graph` → `docs/CODEBASE-MAP.md`, `docs/codebase-graph.json`.
- Documentation: README, AGENTS, CONTRIBUTING (branch model), SECURITY,
  docs/ARCHITECTURE, DATABASE, DEPLOYMENT, AUDIT; PR template, CODEOWNERS.
- `supabase/proposed/20261112_001_close_public_data_exposure.sql` (+ rollback)
  — **not applied**, waiting for approval.

**Changed**
- supabase-js pinned to 2.119.0 on every page (was the floating `@2`).
- Edge function source and internal docs no longer published on the website
  (`.vercelignore`); `ANALYTICS-SETUP-AND-QA.md` moved to `docs/`.

**Fixed** — 30 front-end defects, among them: login form staying visible
after sign-in; employee save removing roles; lockouts from Enter presses;
duplicate records from double-clicks; links blanked when editing records with
inactive references; allowance edits hitting the wrong row; phone numbers
rewritten with the wrong country code; one network blip ejecting staff; 404
page styling; canonical URLs.

## 2026-11-03 — `655ff86` (`dpl_AQNnYekryRCKmKS374ELKwNAkHC3`)

CRM email: multiple Cc/Bcc and attachments (device upload + `crm-private` documents).
