-- ============================================================================
-- APPLIED to production 2026-11-12 19:32:36 UTC (migration 20261112193236) with
-- the owner's approval. Verified: all 8 functions carry search_path=public, pg_temp.
--
-- Supabase security advisor "function_search_path_mutable": these 8 functions
-- run with the caller's search_path. Pinning it prevents a malicious schema on
-- the path from shadowing the tables they touch. All 8 are SECURITY INVOKER
-- trigger/helper functions that only use public objects or fully-qualified
-- names, so behaviour is unchanged.
-- Rollback: alter function … reset search_path;  (same 8 signatures)
-- ============================================================================
begin;
alter function public.ai_conv_touch()                   set search_path = public, pg_temp;
alter function public.crm_att_touch()                   set search_path = public, pg_temp;
alter function public.crm_invoice_lock_guard()          set search_path = public, pg_temp;
alter function public.crm_order_client_status(text)     set search_path = public, pg_temp;
alter function public.crm_quotation_lock_guard()        set search_path = public, pg_temp;
alter function public.crm_stockists_set_updated_at()    set search_path = public, pg_temp;
alter function public.crm_touch_updated_at()            set search_path = public, pg_temp;
alter function public.social_set_updated_at()           set search_path = public, pg_temp;
commit;
