# Database

Supabase project **`dvsaqjvcxqlzgpbvexnu`** ("Syedjabran's Project", region
ap-northeast-1, Postgres 17.6). It is the **only** database — production.
Figures below were read from the catalog on 2026-11-12.

## 1 · Inventory

| Object | Count | Notes |
|---|---|---|
| Tables (`public`) | 182 (incl. `ai_public_rate_events`, 2026-11-12) | RLS **enabled on every one** |
| Views | 78 | 70 run as the caller (`security_invoker`); 8 run as the owner, of which 4 are now closed to the public key and 4 filter by the signed-in user — see §3 |
| Functions | 153 | 139 are `SECURITY DEFINER` |
| Triggers | 134 | numbering, totals, history, touch-timestamps, notifications |
| RLS policies | 347 (+19 on storage) | |
| Storage buckets | 2 | `crm-private`, `finance-docs` — both private |
| Extensions | pgcrypto, uuid-ossp, pg_net, pg_stat_statements, supabase_vault | |
| Database webhook | `enquiry-email` on `crm_enquiries` INSERT → `notify-enquiry` | |
| Enums | `social_*` status/action enums | other "enums" are CHECK constraints on text |

The full name list is in [`supabase/schema/objects.json`](../supabase/schema/objects.json);
which code uses which object is in [`CODEBASE-MAP.md`](CODEBASE-MAP.md).

### Domains

| Prefix | Tables | Views | Holds |
|---|---|---|---|
| `crm_` | 82 | 56 | Organisations, contacts, prospects, enquiries, opportunities, quotations (+items, approvals), orders (+items, milestones, tracking, shipments, customs), invoices, payments, allocations, receipts, projects, timesheets, employee costs, fixed expenses, subscriptions, cost sheets/lines/centres, budgets, vendors, service providers & offers, attachments, settings, counters, audit and login logs, notifications, staff roles and profiles |
| `pharma_` | 48 | 17 | Pharma distribution master: products, prices, regulatory, plants, batches, inventory, warehouses, distributors, territories, doctors, hospitals, pharmacies, visits, samples, campaigns, tenders, toll manufacturing, complaints, recalls, returns |
| `analytics_` | 17 | 5 | AI analytics: role permissions, metric definitions, connections, OAuth states/tokens (encrypted), sync jobs, daily/content metrics, attribution, prompt history |
| `ai_` | 8 | – | AI agents: configs, prompt versions, conversations, messages, summaries, handoffs, feedback, usage log |
| `social_` | 8 | – | Social planner: brand voice, channels, calendar, posts, engagement, assets, settings, audit |
| `training_` | 5 | – | Training academy: modules, quiz questions, attempts, assignments, certificates |
| other | 13 | – | `clients`, `client_*` (first-generation portal), `profiles`, `blog_posts`, `case_studies`, `featured_topics`, `contact_submissions`, `audit_findings` |

## 2 · Conventions already in the schema

- Primary keys are `uuid default gen_random_uuid()`.
- `created_at`/`updated_at timestamptz default now()`; `crm_touch_row`
  triggers maintain `updated_at`; `created_by default auth.uid()`.
- Soft delete via `deleted_at`; archive via `status`.
- Human document numbers come from `crm_next_number(p_entity)` →
  `JCO-<ENTITY>-<year>-<seq>` (counters in `crm_counters`; prefix from
  `crm_settings.numbering_prefix`). Always pass the lowercase entity code
  used elsewhere (`qtn`, `inv`, `pay`, `rcp`, `sub`, `fxp` …).
- Money is `numeric(14,2)` or `(16,2)` with a `currency` text column; derived
  amounts (`monthly_equivalent`, totals) are generated columns or trigger-maintained
  — never write them from the browser.
- Allowed values are `CHECK (col = ANY (ARRAY[...]))` on text columns.
- History tables (`*_history`) are filled by triggers.
- Settings are key/value rows in `crm_settings(key text, value jsonb)` —
  write JSON values, not JSON-encoded strings.

## 3 · Security model

1. **RLS is the boundary.** The browser uses the publishable key; RLS
   policies call `crm_is_staff()`, `crm_has_role(text[])`,
   `crm_my_org_ids()`, `analytics_can()`, `pharma_can()`.
2. **Views must run as the caller.** Create views with
   `with (security_invoker = on)`. A view without it runs as its owner and
   skips RLS — 9 views are in that state today; 5 of them expose data to
   anyone (fix proposed in `supabase/proposed/20261112_001_*`).
3. **`SECURITY DEFINER` functions must check the caller** in their first lines
   (`if not crm_has_role(...) then raise exception ...`), set
   `search_path = public` (8 functions are missing it), and be granted only
   to the roles that need them. Helpers that are only called by triggers or by
   other functions should have `EXECUTE` revoked from `anon` and
   `authenticated`.
4. **Service-role access** happens only in Edge Functions, after verifying
   the caller.

## 4 · Changing the database

There is no staging database. Every change is a production change.

1. Write the change as SQL in `supabase/proposed/<yyyymmdd>_<nnn>_<what>.sql`
   with a header explaining *why*, the verification queries, and a matching
   `.rollback.sql`.
2. Open a PR. The owner approves.
3. Run it in Supabase → SQL editor (it is wrapped in `begin; … commit;`).
   Run the verification block.
4. Move both files to `supabase/migrations/` (rename to
   `<yyyymmddHHMMSS>_<what>.sql` with the time it was applied) in a follow-up
   commit, and note it in `CHANGELOG.md`.

Never use `supabase db push` / `db reset` against this project: the remote
migration history has only one entry (`social_agent_001_foundation`), so the
CLI would not know the rest of the schema exists.

## 5 · Schema baseline

A schema-only snapshot reconstructed from the production catalog (read-only,
2026-11-12) is in [`supabase/schema/baseline/`](../supabase/schema/baseline/README.md)
— tables, constraints, indexes, functions, views, triggers, RLS policies and
grants, with two secrets redacted. To replace it with a true `pg_dump`:

The schema was built by hand in the SQL editor across ~26 numbered
increments and is not in git. To capture it (schema only, no data):

```bash
# needs the database password (Supabase → Project Settings → Database)
# and Docker Desktop running, for the Supabase CLI's pg_dump:
npx supabase@3 login
npx supabase@3 link --project-ref dvsaqjvcxqlzgpbvexnu
npx supabase@3 db dump --linked -f supabase/schema/baseline.sql
npx supabase@3 db dump --linked --role-only -f supabase/schema/roles.sql
```

Or with a local PostgreSQL 17 client:
`pg_dump "$SUPABASE_DB_URL" --schema-only --no-owner --schema=public --schema=storage -f supabase/schema/baseline.sql`.

Commit the result as `supabase/migrations/20261112000000_baseline.sql` and
mark it applied (`npx supabase@3 migration repair --status applied 20261112000000`)
so future migrations stack on top of it.

## 6 · Recommended improvements (not applied)

| # | Change | Why | Risk |
|---|---|---|---|
| D1 | ~~Close anonymous access to 5 views and 5 helper functions~~ | **Done 2026-11-12** — migration `20261112191851` | Permissions only; rollback provided |
| D2 | ~~`set search_path` on the 8 flagged functions~~ **Done 2026-11-12** (migration `20261112193236`) (`ai_conv_touch`, `crm_att_touch`, `crm_invoice_lock_guard`, `crm_order_client_status`, …) | Prevents search-path hijacking of definer code | Very low |
| D3 | Review the remaining ~125 `SECURITY DEFINER` functions executable by `anon`; revoke where no signed-out page needs them | Smaller public attack surface | Low, needs a per-function check of which public pages call RPCs |
| D4 | Turn on Auth → leaked password protection | Advisor warning | None |
| D5 | Create a **staging** Supabase project from the baseline (§5) and point previews/localhost at it | Testing today happens on live data | Medium effort; needs a config switch in `supabase-client.js` by hostname |
| D6 | Merge the duplicate counter keys (`pay`/`PAY`/`payment`, `enq`/`enquiry`, `prs`/`prospect`) | `upper()` makes `pay` and `PAY` produce the same numbers; the unique constraint turns a clash into a failed insert | Low; data change |
| D7 | Index review with `pg_stat_statements` once traffic grows | Tables are small today (largest ~1,150 rows) | None |
