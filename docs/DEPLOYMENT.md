# Deployment

There are two independent deploy targets. Changing one never deploys the other.

| What | Where | How it deploys |
|---|---|---|
| Website, CRM, portal (all root files) | Vercel `jabran-and-co-website` (team `jabranandcoprojects`) | **Automatically from GitHub.** `main` → production; any other branch → private preview |
| Edge functions (`supabase/functions/*`) | Supabase `dvsaqjvcxqlzgpbvexnu` | **By hand**, one function at a time, from a merged commit |
| Database (schema, policies, grants) | Supabase `dvsaqjvcxqlzgpbvexnu` | **By hand** in the SQL editor, after owner approval |

## 1 · Website (Vercel)

Vercel serves the repository root as static files — there is no build step
(`framework: null`, no build command). `.vercelignore` keeps docs, backend
source and tooling off the public site. `vercel.json` adds the security and
cache headers.

**Preview.** Every push to a non-`main` branch builds a preview such as
`jabran-and-co-website-git-<branch>-jabranandcoprojects.vercel.app`. Previews
need a Vercel login (SSO protection on all but the custom domains). The link
appears on the pull request and in the Vercel dashboard.

**Production.** Merging into `main` deploys to www.jabranandco.com and
jabranandco.com. Release checklist:

1. `npm run check` passes and CI is green on the PR.
2. The preview was opened and the changed pages checked; public home, contact
   form page, CRM login screen and one CRM module load without console errors.
3. The owner has said yes to this release.
4. Merge. Wait for the production deployment to show **Ready** in Vercel.
5. Smoke test production (read-only — no form submits, no logins needed):
   `curl -sI https://www.jabranandco.com/ https://www.jabranandco.com/crm.html https://www.jabranandco.com/contact.html`
   → all `200`; open the home page and the CRM login screen in a browser.
6. Note the deployment id in CHANGELOG.md.

**Rollback.** Vercel → Deployments → the previous production deployment →
**Instant Rollback** (seconds; no rebuild). Then revert the commit on `main`
so Git matches what is live.

**Caching.** HTML, JS and CSS are sent with `max-age=0, must-revalidate`, so a
release is visible on the next page load. Images/video are cached for 7 days —
give a changed image a new file name.

## 2 · Edge functions (Supabase)

Source of truth is `supabase/functions/<name>/index.ts`; settings are in
`supabase/config.toml`.

```bash
# one-time: log in (opens the browser)
npx supabase@3 login

# deploy ONE function from a clean checkout of the merged commit
git switch main && git pull
npx supabase@3 functions deploy <name> --project-ref dvsaqjvcxqlzgpbvexnu
```

The CLI reads `verify_jwt` from `config.toml`. Before deploying, confirm the
dashboard value matches (Edge Functions → <name> → Details). Webhook/public
functions (`notify-enquiry`, `ai-agent`, `advisory-agent`,
`analytics-oauth-callback`) must stay `verify_jwt = false`.

**Rollback.** Check out the previous commit of that function's folder and
deploy again. (Supabase keeps versions but the dashboard has no one-click
revert.)

**Secrets.** `npx supabase@3 secrets list --project-ref dvsaqjvcxqlzgpbvexnu`
shows names only. Set with `secrets set NAME=value`. Names per function:
`docs/ARCHITECTURE.md` §6.

## 3 · Database

See [DATABASE.md](DATABASE.md) §4. Summary: SQL + rollback in
`supabase/proposed/`, owner approves, run in the SQL editor inside
`begin; … commit;`, run the verification queries in the file, move both files
to `supabase/migrations/`.
