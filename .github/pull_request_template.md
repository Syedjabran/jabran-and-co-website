## What and why

<!-- One or two sentences. Link the issue / request. -->

## Area

- [ ] Public website
- [ ] CRM
- [ ] Client portal
- [ ] Edge function (`supabase/functions/…`)
- [ ] Database (`supabase/migrations/…` or `supabase/proposed/…`)
- [ ] Docs / tooling only

## Checks

- [ ] `npm run check` passes locally
- [ ] Tested on `npm run dev` (http://localhost:3000) — pages touched still look and behave the same
- [ ] Opened the Vercel **preview** for this branch and spot-checked it
- [ ] No secrets, keys or customer data in the diff
- [ ] If an edge function changed: its `[functions.<name>]` entry in `supabase/config.toml` is correct
- [ ] If the database changed: migration + rollback written, owner approved, applied by hand (see `docs/DATABASE.md`)

## Rollback

<!-- How to undo: Vercel "Instant Rollback" to the previous production deploy, a revert commit, a rollback SQL file, or redeploying the previous function version. -->
