# Production schema baseline (schema-only)

A schema-only snapshot of the production Supabase database (project ref
`dvsaqjvcxqlzgpbvexnu`), kept in git so the database structure has a
reviewable source of truth. It contains **no data**.

- **Captured:** 2026-11-12, roughly 19:18 to 19:57 UTC (`select now()` at
  start: `2026-11-12 19:18:50+00`; final count check: `2026-11-12 19:56:56+00`).
  The session's local date was already 2026-11-13.
- **Grants captured at:** tables/views `2026-11-12 19:55:32 UTC`, functions
  `2026-11-12 19:55:44 UTC`.
- **Server:** PostgreSQL 17.6 (Supabase).

## How it was produced

This is a **catalog reconstruction, not `pg_dump`**. It was built only from
read-only `select` queries against `pg_catalog` / `information_schema` and the
catalog functions `format_type`, `pg_get_expr`, `pg_get_constraintdef`,
`pg_get_indexdef`, `pg_get_functiondef`, `pg_get_viewdef`, `pg_get_triggerdef`,
`has_table_privilege`, `aclexplode` and the `pg_policies` view. No application
table rows were read.

Because of that, the following are **not** included:

- object ownership (`alter ... owner to`) and comments (`comment on`);
- sequence current values (sequences start at 1);
- publications / Realtime configuration;
- the Supabase **Database Webhook** `enquiry-email` on `public.crm_enquiries`
  (it embeds a secret header; see the note at the top of `06_triggers.sql`);
- storage buckets (rows in `storage.buckets`), auth config, Edge Functions,
  cron jobs, Vault secrets;
- `alter default privileges` settings;
- anything outside schema `public`, except the `storage` policies in
  `07_rls.sql`.

Deliberate redactions (do not "fix" these by pasting production values):

- `06_triggers.sql`: the `enquiry-email` webhook trigger is commented out and
  its `x-webhook-secret` is replaced with `<REDACTED>`.
- `07_rls.sql`: storage policy `"agent uploads own lane"` uses a path token
  that gates anonymous uploads; it is replaced with `<REDACTED-LANE-TOKEN>`.

Other known differences from production:

- `crm_stockists_assign_number()` and `crm_stockists_set_updated_at()` have
  CRLF line endings inside their bodies on production; they are LF here.

## Contents and counts (at capture time)

| File | What | Count |
| --- | --- | --- |
| `00_extensions.sql` | non-default extensions (pgcrypto, uuid-ossp, pg_stat_statements, pg_net in `extensions`; supabase_vault in `vault`) | 5 |
| `01_types.sql` | enum types | 4 |
| `02_tables.sql` | standalone/serial sequences, tables, then constraints (PK, unique, check, FK last) | 4 sequences, 182 tables (2,583 columns), 182 PK + 82 unique + 303 check + 345 FK = 912 constraints |
| `03_indexes.sql` | indexes not backing a PK/unique constraint | 153 |
| `04_functions.sql` | all functions in `public`, via `pg_get_functiondef` | 153 |
| `05_views.sql` | views in dependency order, with `security_invoker` reloptions | 78 |
| `06_triggers.sql` | non-internal triggers | 133 emitted (+1 webhook, redacted) = 134 on production |
| `07_rls.sql` | `enable row level security` + policies | 182 tables, 347 public policies, 19 storage policies |
| `08_grants.sql` | anon/authenticated table+view privileges and function EXECUTE | 260 relations, 153 functions |

## Applying to a fresh Supabase project

Run the files **in numeric order** as a privileged role (e.g. `postgres` via
the SQL editor or `psql`), on a new project where the `auth`, `storage` and
`extensions` schemas already exist (any Supabase project):

```
00_extensions.sql
01_types.sql
02_tables.sql
03_indexes.sql
04_functions.sql   (sets check_function_bodies = off for its duration)
05_views.sql
06_triggers.sql
07_rls.sql
08_grants.sql
```

Notes:

- Keep the default `search_path` (`"$user", public, extensions`). Constraint
  and view definitions use unqualified names, as `pg_get_*def` prints them.
- `02_tables.sql` uses `create table if not exists`, but the `alter table ...
  add constraint` statements, indexes, triggers and policies are **not**
  idempotent; this is meant for an empty project, not for re-running on an
  existing one.
- Functions are created before views because several views call them; some
  SQL functions in turn reference views, which is why function body checking
  is switched off in `04_functions.sql`.
- After applying, recreate the `enquiry-email` webhook from the dashboard
  (Database -> Webhooks) with a new secret, recreate storage buckets, and set
  a fresh agent-lane token in the `"agent uploads own lane"` storage policy.

## Point in time

This reflects production **before any 2026-11-13 migrations**, with these
exceptions that were already live when it was captured:

- table `public.ai_public_rate_events` (+ its serial sequence, PK, two
  indexes, RLS enabled, no anon/authenticated grants) is included;
- the grants in `08_grants.sql` already show SELECT revoked from anon and
  authenticated on `analytics_fact_enquiries`, `analytics_fact_opportunities`,
  `analytics_fact_orders`, `analytics_fact_quotations`, and from anon on
  `crm_receivables_payment_breakdown`.

Permission migrations were being applied to production while this was
captured. Treat `08_grants.sql` as accurate only as of the grant timestamps
above; function bodies were read between about 19:35 and 19:50 UTC.
