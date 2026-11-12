-- Baseline 07: row level security.
-- 1) RLS is enabled on every public table (182 of 182; none use FORCE RLS).
-- 2) Every policy from pg_policies for schema public (347 at capture time),
--    then the storage.objects policies (19). Ordered by table, policy name.

alter table public.ai_agent_configs enable row level security;
alter table public.ai_agent_feedback enable row level security;
alter table public.ai_agent_handoffs enable row level security;
alter table public.ai_conversation_summaries enable row level security;
alter table public.ai_conversations enable row level security;
alter table public.ai_messages enable row level security;
alter table public.ai_prompt_versions enable row level security;
alter table public.ai_public_rate_events enable row level security;
alter table public.ai_usage_log enable row level security;
alter table public.analytics_accounts enable row level security;
alter table public.analytics_alerts enable row level security;
alter table public.analytics_attribution enable row level security;
alter table public.analytics_campaigns enable row level security;
alter table public.analytics_connections enable row level security;
alter table public.analytics_content_metrics enable row level security;
alter table public.analytics_conversion_events enable row level security;
alter table public.analytics_daily_metrics enable row level security;
alter table public.analytics_data_quality_events enable row level security;
alter table public.analytics_fact_map enable row level security;
alter table public.analytics_generated_reports enable row level security;
alter table public.analytics_metric_definitions enable row level security;
alter table public.analytics_oauth_states enable row level security;
alter table public.analytics_oauth_tokens enable row level security;
alter table public.analytics_prompt_history enable row level security;
alter table public.analytics_role_permissions enable row level security;
alter table public.analytics_sync_jobs enable row level security;
alter table public.audit_findings enable row level security;
alter table public.blog_posts enable row level security;
alter table public.case_studies enable row level security;
alter table public.case_study_approvals enable row level security;
alter table public.client_actions enable row level security;
alter table public.client_documents enable row level security;
alter table public.client_kpis enable row level security;
alter table public.client_meetings enable row level security;
alter table public.client_reports enable row level security;
alter table public.clients enable row level security;
alter table public.contact_submissions enable row level security;
alter table public.crm_activity_events enable row level security;
alter table public.crm_agent_accounts enable row level security;
alter table public.crm_ai_actions enable row level security;
alter table public.crm_ai_agents enable row level security;
alter table public.crm_alert_dismissals enable row level security;
alter table public.crm_allocation_rules enable row level security;
alter table public.crm_allocation_targets enable row level security;
alter table public.crm_attachment_categories enable row level security;
alter table public.crm_attachment_events enable row level security;
alter table public.crm_attachment_policy enable row level security;
alter table public.crm_attachments enable row level security;
alter table public.crm_audit_logs enable row level security;
alter table public.crm_billing_bases enable row level security;
alter table public.crm_budgets enable row level security;
alter table public.crm_contacts enable row level security;
alter table public.crm_cost_allocations enable row level security;
alter table public.crm_cost_categories enable row level security;
alter table public.crm_cost_centres enable row level security;
alter table public.crm_cost_lines enable row level security;
alter table public.crm_cost_sheet_items enable row level security;
alter table public.crm_cost_sheets enable row level security;
alter table public.crm_counters enable row level security;
alter table public.crm_countries enable row level security;
alter table public.crm_custom_values enable row level security;
alter table public.crm_customs_records enable row level security;
alter table public.crm_daily_entries enable row level security;
alter table public.crm_departments enable row level security;
alter table public.crm_email_log enable row level security;
alter table public.crm_employee_allowances enable row level security;
alter table public.crm_employee_cost_history enable row level security;
alter table public.crm_employee_costs enable row level security;
alter table public.crm_employee_profiles enable row level security;
alter table public.crm_enquiries enable row level security;
alter table public.crm_enquiry_activity enable row level security;
alter table public.crm_expenses enable row level security;
alter table public.crm_field_config enable row level security;
alter table public.crm_fixed_expense_history enable row level security;
alter table public.crm_fixed_expenses enable row level security;
alter table public.crm_invoice_items enable row level security;
alter table public.crm_invoices enable row level security;
alter table public.crm_job_roles enable row level security;
alter table public.crm_login_history enable row level security;
alter table public.crm_notifications enable row level security;
alter table public.crm_opportunities enable row level security;
alter table public.crm_opportunity_activity enable row level security;
alter table public.crm_order_events enable row level security;
alter table public.crm_order_items enable row level security;
alter table public.crm_order_milestones enable row level security;
alter table public.crm_order_tracking enable row level security;
alter table public.crm_orders enable row level security;
alter table public.crm_organizations enable row level security;
alter table public.crm_outsourced_categories enable row level security;
alter table public.crm_payment_allocations enable row level security;
alter table public.crm_payments enable row level security;
alter table public.crm_portal_members enable row level security;
alter table public.crm_project_milestones enable row level security;
alter table public.crm_projects enable row level security;
alter table public.crm_prospects enable row level security;
alter table public.crm_quotation_approvals enable row level security;
alter table public.crm_quotation_items enable row level security;
alter table public.crm_quotations enable row level security;
alter table public.crm_receipts enable row level security;
alter table public.crm_record_assignments enable row level security;
alter table public.crm_rm_policy enable row level security;
alter table public.crm_service_branches enable row level security;
alter table public.crm_service_milestone_templates enable row level security;
alter table public.crm_service_offers enable row level security;
alter table public.crm_service_provider_bank enable row level security;
alter table public.crm_service_providers enable row level security;
alter table public.crm_services enable row level security;
alter table public.crm_settings enable row level security;
alter table public.crm_shipments enable row level security;
alter table public.crm_staff_roles enable row level security;
alter table public.crm_stockists enable row level security;
alter table public.crm_subscription_price_history enable row level security;
alter table public.crm_subscriptions enable row level security;
alter table public.crm_supplier_offers enable row level security;
alter table public.crm_timesheets enable row level security;
alter table public.crm_tracking_policy enable row level security;
alter table public.crm_tracking_template_steps enable row level security;
alter table public.crm_tracking_templates enable row level security;
alter table public.crm_vendors enable row level security;
alter table public.featured_topics enable row level security;
alter table public.pharma_adverse_events enable row level security;
alter table public.pharma_campaigns enable row level security;
alter table public.pharma_companies enable row level security;
alter table public.pharma_company_contacts enable row level security;
alter table public.pharma_complaints enable row level security;
alter table public.pharma_distributor_products enable row level security;
alter table public.pharma_distributor_territories enable row level security;
alter table public.pharma_distributors enable row level security;
alter table public.pharma_doctor_affiliations enable row level security;
alter table public.pharma_doctor_products enable row level security;
alter table public.pharma_doctors enable row level security;
alter table public.pharma_dosage_forms enable row level security;
alter table public.pharma_engagement_spend enable row level security;
alter table public.pharma_expense_dimensions enable row level security;
alter table public.pharma_field_force enable row level security;
alter table public.pharma_hospitals enable row level security;
alter table public.pharma_inventory_batches enable row level security;
alter table public.pharma_inventory_movements enable row level security;
alter table public.pharma_invoices enable row level security;
alter table public.pharma_offer_categories enable row level security;
alter table public.pharma_offer_products enable row level security;
alter table public.pharma_offer_targets enable row level security;
alter table public.pharma_pharmacies enable row level security;
alter table public.pharma_plant_capabilities enable row level security;
alter table public.pharma_plants enable row level security;
alter table public.pharma_product_prices enable row level security;
alter table public.pharma_product_regulatory enable row level security;
alter table public.pharma_production_batches enable row level security;
alter table public.pharma_products enable row level security;
alter table public.pharma_promotional_offers enable row level security;
alter table public.pharma_recalls enable row level security;
alter table public.pharma_receipts enable row level security;
alter table public.pharma_returns enable row level security;
alter table public.pharma_role_permissions enable row level security;
alter table public.pharma_sales_order_items enable row level security;
alter table public.pharma_sales_orders enable row level security;
alter table public.pharma_sample_items enable row level security;
alter table public.pharma_sample_transactions enable row level security;
alter table public.pharma_tender_products enable row level security;
alter table public.pharma_tenders enable row level security;
alter table public.pharma_territories enable row level security;
alter table public.pharma_therapeutic_categories enable row level security;
alter table public.pharma_toll_contracts enable row level security;
alter table public.pharma_toll_enquiries enable row level security;
alter table public.pharma_toll_offers enable row level security;
alter table public.pharma_visit_plans enable row level security;
alter table public.pharma_visits enable row level security;
alter table public.pharma_warehouses enable row level security;
alter table public.profiles enable row level security;
alter table public.social_assets enable row level security;
alter table public.social_audit_log enable row level security;
alter table public.social_brand_voice enable row level security;
alter table public.social_channels enable row level security;
alter table public.social_content_calendar enable row level security;
alter table public.social_engagement enable row level security;
alter table public.social_posts enable row level security;
alter table public.social_settings enable row level security;
alter table public.training_assignments enable row level security;
alter table public.training_certificates enable row level security;
alter table public.training_modules enable row level security;
alter table public.training_quiz_attempts enable row level security;
alter table public.training_quiz_questions enable row level security;

-- ---------------------------------------------------------------------------
-- Policies: schema public
-- ---------------------------------------------------------------------------

create policy "aicfg_read" on public.ai_agent_configs as permissive for select to public
  using (crm_is_staff());
create policy "aicfg_write" on public.ai_agent_configs as permissive for update to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]));
create policy "aifb_client_insert" on public.ai_agent_feedback as permissive for insert to public
  with check (((submitted_by = 'client'::text) AND (EXISTS ( SELECT 1
   FROM ai_conversations c
  WHERE ((c.id = ai_agent_feedback.conversation_id) AND (c.user_id = auth.uid()))))));
create policy "aifb_staff_read" on public.ai_agent_feedback as permissive for select to public
  using (crm_is_staff());
create policy "aihand_client_raise" on public.ai_agent_handoffs as permissive for insert to public
  with check (((requested_by = 'client'::text) AND (EXISTS ( SELECT 1
   FROM ai_conversations c
  WHERE ((c.id = ai_agent_handoffs.conversation_id) AND (c.user_id = auth.uid()))))));
create policy "aihand_staff" on public.ai_agent_handoffs as permissive for all to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "aisum_gov_write" on public.ai_conversation_summaries as permissive for update to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]));
create policy "aisum_staff_read" on public.ai_conversation_summaries as permissive for select to public
  using (crm_is_staff());
create policy "aic_client_read" on public.ai_conversations as permissive for select to public
  using ((user_id = auth.uid()));
create policy "aic_client_touch" on public.ai_conversations as permissive for update to public
  using ((user_id = auth.uid()))
  with check (((user_id = auth.uid()) AND (conversation_type = 'client'::text)));
create policy "aic_staff" on public.ai_conversations as permissive for all to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "aim_client_read" on public.ai_messages as permissive for select to public
  using ((EXISTS ( SELECT 1
   FROM ai_conversations c
  WHERE ((c.id = ai_messages.conversation_id) AND (c.user_id = auth.uid())))));
create policy "aim_client_write" on public.ai_messages as permissive for insert to public
  with check (((sender_type = 'client'::text) AND (sender_user_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM ai_conversations c
  WHERE ((c.id = ai_messages.conversation_id) AND (c.user_id = auth.uid()) AND (c.status <> ALL (ARRAY['resolved'::text, 'abandoned'::text, 'spam'::text])))))));
create policy "aim_staff" on public.ai_messages as permissive for all to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "apv_read" on public.ai_prompt_versions as permissive for select to public
  using (crm_is_staff());
create policy "apv_write" on public.ai_prompt_versions as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]));
create policy "aiusage_read" on public.ai_usage_log as permissive for select to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'read_only_auditor'::text]));
create policy "read accounts" on public.analytics_accounts as permissive for select to public
  using (analytics_can('analytics.view'::text));
create policy "read alerts" on public.analytics_alerts as permissive for select to public
  using (analytics_can('analytics.view'::text));
create policy "read attribution" on public.analytics_attribution as permissive for select to public
  using ((analytics_can('analytics.view'::text) AND ((analytics_scope_orgs() IS NULL) OR (org_id = ANY (analytics_scope_orgs())))));
create policy "read campaigns" on public.analytics_campaigns as permissive for select to public
  using ((analytics_can('analytics.view'::text) AND (analytics_scope_orgs() IS NULL)));
create policy "manage connections" on public.analytics_connections as permissive for all to public
  using ((analytics_can('analytics.manage_connections'::text) OR analytics_can('analytics.admin'::text)))
  with check ((analytics_can('analytics.manage_connections'::text) OR analytics_can('analytics.admin'::text)));
create policy "read connections" on public.analytics_connections as permissive for select to public
  using (analytics_can('analytics.view'::text));
create policy "read content metrics" on public.analytics_content_metrics as permissive for select to public
  using ((analytics_can('analytics.view'::text) AND (analytics_scope_orgs() IS NULL)));
create policy "read conversion events" on public.analytics_conversion_events as permissive for select to public
  using ((analytics_can('analytics.view'::text) AND ((analytics_scope_orgs() IS NULL) OR (org_id = ANY (analytics_scope_orgs())))));
create policy "read daily metrics" on public.analytics_daily_metrics as permissive for select to public
  using ((analytics_can('analytics.view'::text) AND ((analytics_scope_orgs() IS NULL) OR (org_id IS NULL) OR (org_id = ANY (analytics_scope_orgs())))));
create policy "read dq events" on public.analytics_data_quality_events as permissive for select to public
  using (analytics_can('analytics.view'::text));
create policy "read fact map" on public.analytics_fact_map as permissive for select to public
  using (analytics_can('analytics.view'::text));
create policy "create reports" on public.analytics_generated_reports as permissive for insert to public
  with check (((created_by = auth.uid()) AND analytics_can('analytics.query'::text)));
create policy "read reports" on public.analytics_generated_reports as permissive for select to public
  using (((created_by = auth.uid()) OR analytics_can('analytics.admin'::text)));
create policy "manage metric defs" on public.analytics_metric_definitions as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]));
create policy "read metric defs" on public.analytics_metric_definitions as permissive for select to public
  using (analytics_can('analytics.view'::text));
create policy "insert own prompts" on public.analytics_prompt_history as permissive for insert to public
  with check (((user_id = auth.uid()) AND analytics_can('analytics.query'::text)));
create policy "own prompts" on public.analytics_prompt_history as permissive for select to public
  using (((user_id = auth.uid()) OR analytics_can('analytics.admin'::text)));
create policy "governance manages analytics permissions" on public.analytics_role_permissions as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]));
create policy "staff read analytics permissions" on public.analytics_role_permissions as permissive for select to public
  using (crm_is_staff());
create policy "read sync jobs" on public.analytics_sync_jobs as permissive for select to public
  using (analytics_can('analytics.view'::text));
create policy "admin_full_audit" on public.audit_findings as permissive for all to authenticated
  using (is_admin());
create policy "client_view_own_audit" on public.audit_findings as permissive for select to authenticated
  using ((client_id IN ( SELECT profiles.client_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
create policy "Admin can read all posts" on public.blog_posts as permissive for select to authenticated
  using (true);
create policy "Admin can update posts" on public.blog_posts as permissive for update to authenticated
  using (true);
create policy "Public can read approved posts" on public.blog_posts as permissive for select to anon
  using ((status = 'approved'::text));
create policy "Public can submit posts" on public.blog_posts as permissive for insert to anon
  with check ((status = 'pending'::text));
create policy "admin_full_case_studies" on public.case_studies as permissive for all to authenticated
  using (is_admin());
create policy "client_view_own_case_studies" on public.case_studies as permissive for select to authenticated
  using ((client_id IN ( SELECT profiles.client_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
create policy "public_read_published_cases" on public.case_studies as permissive for select to anon
  using ((status = 'published'::text));
create policy "admin_full_case_approvals" on public.case_study_approvals as permissive for all to authenticated
  using (is_admin());
create policy "client_manage_own_approval" on public.case_study_approvals as permissive for all to authenticated
  using ((case_study_id IN ( SELECT case_studies.id
   FROM case_studies
  WHERE (case_studies.client_id IN ( SELECT profiles.client_id
           FROM profiles
          WHERE (profiles.id = auth.uid()))))))
  with check ((case_study_id IN ( SELECT case_studies.id
   FROM case_studies
  WHERE (case_studies.client_id IN ( SELECT profiles.client_id
           FROM profiles
          WHERE (profiles.id = auth.uid()))))));
create policy "admin_full_actions" on public.client_actions as permissive for all to authenticated
  using (is_admin());
create policy "client_view_own_actions" on public.client_actions as permissive for select to authenticated
  using ((client_id IN ( SELECT profiles.client_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
create policy "admin_full_documents" on public.client_documents as permissive for all to authenticated
  using (is_admin());
create policy "client_view_own_documents" on public.client_documents as permissive for select to authenticated
  using ((client_id IN ( SELECT profiles.client_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
create policy "admin_full_kpis" on public.client_kpis as permissive for all to authenticated
  using (is_admin());
create policy "client_view_own_kpis" on public.client_kpis as permissive for select to authenticated
  using ((client_id IN ( SELECT profiles.client_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
create policy "admin_full_meetings" on public.client_meetings as permissive for all to authenticated
  using (is_admin());
create policy "client_view_own_meetings" on public.client_meetings as permissive for select to authenticated
  using ((client_id IN ( SELECT profiles.client_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
create policy "admin_full_reports" on public.client_reports as permissive for all to authenticated
  using (is_admin());
create policy "client_view_own_reports" on public.client_reports as permissive for select to authenticated
  using ((client_id IN ( SELECT profiles.client_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
create policy "admin_full_clients" on public.clients as permissive for all to authenticated
  using (is_admin());
create policy "client_view_own" on public.clients as permissive for select to authenticated
  using ((id IN ( SELECT profiles.client_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
create policy "Admin can read contact" on public.contact_submissions as permissive for select to authenticated
  using (true);
create policy "Public can submit contact" on public.contact_submissions as permissive for insert to anon
  with check (true);
create policy "governance reads activity" on public.crm_activity_events as permissive for select to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'read_only_auditor'::text]));
create policy "staff read agent accounts" on public.crm_agent_accounts as permissive for select to public
  using (crm_is_staff());
create policy "read own or management reads all ai actions" on public.crm_ai_actions as permissive for select to public
  using (((user_id = auth.uid()) OR crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text])));
create policy "staff log own ai actions" on public.crm_ai_actions as permissive for insert to public
  with check ((crm_is_staff() AND (user_id = auth.uid())));
create policy "staff update own ai actions" on public.crm_ai_actions as permissive for update to public
  using ((user_id = auth.uid()))
  with check ((user_id = auth.uid()));
create policy "crm_ai_agents_staff_read" on public.crm_ai_agents as permissive for select to public
  using (crm_is_staff());
create policy "own dismissals" on public.crm_alert_dismissals as permissive for all to public
  using ((user_id = auth.uid()))
  with check ((user_id = auth.uid()));
create policy "governance edits allocation rules" on public.crm_allocation_rules as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]));
create policy "management reads allocation rules" on public.crm_allocation_rules as permissive for select to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]));
create policy "governance edits allocation targets" on public.crm_allocation_targets as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]));
create policy "management reads allocation targets" on public.crm_allocation_targets as permissive for select to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]));
create policy "att_cat_read" on public.crm_attachment_categories as permissive for select to public
  using ((auth.role() = 'authenticated'::text));
create policy "att_cat_write" on public.crm_attachment_categories as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]));
create policy "att_ev_insert" on public.crm_attachment_events as permissive for insert to public
  with check (((auth.uid() IS NOT NULL) AND (actor = auth.uid())));
create policy "att_ev_read" on public.crm_attachment_events as permissive for select to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'read_only_auditor'::text]));
create policy "att_policy_read" on public.crm_attachment_policy as permissive for select to public
  using (crm_is_staff());
create policy "att_policy_write" on public.crm_attachment_policy as permissive for update to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]));
create policy "att_client_insert" on public.crm_attachments as permissive for insert to public
  with check (((auth.uid() IS NOT NULL) AND (organization_id IN ( SELECT pm.organization_id
   FROM crm_portal_members pm
  WHERE (pm.user_id = auth.uid())))));
create policy "att_client_select" on public.crm_attachments as permissive for select to public
  using (((deleted_at IS NULL) AND (visibility_scope = ANY (ARRAY['client_visible'::text, 'client_uploaded'::text])) AND (organization_id IN ( SELECT pm.organization_id
   FROM crm_portal_members pm
  WHERE (pm.user_id = auth.uid())))));
create policy "att_staff_delete" on public.crm_attachments as permissive for delete to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]));
create policy "att_staff_insert" on public.crm_attachments as permissive for insert to public
  with check (crm_is_staff());
create policy "att_staff_select" on public.crm_attachments as permissive for select to public
  using ((crm_is_staff() AND ((visibility_scope <> ALL (ARRAY['owner_only'::text, 'finance_only'::text, 'legal_confidential'::text])) OR ((visibility_scope = 'finance_only'::text) AND crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text])) OR ((visibility_scope = ANY (ARRAY['owner_only'::text, 'legal_confidential'::text])) AND crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text])))));
create policy "att_staff_update" on public.crm_attachments as permissive for update to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "staff add attachments" on public.crm_attachments as permissive for insert to public
  with check ((crm_is_staff() AND (uploaded_by = auth.uid())));
create policy "staff delete attachments" on public.crm_attachments as permissive for delete to public
  using (crm_is_staff());
create policy "staff read attachments" on public.crm_attachments as permissive for select to public
  using (crm_is_staff());
create policy "management reads audit logs" on public.crm_audit_logs as permissive for select to public
  using (crm_has_role(ARRAY['super_admin'::text, 'ceo'::text, 'read_only_auditor'::text]));
create policy "governance manages billing bases" on public.crm_billing_bases as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]));
create policy "staff read billing bases" on public.crm_billing_bases as permissive for select to public
  using (crm_is_staff());
create policy "governance manages budgets" on public.crm_budgets as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]));
create policy "management reads budgets" on public.crm_budgets as permissive for select to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]));
create policy "clients read own contacts" on public.crm_contacts as permissive for select to public
  using (((organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)) AND (deleted_at IS NULL)));
create policy "staff full access contacts" on public.crm_contacts as permissive for all to public
  using ((crm_is_staff() AND (deleted_at IS NULL)))
  with check (crm_is_staff());
create policy "management reads allocations" on public.crm_cost_allocations as permissive for select to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]));
create policy "governance manages cost categories" on public.crm_cost_categories as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]));
create policy "staff read cost categories" on public.crm_cost_categories as permissive for select to public
  using (crm_is_staff());
create policy "finance reads cost centres" on public.crm_cost_centres as permissive for select to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text, 'operations_manager'::text]));
create policy "governance manages cost centres" on public.crm_cost_centres as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]));
create policy "governance manages cost lines" on public.crm_cost_lines as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]));
create policy "staff read cost lines" on public.crm_cost_lines as permissive for select to public
  using (crm_is_staff());
create policy "finance mgmt access cost items" on public.crm_cost_sheet_items as permissive for all to public
  using (crm_has_role(ARRAY['super_admin'::text, 'ceo'::text, 'finance_manager'::text, 'trade_sourcing_manager'::text, 'operations_manager'::text]))
  with check (crm_has_role(ARRAY['super_admin'::text, 'ceo'::text, 'finance_manager'::text, 'trade_sourcing_manager'::text, 'operations_manager'::text]));
create policy "finance mgmt access cost sheets" on public.crm_cost_sheets as permissive for all to public
  using ((crm_has_role(ARRAY['super_admin'::text, 'ceo'::text, 'finance_manager'::text, 'trade_sourcing_manager'::text, 'operations_manager'::text]) AND (deleted_at IS NULL)))
  with check (crm_has_role(ARRAY['super_admin'::text, 'ceo'::text, 'finance_manager'::text, 'trade_sourcing_manager'::text, 'operations_manager'::text]));
create policy "staff read counters" on public.crm_counters as permissive for select to public
  using (crm_is_staff());
create policy "anyone reads countries" on public.crm_countries as permissive for select to public
  using (true);
create policy "governance manages countries" on public.crm_countries as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]));
create policy "staff manage custom values" on public.crm_custom_values as permissive for all to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "staff full access customs" on public.crm_customs_records as permissive for all to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "edit own pending daily entries" on public.crm_daily_entries as permissive for update to public
  using (((entered_by = auth.uid()) AND (status = 'pending'::text)))
  with check (((entered_by = auth.uid()) AND (status = 'pending'::text)));
create policy "read own or management reads all daily entries" on public.crm_daily_entries as permissive for select to public
  using (((entered_by = auth.uid()) OR crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text])));
create policy "staff submit own daily entries" on public.crm_daily_entries as permissive for insert to public
  with check ((crm_is_staff() AND (entered_by = auth.uid())));
create policy "withdraw own pending daily entries" on public.crm_daily_entries as permissive for delete to public
  using (((entered_by = auth.uid()) AND (status = 'pending'::text)));
create policy "governance manages departments" on public.crm_departments as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'hr_manager'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'hr_manager'::text]));
create policy "staff read departments" on public.crm_departments as permissive for select to public
  using (crm_is_staff());
create policy "crm_email_log_select" on public.crm_email_log as permissive for select to public
  using (crm_is_staff());
create policy "finance reads allowances" on public.crm_employee_allowances as permissive for select to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]));
create policy "governance manages allowances" on public.crm_employee_allowances as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]));
create policy "finance reads employee cost history" on public.crm_employee_cost_history as permissive for select to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]));
create policy "finance reads employee costs" on public.crm_employee_costs as permissive for select to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]));
create policy "governance manages employee costs" on public.crm_employee_costs as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]));
create policy "employees read own profile" on public.crm_employee_profiles as permissive for select to public
  using ((user_id = auth.uid()));
create policy "governance manages employee profiles" on public.crm_employee_profiles as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]));
create policy "clients create own enquiries" on public.crm_enquiries as permissive for insert to authenticated
  with check (((organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)) AND (source = 'portal'::text) AND (status = 'new'::text) AND (assigned_to IS NULL)));
create policy "clients read own enquiries" on public.crm_enquiries as permissive for select to public
  using (((organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)) AND (deleted_at IS NULL)));
create policy "public website enquiry insert" on public.crm_enquiries as permissive for insert to anon, authenticated
  with check ((source = 'website'::text));
create policy "staff full access enquiries" on public.crm_enquiries as permissive for all to public
  using ((crm_is_staff() AND (deleted_at IS NULL)))
  with check (crm_is_staff());
create policy "client reads visible enquiry activity" on public.crm_enquiry_activity as permissive for select to public
  using (((visibility = ANY (ARRAY['client_visible'::text, 'client_action_required'::text])) AND (enquiry_id IN ( SELECT crm_enquiries.id
   FROM crm_enquiries
  WHERE (crm_enquiries.organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids))))));
create policy "clients post visible comments" on public.crm_enquiry_activity as permissive for insert to authenticated
  with check (((kind = 'comment'::text) AND (visibility = 'client_visible'::text) AND (enquiry_id IN ( SELECT crm_enquiries.id
   FROM crm_enquiries
  WHERE (crm_enquiries.organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids))))));
create policy "clients read visible activity" on public.crm_enquiry_activity as permissive for select to public
  using (((visibility = ANY (ARRAY['client_visible'::text, 'client_action_required'::text])) AND (enquiry_id IN ( SELECT crm_enquiries.id
   FROM crm_enquiries
  WHERE (crm_enquiries.organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids))))));
create policy "staff full access enquiry activity" on public.crm_enquiry_activity as permissive for all to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "finance manages expenses" on public.crm_expenses as permissive for all to public
  using ((crm_is_finance() AND (deleted_at IS NULL)))
  with check (crm_is_finance());
create policy "mgmt read expenses" on public.crm_expenses as permissive for select to public
  using ((crm_has_role(ARRAY['operations_manager'::text, 'read_only_auditor'::text]) AND (deleted_at IS NULL)));
create policy "owner manages field config" on public.crm_field_config as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]));
create policy "staff read field config" on public.crm_field_config as permissive for select to public
  using (crm_is_staff());
create policy "finance reads fixed expense history" on public.crm_fixed_expense_history as permissive for select to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]));
create policy "finance reads fixed expenses" on public.crm_fixed_expenses as permissive for select to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]));
create policy "governance manages fixed expenses" on public.crm_fixed_expenses as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]));
create policy "clients read issued invoice items" on public.crm_invoice_items as permissive for select to public
  using ((invoice_id IN ( SELECT crm_invoices.id
   FROM crm_invoices
  WHERE ((crm_invoices.organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)) AND (crm_invoices.status = ANY (ARRAY['issued'::text, 'partially_paid'::text, 'paid'::text, 'overdue'::text, 'refunded'::text])) AND (crm_invoices.deleted_at IS NULL)))));
create policy "finance manages invoice items" on public.crm_invoice_items as permissive for all to public
  using (crm_is_finance())
  with check (crm_is_finance());
create policy "staff read invoice items" on public.crm_invoice_items as permissive for select to public
  using (crm_is_staff());
create policy "clients read issued invoices" on public.crm_invoices as permissive for select to public
  using (((organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)) AND (status = ANY (ARRAY['issued'::text, 'partially_paid'::text, 'paid'::text, 'overdue'::text, 'refunded'::text])) AND (deleted_at IS NULL)));
create policy "finance manages invoices" on public.crm_invoices as permissive for all to public
  using ((crm_is_finance() AND (deleted_at IS NULL)))
  with check (crm_is_finance());
create policy "staff read invoices" on public.crm_invoices as permissive for select to public
  using ((crm_is_staff() AND (deleted_at IS NULL)));
create policy "governance manages job roles" on public.crm_job_roles as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'hr_manager'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'hr_manager'::text]));
create policy "staff read job roles" on public.crm_job_roles as permissive for select to public
  using (crm_is_staff());
create policy "users read own login history" on public.crm_login_history as permissive for select to public
  using (((user_id = auth.uid()) OR crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'read_only_auditor'::text])));
create policy "notif_own_read" on public.crm_notifications as permissive for select to public
  using ((user_id = auth.uid()));
create policy "notif_own_update" on public.crm_notifications as permissive for update to public
  using ((user_id = auth.uid()))
  with check ((user_id = auth.uid()));
create policy "staff full access opportunities" on public.crm_opportunities as permissive for all to public
  using ((crm_is_staff() AND (deleted_at IS NULL)))
  with check (crm_is_staff());
create policy "staff access opportunity activity" on public.crm_opportunity_activity as permissive for all to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "clients read visible order events" on public.crm_order_events as permissive for select to public
  using (((visibility = ANY (ARRAY['client_visible'::text, 'client_action_required'::text])) AND (order_id IN ( SELECT crm_orders.id
   FROM crm_orders
  WHERE ((crm_orders.organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)) AND (crm_orders.deleted_at IS NULL))))));
create policy "staff full access order events" on public.crm_order_events as permissive for all to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "clients read own order items" on public.crm_order_items as permissive for select to public
  using ((order_id IN ( SELECT crm_orders.id
   FROM crm_orders
  WHERE ((crm_orders.organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)) AND (crm_orders.deleted_at IS NULL)))));
create policy "staff full access order items" on public.crm_order_items as permissive for all to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "om_client_read" on public.crm_order_milestones as permissive for select to public
  using ((client_visible AND (EXISTS ( SELECT 1
   FROM (crm_orders o
     JOIN crm_portal_members pm ON ((pm.organization_id = o.organization_id)))
  WHERE ((o.id = crm_order_milestones.order_id) AND (pm.user_id = auth.uid()))))));
create policy "om_staff" on public.crm_order_milestones as permissive for all to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "ot_staff" on public.crm_order_tracking as permissive for all to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "staff full access orders" on public.crm_orders as permissive for all to public
  using ((crm_is_staff() AND (deleted_at IS NULL)))
  with check (crm_is_staff());
create policy "staff full access orgs" on public.crm_organizations as permissive for all to public
  using ((crm_is_staff() AND (deleted_at IS NULL)))
  with check (crm_is_staff());
create policy "governance manages osc" on public.crm_outsourced_categories as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'operations_manager'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'operations_manager'::text]));
create policy "staff read osc" on public.crm_outsourced_categories as permissive for select to public
  using (crm_is_staff());
create policy "finance manages allocations" on public.crm_payment_allocations as permissive for all to public
  using (crm_is_finance())
  with check (crm_is_finance());
create policy "staff read allocations" on public.crm_payment_allocations as permissive for select to public
  using (crm_is_staff());
create policy "clients read own verified payments" on public.crm_payments as permissive for select to public
  using (((organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)) AND (is_verified = true) AND (deleted_at IS NULL)));
create policy "finance manages payments" on public.crm_payments as permissive for all to public
  using ((crm_is_finance() AND (deleted_at IS NULL)))
  with check (crm_is_finance());
create policy "staff read payments" on public.crm_payments as permissive for select to public
  using ((crm_is_staff() AND (deleted_at IS NULL)));
create policy "admin manages portal members" on public.crm_portal_members as permissive for all to public
  using (crm_has_role(ARRAY['super_admin'::text, 'ceo'::text, 'operations_manager'::text]))
  with check (crm_has_role(ARRAY['super_admin'::text, 'ceo'::text, 'operations_manager'::text]));
create policy "members read own membership" on public.crm_portal_members as permissive for select to public
  using ((user_id = auth.uid()));
create policy "clients read visible milestones" on public.crm_project_milestones as permissive for select to public
  using (((visibility = ANY (ARRAY['client_visible'::text, 'client_action_required'::text])) AND (project_id IN ( SELECT crm_projects.id
   FROM crm_projects
  WHERE ((crm_projects.organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)) AND (crm_projects.deleted_at IS NULL))))));
create policy "staff full access milestones" on public.crm_project_milestones as permissive for all to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "staff full access projects" on public.crm_projects as permissive for all to public
  using ((crm_is_staff() AND (deleted_at IS NULL)))
  with check (crm_is_staff());
create policy "staff full access prospects" on public.crm_prospects as permissive for all to public
  using ((crm_is_staff() AND (deleted_at IS NULL)))
  with check (crm_is_staff());
create policy "staff access approvals" on public.crm_quotation_approvals as permissive for all to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "clients read issued quotation items" on public.crm_quotation_items as permissive for select to public
  using ((quotation_id IN ( SELECT crm_quotations.id
   FROM crm_quotations
  WHERE ((crm_quotations.organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)) AND (crm_quotations.status = ANY (ARRAY['issued'::text, 'viewed'::text, 'revision_requested'::text, 'accepted'::text, 'rejected'::text, 'expired'::text, 'converted_to_order'::text])) AND (crm_quotations.deleted_at IS NULL)))));
create policy "staff full access quotation items" on public.crm_quotation_items as permissive for all to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "clients read issued quotations" on public.crm_quotations as permissive for select to public
  using (((organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)) AND (status = ANY (ARRAY['issued'::text, 'viewed'::text, 'revision_requested'::text, 'accepted'::text, 'rejected'::text, 'expired'::text, 'converted_to_order'::text])) AND (deleted_at IS NULL)));
create policy "staff full access quotations" on public.crm_quotations as permissive for all to public
  using ((crm_is_staff() AND (deleted_at IS NULL)))
  with check (crm_is_staff());
create policy "clients read own receipts" on public.crm_receipts as permissive for select to public
  using ((organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)));
create policy "finance manages receipts" on public.crm_receipts as permissive for all to public
  using (crm_is_finance())
  with check (crm_is_finance());
create policy "assign_mgmt_write" on public.crm_record_assignments as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]));
create policy "assign_staff_read" on public.crm_record_assignments as permissive for select to public
  using (crm_is_staff());
create policy "rm_policy_read" on public.crm_rm_policy as permissive for select to public
  using (crm_is_staff());
create policy "rm_policy_write" on public.crm_rm_policy as permissive for update to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]));
create policy "governance manages branches" on public.crm_service_branches as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]));
create policy "staff read branches" on public.crm_service_branches as permissive for select to public
  using (crm_is_staff());
create policy "smt_staff_all" on public.crm_service_milestone_templates as permissive for all to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "governance deletes offers" on public.crm_service_offers as permissive for delete to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]));
create policy "managers edit offers" on public.crm_service_offers as permissive for update to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'operations_manager'::text, 'project_manager'::text, 'trade_sourcing_manager'::text, 'customs_manager'::text]));
create policy "staff create offers" on public.crm_service_offers as permissive for insert to public
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'operations_manager'::text, 'project_manager'::text, 'trade_sourcing_manager'::text, 'customs_manager'::text]));
create policy "staff read offers" on public.crm_service_offers as permissive for select to public
  using ((crm_is_staff() AND (deleted_at IS NULL)));
create policy "finance reads bank" on public.crm_service_provider_bank as permissive for select to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'finance_manager'::text]));
create policy "finance writes bank" on public.crm_service_provider_bank as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'finance_manager'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'finance_manager'::text]));
create policy "governance deletes providers" on public.crm_service_providers as permissive for delete to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]));
create policy "managers edit providers" on public.crm_service_providers as permissive for update to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'operations_manager'::text, 'project_manager'::text, 'trade_sourcing_manager'::text, 'customs_manager'::text]));
create policy "staff create providers" on public.crm_service_providers as permissive for insert to public
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'operations_manager'::text, 'project_manager'::text, 'trade_sourcing_manager'::text, 'customs_manager'::text]));
create policy "staff read providers" on public.crm_service_providers as permissive for select to public
  using ((crm_is_staff() AND (deleted_at IS NULL)));
create policy "admin manages services" on public.crm_services as permissive for all to public
  using (crm_has_role(ARRAY['super_admin'::text, 'ceo'::text, 'operations_manager'::text]))
  with check (crm_has_role(ARRAY['super_admin'::text, 'ceo'::text, 'operations_manager'::text]));
create policy "public read active services" on public.crm_services as permissive for select to public
  using (((is_active = true) OR crm_is_staff()));
create policy "public reads active services" on public.crm_services as permissive for select to anon, authenticated
  using ((is_active = true));
create policy "admin writes settings" on public.crm_settings as permissive for all to public
  using (crm_has_role(ARRAY['super_admin'::text, 'ceo'::text]))
  with check (crm_has_role(ARRAY['super_admin'::text, 'ceo'::text]));
create policy "staff read settings" on public.crm_settings as permissive for select to public
  using (crm_is_staff());
create policy "staff full access shipments" on public.crm_shipments as permissive for all to public
  using ((crm_is_staff() AND (deleted_at IS NULL)))
  with check (crm_is_staff());
create policy "admin manages staff roles" on public.crm_staff_roles as permissive for all to public
  using (is_admin())
  with check (is_admin());
create policy "owner manages staff roles" on public.crm_staff_roles as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text]))
  with check (crm_has_role(ARRAY['owner'::text]));
create policy "staff read own roles" on public.crm_staff_roles as permissive for select to public
  using ((user_id = auth.uid()));
create policy "crm_stockists_staff_all" on public.crm_stockists as permissive for all to public
  using (crm_is_staff())
  with check (crm_is_staff());
create policy "finance reads subscription prices" on public.crm_subscription_price_history as permissive for select to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]));
create policy "finance reads subscriptions" on public.crm_subscriptions as permissive for select to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]));
create policy "governance manages subscriptions" on public.crm_subscriptions as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]));
create policy "staff full access supplier offers" on public.crm_supplier_offers as permissive for all to public
  using ((crm_is_staff() AND (deleted_at IS NULL)))
  with check (crm_is_staff());
create policy "management manages timesheets" on public.crm_timesheets as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text]));
create policy "staff amend own hours" on public.crm_timesheets as permissive for update to public
  using ((entered_by = auth.uid()))
  with check ((entered_by = auth.uid()));
create policy "staff log own hours" on public.crm_timesheets as permissive for insert to public
  with check ((crm_is_staff() AND (entered_by = auth.uid()) AND (EXISTS ( SELECT 1
   FROM crm_employee_costs ec
  WHERE ((ec.id = crm_timesheets.employee_cost_id) AND (ec.user_id = auth.uid()))))));
create policy "staff remove own hours" on public.crm_timesheets as permissive for delete to public
  using ((entered_by = auth.uid()));
create policy "tp_read" on public.crm_tracking_policy as permissive for select to public
  using (crm_is_staff());
create policy "tp_write" on public.crm_tracking_policy as permissive for update to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]));
create policy "tts_read" on public.crm_tracking_template_steps as permissive for select to public
  using (crm_is_staff());
create policy "tts_write" on public.crm_tracking_template_steps as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]));
create policy "tt_read" on public.crm_tracking_templates as permissive for select to public
  using (crm_is_staff());
create policy "tt_write" on public.crm_tracking_templates as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text]));
create policy "staff full access vendors" on public.crm_vendors as permissive for all to public
  using ((crm_is_staff() AND (deleted_at IS NULL)))
  with check (crm_is_staff());
create policy "admin_insert_topics" on public.featured_topics as permissive for insert to authenticated
  with check (true);
create policy "admin_read_all_topics" on public.featured_topics as permissive for select to authenticated
  using (true);
create policy "admin_update_topics" on public.featured_topics as permissive for update to authenticated
  using (true);
create policy "public_read_active_topic" on public.featured_topics as permissive for select to anon
  using ((is_active = true));
create policy "medical manages adverse events" on public.pharma_adverse_events as permissive for all to public
  using ((pharma_can('pharma.view_medical'::text) OR pharma_can('pharma.admin'::text)))
  with check ((pharma_can('pharma.view_medical'::text) OR pharma_can('pharma.admin'::text)));
create policy "medical reads adverse events" on public.pharma_adverse_events as permissive for select to public
  using ((pharma_can('pharma.view_medical'::text) OR pharma_can('pharma.admin'::text)));
create policy "manage campaigns" on public.pharma_campaigns as permissive for all to public
  using ((pharma_editor() OR pharma_can('pharma.manage_field'::text)))
  with check ((pharma_editor() OR pharma_can('pharma.manage_field'::text)));
create policy "read campaigns" on public.pharma_campaigns as permissive for select to public
  using ((pharma_can('pharma.view'::text) AND (deleted_at IS NULL)));
create policy "manage pharma companies" on public.pharma_companies as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read pharma companies" on public.pharma_companies as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage company contacts" on public.pharma_company_contacts as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read company contacts" on public.pharma_company_contacts as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage complaints" on public.pharma_complaints as permissive for all to public
  using ((pharma_editor() OR pharma_can('pharma.manage_field'::text)))
  with check ((pharma_editor() OR pharma_can('pharma.manage_field'::text)));
create policy "read complaints" on public.pharma_complaints as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage dist prod" on public.pharma_distributor_products as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read dist prod" on public.pharma_distributor_products as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage dist terr" on public.pharma_distributor_territories as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read dist terr" on public.pharma_distributor_territories as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage distributors" on public.pharma_distributors as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read distributors" on public.pharma_distributors as permissive for select to public
  using ((pharma_can('pharma.view'::text) AND (deleted_at IS NULL)));
create policy "manage affiliations" on public.pharma_doctor_affiliations as permissive for all to public
  using ((pharma_editor() OR pharma_can('pharma.manage_field'::text)))
  with check ((pharma_editor() OR pharma_can('pharma.manage_field'::text)));
create policy "read affiliations" on public.pharma_doctor_affiliations as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage doc products" on public.pharma_doctor_products as permissive for all to public
  using ((pharma_editor() OR pharma_can('pharma.manage_field'::text)))
  with check ((pharma_editor() OR pharma_can('pharma.manage_field'::text)));
create policy "read doc products" on public.pharma_doctor_products as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage doctors" on public.pharma_doctors as permissive for all to public
  using ((pharma_editor() OR pharma_can('pharma.manage_field'::text)))
  with check ((pharma_editor() OR pharma_can('pharma.manage_field'::text)));
create policy "read doctors" on public.pharma_doctors as permissive for select to public
  using ((pharma_can('pharma.view'::text) AND (deleted_at IS NULL)));
create policy "manage dosage forms" on public.pharma_dosage_forms as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read dosage forms" on public.pharma_dosage_forms as permissive for select to public
  using (crm_is_staff());
create policy "manage spend" on public.pharma_engagement_spend as permissive for all to public
  using ((pharma_can('pharma.view_financial'::text) OR pharma_can('pharma.admin'::text)))
  with check ((pharma_can('pharma.view_financial'::text) OR pharma_can('pharma.admin'::text)));
create policy "read spend" on public.pharma_engagement_spend as permissive for select to public
  using ((pharma_can('pharma.view_financial'::text) OR pharma_can('pharma.admin'::text)));
create policy "manage expense dims" on public.pharma_expense_dimensions as permissive for all to public
  using ((pharma_can('pharma.view_financial'::text) OR pharma_can('pharma.admin'::text)))
  with check ((pharma_can('pharma.view_financial'::text) OR pharma_can('pharma.admin'::text)));
create policy "read expense dims" on public.pharma_expense_dimensions as permissive for select to public
  using ((pharma_can('pharma.view_financial'::text) OR pharma_can('pharma.admin'::text)));
create policy "manage field force" on public.pharma_field_force as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read field force" on public.pharma_field_force as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage hospitals" on public.pharma_hospitals as permissive for all to public
  using ((pharma_editor() OR pharma_can('pharma.manage_field'::text)))
  with check ((pharma_editor() OR pharma_can('pharma.manage_field'::text)));
create policy "read hospitals" on public.pharma_hospitals as permissive for select to public
  using ((pharma_can('pharma.view'::text) AND (deleted_at IS NULL)));
create policy "manage inventory" on public.pharma_inventory_batches as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read inventory" on public.pharma_inventory_batches as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage movements" on public.pharma_inventory_movements as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read movements" on public.pharma_inventory_movements as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage pharma invoices" on public.pharma_invoices as permissive for all to public
  using ((pharma_can('pharma.view_financial'::text) OR pharma_can('pharma.admin'::text)))
  with check ((pharma_can('pharma.view_financial'::text) OR pharma_can('pharma.admin'::text)));
create policy "read pharma invoices" on public.pharma_invoices as permissive for select to public
  using ((pharma_can('pharma.view_financial'::text) OR pharma_can('pharma.admin'::text)));
create policy "manage offer cats" on public.pharma_offer_categories as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read offer cats" on public.pharma_offer_categories as permissive for select to public
  using (crm_is_staff());
create policy "manage offer products" on public.pharma_offer_products as permissive for all to public
  using ((pharma_editor() OR pharma_can('pharma.manage_field'::text)))
  with check ((pharma_editor() OR pharma_can('pharma.manage_field'::text)));
create policy "read offer products" on public.pharma_offer_products as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage offer targets" on public.pharma_offer_targets as permissive for all to public
  using ((pharma_editor() OR pharma_can('pharma.manage_field'::text)))
  with check ((pharma_editor() OR pharma_can('pharma.manage_field'::text)));
create policy "read offer targets" on public.pharma_offer_targets as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage pharmacies" on public.pharma_pharmacies as permissive for all to public
  using ((pharma_editor() OR pharma_can('pharma.manage_field'::text)))
  with check ((pharma_editor() OR pharma_can('pharma.manage_field'::text)));
create policy "read pharmacies" on public.pharma_pharmacies as permissive for select to public
  using ((pharma_can('pharma.view'::text) AND (deleted_at IS NULL)));
create policy "manage plant caps" on public.pharma_plant_capabilities as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read plant caps" on public.pharma_plant_capabilities as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage plants" on public.pharma_plants as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read plants" on public.pharma_plants as permissive for select to public
  using ((pharma_can('pharma.view'::text) AND (deleted_at IS NULL)));
create policy "manage prices" on public.pharma_product_prices as permissive for all to public
  using ((pharma_can('pharma.view_financial'::text) OR pharma_can('pharma.admin'::text)))
  with check ((pharma_can('pharma.view_financial'::text) OR pharma_can('pharma.admin'::text)));
create policy "read prices" on public.pharma_product_prices as permissive for select to public
  using ((pharma_can('pharma.view_financial'::text) OR pharma_can('pharma.admin'::text)));
create policy "manage reg" on public.pharma_product_regulatory as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read reg" on public.pharma_product_regulatory as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage prod batches" on public.pharma_production_batches as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read prod batches" on public.pharma_production_batches as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage products" on public.pharma_products as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read products" on public.pharma_products as permissive for select to public
  using ((pharma_can('pharma.view'::text) AND (deleted_at IS NULL)));
create policy "manage offers" on public.pharma_promotional_offers as permissive for all to public
  using ((pharma_editor() OR pharma_can('pharma.manage_field'::text)))
  with check ((pharma_editor() OR pharma_can('pharma.manage_field'::text)));
create policy "read offers" on public.pharma_promotional_offers as permissive for select to public
  using ((pharma_can('pharma.view'::text) AND (deleted_at IS NULL)));
create policy "manage recalls" on public.pharma_recalls as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read recalls" on public.pharma_recalls as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage receipts" on public.pharma_receipts as permissive for all to public
  using ((pharma_can('pharma.view_financial'::text) OR pharma_can('pharma.admin'::text)))
  with check ((pharma_can('pharma.view_financial'::text) OR pharma_can('pharma.admin'::text)));
create policy "read receipts" on public.pharma_receipts as permissive for select to public
  using ((pharma_can('pharma.view_financial'::text) OR pharma_can('pharma.admin'::text)));
create policy "manage returns" on public.pharma_returns as permissive for all to public
  using ((pharma_editor() OR pharma_can('pharma.manage_field'::text)))
  with check ((pharma_editor() OR pharma_can('pharma.manage_field'::text)));
create policy "read returns" on public.pharma_returns as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "governance manages pharma perms" on public.pharma_role_permissions as permissive for all to public
  using (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]))
  with check (crm_has_role(ARRAY['owner'::text, 'super_admin'::text]));
create policy "staff read pharma perms" on public.pharma_role_permissions as permissive for select to public
  using (crm_is_staff());
create policy "manage order items" on public.pharma_sales_order_items as permissive for all to public
  using ((pharma_editor() OR pharma_can('pharma.manage_field'::text)))
  with check ((pharma_editor() OR pharma_can('pharma.manage_field'::text)));
create policy "read order items" on public.pharma_sales_order_items as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage sales orders" on public.pharma_sales_orders as permissive for all to public
  using ((pharma_editor() OR pharma_can('pharma.manage_field'::text)))
  with check ((pharma_editor() OR pharma_can('pharma.manage_field'::text)));
create policy "read sales orders" on public.pharma_sales_orders as permissive for select to public
  using ((pharma_can('pharma.view'::text) AND (deleted_at IS NULL)));
create policy "manage sample items" on public.pharma_sample_items as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read sample items" on public.pharma_sample_items as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage sample txns" on public.pharma_sample_transactions as permissive for all to public
  using ((pharma_editor() OR pharma_can('pharma.manage_field'::text) OR (created_by = auth.uid())))
  with check ((pharma_editor() OR pharma_can('pharma.manage_field'::text) OR (created_by = auth.uid())));
create policy "read sample txns" on public.pharma_sample_transactions as permissive for select to public
  using ((pharma_can('pharma.view'::text) OR (created_by = auth.uid())));
create policy "manage tender products" on public.pharma_tender_products as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read tender products" on public.pharma_tender_products as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage tenders" on public.pharma_tenders as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read tenders" on public.pharma_tenders as permissive for select to public
  using ((pharma_can('pharma.view'::text) AND (deleted_at IS NULL)));
create policy "manage territories" on public.pharma_territories as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read territories" on public.pharma_territories as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage tc" on public.pharma_therapeutic_categories as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read tc" on public.pharma_therapeutic_categories as permissive for select to public
  using (crm_is_staff());
create policy "manage toll contracts" on public.pharma_toll_contracts as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read toll contracts" on public.pharma_toll_contracts as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "manage toll enq" on public.pharma_toll_enquiries as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read toll enq" on public.pharma_toll_enquiries as permissive for select to public
  using ((pharma_can('pharma.view'::text) AND (deleted_at IS NULL)));
create policy "manage toll offers" on public.pharma_toll_offers as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read toll offers" on public.pharma_toll_offers as permissive for select to public
  using ((pharma_can('pharma.view_financial'::text) OR pharma_can('pharma.admin'::text)));
create policy "own visit plans" on public.pharma_visit_plans as permissive for all to public
  using (((user_id = auth.uid()) OR pharma_editor()))
  with check (((user_id = auth.uid()) OR pharma_editor()));
create policy "read visit plans" on public.pharma_visit_plans as permissive for select to public
  using ((pharma_can('pharma.view'::text) OR (user_id = auth.uid())));
create policy "log visits" on public.pharma_visits as permissive for all to public
  using (((visited_by = auth.uid()) OR pharma_editor()))
  with check (((visited_by = auth.uid()) OR pharma_editor()));
create policy "read visits" on public.pharma_visits as permissive for select to public
  using ((pharma_can('pharma.view'::text) OR (visited_by = auth.uid())));
create policy "manage warehouses" on public.pharma_warehouses as permissive for all to public
  using (pharma_editor())
  with check (pharma_editor());
create policy "read warehouses" on public.pharma_warehouses as permissive for select to public
  using (pharma_can('pharma.view'::text));
create policy "admin_manage_profiles" on public.profiles as permissive for all to authenticated
  using (is_admin());
create policy "own_profile" on public.profiles as permissive for select to authenticated
  using ((id = auth.uid()));
create policy "social_assets_mgr_all" on public.social_assets as permissive for all to public
  using (social_is_manager())
  with check (social_is_manager());
create policy "social_audit_staff_read" on public.social_audit_log as permissive for select to public
  using (social_is_staff());
create policy "social_brand_voice_mgr_all" on public.social_brand_voice as permissive for all to public
  using (social_is_manager())
  with check (social_is_manager());
create policy "social_channels_mgr_all" on public.social_channels as permissive for all to public
  using (social_is_manager())
  with check (social_is_manager());
create policy "social_content_calendar_mgr_write" on public.social_content_calendar as permissive for all to public
  using (social_is_manager())
  with check (social_is_manager());
create policy "social_content_calendar_staff_read" on public.social_content_calendar as permissive for select to public
  using (social_is_staff());
create policy "social_engagement_mgr_write" on public.social_engagement as permissive for all to public
  using (social_is_manager())
  with check (social_is_manager());
create policy "social_engagement_staff_read" on public.social_engagement as permissive for select to public
  using (social_is_staff());
create policy "social_posts_mgr_write" on public.social_posts as permissive for all to public
  using (social_is_manager())
  with check (social_is_manager());
create policy "social_posts_staff_read" on public.social_posts as permissive for select to public
  using (social_is_staff());
create policy "social_settings_mgr_all" on public.social_settings as permissive for all to public
  using (social_is_manager())
  with check (social_is_manager());
create policy "admin_full_assignments" on public.training_assignments as permissive for all to authenticated
  using (is_admin());
create policy "client_update_own_assignment" on public.training_assignments as permissive for update to authenticated
  using ((client_id IN ( SELECT profiles.client_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))))
  with check ((client_id IN ( SELECT profiles.client_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
create policy "client_view_own_assignments" on public.training_assignments as permissive for select to authenticated
  using ((client_id IN ( SELECT profiles.client_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
create policy "admin_full_certificates" on public.training_certificates as permissive for all to authenticated
  using (is_admin());
create policy "client_insert_own_certificate" on public.training_certificates as permissive for insert to authenticated
  with check ((client_id IN ( SELECT profiles.client_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
create policy "client_view_own_certificates" on public.training_certificates as permissive for select to authenticated
  using ((client_id IN ( SELECT profiles.client_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
create policy "admin_full_modules" on public.training_modules as permissive for all to authenticated
  using (is_admin());
create policy "client_view_assigned_modules" on public.training_modules as permissive for select to authenticated
  using ((id IN ( SELECT training_assignments.module_id
   FROM training_assignments
  WHERE (training_assignments.client_id IN ( SELECT profiles.client_id
           FROM profiles
          WHERE (profiles.id = auth.uid()))))));
create policy "admin_full_attempts" on public.training_quiz_attempts as permissive for all to authenticated
  using (is_admin());
create policy "client_manage_own_attempts" on public.training_quiz_attempts as permissive for all to authenticated
  using ((client_id IN ( SELECT profiles.client_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))))
  with check ((client_id IN ( SELECT profiles.client_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
create policy "admin_full_questions" on public.training_quiz_questions as permissive for all to authenticated
  using (is_admin());
create policy "client_view_questions_assigned" on public.training_quiz_questions as permissive for select to authenticated
  using ((module_id IN ( SELECT training_assignments.module_id
   FROM training_assignments
  WHERE (training_assignments.client_id IN ( SELECT profiles.client_id
           FROM profiles
          WHERE (profiles.id = auth.uid()))))));

-- ---------------------------------------------------------------------------
-- Policies: schema storage (19 = 1 on storage.buckets + 18 on storage.objects)
-- Buckets themselves (crm-private, finance-docs, ...) are rows in
-- storage.buckets and are NOT created here.
-- ---------------------------------------------------------------------------

create policy "authenticated read buckets" on storage.buckets as permissive for select to authenticated
  using (true);
create policy "admin writes crm private" on storage.objects as permissive for insert to public
  with check (((bucket_id = 'crm-private'::text) AND crm_has_role(ARRAY['super_admin'::text, 'ceo'::text])));
create policy "agent reads own lane" on storage.objects as permissive for select to public
  using (((bucket_id = 'crm-private'::text) AND (name ~~ 'attachments/agent/%'::text) AND crm_is_agent()));
-- NOTE: on production this policy's path contains an unguessable folder token
-- (it is the only thing gating anonymous uploads into the agent lane). The
-- token is redacted here; substitute a fresh random token on a new project.
create policy "agent uploads own lane" on storage.objects as permissive for insert to public
  with check (((bucket_id = 'crm-private'::text) AND (name ~~ 'attachments/agent/<REDACTED-LANE-TOKEN>/%'::text)));
create policy "att client read own visible" on storage.objects as permissive for select to public
  using (((bucket_id = 'crm-private'::text) AND (name ~~ 'attachments/%'::text) AND (EXISTS ( SELECT 1
   FROM crm_attachments a
  WHERE ((a.file_path = objects.name) AND (a.deleted_at IS NULL) AND (a.visibility_scope = ANY (ARRAY['client_visible'::text, 'client_uploaded'::text])) AND (a.organization_id IN ( SELECT pm.organization_id
           FROM crm_portal_members pm
          WHERE (pm.user_id = auth.uid()))))))));
create policy "att client upload own folder" on storage.objects as permissive for insert to public
  with check (((bucket_id = 'crm-private'::text) AND (name ~~ 'attachments/portal/%'::text) AND ((split_part(name, '/'::text, 3))::uuid IN ( SELECT pm.organization_id
   FROM crm_portal_members pm
  WHERE (pm.user_id = auth.uid())))));
create policy "att staff manage" on storage.objects as permissive for all to public
  using (((bucket_id = 'crm-private'::text) AND (name ~~ 'attachments/%'::text) AND crm_is_staff()))
  with check (((bucket_id = 'crm-private'::text) AND (name ~~ 'attachments/%'::text) AND crm_is_staff()));
create policy "clients read own payment proofs" on storage.objects as permissive for select to public
  using (((bucket_id = 'crm-private'::text) AND ((storage.foldername(name))[1] = 'payment-proofs'::text) AND ((storage.foldername(name))[2] IN ( SELECT (crm_my_org_ids())::text AS crm_my_org_ids))));
create policy "clients read signature on issued quotation" on storage.objects as permissive for select to public
  using (((bucket_id = 'crm-private'::text) AND (name = 'signature/signature-light.png'::text) AND (EXISTS ( SELECT 1
   FROM crm_quotations
  WHERE ((crm_quotations.organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)) AND (crm_quotations.approval_status = ANY (ARRAY['approved'::text, 'not_required'::text])) AND (crm_quotations.status = ANY (ARRAY['issued'::text, 'viewed'::text, 'accepted'::text, 'converted_to_order'::text])) AND (crm_quotations.deleted_at IS NULL))))));
create policy "clients upload own payment proofs" on storage.objects as permissive for insert to public
  with check (((bucket_id = 'crm-private'::text) AND ((storage.foldername(name))[1] = 'payment-proofs'::text) AND ((storage.foldername(name))[2] IN ( SELECT (crm_my_org_ids())::text AS crm_my_org_ids))));
create policy "daily receipts insert" on storage.objects as permissive for insert to public
  with check (((bucket_id = 'finance-docs'::text) AND crm_is_staff() AND ((storage.foldername(name))[1] = 'daily'::text)));
create policy "daily receipts read own" on storage.objects as permissive for select to public
  using (((bucket_id = 'finance-docs'::text) AND ((storage.foldername(name))[1] = 'daily'::text) AND (owner = auth.uid())));
create policy "finance docs delete" on storage.objects as permissive for delete to public
  using (((bucket_id = 'finance-docs'::text) AND crm_has_role(ARRAY['owner'::text, 'super_admin'::text])));
create policy "finance docs insert" on storage.objects as permissive for insert to public
  with check (((bucket_id = 'finance-docs'::text) AND crm_has_role(ARRAY['owner'::text, 'super_admin'::text])));
create policy "finance docs read" on storage.objects as permissive for select to public
  using (((bucket_id = 'finance-docs'::text) AND crm_has_role(ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text])));
create policy "finance docs update" on storage.objects as permissive for update to public
  using (((bucket_id = 'finance-docs'::text) AND crm_has_role(ARRAY['owner'::text, 'super_admin'::text])));
create policy "jco document seal assets readable" on storage.objects as permissive for select to public
  using (((bucket_id = 'crm-private'::text) AND ((name ~~ 'signature/%'::text) OR (name ~~ 'stamp/%'::text)) AND (crm_is_staff() OR (EXISTS ( SELECT 1
   FROM (crm_portal_members pm
     JOIN crm_quotations q ON ((q.organization_id = pm.organization_id)))
  WHERE ((pm.user_id = auth.uid()) AND (q.status = ANY (ARRAY['issued'::text, 'viewed'::text, 'accepted'::text, 'converted_to_order'::text]))))))));
create policy "jco staff manage attachment objects" on storage.objects as permissive for all to public
  using (((bucket_id = 'crm-private'::text) AND (name ~~ 'attachments/%'::text) AND crm_is_staff()))
  with check (((bucket_id = 'crm-private'::text) AND (name ~~ 'attachments/%'::text) AND crm_is_staff()));
create policy "staff read crm private" on storage.objects as permissive for select to public
  using (((bucket_id = 'crm-private'::text) AND crm_is_staff()));
