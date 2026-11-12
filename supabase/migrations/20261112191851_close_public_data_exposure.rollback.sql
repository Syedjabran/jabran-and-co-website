-- Rollback for 20261112_001_close_public_data_exposure.sql
-- Restores the exact permissions found on production on 2026-11-12.
begin;

grant select on public.analytics_fact_orders        to anon, authenticated;
grant select on public.analytics_fact_quotations    to anon, authenticated;
grant select on public.analytics_fact_opportunities to anon, authenticated;
grant select on public.analytics_fact_enquiries     to anon, authenticated;

alter view public.crm_receivables_payment_breakdown reset (security_invoker);
grant select on public.crm_receivables_payment_breakdown to anon;

grant execute on function public.crm_notify(uuid, text, text, text, text)  to public, anon, authenticated;
grant execute on function public.crm_invoice_recalc(uuid)                  to public, anon, authenticated;
grant execute on function public.crm_quotation_recalc(uuid)                to public, anon, authenticated;
grant execute on function public.crm_apply_allocation_totals(uuid)         to public, anon, authenticated;
grant execute on function public.analytics_purge_oauth_states()            to public, anon, authenticated;

commit;
