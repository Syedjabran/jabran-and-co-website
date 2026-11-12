# Changelog

Production deployments of www.jabranandco.com. Newest first.
Rollback any release with Vercel → Deployments → the previous one → Instant Rollback.

## 2026-11-12 — `8a8196b` (`dpl_8RjmYGSeN8KqxYhJ7nFVZVreVhVu`) — backend hardening

Rollback target: `dpl_AQNnYekryRCKmKS374ELKwNAkHC3` (`655ff86`). Live smoke test
passed (pages 200, backend source and docs 404, no console errors).

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
- Migrations with rollbacks under `supabase/migrations/`.

**Database / backend (applied 2026-11-12, owner-approved)**
- Migration `20261112191851`: closed anonymous read of 5 views and EXECUTE on 5 unguarded helpers.
- Migration `20261112191938`: `ai_public_rate_events` table.
- Migration `20261112193236`: fixed `search_path` on 8 functions (advisor warning).
- Schema baseline (catalog reconstruction) in `supabase/schema/baseline/`.
- `advisory-agent` v25: server-side rate limit + website-chat lead capture.
- `ai-agent` / `ai-client-agent` switched off (`ai_agent_configs.is_enabled = false`).
- Claude connected (2026-11-12 21:40 UTC, commit `4537bb8`): `advisory-agent` v27, `ai-accountant` v30,
  `analytics-agent` v25 deployed with the Supabase CLI; `ANTHROPIC_API_KEY` set by the owner; live test answered
  by `claude-haiku-5-5`. Gemini remains the automatic fallback if the key is removed.

**Changed**
- supabase-js pinned to 2.119.0 on every page (was the floating `@2`).
- Edge function source and internal docs no longer published on the website
  (`.vercelignore`); `ANALYTICS-SETUP-AND-QA.md` moved to `docs/`.

**Fixed** — 30 front-end defects, among them: login form staying visible
after sign-in; employee save removing roles; lockouts from Enter presses;
duplicate records from double-clicks; links blanked when editing records with
inactive references; allowance edits hitting the wrong row; phone numbers
rewritten with the wrong country code; one network blip ejecting staff; 404
page styling; canonical URLs. Second batch: new-tab logout (shared session
cookie, local-scope sign-out), idle timeout shared across tabs, owner-only
menu links, per-currency totals, Pakistan-time business dates, iOS receipt view.

## 2026-11-03 — `655ff86` (`dpl_AQNnYekryRCKmKS374ELKwNAkHC3`)

CRM email: multiple Cc/Bcc and attachments (device upload + `crm-private` documents).
