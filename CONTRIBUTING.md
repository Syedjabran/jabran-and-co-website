# Contributing

## Branches

| Branch | Purpose | Deploys to |
|---|---|---|
| `main` | **Production.** Always what is live on www.jabranandco.com. Protected: changes arrive only by reviewed pull request. | Production (automatic on merge) |
| `develop` | Integration / staging. Finished work is merged here first and checked together. | Stable preview: `jabran-and-co-website-git-develop-jabranandcoprojects.vercel.app` |
| `jabran/<topic>` | The owner's work (and work done by the owner's AI agent). | Private preview per push |
| `feature/<topic>` | New capability by anyone else. | Private preview per push |
| `fix/<topic>` | Non-urgent bug fix. | Private preview per push |
| `hotfix/<topic>` | Urgent production fix, branched from `main`. | Private preview per push |

Previews are protected by Vercel login and are **not** a sandbox: they use the
production database (see [AGENTS.md](AGENTS.md) rule 2).

### Normal flow

```
git switch develop && git pull
git switch -c jabran/quotation-print-fix
# … work, npm run check, test on npm run dev …
git push -u origin jabran/quotation-print-fix
# open PR → develop. Check the Vercel preview link on the PR.
# when a release is ready: PR develop → main, owner approves, merge = live.
```

### Hotfix flow

```
git switch main && git pull
git switch -c hotfix/login-button
# fix, check, push, PR → main (owner approves) → live
# then: PR main → develop so develop doesn't lose the fix
```

## Commits

Short imperative subject (≤ 72 chars), optional scope, body says *why*:

```
crm-quotations: keep discount when currency changes

The currency switch rebuilt the line items from the template and dropped the
manual discount. Re-apply it after the rebuild.
```

Scopes in use: `site`, `crm`, `portal`, `crm-<module>`, `fn:<function>`,
`db`, `docs`, `ci`, `chore`.

## Pull requests

- One topic per PR. The template asks what changed, the area, the checks and
  how to roll back.
- `npm run check` must pass (CI runs it).
- Database changes: the PR adds the SQL + rollback in `supabase/proposed/`;
  the owner applies it; a follow-up commit moves both into
  `supabase/migrations/` with the date applied.
- Edge-function changes: deploy only after the PR is merged, from the merged
  commit ([docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)).

## GitHub settings to switch on (owner, once)

Settings → Branches → Add rule for `main`:
- Require a pull request before merging (1 approval)
- Require status checks: **CI / Quality gate**
- Do not allow force pushes or deletions

Same for `develop`, without the approval requirement.
