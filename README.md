# Jabran & Co — website, CRM and client portal

Source for **www.jabranandco.com**: the public website of M/S Jabran & Co
(consultancy, global trade & sourcing, customs, plant audits, training), the
internal **CRM**, and the **client portal**.

| | |
|---|---|
| Live | https://www.jabranandco.com (also `jabranandco.com`) |
| Hosting | Vercel — team `jabranandcoprojects`, project `jabran-and-co-website` |
| Backend | Supabase project `dvsaqjvcxqlzgpbvexnu` (Tokyo, Postgres 17): Auth, Postgres + RLS, Storage, Edge Functions |
| Repo | `Syedjabran/jabran-and-co-website` |
| Stack | Plain HTML + CSS + vanilla JavaScript. No framework, no bundler, no build step. |

## Quick start

```bash
git clone https://github.com/Syedjabran/jabran-and-co-website.git
cd jabran-and-co-website
npm run dev        # http://localhost:3000  (static server, no install needed)
npm run check      # quality gate — must pass before every push
```

Node 20+ is the only requirement. There are no npm dependencies.

> **The local site talks to the PRODUCTION database.** There is no staging
> Supabase project yet. Logging in to the CRM locally, submitting the contact
> form or editing records changes real data. Read [AGENTS.md](AGENTS.md) first.

## Repository layout

```
/                         The website. Every *.html at the root is a page, served as-is.
  index.html …            Public site (services, insights, podcast, careers, legal)
  crm*.html               CRM modules (staff only, role-gated)
  my-account.html         Client portal
  *-view.html             Printable documents: invoice, quotation, receipt, report, certificate
  supabase-client.js      Creates the Supabase client `sb`, session-context cache, login gateway
  crm-auth.js             CRM login screen, guard, navigation, sign-out
  crm-*.js                Shared CRM helpers (forms, selects, links, tracking, alerts …)
  style.css, animations.js, images, video
  vercel.json             Security + cache headers
  sitemap.xml, robots.txt

supabase/
  functions/<name>/       Edge Functions — source of truth for what is deployed
  config.toml             Per-function settings (verify_jwt) pinned to production
  proposed/               SQL waiting for owner approval (NOT applied)
  migrations/             SQL that has been applied (from 2026-11-12 onward)

docs/                     Architecture, database, deployment, audit, runbooks
scripts/check.mjs         Quality gate (syntax, links, sitemap, secrets, function config)
.github/                  CI workflow, PR template, CODEOWNERS
```

Files under `supabase/`, `docs/`, `scripts/`, `.github/` and the Markdown
files are **not** published to the website (see `.vercelignore`).

## Documentation

| Read this | For |
|---|---|
| [AGENTS.md](AGENTS.md) | Ground rules for anyone (human or AI) changing this repo |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the system fits together: pages, shared scripts, auth, Supabase, edge functions, third parties |
| [docs/CODEBASE-MAP.md](docs/CODEBASE-MAP.md) | Generated map: which page loads which script and touches which table, RPC, function (`npm run graph`; interactive page: `npm run map` → `docs/codebase-map/index.html`) |
| [docs/DATABASE.md](docs/DATABASE.md) | Schema inventory, security model, how database changes are made |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Branches, commits, pull requests, release flow |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Previews, production, edge functions, rollback |
| [SECURITY.md](SECURITY.md) | Secrets, access, reporting a problem |
| [docs/AUDIT-2026-11-12.md](docs/AUDIT-2026-11-12.md) | Latest engineering audit: findings, fixes, open items |
| [docs/ANALYTICS-SETUP-AND-QA.md](docs/ANALYTICS-SETUP-AND-QA.md) | Analytics connectors setup and manual QA checklist |
| [CHANGELOG.md](CHANGELOG.md) | What changed, release by release |
