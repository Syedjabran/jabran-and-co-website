-- Baseline 01: enum types in schema public (4).

do $$ begin
  create type public.social_audit_action as enum ('plan', 'produce', 'guardrail_pass', 'guardrail_fail', 'publish', 'publish_fail', 'reply', 'escalate', 'killswitch', 'config_change');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.social_calendar_status as enum ('planned', 'producing', 'ready', 'scheduled', 'published', 'skipped', 'failed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.social_engagement_status as enum ('new', 'drafted', 'replied', 'escalated', 'ignored');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.social_post_status as enum ('draft', 'guardrail_pending', 'quarantined', 'approved', 'scheduled', 'published', 'failed');
exception when duplicate_object then null; end $$;
