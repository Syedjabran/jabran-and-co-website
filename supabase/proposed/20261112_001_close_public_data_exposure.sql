-- ============================================================================
-- PROPOSED — NOT APPLIED.  Needs the owner's approval before it is run.
-- Jabran & Co · security hardening 001 · prepared 2026-11-12
--
-- Changes PERMISSIONS only. No table, column, row, policy or function body is
-- created, altered or deleted. Every page and CRM module keeps working.
--
-- Why (verified on production 2026-11-12, read-only, see docs/AUDIT-2026-11-12.md):
--
-- A. Five views run with their OWNER's rights (Postgres default "security
--    definer" views), so row-level security on the underlying tables is skipped.
--    The `anon` role (anyone holding the public key that every web page ships)
--    can read them without logging in:
--       crm_receivables_payment_breakdown  23 rows: invoice numbers, totals, paid,
--                                          outstanding, payment refs, receipt numbers
--       analytics_fact_orders              order titles + revenue
--       analytics_fact_quotations          quotation totals
--       analytics_fact_opportunities       pipeline values
--       analytics_fact_enquiries           enquiry sources / UTM data
--    Any signed-in CLIENT PORTAL account can read every organisation's rows the
--    same way.
--    Who legitimately reads them:
--       analytics_fact_*  → only the SECURITY DEFINER RPCs analytics_overview,
--                           analytics_timeseries, analytics_by_dimension,
--                           analytics_metric_catalog, analytics_data_freshness
--                           (they run as the owner, so this revoke does not
--                           touch them).
--       crm_receivables_payment_breakdown → no page, script or edge function.
--
-- B. Five SECURITY DEFINER helper functions are callable by `anon` and by any
--    signed-in account and perform writes with no caller check:
--       crm_notify(...)                 inserts a notification (any title, body,
--                                       link) for ANY user → phishing inside the CRM
--       crm_invoice_recalc(uuid)        rewrites an invoice's totals
--       crm_quotation_recalc(uuid)      rewrites a quotation's totals
--       crm_apply_allocation_totals(uuid)
--       analytics_purge_oauth_states()
--    Every in-database caller of these is itself SECURITY DEFINER (trigger
--    functions crm_invoice_items_changed, crm_invoice_rates_changed,
--    crm_quotation_items_changed, crm_quotation_rates_changed,
--    crm_allocations_changed, ai_msg_after, ai_handoff_after, crm_rm_track and
--    the RPCs crm_generate_milestones, crm_reassign_rm, crm_recalc_tracking),
--    so they keep working. No page or script calls them directly. Edge functions
--    use the service role, which is unaffected.
--
-- Rollback: supabase/proposed/20261112_001_close_public_data_exposure.rollback.sql
-- ============================================================================

begin;

-- A · views -----------------------------------------------------------------
revoke select on public.analytics_fact_orders        from anon, authenticated;
revoke select on public.analytics_fact_quotations    from anon, authenticated;
revoke select on public.analytics_fact_opportunities from anon, authenticated;
revoke select on public.analytics_fact_enquiries     from anon, authenticated;

-- Keep it usable for staff in future, but under each caller's own RLS:
alter view public.crm_receivables_payment_breakdown set (security_invoker = on);
revoke select on public.crm_receivables_payment_breakdown from anon;

-- B · unguarded write helpers --------------------------------------------------
revoke execute on function public.crm_notify(uuid, text, text, text, text)  from public, anon, authenticated;
revoke execute on function public.crm_invoice_recalc(uuid)                  from public, anon, authenticated;
revoke execute on function public.crm_quotation_recalc(uuid)                from public, anon, authenticated;
revoke execute on function public.crm_apply_allocation_totals(uuid)         from public, anon, authenticated;
revoke execute on function public.analytics_purge_oauth_states()            from public, anon, authenticated;

commit;

-- Verify afterwards (expect 0 / permission denied for anon):
--   begin read only; set local role anon;
--   select count(*) from public.crm_receivables_payment_breakdown;   -- 0 rows
--   select count(*) from public.analytics_fact_orders;               -- permission denied
--   rollback;
-- And as Owner in the CRM: AI Analytics overview still loads; Finance pages,
-- invoice/quotation edits still recalculate totals.
