# Jabran & Co — guide for AI agents and developers

Read this whole file before changing anything. `CLAUDE.md` points here.

- **Owner:** Syed Jabran Ali Kamran (GitHub `Syedjabran`). Owns the repo, the
  Vercel team `jabranandcoprojects` and the Supabase project, and makes every
  product decision.
- **What this is:** the public website, the CRM and the client portal of
  M/S Jabran & Co — one static site (HTML/CSS/vanilla JS, no build step) on
  Vercel, backed by Supabase. Start with [README.md](README.md) and
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Ground rules

1. **Pushing to `main` puts the site live.** Vercel is connected to GitHub:
   `main` deploys to www.jabranandco.com within a minute; every other branch
   gets a private preview. Never push or merge to `main` without the owner's
   explicit yes for that release. Work on a branch (see
   [CONTRIBUTING.md](CONTRIBUTING.md)).
2. **There is one database and it is production.** Supabase
   `dvsaqjvcxqlzgpbvexnu` holds real clients, invoices, staff and
   enquiries. Previews and `localhost` use it too.
   - Don't create test records. If you must, mark them clearly and delete them.
   - Never run DDL (`create`/`alter`/`drop`/`grant`/`revoke`) or bulk
     `update`/`delete` without the owner's approval. Write the SQL and its
     rollback into `supabase/proposed/` and ask. Once applied, move them to
     `supabase/migrations/` ([docs/DATABASE.md](docs/DATABASE.md)).
   - Read-only inspection (catalog queries, `begin read only; … rollback;`)
     is fine.
3. **Don't change the look, the wording or the behaviour** of the website, the
   CRM or the portal unless that is the task. Bug fixes stay minimal and
   invisible.
4. **Never commit secrets.** The only key allowed in the code is the Supabase
   *publishable* key in `supabase-client.js` (public by design; RLS protects
   the data). Service-role keys, API keys, relay secrets and webhook secrets
   live only in Supabase → Edge Functions → Secrets. `npm run check` scans for
   them.
5. **Edge functions: the repo is the source of truth.** Edit
   `supabase/functions/<name>/index.ts`, commit, then deploy that exact commit
   (see [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)). Never paste code into the
   dashboard editor without committing it — that is how 10 of 12 functions
   ended up outside git before 2026-11-12. Keep `supabase/config.toml` in sync:
   a missing `[functions.<name>]` silently turns `verify_jwt` on and breaks
   webhooks/public endpoints.
6. **Real people get real messages.** `notify-enquiry` emails the CEO on every
   new enquiry; `send-client-email` sends from ceo@jabranandco.com; the AI
   agents answer real visitors. Don't trigger them while testing.
7. **Quality gate.** `npm run check` must pass before every push. CI runs it on
   every branch.

## House style

- Plain ES5/ES2017 JavaScript in classic `<script>` tags; globals are `sb`
  (Supabase client) and `jco` (shared helpers). Don't introduce a framework,
  bundler or module system without the owner's decision.
- Shared code goes in a root `*.js` file included with `<script src>`; page
  logic stays inline in its page.
- Every DB call checks `error`. Escape anything from the database before it
  goes into `innerHTML`.
- Load third-party scripts from cdnjs/jsdelivr with an **exact** version
  (`@supabase/supabase-js@2.119.0`, not `@2`).
- Comments explain *why*. Existing files carry build banners and dated notes —
  keep them.

## Where things are

| Need | Look at |
|---|---|
| Login, session cache, gesture gateway, watermark | `supabase-client.js` |
| CRM guard, login screen, nav, sign-out, client lockout | `crm-auth.js` |
| A CRM module | `crm-<module>.html` (+ helpers it includes) |
| Server logic with secrets | `supabase/functions/<name>/index.ts` |
| Business rules, permissions, totals | Postgres RPCs and triggers (see `docs/DATABASE.md`) |
| Headers / caching | `vercel.json` |
