-- Baseline 02: tables in schema public, then constraints.
-- Reconstructed from pg_attribute / pg_attrdef (format_type, pg_get_expr).
-- Standalone sequences used by column defaults are created first.
-- serial-style sequences (owned by a column) are created first as well and
-- re-linked with "alter sequence ... owned by" after the tables.
-- Identity columns create their own sequences.

create sequence if not exists public.ai_conversation_seq as bigint increment by 1 minvalue 1 maxvalue 9223372036854775807 start with 1 cache 1;
create sequence if not exists public.ai_prompt_version_seq as bigint increment by 1 minvalue 1 maxvalue 9223372036854775807 start with 1 cache 1;
create sequence if not exists public.ai_public_rate_events_id_seq as bigint increment by 1 minvalue 1 maxvalue 9223372036854775807 start with 1 cache 1;
create sequence if not exists public.crm_stockists_fallback_seq as bigint increment by 1 minvalue 1 maxvalue 9223372036854775807 start with 1 cache 1;

create table if not exists public.ai_agent_configs (
  id uuid not null default gen_random_uuid(),
  singleton boolean not null default true,
  is_enabled boolean not null default true,
  proactive_enabled boolean not null default true,
  agent_name text not null default 'Jabran & Co. Advisory Agent'::text,
  greeting text not null default 'Welcome to Jabran & Co. I’m the firm’s AI Advisory Agent — I can help identify the right service, answer initial questions, collect your requirements and connect you with a specialist. How can I assist?'::text,
  disclosure text not null default 'You are chatting with Jabran & Co.’s AI Advisory Agent. Please don’t share passwords or payment-card details.'::text,
  proactive_seconds integer not null default 45,
  proactive_scroll_pct integer not null default 60,
  frequency_cap_hours integer not null default 24,
  rate_per_minute integer not null default 6,
  max_messages integer not null default 40,
  max_message_chars integer not null default 2000,
  daily_token_budget integer not null default 200000,
  model_public text,
  temperature numeric not null default 0.3,
  updated_by uuid,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.ai_agent_feedback (
  id uuid not null default gen_random_uuid(),
  conversation_id uuid not null,
  message_id uuid,
  rating integer,
  feedback text,
  submitted_by text default 'visitor'::text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.ai_agent_handoffs (
  id uuid not null default gen_random_uuid(),
  conversation_id uuid not null,
  requested_by text not null default 'ai'::text,
  handoff_reason text,
  assigned_to uuid,
  status text not null default 'open'::text,
  requested_at timestamp with time zone not null default now(),
  accepted_at timestamp with time zone,
  resolved_at timestamp with time zone,
  resolution_notes text
);

create table if not exists public.ai_conversation_summaries (
  id uuid not null default gen_random_uuid(),
  conversation_id uuid not null,
  summary text,
  identified_needs text,
  budget_range text,
  timeline text,
  decision_role text,
  recommended_service text,
  recommended_next_action text,
  risk_flags text,
  generated_at timestamp with time zone not null default now(),
  approved_by uuid,
  approved_at timestamp with time zone
);

create table if not exists public.ai_conversations (
  id uuid not null default gen_random_uuid(),
  conversation_reference text not null default ((('JCO-CNV-'::text || to_char(now(), 'YYYY'::text)) || '-'::text) || lpad((nextval('ai_conversation_seq'::regclass))::text, 4, '0'::text)),
  visitor_token uuid not null default gen_random_uuid(),
  channel text not null default 'web_widget'::text,
  conversation_type text not null default 'public'::text,
  visitor_id text,
  session_id text,
  user_id uuid,
  organization_id uuid,
  prospect_id uuid,
  enquiry_id uuid,
  opportunity_id uuid,
  order_id uuid,
  chat_lead_id uuid,
  assigned_user_id uuid,
  assigned_rm_id uuid,
  service_context text,
  status text not null default 'ai_active'::text,
  priority text not null default 'normal'::text,
  lead_score integer,
  lead_class text,
  sentiment text,
  intent text,
  language text default 'en'::text,
  source_url text,
  landing_page text,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  consent_status text default 'implied'::text,
  contact_name text,
  contact_email text,
  contact_phone text,
  contact_company text,
  contact_country text,
  started_at timestamp with time zone not null default now(),
  last_message_at timestamp with time zone not null default now(),
  closed_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.ai_messages (
  id uuid not null default gen_random_uuid(),
  conversation_id uuid not null,
  sender_type text not null,
  sender_user_id uuid,
  message_type text not null default 'text'::text,
  content text,
  attachment_id uuid,
  model_name text,
  prompt_version text,
  token_usage integer,
  confidence_score numeric,
  requires_human_review boolean not null default false,
  moderation_status text default 'clear'::text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.ai_prompt_versions (
  id uuid not null default gen_random_uuid(),
  agent text not null default 'public'::text,
  version_number integer not null default nextval('ai_prompt_version_seq'::regclass),
  prompt_text text not null,
  prompt_hash text generated always as (md5(prompt_text)) stored,
  change_reason text,
  changed_by uuid default auth.uid(),
  approval_status text not null default 'approved'::text,
  is_active boolean not null default false,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.ai_public_rate_events (
  id bigint not null default nextval('ai_public_rate_events_id_seq'::regclass),
  bucket text not null,
  client_key text not null,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.ai_usage_log (
  id uuid not null default gen_random_uuid(),
  conversation_id uuid,
  provider text,
  model text,
  prompt_version integer,
  token_usage integer,
  latency_ms integer,
  error text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.analytics_accounts (
  id uuid not null default gen_random_uuid(),
  connection_id uuid not null,
  external_account_id text not null,
  name text,
  currency text,
  timezone text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.analytics_alerts (
  id uuid not null default gen_random_uuid(),
  rule_code text not null,
  severity text not null default 'warning'::text,
  title text not null,
  detail text,
  is_active boolean not null default true,
  raised_at timestamp with time zone not null default now(),
  resolved_at timestamp with time zone
);

create table if not exists public.analytics_attribution (
  id uuid not null default gen_random_uuid(),
  entity text not null,
  entity_id uuid not null,
  org_id uuid,
  first_touch jsonb not null default '{}'::jsonb,
  last_touch jsonb not null default '{}'::jsonb,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  utm_content text,
  utm_term text,
  referrer text,
  landing_page text,
  click_id text,
  confidence text not null default 'unknown'::text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.analytics_campaigns (
  id uuid not null default gen_random_uuid(),
  source text not null,
  external_id text not null,
  name text,
  status text,
  period_start date,
  period_end date,
  impressions numeric,
  clicks numeric,
  conversions numeric,
  spend numeric,
  currency text,
  ingested_at timestamp with time zone not null default now()
);

create table if not exists public.analytics_connections (
  id uuid not null default gen_random_uuid(),
  platform text not null,
  display_name text not null,
  status text not null default 'not_connected'::text,
  account_ref text,
  scopes jsonb not null default '[]'::jsonb,
  setup_note text,
  connected_by uuid,
  connected_at timestamp with time zone,
  last_sync_at timestamp with time zone,
  next_sync_at timestamp with time zone,
  token_status text,
  last_error text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.analytics_content_metrics (
  id uuid not null default gen_random_uuid(),
  source text not null,
  metric_date date not null,
  page_path text,
  search_query text,
  impressions numeric,
  clicks numeric,
  ctr numeric,
  avg_position numeric,
  sessions numeric,
  conversions numeric,
  ingested_at timestamp with time zone not null default now()
);

create table if not exists public.analytics_conversion_events (
  id uuid not null default gen_random_uuid(),
  source text not null,
  event_name text not null,
  occurred_at timestamp with time zone not null,
  org_id uuid,
  entity text,
  entity_id uuid,
  value numeric,
  currency text,
  properties jsonb not null default '{}'::jsonb
);

create table if not exists public.analytics_daily_metrics (
  id uuid not null default gen_random_uuid(),
  source text not null,
  metric_date date not null,
  org_id uuid,
  dimension jsonb not null default '{}'::jsonb,
  users numeric,
  sessions numeric,
  engaged_sessions numeric,
  impressions numeric,
  clicks numeric,
  conversions numeric,
  spend numeric,
  currency text,
  ingested_at timestamp with time zone not null default now()
);

create table if not exists public.analytics_data_quality_events (
  id uuid not null default gen_random_uuid(),
  source text not null,
  event text not null,
  detail text,
  occurred_at timestamp with time zone not null default now()
);

create table if not exists public.analytics_fact_map (
  fact text not null,
  base_table text not null,
  columns jsonb not null default '{}'::jsonb,
  detected_at timestamp with time zone not null default now()
);

create table if not exists public.analytics_generated_reports (
  id uuid not null default gen_random_uuid(),
  created_by uuid not null default auth.uid(),
  title text not null,
  kind text not null default 'executive'::text,
  period_from date,
  period_to date,
  sources jsonb not null default '[]'::jsonb,
  body text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.analytics_metric_definitions (
  code text not null,
  label text not null,
  category text not null,
  unit text not null,
  formula text not null,
  source_fact text,
  needs_permission text,
  needs_source text,
  supports_timeseries boolean not null default false,
  supports_dimensions text[] not null default ARRAY[]::text[],
  sort_order integer not null default 100
);

create table if not exists public.analytics_oauth_states (
  state text not null,
  provider text not null,
  user_id uuid not null,
  code_verifier text,
  redirect_uri text not null,
  created_at timestamp with time zone not null default now(),
  expires_at timestamp with time zone not null default (now() + '00:10:00'::interval),
  used_at timestamp with time zone
);

create table if not exists public.analytics_oauth_tokens (
  provider text not null,
  ciphertext text not null,
  iv text not null,
  scopes jsonb not null default '[]'::jsonb,
  account_ref text,
  access_expires timestamp with time zone,
  connected_by uuid,
  connected_at timestamp with time zone not null default now(),
  rotated_at timestamp with time zone,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.analytics_prompt_history (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  prompt text not null,
  query_plan jsonb,
  answer text,
  sources jsonb not null default '[]'::jsonb,
  period_from date,
  period_to date,
  confidence text,
  error text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.analytics_role_permissions (
  role text not null,
  permission text not null,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.analytics_sync_jobs (
  id uuid not null default gen_random_uuid(),
  connection_id uuid not null,
  started_at timestamp with time zone not null default now(),
  finished_at timestamp with time zone,
  status text not null default 'running'::text,
  rows_ingested integer not null default 0,
  sync_cursor text,
  error text
);

create table if not exists public.audit_findings (
  id uuid not null default gen_random_uuid(),
  client_id uuid not null,
  category text not null,
  title text not null,
  description text,
  media_url text,
  severity text default 'medium'::text,
  recorded_at date not null default CURRENT_DATE,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.blog_posts (
  id uuid not null default gen_random_uuid(),
  author_name text not null,
  title text not null,
  body text not null,
  status text not null default 'pending'::text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.case_studies (
  id uuid not null default gen_random_uuid(),
  client_id uuid not null,
  client_display_name text not null,
  industry text,
  title text not null,
  problem text,
  diagnosis text,
  solution text,
  implementation text,
  results text,
  lessons text,
  status text not null default 'draft'::text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.case_study_approvals (
  case_study_id uuid not null,
  client_approved boolean not null default false,
  approved_at timestamp with time zone
);

create table if not exists public.client_actions (
  id uuid not null default gen_random_uuid(),
  client_id uuid not null,
  title text not null,
  description text,
  status text not null default 'not_started'::text,
  priority text not null default 'medium'::text,
  due_date date,
  assigned_to text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.client_documents (
  id uuid not null default gen_random_uuid(),
  client_id uuid not null,
  title text not null,
  url text not null,
  category text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.client_kpis (
  id uuid not null default gen_random_uuid(),
  client_id uuid not null,
  metric_name text not null,
  value text not null,
  unit text,
  recorded_at date not null default CURRENT_DATE,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.client_meetings (
  id uuid not null default gen_random_uuid(),
  client_id uuid not null,
  title text not null,
  meeting_datetime timestamp with time zone not null,
  meeting_link text,
  notes text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.client_reports (
  id uuid not null default gen_random_uuid(),
  client_id uuid not null,
  report_type text not null default 'monthly'::text,
  report_date date not null default CURRENT_DATE,
  baseline_summary text,
  current_performance text,
  improvements_achieved text,
  financial_savings text,
  risks text,
  next_steps text,
  recommendations text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.clients (
  id uuid not null default gen_random_uuid(),
  name text not null,
  industry text,
  status text not null default 'active'::text,
  start_date date,
  notes text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.contact_submissions (
  id uuid not null default gen_random_uuid(),
  name text not null,
  email text not null,
  message text not null,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_activity_events (
  id bigint not null generated always as identity,
  user_id uuid not null,
  event text not null,
  entity text,
  entity_id uuid,
  detail text,
  user_agent text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_agent_accounts (
  id uuid not null default gen_random_uuid(),
  agent_name text not null,
  user_id uuid not null,
  active boolean not null default true,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_ai_actions (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null default auth.uid(),
  request_text text not null,
  action_type text,
  intent jsonb,
  status text not null default 'proposed'::text,
  result_ref text,
  error text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.crm_ai_agents (
  id uuid not null default gen_random_uuid(),
  slug text not null,
  display_name text not null,
  role_title text not null,
  emoji text,
  status text not null default 'live'::text,
  model_chain text,
  runtime text,
  capabilities text[],
  scope text,
  guardrails text,
  sort_order integer not null default 100,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.crm_alert_dismissals (
  user_id uuid not null default auth.uid(),
  alert_key text not null,
  dismissed_at timestamp with time zone not null default now()
);

create table if not exists public.crm_allocation_rules (
  cost_pool text not null,
  method text not null,
  updated_by uuid default auth.uid(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.crm_allocation_targets (
  id uuid not null default gen_random_uuid(),
  order_id uuid not null,
  weight numeric(10,4) not null,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_attachment_categories (
  code text not null,
  label text not null,
  sort_order integer not null default 100,
  is_active boolean not null default true
);

create table if not exists public.crm_attachment_events (
  id uuid not null default gen_random_uuid(),
  attachment_id uuid,
  event_type text not null,
  detail text,
  actor uuid default auth.uid(),
  actor_type text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_attachment_policy (
  id boolean not null default true,
  allowed_extensions text[] not null default ARRAY['pdf'::text, 'png'::text, 'jpg'::text, 'jpeg'::text, 'webp'::text, 'doc'::text, 'docx'::text, 'xls'::text, 'xlsx'::text, 'csv'::text, 'txt'::text, 'ppt'::text, 'pptx'::text],
  blocked_extensions text[] not null default ARRAY['exe'::text, 'bat'::text, 'cmd'::text, 'js'::text, 'mjs'::text, 'sh'::text, 'php'::text, 'apk'::text, 'msi'::text, 'scr'::text, 'dll'::text, 'com'::text, 'vbs'::text, 'ps1'::text, 'jar'::text, 'docm'::text, 'xlsm'::text, 'pptm'::text, 'html'::text, 'htm'::text, 'svg'::text],
  max_image_bytes bigint not null default 10485760,
  max_document_bytes bigint not null default 26214400,
  max_client_bytes bigint not null default 10485760,
  updated_by uuid,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.crm_attachments (
  id uuid not null default gen_random_uuid(),
  module text not null,
  record_id uuid not null,
  file_path text not null,
  file_name text not null,
  label text,
  content_type text,
  size_bytes bigint,
  uploaded_by uuid not null default auth.uid(),
  created_at timestamp with time zone not null default now(),
  organization_id uuid,
  document_category text not null default 'other'::text,
  document_title text,
  description text,
  visibility_scope text not null default 'internal'::text,
  version_number integer not null default 1,
  is_current_version boolean not null default true,
  parent_attachment_id uuid,
  original_file_name text,
  file_extension text,
  uploaded_by_type text not null default 'staff'::text,
  source text not null default 'crm'::text,
  approval_status text not null default 'not_required'::text,
  approved_by uuid,
  approved_at timestamp with time zone,
  expires_at timestamp with time zone,
  is_confidential boolean not null default false,
  replacement_reason text,
  deleted_at timestamp with time zone,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.crm_audit_logs (
  id bigint not null generated always as identity,
  user_id uuid default auth.uid(),
  action text not null,
  entity text not null,
  entity_id text,
  before_value jsonb,
  after_value jsonb,
  occurred_at timestamp with time zone not null default now(),
  source text default 'crm'::text
);

create table if not exists public.crm_billing_bases (
  code text not null,
  name text not null,
  qty_label text not null,
  rate_label text not null,
  needs_qty boolean not null default true,
  allows_resources boolean not null default false,
  allows_overtime boolean not null default false,
  is_percentage boolean not null default false,
  sort_order integer not null default 100,
  is_active boolean not null default true
);

create table if not exists public.crm_budgets (
  id uuid not null default gen_random_uuid(),
  period text not null,
  cost_centre_id uuid,
  amount numeric(14,2) not null,
  currency text not null default 'PKR'::text,
  notes text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.crm_contacts (
  id uuid not null default gen_random_uuid(),
  organization_id uuid not null,
  full_name text not null,
  designation text,
  email text,
  phone text,
  whatsapp text,
  is_primary boolean not null default false,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamp with time zone,
  vendor_id uuid
);

create table if not exists public.crm_cost_allocations (
  id uuid not null default gen_random_uuid(),
  period text not null,
  order_id uuid not null,
  cost_pool text not null,
  method text not null,
  basis_label text,
  allocated_amount numeric(14,2) not null,
  currency text not null default 'PKR'::text,
  run_by uuid default auth.uid(),
  run_at timestamp with time zone not null default now()
);

create table if not exists public.crm_cost_categories (
  code text not null,
  letter text not null,
  name text not null,
  default_kind text not null,
  service_tags text[] not null default ARRAY['all'::text],
  sort_order integer not null default 100,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_cost_centres (
  id uuid not null default gen_random_uuid(),
  code text not null,
  name text not null,
  description text,
  is_active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.crm_cost_lines (
  id uuid not null default gen_random_uuid(),
  code text not null,
  category_code text not null,
  name text not null,
  line_kind text not null,
  default_unit text not null default 'lump_sum'::text,
  default_borne_by text not null default 'company'::text,
  service_tags text[] not null default ARRAY['all'::text],
  default_rate numeric(14,2),
  currency text,
  notes text,
  is_active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  billing_basis text
);

create table if not exists public.crm_cost_sheet_items (
  id uuid not null default gen_random_uuid(),
  cost_sheet_id uuid not null,
  category text not null,
  description text,
  estimated_amount numeric(14,2) default 0,
  revised_amount numeric(14,2),
  actual_amount numeric(14,2),
  borne_by text not null default 'company'::text,
  tax_recoverable boolean not null default false,
  sort_order integer default 0,
  created_at timestamp with time zone not null default now(),
  cost_line_id uuid,
  billing_basis text,
  rate numeric(14,4),
  quantity numeric(12,3),
  resources integer,
  overtime_hours numeric(10,2),
  overtime_rate numeric(14,4),
  additional_charges numeric(14,2),
  discount_amount numeric(14,2),
  tax_amount numeric(14,2),
  service_offer_id uuid,
  offer_snapshot jsonb,
  computed_amount numeric(14,2) generated always as (
CASE
    WHEN ((rate IS NULL) AND (quantity IS NULL)) THEN NULL::numeric
    ELSE round(((((((COALESCE(rate, (0)::numeric) * COALESCE(quantity, (0)::numeric)) * (COALESCE(resources, 1))::numeric) + ((COALESCE(overtime_rate, (0)::numeric) * COALESCE(overtime_hours, (0)::numeric)) * (COALESCE(resources, 1))::numeric)) + COALESCE(additional_charges, (0)::numeric)) - COALESCE(discount_amount, (0)::numeric)) + COALESCE(tax_amount, (0)::numeric)), 2)
END) stored,
  effective_amount numeric(14,2) generated always as (COALESCE(
CASE
    WHEN ((rate IS NULL) AND (quantity IS NULL)) THEN NULL::numeric
    ELSE round(((((((COALESCE(rate, (0)::numeric) * COALESCE(quantity, (0)::numeric)) * (COALESCE(resources, 1))::numeric) + ((COALESCE(overtime_rate, (0)::numeric) * COALESCE(overtime_hours, (0)::numeric)) * (COALESCE(resources, 1))::numeric)) + COALESCE(additional_charges, (0)::numeric)) - COALESCE(discount_amount, (0)::numeric)) + COALESCE(tax_amount, (0)::numeric)), 2)
END, estimated_amount)) stored
);

create table if not exists public.crm_cost_sheets (
  id uuid not null default gen_random_uuid(),
  sheet_number text,
  enquiry_id uuid,
  title text not null,
  currency text not null default 'PKR'::text,
  quantity numeric(14,3),
  unit text,
  contingency_pct numeric(5,2) default 0,
  status text not null default 'draft'::text,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamp with time zone,
  key_contact_id uuid
);

create table if not exists public.crm_counters (
  entity text not null,
  year integer not null,
  last_seq integer not null default 0
);

create table if not exists public.crm_countries (
  iso2 text not null,
  name text not null,
  dial_code text not null,
  flag text not null,
  is_active boolean not null default true,
  sort_hint integer
);

create table if not exists public.crm_custom_values (
  module text not null,
  record_id uuid not null,
  field_key text not null,
  value text,
  updated_at timestamp with time zone not null default now(),
  updated_by uuid default auth.uid()
);

create table if not exists public.crm_customs_records (
  id uuid not null default gen_random_uuid(),
  shipment_id uuid not null,
  customs_agent text,
  gd_number text,
  hs_code text,
  customs_value numeric(16,2),
  duty_amount numeric(14,2),
  tax_amount numeric(14,2),
  clearing_charges numeric(14,2),
  demurrage numeric(14,2),
  detention numeric(14,2),
  status text not null default 'pending'::text,
  clearance_date date,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  updated_by uuid
);

create table if not exists public.crm_daily_entries (
  id uuid not null default gen_random_uuid(),
  entry_number text,
  entered_by uuid not null default auth.uid(),
  entry_date date not null default CURRENT_DATE,
  description text not null,
  amount numeric(14,2) not null,
  currency text not null default 'PKR'::text,
  category text not null default 'other'::text,
  cost_centre_id uuid,
  order_id uuid,
  project_id uuid,
  receipt_path text,
  status text not null default 'pending'::text,
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  review_note text,
  expense_id uuid,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  cost_line_id uuid
);

create table if not exists public.crm_departments (
  id uuid not null default gen_random_uuid(),
  code text not null,
  name text not null,
  parent_id uuid,
  head_user_id uuid,
  cost_centre_id uuid,
  sort_order integer not null default 100,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.crm_email_log (
  id uuid not null default gen_random_uuid(),
  organization_id uuid,
  opportunity_id uuid,
  enquiry_id uuid,
  to_email text not null,
  cc_email text,
  subject text not null,
  body_preview text,
  status text not null default 'sent'::text,
  provider text not null default 'gmail-relay'::text,
  provider_ref text,
  error text,
  sent_by uuid,
  sent_at timestamp with time zone not null default now()
);

create table if not exists public.crm_employee_allowances (
  id uuid not null default gen_random_uuid(),
  employee_cost_id uuid not null,
  allowance_type text not null default 'other'::text,
  allowance_name text,
  monthly_amount numeric(14,2) not null,
  is_deduction boolean not null default false,
  is_active boolean not null default true,
  notes text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_employee_cost_history (
  id uuid not null default gen_random_uuid(),
  employee_cost_id uuid not null,
  action text not null,
  old_data jsonb not null,
  changed_by uuid default auth.uid(),
  changed_at timestamp with time zone not null default now()
);

create table if not exists public.crm_employee_costs (
  id uuid not null default gen_random_uuid(),
  user_id uuid,
  employee_name text not null,
  designation text,
  cost_centre_id uuid,
  employment_type text not null default 'full_time'::text,
  joining_date date,
  status text not null default 'active'::text,
  currency text not null default 'PKR'::text,
  monthly_salary numeric(14,2) not null default 0,
  monthly_bonus_avg numeric(14,2) not null default 0,
  employer_contributions numeric(14,2) not null default 0,
  commission_pct numeric(6,2),
  hourly_rate_manual numeric(14,2),
  daily_rate_manual numeric(14,2),
  overtime_rate numeric(14,2),
  consultancy_rate numeric(14,2),
  opportunity_cost_hour numeric(14,2),
  notes text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone
);

create table if not exists public.crm_employee_profiles (
  user_id uuid not null,
  full_name text,
  department text,
  designation text,
  reporting_manager uuid,
  phone text,
  is_active boolean not null default true,
  suspended_at timestamp with time zone,
  approval_limit numeric(16,2),
  quotation_authority boolean not null default false,
  finance_authority boolean not null default false,
  sourcing_authority boolean not null default false,
  project_authority boolean not null default false,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  updated_by uuid,
  department_id uuid,
  job_role_id uuid
);

create table if not exists public.crm_enquiries (
  id uuid not null default gen_random_uuid(),
  enquiry_number text,
  organization_id uuid,
  contact_id uuid,
  service_id uuid,
  enquiry_type text not null default 'general'::text,
  title text not null,
  requirement_detail text,
  location text,
  country text,
  estimated_budget numeric(14,2),
  budget_currency text default 'PKR'::text,
  required_by_date date,
  urgency text default 'normal'::text,
  priority text not null default 'medium'::text,
  source text not null default 'manual'::text,
  submitter_name text,
  submitter_email text,
  submitter_phone text,
  submitter_company text,
  assigned_department text,
  assigned_to uuid,
  followup_date date,
  quotation_required boolean not null default false,
  status text not null default 'new'::text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamp with time zone,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  utm_content text,
  utm_term text,
  referrer text,
  landing_page text,
  click_id text,
  first_touch jsonb,
  last_touch jsonb
);

create table if not exists public.crm_enquiry_activity (
  id uuid not null default gen_random_uuid(),
  enquiry_id uuid not null,
  kind text not null default 'comment'::text,
  body text,
  old_value text,
  new_value text,
  visibility text not null default 'internal_only'::text,
  created_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid()
);

create table if not exists public.crm_expenses (
  id uuid not null default gen_random_uuid(),
  expense_number text,
  order_id uuid,
  project_id uuid,
  category text not null,
  description text,
  expense_date date not null default CURRENT_DATE,
  amount numeric(14,2) not null,
  currency text not null default 'PKR'::text,
  is_direct boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamp with time zone,
  cost_line_id uuid
);

create table if not exists public.crm_field_config (
  id uuid not null default gen_random_uuid(),
  module text not null,
  field_id text not null,
  label text,
  visible boolean not null default true,
  mandatory boolean not null default false,
  readonly boolean not null default false,
  visibility_scope text not null default 'staff'::text,
  default_value text,
  placeholder text,
  tooltip text,
  display_order integer,
  group_name text,
  updated_at timestamp with time zone not null default now(),
  updated_by uuid,
  is_custom boolean not null default false,
  is_active boolean not null default true,
  field_type text not null default 'text'::text,
  options jsonb,
  validation_regex text,
  min_value numeric,
  max_value numeric,
  visible_if_field text,
  visible_if_value text
);

create table if not exists public.crm_fixed_expense_history (
  id uuid not null default gen_random_uuid(),
  fixed_expense_id uuid not null,
  action text not null,
  old_data jsonb not null,
  changed_by uuid default auth.uid(),
  changed_at timestamp with time zone not null default now()
);

create table if not exists public.crm_fixed_expenses (
  id uuid not null default gen_random_uuid(),
  expense_number text,
  name text not null,
  category text not null default 'other'::text,
  vendor_name text,
  frequency text not null default 'monthly'::text,
  start_date date not null default CURRENT_DATE,
  end_date date,
  amount numeric(14,2) not null,
  tax_included boolean not null default true,
  currency text not null default 'PKR'::text,
  cost_centre_id uuid,
  status text not null default 'active'::text,
  notes text,
  attachment_path text,
  monthly_equivalent numeric(14,2) generated always as (
CASE frequency
    WHEN 'daily'::text THEN round((amount * 30.4375), 2)
    WHEN 'weekly'::text THEN round((amount * 4.34524), 2)
    WHEN 'monthly'::text THEN amount
    WHEN 'quarterly'::text THEN round((amount / 3.0), 2)
    WHEN 'half_yearly'::text THEN round((amount / 6.0), 2)
    WHEN 'yearly'::text THEN round((amount / 12.0), 2)
    ELSE (0)::numeric
END) stored,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone
);

create table if not exists public.crm_invoice_items (
  id uuid not null default gen_random_uuid(),
  invoice_id uuid not null,
  description text not null,
  quantity numeric(14,3) not null default 1,
  unit text,
  unit_price numeric(14,4) not null default 0,
  line_total numeric(16,2) generated always as (round((quantity * unit_price), 2)) stored,
  sort_order integer default 0,
  created_at timestamp with time zone not null default now(),
  cost_line_id uuid
);

create table if not exists public.crm_invoices (
  id uuid not null default gen_random_uuid(),
  invoice_number text,
  organization_id uuid not null,
  order_id uuid,
  project_id uuid,
  quotation_id uuid,
  invoice_type text not null default 'commercial'::text,
  title text not null,
  issue_date date,
  due_date date,
  currency text not null default 'PKR'::text,
  exchange_rate numeric(14,6),
  discount_pct numeric(5,2) default 0,
  tax_pct numeric(5,2) default 0,
  freight_amount numeric(14,2) default 0,
  other_charges numeric(14,2) default 0,
  subtotal numeric(16,2) not null default 0,
  discount_amount numeric(16,2) not null default 0,
  tax_amount numeric(16,2) not null default 0,
  total numeric(16,2) not null default 0,
  paid_amount numeric(16,2) not null default 0,
  outstanding numeric(16,2) not null default 0,
  payment_terms text,
  payment_instructions text,
  notes text,
  internal_notes text,
  prepared_by uuid default auth.uid(),
  approved_by uuid,
  status text not null default 'draft'::text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamp with time zone,
  key_contact_id uuid
);

create table if not exists public.crm_job_roles (
  id uuid not null default gen_random_uuid(),
  code text not null,
  title text not null,
  level integer not null,
  dept_code text,
  is_management boolean not null default false,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_login_history (
  id bigint not null generated always as identity,
  user_id uuid not null,
  event text not null,
  user_agent text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_notifications (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  title text not null,
  body text,
  link text,
  kind text not null default 'info'::text,
  read_at timestamp with time zone,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_opportunities (
  id uuid not null default gen_random_uuid(),
  opportunity_number text,
  enquiry_id uuid,
  organization_id uuid,
  contact_id uuid,
  service_id uuid,
  title text not null,
  description text,
  estimated_value numeric(16,2),
  currency text not null default 'PKR'::text,
  probability_pct integer not null default 30,
  weighted_value numeric(16,2) generated always as (round(((COALESCE(estimated_value, (0)::numeric) * (probability_pct)::numeric) / 100.0), 2)) stored,
  expected_close_date date,
  stage text not null default 'qualification'::text,
  loss_reason text,
  competitor text,
  next_step text,
  next_step_date date,
  assigned_to uuid,
  priority text not null default 'medium'::text,
  internal_notes text,
  converted_quotation_id uuid,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamp with time zone,
  key_contact_id uuid
);

create table if not exists public.crm_opportunity_activity (
  id uuid not null default gen_random_uuid(),
  opportunity_id uuid not null,
  kind text not null default 'comment'::text,
  body text,
  old_value text,
  new_value text,
  created_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid()
);

create table if not exists public.crm_order_events (
  id uuid not null default gen_random_uuid(),
  order_id uuid not null,
  kind text not null default 'comment'::text,
  body text,
  old_value text,
  new_value text,
  visibility text not null default 'internal_only'::text,
  created_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid()
);

create table if not exists public.crm_order_items (
  id uuid not null default gen_random_uuid(),
  order_id uuid not null,
  description text not null,
  quantity numeric(14,3) not null default 1,
  unit text,
  unit_price numeric(14,4) not null default 0,
  line_total numeric(16,2) generated always as (round((quantity * unit_price), 2)) stored,
  sort_order integer default 0,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_order_milestones (
  id uuid not null default gen_random_uuid(),
  order_id uuid not null,
  milestone_code text not null,
  milestone_label text not null,
  sequence_number integer not null,
  status text not null default 'pending'::text,
  planned_start_at date,
  planned_due_at date,
  actual_start_at timestamp with time zone,
  completed_at timestamp with time zone,
  completion_percentage numeric not null default 0,
  weight numeric not null default 1,
  owner_user_id uuid,
  client_visible boolean not null default true,
  internal_notes text,
  client_update text,
  delay_reason text,
  evidence_required boolean not null default false,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.crm_order_tracking (
  id uuid not null default gen_random_uuid(),
  order_id uuid not null,
  tracking_template_id uuid,
  progress_percentage numeric not null default 0,
  is_delayed boolean not null default false,
  delay_reason text,
  expected_completion_date date,
  revised_completion_date date,
  last_update_at timestamp with time zone not null default now(),
  last_client_update_at timestamp with time zone,
  next_milestone text,
  next_milestone_due_at date,
  updated_by uuid,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.crm_orders (
  id uuid not null default gen_random_uuid(),
  order_number text,
  organization_id uuid not null,
  quotation_id uuid,
  enquiry_id uuid,
  cost_sheet_id uuid,
  service_id uuid,
  order_type text not null default 'trade'::text,
  title text not null,
  currency text not null default 'PKR'::text,
  order_value numeric(16,2) not null default 0,
  purchase_cost numeric(16,2),
  landed_cost numeric(16,2),
  vendor_id uuid,
  payment_terms text,
  delivery_terms text,
  incoterm text,
  order_date date not null default CURRENT_DATE,
  promised_date date,
  expected_completion date,
  assigned_manager uuid,
  payment_status text not null default 'unpaid'::text,
  status text not null default 'draft'::text,
  internal_notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamp with time zone,
  key_contact_id uuid,
  relationship_manager_id uuid,
  rm_exempt boolean not null default false
);

create table if not exists public.crm_organizations (
  id uuid not null default gen_random_uuid(),
  org_number text,
  legal_name text not null,
  trading_name text,
  business_type text,
  industry text,
  registered_address text,
  billing_address text,
  delivery_address text,
  country text,
  city text,
  website text,
  primary_email text,
  phone text,
  whatsapp text,
  registration_number text,
  ntn text,
  strn text,
  tax_registration text,
  import_registration text,
  preferred_currency text not null default 'PKR'::text,
  preferred_language text default 'en'::text,
  payment_terms text,
  credit_limit numeric(14,2),
  risk_status text not null default 'standard'::text,
  kyc_status text not null default 'pending'::text,
  account_manager uuid,
  classification text default 'standard'::text,
  status text not null default 'active'::text,
  internal_remarks text,
  legacy_client_id uuid,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamp with time zone
);

create table if not exists public.crm_outsourced_categories (
  code text not null,
  branch_code text not null,
  name text not null,
  typical_basis text,
  added_by_system boolean not null default false,
  is_active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_payment_allocations (
  id uuid not null default gen_random_uuid(),
  payment_id uuid not null,
  invoice_id uuid not null,
  amount numeric(16,2) not null,
  created_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid()
);

create table if not exists public.crm_payments (
  id uuid not null default gen_random_uuid(),
  payment_number text,
  organization_id uuid not null,
  payment_date date not null default CURRENT_DATE,
  amount numeric(16,2) not null,
  currency text not null default 'PKR'::text,
  exchange_rate numeric(14,6),
  payment_method text default 'bank_transfer'::text,
  bank_name text,
  transaction_ref text,
  withholding_tax numeric(14,2) default 0,
  bank_charges numeric(14,2) default 0,
  deductions numeric(14,2) default 0,
  net_received numeric(16,2) generated always as ((((amount - COALESCE(withholding_tax, (0)::numeric)) - COALESCE(bank_charges, (0)::numeric)) - COALESCE(deductions, (0)::numeric))) stored,
  proof_path text,
  is_verified boolean not null default false,
  verified_by uuid,
  verified_at timestamp with time zone,
  internal_notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamp with time zone,
  key_contact_id uuid
);

create table if not exists public.crm_portal_members (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  organization_id uuid not null,
  member_role text not null default 'client_user'::text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid()
);

create table if not exists public.crm_project_milestones (
  id uuid not null default gen_random_uuid(),
  project_id uuid not null,
  title text not null,
  description text,
  due_date date,
  completed_at date,
  status text not null default 'pending'::text,
  visibility text not null default 'internal_only'::text,
  sort_order integer default 0,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_projects (
  id uuid not null default gen_random_uuid(),
  project_number text,
  organization_id uuid not null,
  order_id uuid,
  quotation_id uuid,
  service_id uuid,
  title text not null,
  scope text,
  project_manager uuid,
  start_date date,
  due_date date,
  completion_pct integer not null default 0,
  status text not null default 'planned'::text,
  client_feedback text,
  internal_notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamp with time zone,
  client_visible boolean not null default true
);

create table if not exists public.crm_prospects (
  id uuid not null default gen_random_uuid(),
  prospect_number text,
  full_name text not null,
  company_name text,
  designation text,
  email text,
  phone text,
  whatsapp text,
  country text,
  city text,
  industry text,
  website text,
  lead_source text,
  campaign_source text,
  referral_source text,
  interested_service_id uuid,
  product_interest text,
  requirement_summary text,
  estimated_quantity text,
  expected_budget numeric(14,2),
  budget_currency text default 'PKR'::text,
  expected_close_date date,
  priority text not null default 'medium'::text,
  lead_score integer,
  stage text not null default 'new'::text,
  assigned_to uuid,
  last_contact_date date,
  next_followup_date date,
  internal_notes text,
  communication_consent boolean not null default false,
  converted_org_id uuid,
  converted_contact_id uuid,
  converted_enquiry_id uuid,
  converted_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamp with time zone
);

create table if not exists public.crm_quotation_approvals (
  id uuid not null default gen_random_uuid(),
  quotation_id uuid not null,
  requested_by uuid default auth.uid(),
  requested_at timestamp with time zone not null default now(),
  reason text,
  decided_by uuid,
  decided_at timestamp with time zone,
  decision text,
  comments text
);

create table if not exists public.crm_quotation_items (
  id uuid not null default gen_random_uuid(),
  quotation_id uuid not null,
  description text not null,
  quantity numeric(14,3) not null default 1,
  unit text,
  unit_price numeric(14,4) not null default 0,
  line_total numeric(16,2) generated always as (round((quantity * unit_price), 2)) stored,
  sort_order integer default 0,
  created_at timestamp with time zone not null default now(),
  cost_line_id uuid
);

create table if not exists public.crm_quotations (
  id uuid not null default gen_random_uuid(),
  quotation_number text not null,
  version integer not null default 1,
  quotation_group uuid not null default gen_random_uuid(),
  organization_id uuid not null,
  contact_id uuid,
  enquiry_id uuid,
  cost_sheet_id uuid,
  service_id uuid,
  title text not null,
  issue_date date,
  expiry_date date,
  currency text not null default 'PKR'::text,
  discount_pct numeric(5,2) default 0,
  tax_pct numeric(5,2) default 0,
  freight_amount numeric(14,2) default 0,
  other_charges numeric(14,2) default 0,
  subtotal numeric(16,2) not null default 0,
  discount_amount numeric(16,2) not null default 0,
  tax_amount numeric(16,2) not null default 0,
  total numeric(16,2) not null default 0,
  payment_terms text,
  delivery_terms text,
  incoterm text,
  delivery_timeline text,
  warranty text,
  assumptions text,
  exclusions text,
  terms_conditions text,
  internal_notes text,
  client_notes text,
  prepared_by uuid default auth.uid(),
  reviewed_by uuid,
  approved_by uuid,
  approved_at timestamp with time zone,
  approval_status text not null default 'not_required'::text,
  status text not null default 'draft'::text,
  client_action_by uuid,
  client_action_at timestamp with time zone,
  client_action_comment text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamp with time zone,
  executive_summary text,
  requirement_understanding text,
  scope_of_work text,
  technical_specifications text,
  timeline_milestones text,
  payment_schedule text
);

create table if not exists public.crm_receipts (
  id uuid not null default gen_random_uuid(),
  receipt_number text,
  payment_id uuid not null,
  organization_id uuid not null,
  amount numeric(16,2) not null,
  currency text not null,
  issued_at timestamp with time zone not null default now(),
  issued_by uuid default auth.uid()
);

create table if not exists public.crm_record_assignments (
  id uuid not null default gen_random_uuid(),
  entity_type text not null default 'orders'::text,
  entity_id uuid not null,
  assignment_type text not null default 'relationship_manager'::text,
  user_id uuid not null,
  is_primary boolean not null default true,
  effective_from timestamp with time zone not null default now(),
  effective_to timestamp with time zone,
  assigned_by uuid default auth.uid(),
  assignment_reason text,
  handover_notes text,
  status text not null default 'active'::text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.crm_rm_policy (
  id uuid not null default gen_random_uuid(),
  singleton boolean not null default true,
  max_active_orders integer not null default 8,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.crm_service_branches (
  code text not null,
  letter text not null,
  name text not null,
  service_tag text,
  sort_order integer not null default 100,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_service_milestone_templates (
  id uuid not null default gen_random_uuid(),
  service_id uuid not null,
  title text not null,
  sort_order integer not null default 0,
  visibility text not null default 'client_visible'::text,
  offset_days integer,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_service_offers (
  id uuid not null default gen_random_uuid(),
  offer_number text,
  provider_id uuid not null,
  branch_code text,
  category_code text,
  title text not null,
  scope_of_work text,
  billing_basis text not null,
  rate numeric(14,4),
  min_billable_qty numeric(10,2),
  estimated_qty numeric(12,3),
  resources integer default 1,
  currency text not null default 'PKR'::text,
  tax_pct numeric(5,2) default 0,
  travel_cost numeric(14,2) default 0,
  accommodation_cost numeric(14,2) default 0,
  mobilisation_cost numeric(14,2) default 0,
  equipment_cost numeric(14,2) default 0,
  reimbursables numeric(14,2) default 0,
  discount_amount numeric(14,2) default 0,
  valid_until date,
  expected_start date,
  completion_days integer,
  payment_terms text,
  cancellation_terms text,
  deliverables text,
  sla text,
  evaluation_note text,
  status text not null default 'received'::text,
  is_preferred boolean not null default false,
  rejection_reason text,
  internal_comments text,
  created_by uuid default auth.uid(),
  approved_by uuid,
  approved_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone,
  gross_amount numeric(14,2) generated always as (round((((((((COALESCE(rate, (0)::numeric) * COALESCE(estimated_qty, (0)::numeric)) * (COALESCE(resources, 1))::numeric) + COALESCE(travel_cost, (0)::numeric)) + COALESCE(accommodation_cost, (0)::numeric)) + COALESCE(mobilisation_cost, (0)::numeric)) + COALESCE(equipment_cost, (0)::numeric)) + COALESCE(reimbursables, (0)::numeric)), 2)) stored,
  final_amount numeric(14,2) generated always as (round((((((((((COALESCE(rate, (0)::numeric) * COALESCE(estimated_qty, (0)::numeric)) * (COALESCE(resources, 1))::numeric) + COALESCE(travel_cost, (0)::numeric)) + COALESCE(accommodation_cost, (0)::numeric)) + COALESCE(mobilisation_cost, (0)::numeric)) + COALESCE(equipment_cost, (0)::numeric)) + COALESCE(reimbursables, (0)::numeric)) - COALESCE(discount_amount, (0)::numeric)) * ((1)::numeric + (COALESCE(tax_pct, (0)::numeric) / (100)::numeric))), 2)) stored
);

create table if not exists public.crm_service_provider_bank (
  provider_id uuid not null,
  bank_name text,
  account_title text,
  account_number text,
  iban text,
  swift text,
  branch_address text,
  payment_terms text,
  updated_by uuid default auth.uid(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.crm_service_providers (
  id uuid not null default gen_random_uuid(),
  provider_number text,
  legal_name text not null,
  trading_name text,
  contact_person text,
  branch_code text,
  category_code text,
  provider_type text default 'company'::text,
  country text,
  city text,
  address text,
  phone text,
  whatsapp text,
  email text,
  website text,
  tax_number text,
  currency text default 'PKR'::text,
  years_experience integer,
  certifications text,
  coverage text,
  availability text,
  lead_time_days integer,
  rating numeric(2,1),
  risk_class text default 'unrated'::text,
  is_preferred boolean not null default false,
  is_blacklisted boolean not null default false,
  blacklist_reason text,
  notes text,
  status text not null default 'active'::text,
  created_by uuid default auth.uid(),
  updated_by uuid,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone
);

create table if not exists public.crm_services (
  id uuid not null default gen_random_uuid(),
  name text not null,
  slug text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  updated_by uuid,
  fulfilment_type text not null default 'service'::text,
  parent_id uuid
);

create table if not exists public.crm_settings (
  key text not null,
  value jsonb not null,
  updated_at timestamp with time zone not null default now(),
  updated_by uuid default auth.uid()
);

create table if not exists public.crm_shipments (
  id uuid not null default gen_random_uuid(),
  shipment_number text,
  order_id uuid not null,
  vendor_id uuid,
  mode text default 'sea'::text,
  carrier text,
  freight_forwarder text,
  incoterm text,
  country_of_origin text,
  port_of_loading text,
  destination_port text,
  container_number text,
  bl_number text,
  awb_number text,
  etd date,
  eta date,
  actual_departure date,
  actual_arrival date,
  freight_cost numeric(14,2),
  insurance_cost numeric(14,2),
  status text not null default 'planned'::text,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamp with time zone,
  key_contact_id uuid
);

create table if not exists public.crm_staff_roles (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  role text not null,
  created_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid()
);

create table if not exists public.crm_stockists (
  id uuid not null default gen_random_uuid(),
  stockist_number text,
  organization_id uuid not null,
  store_name text not null,
  branch text,
  city text,
  address text,
  contact_name text,
  contact_phone text,
  contact_email text,
  product_line text,
  placement_status text not null default 'active'::text,
  shelf_status text not null default 'on_shelf'::text,
  reorder_status text not null default 'not_due'::text,
  last_order_date date,
  next_reorder_date date,
  is_active boolean not null default true,
  notes text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.crm_subscription_price_history (
  id uuid not null default gen_random_uuid(),
  subscription_id uuid not null,
  old_cost numeric(14,2),
  new_cost numeric(14,2),
  old_billing_cycle text,
  new_billing_cycle text,
  changed_by uuid default auth.uid(),
  changed_at timestamp with time zone not null default now()
);

create table if not exists public.crm_subscriptions (
  id uuid not null default gen_random_uuid(),
  subscription_number text,
  software_name text not null,
  vendor_name text,
  plan_name text,
  billing_cycle text not null default 'monthly'::text,
  cost numeric(14,2) not null,
  currency text not null default 'PKR'::text,
  renewal_date date,
  auto_renewal boolean not null default true,
  seats_purchased integer,
  seats_used integer,
  cost_centre_id uuid,
  assigned_users jsonb not null default '[]'::jsonb,
  license_key text,
  invoice_path text,
  notes text,
  status text not null default 'active'::text,
  monthly_equivalent numeric(14,2) generated always as (
CASE billing_cycle
    WHEN 'monthly'::text THEN cost
    WHEN 'quarterly'::text THEN round((cost / 3.0), 2)
    WHEN 'yearly'::text THEN round((cost / 12.0), 2)
    ELSE cost
END) stored,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone
);

create table if not exists public.crm_supplier_offers (
  id uuid not null default gen_random_uuid(),
  offer_number text,
  enquiry_id uuid not null,
  vendor_id uuid not null,
  product text,
  specification text,
  quantity numeric(14,3),
  unit text,
  unit_cost numeric(14,4),
  currency text not null default 'USD'::text,
  exchange_rate numeric(14,6),
  exchange_rate_date date,
  moq text,
  sample_cost numeric(14,2) default 0,
  tooling_cost numeric(14,2) default 0,
  packaging_cost numeric(14,2) default 0,
  freight_estimate numeric(14,2) default 0,
  payment_terms text,
  lead_time text,
  incoterm text,
  inspection text,
  certification text,
  warranty text,
  validity_date date,
  quality_score integer,
  risk_score integer,
  notes text,
  total_cost numeric(16,2) generated always as ((((((COALESCE(unit_cost, (0)::numeric) * COALESCE(quantity, (0)::numeric)) + COALESCE(sample_cost, (0)::numeric)) + COALESCE(tooling_cost, (0)::numeric)) + COALESCE(packaging_cost, (0)::numeric)) + COALESCE(freight_estimate, (0)::numeric))) stored,
  is_selected boolean not null default false,
  selected_by uuid,
  selected_at timestamp with time zone,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamp with time zone,
  key_contact_id uuid
);

create table if not exists public.crm_timesheets (
  id uuid not null default gen_random_uuid(),
  employee_cost_id uuid not null,
  work_date date not null default CURRENT_DATE,
  hours numeric(5,2) not null,
  order_id uuid,
  project_id uuid,
  description text,
  is_billable boolean not null default true,
  rate_snapshot numeric(14,2),
  rate_currency text,
  entered_by uuid not null default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.crm_tracking_policy (
  id uuid not null default gen_random_uuid(),
  singleton boolean not null default true,
  auto_assign boolean not null default true,
  stale_after_days integer not null default 7,
  due_soon_hours integer not null default 48,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.crm_tracking_template_steps (
  id uuid not null default gen_random_uuid(),
  template_id uuid not null,
  step_code text not null,
  step_label text not null,
  sequence_number integer not null,
  default_duration_days integer not null default 3,
  weight numeric not null default 1,
  client_visible boolean not null default true,
  requires_attachment boolean not null default false,
  requires_approval boolean not null default false,
  responsible_role text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_tracking_templates (
  id uuid not null default gen_random_uuid(),
  service_code text not null,
  template_name text not null,
  description text,
  is_default boolean not null default false,
  is_active boolean not null default true,
  version integer not null default 1,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now()
);

create table if not exists public.crm_vendors (
  id uuid not null default gen_random_uuid(),
  vendor_number text,
  legal_name text not null,
  trading_name text,
  supplier_type text default 'manufacturer'::text,
  country text,
  city text,
  registered_address text,
  website text,
  primary_contact text,
  email text,
  phone text,
  whatsapp text,
  wechat text,
  product_categories text,
  years_in_business integer,
  registration_number text,
  export_licence text,
  tax_number text,
  certifications text,
  supported_currencies text,
  supported_incoterms text,
  moq text,
  capacity text,
  lead_time text,
  sample_policy text,
  payment_terms text,
  credit_terms text,
  factory_audit_status text default 'not_audited'::text,
  score_price integer,
  score_quality integer,
  score_communication integer,
  score_delivery integer,
  score_documentation integer,
  score_compliance integer,
  score_reliability integer,
  internal_notes text,
  approval_status text not null default 'pending'::text,
  is_blacklisted boolean not null default false,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid(),
  updated_by uuid,
  deleted_at timestamp with time zone
);

create table if not exists public.featured_topics (
  id uuid not null default gen_random_uuid(),
  title text not null,
  prompt text not null,
  is_active boolean not null default false,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_adverse_events (
  id uuid not null default gen_random_uuid(),
  event_code text,
  complaint_id uuid,
  product_id uuid,
  batch_number text,
  reported_on date not null default CURRENT_DATE,
  onset_date date,
  seriousness text not null default 'non_serious'::text,
  outcome text,
  reaction_description text not null,
  reporter_type text,
  reporter_contact text,
  patient_reference text,
  patient_age_band text,
  patient_sex text,
  causality text,
  regulatory_reportable boolean not null default true,
  submitted_to_authority text,
  submitted_on date,
  narrative text,
  responsible uuid,
  status text not null default 'received'::text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_campaigns (
  id uuid not null default gen_random_uuid(),
  campaign_code text,
  name text not null,
  campaign_type text not null,
  objective text,
  level text not null default 'product'::text,
  principal_org uuid,
  product_id uuid,
  territory_id uuid,
  target_specialty text,
  start_date date not null,
  end_date date not null,
  budget numeric(14,2),
  actual_cost numeric(14,2) not null default 0,
  expected_reach integer,
  expected_prescriptions integer,
  expected_revenue numeric(14,2),
  actual_revenue numeric(14,2) not null default 0,
  doctor_coverage_target integer,
  pharmacy_coverage_target integer,
  hospital_coverage_target integer,
  responsible uuid,
  approval_status text not null default 'draft'::text,
  approved_by uuid,
  approved_at timestamp with time zone,
  status text not null default 'planned'::text,
  lessons_learned text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone
);

create table if not exists public.pharma_companies (
  org_id uuid not null,
  company_code text,
  is_principal boolean not null default false,
  is_manufacturer boolean not null default false,
  is_importer boolean not null default false,
  is_distributor boolean not null default false,
  is_marketing_co boolean not null default false,
  is_toll_client boolean not null default false,
  is_exporter boolean not null default false,
  drug_licence_no text,
  establishment_licence text,
  regulatory_authority text,
  business_status text not null default 'prospect'::text,
  risk_category text not null default 'unrated'::text,
  relationship_started date,
  credit_terms text,
  commercial_terms text,
  account_health integer,
  next_action text,
  notes text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_company_contacts (
  id uuid not null default gen_random_uuid(),
  org_id uuid not null,
  full_name text not null,
  designation text,
  role_type text,
  phone text,
  whatsapp text,
  email text,
  preferred_contact text,
  is_primary boolean not null default false,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_complaints (
  id uuid not null default gen_random_uuid(),
  complaint_code text,
  complaint_type text not null,
  severity text not null default 'minor'::text,
  product_id uuid,
  batch_number text,
  doctor_id uuid,
  hospital_id uuid,
  pharmacy_id uuid,
  distributor_id uuid,
  reporter_name text,
  received_on date not null default CURRENT_DATE,
  description text not null,
  immediate_action text,
  investigation text,
  root_cause text,
  capa text,
  regulatory_reportable boolean not null default false,
  regulatory_submitted_on date,
  resolution text,
  closed_on date,
  financial_impact numeric(14,2),
  responsible uuid,
  status text not null default 'open'::text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_distributor_products (
  distributor_id uuid not null,
  product_id uuid not null,
  margin_pct numeric(5,2),
  rebate_pct numeric(5,2),
  commission_pct numeric(5,2),
  target_monthly numeric(14,2)
);

create table if not exists public.pharma_distributor_territories (
  distributor_id uuid not null,
  territory_id uuid not null,
  is_exclusive boolean not null default false
);

create table if not exists public.pharma_distributors (
  id uuid not null default gen_random_uuid(),
  distributor_code text,
  org_id uuid,
  name text not null,
  distributor_type text not null default 'city'::text,
  owner_name text,
  city text,
  address text,
  phone text,
  whatsapp text,
  email text,
  warehouse_locations text,
  warehouse_capacity text,
  cold_chain boolean not null default false,
  fleet_details text,
  sales_force_size integer,
  delivery_frequency text,
  order_cutoff text,
  avg_lead_time_days integer,
  credit_limit numeric(14,2),
  credit_terms text,
  security_deposit numeric(14,2),
  bank_guarantee numeric(14,2),
  performance_score integer,
  service_level_score integer,
  agreement_start date,
  agreement_expiry date,
  relationship_manager uuid,
  notes text,
  status text not null default 'active'::text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone
);

create table if not exists public.pharma_doctor_affiliations (
  id uuid not null default gen_random_uuid(),
  doctor_id uuid not null,
  institution_type text not null,
  hospital_id uuid,
  name text,
  role text,
  is_primary boolean not null default false,
  days_present text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_doctor_products (
  doctor_id uuid not null,
  product_id uuid not null,
  relationship text not null default 'potential'::text,
  competitor_product text,
  estimated_monthly_patients integer,
  interest_level text,
  last_detailed date,
  notes text,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_doctors (
  id uuid not null default gen_random_uuid(),
  doctor_code text,
  full_name text not null,
  title text,
  specialty text,
  subspecialty text,
  qualification text,
  pmdc_number text,
  reg_authority text default 'PMDC'::text,
  years_experience integer,
  designation text,
  city text,
  territory_id uuid,
  address text,
  clinic_timings text,
  phone text,
  whatsapp text,
  email text,
  preferred_contact text,
  assistant_contact text,
  visit_restrictions text,
  appointment_required boolean not null default false,
  latitude numeric(9,6),
  longitude numeric(9,6),
  category text default 'unclassified'::text,
  prescribing_potential text,
  influence_level text,
  engagement_score integer,
  relationship_status text default 'new'::text,
  consent_status text not null default 'not_obtained'::text,
  consent_date date,
  consent_notes text,
  do_not_contact boolean not null default false,
  annual_spend_cap numeric(14,2),
  account_owner uuid,
  medical_rep uuid,
  last_visit date,
  next_visit date,
  notes text,
  status text not null default 'active'::text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone
);

create table if not exists public.pharma_dosage_forms (
  code text not null,
  name text not null,
  sterile boolean not null default false,
  sort_order integer default 100
);

create table if not exists public.pharma_engagement_spend (
  id uuid not null default gen_random_uuid(),
  doctor_id uuid,
  hospital_id uuid,
  spend_type text not null,
  amount numeric(14,2) not null,
  currency text not null default 'PKR'::text,
  spend_date date not null default CURRENT_DATE,
  campaign_id uuid,
  offer_id uuid,
  justification text not null,
  approved_by uuid,
  approved_at timestamp with time zone,
  evidence_note text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_expense_dimensions (
  id uuid not null default gen_random_uuid(),
  crm_expense_id uuid not null,
  product_id uuid,
  principal_org uuid,
  plant_id uuid,
  campaign_id uuid,
  territory_id uuid,
  distributor_id uuid,
  hospital_id uuid,
  pharmacy_id uuid,
  doctor_id uuid,
  tender_id uuid,
  contract_id uuid,
  sales_order_id uuid,
  allocation_pct numeric(6,3) not null default 100,
  pl_layer text not null,
  note text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_field_force (
  user_id uuid not null,
  field_role text not null,
  territory_id uuid,
  reports_to uuid,
  monthly_target numeric(14,2),
  daily_visit_target integer default 8,
  joined_on date,
  is_active boolean not null default true,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_hospitals (
  id uuid not null default gen_random_uuid(),
  hospital_code text,
  legal_name text not null,
  org_id uuid,
  institution_type text not null default 'private_hospital'::text,
  ownership_type text,
  parent_group text,
  beds integer,
  departments text,
  specialties text,
  has_pharmacy boolean not null default false,
  has_formulary boolean not null default false,
  procurement_process text,
  city text,
  territory_id uuid,
  address text,
  phone text,
  email text,
  website text,
  credit_terms text,
  credit_limit numeric(14,2),
  tax_number text,
  relationship_status text default 'prospect'::text,
  account_owner uuid,
  last_contact date,
  next_action text,
  notes text,
  status text not null default 'active'::text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone
);

create table if not exists public.pharma_inventory_batches (
  id uuid not null default gen_random_uuid(),
  product_id uuid not null,
  batch_number text not null,
  warehouse_id uuid,
  mfg_date date,
  expiry_date date not null,
  bin_location text,
  unit_cost numeric(14,4),
  currency text default 'PKR'::text,
  quality_status text not null default 'released'::text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_inventory_movements (
  id uuid not null default gen_random_uuid(),
  batch_id uuid not null,
  movement_type text not null,
  quantity numeric(14,2) not null,
  reference text,
  order_id uuid,
  notes text,
  moved_at timestamp with time zone not null default now(),
  created_by uuid default auth.uid()
);

create table if not exists public.pharma_invoices (
  id uuid not null default gen_random_uuid(),
  invoice_number text,
  order_id uuid,
  distributor_id uuid,
  pharmacy_id uuid,
  hospital_id uuid,
  invoice_date date not null default CURRENT_DATE,
  due_date date not null,
  payment_terms text,
  invoice_value numeric(14,2) not null,
  currency text not null default 'PKR'::text,
  status text not null default 'open'::text,
  dispute_note text,
  collector uuid,
  next_followup date,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_offer_categories (
  code text not null,
  name text not null,
  applies_to text[] not null default ARRAY['doctor'::text, 'hospital'::text, 'pharmacy'::text, 'distributor'::text, 'wholesaler'::text],
  requires_approval boolean not null default true,
  is_monetary boolean not null default true,
  sort_order integer default 100,
  is_active boolean not null default true
);

create table if not exists public.pharma_offer_products (
  offer_id uuid not null,
  product_id uuid not null
);

create table if not exists public.pharma_offer_targets (
  id uuid not null default gen_random_uuid(),
  offer_id uuid not null,
  doctor_id uuid,
  hospital_id uuid,
  pharmacy_id uuid,
  distributor_id uuid,
  utilised_value numeric(14,2) not null default 0,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_pharmacies (
  id uuid not null default gen_random_uuid(),
  pharmacy_code text,
  name text not null,
  chain_name text,
  pharmacy_type text not null default 'independent'::text,
  owner_name text,
  pharmacist_in_charge text,
  drug_licence_no text,
  licence_expiry date,
  tax_number text,
  city text,
  territory_id uuid,
  address text,
  latitude numeric(9,6),
  longitude numeric(9,6),
  phone text,
  whatsapp text,
  email text,
  store_category text,
  monthly_potential numeric(14,2),
  credit_terms text,
  credit_limit numeric(14,2),
  preferred_distributor uuid,
  relationship_rating integer,
  account_owner uuid,
  sales_rep uuid,
  last_visit date,
  next_visit date,
  notes text,
  status text not null default 'active'::text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone
);

create table if not exists public.pharma_plant_capabilities (
  plant_code_id uuid not null,
  dosage_form text not null,
  is_approved boolean not null default true,
  notes text
);

create table if not exists public.pharma_plants (
  id uuid not null default gen_random_uuid(),
  plant_code text,
  name text not null,
  org_id uuid,
  country text default 'Pakistan'::text,
  city text,
  address text,
  latitude numeric(9,6),
  longitude numeric(9,6),
  gmp_status text,
  gmp_expiry date,
  iso_certs text,
  halal_certified boolean not null default false,
  installed_capacity text,
  utilised_capacity_pct numeric(5,2),
  production_lines integer,
  min_batch_size numeric(14,2),
  max_batch_size numeric(14,2),
  lead_time_days integer,
  warehouse_capacity text,
  cold_chain boolean not null default false,
  export_markets text,
  last_audit_date date,
  next_audit_date date,
  audit_status text,
  quality_rating numeric(2,1),
  commercial_rating numeric(2,1),
  risk_rating text default 'unrated'::text,
  status text not null default 'active'::text,
  notes text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone
);

create table if not exists public.pharma_product_prices (
  id uuid not null default gen_random_uuid(),
  product_id uuid not null,
  price_type text not null,
  amount numeric(14,4) not null,
  currency text not null default 'PKR'::text,
  tax_pct numeric(5,2) default 0,
  effective_from date not null default CURRENT_DATE,
  effective_to date,
  approved_by uuid,
  notes text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_product_regulatory (
  id uuid not null default gen_random_uuid(),
  product_id uuid not null,
  record_type text not null,
  authority text,
  reference_no text,
  submitted_on date,
  due_on date,
  approved_on date,
  expires_on date,
  status text not null default 'draft'::text,
  responsible uuid,
  external_consultant uuid,
  fee_amount numeric(14,2),
  fee_paid boolean not null default false,
  missing_docs text,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_production_batches (
  id uuid not null default gen_random_uuid(),
  batch_number text not null,
  contract_id uuid,
  product_id uuid not null,
  plant_id uuid,
  batch_size numeric(14,2),
  mfg_date date,
  expiry_date date,
  stage text not null default 'planned'::text,
  qc_result text,
  released_by uuid,
  released_at timestamp with time zone,
  rejection_reason text,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_products (
  id uuid not null default gen_random_uuid(),
  product_code text,
  brand_name text not null,
  generic_name text,
  molecule text,
  composition text,
  strength text,
  dosage_form text,
  pack_size text,
  uom text,
  therapeutic_category text,
  indication text,
  target_specialty text,
  product_class text not null default 'pharmaceutical'::text,
  rx_status text not null default 'rx'::text,
  is_imported boolean not null default false,
  country_of_origin text,
  brand_owner_org uuid,
  principal_org uuid,
  manufacturer_plant uuid,
  toll_manufacturer uuid,
  importer_org uuid,
  marketing_org uuid,
  status text not null default 'development'::text,
  lifecycle_stage text,
  launch_date date,
  usp text,
  positioning text,
  competitors text,
  approved_claims text,
  promotion_restrictions text,
  sampling_rules text,
  monthly_target numeric(14,2),
  annual_target numeric(14,2),
  sku text,
  barcode text,
  shelf_life_months integer,
  storage_conditions text,
  cold_chain boolean not null default false,
  safety_stock numeric(12,2),
  reorder_point numeric(12,2),
  notes text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone
);

create table if not exists public.pharma_promotional_offers (
  id uuid not null default gen_random_uuid(),
  offer_code text,
  name text not null,
  principal_org uuid,
  category_code text not null,
  target_type text not null,
  territory_id uuid,
  start_date date not null,
  end_date date not null,
  eligibility text,
  min_order_value numeric(14,2),
  max_benefit numeric(14,2),
  discount_pct numeric(5,2),
  discount_value numeric(14,2),
  free_goods_ratio text,
  rebate_pct numeric(5,2),
  rebate_value numeric(14,2),
  commission_pct numeric(5,2),
  budget numeric(14,2),
  spent_to_date numeric(14,2) not null default 0,
  currency text not null default 'PKR'::text,
  approval_status text not null default 'draft'::text,
  approved_by uuid,
  approved_at timestamp with time zone,
  rejection_reason text,
  compliance_status text not null default 'pending'::text,
  compliance_note text,
  terms text,
  status text not null default 'planned'::text,
  notes text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone
);

create table if not exists public.pharma_recalls (
  id uuid not null default gen_random_uuid(),
  recall_code text,
  product_id uuid not null,
  batch_number text not null,
  recall_class text,
  reason text not null,
  initiated_on date not null default CURRENT_DATE,
  authority_informed boolean not null default false,
  authority_informed_on date,
  quantity_affected numeric(14,2),
  quantity_recovered numeric(14,2) default 0,
  status text not null default 'initiated'::text,
  responsible uuid,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_receipts (
  id uuid not null default gen_random_uuid(),
  receipt_number text,
  invoice_id uuid not null,
  receipt_type text not null default 'payment'::text,
  amount numeric(14,2) not null,
  received_on date not null default CURRENT_DATE,
  method text,
  reference text,
  approved_by uuid,
  notes text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_returns (
  id uuid not null default gen_random_uuid(),
  return_code text,
  return_type text not null,
  order_id uuid,
  invoice_id uuid,
  distributor_id uuid,
  pharmacy_id uuid,
  product_id uuid,
  batch_number text,
  quantity numeric(14,2) not null,
  claim_value numeric(14,2),
  currency text default 'PKR'::text,
  received_on date default CURRENT_DATE,
  status text not null default 'requested'::text,
  approved_by uuid,
  rejection_reason text,
  notes text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_role_permissions (
  role text not null,
  permission text not null,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_sales_order_items (
  id uuid not null default gen_random_uuid(),
  order_id uuid not null,
  product_id uuid not null,
  batch_id uuid,
  quantity numeric(14,2) not null,
  free_quantity numeric(14,2) not null default 0,
  list_price numeric(14,4) not null,
  discount_pct numeric(5,2) not null default 0,
  tax_pct numeric(5,2) not null default 0,
  unit_cost numeric(14,4),
  created_at timestamp with time zone not null default now(),
  line_net numeric(14,2) generated always as (round((((quantity * list_price) * ((1)::numeric - (COALESCE(discount_pct, (0)::numeric) / (100)::numeric))) * ((1)::numeric + (COALESCE(tax_pct, (0)::numeric) / (100)::numeric))), 2)) stored,
  line_cogs numeric(14,2) generated always as (round(((quantity + COALESCE(free_quantity, (0)::numeric)) * COALESCE(unit_cost, (0)::numeric)), 2)) stored,
  line_gross_profit numeric(14,2) generated always as (round((((quantity * list_price) * ((1)::numeric - (COALESCE(discount_pct, (0)::numeric) / (100)::numeric))) - ((quantity + COALESCE(free_quantity, (0)::numeric)) * COALESCE(unit_cost, (0)::numeric))), 2)) stored
);

create table if not exists public.pharma_sales_orders (
  id uuid not null default gen_random_uuid(),
  order_number text,
  crm_order_id uuid,
  sale_type text not null,
  distributor_id uuid,
  pharmacy_id uuid,
  hospital_id uuid,
  org_id uuid,
  territory_id uuid,
  sales_rep uuid,
  order_date date not null default CURRENT_DATE,
  required_by date,
  offer_id uuid,
  currency text not null default 'PKR'::text,
  freight numeric(14,2) default 0,
  credit_override boolean not null default false,
  credit_override_by uuid,
  credit_override_reason text,
  status text not null default 'draft'::text,
  dispatch_warehouse uuid,
  notes text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone
);

create table if not exists public.pharma_sample_items (
  id uuid not null default gen_random_uuid(),
  item_code text,
  item_type text not null,
  product_id uuid,
  name text not null,
  batch_number text,
  expiry_date date,
  unit_cost numeric(14,4),
  currency text default 'PKR'::text,
  is_controlled boolean not null default false,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_sample_transactions (
  id uuid not null default gen_random_uuid(),
  item_id uuid not null,
  txn_type text not null,
  quantity numeric(12,2) not null,
  holder_user uuid,
  doctor_id uuid,
  hospital_id uuid,
  pharmacy_id uuid,
  campaign_id uuid,
  visit_id uuid,
  purpose text,
  approved_by uuid,
  proof_note text,
  txn_date date not null default CURRENT_DATE,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_tender_products (
  id uuid not null default gen_random_uuid(),
  tender_id uuid not null,
  product_id uuid,
  description text,
  quantity numeric(14,2),
  quoted_price numeric(14,4),
  unit_cost numeric(14,4),
  awarded_qty numeric(14,2),
  line_margin_pct numeric(6,2) generated always as (
CASE
    WHEN (COALESCE(quoted_price, (0)::numeric) > (0)::numeric) THEN round((((quoted_price - COALESCE(unit_cost, (0)::numeric)) / quoted_price) * (100)::numeric), 2)
    ELSE NULL::numeric
END) stored
);

create table if not exists public.pharma_tenders (
  id uuid not null default gen_random_uuid(),
  tender_code text,
  hospital_id uuid,
  authority text,
  tender_ref text,
  tender_type text,
  published_on date,
  submission_deadline timestamp with time zone,
  bid_opening timestamp with time zone,
  earnest_money numeric(14,2),
  bid_bond numeric(14,2),
  performance_guarantee numeric(14,2),
  required_documents text,
  technical_status text,
  financial_status text,
  competitors text,
  result text,
  award_value numeric(14,2),
  currency text default 'PKR'::text,
  delivery_schedule text,
  payment_terms text,
  owner_id uuid,
  notes text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone
);

create table if not exists public.pharma_territories (
  id uuid not null default gen_random_uuid(),
  code text,
  name text not null,
  level text not null,
  parent_id uuid,
  country_code text,
  manager_id uuid,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_therapeutic_categories (
  code text not null,
  name text not null,
  parent_code text,
  sort_order integer default 100,
  is_active boolean not null default true
);

create table if not exists public.pharma_toll_contracts (
  id uuid not null default gen_random_uuid(),
  contract_code text,
  enquiry_id uuid,
  offer_id uuid,
  client_org uuid,
  plant_id uuid,
  product_id uuid,
  nda_signed boolean not null default false,
  technical_agreement boolean not null default false,
  quality_agreement boolean not null default false,
  commercial_agreement boolean not null default false,
  contract_value numeric(14,2),
  currency text default 'PKR'::text,
  start_date date,
  end_date date,
  forecast_qty numeric(14,2),
  payment_terms text,
  status text not null default 'draft'::text,
  notes text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_toll_enquiries (
  id uuid not null default gen_random_uuid(),
  enquiry_code text,
  client_org uuid,
  product_concept text not null,
  generic_name text,
  dosage_form text,
  strength text,
  pack_size text,
  annual_qty numeric(14,2),
  initial_batch_qty numeric(14,2),
  target_market text,
  required_certifications text,
  registration_by text,
  raw_material_by text,
  packaging_by text,
  artwork_by text,
  testing_requirements text,
  stability_requirements text,
  target_price numeric(14,4),
  currency text default 'PKR'::text,
  required_by date,
  is_confidential boolean not null default true,
  status text not null default 'new'::text,
  lost_reason text,
  owner_id uuid,
  notes text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  deleted_at timestamp with time zone
);

create table if not exists public.pharma_toll_offers (
  id uuid not null default gen_random_uuid(),
  offer_code text,
  enquiry_id uuid not null,
  plant_id uuid not null,
  development_fee numeric(14,2) default 0,
  formulation_fee numeric(14,2) default 0,
  trial_batch_fee numeric(14,2) default 0,
  stability_fee numeric(14,2) default 0,
  regulatory_fee numeric(14,2) default 0,
  raw_material_cost numeric(14,2) default 0,
  packaging_cost numeric(14,2) default 0,
  conversion_cost numeric(14,2) default 0,
  testing_cost numeric(14,2) default 0,
  batch_release_cost numeric(14,2) default 0,
  freight_cost numeric(14,2) default 0,
  warehousing_cost numeric(14,2) default 0,
  insurance_cost numeric(14,2) default 0,
  jco_consultancy_fee numeric(14,2) default 0,
  jco_commission_pct numeric(5,2) default 0,
  tax_pct numeric(5,2) default 0,
  currency text not null default 'PKR'::text,
  lead_time_days integer,
  min_batch_size numeric(14,2),
  validity_date date,
  status text not null default 'received'::text,
  evaluation_note text,
  rejection_reason text,
  created_by uuid default auth.uid(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now(),
  plant_cost_total numeric(14,2) generated always as (((((((((((((COALESCE(development_fee, (0)::numeric) + COALESCE(formulation_fee, (0)::numeric)) + COALESCE(trial_batch_fee, (0)::numeric)) + COALESCE(stability_fee, (0)::numeric)) + COALESCE(regulatory_fee, (0)::numeric)) + COALESCE(raw_material_cost, (0)::numeric)) + COALESCE(packaging_cost, (0)::numeric)) + COALESCE(conversion_cost, (0)::numeric)) + COALESCE(testing_cost, (0)::numeric)) + COALESCE(batch_release_cost, (0)::numeric)) + COALESCE(freight_cost, (0)::numeric)) + COALESCE(warehousing_cost, (0)::numeric)) + COALESCE(insurance_cost, (0)::numeric))) stored,
  jco_earning numeric(14,2) generated always as (round((COALESCE(jco_consultancy_fee, (0)::numeric) + ((((((((((((((COALESCE(development_fee, (0)::numeric) + COALESCE(formulation_fee, (0)::numeric)) + COALESCE(trial_batch_fee, (0)::numeric)) + COALESCE(stability_fee, (0)::numeric)) + COALESCE(regulatory_fee, (0)::numeric)) + COALESCE(raw_material_cost, (0)::numeric)) + COALESCE(packaging_cost, (0)::numeric)) + COALESCE(conversion_cost, (0)::numeric)) + COALESCE(testing_cost, (0)::numeric)) + COALESCE(batch_release_cost, (0)::numeric)) + COALESCE(freight_cost, (0)::numeric)) + COALESCE(warehousing_cost, (0)::numeric)) + COALESCE(insurance_cost, (0)::numeric)) * COALESCE(jco_commission_pct, (0)::numeric)) / (100)::numeric)), 2)) stored,
  client_price numeric(14,2) generated always as (round((((((((((((((((COALESCE(development_fee, (0)::numeric) + COALESCE(formulation_fee, (0)::numeric)) + COALESCE(trial_batch_fee, (0)::numeric)) + COALESCE(stability_fee, (0)::numeric)) + COALESCE(regulatory_fee, (0)::numeric)) + COALESCE(raw_material_cost, (0)::numeric)) + COALESCE(packaging_cost, (0)::numeric)) + COALESCE(conversion_cost, (0)::numeric)) + COALESCE(testing_cost, (0)::numeric)) + COALESCE(batch_release_cost, (0)::numeric)) + COALESCE(freight_cost, (0)::numeric)) + COALESCE(warehousing_cost, (0)::numeric)) + COALESCE(insurance_cost, (0)::numeric)) + COALESCE(jco_consultancy_fee, (0)::numeric)) + ((((((((((((((COALESCE(development_fee, (0)::numeric) + COALESCE(formulation_fee, (0)::numeric)) + COALESCE(trial_batch_fee, (0)::numeric)) + COALESCE(stability_fee, (0)::numeric)) + COALESCE(regulatory_fee, (0)::numeric)) + COALESCE(raw_material_cost, (0)::numeric)) + COALESCE(packaging_cost, (0)::numeric)) + COALESCE(conversion_cost, (0)::numeric)) + COALESCE(testing_cost, (0)::numeric)) + COALESCE(batch_release_cost, (0)::numeric)) + COALESCE(freight_cost, (0)::numeric)) + COALESCE(warehousing_cost, (0)::numeric)) + COALESCE(insurance_cost, (0)::numeric)) * COALESCE(jco_commission_pct, (0)::numeric)) / (100)::numeric)) * ((1)::numeric + (COALESCE(tax_pct, (0)::numeric) / (100)::numeric))), 2)) stored
);

create table if not exists public.pharma_visit_plans (
  id uuid not null default gen_random_uuid(),
  user_id uuid not null,
  plan_date date not null,
  territory_id uuid,
  planned_calls integer,
  objective text,
  status text not null default 'planned'::text,
  manager_note text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_visits (
  id uuid not null default gen_random_uuid(),
  visit_code text,
  visit_type text not null,
  doctor_id uuid,
  hospital_id uuid,
  pharmacy_id uuid,
  distributor_id uuid,
  plan_id uuid,
  campaign_id uuid,
  visited_by uuid not null default auth.uid(),
  planned_at timestamp with time zone,
  visited_at timestamp with time zone not null default now(),
  location text,
  latitude numeric(9,6),
  longitude numeric(9,6),
  objective text,
  products_detailed uuid[],
  discussion_notes text,
  questions_raised text,
  objections text,
  outcome text,
  commitment text,
  estimated_potential numeric(14,2),
  follow_up_date date,
  next_action text,
  status text not null default 'completed'::text,
  manager_reviewed boolean not null default false,
  reviewed_by uuid,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.pharma_warehouses (
  id uuid not null default gen_random_uuid(),
  code text,
  name text not null,
  org_id uuid,
  distributor_id uuid,
  territory_id uuid,
  city text,
  address text,
  cold_chain boolean not null default false,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.profiles (
  id uuid not null,
  role text not null default 'client'::text,
  client_id uuid,
  full_name text,
  email text,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.social_assets (
  id uuid not null default gen_random_uuid(),
  storage_path text not null,
  kind text not null default 'image'::text,
  tags text[] not null default '{}'::text[],
  caption_hint text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.social_audit_log (
  id bigint not null generated always as identity,
  action social_audit_action not null,
  entity text,
  entity_id uuid,
  actor text not null default 'social-agent'::text,
  detail jsonb,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.social_brand_voice (
  id uuid not null default gen_random_uuid(),
  name text not null default 'JABRAN & CO.'::text,
  tone text,
  pillars text[] not null default '{}'::text[],
  banned_topics text[] not null default '{}'::text[],
  do_rules text,
  dont_rules text,
  sample_posts text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.social_channels (
  id uuid not null default gen_random_uuid(),
  platform text not null,
  handle text,
  publishing_layer text not null default 'postiz'::text,
  external_ref text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.social_content_calendar (
  id uuid not null default gen_random_uuid(),
  plan_date date not null,
  pillar text,
  theme text not null,
  brief text,
  status social_calendar_status not null default 'planned'::social_calendar_status,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.social_engagement (
  id uuid not null default gen_random_uuid(),
  platform text not null,
  external_id text,
  author text,
  message text,
  draft_reply text,
  final_reply text,
  status social_engagement_status not null default 'new'::social_engagement_status,
  escalated boolean not null default false,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.social_posts (
  id uuid not null default gen_random_uuid(),
  calendar_id uuid,
  caption text,
  hashtags text[] not null default '{}'::text[],
  asset_id uuid,
  target_channels text[] not null default '{}'::text[],
  scheduled_at timestamp with time zone,
  status social_post_status not null default 'draft'::social_post_status,
  guardrail_verdict jsonb,
  platform_post_ids jsonb,
  error text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.social_settings (
  id smallint not null default 1,
  autoposting_enabled boolean not null default false,
  dry_run boolean not null default true,
  timezone text not null default 'Asia/Karachi'::text,
  max_posts_per_day integer not null default 3,
  max_replies_per_hour integer not null default 20,
  default_publishing_layer text not null default 'postiz'::text,
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.training_assignments (
  id uuid not null default gen_random_uuid(),
  client_id uuid not null,
  module_id uuid not null,
  assigned_at timestamp with time zone not null default now(),
  completed boolean not null default false,
  completed_at timestamp with time zone
);

create table if not exists public.training_certificates (
  id uuid not null default gen_random_uuid(),
  client_id uuid not null,
  module_id uuid not null,
  certificate_code text not null,
  issued_at timestamp with time zone not null default now()
);

create table if not exists public.training_modules (
  id uuid not null default gen_random_uuid(),
  title text not null,
  description text,
  category text,
  content_type text not null default 'mixed'::text,
  content_url text,
  content_text text,
  passing_score integer not null default 70,
  created_at timestamp with time zone not null default now()
);

create table if not exists public.training_quiz_attempts (
  id uuid not null default gen_random_uuid(),
  client_id uuid not null,
  module_id uuid not null,
  score integer not null,
  total_questions integer not null,
  passed boolean not null,
  attempted_at timestamp with time zone not null default now()
);

create table if not exists public.training_quiz_questions (
  id uuid not null default gen_random_uuid(),
  module_id uuid not null,
  question_text text not null,
  option_a text not null,
  option_b text not null,
  option_c text not null,
  option_d text not null,
  correct_option text not null,
  order_index integer default 0
);

alter sequence public.ai_public_rate_events_id_seq owned by public.ai_public_rate_events.id;

-- ---------------------------------------------------------------------------
-- Constraints: primary keys (182), unique (82), check (303), foreign keys (345)
-- Not idempotent: re-running on an existing schema errors on duplicates.
-- ---------------------------------------------------------------------------

-- Primary keys
alter table public.ai_agent_configs add constraint ai_agent_configs_pkey PRIMARY KEY (id);
alter table public.ai_agent_feedback add constraint ai_agent_feedback_pkey PRIMARY KEY (id);
alter table public.ai_agent_handoffs add constraint ai_agent_handoffs_pkey PRIMARY KEY (id);
alter table public.ai_conversation_summaries add constraint ai_conversation_summaries_pkey PRIMARY KEY (id);
alter table public.ai_conversations add constraint ai_conversations_pkey PRIMARY KEY (id);
alter table public.ai_messages add constraint ai_messages_pkey PRIMARY KEY (id);
alter table public.ai_prompt_versions add constraint ai_prompt_versions_pkey PRIMARY KEY (id);
alter table public.ai_public_rate_events add constraint ai_public_rate_events_pkey PRIMARY KEY (id);
alter table public.ai_usage_log add constraint ai_usage_log_pkey PRIMARY KEY (id);
alter table public.analytics_accounts add constraint analytics_accounts_pkey PRIMARY KEY (id);
alter table public.analytics_alerts add constraint analytics_alerts_pkey PRIMARY KEY (id);
alter table public.analytics_attribution add constraint analytics_attribution_pkey PRIMARY KEY (id);
alter table public.analytics_campaigns add constraint analytics_campaigns_pkey PRIMARY KEY (id);
alter table public.analytics_connections add constraint analytics_connections_pkey PRIMARY KEY (id);
alter table public.analytics_content_metrics add constraint analytics_content_metrics_pkey PRIMARY KEY (id);
alter table public.analytics_conversion_events add constraint analytics_conversion_events_pkey PRIMARY KEY (id);
alter table public.analytics_daily_metrics add constraint analytics_daily_metrics_pkey PRIMARY KEY (id);
alter table public.analytics_data_quality_events add constraint analytics_data_quality_events_pkey PRIMARY KEY (id);
alter table public.analytics_fact_map add constraint analytics_fact_map_pkey PRIMARY KEY (fact);
alter table public.analytics_generated_reports add constraint analytics_generated_reports_pkey PRIMARY KEY (id);
alter table public.analytics_metric_definitions add constraint analytics_metric_definitions_pkey PRIMARY KEY (code);
alter table public.analytics_oauth_states add constraint analytics_oauth_states_pkey PRIMARY KEY (state);
alter table public.analytics_oauth_tokens add constraint analytics_oauth_tokens_pkey PRIMARY KEY (provider);
alter table public.analytics_prompt_history add constraint analytics_prompt_history_pkey PRIMARY KEY (id);
alter table public.analytics_role_permissions add constraint analytics_role_permissions_pkey PRIMARY KEY (role, permission);
alter table public.analytics_sync_jobs add constraint analytics_sync_jobs_pkey PRIMARY KEY (id);
alter table public.audit_findings add constraint audit_findings_pkey PRIMARY KEY (id);
alter table public.blog_posts add constraint blog_posts_pkey PRIMARY KEY (id);
alter table public.case_studies add constraint case_studies_pkey PRIMARY KEY (id);
alter table public.case_study_approvals add constraint case_study_approvals_pkey PRIMARY KEY (case_study_id);
alter table public.client_actions add constraint client_actions_pkey PRIMARY KEY (id);
alter table public.client_documents add constraint client_documents_pkey PRIMARY KEY (id);
alter table public.client_kpis add constraint client_kpis_pkey PRIMARY KEY (id);
alter table public.client_meetings add constraint client_meetings_pkey PRIMARY KEY (id);
alter table public.client_reports add constraint client_reports_pkey PRIMARY KEY (id);
alter table public.clients add constraint clients_pkey PRIMARY KEY (id);
alter table public.contact_submissions add constraint contact_submissions_pkey PRIMARY KEY (id);
alter table public.crm_activity_events add constraint crm_activity_events_pkey PRIMARY KEY (id);
alter table public.crm_agent_accounts add constraint crm_agent_accounts_pkey PRIMARY KEY (id);
alter table public.crm_ai_actions add constraint crm_ai_actions_pkey PRIMARY KEY (id);
alter table public.crm_ai_agents add constraint crm_ai_agents_pkey PRIMARY KEY (id);
alter table public.crm_alert_dismissals add constraint crm_alert_dismissals_pkey PRIMARY KEY (user_id, alert_key);
alter table public.crm_allocation_rules add constraint crm_allocation_rules_pkey PRIMARY KEY (cost_pool);
alter table public.crm_allocation_targets add constraint crm_allocation_targets_pkey PRIMARY KEY (id);
alter table public.crm_attachment_categories add constraint crm_attachment_categories_pkey PRIMARY KEY (code);
alter table public.crm_attachment_events add constraint crm_attachment_events_pkey PRIMARY KEY (id);
alter table public.crm_attachment_policy add constraint crm_attachment_policy_pkey PRIMARY KEY (id);
alter table public.crm_attachments add constraint crm_attachments_pkey PRIMARY KEY (id);
alter table public.crm_audit_logs add constraint crm_audit_logs_pkey PRIMARY KEY (id);
alter table public.crm_billing_bases add constraint crm_billing_bases_pkey PRIMARY KEY (code);
alter table public.crm_budgets add constraint crm_budgets_pkey PRIMARY KEY (id);
alter table public.crm_contacts add constraint crm_contacts_pkey PRIMARY KEY (id);
alter table public.crm_cost_allocations add constraint crm_cost_allocations_pkey PRIMARY KEY (id);
alter table public.crm_cost_categories add constraint crm_cost_categories_pkey PRIMARY KEY (code);
alter table public.crm_cost_centres add constraint crm_cost_centres_pkey PRIMARY KEY (id);
alter table public.crm_cost_lines add constraint crm_cost_lines_pkey PRIMARY KEY (id);
alter table public.crm_cost_sheet_items add constraint crm_cost_sheet_items_pkey PRIMARY KEY (id);
alter table public.crm_cost_sheets add constraint crm_cost_sheets_pkey PRIMARY KEY (id);
alter table public.crm_counters add constraint crm_counters_pkey PRIMARY KEY (entity, year);
alter table public.crm_countries add constraint crm_countries_pkey PRIMARY KEY (iso2);
alter table public.crm_custom_values add constraint crm_custom_values_pkey PRIMARY KEY (module, record_id, field_key);
alter table public.crm_customs_records add constraint crm_customs_records_pkey PRIMARY KEY (id);
alter table public.crm_daily_entries add constraint crm_daily_entries_pkey PRIMARY KEY (id);
alter table public.crm_departments add constraint crm_departments_pkey PRIMARY KEY (id);
alter table public.crm_email_log add constraint crm_email_log_pkey PRIMARY KEY (id);
alter table public.crm_employee_allowances add constraint crm_employee_allowances_pkey PRIMARY KEY (id);
alter table public.crm_employee_cost_history add constraint crm_employee_cost_history_pkey PRIMARY KEY (id);
alter table public.crm_employee_costs add constraint crm_employee_costs_pkey PRIMARY KEY (id);
alter table public.crm_employee_profiles add constraint crm_employee_profiles_pkey PRIMARY KEY (user_id);
alter table public.crm_enquiries add constraint crm_enquiries_pkey PRIMARY KEY (id);
alter table public.crm_enquiry_activity add constraint crm_enquiry_activity_pkey PRIMARY KEY (id);
alter table public.crm_expenses add constraint crm_expenses_pkey PRIMARY KEY (id);
alter table public.crm_field_config add constraint crm_field_config_pkey PRIMARY KEY (id);
alter table public.crm_fixed_expense_history add constraint crm_fixed_expense_history_pkey PRIMARY KEY (id);
alter table public.crm_fixed_expenses add constraint crm_fixed_expenses_pkey PRIMARY KEY (id);
alter table public.crm_invoice_items add constraint crm_invoice_items_pkey PRIMARY KEY (id);
alter table public.crm_invoices add constraint crm_invoices_pkey PRIMARY KEY (id);
alter table public.crm_job_roles add constraint crm_job_roles_pkey PRIMARY KEY (id);
alter table public.crm_login_history add constraint crm_login_history_pkey PRIMARY KEY (id);
alter table public.crm_notifications add constraint crm_notifications_pkey PRIMARY KEY (id);
alter table public.crm_opportunities add constraint crm_opportunities_pkey PRIMARY KEY (id);
alter table public.crm_opportunity_activity add constraint crm_opportunity_activity_pkey PRIMARY KEY (id);
alter table public.crm_order_events add constraint crm_order_events_pkey PRIMARY KEY (id);
alter table public.crm_order_items add constraint crm_order_items_pkey PRIMARY KEY (id);
alter table public.crm_order_milestones add constraint crm_order_milestones_pkey PRIMARY KEY (id);
alter table public.crm_order_tracking add constraint crm_order_tracking_pkey PRIMARY KEY (id);
alter table public.crm_orders add constraint crm_orders_pkey PRIMARY KEY (id);
alter table public.crm_organizations add constraint crm_organizations_pkey PRIMARY KEY (id);
alter table public.crm_outsourced_categories add constraint crm_outsourced_categories_pkey PRIMARY KEY (code);
alter table public.crm_payment_allocations add constraint crm_payment_allocations_pkey PRIMARY KEY (id);
alter table public.crm_payments add constraint crm_payments_pkey PRIMARY KEY (id);
alter table public.crm_portal_members add constraint crm_portal_members_pkey PRIMARY KEY (id);
alter table public.crm_project_milestones add constraint crm_project_milestones_pkey PRIMARY KEY (id);
alter table public.crm_projects add constraint crm_projects_pkey PRIMARY KEY (id);
alter table public.crm_prospects add constraint crm_prospects_pkey PRIMARY KEY (id);
alter table public.crm_quotation_approvals add constraint crm_quotation_approvals_pkey PRIMARY KEY (id);
alter table public.crm_quotation_items add constraint crm_quotation_items_pkey PRIMARY KEY (id);
alter table public.crm_quotations add constraint crm_quotations_pkey PRIMARY KEY (id);
alter table public.crm_receipts add constraint crm_receipts_pkey PRIMARY KEY (id);
alter table public.crm_record_assignments add constraint crm_record_assignments_pkey PRIMARY KEY (id);
alter table public.crm_rm_policy add constraint crm_rm_policy_pkey PRIMARY KEY (id);
alter table public.crm_service_branches add constraint crm_service_branches_pkey PRIMARY KEY (code);
alter table public.crm_service_milestone_templates add constraint crm_service_milestone_templates_pkey PRIMARY KEY (id);
alter table public.crm_service_offers add constraint crm_service_offers_pkey PRIMARY KEY (id);
alter table public.crm_service_provider_bank add constraint crm_service_provider_bank_pkey PRIMARY KEY (provider_id);
alter table public.crm_service_providers add constraint crm_service_providers_pkey PRIMARY KEY (id);
alter table public.crm_services add constraint crm_services_pkey PRIMARY KEY (id);
alter table public.crm_settings add constraint crm_settings_pkey PRIMARY KEY (key);
alter table public.crm_shipments add constraint crm_shipments_pkey PRIMARY KEY (id);
alter table public.crm_staff_roles add constraint crm_staff_roles_pkey PRIMARY KEY (id);
alter table public.crm_stockists add constraint crm_stockists_pkey PRIMARY KEY (id);
alter table public.crm_subscription_price_history add constraint crm_subscription_price_history_pkey PRIMARY KEY (id);
alter table public.crm_subscriptions add constraint crm_subscriptions_pkey PRIMARY KEY (id);
alter table public.crm_supplier_offers add constraint crm_supplier_offers_pkey PRIMARY KEY (id);
alter table public.crm_timesheets add constraint crm_timesheets_pkey PRIMARY KEY (id);
alter table public.crm_tracking_policy add constraint crm_tracking_policy_pkey PRIMARY KEY (id);
alter table public.crm_tracking_template_steps add constraint crm_tracking_template_steps_pkey PRIMARY KEY (id);
alter table public.crm_tracking_templates add constraint crm_tracking_templates_pkey PRIMARY KEY (id);
alter table public.crm_vendors add constraint crm_vendors_pkey PRIMARY KEY (id);
alter table public.featured_topics add constraint featured_topics_pkey PRIMARY KEY (id);
alter table public.pharma_adverse_events add constraint pharma_adverse_events_pkey PRIMARY KEY (id);
alter table public.pharma_campaigns add constraint pharma_campaigns_pkey PRIMARY KEY (id);
alter table public.pharma_companies add constraint pharma_companies_pkey PRIMARY KEY (org_id);
alter table public.pharma_company_contacts add constraint pharma_company_contacts_pkey PRIMARY KEY (id);
alter table public.pharma_complaints add constraint pharma_complaints_pkey PRIMARY KEY (id);
alter table public.pharma_distributor_products add constraint pharma_distributor_products_pkey PRIMARY KEY (distributor_id, product_id);
alter table public.pharma_distributor_territories add constraint pharma_distributor_territories_pkey PRIMARY KEY (distributor_id, territory_id);
alter table public.pharma_distributors add constraint pharma_distributors_pkey PRIMARY KEY (id);
alter table public.pharma_doctor_affiliations add constraint pharma_doctor_affiliations_pkey PRIMARY KEY (id);
alter table public.pharma_doctor_products add constraint pharma_doctor_products_pkey PRIMARY KEY (doctor_id, product_id);
alter table public.pharma_doctors add constraint pharma_doctors_pkey PRIMARY KEY (id);
alter table public.pharma_dosage_forms add constraint pharma_dosage_forms_pkey PRIMARY KEY (code);
alter table public.pharma_engagement_spend add constraint pharma_engagement_spend_pkey PRIMARY KEY (id);
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_pkey PRIMARY KEY (id);
alter table public.pharma_field_force add constraint pharma_field_force_pkey PRIMARY KEY (user_id);
alter table public.pharma_hospitals add constraint pharma_hospitals_pkey PRIMARY KEY (id);
alter table public.pharma_inventory_batches add constraint pharma_inventory_batches_pkey PRIMARY KEY (id);
alter table public.pharma_inventory_movements add constraint pharma_inventory_movements_pkey PRIMARY KEY (id);
alter table public.pharma_invoices add constraint pharma_invoices_pkey PRIMARY KEY (id);
alter table public.pharma_offer_categories add constraint pharma_offer_categories_pkey PRIMARY KEY (code);
alter table public.pharma_offer_products add constraint pharma_offer_products_pkey PRIMARY KEY (offer_id, product_id);
alter table public.pharma_offer_targets add constraint pharma_offer_targets_pkey PRIMARY KEY (id);
alter table public.pharma_pharmacies add constraint pharma_pharmacies_pkey PRIMARY KEY (id);
alter table public.pharma_plant_capabilities add constraint pharma_plant_capabilities_pkey PRIMARY KEY (plant_code_id, dosage_form);
alter table public.pharma_plants add constraint pharma_plants_pkey PRIMARY KEY (id);
alter table public.pharma_product_prices add constraint pharma_product_prices_pkey PRIMARY KEY (id);
alter table public.pharma_product_regulatory add constraint pharma_product_regulatory_pkey PRIMARY KEY (id);
alter table public.pharma_production_batches add constraint pharma_production_batches_pkey PRIMARY KEY (id);
alter table public.pharma_products add constraint pharma_products_pkey PRIMARY KEY (id);
alter table public.pharma_promotional_offers add constraint pharma_promotional_offers_pkey PRIMARY KEY (id);
alter table public.pharma_recalls add constraint pharma_recalls_pkey PRIMARY KEY (id);
alter table public.pharma_receipts add constraint pharma_receipts_pkey PRIMARY KEY (id);
alter table public.pharma_returns add constraint pharma_returns_pkey PRIMARY KEY (id);
alter table public.pharma_role_permissions add constraint pharma_role_permissions_pkey PRIMARY KEY (role, permission);
alter table public.pharma_sales_order_items add constraint pharma_sales_order_items_pkey PRIMARY KEY (id);
alter table public.pharma_sales_orders add constraint pharma_sales_orders_pkey PRIMARY KEY (id);
alter table public.pharma_sample_items add constraint pharma_sample_items_pkey PRIMARY KEY (id);
alter table public.pharma_sample_transactions add constraint pharma_sample_transactions_pkey PRIMARY KEY (id);
alter table public.pharma_tender_products add constraint pharma_tender_products_pkey PRIMARY KEY (id);
alter table public.pharma_tenders add constraint pharma_tenders_pkey PRIMARY KEY (id);
alter table public.pharma_territories add constraint pharma_territories_pkey PRIMARY KEY (id);
alter table public.pharma_therapeutic_categories add constraint pharma_therapeutic_categories_pkey PRIMARY KEY (code);
alter table public.pharma_toll_contracts add constraint pharma_toll_contracts_pkey PRIMARY KEY (id);
alter table public.pharma_toll_enquiries add constraint pharma_toll_enquiries_pkey PRIMARY KEY (id);
alter table public.pharma_toll_offers add constraint pharma_toll_offers_pkey PRIMARY KEY (id);
alter table public.pharma_visit_plans add constraint pharma_visit_plans_pkey PRIMARY KEY (id);
alter table public.pharma_visits add constraint pharma_visits_pkey PRIMARY KEY (id);
alter table public.pharma_warehouses add constraint pharma_warehouses_pkey PRIMARY KEY (id);
alter table public.profiles add constraint profiles_pkey PRIMARY KEY (id);
alter table public.social_assets add constraint social_assets_pkey PRIMARY KEY (id);
alter table public.social_audit_log add constraint social_audit_log_pkey PRIMARY KEY (id);
alter table public.social_brand_voice add constraint social_brand_voice_pkey PRIMARY KEY (id);
alter table public.social_channels add constraint social_channels_pkey PRIMARY KEY (id);
alter table public.social_content_calendar add constraint social_content_calendar_pkey PRIMARY KEY (id);
alter table public.social_engagement add constraint social_engagement_pkey PRIMARY KEY (id);
alter table public.social_posts add constraint social_posts_pkey PRIMARY KEY (id);
alter table public.social_settings add constraint social_settings_pkey PRIMARY KEY (id);
alter table public.training_assignments add constraint training_assignments_pkey PRIMARY KEY (id);
alter table public.training_certificates add constraint training_certificates_pkey PRIMARY KEY (id);
alter table public.training_modules add constraint training_modules_pkey PRIMARY KEY (id);
alter table public.training_quiz_attempts add constraint training_quiz_attempts_pkey PRIMARY KEY (id);
alter table public.training_quiz_questions add constraint training_quiz_questions_pkey PRIMARY KEY (id);

-- Unique constraints
alter table public.ai_agent_configs add constraint ai_agent_configs_singleton_key UNIQUE (singleton);
alter table public.ai_conversations add constraint ai_conversations_conversation_reference_key UNIQUE (conversation_reference);
alter table public.analytics_accounts add constraint analytics_accounts_connection_id_external_account_id_key UNIQUE (connection_id, external_account_id);
alter table public.analytics_attribution add constraint analytics_attribution_entity_entity_id_key UNIQUE (entity, entity_id);
alter table public.analytics_campaigns add constraint analytics_campaigns_source_external_id_period_start_period__key UNIQUE (source, external_id, period_start, period_end);
alter table public.analytics_connections add constraint analytics_connections_platform_key UNIQUE (platform);
alter table public.analytics_daily_metrics add constraint analytics_daily_metrics_source_metric_date_dimension_org_id_key UNIQUE (source, metric_date, dimension, org_id);
alter table public.crm_agent_accounts add constraint crm_agent_accounts_agent_name_key UNIQUE (agent_name);
alter table public.crm_agent_accounts add constraint crm_agent_accounts_user_id_key UNIQUE (user_id);
alter table public.crm_ai_agents add constraint crm_ai_agents_slug_key UNIQUE (slug);
alter table public.crm_allocation_targets add constraint crm_allocation_targets_order_id_key UNIQUE (order_id);
alter table public.crm_budgets add constraint crm_budgets_period_cost_centre_id_key UNIQUE NULLS NOT DISTINCT (period, cost_centre_id);
alter table public.crm_cost_allocations add constraint crm_cost_allocations_period_order_id_cost_pool_key UNIQUE (period, order_id, cost_pool);
alter table public.crm_cost_centres add constraint crm_cost_centres_code_key UNIQUE (code);
alter table public.crm_cost_lines add constraint crm_cost_lines_code_key UNIQUE (code);
alter table public.crm_cost_sheets add constraint crm_cost_sheets_sheet_number_key UNIQUE (sheet_number);
alter table public.crm_countries add constraint crm_countries_name_key UNIQUE (name);
alter table public.crm_daily_entries add constraint crm_daily_entries_entry_number_key UNIQUE (entry_number);
alter table public.crm_departments add constraint crm_departments_code_key UNIQUE (code);
alter table public.crm_employee_costs add constraint crm_employee_costs_user_id_key UNIQUE (user_id);
alter table public.crm_enquiries add constraint crm_enquiries_enquiry_number_key UNIQUE (enquiry_number);
alter table public.crm_expenses add constraint crm_expenses_expense_number_key UNIQUE (expense_number);
alter table public.crm_field_config add constraint crm_field_config_module_field_id_key UNIQUE (module, field_id);
alter table public.crm_fixed_expenses add constraint crm_fixed_expenses_expense_number_key UNIQUE (expense_number);
alter table public.crm_invoices add constraint crm_invoices_invoice_number_key UNIQUE (invoice_number);
alter table public.crm_job_roles add constraint crm_job_roles_code_key UNIQUE (code);
alter table public.crm_opportunities add constraint crm_opportunities_opportunity_number_key UNIQUE (opportunity_number);
alter table public.crm_order_milestones add constraint crm_order_milestones_order_id_sequence_number_key UNIQUE (order_id, sequence_number);
alter table public.crm_order_tracking add constraint crm_order_tracking_order_id_key UNIQUE (order_id);
alter table public.crm_orders add constraint crm_orders_order_number_key UNIQUE (order_number);
alter table public.crm_organizations add constraint crm_organizations_org_number_key UNIQUE (org_number);
alter table public.crm_payment_allocations add constraint crm_payment_allocations_payment_id_invoice_id_key UNIQUE (payment_id, invoice_id);
alter table public.crm_payments add constraint crm_payments_payment_number_key UNIQUE (payment_number);
alter table public.crm_portal_members add constraint crm_portal_members_user_id_organization_id_key UNIQUE (user_id, organization_id);
alter table public.crm_projects add constraint crm_projects_project_number_key UNIQUE (project_number);
alter table public.crm_prospects add constraint crm_prospects_prospect_number_key UNIQUE (prospect_number);
alter table public.crm_quotations add constraint crm_quotations_quotation_number_version_key UNIQUE (quotation_number, version);
alter table public.crm_receipts add constraint crm_receipts_receipt_number_key UNIQUE (receipt_number);
alter table public.crm_rm_policy add constraint crm_rm_policy_singleton_key UNIQUE (singleton);
alter table public.crm_service_offers add constraint crm_service_offers_offer_number_key UNIQUE (offer_number);
alter table public.crm_service_providers add constraint crm_service_providers_provider_number_key UNIQUE (provider_number);
alter table public.crm_services add constraint crm_services_name_key UNIQUE (name);
alter table public.crm_services add constraint crm_services_slug_key UNIQUE (slug);
alter table public.crm_shipments add constraint crm_shipments_shipment_number_key UNIQUE (shipment_number);
alter table public.crm_staff_roles add constraint crm_staff_roles_user_id_role_key UNIQUE (user_id, role);
alter table public.crm_stockists add constraint crm_stockists_stockist_number_key UNIQUE (stockist_number);
alter table public.crm_subscriptions add constraint crm_subscriptions_subscription_number_key UNIQUE (subscription_number);
alter table public.crm_supplier_offers add constraint crm_supplier_offers_offer_number_key UNIQUE (offer_number);
alter table public.crm_tracking_policy add constraint crm_tracking_policy_singleton_key UNIQUE (singleton);
alter table public.crm_tracking_template_steps add constraint crm_tracking_template_steps_template_id_sequence_number_key UNIQUE (template_id, sequence_number);
alter table public.crm_vendors add constraint crm_vendors_vendor_number_key UNIQUE (vendor_number);
alter table public.pharma_adverse_events add constraint pharma_adverse_events_event_code_key UNIQUE (event_code);
alter table public.pharma_campaigns add constraint pharma_campaigns_campaign_code_key UNIQUE (campaign_code);
alter table public.pharma_companies add constraint pharma_companies_company_code_key UNIQUE (company_code);
alter table public.pharma_complaints add constraint pharma_complaints_complaint_code_key UNIQUE (complaint_code);
alter table public.pharma_distributors add constraint pharma_distributors_distributor_code_key UNIQUE (distributor_code);
alter table public.pharma_doctors add constraint pharma_doctors_doctor_code_key UNIQUE (doctor_code);
alter table public.pharma_hospitals add constraint pharma_hospitals_hospital_code_key UNIQUE (hospital_code);
alter table public.pharma_inventory_batches add constraint pharma_inventory_batches_product_id_batch_number_warehouse__key UNIQUE (product_id, batch_number, warehouse_id);
alter table public.pharma_invoices add constraint pharma_invoices_invoice_number_key UNIQUE (invoice_number);
alter table public.pharma_pharmacies add constraint pharma_pharmacies_pharmacy_code_key UNIQUE (pharmacy_code);
alter table public.pharma_plants add constraint pharma_plants_plant_code_key UNIQUE (plant_code);
alter table public.pharma_production_batches add constraint pharma_production_batches_product_id_batch_number_key UNIQUE (product_id, batch_number);
alter table public.pharma_products add constraint pharma_products_product_code_key UNIQUE (product_code);
alter table public.pharma_promotional_offers add constraint pharma_promotional_offers_offer_code_key UNIQUE (offer_code);
alter table public.pharma_recalls add constraint pharma_recalls_recall_code_key UNIQUE (recall_code);
alter table public.pharma_receipts add constraint pharma_receipts_receipt_number_key UNIQUE (receipt_number);
alter table public.pharma_returns add constraint pharma_returns_return_code_key UNIQUE (return_code);
alter table public.pharma_sales_orders add constraint pharma_sales_orders_order_number_key UNIQUE (order_number);
alter table public.pharma_sample_items add constraint pharma_sample_items_item_code_key UNIQUE (item_code);
alter table public.pharma_tenders add constraint pharma_tenders_tender_code_key UNIQUE (tender_code);
alter table public.pharma_territories add constraint pharma_territories_code_key UNIQUE (code);
alter table public.pharma_toll_contracts add constraint pharma_toll_contracts_contract_code_key UNIQUE (contract_code);
alter table public.pharma_toll_enquiries add constraint pharma_toll_enquiries_enquiry_code_key UNIQUE (enquiry_code);
alter table public.pharma_toll_offers add constraint pharma_toll_offers_offer_code_key UNIQUE (offer_code);
alter table public.pharma_visit_plans add constraint pharma_visit_plans_user_id_plan_date_key UNIQUE (user_id, plan_date);
alter table public.pharma_visits add constraint pharma_visits_visit_code_key UNIQUE (visit_code);
alter table public.pharma_warehouses add constraint pharma_warehouses_code_key UNIQUE (code);
alter table public.social_channels add constraint social_channels_platform_handle_key UNIQUE (platform, handle);
alter table public.social_engagement add constraint social_engagement_platform_external_id_key UNIQUE (platform, external_id);
alter table public.training_assignments add constraint training_assignments_client_id_module_id_key UNIQUE (client_id, module_id);
alter table public.training_certificates add constraint training_certificates_certificate_code_key UNIQUE (certificate_code);

-- Check constraints
alter table public.ai_agent_configs add constraint ai_agent_configs_singleton_check CHECK (singleton);
alter table public.ai_agent_feedback add constraint ai_agent_feedback_rating_check CHECK (((rating >= 1) AND (rating <= 5)));
alter table public.ai_agent_handoffs add constraint ai_agent_handoffs_status_check CHECK ((status = ANY (ARRAY['open'::text, 'accepted'::text, 'resolved'::text, 'cancelled'::text])));
alter table public.ai_conversations add constraint ai_conversations_conversation_type_check CHECK ((conversation_type = ANY (ARRAY['public'::text, 'client'::text, 'internal'::text])));
alter table public.ai_conversations add constraint ai_conversations_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text])));
alter table public.ai_conversations add constraint ai_conversations_status_check CHECK ((status = ANY (ARRAY['ai_active'::text, 'human_requested'::text, 'human_active'::text, 'waiting_client'::text, 'resolved'::text, 'abandoned'::text, 'spam'::text])));
alter table public.ai_messages add constraint ai_messages_message_type_check CHECK ((message_type = ANY (ARRAY['text'::text, 'file'::text, 'system_note'::text, 'proactive'::text, 'handoff'::text, 'qualification'::text])));
alter table public.ai_messages add constraint ai_messages_sender_type_check CHECK ((sender_type = ANY (ARRAY['visitor'::text, 'client'::text, 'assistant'::text, 'staff'::text, 'system'::text])));
alter table public.ai_prompt_versions add constraint ai_prompt_versions_agent_check CHECK ((agent = ANY (ARRAY['public'::text, 'client'::text, 'summary'::text])));
alter table public.analytics_alerts add constraint analytics_alerts_severity_check CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'critical'::text])));
alter table public.analytics_attribution add constraint analytics_attribution_confidence_check CHECK ((confidence = ANY (ARRAY['unknown'::text, 'low'::text, 'medium'::text, 'high'::text])));
alter table public.analytics_connections add constraint analytics_connections_platform_check CHECK ((platform = ANY (ARRAY['crm'::text, 'ga4'::text, 'search_console'::text, 'google_ads'::text, 'meta_business'::text, 'meta_ads'::text, 'linkedin_page'::text, 'linkedin_ads'::text])));
alter table public.analytics_connections add constraint analytics_connections_status_check CHECK ((status = ANY (ARRAY['not_connected'::text, 'credentials_required'::text, 'oauth_setup_required'::text, 'permission_required'::text, 'verification_pending'::text, 'connection_pending'::text, 'connected'::text, 'syncing'::text, 'sync_failed'::text, 'token_expired'::text, 'access_revoked'::text])));
alter table public.analytics_oauth_states add constraint analytics_oauth_states_provider_check CHECK ((provider = ANY (ARRAY['ga4'::text, 'search_console'::text, 'google_ads'::text, 'meta_business'::text, 'meta_ads'::text, 'linkedin_page'::text, 'linkedin_ads'::text])));
alter table public.analytics_sync_jobs add constraint analytics_sync_jobs_status_check CHECK ((status = ANY (ARRAY['running'::text, 'success'::text, 'failed'::text, 'skipped'::text])));
alter table public.audit_findings add constraint audit_findings_category_check CHECK ((category = ANY (ARRAY['bottleneck'::text, 'quality'::text, 'wastage'::text, 'downtime'::text, 'safety'::text, 'recommendation'::text, 'observation'::text, 'production_data'::text, 'machine_data'::text, 'workforce'::text])));
alter table public.audit_findings add constraint audit_findings_severity_check CHECK ((severity = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])));
alter table public.blog_posts add constraint blog_posts_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
alter table public.case_studies add constraint case_studies_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'pending_approval'::text, 'published'::text, 'rejected'::text])));
alter table public.client_actions add constraint client_actions_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text])));
alter table public.client_actions add constraint client_actions_status_check CHECK ((status = ANY (ARRAY['not_started'::text, 'in_progress'::text, 'under_review'::text, 'completed'::text, 'delayed'::text, 'blocked'::text])));
alter table public.client_reports add constraint client_reports_report_type_check CHECK ((report_type = ANY (ARRAY['weekly'::text, 'monthly'::text, 'project_end'::text])));
alter table public.clients add constraint clients_status_check CHECK ((status = ANY (ARRAY['active'::text, 'on_hold'::text, 'completed'::text])));
alter table public.crm_activity_events add constraint crm_activity_events_event_check CHECK ((event = ANY (ARRAY['view'::text, 'print'::text, 'download'::text, 'export'::text])));
alter table public.crm_ai_actions add constraint crm_ai_actions_status_check CHECK ((status = ANY (ARRAY['proposed'::text, 'confirmed'::text, 'cancelled'::text, 'executed'::text, 'failed'::text])));
alter table public.crm_ai_agents add constraint crm_ai_agents_status_check CHECK ((status = ANY (ARRAY['live'::text, 'paused'::text, 'planned'::text, 'retired'::text])));
alter table public.crm_allocation_rules add constraint crm_allocation_rules_cost_pool_check CHECK ((cost_pool = ANY (ARRAY['overhead'::text, 'payroll'::text])));
alter table public.crm_allocation_rules add constraint crm_allocation_rules_method_check CHECK ((method = ANY (ARRAY['revenue_pct'::text, 'hours'::text, 'headcount'::text, 'equal'::text, 'manual_pct'::text])));
alter table public.crm_allocation_targets add constraint crm_allocation_targets_weight_check CHECK ((weight > (0)::numeric));
alter table public.crm_attachment_events add constraint crm_attachment_events_event_type_check CHECK ((event_type = ANY (ARRAY['upload'::text, 'replace'::text, 'rename'::text, 'recategorize'::text, 'visibility_change'::text, 'approve'::text, 'reject'::text, 'archive'::text, 'restore'::text, 'delete_requested'::text, 'signed_link'::text])));
alter table public.crm_attachment_policy add constraint crm_attachment_policy_id_check CHECK (id);
alter table public.crm_attachments add constraint crm_att_approval_chk CHECK ((approval_status = ANY (ARRAY['not_required'::text, 'pending'::text, 'approved'::text, 'rejected'::text])));
alter table public.crm_attachments add constraint crm_att_uploader_chk CHECK ((uploaded_by_type = ANY (ARRAY['staff'::text, 'client'::text, 'system'::text, 'ai_agent'::text])));
alter table public.crm_attachments add constraint crm_att_visibility_chk CHECK ((visibility_scope = ANY (ARRAY['internal'::text, 'assigned_team'::text, 'relationship_manager'::text, 'management'::text, 'client_visible'::text, 'client_uploaded'::text, 'owner_only'::text, 'finance_only'::text, 'legal_confidential'::text])));
alter table public.crm_attachments add constraint crm_attachments_module_check CHECK ((module = ANY (ARRAY['prospects'::text, 'organizations'::text, 'enquiries'::text, 'opportunities'::text, 'vendors'::text, 'quotations'::text, 'cost_sheets'::text, 'supplier_offers'::text, 'orders'::text, 'projects'::text, 'shipments'::text, 'customs'::text, 'invoices'::text, 'payments'::text, 'expenses'::text])));
alter table public.crm_budgets add constraint crm_budgets_amount_check CHECK ((amount >= (0)::numeric));
alter table public.crm_budgets add constraint crm_budgets_period_check CHECK ((period ~ '^\d{4}-\d{2}$'::text));
alter table public.crm_cost_allocations add constraint crm_cost_allocations_cost_pool_check CHECK ((cost_pool = ANY (ARRAY['overhead'::text, 'payroll'::text])));
alter table public.crm_cost_allocations add constraint crm_cost_allocations_period_check CHECK ((period ~ '^\d{4}-\d{2}$'::text));
alter table public.crm_cost_lines add constraint crm_cost_lines_default_borne_by_check CHECK ((default_borne_by = ANY (ARRAY['company'::text, 'client'::text, 'pass_through'::text])));
alter table public.crm_cost_lines add constraint crm_cost_lines_default_unit_check CHECK ((default_unit = ANY (ARRAY['lump_sum'::text, 'hour'::text, 'day'::text, 'month'::text, 'shipment'::text, 'km'::text, 'unit'::text, 'percent'::text])));
alter table public.crm_cost_lines add constraint crm_cost_lines_line_kind_check CHECK ((line_kind = ANY (ARRAY['service_fee'::text, 'internal_cost'::text, 'pass_through'::text, 'tax_duty'::text, 'deposit'::text, 'penalty'::text])));
alter table public.crm_cost_sheet_items add constraint chk_csi_non_negative CHECK (((COALESCE(rate, (0)::numeric) >= (0)::numeric) AND (COALESCE(quantity, (0)::numeric) >= (0)::numeric) AND (COALESCE(resources, 1) >= 0) AND (COALESCE(overtime_hours, (0)::numeric) >= (0)::numeric) AND (COALESCE(overtime_rate, (0)::numeric) >= (0)::numeric) AND (COALESCE(discount_amount, (0)::numeric) >= (0)::numeric)));
alter table public.crm_cost_sheet_items add constraint chk_csi_sane_limits CHECK (((COALESCE(quantity, (0)::numeric) <= (1000000)::numeric) AND (COALESCE(resources, 1) <= 10000)));
alter table public.crm_cost_sheet_items add constraint crm_cost_sheet_items_borne_by_check CHECK ((borne_by = ANY (ARRAY['company'::text, 'client'::text, 'pass_through'::text])));
alter table public.crm_cost_sheets add constraint crm_cost_sheets_contingency_pct_check CHECK (((contingency_pct >= (0)::numeric) AND (contingency_pct <= (100)::numeric)));
alter table public.crm_cost_sheets add constraint crm_cost_sheets_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.crm_cost_sheets add constraint crm_cost_sheets_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'under_review'::text, 'approved'::text, 'locked'::text, 'archived'::text])));
alter table public.crm_countries add constraint crm_countries_iso2_check CHECK ((iso2 ~ '^[A-Z]{2}$'::text));
alter table public.crm_customs_records add constraint crm_customs_records_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'gd_filed'::text, 'assessment'::text, 'examination'::text, 'duty_paid'::text, 'cleared'::text, 'held'::text, 'disputed'::text])));
alter table public.crm_daily_entries add constraint crm_daily_entries_amount_check CHECK ((amount > (0)::numeric));
alter table public.crm_daily_entries add constraint crm_daily_entries_category_check CHECK ((category = ANY (ARRAY['fuel'::text, 'travel'::text, 'food_entertainment'::text, 'courier'::text, 'parking_toll'::text, 'office_supplies'::text, 'software_subscription'::text, 'domain_hosting'::text, 'marketing'::text, 'utilities'::text, 'phone_internet'::text, 'repairs'::text, 'professional_fees'::text, 'customs'::text, 'other'::text])));
alter table public.crm_daily_entries add constraint crm_daily_entries_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
alter table public.crm_employee_allowances add constraint crm_employee_allowances_allowance_type_check CHECK ((allowance_type = ANY (ARRAY['fuel'::text, 'travel'::text, 'food'::text, 'accommodation'::text, 'phone'::text, 'medical'::text, 'other'::text])));
alter table public.crm_employee_allowances add constraint crm_employee_allowances_monthly_amount_check CHECK ((monthly_amount >= (0)::numeric));
alter table public.crm_employee_costs add constraint crm_employee_costs_commission_pct_check CHECK (((commission_pct IS NULL) OR (commission_pct >= (0)::numeric)));
alter table public.crm_employee_costs add constraint crm_employee_costs_consultancy_rate_check CHECK (((consultancy_rate IS NULL) OR (consultancy_rate >= (0)::numeric)));
alter table public.crm_employee_costs add constraint crm_employee_costs_daily_rate_manual_check CHECK (((daily_rate_manual IS NULL) OR (daily_rate_manual >= (0)::numeric)));
alter table public.crm_employee_costs add constraint crm_employee_costs_employer_contributions_check CHECK ((employer_contributions >= (0)::numeric));
alter table public.crm_employee_costs add constraint crm_employee_costs_employment_type_check CHECK ((employment_type = ANY (ARRAY['full_time'::text, 'part_time'::text, 'contract'::text, 'consultant'::text, 'intern'::text, 'daily_wage'::text])));
alter table public.crm_employee_costs add constraint crm_employee_costs_hourly_rate_manual_check CHECK (((hourly_rate_manual IS NULL) OR (hourly_rate_manual >= (0)::numeric)));
alter table public.crm_employee_costs add constraint crm_employee_costs_monthly_bonus_avg_check CHECK ((monthly_bonus_avg >= (0)::numeric));
alter table public.crm_employee_costs add constraint crm_employee_costs_monthly_salary_check CHECK ((monthly_salary >= (0)::numeric));
alter table public.crm_employee_costs add constraint crm_employee_costs_opportunity_cost_hour_check CHECK (((opportunity_cost_hour IS NULL) OR (opportunity_cost_hour >= (0)::numeric)));
alter table public.crm_employee_costs add constraint crm_employee_costs_overtime_rate_check CHECK (((overtime_rate IS NULL) OR (overtime_rate >= (0)::numeric)));
alter table public.crm_employee_costs add constraint crm_employee_costs_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text])));
alter table public.crm_enquiries add constraint crm_enquiries_enquiry_type_check CHECK ((enquiry_type = ANY (ARRAY['service'::text, 'sourcing'::text, 'customs'::text, 'audit'::text, 'training'::text, 'advisory'::text, 'architecture'::text, 'ai_consultancy'::text, 'general'::text])));
alter table public.crm_enquiries add constraint crm_enquiries_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])));
alter table public.crm_enquiries add constraint crm_enquiries_source_check CHECK ((source = ANY (ARRAY['website'::text, 'portal'::text, 'whatsapp'::text, 'email'::text, 'phone'::text, 'referral'::text, 'manual'::text, 'prospect_conversion'::text, 'agent'::text])));
alter table public.crm_enquiries add constraint crm_enquiries_status_check CHECK ((status = ANY (ARRAY['new'::text, 'under_review'::text, 'information_required'::text, 'assigned'::text, 'feasibility_assessment'::text, 'costing_in_progress'::text, 'quotation_in_preparation'::text, 'quotation_submitted'::text, 'negotiation'::text, 'accepted'::text, 'rejected'::text, 'on_hold'::text, 'converted_to_order'::text, 'converted_to_project'::text, 'closed'::text, 'converted_to_opportunity'::text])));
alter table public.crm_enquiries add constraint crm_enquiries_urgency_check CHECK ((urgency = ANY (ARRAY['low'::text, 'normal'::text, 'high'::text, 'urgent'::text])));
alter table public.crm_enquiry_activity add constraint crm_enquiry_activity_kind_check CHECK ((kind = ANY (ARRAY['comment'::text, 'status_change'::text, 'assignment'::text, 'attachment'::text, 'system'::text])));
alter table public.crm_enquiry_activity add constraint crm_enquiry_activity_visibility_check CHECK ((visibility = ANY (ARRAY['internal_only'::text, 'client_visible'::text, 'client_action_required'::text, 'finance_only'::text, 'management_only'::text, 'archived'::text])));
alter table public.crm_expenses add constraint crm_expenses_amount_check CHECK ((amount > (0)::numeric));
alter table public.crm_field_config add constraint crm_field_config_field_type_check CHECK ((field_type = ANY (ARRAY['text'::text, 'textarea'::text, 'number'::text, 'date'::text, 'select'::text, 'checkbox'::text])));
alter table public.crm_field_config add constraint crm_field_config_visibility_scope_check CHECK ((visibility_scope = ANY (ARRAY['staff'::text, 'client_visible'::text, 'internal_only'::text, 'finance_only'::text, 'management_only'::text, 'owner_only'::text])));
alter table public.crm_fixed_expenses add constraint crm_fixed_expenses_amount_check CHECK ((amount >= (0)::numeric));
alter table public.crm_fixed_expenses add constraint crm_fixed_expenses_category_check CHECK ((category = ANY (ARRAY['rent'::text, 'utilities'::text, 'internet_telecom'::text, 'insurance'::text, 'legal'::text, 'audit_accounting'::text, 'software_licenses'::text, 'cloud_hosting'::text, 'domains_email'::text, 'vehicle'::text, 'fuel'::text, 'office_supplies'::text, 'cleaning'::text, 'security'::text, 'maintenance'::text, 'marketing'::text, 'professional_fees'::text, 'banking'::text, 'travel'::text, 'equipment'::text, 'other'::text])));
alter table public.crm_fixed_expenses add constraint crm_fixed_expenses_frequency_check CHECK ((frequency = ANY (ARRAY['daily'::text, 'weekly'::text, 'monthly'::text, 'quarterly'::text, 'half_yearly'::text, 'yearly'::text, 'one_time'::text])));
alter table public.crm_fixed_expenses add constraint crm_fixed_expenses_status_check CHECK ((status = ANY (ARRAY['active'::text, 'paused'::text, 'archived'::text])));
alter table public.crm_invoice_items add constraint crm_invoice_items_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.crm_invoices add constraint crm_invoices_discount_pct_check CHECK (((discount_pct >= (0)::numeric) AND (discount_pct <= (100)::numeric)));
alter table public.crm_invoices add constraint crm_invoices_freight_amount_check CHECK ((freight_amount >= (0)::numeric));
alter table public.crm_invoices add constraint crm_invoices_invoice_type_check CHECK ((invoice_type = ANY (ARRAY['proforma'::text, 'advance'::text, 'commercial'::text, 'tax'::text, 'milestone'::text, 'final'::text, 'debit_note'::text, 'credit_note'::text])));
alter table public.crm_invoices add constraint crm_invoices_other_charges_check CHECK ((other_charges >= (0)::numeric));
alter table public.crm_invoices add constraint crm_invoices_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'pending_approval'::text, 'issued'::text, 'partially_paid'::text, 'paid'::text, 'overdue'::text, 'disputed'::text, 'cancelled'::text, 'written_off'::text, 'refunded'::text])));
alter table public.crm_invoices add constraint crm_invoices_tax_pct_check CHECK (((tax_pct >= (0)::numeric) AND (tax_pct <= (100)::numeric)));
alter table public.crm_job_roles add constraint crm_job_roles_level_check CHECK (((level >= 1) AND (level <= 7)));
alter table public.crm_login_history add constraint crm_login_history_event_check CHECK ((event = ANY (ARRAY['login'::text, 'logout'::text, 'logout_all'::text, 'timeout'::text])));
alter table public.crm_opportunities add constraint crm_opportunities_estimated_value_check CHECK ((estimated_value >= (0)::numeric));
alter table public.crm_opportunities add constraint crm_opportunities_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])));
alter table public.crm_opportunities add constraint crm_opportunities_probability_pct_check CHECK (((probability_pct >= 0) AND (probability_pct <= 100)));
alter table public.crm_opportunities add constraint crm_opportunities_stage_check CHECK ((stage = ANY (ARRAY['qualification'::text, 'needs_analysis'::text, 'solution_design'::text, 'costing'::text, 'proposal_preparation'::text, 'proposal_sent'::text, 'negotiation'::text, 'won'::text, 'lost'::text, 'on_hold'::text])));
alter table public.crm_opportunity_activity add constraint crm_opportunity_activity_kind_check CHECK ((kind = ANY (ARRAY['comment'::text, 'stage_change'::text, 'system'::text])));
alter table public.crm_order_events add constraint crm_order_events_kind_check CHECK ((kind = ANY (ARRAY['comment'::text, 'status_change'::text, 'milestone'::text, 'system'::text])));
alter table public.crm_order_events add constraint crm_order_events_visibility_check CHECK ((visibility = ANY (ARRAY['internal_only'::text, 'client_visible'::text, 'client_action_required'::text, 'finance_only'::text, 'management_only'::text, 'archived'::text])));
alter table public.crm_order_items add constraint crm_order_items_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.crm_order_items add constraint crm_order_items_unit_price_check CHECK ((unit_price >= (0)::numeric));
alter table public.crm_order_milestones add constraint crm_order_milestones_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'completed'::text, 'skipped'::text, 'blocked'::text])));
alter table public.crm_orders add constraint crm_orders_order_type_check CHECK ((order_type = ANY (ARRAY['trade'::text, 'service'::text, 'mixed'::text])));
alter table public.crm_orders add constraint crm_orders_order_value_check CHECK ((order_value >= (0)::numeric));
alter table public.crm_orders add constraint crm_orders_payment_status_check CHECK ((payment_status = ANY (ARRAY['unpaid'::text, 'advance_received'::text, 'partially_paid'::text, 'paid'::text, 'refunded'::text])));
alter table public.crm_orders add constraint crm_orders_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'confirmed'::text, 'awaiting_advance'::text, 'advance_received'::text, 'supplier_confirmation'::text, 'in_production'::text, 'inspection'::text, 'ready_for_dispatch'::text, 'shipment_booked'::text, 'dispatched'::text, 'in_transit'::text, 'customs_clearance'::text, 'cleared'::text, 'local_delivery'::text, 'delivered'::text, 'completed'::text, 'on_hold'::text, 'cancelled'::text, 'disputed'::text, 'refunded'::text])));
alter table public.crm_organizations add constraint crm_organizations_classification_check CHECK ((classification = ANY (ARRAY['key_account'::text, 'standard'::text, 'occasional'::text, 'dormant'::text])));
alter table public.crm_organizations add constraint crm_organizations_kyc_status_check CHECK ((kyc_status = ANY (ARRAY['pending'::text, 'in_review'::text, 'verified'::text, 'rejected'::text])));
alter table public.crm_organizations add constraint crm_organizations_risk_status_check CHECK ((risk_status = ANY (ARRAY['standard'::text, 'watch'::text, 'high_risk'::text, 'blocked'::text])));
alter table public.crm_organizations add constraint crm_organizations_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'suspended'::text, 'archived'::text])));
alter table public.crm_payment_allocations add constraint crm_payment_allocations_amount_check CHECK ((amount > (0)::numeric));
alter table public.crm_payments add constraint crm_payments_amount_check CHECK ((amount > (0)::numeric));
alter table public.crm_payments add constraint crm_payments_bank_charges_check CHECK ((bank_charges >= (0)::numeric));
alter table public.crm_payments add constraint crm_payments_deductions_check CHECK ((deductions >= (0)::numeric));
alter table public.crm_payments add constraint crm_payments_payment_method_check CHECK ((payment_method = ANY (ARRAY['bank_transfer'::text, 'cash'::text, 'cheque'::text, 'card'::text, 'online'::text, 'other'::text])));
alter table public.crm_payments add constraint crm_payments_withholding_tax_check CHECK ((withholding_tax >= (0)::numeric));
alter table public.crm_portal_members add constraint crm_portal_members_member_role_check CHECK ((member_role = ANY (ARRAY['client_admin'::text, 'client_user'::text])));
alter table public.crm_project_milestones add constraint crm_project_milestones_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'in_progress'::text, 'completed'::text, 'delayed'::text, 'cancelled'::text])));
alter table public.crm_project_milestones add constraint crm_project_milestones_visibility_check CHECK ((visibility = ANY (ARRAY['internal_only'::text, 'client_visible'::text, 'client_action_required'::text, 'archived'::text])));
alter table public.crm_projects add constraint crm_projects_completion_pct_check CHECK (((completion_pct >= 0) AND (completion_pct <= 100)));
alter table public.crm_projects add constraint crm_projects_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'active'::text, 'on_hold'::text, 'delayed'::text, 'completed'::text, 'cancelled'::text])));
alter table public.crm_prospects add constraint crm_prospects_lead_score_check CHECK (((lead_score >= 0) AND (lead_score <= 100)));
alter table public.crm_prospects add constraint crm_prospects_lead_source_check CHECK ((lead_source = ANY (ARRAY['website'::text, 'whatsapp'::text, 'linkedin'::text, 'facebook'::text, 'instagram'::text, 'google_business'::text, 'referral'::text, 'exhibition'::text, 'phone'::text, 'email'::text, 'manual'::text, 'existing_client'::text])));
alter table public.crm_prospects add constraint crm_prospects_priority_check CHECK ((priority = ANY (ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])));
alter table public.crm_prospects add constraint crm_prospects_stage_check CHECK ((stage = ANY (ARRAY['new'::text, 'contacted'::text, 'qualified'::text, 'needs_assessment'::text, 'quotation_required'::text, 'quotation_sent'::text, 'negotiation'::text, 'won'::text, 'lost'::text, 'dormant'::text, 'disqualified'::text])));
alter table public.crm_quotation_approvals add constraint crm_quotation_approvals_decision_check CHECK ((decision = ANY (ARRAY['approved'::text, 'rejected'::text, 'revision_requested'::text])));
alter table public.crm_quotation_items add constraint crm_quotation_items_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.crm_quotation_items add constraint crm_quotation_items_unit_price_check CHECK ((unit_price >= (0)::numeric));
alter table public.crm_quotations add constraint crm_quotations_approval_status_check CHECK ((approval_status = ANY (ARRAY['not_required'::text, 'pending'::text, 'approved'::text, 'rejected'::text])));
alter table public.crm_quotations add constraint crm_quotations_discount_pct_check CHECK (((discount_pct >= (0)::numeric) AND (discount_pct <= (100)::numeric)));
alter table public.crm_quotations add constraint crm_quotations_freight_amount_check CHECK ((freight_amount >= (0)::numeric));
alter table public.crm_quotations add constraint crm_quotations_other_charges_check CHECK ((other_charges >= (0)::numeric));
alter table public.crm_quotations add constraint crm_quotations_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'costing_review'::text, 'pending_approval'::text, 'approved'::text, 'issued'::text, 'viewed'::text, 'revision_requested'::text, 'revised'::text, 'accepted'::text, 'rejected'::text, 'expired'::text, 'withdrawn'::text, 'converted_to_order'::text])));
alter table public.crm_quotations add constraint crm_quotations_tax_pct_check CHECK (((tax_pct >= (0)::numeric) AND (tax_pct <= (100)::numeric)));
alter table public.crm_record_assignments add constraint crm_record_assignments_assignment_type_check CHECK ((assignment_type = ANY (ARRAY['relationship_manager'::text, 'project_manager'::text, 'operations_lead'::text, 'finance_contact'::text, 'document_controller'::text, 'technical_lead'::text, 'audit_lead'::text, 'training_coordinator'::text])));
alter table public.crm_record_assignments add constraint crm_record_assignments_status_check CHECK ((status = ANY (ARRAY['active'::text, 'ended'::text])));
alter table public.crm_rm_policy add constraint crm_rm_policy_singleton_check CHECK (singleton);
alter table public.crm_service_milestone_templates add constraint crm_service_milestone_templates_visibility_check CHECK ((visibility = ANY (ARRAY['internal_only'::text, 'client_visible'::text, 'client_action_required'::text])));
alter table public.crm_service_offers add constraint crm_service_offers_discount_amount_check CHECK ((discount_amount >= (0)::numeric));
alter table public.crm_service_offers add constraint crm_service_offers_estimated_qty_check CHECK (((estimated_qty IS NULL) OR (estimated_qty >= (0)::numeric)));
alter table public.crm_service_offers add constraint crm_service_offers_rate_check CHECK (((rate IS NULL) OR (rate >= (0)::numeric)));
alter table public.crm_service_offers add constraint crm_service_offers_resources_check CHECK ((resources >= 1));
alter table public.crm_service_offers add constraint crm_service_offers_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'received'::text, 'under_review'::text, 'approved'::text, 'rejected'::text, 'expired'::text, 'archived'::text])));
alter table public.crm_service_offers add constraint crm_service_offers_tax_pct_check CHECK (((tax_pct >= (0)::numeric) AND (tax_pct <= (100)::numeric)));
alter table public.crm_service_providers add constraint crm_service_providers_provider_type_check CHECK ((provider_type = ANY (ARRAY['company'::text, 'individual'::text, 'freelancer'::text, 'agency'::text])));
alter table public.crm_service_providers add constraint crm_service_providers_rating_check CHECK (((rating IS NULL) OR ((rating >= (0)::numeric) AND (rating <= (5)::numeric))));
alter table public.crm_service_providers add constraint crm_service_providers_risk_class_check CHECK ((risk_class = ANY (ARRAY['unrated'::text, 'low'::text, 'medium'::text, 'high'::text])));
alter table public.crm_service_providers add constraint crm_service_providers_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'archived'::text])));
alter table public.crm_service_providers add constraint crm_service_providers_years_experience_check CHECK (((years_experience IS NULL) OR ((years_experience >= 0) AND (years_experience <= 100))));
alter table public.crm_services add constraint crm_services_fulfilment_type_chk CHECK ((fulfilment_type = ANY (ARRAY['service'::text, 'trade'::text, 'logistics'::text, 'mixed'::text])));
alter table public.crm_shipments add constraint crm_shipments_mode_check CHECK ((mode = ANY (ARRAY['sea'::text, 'air'::text, 'road'::text, 'rail'::text, 'courier'::text])));
alter table public.crm_shipments add constraint crm_shipments_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'booked'::text, 'at_origin_port'::text, 'departed'::text, 'in_transit'::text, 'arrived'::text, 'customs'::text, 'cleared'::text, 'delivered'::text, 'delayed'::text, 'cancelled'::text])));
alter table public.crm_staff_roles add constraint crm_staff_roles_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'super_admin'::text, 'ceo'::text, 'finance_manager'::text, 'trade_sourcing_manager'::text, 'customs_manager'::text, 'consultancy_manager'::text, 'operations_manager'::text, 'business_development'::text, 'account_manager'::text, 'project_manager'::text, 'document_controller'::text, 'read_only_auditor'::text])));
alter table public.crm_stockists add constraint crm_stockists_placement_status_check CHECK ((placement_status = ANY (ARRAY['prospect'::text, 'pitched'::text, 'listed'::text, 'active'::text, 'paused'::text, 'delisted'::text])));
alter table public.crm_stockists add constraint crm_stockists_reorder_status_check CHECK ((reorder_status = ANY (ARRAY['not_due'::text, 'due_soon'::text, 'due'::text, 'overdue'::text, 'ordered'::text])));
alter table public.crm_stockists add constraint crm_stockists_shelf_status_check CHECK ((shelf_status = ANY (ARRAY['not_placed'::text, 'on_shelf'::text, 'prime_shelf'::text, 'back_stock'::text])));
alter table public.crm_subscriptions add constraint crm_subscriptions_billing_cycle_check CHECK ((billing_cycle = ANY (ARRAY['monthly'::text, 'quarterly'::text, 'yearly'::text])));
alter table public.crm_subscriptions add constraint crm_subscriptions_cost_check CHECK ((cost >= (0)::numeric));
alter table public.crm_subscriptions add constraint crm_subscriptions_seats_purchased_check CHECK (((seats_purchased IS NULL) OR (seats_purchased >= 0)));
alter table public.crm_subscriptions add constraint crm_subscriptions_seats_used_check CHECK (((seats_used IS NULL) OR (seats_used >= 0)));
alter table public.crm_subscriptions add constraint crm_subscriptions_status_check CHECK ((status = ANY (ARRAY['active'::text, 'cancelled'::text, 'archived'::text])));
alter table public.crm_supplier_offers add constraint crm_supplier_offers_exchange_rate_check CHECK ((exchange_rate > (0)::numeric));
alter table public.crm_supplier_offers add constraint crm_supplier_offers_freight_estimate_check CHECK ((freight_estimate >= (0)::numeric));
alter table public.crm_supplier_offers add constraint crm_supplier_offers_packaging_cost_check CHECK ((packaging_cost >= (0)::numeric));
alter table public.crm_supplier_offers add constraint crm_supplier_offers_quality_score_check CHECK (((quality_score >= 1) AND (quality_score <= 5)));
alter table public.crm_supplier_offers add constraint crm_supplier_offers_risk_score_check CHECK (((risk_score >= 1) AND (risk_score <= 5)));
alter table public.crm_supplier_offers add constraint crm_supplier_offers_sample_cost_check CHECK ((sample_cost >= (0)::numeric));
alter table public.crm_supplier_offers add constraint crm_supplier_offers_tooling_cost_check CHECK ((tooling_cost >= (0)::numeric));
alter table public.crm_supplier_offers add constraint crm_supplier_offers_unit_cost_check CHECK ((unit_cost >= (0)::numeric));
alter table public.crm_timesheets add constraint crm_timesheets_hours_check CHECK (((hours > (0)::numeric) AND (hours <= (24)::numeric)));
alter table public.crm_tracking_policy add constraint crm_tracking_policy_singleton_check CHECK (singleton);
alter table public.crm_vendors add constraint crm_vendors_approval_status_check CHECK ((approval_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'suspended'::text])));
alter table public.crm_vendors add constraint crm_vendors_factory_audit_status_check CHECK ((factory_audit_status = ANY (ARRAY['not_audited'::text, 'scheduled'::text, 'passed'::text, 'failed'::text, 'expired'::text])));
alter table public.crm_vendors add constraint crm_vendors_score_communication_check CHECK (((score_communication >= 1) AND (score_communication <= 5)));
alter table public.crm_vendors add constraint crm_vendors_score_compliance_check CHECK (((score_compliance >= 1) AND (score_compliance <= 5)));
alter table public.crm_vendors add constraint crm_vendors_score_delivery_check CHECK (((score_delivery >= 1) AND (score_delivery <= 5)));
alter table public.crm_vendors add constraint crm_vendors_score_documentation_check CHECK (((score_documentation >= 1) AND (score_documentation <= 5)));
alter table public.crm_vendors add constraint crm_vendors_score_price_check CHECK (((score_price >= 1) AND (score_price <= 5)));
alter table public.crm_vendors add constraint crm_vendors_score_quality_check CHECK (((score_quality >= 1) AND (score_quality <= 5)));
alter table public.crm_vendors add constraint crm_vendors_score_reliability_check CHECK (((score_reliability >= 1) AND (score_reliability <= 5)));
alter table public.crm_vendors add constraint crm_vendors_supplier_type_check CHECK ((supplier_type = ANY (ARRAY['manufacturer'::text, 'trader'::text, 'agent'::text, 'service_provider'::text])));
alter table public.pharma_adverse_events add constraint pharma_adverse_events_causality_check CHECK ((causality = ANY (ARRAY['certain'::text, 'probable'::text, 'possible'::text, 'unlikely'::text, 'unassessable'::text])));
alter table public.pharma_adverse_events add constraint pharma_adverse_events_outcome_check CHECK ((outcome = ANY (ARRAY['recovered'::text, 'recovering'::text, 'not_recovered'::text, 'sequelae'::text, 'fatal'::text, 'unknown'::text])));
alter table public.pharma_adverse_events add constraint pharma_adverse_events_patient_age_band_check CHECK ((patient_age_band = ANY (ARRAY['neonate'::text, 'infant'::text, 'child'::text, 'adolescent'::text, 'adult'::text, 'elderly'::text, 'unknown'::text])));
alter table public.pharma_adverse_events add constraint pharma_adverse_events_patient_sex_check CHECK ((patient_sex = ANY (ARRAY['male'::text, 'female'::text, 'unknown'::text])));
alter table public.pharma_adverse_events add constraint pharma_adverse_events_reporter_type_check CHECK ((reporter_type = ANY (ARRAY['doctor'::text, 'pharmacist'::text, 'patient'::text, 'nurse'::text, 'other_hcp'::text, 'company'::text])));
alter table public.pharma_adverse_events add constraint pharma_adverse_events_seriousness_check CHECK ((seriousness = ANY (ARRAY['non_serious'::text, 'serious'::text, 'fatal'::text])));
alter table public.pharma_adverse_events add constraint pharma_adverse_events_status_check CHECK ((status = ANY (ARRAY['received'::text, 'assessing'::text, 'reported'::text, 'follow_up'::text, 'closed'::text])));
alter table public.pharma_campaigns add constraint chk_campaign_dates CHECK ((end_date >= start_date));
alter table public.pharma_campaigns add constraint pharma_campaigns_approval_status_check CHECK ((approval_status = ANY (ARRAY['draft'::text, 'submitted'::text, 'approved'::text, 'rejected'::text])));
alter table public.pharma_campaigns add constraint pharma_campaigns_budget_check CHECK (((budget IS NULL) OR (budget >= (0)::numeric)));
alter table public.pharma_campaigns add constraint pharma_campaigns_campaign_type_check CHECK ((campaign_type = ANY (ARRAY['product_launch'::text, 'doctor_detailing'::text, 'pharmacy_activation'::text, 'formulary_campaign'::text, 'medical_conference'::text, 'webinar'::text, 'continuing_education'::text, 'patient_awareness'::text, 'digital_ads'::text, 'social_media'::text, 'email'::text, 'messaging'::text, 'pharmacy_display'::text, 'distributor_incentive'::text, 'salesforce_incentive'::text, 'scientific_seminar'::text, 'sampling'::text])));
alter table public.pharma_campaigns add constraint pharma_campaigns_level_check CHECK ((level = ANY (ARRAY['company'::text, 'brand'::text, 'product'::text, 'territory'::text, 'specialty'::text, 'hospital'::text, 'pharmacy'::text, 'distributor'::text])));
alter table public.pharma_campaigns add constraint pharma_campaigns_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'running'::text, 'paused'::text, 'completed'::text, 'cancelled'::text])));
alter table public.pharma_companies add constraint pharma_companies_account_health_check CHECK (((account_health IS NULL) OR ((account_health >= 0) AND (account_health <= 100))));
alter table public.pharma_companies add constraint pharma_companies_business_status_check CHECK ((business_status = ANY (ARRAY['prospect'::text, 'lead'::text, 'qualified'::text, 'active'::text, 'partner'::text, 'dormant'::text, 'blacklisted'::text, 'former'::text])));
alter table public.pharma_companies add constraint pharma_companies_risk_category_check CHECK ((risk_category = ANY (ARRAY['unrated'::text, 'low'::text, 'medium'::text, 'high'::text])));
alter table public.pharma_company_contacts add constraint pharma_company_contacts_preferred_contact_check CHECK ((preferred_contact = ANY (ARRAY['phone'::text, 'whatsapp'::text, 'email'::text, 'in_person'::text])));
alter table public.pharma_company_contacts add constraint pharma_company_contacts_role_type_check CHECK ((role_type = ANY (ARRAY['owner'::text, 'ceo'::text, 'managing_director'::text, 'commercial_director'::text, 'marketing_director'::text, 'sales_director'::text, 'regulatory_manager'::text, 'supply_chain_manager'::text, 'purchase_manager'::text, 'production_manager'::text, 'qc_manager'::text, 'qa_manager'::text, 'finance_manager'::text, 'medical_affairs'::text, 'export_manager'::text, 'distribution_manager'::text, 'warehouse_manager'::text, 'other'::text])));
alter table public.pharma_complaints add constraint pharma_complaints_complaint_type_check CHECK ((complaint_type = ANY (ARRAY['product_quality'::text, 'packaging'::text, 'labelling'::text, 'short_supply'::text, 'wrong_product'::text, 'damaged'::text, 'temperature_excursion'::text, 'counterfeit_suspicion'::text, 'expired_supply'::text, 'other'::text])));
alter table public.pharma_complaints add constraint pharma_complaints_severity_check CHECK ((severity = ANY (ARRAY['minor'::text, 'major'::text, 'critical'::text])));
alter table public.pharma_complaints add constraint pharma_complaints_status_check CHECK ((status = ANY (ARRAY['open'::text, 'investigating'::text, 'capa_pending'::text, 'resolved'::text, 'closed'::text, 'escalated'::text])));
alter table public.pharma_distributors add constraint pharma_distributors_distributor_type_check CHECK ((distributor_type = ANY (ARRAY['national'::text, 'regional'::text, 'city'::text, 'sub_distributor'::text, 'wholesaler'::text, 'institutional'::text, 'pharmacy_chain_supplier'::text, 'importer_distributor'::text])));
alter table public.pharma_distributors add constraint pharma_distributors_performance_score_check CHECK (((performance_score IS NULL) OR ((performance_score >= 0) AND (performance_score <= 100))));
alter table public.pharma_distributors add constraint pharma_distributors_service_level_score_check CHECK (((service_level_score IS NULL) OR ((service_level_score >= 0) AND (service_level_score <= 100))));
alter table public.pharma_distributors add constraint pharma_distributors_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'suspended'::text, 'archived'::text])));
alter table public.pharma_doctor_affiliations add constraint pharma_doctor_affiliations_institution_type_check CHECK ((institution_type = ANY (ARRAY['hospital'::text, 'clinic'::text, 'pharmacy'::text, 'university'::text, 'other'::text])));
alter table public.pharma_doctor_products add constraint pharma_doctor_products_interest_level_check CHECK ((interest_level = ANY (ARRAY['high'::text, 'medium'::text, 'low'::text, 'none'::text])));
alter table public.pharma_doctor_products add constraint pharma_doctor_products_relationship_check CHECK ((relationship = ANY (ARRAY['detailed'::text, 'prescribing'::text, 'potential'::text, 'declined'::text, 'switched_away'::text])));
alter table public.pharma_doctors add constraint pharma_doctors_category_check CHECK ((category = ANY (ARRAY['unclassified'::text, 'A_plus'::text, 'A'::text, 'B'::text, 'C'::text, 'kol'::text, 'new'::text, 'potential'::text, 'inactive'::text, 'restricted'::text])));
alter table public.pharma_doctors add constraint pharma_doctors_consent_status_check CHECK ((consent_status = ANY (ARRAY['not_obtained'::text, 'obtained'::text, 'refused'::text, 'withdrawn'::text])));
alter table public.pharma_doctors add constraint pharma_doctors_designation_check CHECK ((designation = ANY (ARRAY['consultant'::text, 'professor'::text, 'associate_professor'::text, 'assistant_professor'::text, 'senior_registrar'::text, 'medical_officer'::text, 'gp'::text, 'surgeon'::text, 'dentist'::text, 'nutritionist'::text, 'pharmacist'::text, 'veterinarian'::text, 'other'::text])));
alter table public.pharma_doctors add constraint pharma_doctors_engagement_score_check CHECK (((engagement_score IS NULL) OR ((engagement_score >= 0) AND (engagement_score <= 100))));
alter table public.pharma_doctors add constraint pharma_doctors_influence_level_check CHECK ((influence_level = ANY (ARRAY['national'::text, 'regional'::text, 'local'::text, 'unknown'::text])));
alter table public.pharma_doctors add constraint pharma_doctors_preferred_contact_check CHECK ((preferred_contact = ANY (ARRAY['phone'::text, 'whatsapp'::text, 'email'::text, 'in_person'::text, 'none'::text])));
alter table public.pharma_doctors add constraint pharma_doctors_prescribing_potential_check CHECK ((prescribing_potential = ANY (ARRAY['high'::text, 'medium'::text, 'low'::text, 'unknown'::text])));
alter table public.pharma_doctors add constraint pharma_doctors_relationship_status_check CHECK ((relationship_status = ANY (ARRAY['new'::text, 'engaged'::text, 'loyal'::text, 'lapsed'::text, 'lost'::text])));
alter table public.pharma_doctors add constraint pharma_doctors_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'archived'::text])));
alter table public.pharma_engagement_spend add constraint chk_spend_subject CHECK (((
CASE
    WHEN (doctor_id IS NOT NULL) THEN 1
    ELSE 0
END +
CASE
    WHEN (hospital_id IS NOT NULL) THEN 1
    ELSE 0
END) = 1));
alter table public.pharma_engagement_spend add constraint pharma_engagement_spend_amount_check CHECK ((amount >= (0)::numeric));
alter table public.pharma_engagement_spend add constraint pharma_engagement_spend_spend_type_check CHECK ((spend_type = ANY (ARRAY['conference'::text, 'seminar'::text, 'training'::text, 'educational_material'::text, 'patient_material'::text, 'meeting_venue'::text, 'meeting_catering'::text, 'travel_support'::text, 'speaker_fee'::text, 'other_approved'::text])));
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_allocation_pct_check CHECK (((allocation_pct > (0)::numeric) AND (allocation_pct <= (100)::numeric)));
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_pl_layer_check CHECK ((pl_layer = ANY (ARRAY['cogs'::text, 'direct_selling'::text, 'distribution'::text, 'promotion'::text, 'regulatory'::text, 'admin_overhead'::text, 'depreciation'::text, 'amortisation'::text])));
alter table public.pharma_field_force add constraint pharma_field_force_field_role_check CHECK ((field_role = ANY (ARRAY['national_sales_manager'::text, 'regional_sales_manager'::text, 'zonal_sales_manager'::text, 'area_sales_manager'::text, 'territory_manager'::text, 'medical_representative'::text, 'sales_representative'::text, 'product_specialist'::text, 'institutional_sales_officer'::text, 'pharmacy_sales_officer'::text])));
alter table public.pharma_hospitals add constraint pharma_hospitals_institution_type_check CHECK ((institution_type = ANY (ARRAY['public_hospital'::text, 'private_hospital'::text, 'teaching_hospital'::text, 'clinic'::text, 'diagnostic_centre'::text, 'laboratory'::text, 'medical_college'::text, 'university'::text, 'govt_health_dept'::text, 'armed_forces'::text, 'ngo'::text, 'charitable'::text, 'pharmacy_chain'::text, 'corporate_healthcare'::text])));
alter table public.pharma_hospitals add constraint pharma_hospitals_ownership_type_check CHECK ((ownership_type = ANY (ARRAY['government'::text, 'private'::text, 'trust'::text, 'ngo'::text, 'armed_forces'::text, 'corporate'::text])));
alter table public.pharma_hospitals add constraint pharma_hospitals_relationship_status_check CHECK ((relationship_status = ANY (ARRAY['prospect'::text, 'engaged'::text, 'listed'::text, 'active'::text, 'dormant'::text, 'blacklisted'::text])));
alter table public.pharma_hospitals add constraint pharma_hospitals_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'archived'::text])));
alter table public.pharma_inventory_batches add constraint pharma_inventory_batches_quality_status_check CHECK ((quality_status = ANY (ARRAY['quarantine'::text, 'released'::text, 'rejected'::text, 'recalled'::text, 'on_hold'::text])));
alter table public.pharma_inventory_movements add constraint pharma_inventory_movements_movement_type_check CHECK ((movement_type = ANY (ARRAY['receipt'::text, 'sale'::text, 'return'::text, 'transfer_in'::text, 'transfer_out'::text, 'damage'::text, 'expiry_writeoff'::text, 'recall'::text, 'sample_conversion'::text, 'adjustment'::text])));
alter table public.pharma_invoices add constraint chk_inv_dates CHECK ((due_date >= invoice_date));
alter table public.pharma_invoices add constraint pharma_invoices_invoice_value_check CHECK ((invoice_value >= (0)::numeric));
alter table public.pharma_invoices add constraint pharma_invoices_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'open'::text, 'part_paid'::text, 'paid'::text, 'overdue'::text, 'disputed'::text, 'written_off'::text, 'cancelled'::text])));
alter table public.pharma_offer_targets add constraint chk_one_target CHECK (((((
CASE
    WHEN (doctor_id IS NOT NULL) THEN 1
    ELSE 0
END +
CASE
    WHEN (hospital_id IS NOT NULL) THEN 1
    ELSE 0
END) +
CASE
    WHEN (pharmacy_id IS NOT NULL) THEN 1
    ELSE 0
END) +
CASE
    WHEN (distributor_id IS NOT NULL) THEN 1
    ELSE 0
END) = 1));
alter table public.pharma_pharmacies add constraint pharma_pharmacies_pharmacy_type_check CHECK ((pharmacy_type = ANY (ARRAY['independent'::text, 'chain'::text, 'hospital'::text, 'clinic'::text, 'wholesale'::text, 'online'::text, 'supermarket'::text, 'distributor_outlet'::text, 'government'::text, 'institutional'::text])));
alter table public.pharma_pharmacies add constraint pharma_pharmacies_relationship_rating_check CHECK (((relationship_rating IS NULL) OR ((relationship_rating >= 1) AND (relationship_rating <= 5))));
alter table public.pharma_pharmacies add constraint pharma_pharmacies_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'archived'::text])));
alter table public.pharma_pharmacies add constraint pharma_pharmacies_store_category_check CHECK ((store_category = ANY (ARRAY['A'::text, 'B'::text, 'C'::text, 'D'::text])));
alter table public.pharma_plants add constraint pharma_plants_audit_status_check CHECK ((audit_status = ANY (ARRAY['not_audited'::text, 'scheduled'::text, 'passed'::text, 'conditional'::text, 'failed'::text])));
alter table public.pharma_plants add constraint pharma_plants_commercial_rating_check CHECK (((commercial_rating IS NULL) OR ((commercial_rating >= (0)::numeric) AND (commercial_rating <= (5)::numeric))));
alter table public.pharma_plants add constraint pharma_plants_gmp_status_check CHECK ((gmp_status = ANY (ARRAY['none'::text, 'local_gmp'::text, 'who_gmp'::text, 'eu_gmp'::text, 'us_fda'::text, 'pics'::text])));
alter table public.pharma_plants add constraint pharma_plants_quality_rating_check CHECK (((quality_rating IS NULL) OR ((quality_rating >= (0)::numeric) AND (quality_rating <= (5)::numeric))));
alter table public.pharma_plants add constraint pharma_plants_risk_rating_check CHECK ((risk_rating = ANY (ARRAY['unrated'::text, 'low'::text, 'medium'::text, 'high'::text])));
alter table public.pharma_plants add constraint pharma_plants_status_check CHECK ((status = ANY (ARRAY['active'::text, 'inactive'::text, 'archived'::text])));
alter table public.pharma_plants add constraint pharma_plants_utilised_capacity_pct_check CHECK (((utilised_capacity_pct IS NULL) OR ((utilised_capacity_pct >= (0)::numeric) AND (utilised_capacity_pct <= (100)::numeric))));
alter table public.pharma_product_prices add constraint pharma_product_prices_amount_check CHECK ((amount >= (0)::numeric));
alter table public.pharma_product_prices add constraint pharma_product_prices_price_type_check CHECK ((price_type = ANY (ARRAY['ex_factory'::text, 'landed_cost'::text, 'trade'::text, 'distributor'::text, 'wholesale'::text, 'retail'::text, 'mrp'::text, 'institutional'::text, 'tender'::text, 'export'::text, 'transfer'::text, 'rsp'::text])));
alter table public.pharma_product_regulatory add constraint pharma_product_regulatory_record_type_check CHECK ((record_type = ANY (ARRAY['registration'::text, 'renewal'::text, 'variation'::text, 'price_approval'::text, 'import_permission'::text, 'export_doc'::text, 'marketing_authorisation'::text, 'label_approval'::text, 'artwork_approval'::text, 'free_sale_cert'::text, 'cpp'::text, 'halal'::text, 'controlled_permit'::text, 'other'::text])));
alter table public.pharma_product_regulatory add constraint pharma_product_regulatory_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'submitted'::text, 'query_raised'::text, 'under_review'::text, 'approved'::text, 'rejected'::text, 'expired'::text, 'withdrawn'::text])));
alter table public.pharma_production_batches add constraint pharma_production_batches_qc_result_check CHECK ((qc_result = ANY (ARRAY['pass'::text, 'fail'::text, 'pending'::text, 'retest'::text])));
alter table public.pharma_production_batches add constraint pharma_production_batches_stage_check CHECK ((stage = ANY (ARRAY['planned'::text, 'rm_pending'::text, 'rm_ready'::text, 'in_production'::text, 'qc_testing'::text, 'qa_review'::text, 'released'::text, 'rejected'::text, 'dispatched'::text])));
alter table public.pharma_products add constraint pharma_products_lifecycle_stage_check CHECK ((lifecycle_stage = ANY (ARRAY['launch'::text, 'growth'::text, 'maturity'::text, 'decline'::text, 'withdrawn'::text])));
alter table public.pharma_products add constraint pharma_products_product_class_check CHECK ((product_class = ANY (ARRAY['pharmaceutical'::text, 'nutraceutical'::text, 'herbal'::text, 'cosmetic'::text, 'device'::text, 'veterinary'::text])));
alter table public.pharma_products add constraint pharma_products_rx_status_check CHECK ((rx_status = ANY (ARRAY['rx'::text, 'otc'::text, 'controlled'::text, 'device'::text, 'supplement'::text])));
alter table public.pharma_products add constraint pharma_products_status_check CHECK ((status = ANY (ARRAY['development'::text, 'under_registration'::text, 'registered'::text, 'active'::text, 'on_hold'::text, 'discontinued'::text])));
alter table public.pharma_promotional_offers add constraint chk_offer_dates CHECK ((end_date >= start_date));
alter table public.pharma_promotional_offers add constraint pharma_promotional_offers_approval_status_check CHECK ((approval_status = ANY (ARRAY['draft'::text, 'submitted'::text, 'approved'::text, 'rejected'::text, 'withdrawn'::text])));
alter table public.pharma_promotional_offers add constraint pharma_promotional_offers_budget_check CHECK (((budget IS NULL) OR (budget >= (0)::numeric)));
alter table public.pharma_promotional_offers add constraint pharma_promotional_offers_commission_pct_check CHECK (((commission_pct IS NULL) OR ((commission_pct >= (0)::numeric) AND (commission_pct <= (100)::numeric))));
alter table public.pharma_promotional_offers add constraint pharma_promotional_offers_compliance_status_check CHECK ((compliance_status = ANY (ARRAY['pending'::text, 'cleared'::text, 'flagged'::text, 'blocked'::text])));
alter table public.pharma_promotional_offers add constraint pharma_promotional_offers_discount_pct_check CHECK (((discount_pct IS NULL) OR ((discount_pct >= (0)::numeric) AND (discount_pct <= (100)::numeric))));
alter table public.pharma_promotional_offers add constraint pharma_promotional_offers_discount_value_check CHECK (((discount_value IS NULL) OR (discount_value >= (0)::numeric)));
alter table public.pharma_promotional_offers add constraint pharma_promotional_offers_rebate_pct_check CHECK (((rebate_pct IS NULL) OR ((rebate_pct >= (0)::numeric) AND (rebate_pct <= (100)::numeric))));
alter table public.pharma_promotional_offers add constraint pharma_promotional_offers_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'running'::text, 'paused'::text, 'completed'::text, 'expired'::text, 'cancelled'::text])));
alter table public.pharma_promotional_offers add constraint pharma_promotional_offers_target_type_check CHECK ((target_type = ANY (ARRAY['doctor'::text, 'hospital'::text, 'pharmacy'::text, 'distributor'::text, 'wholesaler'::text])));
alter table public.pharma_recalls add constraint pharma_recalls_recall_class_check CHECK ((recall_class = ANY (ARRAY['class_i'::text, 'class_ii'::text, 'class_iii'::text])));
alter table public.pharma_recalls add constraint pharma_recalls_status_check CHECK ((status = ANY (ARRAY['initiated'::text, 'in_progress'::text, 'completed'::text, 'closed'::text])));
alter table public.pharma_receipts add constraint pharma_receipts_amount_check CHECK ((amount > (0)::numeric));
alter table public.pharma_receipts add constraint pharma_receipts_method_check CHECK ((method = ANY (ARRAY['cash'::text, 'cheque'::text, 'bank_transfer'::text, 'online'::text, 'adjustment'::text])));
alter table public.pharma_receipts add constraint pharma_receipts_receipt_type_check CHECK ((receipt_type = ANY (ARRAY['payment'::text, 'credit_note'::text, 'rebate_adjustment'::text, 'return_adjustment'::text, 'write_off'::text])));
alter table public.pharma_returns add constraint pharma_returns_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.pharma_returns add constraint pharma_returns_return_type_check CHECK ((return_type = ANY (ARRAY['expired'::text, 'near_expiry'::text, 'damaged'::text, 'wrong_supply'::text, 'excess'::text, 'recall'::text, 'other'::text])));
alter table public.pharma_returns add constraint pharma_returns_status_check CHECK ((status = ANY (ARRAY['requested'::text, 'approved'::text, 'received'::text, 'credited'::text, 'rejected'::text])));
alter table public.pharma_sales_order_items add constraint pharma_sales_order_items_discount_pct_check CHECK (((discount_pct >= (0)::numeric) AND (discount_pct <= (100)::numeric)));
alter table public.pharma_sales_order_items add constraint pharma_sales_order_items_free_quantity_check CHECK ((free_quantity >= (0)::numeric));
alter table public.pharma_sales_order_items add constraint pharma_sales_order_items_list_price_check CHECK ((list_price >= (0)::numeric));
alter table public.pharma_sales_order_items add constraint pharma_sales_order_items_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.pharma_sales_order_items add constraint pharma_sales_order_items_tax_pct_check CHECK (((tax_pct >= (0)::numeric) AND (tax_pct <= (100)::numeric)));
alter table public.pharma_sales_orders add constraint pharma_sales_orders_sale_type_check CHECK ((sale_type = ANY (ARRAY['primary'::text, 'secondary'::text, 'institutional'::text, 'pharmacy'::text, 'hospital'::text, 'distributor'::text, 'direct'::text, 'export'::text, 'toll'::text, 'promotional_service'::text])));
alter table public.pharma_sales_orders add constraint pharma_sales_orders_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'confirmed'::text, 'picked'::text, 'dispatched'::text, 'delivered'::text, 'invoiced'::text, 'cancelled'::text, 'returned'::text])));
alter table public.pharma_sample_items add constraint pharma_sample_items_item_type_check CHECK ((item_type = ANY (ARRAY['medicine_sample'::text, 'nutraceutical_sample'::text, 'starter_pack'::text, 'brochure'::text, 'visual_aid'::text, 'monograph'::text, 'reminder_card'::text, 'prescription_pad'::text, 'stand'::text, 'banner'::text, 'display'::text, 'conference_material'::text, 'patient_education'::text, 'other_approved'::text])));
alter table public.pharma_sample_transactions add constraint pharma_sample_transactions_quantity_check CHECK ((quantity > (0)::numeric));
alter table public.pharma_sample_transactions add constraint pharma_sample_transactions_txn_type_check CHECK ((txn_type = ANY (ARRAY['receive'::text, 'issue_to_rep'::text, 'issue_to_doctor'::text, 'issue_to_hospital'::text, 'issue_to_pharmacy'::text, 'return'::text, 'damage'::text, 'expire'::text, 'adjust'::text])));
alter table public.pharma_tenders add constraint pharma_tenders_financial_status_check CHECK ((financial_status = ANY (ARRAY['not_opened'::text, 'opened'::text, 'lowest'::text, 'not_lowest'::text])));
alter table public.pharma_tenders add constraint pharma_tenders_result_check CHECK ((result = ANY (ARRAY['pending'::text, 'won'::text, 'lost'::text, 'cancelled'::text, 'retendered'::text])));
alter table public.pharma_tenders add constraint pharma_tenders_technical_status_check CHECK ((technical_status = ANY (ARRAY['not_submitted'::text, 'submitted'::text, 'qualified'::text, 'disqualified'::text])));
alter table public.pharma_tenders add constraint pharma_tenders_tender_type_check CHECK ((tender_type = ANY (ARRAY['open'::text, 'limited'::text, 'single_source'::text, 'framework'::text, 'rate_contract'::text])));
alter table public.pharma_territories add constraint pharma_territories_level_check CHECK ((level = ANY (ARRAY['country'::text, 'region'::text, 'province'::text, 'division'::text, 'district'::text, 'city'::text, 'zone'::text, 'territory'::text, 'route'::text, 'beat'::text])));
alter table public.pharma_toll_contracts add constraint pharma_toll_contracts_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'negotiating'::text, 'signed'::text, 'in_production'::text, 'completed'::text, 'terminated'::text])));
alter table public.pharma_toll_enquiries add constraint pharma_toll_enquiries_artwork_by_check CHECK ((artwork_by = ANY (ARRAY['client'::text, 'jabran'::text, 'manufacturer'::text, 'shared'::text])));
alter table public.pharma_toll_enquiries add constraint pharma_toll_enquiries_packaging_by_check CHECK ((packaging_by = ANY (ARRAY['client'::text, 'jabran'::text, 'manufacturer'::text, 'shared'::text])));
alter table public.pharma_toll_enquiries add constraint pharma_toll_enquiries_raw_material_by_check CHECK ((raw_material_by = ANY (ARRAY['client'::text, 'jabran'::text, 'manufacturer'::text, 'shared'::text])));
alter table public.pharma_toll_enquiries add constraint pharma_toll_enquiries_registration_by_check CHECK ((registration_by = ANY (ARRAY['client'::text, 'jabran'::text, 'manufacturer'::text, 'shared'::text])));
alter table public.pharma_toll_enquiries add constraint pharma_toll_enquiries_status_check CHECK ((status = ANY (ARRAY['new'::text, 'sourcing'::text, 'offers_received'::text, 'quoted'::text, 'won'::text, 'lost'::text, 'on_hold'::text, 'cancelled'::text])));
alter table public.pharma_toll_offers add constraint pharma_toll_offers_jco_commission_pct_check CHECK (((jco_commission_pct >= (0)::numeric) AND (jco_commission_pct <= (100)::numeric)));
alter table public.pharma_toll_offers add constraint pharma_toll_offers_status_check CHECK ((status = ANY (ARRAY['requested'::text, 'received'::text, 'under_review'::text, 'shortlisted'::text, 'selected'::text, 'rejected'::text, 'expired'::text])));
alter table public.pharma_toll_offers add constraint pharma_toll_offers_tax_pct_check CHECK (((tax_pct >= (0)::numeric) AND (tax_pct <= (100)::numeric)));
alter table public.pharma_visit_plans add constraint pharma_visit_plans_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'approved'::text, 'in_progress'::text, 'completed'::text, 'missed'::text])));
alter table public.pharma_visits add constraint chk_visit_subject CHECK (((((
CASE
    WHEN (doctor_id IS NOT NULL) THEN 1
    ELSE 0
END +
CASE
    WHEN (hospital_id IS NOT NULL) THEN 1
    ELSE 0
END) +
CASE
    WHEN (pharmacy_id IS NOT NULL) THEN 1
    ELSE 0
END) +
CASE
    WHEN (distributor_id IS NOT NULL) THEN 1
    ELSE 0
END) = 1));
alter table public.pharma_visits add constraint pharma_visits_outcome_check CHECK ((outcome = ANY (ARRAY['committed'::text, 'interested'::text, 'neutral'::text, 'objection'::text, 'refused'::text, 'not_available'::text])));
alter table public.pharma_visits add constraint pharma_visits_status_check CHECK ((status = ANY (ARRAY['planned'::text, 'completed'::text, 'missed'::text, 'cancelled'::text])));
alter table public.pharma_visits add constraint pharma_visits_visit_type_check CHECK ((visit_type = ANY (ARRAY['doctor'::text, 'hospital'::text, 'pharmacy'::text, 'distributor'::text])));
alter table public.profiles add constraint profiles_role_check CHECK ((role = ANY (ARRAY['admin'::text, 'client'::text])));
alter table public.social_settings add constraint social_settings_singleton CHECK ((id = 1));
alter table public.training_modules add constraint training_modules_content_type_check CHECK ((content_type = ANY (ARRAY['video'::text, 'pdf'::text, 'text'::text, 'mixed'::text])));
alter table public.training_quiz_questions add constraint training_quiz_questions_correct_option_check CHECK ((correct_option = ANY (ARRAY['a'::text, 'b'::text, 'c'::text, 'd'::text])));

-- Foreign keys
alter table public.ai_agent_feedback add constraint ai_agent_feedback_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES ai_conversations(id) ON DELETE CASCADE;
alter table public.ai_agent_handoffs add constraint ai_agent_handoffs_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES ai_conversations(id) ON DELETE CASCADE;
alter table public.ai_conversation_summaries add constraint ai_conversation_summaries_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES ai_conversations(id) ON DELETE CASCADE;
alter table public.ai_messages add constraint ai_messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES ai_conversations(id) ON DELETE CASCADE;
alter table public.analytics_accounts add constraint analytics_accounts_connection_id_fkey FOREIGN KEY (connection_id) REFERENCES analytics_connections(id) ON DELETE CASCADE;
alter table public.analytics_connections add constraint analytics_connections_connected_by_fkey FOREIGN KEY (connected_by) REFERENCES auth.users(id);
alter table public.analytics_generated_reports add constraint analytics_generated_reports_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.analytics_oauth_states add constraint analytics_oauth_states_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table public.analytics_oauth_tokens add constraint analytics_oauth_tokens_connected_by_fkey FOREIGN KEY (connected_by) REFERENCES auth.users(id);
alter table public.analytics_prompt_history add constraint analytics_prompt_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table public.analytics_sync_jobs add constraint analytics_sync_jobs_connection_id_fkey FOREIGN KEY (connection_id) REFERENCES analytics_connections(id) ON DELETE CASCADE;
alter table public.audit_findings add constraint audit_findings_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE;
alter table public.case_studies add constraint case_studies_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE;
alter table public.case_study_approvals add constraint case_study_approvals_case_study_id_fkey FOREIGN KEY (case_study_id) REFERENCES case_studies(id) ON DELETE CASCADE;
alter table public.client_actions add constraint client_actions_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE;
alter table public.client_documents add constraint client_documents_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE;
alter table public.client_kpis add constraint client_kpis_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE;
alter table public.client_meetings add constraint client_meetings_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE;
alter table public.client_reports add constraint client_reports_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE;
alter table public.crm_activity_events add constraint crm_activity_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.crm_agent_accounts add constraint crm_agent_accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table public.crm_ai_actions add constraint crm_ai_actions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table public.crm_alert_dismissals add constraint crm_alert_dismissals_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table public.crm_attachments add constraint crm_attachments_parent_attachment_id_fkey FOREIGN KEY (parent_attachment_id) REFERENCES crm_attachments(id) ON DELETE SET NULL;
alter table public.crm_attachments add constraint crm_attachments_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES auth.users(id);
alter table public.crm_budgets add constraint crm_budgets_cost_centre_id_fkey FOREIGN KEY (cost_centre_id) REFERENCES crm_cost_centres(id);
alter table public.crm_contacts add constraint crm_contacts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES crm_organizations(id) ON DELETE CASCADE;
alter table public.crm_contacts add constraint crm_contacts_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES crm_vendors(id);
alter table public.crm_cost_lines add constraint crm_cost_lines_billing_basis_fkey FOREIGN KEY (billing_basis) REFERENCES crm_billing_bases(code);
alter table public.crm_cost_lines add constraint crm_cost_lines_category_code_fkey FOREIGN KEY (category_code) REFERENCES crm_cost_categories(code);
alter table public.crm_cost_sheet_items add constraint crm_cost_sheet_items_billing_basis_fkey FOREIGN KEY (billing_basis) REFERENCES crm_billing_bases(code);
alter table public.crm_cost_sheet_items add constraint crm_cost_sheet_items_cost_line_id_fkey FOREIGN KEY (cost_line_id) REFERENCES crm_cost_lines(id);
alter table public.crm_cost_sheet_items add constraint crm_cost_sheet_items_cost_sheet_id_fkey FOREIGN KEY (cost_sheet_id) REFERENCES crm_cost_sheets(id) ON DELETE CASCADE;
alter table public.crm_cost_sheet_items add constraint crm_cost_sheet_items_service_offer_id_fkey FOREIGN KEY (service_offer_id) REFERENCES crm_service_offers(id);
alter table public.crm_cost_sheets add constraint crm_cost_sheets_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES crm_enquiries(id);
alter table public.crm_cost_sheets add constraint crm_cost_sheets_key_contact_id_fkey FOREIGN KEY (key_contact_id) REFERENCES crm_contacts(id);
alter table public.crm_customs_records add constraint crm_customs_records_shipment_id_fkey FOREIGN KEY (shipment_id) REFERENCES crm_shipments(id) ON DELETE CASCADE;
alter table public.crm_daily_entries add constraint crm_daily_entries_cost_centre_id_fkey FOREIGN KEY (cost_centre_id) REFERENCES crm_cost_centres(id);
alter table public.crm_daily_entries add constraint crm_daily_entries_cost_line_id_fkey FOREIGN KEY (cost_line_id) REFERENCES crm_cost_lines(id);
alter table public.crm_daily_entries add constraint crm_daily_entries_entered_by_fkey FOREIGN KEY (entered_by) REFERENCES auth.users(id);
alter table public.crm_daily_entries add constraint crm_daily_entries_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id);
alter table public.crm_departments add constraint crm_departments_cost_centre_id_fkey FOREIGN KEY (cost_centre_id) REFERENCES crm_cost_centres(id);
alter table public.crm_departments add constraint crm_departments_head_user_id_fkey FOREIGN KEY (head_user_id) REFERENCES auth.users(id);
alter table public.crm_departments add constraint crm_departments_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES crm_departments(id);
alter table public.crm_email_log add constraint crm_email_log_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES crm_enquiries(id) ON DELETE SET NULL;
alter table public.crm_email_log add constraint crm_email_log_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES crm_opportunities(id) ON DELETE SET NULL;
alter table public.crm_email_log add constraint crm_email_log_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES crm_organizations(id) ON DELETE SET NULL;
alter table public.crm_employee_allowances add constraint crm_employee_allowances_employee_cost_id_fkey FOREIGN KEY (employee_cost_id) REFERENCES crm_employee_costs(id) ON DELETE CASCADE;
alter table public.crm_employee_cost_history add constraint crm_employee_cost_history_employee_cost_id_fkey FOREIGN KEY (employee_cost_id) REFERENCES crm_employee_costs(id) ON DELETE CASCADE;
alter table public.crm_employee_costs add constraint crm_employee_costs_cost_centre_id_fkey FOREIGN KEY (cost_centre_id) REFERENCES crm_cost_centres(id);
alter table public.crm_employee_costs add constraint crm_employee_costs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table public.crm_employee_profiles add constraint crm_employee_profiles_department_id_fkey FOREIGN KEY (department_id) REFERENCES crm_departments(id);
alter table public.crm_employee_profiles add constraint crm_employee_profiles_job_role_id_fkey FOREIGN KEY (job_role_id) REFERENCES crm_job_roles(id);
alter table public.crm_employee_profiles add constraint crm_employee_profiles_reporting_manager_fkey FOREIGN KEY (reporting_manager) REFERENCES auth.users(id);
alter table public.crm_employee_profiles add constraint crm_employee_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.crm_enquiries add constraint crm_enquiries_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES auth.users(id);
alter table public.crm_enquiries add constraint crm_enquiries_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES crm_contacts(id);
alter table public.crm_enquiries add constraint crm_enquiries_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES crm_organizations(id);
alter table public.crm_enquiries add constraint crm_enquiries_service_id_fkey FOREIGN KEY (service_id) REFERENCES crm_services(id);
alter table public.crm_enquiry_activity add constraint crm_enquiry_activity_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES crm_enquiries(id) ON DELETE CASCADE;
alter table public.crm_expenses add constraint crm_expenses_cost_line_id_fkey FOREIGN KEY (cost_line_id) REFERENCES crm_cost_lines(id);
alter table public.crm_expenses add constraint crm_expenses_order_id_fkey FOREIGN KEY (order_id) REFERENCES crm_orders(id);
alter table public.crm_expenses add constraint crm_expenses_project_id_fkey FOREIGN KEY (project_id) REFERENCES crm_projects(id);
alter table public.crm_fixed_expense_history add constraint crm_fixed_expense_history_fixed_expense_id_fkey FOREIGN KEY (fixed_expense_id) REFERENCES crm_fixed_expenses(id) ON DELETE CASCADE;
alter table public.crm_fixed_expenses add constraint crm_fixed_expenses_cost_centre_id_fkey FOREIGN KEY (cost_centre_id) REFERENCES crm_cost_centres(id);
alter table public.crm_invoice_items add constraint crm_invoice_items_cost_line_id_fkey FOREIGN KEY (cost_line_id) REFERENCES crm_cost_lines(id);
alter table public.crm_invoice_items add constraint crm_invoice_items_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES crm_invoices(id) ON DELETE CASCADE;
alter table public.crm_invoices add constraint crm_invoices_key_contact_id_fkey FOREIGN KEY (key_contact_id) REFERENCES crm_contacts(id);
alter table public.crm_invoices add constraint crm_invoices_order_id_fkey FOREIGN KEY (order_id) REFERENCES crm_orders(id);
alter table public.crm_invoices add constraint crm_invoices_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES crm_organizations(id);
alter table public.crm_invoices add constraint crm_invoices_project_id_fkey FOREIGN KEY (project_id) REFERENCES crm_projects(id);
alter table public.crm_invoices add constraint crm_invoices_quotation_id_fkey FOREIGN KEY (quotation_id) REFERENCES crm_quotations(id);
alter table public.crm_login_history add constraint crm_login_history_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.crm_opportunities add constraint crm_opportunities_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES auth.users(id);
alter table public.crm_opportunities add constraint crm_opportunities_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES crm_contacts(id);
alter table public.crm_opportunities add constraint crm_opportunities_converted_quotation_id_fkey FOREIGN KEY (converted_quotation_id) REFERENCES crm_quotations(id);
alter table public.crm_opportunities add constraint crm_opportunities_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES crm_enquiries(id);
alter table public.crm_opportunities add constraint crm_opportunities_key_contact_id_fkey FOREIGN KEY (key_contact_id) REFERENCES crm_contacts(id);
alter table public.crm_opportunities add constraint crm_opportunities_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES crm_organizations(id);
alter table public.crm_opportunities add constraint crm_opportunities_service_id_fkey FOREIGN KEY (service_id) REFERENCES crm_services(id);
alter table public.crm_opportunity_activity add constraint crm_opportunity_activity_opportunity_id_fkey FOREIGN KEY (opportunity_id) REFERENCES crm_opportunities(id) ON DELETE CASCADE;
alter table public.crm_order_events add constraint crm_order_events_order_id_fkey FOREIGN KEY (order_id) REFERENCES crm_orders(id) ON DELETE CASCADE;
alter table public.crm_order_items add constraint crm_order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES crm_orders(id) ON DELETE CASCADE;
alter table public.crm_order_milestones add constraint crm_order_milestones_order_id_fkey FOREIGN KEY (order_id) REFERENCES crm_orders(id) ON DELETE CASCADE;
alter table public.crm_order_tracking add constraint crm_order_tracking_order_id_fkey FOREIGN KEY (order_id) REFERENCES crm_orders(id) ON DELETE CASCADE;
alter table public.crm_order_tracking add constraint crm_order_tracking_tracking_template_id_fkey FOREIGN KEY (tracking_template_id) REFERENCES crm_tracking_templates(id);
alter table public.crm_orders add constraint crm_orders_assigned_manager_fkey FOREIGN KEY (assigned_manager) REFERENCES auth.users(id);
alter table public.crm_orders add constraint crm_orders_cost_sheet_id_fkey FOREIGN KEY (cost_sheet_id) REFERENCES crm_cost_sheets(id);
alter table public.crm_orders add constraint crm_orders_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES crm_enquiries(id);
alter table public.crm_orders add constraint crm_orders_key_contact_id_fkey FOREIGN KEY (key_contact_id) REFERENCES crm_contacts(id);
alter table public.crm_orders add constraint crm_orders_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES crm_organizations(id);
alter table public.crm_orders add constraint crm_orders_quotation_id_fkey FOREIGN KEY (quotation_id) REFERENCES crm_quotations(id);
alter table public.crm_orders add constraint crm_orders_service_id_fkey FOREIGN KEY (service_id) REFERENCES crm_services(id);
alter table public.crm_orders add constraint crm_orders_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES crm_vendors(id);
alter table public.crm_organizations add constraint crm_organizations_account_manager_fkey FOREIGN KEY (account_manager) REFERENCES auth.users(id);
alter table public.crm_outsourced_categories add constraint crm_outsourced_categories_branch_code_fkey FOREIGN KEY (branch_code) REFERENCES crm_service_branches(code);
alter table public.crm_outsourced_categories add constraint crm_outsourced_categories_typical_basis_fkey FOREIGN KEY (typical_basis) REFERENCES crm_billing_bases(code);
alter table public.crm_payment_allocations add constraint crm_payment_allocations_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES crm_invoices(id);
alter table public.crm_payment_allocations add constraint crm_payment_allocations_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES crm_payments(id) ON DELETE CASCADE;
alter table public.crm_payments add constraint crm_payments_key_contact_id_fkey FOREIGN KEY (key_contact_id) REFERENCES crm_contacts(id);
alter table public.crm_payments add constraint crm_payments_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES crm_organizations(id);
alter table public.crm_portal_members add constraint crm_portal_members_org_fk FOREIGN KEY (organization_id) REFERENCES crm_organizations(id) ON DELETE CASCADE;
alter table public.crm_portal_members add constraint crm_portal_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.crm_project_milestones add constraint crm_project_milestones_project_id_fkey FOREIGN KEY (project_id) REFERENCES crm_projects(id) ON DELETE CASCADE;
alter table public.crm_projects add constraint crm_projects_order_id_fkey FOREIGN KEY (order_id) REFERENCES crm_orders(id);
alter table public.crm_projects add constraint crm_projects_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES crm_organizations(id);
alter table public.crm_projects add constraint crm_projects_project_manager_fkey FOREIGN KEY (project_manager) REFERENCES auth.users(id);
alter table public.crm_projects add constraint crm_projects_quotation_id_fkey FOREIGN KEY (quotation_id) REFERENCES crm_quotations(id);
alter table public.crm_projects add constraint crm_projects_service_id_fkey FOREIGN KEY (service_id) REFERENCES crm_services(id);
alter table public.crm_prospects add constraint crm_prospects_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES auth.users(id);
alter table public.crm_prospects add constraint crm_prospects_converted_contact_id_fkey FOREIGN KEY (converted_contact_id) REFERENCES crm_contacts(id);
alter table public.crm_prospects add constraint crm_prospects_converted_enquiry_fk FOREIGN KEY (converted_enquiry_id) REFERENCES crm_enquiries(id);
alter table public.crm_prospects add constraint crm_prospects_converted_org_id_fkey FOREIGN KEY (converted_org_id) REFERENCES crm_organizations(id);
alter table public.crm_prospects add constraint crm_prospects_interested_service_id_fkey FOREIGN KEY (interested_service_id) REFERENCES crm_services(id);
alter table public.crm_quotation_approvals add constraint crm_quotation_approvals_quotation_id_fkey FOREIGN KEY (quotation_id) REFERENCES crm_quotations(id) ON DELETE CASCADE;
alter table public.crm_quotation_items add constraint crm_quotation_items_cost_line_id_fkey FOREIGN KEY (cost_line_id) REFERENCES crm_cost_lines(id);
alter table public.crm_quotation_items add constraint crm_quotation_items_quotation_id_fkey FOREIGN KEY (quotation_id) REFERENCES crm_quotations(id) ON DELETE CASCADE;
alter table public.crm_quotations add constraint crm_quotations_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES crm_contacts(id);
alter table public.crm_quotations add constraint crm_quotations_cost_sheet_id_fkey FOREIGN KEY (cost_sheet_id) REFERENCES crm_cost_sheets(id);
alter table public.crm_quotations add constraint crm_quotations_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES crm_enquiries(id);
alter table public.crm_quotations add constraint crm_quotations_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES crm_organizations(id);
alter table public.crm_quotations add constraint crm_quotations_service_id_fkey FOREIGN KEY (service_id) REFERENCES crm_services(id);
alter table public.crm_receipts add constraint crm_receipts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES crm_organizations(id);
alter table public.crm_receipts add constraint crm_receipts_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES crm_payments(id);
alter table public.crm_service_milestone_templates add constraint crm_service_milestone_templates_service_id_fkey FOREIGN KEY (service_id) REFERENCES crm_services(id) ON DELETE CASCADE;
alter table public.crm_service_offers add constraint crm_service_offers_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id);
alter table public.crm_service_offers add constraint crm_service_offers_billing_basis_fkey FOREIGN KEY (billing_basis) REFERENCES crm_billing_bases(code);
alter table public.crm_service_offers add constraint crm_service_offers_branch_code_fkey FOREIGN KEY (branch_code) REFERENCES crm_service_branches(code);
alter table public.crm_service_offers add constraint crm_service_offers_category_code_fkey FOREIGN KEY (category_code) REFERENCES crm_outsourced_categories(code);
alter table public.crm_service_offers add constraint crm_service_offers_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.crm_service_offers add constraint crm_service_offers_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES crm_service_providers(id) ON DELETE CASCADE;
alter table public.crm_service_provider_bank add constraint crm_service_provider_bank_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES crm_service_providers(id) ON DELETE CASCADE;
alter table public.crm_service_provider_bank add constraint crm_service_provider_bank_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
alter table public.crm_service_providers add constraint crm_service_providers_branch_code_fkey FOREIGN KEY (branch_code) REFERENCES crm_service_branches(code);
alter table public.crm_service_providers add constraint crm_service_providers_category_code_fkey FOREIGN KEY (category_code) REFERENCES crm_outsourced_categories(code);
alter table public.crm_service_providers add constraint crm_service_providers_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.crm_service_providers add constraint crm_service_providers_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
alter table public.crm_services add constraint crm_services_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES crm_services(id) ON DELETE SET NULL;
alter table public.crm_shipments add constraint crm_shipments_key_contact_id_fkey FOREIGN KEY (key_contact_id) REFERENCES crm_contacts(id);
alter table public.crm_shipments add constraint crm_shipments_order_id_fkey FOREIGN KEY (order_id) REFERENCES crm_orders(id);
alter table public.crm_shipments add constraint crm_shipments_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES crm_vendors(id);
alter table public.crm_staff_roles add constraint crm_staff_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.crm_stockists add constraint crm_stockists_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;
alter table public.crm_stockists add constraint crm_stockists_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES crm_organizations(id) ON DELETE CASCADE;
alter table public.crm_subscription_price_history add constraint crm_subscription_price_history_subscription_id_fkey FOREIGN KEY (subscription_id) REFERENCES crm_subscriptions(id) ON DELETE CASCADE;
alter table public.crm_subscriptions add constraint crm_subscriptions_cost_centre_id_fkey FOREIGN KEY (cost_centre_id) REFERENCES crm_cost_centres(id);
alter table public.crm_supplier_offers add constraint crm_supplier_offers_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES crm_enquiries(id) ON DELETE CASCADE;
alter table public.crm_supplier_offers add constraint crm_supplier_offers_key_contact_id_fkey FOREIGN KEY (key_contact_id) REFERENCES crm_contacts(id);
alter table public.crm_supplier_offers add constraint crm_supplier_offers_vendor_id_fkey FOREIGN KEY (vendor_id) REFERENCES crm_vendors(id);
alter table public.crm_timesheets add constraint crm_timesheets_employee_cost_id_fkey FOREIGN KEY (employee_cost_id) REFERENCES crm_employee_costs(id);
alter table public.crm_timesheets add constraint crm_timesheets_entered_by_fkey FOREIGN KEY (entered_by) REFERENCES auth.users(id);
alter table public.crm_tracking_template_steps add constraint crm_tracking_template_steps_template_id_fkey FOREIGN KEY (template_id) REFERENCES crm_tracking_templates(id) ON DELETE CASCADE;
alter table public.pharma_adverse_events add constraint pharma_adverse_events_complaint_id_fkey FOREIGN KEY (complaint_id) REFERENCES pharma_complaints(id);
alter table public.pharma_adverse_events add constraint pharma_adverse_events_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_adverse_events add constraint pharma_adverse_events_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id);
alter table public.pharma_adverse_events add constraint pharma_adverse_events_responsible_fkey FOREIGN KEY (responsible) REFERENCES auth.users(id);
alter table public.pharma_campaigns add constraint pharma_campaigns_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id);
alter table public.pharma_campaigns add constraint pharma_campaigns_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_campaigns add constraint pharma_campaigns_principal_org_fkey FOREIGN KEY (principal_org) REFERENCES crm_organizations(id);
alter table public.pharma_campaigns add constraint pharma_campaigns_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id);
alter table public.pharma_campaigns add constraint pharma_campaigns_responsible_fkey FOREIGN KEY (responsible) REFERENCES auth.users(id);
alter table public.pharma_campaigns add constraint pharma_campaigns_territory_id_fkey FOREIGN KEY (territory_id) REFERENCES pharma_territories(id);
alter table public.pharma_companies add constraint pharma_companies_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_companies add constraint pharma_companies_org_id_fkey FOREIGN KEY (org_id) REFERENCES crm_organizations(id) ON DELETE CASCADE;
alter table public.pharma_company_contacts add constraint pharma_company_contacts_org_id_fkey FOREIGN KEY (org_id) REFERENCES crm_organizations(id) ON DELETE CASCADE;
alter table public.pharma_complaints add constraint pharma_complaints_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_complaints add constraint pharma_complaints_distributor_id_fkey FOREIGN KEY (distributor_id) REFERENCES pharma_distributors(id);
alter table public.pharma_complaints add constraint pharma_complaints_doctor_id_fkey FOREIGN KEY (doctor_id) REFERENCES pharma_doctors(id);
alter table public.pharma_complaints add constraint pharma_complaints_hospital_id_fkey FOREIGN KEY (hospital_id) REFERENCES pharma_hospitals(id);
alter table public.pharma_complaints add constraint pharma_complaints_pharmacy_id_fkey FOREIGN KEY (pharmacy_id) REFERENCES pharma_pharmacies(id);
alter table public.pharma_complaints add constraint pharma_complaints_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id);
alter table public.pharma_complaints add constraint pharma_complaints_responsible_fkey FOREIGN KEY (responsible) REFERENCES auth.users(id);
alter table public.pharma_distributor_products add constraint pharma_distributor_products_distributor_id_fkey FOREIGN KEY (distributor_id) REFERENCES pharma_distributors(id) ON DELETE CASCADE;
alter table public.pharma_distributor_products add constraint pharma_distributor_products_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id) ON DELETE CASCADE;
alter table public.pharma_distributor_territories add constraint pharma_distributor_territories_distributor_id_fkey FOREIGN KEY (distributor_id) REFERENCES pharma_distributors(id) ON DELETE CASCADE;
alter table public.pharma_distributor_territories add constraint pharma_distributor_territories_territory_id_fkey FOREIGN KEY (territory_id) REFERENCES pharma_territories(id) ON DELETE CASCADE;
alter table public.pharma_distributors add constraint pharma_distributors_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_distributors add constraint pharma_distributors_org_id_fkey FOREIGN KEY (org_id) REFERENCES crm_organizations(id);
alter table public.pharma_distributors add constraint pharma_distributors_relationship_manager_fkey FOREIGN KEY (relationship_manager) REFERENCES auth.users(id);
alter table public.pharma_doctor_affiliations add constraint pharma_doctor_affiliations_doctor_id_fkey FOREIGN KEY (doctor_id) REFERENCES pharma_doctors(id) ON DELETE CASCADE;
alter table public.pharma_doctor_affiliations add constraint pharma_doctor_affiliations_hospital_id_fkey FOREIGN KEY (hospital_id) REFERENCES pharma_hospitals(id) ON DELETE SET NULL;
alter table public.pharma_doctor_products add constraint pharma_doctor_products_doctor_id_fkey FOREIGN KEY (doctor_id) REFERENCES pharma_doctors(id) ON DELETE CASCADE;
alter table public.pharma_doctor_products add constraint pharma_doctor_products_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id) ON DELETE CASCADE;
alter table public.pharma_doctors add constraint pharma_doctors_account_owner_fkey FOREIGN KEY (account_owner) REFERENCES auth.users(id);
alter table public.pharma_doctors add constraint pharma_doctors_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_doctors add constraint pharma_doctors_medical_rep_fkey FOREIGN KEY (medical_rep) REFERENCES auth.users(id);
alter table public.pharma_doctors add constraint pharma_doctors_territory_id_fkey FOREIGN KEY (territory_id) REFERENCES pharma_territories(id);
alter table public.pharma_engagement_spend add constraint pharma_engagement_spend_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id);
alter table public.pharma_engagement_spend add constraint pharma_engagement_spend_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES pharma_campaigns(id);
alter table public.pharma_engagement_spend add constraint pharma_engagement_spend_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_engagement_spend add constraint pharma_engagement_spend_doctor_id_fkey FOREIGN KEY (doctor_id) REFERENCES pharma_doctors(id) ON DELETE CASCADE;
alter table public.pharma_engagement_spend add constraint pharma_engagement_spend_hospital_id_fkey FOREIGN KEY (hospital_id) REFERENCES pharma_hospitals(id) ON DELETE CASCADE;
alter table public.pharma_engagement_spend add constraint pharma_engagement_spend_offer_id_fkey FOREIGN KEY (offer_id) REFERENCES pharma_promotional_offers(id);
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES pharma_campaigns(id);
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES pharma_toll_contracts(id);
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_crm_expense_id_fkey FOREIGN KEY (crm_expense_id) REFERENCES crm_expenses(id) ON DELETE CASCADE;
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_distributor_id_fkey FOREIGN KEY (distributor_id) REFERENCES pharma_distributors(id);
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_doctor_id_fkey FOREIGN KEY (doctor_id) REFERENCES pharma_doctors(id);
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_hospital_id_fkey FOREIGN KEY (hospital_id) REFERENCES pharma_hospitals(id);
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_pharmacy_id_fkey FOREIGN KEY (pharmacy_id) REFERENCES pharma_pharmacies(id);
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES pharma_plants(id);
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_principal_org_fkey FOREIGN KEY (principal_org) REFERENCES crm_organizations(id);
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id);
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_sales_order_id_fkey FOREIGN KEY (sales_order_id) REFERENCES pharma_sales_orders(id);
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_tender_id_fkey FOREIGN KEY (tender_id) REFERENCES pharma_tenders(id);
alter table public.pharma_expense_dimensions add constraint pharma_expense_dimensions_territory_id_fkey FOREIGN KEY (territory_id) REFERENCES pharma_territories(id);
alter table public.pharma_field_force add constraint pharma_field_force_reports_to_fkey FOREIGN KEY (reports_to) REFERENCES auth.users(id);
alter table public.pharma_field_force add constraint pharma_field_force_territory_id_fkey FOREIGN KEY (territory_id) REFERENCES pharma_territories(id);
alter table public.pharma_field_force add constraint pharma_field_force_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.pharma_hospitals add constraint pharma_hospitals_account_owner_fkey FOREIGN KEY (account_owner) REFERENCES auth.users(id);
alter table public.pharma_hospitals add constraint pharma_hospitals_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_hospitals add constraint pharma_hospitals_org_id_fkey FOREIGN KEY (org_id) REFERENCES crm_organizations(id);
alter table public.pharma_hospitals add constraint pharma_hospitals_territory_id_fkey FOREIGN KEY (territory_id) REFERENCES pharma_territories(id);
alter table public.pharma_inventory_batches add constraint pharma_inventory_batches_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id);
alter table public.pharma_inventory_batches add constraint pharma_inventory_batches_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES pharma_warehouses(id);
alter table public.pharma_inventory_movements add constraint pharma_inventory_movements_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES pharma_inventory_batches(id) ON DELETE CASCADE;
alter table public.pharma_inventory_movements add constraint pharma_inventory_movements_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_invoices add constraint pharma_invoices_collector_fkey FOREIGN KEY (collector) REFERENCES auth.users(id);
alter table public.pharma_invoices add constraint pharma_invoices_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_invoices add constraint pharma_invoices_distributor_id_fkey FOREIGN KEY (distributor_id) REFERENCES pharma_distributors(id);
alter table public.pharma_invoices add constraint pharma_invoices_hospital_id_fkey FOREIGN KEY (hospital_id) REFERENCES pharma_hospitals(id);
alter table public.pharma_invoices add constraint pharma_invoices_order_id_fkey FOREIGN KEY (order_id) REFERENCES pharma_sales_orders(id);
alter table public.pharma_invoices add constraint pharma_invoices_pharmacy_id_fkey FOREIGN KEY (pharmacy_id) REFERENCES pharma_pharmacies(id);
alter table public.pharma_offer_products add constraint pharma_offer_products_offer_id_fkey FOREIGN KEY (offer_id) REFERENCES pharma_promotional_offers(id) ON DELETE CASCADE;
alter table public.pharma_offer_products add constraint pharma_offer_products_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id) ON DELETE CASCADE;
alter table public.pharma_offer_targets add constraint pharma_offer_targets_distributor_id_fkey FOREIGN KEY (distributor_id) REFERENCES pharma_distributors(id) ON DELETE CASCADE;
alter table public.pharma_offer_targets add constraint pharma_offer_targets_doctor_id_fkey FOREIGN KEY (doctor_id) REFERENCES pharma_doctors(id) ON DELETE CASCADE;
alter table public.pharma_offer_targets add constraint pharma_offer_targets_hospital_id_fkey FOREIGN KEY (hospital_id) REFERENCES pharma_hospitals(id) ON DELETE CASCADE;
alter table public.pharma_offer_targets add constraint pharma_offer_targets_offer_id_fkey FOREIGN KEY (offer_id) REFERENCES pharma_promotional_offers(id) ON DELETE CASCADE;
alter table public.pharma_offer_targets add constraint pharma_offer_targets_pharmacy_id_fkey FOREIGN KEY (pharmacy_id) REFERENCES pharma_pharmacies(id) ON DELETE CASCADE;
alter table public.pharma_pharmacies add constraint pharma_pharmacies_account_owner_fkey FOREIGN KEY (account_owner) REFERENCES auth.users(id);
alter table public.pharma_pharmacies add constraint pharma_pharmacies_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_pharmacies add constraint pharma_pharmacies_preferred_distributor_fkey FOREIGN KEY (preferred_distributor) REFERENCES pharma_distributors(id) ON DELETE SET NULL;
alter table public.pharma_pharmacies add constraint pharma_pharmacies_sales_rep_fkey FOREIGN KEY (sales_rep) REFERENCES auth.users(id);
alter table public.pharma_pharmacies add constraint pharma_pharmacies_territory_id_fkey FOREIGN KEY (territory_id) REFERENCES pharma_territories(id);
alter table public.pharma_plant_capabilities add constraint pharma_plant_capabilities_dosage_form_fkey FOREIGN KEY (dosage_form) REFERENCES pharma_dosage_forms(code);
alter table public.pharma_plant_capabilities add constraint pharma_plant_capabilities_plant_code_id_fkey FOREIGN KEY (plant_code_id) REFERENCES pharma_plants(id) ON DELETE CASCADE;
alter table public.pharma_plants add constraint pharma_plants_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_plants add constraint pharma_plants_org_id_fkey FOREIGN KEY (org_id) REFERENCES crm_organizations(id);
alter table public.pharma_product_prices add constraint pharma_product_prices_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id);
alter table public.pharma_product_prices add constraint pharma_product_prices_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_product_prices add constraint pharma_product_prices_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id) ON DELETE CASCADE;
alter table public.pharma_product_regulatory add constraint pharma_product_regulatory_external_consultant_fkey FOREIGN KEY (external_consultant) REFERENCES crm_service_providers(id);
alter table public.pharma_product_regulatory add constraint pharma_product_regulatory_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id) ON DELETE CASCADE;
alter table public.pharma_product_regulatory add constraint pharma_product_regulatory_responsible_fkey FOREIGN KEY (responsible) REFERENCES auth.users(id);
alter table public.pharma_production_batches add constraint pharma_production_batches_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES pharma_toll_contracts(id);
alter table public.pharma_production_batches add constraint pharma_production_batches_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES pharma_plants(id);
alter table public.pharma_production_batches add constraint pharma_production_batches_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id);
alter table public.pharma_production_batches add constraint pharma_production_batches_released_by_fkey FOREIGN KEY (released_by) REFERENCES auth.users(id);
alter table public.pharma_products add constraint pharma_products_brand_owner_org_fkey FOREIGN KEY (brand_owner_org) REFERENCES crm_organizations(id);
alter table public.pharma_products add constraint pharma_products_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_products add constraint pharma_products_dosage_form_fkey FOREIGN KEY (dosage_form) REFERENCES pharma_dosage_forms(code);
alter table public.pharma_products add constraint pharma_products_importer_org_fkey FOREIGN KEY (importer_org) REFERENCES crm_organizations(id);
alter table public.pharma_products add constraint pharma_products_manufacturer_plant_fkey FOREIGN KEY (manufacturer_plant) REFERENCES pharma_plants(id);
alter table public.pharma_products add constraint pharma_products_marketing_org_fkey FOREIGN KEY (marketing_org) REFERENCES crm_organizations(id);
alter table public.pharma_products add constraint pharma_products_principal_org_fkey FOREIGN KEY (principal_org) REFERENCES crm_organizations(id);
alter table public.pharma_products add constraint pharma_products_therapeutic_category_fkey FOREIGN KEY (therapeutic_category) REFERENCES pharma_therapeutic_categories(code);
alter table public.pharma_products add constraint pharma_products_toll_manufacturer_fkey FOREIGN KEY (toll_manufacturer) REFERENCES pharma_plants(id);
alter table public.pharma_promotional_offers add constraint pharma_promotional_offers_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id);
alter table public.pharma_promotional_offers add constraint pharma_promotional_offers_category_code_fkey FOREIGN KEY (category_code) REFERENCES pharma_offer_categories(code);
alter table public.pharma_promotional_offers add constraint pharma_promotional_offers_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_promotional_offers add constraint pharma_promotional_offers_principal_org_fkey FOREIGN KEY (principal_org) REFERENCES crm_organizations(id);
alter table public.pharma_promotional_offers add constraint pharma_promotional_offers_territory_id_fkey FOREIGN KEY (territory_id) REFERENCES pharma_territories(id);
alter table public.pharma_recalls add constraint pharma_recalls_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id);
alter table public.pharma_recalls add constraint pharma_recalls_responsible_fkey FOREIGN KEY (responsible) REFERENCES auth.users(id);
alter table public.pharma_receipts add constraint pharma_receipts_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id);
alter table public.pharma_receipts add constraint pharma_receipts_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_receipts add constraint pharma_receipts_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES pharma_invoices(id) ON DELETE CASCADE;
alter table public.pharma_returns add constraint pharma_returns_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id);
alter table public.pharma_returns add constraint pharma_returns_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_returns add constraint pharma_returns_distributor_id_fkey FOREIGN KEY (distributor_id) REFERENCES pharma_distributors(id);
alter table public.pharma_returns add constraint pharma_returns_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES pharma_invoices(id);
alter table public.pharma_returns add constraint pharma_returns_order_id_fkey FOREIGN KEY (order_id) REFERENCES pharma_sales_orders(id);
alter table public.pharma_returns add constraint pharma_returns_pharmacy_id_fkey FOREIGN KEY (pharmacy_id) REFERENCES pharma_pharmacies(id);
alter table public.pharma_returns add constraint pharma_returns_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id);
alter table public.pharma_sales_order_items add constraint pharma_sales_order_items_batch_id_fkey FOREIGN KEY (batch_id) REFERENCES pharma_inventory_batches(id);
alter table public.pharma_sales_order_items add constraint pharma_sales_order_items_order_id_fkey FOREIGN KEY (order_id) REFERENCES pharma_sales_orders(id) ON DELETE CASCADE;
alter table public.pharma_sales_order_items add constraint pharma_sales_order_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id);
alter table public.pharma_sales_orders add constraint pharma_sales_orders_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_sales_orders add constraint pharma_sales_orders_credit_override_by_fkey FOREIGN KEY (credit_override_by) REFERENCES auth.users(id);
alter table public.pharma_sales_orders add constraint pharma_sales_orders_crm_order_id_fkey FOREIGN KEY (crm_order_id) REFERENCES crm_orders(id);
alter table public.pharma_sales_orders add constraint pharma_sales_orders_dispatch_warehouse_fkey FOREIGN KEY (dispatch_warehouse) REFERENCES pharma_warehouses(id);
alter table public.pharma_sales_orders add constraint pharma_sales_orders_distributor_id_fkey FOREIGN KEY (distributor_id) REFERENCES pharma_distributors(id);
alter table public.pharma_sales_orders add constraint pharma_sales_orders_hospital_id_fkey FOREIGN KEY (hospital_id) REFERENCES pharma_hospitals(id);
alter table public.pharma_sales_orders add constraint pharma_sales_orders_offer_id_fkey FOREIGN KEY (offer_id) REFERENCES pharma_promotional_offers(id);
alter table public.pharma_sales_orders add constraint pharma_sales_orders_org_id_fkey FOREIGN KEY (org_id) REFERENCES crm_organizations(id);
alter table public.pharma_sales_orders add constraint pharma_sales_orders_pharmacy_id_fkey FOREIGN KEY (pharmacy_id) REFERENCES pharma_pharmacies(id);
alter table public.pharma_sales_orders add constraint pharma_sales_orders_sales_rep_fkey FOREIGN KEY (sales_rep) REFERENCES auth.users(id);
alter table public.pharma_sales_orders add constraint pharma_sales_orders_territory_id_fkey FOREIGN KEY (territory_id) REFERENCES pharma_territories(id);
alter table public.pharma_sample_items add constraint pharma_sample_items_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id);
alter table public.pharma_sample_transactions add constraint pharma_sample_transactions_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES auth.users(id);
alter table public.pharma_sample_transactions add constraint pharma_sample_transactions_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES pharma_campaigns(id);
alter table public.pharma_sample_transactions add constraint pharma_sample_transactions_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_sample_transactions add constraint pharma_sample_transactions_doctor_id_fkey FOREIGN KEY (doctor_id) REFERENCES pharma_doctors(id);
alter table public.pharma_sample_transactions add constraint pharma_sample_transactions_holder_user_fkey FOREIGN KEY (holder_user) REFERENCES auth.users(id);
alter table public.pharma_sample_transactions add constraint pharma_sample_transactions_hospital_id_fkey FOREIGN KEY (hospital_id) REFERENCES pharma_hospitals(id);
alter table public.pharma_sample_transactions add constraint pharma_sample_transactions_item_id_fkey FOREIGN KEY (item_id) REFERENCES pharma_sample_items(id) ON DELETE CASCADE;
alter table public.pharma_sample_transactions add constraint pharma_sample_transactions_pharmacy_id_fkey FOREIGN KEY (pharmacy_id) REFERENCES pharma_pharmacies(id);
alter table public.pharma_sample_transactions add constraint pharma_sample_transactions_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES pharma_visits(id);
alter table public.pharma_tender_products add constraint pharma_tender_products_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id);
alter table public.pharma_tender_products add constraint pharma_tender_products_tender_id_fkey FOREIGN KEY (tender_id) REFERENCES pharma_tenders(id) ON DELETE CASCADE;
alter table public.pharma_tenders add constraint pharma_tenders_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_tenders add constraint pharma_tenders_hospital_id_fkey FOREIGN KEY (hospital_id) REFERENCES pharma_hospitals(id);
alter table public.pharma_tenders add constraint pharma_tenders_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users(id);
alter table public.pharma_territories add constraint pharma_territories_manager_id_fkey FOREIGN KEY (manager_id) REFERENCES auth.users(id);
alter table public.pharma_territories add constraint pharma_territories_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES pharma_territories(id);
alter table public.pharma_therapeutic_categories add constraint pharma_therapeutic_categories_parent_code_fkey FOREIGN KEY (parent_code) REFERENCES pharma_therapeutic_categories(code);
alter table public.pharma_toll_contracts add constraint pharma_toll_contracts_client_org_fkey FOREIGN KEY (client_org) REFERENCES crm_organizations(id);
alter table public.pharma_toll_contracts add constraint pharma_toll_contracts_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_toll_contracts add constraint pharma_toll_contracts_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES pharma_toll_enquiries(id);
alter table public.pharma_toll_contracts add constraint pharma_toll_contracts_offer_id_fkey FOREIGN KEY (offer_id) REFERENCES pharma_toll_offers(id);
alter table public.pharma_toll_contracts add constraint pharma_toll_contracts_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES pharma_plants(id);
alter table public.pharma_toll_contracts add constraint pharma_toll_contracts_product_id_fkey FOREIGN KEY (product_id) REFERENCES pharma_products(id);
alter table public.pharma_toll_enquiries add constraint pharma_toll_enquiries_client_org_fkey FOREIGN KEY (client_org) REFERENCES crm_organizations(id);
alter table public.pharma_toll_enquiries add constraint pharma_toll_enquiries_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_toll_enquiries add constraint pharma_toll_enquiries_dosage_form_fkey FOREIGN KEY (dosage_form) REFERENCES pharma_dosage_forms(code);
alter table public.pharma_toll_enquiries add constraint pharma_toll_enquiries_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES auth.users(id);
alter table public.pharma_toll_offers add constraint pharma_toll_offers_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
alter table public.pharma_toll_offers add constraint pharma_toll_offers_enquiry_id_fkey FOREIGN KEY (enquiry_id) REFERENCES pharma_toll_enquiries(id) ON DELETE CASCADE;
alter table public.pharma_toll_offers add constraint pharma_toll_offers_plant_id_fkey FOREIGN KEY (plant_id) REFERENCES pharma_plants(id);
alter table public.pharma_visit_plans add constraint pharma_visit_plans_territory_id_fkey FOREIGN KEY (territory_id) REFERENCES pharma_territories(id);
alter table public.pharma_visit_plans add constraint pharma_visit_plans_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table public.pharma_visits add constraint pharma_visits_campaign_id_fkey FOREIGN KEY (campaign_id) REFERENCES pharma_campaigns(id);
alter table public.pharma_visits add constraint pharma_visits_distributor_id_fkey FOREIGN KEY (distributor_id) REFERENCES pharma_distributors(id);
alter table public.pharma_visits add constraint pharma_visits_doctor_id_fkey FOREIGN KEY (doctor_id) REFERENCES pharma_doctors(id);
alter table public.pharma_visits add constraint pharma_visits_hospital_id_fkey FOREIGN KEY (hospital_id) REFERENCES pharma_hospitals(id);
alter table public.pharma_visits add constraint pharma_visits_pharmacy_id_fkey FOREIGN KEY (pharmacy_id) REFERENCES pharma_pharmacies(id);
alter table public.pharma_visits add constraint pharma_visits_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES pharma_visit_plans(id);
alter table public.pharma_visits add constraint pharma_visits_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES auth.users(id);
alter table public.pharma_visits add constraint pharma_visits_visited_by_fkey FOREIGN KEY (visited_by) REFERENCES auth.users(id);
alter table public.pharma_warehouses add constraint pharma_warehouses_distributor_id_fkey FOREIGN KEY (distributor_id) REFERENCES pharma_distributors(id);
alter table public.pharma_warehouses add constraint pharma_warehouses_org_id_fkey FOREIGN KEY (org_id) REFERENCES crm_organizations(id);
alter table public.pharma_warehouses add constraint pharma_warehouses_territory_id_fkey FOREIGN KEY (territory_id) REFERENCES pharma_territories(id);
alter table public.profiles add constraint profiles_client_fk FOREIGN KEY (client_id) REFERENCES clients(id);
alter table public.profiles add constraint profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table public.social_posts add constraint social_posts_asset_id_fkey FOREIGN KEY (asset_id) REFERENCES social_assets(id) ON DELETE SET NULL;
alter table public.social_posts add constraint social_posts_calendar_id_fkey FOREIGN KEY (calendar_id) REFERENCES social_content_calendar(id) ON DELETE SET NULL;
alter table public.training_assignments add constraint training_assignments_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE;
alter table public.training_assignments add constraint training_assignments_module_id_fkey FOREIGN KEY (module_id) REFERENCES training_modules(id) ON DELETE CASCADE;
alter table public.training_certificates add constraint training_certificates_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE;
alter table public.training_certificates add constraint training_certificates_module_id_fkey FOREIGN KEY (module_id) REFERENCES training_modules(id) ON DELETE CASCADE;
alter table public.training_quiz_attempts add constraint training_quiz_attempts_client_id_fkey FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE;
alter table public.training_quiz_attempts add constraint training_quiz_attempts_module_id_fkey FOREIGN KEY (module_id) REFERENCES training_modules(id) ON DELETE CASCADE;
alter table public.training_quiz_questions add constraint training_quiz_questions_module_id_fkey FOREIGN KEY (module_id) REFERENCES training_modules(id) ON DELETE CASCADE;
