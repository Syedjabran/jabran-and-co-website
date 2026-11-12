-- APPLIED to production 2026-11-12 19:19:38 UTC (migration 20261112191938).
-- Per-visitor request log used by the advisory-agent edge function to rate-limit
-- the public website chat. No raw IPs: client_key = SHA-256(IP + salt).
-- Service role only (RLS on, no policies, no grants to anon/authenticated).
create table if not exists public.ai_public_rate_events (
  id          bigserial primary key,
  bucket      text        not null,
  client_key  text        not null,
  created_at  timestamptz not null default now()
);
comment on table public.ai_public_rate_events is
  'Per-visitor request log for public AI endpoints (advisory-agent). client_key = SHA-256 of IP + salt; no raw IPs. Service role only.';
create index if not exists ai_public_rate_events_client_idx on public.ai_public_rate_events (bucket, client_key, created_at desc);
create index if not exists ai_public_rate_events_bucket_idx on public.ai_public_rate_events (bucket, created_at desc);
alter table public.ai_public_rate_events enable row level security;
revoke all on public.ai_public_rate_events from anon, authenticated;
revoke all on sequence public.ai_public_rate_events_id_seq from anon, authenticated;

-- Rollback:
--   drop table if exists public.ai_public_rate_events;
