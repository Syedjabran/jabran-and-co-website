-- Baseline 05: views in schema public (78), from pg_get_viewdef(), in
-- dependency order. "depth" = longest chain of public views this view reads
-- (resolved via pg_rewrite/pg_depend); within a depth, alphabetical.
-- reloptions (security_invoker) are reproduced as on production; views without
-- a "with (...)" clause run with the owner's rights (security definer
-- semantics) on production too.

-- depth 0
create or replace view public.analytics_fact_enquiries as
 SELECT e.id,
    e.created_at,
    e.organization_id AS org_id,
    s.name AS service,
    e.status,
    e.source,
    analytics_derive_channel(e.utm_source, e.utm_medium, e.referrer, e.click_id, e.landing_page) AS channel,
    e.utm_source,
    e.utm_medium,
    e.utm_campaign,
    e.referrer,
    e.landing_page
   FROM (crm_enquiries e
     LEFT JOIN crm_services s ON ((s.id = e.service_id)))
  WHERE (e.deleted_at IS NULL);

-- depth 0
create or replace view public.analytics_fact_opportunities as
 SELECT id,
    created_at,
    organization_id AS org_id,
    NULL::text AS service,
    stage,
    (estimated_value)::numeric AS est_value,
    (probability_pct)::numeric AS probability
   FROM crm_opportunities
  WHERE (deleted_at IS NULL);

-- depth 0
create or replace view public.analytics_fact_quotations as
 SELECT id,
    created_at,
    organization_id AS org_id,
    NULL::text AS service,
    status,
    (total)::numeric AS total,
    currency
   FROM crm_quotations
  WHERE (deleted_at IS NULL);

-- depth 0
create or replace view public.analytics_my_orgs as
 SELECT organization_id AS org_id
   FROM crm_portal_members
  WHERE (user_id = auth.uid());

-- depth 0
create or replace view public.crm_allocations_monthly with (security_invoker=true) as
 SELECT period,
    sum(allocated_amount) AS allocated,
    count(DISTINCT order_id) AS orders
   FROM crm_cost_allocations
  GROUP BY period;

-- depth 0
create or replace view public.crm_cc_funnel with (security_invoker=on) as
 SELECT 1 AS sort,
    'Enquiries'::text AS stage,
    count(*) AS n
   FROM crm_enquiries
  WHERE (crm_enquiries.deleted_at IS NULL)
UNION ALL
 SELECT 2 AS sort,
    'Opportunities'::text AS stage,
    count(*) AS n
   FROM crm_opportunities
  WHERE (crm_opportunities.deleted_at IS NULL)
UNION ALL
 SELECT 3 AS sort,
    'Quotations'::text AS stage,
    count(DISTINCT crm_quotations.quotation_group) AS n
   FROM crm_quotations
  WHERE (crm_quotations.deleted_at IS NULL)
UNION ALL
 SELECT 4 AS sort,
    'Orders'::text AS stage,
    count(*) AS n
   FROM crm_orders
  WHERE (crm_orders.deleted_at IS NULL)
UNION ALL
 SELECT 5 AS sort,
    'Paid Orders'::text AS stage,
    count(*) AS n
   FROM crm_orders
  WHERE ((crm_orders.deleted_at IS NULL) AND (crm_orders.payment_status = 'paid'::text));

-- depth 0
create or replace view public.crm_cc_kpis with (security_invoker=on) as
 SELECT ( SELECT COALESCE(sum(crm_invoices.total), (0)::numeric) AS "coalesce"
           FROM crm_invoices
          WHERE ((crm_invoices.deleted_at IS NULL) AND (crm_invoices.status = ANY (ARRAY['issued'::text, 'partially_paid'::text, 'paid'::text, 'overdue'::text])) AND (crm_invoices.issue_date >= date_trunc('year'::text, (CURRENT_DATE)::timestamp with time zone)))) AS revenue_ytd,
    ( SELECT COALESCE(sum(crm_payments.net_received), (0)::numeric) AS "coalesce"
           FROM crm_payments
          WHERE ((crm_payments.deleted_at IS NULL) AND crm_payments.is_verified AND (crm_payments.payment_date >= date_trunc('year'::text, (CURRENT_DATE)::timestamp with time zone)))) AS collected_ytd,
    ( SELECT COALESCE(sum(crm_invoices.outstanding), (0)::numeric) AS "coalesce"
           FROM crm_invoices
          WHERE ((crm_invoices.deleted_at IS NULL) AND (crm_invoices.outstanding > (0)::numeric) AND (crm_invoices.status = ANY (ARRAY['issued'::text, 'partially_paid'::text, 'overdue'::text])))) AS outstanding_ar,
    ( SELECT COALESCE(sum(crm_expenses.amount), (0)::numeric) AS "coalesce"
           FROM crm_expenses
          WHERE ((crm_expenses.deleted_at IS NULL) AND (crm_expenses.expense_date >= date_trunc('year'::text, (CURRENT_DATE)::timestamp with time zone)))) AS expenses_ytd,
    ( SELECT COALESCE(sum(crm_opportunities.weighted_value), (0)::numeric) AS "coalesce"
           FROM crm_opportunities
          WHERE ((crm_opportunities.deleted_at IS NULL) AND (crm_opportunities.stage <> ALL (ARRAY['won'::text, 'lost'::text])))) AS weighted_pipeline,
    ( SELECT count(*) AS count
           FROM crm_opportunities
          WHERE ((crm_opportunities.deleted_at IS NULL) AND (crm_opportunities.stage <> ALL (ARRAY['won'::text, 'lost'::text])))) AS open_opportunities,
    ( SELECT count(*) AS count
           FROM crm_quotations
          WHERE ((crm_quotations.deleted_at IS NULL) AND (crm_quotations.status = ANY (ARRAY['issued'::text, 'viewed'::text])))) AS quotations_awaiting_client,
    ( SELECT count(*) AS count
           FROM crm_quotations
          WHERE ((crm_quotations.deleted_at IS NULL) AND (crm_quotations.status = 'pending_approval'::text))) AS quotations_awaiting_approval,
    ( SELECT count(*) AS count
           FROM crm_enquiries
          WHERE ((crm_enquiries.deleted_at IS NULL) AND (crm_enquiries.status = ANY (ARRAY['new'::text, 'under_review'::text, 'information_required'::text])))) AS open_enquiries,
    ( SELECT count(*) AS count
           FROM crm_orders
          WHERE ((crm_orders.deleted_at IS NULL) AND (crm_orders.status <> ALL (ARRAY['completed'::text, 'cancelled'::text, 'closed'::text])))) AS active_orders;

-- depth 0
create or replace view public.crm_cc_monthly with (security_invoker=on) as
 WITH months AS (
         SELECT (date_trunc('month'::text, (CURRENT_DATE)::timestamp with time zone) - ('1 mon'::interval * (g.g)::double precision)) AS m
           FROM generate_series(11, 0, '-1'::integer) g(g)
        )
 SELECT to_char(m, 'Mon YYYY'::text) AS month_label,
    (m)::date AS month_start,
    COALESCE(( SELECT sum(i.total) AS sum
           FROM crm_invoices i
          WHERE ((i.deleted_at IS NULL) AND (i.status = ANY (ARRAY['issued'::text, 'partially_paid'::text, 'paid'::text, 'overdue'::text])) AND (date_trunc('month'::text, (i.issue_date)::timestamp with time zone) = m.m))), (0)::numeric) AS invoiced,
    COALESCE(( SELECT sum(p.net_received) AS sum
           FROM crm_payments p
          WHERE ((p.deleted_at IS NULL) AND p.is_verified AND (date_trunc('month'::text, (p.payment_date)::timestamp with time zone) = m.m))), (0)::numeric) AS collected,
    COALESCE(( SELECT sum(e.amount) AS sum
           FROM crm_expenses e
          WHERE ((e.deleted_at IS NULL) AND (date_trunc('month'::text, (e.expense_date)::timestamp with time zone) = m.m))), (0)::numeric) AS expenses
   FROM months m
  ORDER BY m;

-- depth 0
create or replace view public.crm_cc_order_status with (security_invoker=on) as
 SELECT status,
    count(*) AS n
   FROM crm_orders
  WHERE (deleted_at IS NULL)
  GROUP BY status;

-- depth 0
create or replace view public.crm_cc_project_status with (security_invoker=on) as
 SELECT status,
    count(*) AS n
   FROM crm_projects
  WHERE (deleted_at IS NULL)
  GROUP BY status;

-- depth 0
create or replace view public.crm_cc_quotation_outcomes with (security_invoker=on) as
 SELECT status,
    count(*) AS n
   FROM crm_quotations
  WHERE (deleted_at IS NULL)
  GROUP BY status;

-- depth 0
create or replace view public.crm_cc_revenue_client with (security_invoker=on) as
 SELECT g.legal_name AS client,
    g.id AS organization_id,
    sum(o.order_value) AS order_value,
    count(*) AS orders
   FROM (crm_orders o
     JOIN crm_organizations g ON ((g.id = o.organization_id)))
  WHERE ((o.deleted_at IS NULL) AND (o.status <> 'cancelled'::text))
  GROUP BY g.legal_name, g.id
  ORDER BY (sum(o.order_value)) DESC
 LIMIT 10;

-- depth 0
create or replace view public.crm_cc_revenue_country with (security_invoker=on) as
 SELECT COALESCE(g.country, 'Unspecified'::text) AS country,
    sum(o.order_value) AS order_value,
    count(*) AS orders
   FROM (crm_orders o
     JOIN crm_organizations g ON ((g.id = o.organization_id)))
  WHERE ((o.deleted_at IS NULL) AND (o.status <> 'cancelled'::text))
  GROUP BY COALESCE(g.country, 'Unspecified'::text)
  ORDER BY (sum(o.order_value)) DESC;

-- depth 0
create or replace view public.crm_cc_revenue_service with (security_invoker=on) as
 SELECT COALESCE(s.name, 'Unassigned'::text) AS service,
    sum(o.order_value) AS order_value,
    count(*) AS orders
   FROM (crm_orders o
     LEFT JOIN crm_services s ON ((s.id = o.service_id)))
  WHERE ((o.deleted_at IS NULL) AND (o.status <> 'cancelled'::text))
  GROUP BY COALESCE(s.name, 'Unassigned'::text)
  ORDER BY (sum(o.order_value)) DESC;

-- depth 0
create or replace view public.crm_cc_shipment_status with (security_invoker=on) as
 SELECT status,
    count(*) AS n
   FROM crm_shipments
  WHERE (deleted_at IS NULL)
  GROUP BY status;

-- depth 0
create or replace view public.crm_client_invoices with (security_invoker=on) as
 SELECT id,
    invoice_number,
    organization_id,
    order_id,
    project_id,
    invoice_type,
    title,
    issue_date,
    due_date,
    currency,
    subtotal,
    discount_amount,
    tax_amount,
    freight_amount,
    other_charges,
    total,
    paid_amount,
    outstanding,
    payment_terms,
    payment_instructions,
    notes,
    status
   FROM crm_invoices;

-- depth 0
create or replace view public.crm_client_orders with (security_invoker=on) as
 SELECT id,
    order_number,
    organization_id,
    service_id,
    title,
    currency,
    order_value,
    payment_terms,
    delivery_terms,
    incoterm,
    order_date,
    promised_date,
    expected_completion,
    crm_order_client_status(status) AS status,
    payment_status
   FROM crm_orders o
  WHERE ((organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)) AND (deleted_at IS NULL));

-- depth 0
create or replace view public.crm_client_projects as
 SELECT id,
    project_number,
    organization_id,
    service_id,
    title,
    scope,
    start_date,
    due_date,
    completion_pct,
    status
   FROM crm_projects
  WHERE ((organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)) AND (deleted_at IS NULL) AND (client_visible = true));

-- depth 0
create or replace view public.crm_client_quotations with (security_invoker=on) as
 SELECT id,
    quotation_number,
    version,
    organization_id,
    service_id,
    title,
    issue_date,
    expiry_date,
    currency,
    discount_pct,
    tax_pct,
    freight_amount,
    other_charges,
    subtotal,
    discount_amount,
    tax_amount,
    total,
    payment_terms,
    delivery_terms,
    incoterm,
    delivery_timeline,
    warranty,
    assumptions,
    exclusions,
    terms_conditions,
    client_notes,
    status,
    client_action_at,
    client_action_comment,
    executive_summary,
    requirement_understanding,
    scope_of_work,
    technical_specifications,
    timeline_milestones,
    payment_schedule
   FROM crm_quotations;

-- depth 0
create or replace view public.crm_client_shipments with (security_invoker=on) as
 SELECT s.id,
    s.shipment_number,
    s.order_id,
    s.mode,
    s.destination_port,
    s.etd,
    s.eta,
        CASE s.status
            WHEN 'planned'::text THEN 'Being Arranged'::text
            WHEN 'booked'::text THEN 'Booked'::text
            WHEN 'at_origin_port'::text THEN 'At Origin Port'::text
            WHEN 'departed'::text THEN 'Departed'::text
            WHEN 'in_transit'::text THEN 'In Transit'::text
            WHEN 'arrived'::text THEN 'Arrived at Destination'::text
            WHEN 'customs'::text THEN 'In Customs Clearance'::text
            WHEN 'cleared'::text THEN 'Customs Cleared'::text
            WHEN 'delivered'::text THEN 'Delivered'::text
            WHEN 'delayed'::text THEN 'Delayed'::text
            WHEN 'cancelled'::text THEN 'Cancelled'::text
            ELSE 'In Progress'::text
        END AS status
   FROM (crm_shipments s
     JOIN crm_orders o ON ((o.id = s.order_id)))
  WHERE ((o.organization_id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)) AND (s.deleted_at IS NULL) AND (o.deleted_at IS NULL));

-- depth 0
create or replace view public.crm_cost_line_performance with (security_invoker=true) as
 WITH quoted AS (
         SELECT qi.cost_line_id,
            sum((qi.quantity * qi.unit_price)) AS quoted_value,
            count(*) AS quoted_lines
           FROM crm_quotation_items qi
          WHERE (qi.cost_line_id IS NOT NULL)
          GROUP BY qi.cost_line_id
        ), sheeted AS (
         SELECT csi.cost_line_id,
            sum(csi.estimated_amount) AS estimated_cost,
            sum(csi.actual_amount) AS actual_cost,
            count(*) AS sheet_lines
           FROM crm_cost_sheet_items csi
          WHERE (csi.cost_line_id IS NOT NULL)
          GROUP BY csi.cost_line_id
        ), spent AS (
         SELECT e.cost_line_id,
            sum(e.amount) AS ledger_spend,
            count(*) AS ledger_lines
           FROM crm_expenses e
          WHERE ((e.cost_line_id IS NOT NULL) AND (e.deleted_at IS NULL))
          GROUP BY e.cost_line_id
        )
 SELECT l.code,
    l.name,
    c.letter,
    c.name AS category,
    l.line_kind,
    COALESCE(q.quoted_value, (0)::numeric) AS quoted_value,
    COALESCE(s.estimated_cost, (0)::numeric) AS estimated_cost,
    COALESCE(s.actual_cost, (0)::numeric) AS actual_cost,
    COALESCE(x.ledger_spend, (0)::numeric) AS ledger_spend,
        CASE
            WHEN (COALESCE(s.estimated_cost, (0)::numeric) <> (0)::numeric) THEN round((((COALESCE(s.actual_cost, (0)::numeric) - s.estimated_cost) / s.estimated_cost) * (100)::numeric), 2)
            ELSE NULL::numeric
        END AS cost_variance_pct,
        CASE
            WHEN ((l.line_kind = 'service_fee'::text) AND (COALESCE(q.quoted_value, (0)::numeric) <> (0)::numeric)) THEN round((((q.quoted_value - COALESCE(s.actual_cost, (0)::numeric)) / q.quoted_value) * (100)::numeric), 2)
            ELSE NULL::numeric
        END AS margin_pct,
    ((COALESCE(q.quoted_lines, (0)::bigint) + COALESCE(s.sheet_lines, (0)::bigint)) + COALESCE(x.ledger_lines, (0)::bigint)) AS usage_count
   FROM ((((crm_cost_lines l
     JOIN crm_cost_categories c ON ((c.code = l.category_code)))
     LEFT JOIN quoted q ON ((q.cost_line_id = l.id)))
     LEFT JOIN sheeted s ON ((s.cost_line_id = l.id)))
     LEFT JOIN spent x ON ((x.cost_line_id = l.id)))
  WHERE (((COALESCE(q.quoted_lines, (0)::bigint) + COALESCE(s.sheet_lines, (0)::bigint)) + COALESCE(x.ledger_lines, (0)::bigint)) > 0);

-- depth 0
create or replace view public.crm_cost_sheet_breakdown with (security_invoker=true) as
 SELECT i.id,
    i.cost_sheet_id,
    COALESCE(l.name, initcap(replace(COALESCE(i.category, 'other'::text), '_'::text, ' '::text))) AS cost_item,
    l.line_kind AS cost_source,
    COALESCE(b.name, 'Direct amount'::text) AS billing_basis,
    i.rate,
    i.quantity,
    i.resources,
    i.overtime_hours,
    i.overtime_rate,
    i.additional_charges,
    i.discount_amount,
    i.tax_amount,
    i.computed_amount,
    i.estimated_amount,
    i.actual_amount,
    i.effective_amount AS line_total,
    i.borne_by,
        CASE
            WHEN ((i.rate IS NOT NULL) AND (i.quantity IS NOT NULL)) THEN ((((((((TRIM(BOTH FROM to_char(i.rate, 'FM999999990.00'::text)) || ' x '::text) || TRIM(BOTH FROM to_char(i.quantity, 'FM999999990.###'::text))) || ' '::text) || lower(COALESCE(b.qty_label, 'units'::text))) ||
            CASE
                WHEN (COALESCE(i.resources, 1) > 1) THEN ((' x '::text || i.resources) || ' resources'::text)
                ELSE ''::text
            END) ||
            CASE
                WHEN (COALESCE(i.overtime_hours, (0)::numeric) > (0)::numeric) THEN (((' + overtime '::text || TRIM(BOTH FROM to_char(i.overtime_rate, 'FM999999990.00'::text))) || ' x '::text) || TRIM(BOTH FROM to_char(i.overtime_hours, 'FM999999990.##'::text)))
                ELSE ''::text
            END) ||
            CASE
                WHEN (COALESCE(i.discount_amount, (0)::numeric) > (0)::numeric) THEN (' − discount '::text || TRIM(BOTH FROM to_char(i.discount_amount, 'FM999999990.00'::text)))
                ELSE ''::text
            END) ||
            CASE
                WHEN (COALESCE(i.tax_amount, (0)::numeric) > (0)::numeric) THEN (' + tax '::text || TRIM(BOTH FROM to_char(i.tax_amount, 'FM999999990.00'::text)))
                ELSE ''::text
            END)
            ELSE 'Amount entered directly'::text
        END AS how_calculated
   FROM ((crm_cost_sheet_items i
     LEFT JOIN crm_cost_lines l ON ((l.id = i.cost_line_id)))
     LEFT JOIN crm_billing_bases b ON ((b.code = COALESCE(i.billing_basis, l.billing_basis))));

-- depth 0
create or replace view public.crm_cost_sheet_items_classified with (security_invoker=true) as
 SELECT i.id,
    i.cost_sheet_id,
    i.category,
    i.description,
    i.estimated_amount,
    i.revised_amount,
    i.actual_amount,
    i.borne_by,
    i.tax_recoverable,
    i.sort_order,
    i.created_at,
    i.cost_line_id,
    COALESCE(l.code, ('LEGACY:'::text || COALESCE(i.category, 'unspecified'::text))) AS resolved_code,
    COALESCE(l.name, initcap(replace(COALESCE(i.category, 'other'::text), '_'::text, ' '::text))) AS resolved_name,
    COALESCE(l.line_kind,
        CASE
            WHEN (i.category = ANY (ARRAY['customs_duty'::text, 'sales_tax'::text, 'withholding_tax'::text])) THEN 'tax_duty'::text
            WHEN (i.category = 'demurrage'::text) THEN 'penalty'::text
            WHEN (i.category = ANY (ARRAY['project_mgmt'::text, 'commission'::text])) THEN 'service_fee'::text
            WHEN (i.category = ANY (ARRAY['admin_allocation'::text, 'finance_cost'::text, 'marketing'::text])) THEN 'internal_cost'::text
            ELSE 'pass_through'::text
        END) AS resolved_kind,
    COALESCE(l.category_code,
        CASE
            WHEN (i.category = ANY (ARRAY['customs_duty'::text, 'sales_tax'::text, 'withholding_tax'::text, 'clearing'::text])) THEN 'customs'::text
            WHEN (i.category = ANY (ARRAY['freight'::text, 'insurance'::text, 'local_transport'::text, 'demurrage'::text])) THEN 'logistics'::text
            WHEN (i.category = ANY (ARRAY['supplier_cost'::text, 'samples'::text, 'tooling'::text, 'packaging'::text, 'certification'::text, 'inspection'::text, 'export_docs'::text, 'origin_transport'::text, 'bank_charges'::text])) THEN 'trading_sourcing'::text
            ELSE 'internal_resource'::text
        END) AS resolved_category
   FROM (crm_cost_sheet_items i
     LEFT JOIN crm_cost_lines l ON ((l.id = i.cost_line_id)));

-- depth 0
create or replace view public.crm_cost_sheet_totals with (security_invoker=on) as
 SELECT cs.id AS cost_sheet_id,
    cs.currency,
    cs.quantity,
    sum(COALESCE(i.estimated_amount, (0)::numeric)) AS est_subtotal,
    sum(COALESCE(i.revised_amount, i.estimated_amount, (0)::numeric)) AS revised_subtotal,
    sum(COALESCE(i.actual_amount, (0)::numeric)) AS actual_subtotal,
    round((sum(COALESCE(i.estimated_amount, (0)::numeric)) * ((1)::numeric + (cs.contingency_pct / 100.0))), 2) AS est_total_with_contingency,
    round((sum(COALESCE(i.actual_amount, (0)::numeric)) - sum(COALESCE(i.estimated_amount, (0)::numeric))), 2) AS variance,
        CASE
            WHEN (sum(COALESCE(i.estimated_amount, (0)::numeric)) > (0)::numeric) THEN round((((sum(COALESCE(i.actual_amount, (0)::numeric)) - sum(COALESCE(i.estimated_amount, (0)::numeric))) / sum(COALESCE(i.estimated_amount, (0)::numeric))) * (100)::numeric), 2)
            ELSE NULL::numeric
        END AS variance_pct,
        CASE
            WHEN (cs.quantity > (0)::numeric) THEN round(((sum(COALESCE(i.estimated_amount, (0)::numeric)) * ((1)::numeric + (cs.contingency_pct / 100.0))) / cs.quantity), 4)
            ELSE NULL::numeric
        END AS est_landed_cost_per_unit
   FROM (crm_cost_sheets cs
     LEFT JOIN crm_cost_sheet_items i ON ((i.cost_sheet_id = cs.id)))
  WHERE (cs.deleted_at IS NULL)
  GROUP BY cs.id, cs.currency, cs.quantity, cs.contingency_pct;

-- depth 0
create or replace view public.crm_department_directory with (security_invoker=true) as
 SELECT d.id,
    d.code,
    d.name,
    d.head_user_id,
    d.is_active,
    d.sort_order,
    c.name AS cost_centre,
    ( SELECT count(*) AS count
           FROM crm_employee_profiles p
          WHERE (p.department_id = d.id)) AS headcount
   FROM (crm_departments d
     LEFT JOIN crm_cost_centres c ON ((c.id = d.cost_centre_id)));

-- depth 0
create or replace view public.crm_employee_cost_rates with (security_invoker=true) as
 WITH basis AS (
         SELECT COALESCE(( SELECT (NULLIF((crm_settings.value #>> '{}'::text[]), ''::text))::numeric AS "nullif"
                   FROM crm_settings
                  WHERE (crm_settings.key = 'working_hours_per_day'::text)), (8)::numeric) AS hours_per_day,
            COALESCE(( SELECT (NULLIF((crm_settings.value #>> '{}'::text[]), ''::text))::numeric AS "nullif"
                   FROM crm_settings
                  WHERE (crm_settings.key = 'working_days_per_month'::text)), (22)::numeric) AS days_per_month
        ), allow AS (
         SELECT crm_employee_allowances.employee_cost_id,
            sum(crm_employee_allowances.monthly_amount) FILTER (WHERE (NOT crm_employee_allowances.is_deduction)) AS allowances_monthly,
            sum(crm_employee_allowances.monthly_amount) FILTER (WHERE crm_employee_allowances.is_deduction) AS deductions_monthly
           FROM crm_employee_allowances
          WHERE crm_employee_allowances.is_active
          GROUP BY crm_employee_allowances.employee_cost_id
        )
 SELECT e.id,
    e.user_id,
    e.employee_name,
    e.designation,
    e.cost_centre_id,
    e.employment_type,
    e.joining_date,
    e.status,
    e.currency,
    e.monthly_salary,
    e.monthly_bonus_avg,
    e.employer_contributions,
    e.commission_pct,
    e.hourly_rate_manual,
    e.daily_rate_manual,
    e.overtime_rate,
    e.consultancy_rate,
    e.opportunity_cost_hour,
    e.notes,
    e.created_by,
    e.created_at,
    e.updated_at,
    e.deleted_at,
    COALESCE(a.allowances_monthly, (0)::numeric) AS allowances_monthly,
    COALESCE(a.deductions_monthly, (0)::numeric) AS deductions_monthly,
    round(((((e.monthly_salary + COALESCE(a.allowances_monthly, (0)::numeric)) - COALESCE(a.deductions_monthly, (0)::numeric)) + e.employer_contributions) + e.monthly_bonus_avg), 2) AS total_monthly_cost,
    b.hours_per_day,
    b.days_per_month,
    round((((((e.monthly_salary + COALESCE(a.allowances_monthly, (0)::numeric)) - COALESCE(a.deductions_monthly, (0)::numeric)) + e.employer_contributions) + e.monthly_bonus_avg) / NULLIF(b.days_per_month, (0)::numeric)), 2) AS derived_daily_rate,
    round((((((e.monthly_salary + COALESCE(a.allowances_monthly, (0)::numeric)) - COALESCE(a.deductions_monthly, (0)::numeric)) + e.employer_contributions) + e.monthly_bonus_avg) / NULLIF((b.days_per_month * b.hours_per_day), (0)::numeric)), 2) AS derived_hourly_rate,
    COALESCE(e.daily_rate_manual, round((((((e.monthly_salary + COALESCE(a.allowances_monthly, (0)::numeric)) - COALESCE(a.deductions_monthly, (0)::numeric)) + e.employer_contributions) + e.monthly_bonus_avg) / NULLIF(b.days_per_month, (0)::numeric)), 2)) AS effective_daily_rate,
    COALESCE(e.hourly_rate_manual, round((((((e.monthly_salary + COALESCE(a.allowances_monthly, (0)::numeric)) - COALESCE(a.deductions_monthly, (0)::numeric)) + e.employer_contributions) + e.monthly_bonus_avg) / NULLIF((b.days_per_month * b.hours_per_day), (0)::numeric)), 2)) AS effective_hourly_rate,
    (e.hourly_rate_manual IS NOT NULL) AS hourly_is_manual,
    (e.daily_rate_manual IS NOT NULL) AS daily_is_manual
   FROM ((crm_employee_costs e
     CROSS JOIN basis b)
     LEFT JOIN allow a ON ((a.employee_cost_id = e.id)))
  WHERE (e.deleted_at IS NULL);

-- depth 0
create or replace view public.crm_expense_ledger_monthly with (security_invoker=true) as
 SELECT to_char((expense_date)::timestamp with time zone, 'YYYY-MM'::text) AS period,
    sum(amount) FILTER (WHERE is_direct) AS direct_total,
    sum(amount) FILTER (WHERE (NOT is_direct)) AS overhead_total,
    sum(amount) AS ledger_total,
    count(*) AS line_count
   FROM crm_expenses
  WHERE ((deleted_at IS NULL) AND (currency = 'PKR'::text))
  GROUP BY (to_char((expense_date)::timestamp with time zone, 'YYYY-MM'::text));

-- depth 0
create or replace view public.crm_fx_realised with (security_invoker=on) as
 SELECT a.id AS allocation_id,
    a.invoice_id,
    a.payment_id,
    a.amount,
    i.currency,
    i.exchange_rate AS invoice_rate,
    p.exchange_rate AS payment_rate,
        CASE
            WHEN ((i.currency <> 'PKR'::text) AND (i.exchange_rate IS NOT NULL) AND (p.exchange_rate IS NOT NULL)) THEN round((a.amount * (p.exchange_rate - i.exchange_rate)), 2)
            ELSE (0)::numeric
        END AS fx_gain_loss_pkr
   FROM ((crm_payment_allocations a
     JOIN crm_invoices i ON ((i.id = a.invoice_id)))
     JOIN crm_payments p ON (((p.id = a.payment_id) AND (p.deleted_at IS NULL))));

-- depth 0
create or replace view public.crm_labour_monthly with (security_invoker=true) as
 SELECT to_char((work_date)::timestamp with time zone, 'YYYY-MM'::text) AS period,
    sum(hours) AS hours,
    sum((hours * rate_snapshot)) AS direct_labour
   FROM crm_timesheets
  WHERE (((order_id IS NOT NULL) OR (project_id IS NOT NULL)) AND (COALESCE(rate_currency, 'PKR'::text) = 'PKR'::text))
  GROUP BY (to_char((work_date)::timestamp with time zone, 'YYYY-MM'::text));

-- depth 0
create or replace view public.crm_my_organization with (security_invoker=off) as
 SELECT id,
    legal_name,
    trading_name,
    industry,
    country,
    city,
    website,
    primary_email,
    phone,
    whatsapp,
    registered_address,
    billing_address,
    delivery_address,
    preferred_currency,
    status
   FROM crm_organizations
  WHERE ((id IN ( SELECT crm_my_org_ids() AS crm_my_org_ids)) AND (deleted_at IS NULL));

-- depth 0
create or replace view public.crm_my_timesheets as
 SELECT id,
    employee_cost_id,
    work_date,
    hours,
    order_id,
    project_id,
    description,
    is_billable,
    created_at
   FROM crm_timesheets
  WHERE ((entered_by = auth.uid()) OR (EXISTS ( SELECT 1
           FROM crm_employee_costs ec
          WHERE ((ec.id = crm_timesheets.employee_cost_id) AND (ec.user_id = auth.uid())))));

-- depth 0
create or replace view public.crm_order_direct_labour with (security_invoker=true) as
 SELECT order_id,
    sum(hours) AS hours,
    sum((hours * rate_snapshot)) AS direct_labour
   FROM crm_timesheets
  WHERE ((order_id IS NOT NULL) AND (COALESCE(rate_currency, 'PKR'::text) = 'PKR'::text))
  GROUP BY order_id;

-- depth 0
create or replace view public.crm_org_assignments with (security_invoker=true) as
 SELECT p.user_id,
    p.reporting_manager,
    p.department_id,
    d.name AS department,
    d.code AS department_code,
    p.job_role_id,
    j.title AS job_title,
    j.level AS org_level,
    j.is_management
   FROM ((crm_employee_profiles p
     LEFT JOIN crm_departments d ON ((d.id = p.department_id)))
     LEFT JOIN crm_job_roles j ON ((j.id = p.job_role_id)));

-- depth 0
create or replace view public.crm_org_credit_status with (security_invoker=on) as
 SELECT g.id AS organization_id,
    g.legal_name,
    g.credit_limit,
    COALESCE(sum(i.outstanding) FILTER (WHERE ((i.outstanding > (0)::numeric) AND (i.status = ANY (ARRAY['issued'::text, 'partially_paid'::text, 'overdue'::text])))), (0)::numeric) AS outstanding,
        CASE
            WHEN ((g.credit_limit IS NULL) OR (g.credit_limit <= (0)::numeric)) THEN false
            ELSE (COALESCE(sum(i.outstanding) FILTER (WHERE ((i.outstanding > (0)::numeric) AND (i.status = ANY (ARRAY['issued'::text, 'partially_paid'::text, 'overdue'::text])))), (0)::numeric) > g.credit_limit)
        END AS over_limit
   FROM (crm_organizations g
     LEFT JOIN crm_invoices i ON (((i.organization_id = g.id) AND (i.deleted_at IS NULL))))
  WHERE (g.deleted_at IS NULL)
  GROUP BY g.id, g.legal_name, g.credit_limit;

-- depth 0
create or replace view public.crm_overhead_lines with (security_invoker=true) as
 SELECT 'fixed_expense'::text AS source,
    f.id,
    f.name AS item,
    f.category,
    f.cost_centre_id,
    c.name AS cost_centre,
    f.currency,
    f.monthly_equivalent
   FROM (crm_fixed_expenses f
     LEFT JOIN crm_cost_centres c ON ((c.id = f.cost_centre_id)))
  WHERE ((f.deleted_at IS NULL) AND (f.status = 'active'::text) AND (f.frequency <> 'one_time'::text) AND (f.start_date <= CURRENT_DATE) AND ((f.end_date IS NULL) OR (f.end_date >= CURRENT_DATE)))
UNION ALL
 SELECT 'subscription'::text AS source,
    s.id,
    s.software_name AS item,
    'software_subscription'::text AS category,
    s.cost_centre_id,
    c.name AS cost_centre,
    s.currency,
    s.monthly_equivalent
   FROM (crm_subscriptions s
     LEFT JOIN crm_cost_centres c ON ((c.id = s.cost_centre_id)))
  WHERE ((s.deleted_at IS NULL) AND (s.status = 'active'::text));

-- depth 0
create or replace view public.crm_receivables_ageing with (security_invoker=on) as
 SELECT id AS invoice_id,
    invoice_number,
    organization_id,
    currency,
    issue_date,
    due_date,
    total,
    paid_amount,
    outstanding,
    status,
        CASE
            WHEN ((due_date IS NULL) OR (due_date >= CURRENT_DATE)) THEN 'current'::text
            WHEN (((CURRENT_DATE - due_date) >= 1) AND ((CURRENT_DATE - due_date) <= 30)) THEN '1_30'::text
            WHEN (((CURRENT_DATE - due_date) >= 31) AND ((CURRENT_DATE - due_date) <= 60)) THEN '31_60'::text
            WHEN (((CURRENT_DATE - due_date) >= 61) AND ((CURRENT_DATE - due_date) <= 90)) THEN '61_90'::text
            WHEN (((CURRENT_DATE - due_date) >= 91) AND ((CURRENT_DATE - due_date) <= 120)) THEN '91_120'::text
            ELSE 'over_120'::text
        END AS ageing_bucket,
    GREATEST((CURRENT_DATE - due_date), 0) AS days_overdue
   FROM crm_invoices i
  WHERE ((deleted_at IS NULL) AND (status = ANY (ARRAY['issued'::text, 'partially_paid'::text, 'overdue'::text])) AND (outstanding > (0)::numeric));

-- depth 0
create or replace view public.crm_receivables_payment_breakdown with (security_invoker=on) as
 SELECT i.id AS invoice_id,
    i.invoice_number,
    i.organization_id,
    i.currency,
    i.total AS invoice_total,
    i.paid_amount,
    i.outstanding,
    i.status AS invoice_status,
    pa.id AS allocation_id,
    p.id AS payment_id,
    p.payment_number,
    p.payment_date,
    pa.amount AS amount_received,
    p.payment_method,
    p.transaction_ref,
    p.is_verified,
    r.receipt_number,
    sum(pa.amount) OVER (PARTITION BY i.id ORDER BY p.payment_date, p.payment_number ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_paid,
    (i.total - sum(pa.amount) OVER (PARTITION BY i.id ORDER BY p.payment_date, p.payment_number ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)) AS running_balance
   FROM (((crm_invoices i
     JOIN crm_payment_allocations pa ON ((pa.invoice_id = i.id)))
     JOIN crm_payments p ON (((p.id = pa.payment_id) AND (p.deleted_at IS NULL))))
     LEFT JOIN crm_receipts r ON ((r.payment_id = p.id)))
  WHERE (i.deleted_at IS NULL)
  ORDER BY i.invoice_number, p.payment_date, p.payment_number;

-- depth 0
create or replace view public.crm_report_enquiries with (security_invoker=on) as
 SELECT e.service_id,
    s.name AS service_name,
    e.status,
    e.source,
    count(*) AS enquiries
   FROM (crm_enquiries e
     LEFT JOIN crm_services s ON ((s.id = e.service_id)))
  WHERE (e.deleted_at IS NULL)
  GROUP BY e.service_id, s.name, e.status, e.source;

-- depth 0
create or replace view public.crm_report_lead_sources with (security_invoker=on) as
 SELECT COALESCE(lead_source, 'unknown'::text) AS lead_source,
    count(*) AS prospects,
    count(*) FILTER (WHERE (stage = 'won'::text)) AS won,
    count(*) FILTER (WHERE (stage = ANY (ARRAY['lost'::text, 'disqualified'::text]))) AS lost,
        CASE
            WHEN (count(*) > 0) THEN round((((count(*) FILTER (WHERE (stage = 'won'::text)))::numeric / (count(*))::numeric) * (100)::numeric), 1)
            ELSE NULL::numeric
        END AS win_rate_pct
   FROM crm_prospects p
  WHERE (deleted_at IS NULL)
  GROUP BY COALESCE(lead_source, 'unknown'::text);

-- depth 0
create or replace view public.crm_report_opportunity_pipeline with (security_invoker=on) as
 SELECT stage,
    count(*) AS opportunities,
    COALESCE(sum(estimated_value), (0)::numeric) AS estimated_value,
    COALESCE(sum(weighted_value), (0)::numeric) AS weighted_value
   FROM crm_opportunities
  WHERE (deleted_at IS NULL)
  GROUP BY stage;

-- depth 0
create or replace view public.crm_report_pipeline with (security_invoker=on) as
 SELECT stage,
    count(*) AS prospects,
    COALESCE(sum(expected_budget), (0)::numeric) AS expected_budget,
    round(COALESCE(sum(((expected_budget * COALESCE(((( SELECT crm_settings.value
           FROM crm_settings
          WHERE (crm_settings.key = 'pipeline_probabilities'::text)) ->> stage))::numeric, (10)::numeric)) / 100.0)), (0)::numeric), 2) AS weighted_budget
   FROM crm_prospects p
  WHERE (deleted_at IS NULL)
  GROUP BY stage;

-- depth 0
create or replace view public.crm_report_quotation_stats with (security_invoker=on) as
 SELECT status,
    count(*) AS quotations,
    COALESCE(sum(total), (0)::numeric) AS total_value
   FROM crm_quotations q
  WHERE (deleted_at IS NULL)
  GROUP BY status;

-- depth 0
create or replace view public.crm_report_unrealised with (security_invoker=on) as
 SELECT id,
    quotation_number,
    version,
    organization_id,
    service_id,
    title,
    currency,
    total,
    expiry_date,
    status,
        CASE status
            WHEN 'issued'::text THEN 50
            WHEN 'viewed'::text THEN 55
            WHEN 'revision_requested'::text THEN 60
            WHEN 'pending_approval'::text THEN 30
            WHEN 'approved'::text THEN 40
            ELSE 20
        END AS probability_pct,
    round(((total * (
        CASE status
            WHEN 'issued'::text THEN 50
            WHEN 'viewed'::text THEN 55
            WHEN 'revision_requested'::text THEN 60
            WHEN 'pending_approval'::text THEN 30
            WHEN 'approved'::text THEN 40
            ELSE 20
        END)::numeric) / 100.0), 2) AS weighted_value
   FROM crm_quotations q
  WHERE ((deleted_at IS NULL) AND (status = ANY (ARRAY['draft'::text, 'costing_review'::text, 'pending_approval'::text, 'approved'::text, 'issued'::text, 'viewed'::text, 'revision_requested'::text, 'revised'::text])));

-- depth 0
create or replace view public.crm_service_offer_comparison with (security_invoker=true) as
 SELECT o.category_code,
    c.name AS category,
    b.name AS branch,
    p.legal_name AS provider,
    p.rating,
    p.risk_class,
    p.is_preferred AS preferred_provider,
    p.lead_time_days,
    p.city,
    p.country,
    o.offer_number,
    o.title,
    bb.name AS billing_basis,
    o.rate,
    o.currency,
    o.estimated_qty,
    o.resources,
    o.final_amount,
    o.valid_until,
    o.status,
    rank() OVER (PARTITION BY o.category_code ORDER BY o.final_amount) AS price_rank
   FROM ((((crm_service_offers o
     JOIN crm_service_providers p ON ((p.id = o.provider_id)))
     JOIN crm_outsourced_categories c ON ((c.code = o.category_code)))
     JOIN crm_service_branches b ON ((b.code = c.branch_code)))
     LEFT JOIN crm_billing_bases bb ON ((bb.code = o.billing_basis)))
  WHERE ((o.deleted_at IS NULL) AND (p.deleted_at IS NULL) AND (o.status = ANY (ARRAY['received'::text, 'under_review'::text, 'approved'::text])));

-- depth 0
create or replace view public.crm_service_offers_selectable with (security_invoker=true) as
 SELECT o.id,
    o.offer_number,
    o.title,
    o.billing_basis,
    o.rate,
    o.currency,
    o.estimated_qty,
    o.resources,
    o.final_amount,
    o.valid_until,
    o.category_code,
    o.branch_code,
    o.is_preferred,
    p.id AS provider_id,
    p.legal_name AS provider,
    p.rating,
    p.risk_class,
    p.is_preferred AS provider_preferred
   FROM (crm_service_offers o
     JOIN crm_service_providers p ON ((p.id = o.provider_id)))
  WHERE ((o.deleted_at IS NULL) AND (p.deleted_at IS NULL) AND (o.status = 'approved'::text) AND (p.is_blacklisted = false) AND (p.status = 'active'::text) AND ((o.valid_until IS NULL) OR (o.valid_until >= CURRENT_DATE)));

-- depth 0
create or replace view public.crm_upcoming_renewals with (security_invoker=true) as
 SELECT id,
    subscription_number,
    software_name,
    vendor_name,
    plan_name,
    billing_cycle,
    cost,
    currency,
    renewal_date,
    auto_renewal,
    status,
    (renewal_date - CURRENT_DATE) AS days_to_renewal
   FROM crm_subscriptions
  WHERE ((deleted_at IS NULL) AND (status = 'active'::text) AND (renewal_date IS NOT NULL) AND (renewal_date <= (CURRENT_DATE + 45)));

-- depth 0
create or replace view public.pharma_allocated_costs with (security_invoker=true) as
 SELECT d.id,
    d.crm_expense_id,
    e.expense_number,
    e.expense_date,
    e.currency,
    e.category AS ledger_category,
    cl.name AS cost_line,
    cl.line_kind,
    d.pl_layer,
    d.allocation_pct,
    round(((e.amount * d.allocation_pct) / (100)::numeric), 2) AS allocated_amount,
    e.amount AS full_expense_amount,
    d.product_id,
    d.principal_org,
    d.plant_id,
    d.campaign_id,
    d.territory_id,
    d.distributor_id,
    d.hospital_id,
    d.pharmacy_id,
    d.doctor_id,
    d.tender_id,
    d.contract_id,
    d.sales_order_id,
    (date_trunc('month'::text, (e.expense_date)::timestamp with time zone))::date AS period
   FROM ((pharma_expense_dimensions d
     JOIN crm_expenses e ON (((e.id = d.crm_expense_id) AND (e.deleted_at IS NULL))))
     LEFT JOIN crm_cost_lines cl ON ((cl.id = e.cost_line_id)));

-- depth 0
create or replace view public.pharma_campaign_performance with (security_invoker=true) as
 SELECT c.id,
    c.campaign_code,
    c.name,
    c.campaign_type,
    c.status,
    c.start_date,
    c.end_date,
    c.budget,
    c.actual_cost,
    c.actual_revenue,
    p.brand_name AS product,
        CASE
            WHEN (COALESCE(c.budget, (0)::numeric) > (0)::numeric) THEN round(((c.actual_cost / c.budget) * (100)::numeric), 2)
            ELSE NULL::numeric
        END AS budget_used_pct,
        CASE
            WHEN (COALESCE(c.actual_cost, (0)::numeric) > (0)::numeric) THEN round((((c.actual_revenue - c.actual_cost) / c.actual_cost) * (100)::numeric), 2)
            ELSE NULL::numeric
        END AS romi_pct,
    ( SELECT count(*) AS count
           FROM pharma_visits v
          WHERE (v.campaign_id = c.id)) AS visits_logged,
    ( SELECT count(DISTINCT v.doctor_id) AS count
           FROM pharma_visits v
          WHERE ((v.campaign_id = c.id) AND (v.doctor_id IS NOT NULL))) AS doctors_reached
   FROM (pharma_campaigns c
     LEFT JOIN pharma_products p ON ((p.id = c.product_id)))
  WHERE (c.deleted_at IS NULL);

-- depth 0
create or replace view public.pharma_doctor_spend_status with (security_invoker=true) as
 SELECT d.id,
    d.full_name,
    d.specialty,
    d.category,
    d.annual_spend_cap,
    COALESCE(s.spent_this_year, (0)::numeric) AS spent_this_year,
        CASE
            WHEN (d.annual_spend_cap IS NOT NULL) THEN (d.annual_spend_cap - COALESCE(s.spent_this_year, (0)::numeric))
            ELSE NULL::numeric
        END AS remaining,
        CASE
            WHEN (COALESCE(d.annual_spend_cap, (0)::numeric) > (0)::numeric) THEN round(((COALESCE(s.spent_this_year, (0)::numeric) / d.annual_spend_cap) * (100)::numeric), 1)
            ELSE NULL::numeric
        END AS used_pct,
        CASE
            WHEN (d.annual_spend_cap IS NULL) THEN 'no cap set'::text
            WHEN (COALESCE(s.spent_this_year, (0)::numeric) >= d.annual_spend_cap) THEN 'cap reached'::text
            WHEN (COALESCE(s.spent_this_year, (0)::numeric) >= (d.annual_spend_cap * 0.8)) THEN 'approaching cap'::text
            ELSE 'within cap'::text
        END AS cap_status
   FROM (pharma_doctors d
     LEFT JOIN ( SELECT pharma_engagement_spend.doctor_id,
            sum(pharma_engagement_spend.amount) AS spent_this_year
           FROM pharma_engagement_spend
          WHERE (date_trunc('year'::text, (pharma_engagement_spend.spend_date)::timestamp with time zone) = date_trunc('year'::text, (CURRENT_DATE)::timestamp with time zone))
          GROUP BY pharma_engagement_spend.doctor_id) s ON ((s.doctor_id = d.id)))
  WHERE (d.deleted_at IS NULL);

-- depth 0
create or replace view public.pharma_field_activity with (security_invoker=true) as
 SELECT visited_by AS user_id,
    (date_trunc('month'::text, visited_at))::date AS month,
    count(*) FILTER (WHERE (status = 'completed'::text)) AS visits_completed,
    count(*) FILTER (WHERE (status = 'missed'::text)) AS visits_missed,
    count(DISTINCT doctor_id) FILTER (WHERE (doctor_id IS NOT NULL)) AS doctors_seen,
    count(DISTINCT pharmacy_id) FILTER (WHERE (pharmacy_id IS NOT NULL)) AS pharmacies_seen,
    count(DISTINCT hospital_id) FILTER (WHERE (hospital_id IS NOT NULL)) AS hospitals_seen,
    count(*) FILTER (WHERE (outcome = 'committed'::text)) AS commitments,
    COALESCE(sum(estimated_potential), (0)::numeric) AS potential_logged
   FROM pharma_visits v
  GROUP BY visited_by, ((date_trunc('month'::text, visited_at))::date);

-- depth 0
create or replace view public.pharma_network_counts with (security_invoker=true) as
 SELECT ( SELECT count(*) AS count
           FROM pharma_companies) AS companies,
    ( SELECT count(*) AS count
           FROM pharma_plants
          WHERE (pharma_plants.deleted_at IS NULL)) AS plants,
    ( SELECT count(*) AS count
           FROM pharma_products
          WHERE (pharma_products.deleted_at IS NULL)) AS products,
    ( SELECT count(*) AS count
           FROM pharma_products
          WHERE ((pharma_products.deleted_at IS NULL) AND (pharma_products.status = 'active'::text))) AS active_products,
    ( SELECT count(*) AS count
           FROM pharma_products
          WHERE ((pharma_products.deleted_at IS NULL) AND (pharma_products.status = 'registered'::text))) AS registered_products,
    ( SELECT count(*) AS count
           FROM pharma_products
          WHERE ((pharma_products.deleted_at IS NULL) AND (pharma_products.status = 'under_registration'::text))) AS under_registration,
    ( SELECT count(*) AS count
           FROM pharma_doctors
          WHERE (pharma_doctors.deleted_at IS NULL)) AS doctors,
    ( SELECT count(*) AS count
           FROM pharma_doctors
          WHERE ((pharma_doctors.deleted_at IS NULL) AND (pharma_doctors.consent_status = 'obtained'::text))) AS consented_doctors,
    ( SELECT count(*) AS count
           FROM pharma_doctors
          WHERE ((pharma_doctors.deleted_at IS NULL) AND pharma_doctors.do_not_contact)) AS do_not_contact_doctors,
    ( SELECT count(*) AS count
           FROM pharma_hospitals
          WHERE (pharma_hospitals.deleted_at IS NULL)) AS hospitals,
    ( SELECT count(*) AS count
           FROM pharma_pharmacies
          WHERE (pharma_pharmacies.deleted_at IS NULL)) AS pharmacies,
    ( SELECT count(*) AS count
           FROM pharma_distributors
          WHERE (pharma_distributors.deleted_at IS NULL)) AS distributors,
    ( SELECT count(*) AS count
           FROM pharma_territories
          WHERE pharma_territories.is_active) AS territories,
    ( SELECT count(*) AS count
           FROM pharma_field_force
          WHERE pharma_field_force.is_active) AS field_force;

-- depth 0
create or replace view public.pharma_order_totals with (security_invoker=true) as
 SELECT o.id AS order_id,
    o.order_number,
    o.sale_type,
    o.status,
    o.order_date,
    o.currency,
    d.name AS distributor,
    ph.name AS pharmacy,
    h.legal_name AS hospital,
    (COALESCE(sum(i.line_net), (0)::numeric) + COALESCE(o.freight, (0)::numeric)) AS invoice_value,
    COALESCE(sum(i.line_cogs), (0)::numeric) AS cogs,
    COALESCE(sum(i.line_gross_profit), (0)::numeric) AS gross_profit,
        CASE
            WHEN (COALESCE(sum(i.line_net), (0)::numeric) > (0)::numeric) THEN round(((COALESCE(sum(i.line_gross_profit), (0)::numeric) / sum(i.line_net)) * (100)::numeric), 2)
            ELSE NULL::numeric
        END AS gross_margin_pct,
    COALESCE(sum((i.free_quantity * COALESCE(i.unit_cost, (0)::numeric))), (0)::numeric) AS free_goods_cost,
    count(i.*) AS line_count
   FROM ((((pharma_sales_orders o
     LEFT JOIN pharma_sales_order_items i ON ((i.order_id = o.id)))
     LEFT JOIN pharma_distributors d ON ((d.id = o.distributor_id)))
     LEFT JOIN pharma_pharmacies ph ON ((ph.id = o.pharmacy_id)))
     LEFT JOIN pharma_hospitals h ON ((h.id = o.hospital_id)))
  WHERE (o.deleted_at IS NULL)
  GROUP BY o.id, o.order_number, o.sale_type, o.status, o.order_date, o.currency, d.name, ph.name, h.legal_name, o.freight;

-- depth 0
create or replace view public.pharma_receivables_ageing with (security_invoker=true) as
 SELECT i.id AS invoice_id,
    i.invoice_number,
    i.invoice_date,
    i.due_date,
    i.currency,
    i.distributor_id,
    COALESCE(d.name, ph.name, h.legal_name) AS customer,
        CASE
            WHEN (i.distributor_id IS NOT NULL) THEN 'distributor'::text
            WHEN (i.pharmacy_id IS NOT NULL) THEN 'pharmacy'::text
            WHEN (i.hospital_id IS NOT NULL) THEN 'hospital'::text
            ELSE 'other'::text
        END AS customer_type,
    i.invoice_value,
    COALESCE(r.received, (0)::numeric) AS received,
    (i.invoice_value - COALESCE(r.received, (0)::numeric)) AS outstanding,
    GREATEST((CURRENT_DATE - i.due_date), 0) AS days_overdue,
        CASE
            WHEN ((i.invoice_value - COALESCE(r.received, (0)::numeric)) <= (0)::numeric) THEN 'settled'::text
            WHEN (CURRENT_DATE <= i.due_date) THEN 'current'::text
            WHEN ((CURRENT_DATE - i.due_date) <= 30) THEN '1-30 days'::text
            WHEN ((CURRENT_DATE - i.due_date) <= 60) THEN '31-60 days'::text
            WHEN ((CURRENT_DATE - i.due_date) <= 90) THEN '61-90 days'::text
            WHEN ((CURRENT_DATE - i.due_date) <= 120) THEN '91-120 days'::text
            ELSE 'over 120 days'::text
        END AS ageing_bucket,
    i.status,
    i.collector,
    i.next_followup
   FROM ((((pharma_invoices i
     LEFT JOIN ( SELECT pharma_receipts.invoice_id,
            sum(pharma_receipts.amount) AS received
           FROM pharma_receipts
          GROUP BY pharma_receipts.invoice_id) r ON ((r.invoice_id = i.id)))
     LEFT JOIN pharma_distributors d ON ((d.id = i.distributor_id)))
     LEFT JOIN pharma_pharmacies ph ON ((ph.id = i.pharmacy_id)))
     LEFT JOIN pharma_hospitals h ON ((h.id = i.hospital_id)))
  WHERE (i.status <> ALL (ARRAY['cancelled'::text, 'draft'::text]));

-- depth 0
create or replace view public.pharma_revenue_lines with (security_invoker=true) as
 SELECT i.id AS item_id,
    o.id AS order_id,
    o.order_number,
    o.order_date,
    (date_trunc('month'::text, (o.order_date)::timestamp with time zone))::date AS period,
    o.sale_type,
    o.currency,
    o.territory_id,
    o.distributor_id,
    o.hospital_id,
    o.pharmacy_id,
    o.sales_rep,
    o.offer_id,
    i.product_id,
    p.brand_name,
    p.therapeutic_category,
    p.product_class,
    p.principal_org,
    p.manufacturer_plant,
    i.quantity,
    i.free_quantity,
    i.list_price,
    i.discount_pct,
    i.line_net AS revenue,
    i.line_cogs AS cogs,
    i.line_gross_profit AS gross_profit,
    round((((i.quantity * i.list_price) * COALESCE(i.discount_pct, (0)::numeric)) / (100)::numeric), 2) AS discount_given,
    round((COALESCE(i.free_quantity, (0)::numeric) * COALESCE(i.unit_cost, (0)::numeric)), 2) AS free_goods_cost
   FROM ((pharma_sales_order_items i
     JOIN pharma_sales_orders o ON ((o.id = i.order_id)))
     LEFT JOIN pharma_products p ON ((p.id = i.product_id)))
  WHERE ((o.deleted_at IS NULL) AND (o.status = ANY (ARRAY['confirmed'::text, 'picked'::text, 'dispatched'::text, 'delivered'::text, 'invoiced'::text])));

-- depth 0
create or replace view public.pharma_sample_balances with (security_invoker=true) as
 SELECT i.id AS item_id,
    i.item_code,
    i.name,
    i.item_type,
    i.batch_number,
    i.expiry_date,
    p.brand_name AS product,
    COALESCE(sum(
        CASE
            WHEN (t.txn_type = 'receive'::text) THEN t.quantity
            ELSE (0)::numeric
        END), (0)::numeric) AS received,
    COALESCE(sum(
        CASE
            WHEN (t.txn_type ~~ 'issue%'::text) THEN t.quantity
            ELSE (0)::numeric
        END), (0)::numeric) AS issued,
    COALESCE(sum(
        CASE
            WHEN (t.txn_type = 'return'::text) THEN t.quantity
            ELSE (0)::numeric
        END), (0)::numeric) AS returned,
    COALESCE(sum(
        CASE
            WHEN (t.txn_type = ANY (ARRAY['damage'::text, 'expire'::text])) THEN t.quantity
            ELSE (0)::numeric
        END), (0)::numeric) AS written_off,
    COALESCE(sum(
        CASE
            WHEN (t.txn_type = 'receive'::text) THEN t.quantity
            WHEN (t.txn_type = 'return'::text) THEN t.quantity
            WHEN (t.txn_type ~~ 'issue%'::text) THEN (- t.quantity)
            WHEN (t.txn_type = ANY (ARRAY['damage'::text, 'expire'::text])) THEN (- t.quantity)
            WHEN (t.txn_type = 'adjust'::text) THEN t.quantity
            ELSE (0)::numeric
        END), (0)::numeric) AS balance,
        CASE
            WHEN (i.expiry_date IS NULL) THEN 'no expiry'::text
            WHEN (i.expiry_date < CURRENT_DATE) THEN 'expired'::text
            WHEN (i.expiry_date < (CURRENT_DATE + 90)) THEN 'near expiry'::text
            ELSE 'ok'::text
        END AS expiry_status
   FROM ((pharma_sample_items i
     LEFT JOIN pharma_sample_transactions t ON ((t.item_id = i.id)))
     LEFT JOIN pharma_products p ON ((p.id = i.product_id)))
  GROUP BY i.id, i.item_code, i.name, i.item_type, i.batch_number, i.expiry_date, p.brand_name;

-- depth 0
create or replace view public.pharma_stock_positions with (security_invoker=true) as
 SELECT b.id AS batch_id,
    b.product_id,
    p.brand_name,
    p.sku,
    b.batch_number,
    b.warehouse_id,
    w.name AS warehouse,
    b.mfg_date,
    b.expiry_date,
    b.quality_status,
    b.unit_cost,
    b.currency,
    COALESCE(sum(m.quantity), (0)::numeric) AS on_hand,
    (COALESCE(sum(m.quantity), (0)::numeric) * COALESCE(b.unit_cost, (0)::numeric)) AS stock_value,
    (b.expiry_date - CURRENT_DATE) AS days_to_expiry,
        CASE
            WHEN (b.quality_status = 'recalled'::text) THEN 'recalled'::text
            WHEN (b.quality_status <> 'released'::text) THEN b.quality_status
            WHEN (b.expiry_date < CURRENT_DATE) THEN 'expired'::text
            WHEN (b.expiry_date < (CURRENT_DATE + 90)) THEN 'near expiry'::text
            WHEN (b.expiry_date < (CURRENT_DATE + 180)) THEN 'watch'::text
            ELSE 'ok'::text
        END AS stock_status,
    ((b.quality_status = 'released'::text) AND (b.expiry_date >= CURRENT_DATE)) AS is_sellable
   FROM (((pharma_inventory_batches b
     LEFT JOIN pharma_inventory_movements m ON ((m.batch_id = b.id)))
     LEFT JOIN pharma_products p ON ((p.id = b.product_id)))
     LEFT JOIN pharma_warehouses w ON ((w.id = b.warehouse_id)))
  GROUP BY b.id, b.product_id, p.brand_name, p.sku, b.batch_number, b.warehouse_id, w.name, b.mfg_date, b.expiry_date, b.quality_status, b.unit_cost, b.currency;

-- depth 0
create or replace view public.pharma_toll_comparison with (security_invoker=true) as
 SELECT o.enquiry_id,
    e.product_concept,
    e.annual_qty,
    e.target_price,
    p.name AS plant,
    p.city,
    p.gmp_status,
    p.quality_rating,
    p.risk_rating,
    p.min_batch_size AS plant_min_batch,
    o.id AS offer_id,
    o.offer_code,
    o.plant_cost_total,
    o.jco_earning,
    o.client_price,
    o.currency,
    o.lead_time_days,
    o.validity_date,
    o.status,
        CASE
            WHEN ((COALESCE(e.target_price, (0)::numeric) > (0)::numeric) AND (o.client_price IS NOT NULL)) THEN round((((o.client_price - e.target_price) / e.target_price) * (100)::numeric), 2)
            ELSE NULL::numeric
        END AS vs_target_pct,
    rank() OVER (PARTITION BY o.enquiry_id ORDER BY o.client_price) AS price_rank
   FROM ((pharma_toll_offers o
     JOIN pharma_toll_enquiries e ON ((e.id = o.enquiry_id)))
     JOIN pharma_plants p ON ((p.id = o.plant_id)))
  WHERE ((e.deleted_at IS NULL) AND (o.status <> 'rejected'::text));

-- depth 0
create or replace view public.pharma_unallocated_expenses with (security_invoker=true) as
 SELECT e.id,
    e.expense_number,
    e.expense_date,
    e.category,
    e.amount,
    e.currency,
    e.description,
    COALESCE(sum(d.allocation_pct), (0)::numeric) AS allocated_pct,
    ((100)::numeric - COALESCE(sum(d.allocation_pct), (0)::numeric)) AS unallocated_pct,
    round(((e.amount * ((100)::numeric - COALESCE(sum(d.allocation_pct), (0)::numeric))) / (100)::numeric), 2) AS unallocated_amount
   FROM (crm_expenses e
     LEFT JOIN pharma_expense_dimensions d ON ((d.crm_expense_id = e.id)))
  WHERE (e.deleted_at IS NULL)
  GROUP BY e.id, e.expense_number, e.expense_date, e.category, e.amount, e.currency, e.description
 HAVING (COALESCE(sum(d.allocation_pct), (0)::numeric) < (100)::numeric);

-- depth 1
create or replace view public.crm_cc_ageing with (security_invoker=on) as
 SELECT ageing_bucket,
    sum(outstanding) AS outstanding,
    count(*) AS invoices
   FROM crm_receivables_ageing
  GROUP BY ageing_bucket;

-- depth 1
create or replace view public.crm_monthly_employee_cost with (security_invoker=true) as
 SELECT COALESCE(c.name, 'Unassigned'::text) AS cost_centre,
    r.currency,
    count(*) AS employee_count,
    sum(r.total_monthly_cost) AS monthly_total
   FROM (crm_employee_cost_rates r
     LEFT JOIN crm_cost_centres c ON ((c.id = r.cost_centre_id)))
  WHERE (r.status = 'active'::text)
  GROUP BY COALESCE(c.name, 'Unassigned'::text), r.currency;

-- depth 1
create or replace view public.crm_monthly_overhead_actual with (security_invoker=true) as
 SELECT COALESCE(cost_centre, 'Unassigned'::text) AS cost_centre,
    currency,
    sum(monthly_equivalent) AS monthly_total,
    count(*) AS line_count
   FROM crm_overhead_lines
  GROUP BY COALESCE(cost_centre, 'Unassigned'::text), currency;

-- depth 1
create or replace view public.crm_order_ebitda with (security_invoker=on) as
 SELECT o.id AS order_id,
    o.order_number,
    o.organization_id,
    o.service_id,
    o.currency,
    o.status,
    o.order_date,
    o.order_value AS revenue,
    COALESCE(o.landed_cost, t.est_total_with_contingency, (0)::numeric) AS cogs,
    COALESCE(e.direct_expenses, (0)::numeric) AS direct_expenses,
    round(((o.order_value * COALESCE(( SELECT ((crm_settings.value #>> '{}'::text[]))::numeric AS "numeric"
           FROM crm_settings
          WHERE (crm_settings.key = 'ebitda_overhead_allocation_pct'::text)), (8)::numeric)) / 100.0), 2) AS allocated_overhead,
    round((((o.order_value - COALESCE(o.landed_cost, t.est_total_with_contingency, (0)::numeric)) - COALESCE(e.direct_expenses, (0)::numeric)) - round(((o.order_value * COALESCE(( SELECT ((crm_settings.value #>> '{}'::text[]))::numeric AS "numeric"
           FROM crm_settings
          WHERE (crm_settings.key = 'ebitda_overhead_allocation_pct'::text)), (8)::numeric)) / 100.0), 2)), 2) AS ebitda_contribution,
        CASE
            WHEN (o.order_value > (0)::numeric) THEN round((((((o.order_value - COALESCE(o.landed_cost, t.est_total_with_contingency, (0)::numeric)) - COALESCE(e.direct_expenses, (0)::numeric)) - round(((o.order_value * COALESCE(( SELECT ((crm_settings.value #>> '{}'::text[]))::numeric AS "numeric"
               FROM crm_settings
              WHERE (crm_settings.key = 'ebitda_overhead_allocation_pct'::text)), (8)::numeric)) / 100.0), 2)) / o.order_value) * (100)::numeric), 2)
            ELSE NULL::numeric
        END AS ebitda_margin_pct
   FROM ((crm_orders o
     LEFT JOIN crm_cost_sheet_totals t ON ((t.cost_sheet_id = o.cost_sheet_id)))
     LEFT JOIN ( SELECT crm_expenses.order_id,
            sum(crm_expenses.amount) AS direct_expenses
           FROM crm_expenses
          WHERE ((crm_expenses.deleted_at IS NULL) AND crm_expenses.is_direct)
          GROUP BY crm_expenses.order_id) e ON ((e.order_id = o.id)))
  WHERE ((o.deleted_at IS NULL) AND (o.status <> ALL (ARRAY['draft'::text, 'cancelled'::text])));

-- depth 1
create or replace view public.crm_order_profitability with (security_invoker=on) as
 SELECT o.id AS order_id,
    o.order_number,
    o.organization_id,
    o.service_id,
    o.currency,
    o.order_value,
    COALESCE(o.landed_cost, t.est_total_with_contingency) AS cost_basis,
    round((o.order_value - COALESCE(o.landed_cost, t.est_total_with_contingency, (0)::numeric)), 2) AS gross_profit,
        CASE
            WHEN (o.order_value > (0)::numeric) THEN round((((o.order_value - COALESCE(o.landed_cost, t.est_total_with_contingency, (0)::numeric)) / o.order_value) * (100)::numeric), 2)
            ELSE NULL::numeric
        END AS gross_margin_pct
   FROM (crm_orders o
     LEFT JOIN crm_cost_sheet_totals t ON ((t.cost_sheet_id = o.cost_sheet_id)))
  WHERE (o.deleted_at IS NULL);

-- depth 1
create or replace view public.pharma_campaign_roi with (security_invoker=true) as
 SELECT c.id AS campaign_id,
    c.campaign_code,
    c.name,
    c.campaign_type,
    c.status,
    c.start_date,
    c.end_date,
    c.budget,
    COALESCE(sp.spend, (0)::numeric) AS actual_cost,
    COALESCE(rv.revenue, (0)::numeric) AS attributed_revenue,
    COALESCE(rv.gross_profit, (0)::numeric) AS attributed_gross_profit,
    (COALESCE(rv.gross_profit, (0)::numeric) - COALESCE(sp.spend, (0)::numeric)) AS net_contribution,
        CASE
            WHEN (COALESCE(sp.spend, (0)::numeric) > (0)::numeric) THEN round((((COALESCE(rv.gross_profit, (0)::numeric) - sp.spend) / sp.spend) * (100)::numeric), 2)
            ELSE NULL::numeric
        END AS roi_pct,
        CASE
            WHEN (COALESCE(c.budget, (0)::numeric) > (0)::numeric) THEN round(((COALESCE(sp.spend, (0)::numeric) / c.budget) * (100)::numeric), 1)
            ELSE NULL::numeric
        END AS budget_used_pct,
    ( SELECT count(*) AS count
           FROM pharma_visits v
          WHERE (v.campaign_id = c.id)) AS visits,
    ( SELECT count(DISTINCT v.doctor_id) AS count
           FROM pharma_visits v
          WHERE ((v.campaign_id = c.id) AND (v.doctor_id IS NOT NULL))) AS doctors_reached,
        CASE
            WHEN (( SELECT count(DISTINCT v.doctor_id) AS count
               FROM pharma_visits v
              WHERE ((v.campaign_id = c.id) AND (v.doctor_id IS NOT NULL))) > 0) THEN round((COALESCE(sp.spend, (0)::numeric) / (( SELECT count(DISTINCT v.doctor_id) AS count
               FROM pharma_visits v
              WHERE ((v.campaign_id = c.id) AND (v.doctor_id IS NOT NULL))))::numeric), 2)
            ELSE NULL::numeric
        END AS cost_per_doctor
   FROM ((pharma_campaigns c
     LEFT JOIN ( SELECT pharma_allocated_costs.campaign_id,
            sum(pharma_allocated_costs.allocated_amount) AS spend
           FROM pharma_allocated_costs
          WHERE (pharma_allocated_costs.campaign_id IS NOT NULL)
          GROUP BY pharma_allocated_costs.campaign_id) sp ON ((sp.campaign_id = c.id)))
     LEFT JOIN LATERAL ( SELECT sum(r.revenue) AS revenue,
            sum(r.gross_profit) AS gross_profit
           FROM pharma_revenue_lines r
          WHERE ((r.order_date >= c.start_date) AND (r.order_date <= c.end_date) AND ((c.product_id IS NULL) OR (r.product_id = c.product_id)) AND ((c.territory_id IS NULL) OR (r.territory_id = c.territory_id)))) rv ON (true))
  WHERE (c.deleted_at IS NULL);

-- depth 1
create or replace view public.pharma_credit_exposure with (security_invoker=true) as
 SELECT d.id AS distributor_id,
    d.name,
    d.credit_limit,
    COALESCE(sum(a.outstanding), (0)::numeric) AS outstanding,
        CASE
            WHEN (COALESCE(d.credit_limit, (0)::numeric) > (0)::numeric) THEN round(((COALESCE(sum(a.outstanding), (0)::numeric) / d.credit_limit) * (100)::numeric), 1)
            ELSE NULL::numeric
        END AS utilisation_pct,
        CASE
            WHEN (d.credit_limit IS NULL) THEN 'no limit set'::text
            WHEN (COALESCE(sum(a.outstanding), (0)::numeric) > d.credit_limit) THEN 'OVER LIMIT'::text
            WHEN (COALESCE(sum(a.outstanding), (0)::numeric) > (d.credit_limit * 0.9)) THEN 'near limit'::text
            ELSE 'within limit'::text
        END AS credit_status,
    count(a.*) FILTER (WHERE (a.days_overdue > 0)) AS overdue_invoices,
    COALESCE(max(a.days_overdue), 0) AS worst_overdue_days
   FROM (pharma_distributors d
     LEFT JOIN pharma_receivables_ageing a ON ((a.distributor_id = d.id)))
  WHERE (d.deleted_at IS NULL)
  GROUP BY d.id, d.name, d.credit_limit;

-- depth 1
create or replace view public.pharma_product_pl with (security_invoker=true) as
 WITH rev AS (
         SELECT pharma_revenue_lines.product_id,
            sum(pharma_revenue_lines.revenue) AS revenue,
            sum(pharma_revenue_lines.cogs) AS cogs,
            sum(pharma_revenue_lines.gross_profit) AS gross_profit,
            sum(pharma_revenue_lines.quantity) AS units,
            sum(pharma_revenue_lines.free_goods_cost) AS free_goods_cost,
            sum(pharma_revenue_lines.discount_given) AS discounts
           FROM pharma_revenue_lines
          GROUP BY pharma_revenue_lines.product_id
        ), cost AS (
         SELECT pharma_allocated_costs.product_id,
            sum(pharma_allocated_costs.allocated_amount) FILTER (WHERE (pharma_allocated_costs.pl_layer = ANY (ARRAY['direct_selling'::text, 'distribution'::text, 'promotion'::text, 'regulatory'::text]))) AS direct_costs,
            sum(pharma_allocated_costs.allocated_amount) FILTER (WHERE (pharma_allocated_costs.pl_layer = 'promotion'::text)) AS promotion_cost,
            sum(pharma_allocated_costs.allocated_amount) FILTER (WHERE (pharma_allocated_costs.pl_layer = 'admin_overhead'::text)) AS overhead,
            sum(pharma_allocated_costs.allocated_amount) FILTER (WHERE (pharma_allocated_costs.pl_layer = ANY (ARRAY['depreciation'::text, 'amortisation'::text]))) AS dna
           FROM pharma_allocated_costs
          WHERE (pharma_allocated_costs.product_id IS NOT NULL)
          GROUP BY pharma_allocated_costs.product_id
        )
 SELECT p.id AS product_id,
    p.brand_name,
    p.generic_name,
    p.therapeutic_category,
    p.product_class,
    p.status,
    COALESCE(r.units, (0)::numeric) AS units_sold,
    COALESCE(r.revenue, (0)::numeric) AS revenue,
    COALESCE(r.cogs, (0)::numeric) AS cogs,
    COALESCE(r.gross_profit, (0)::numeric) AS gross_profit,
        CASE
            WHEN (COALESCE(r.revenue, (0)::numeric) > (0)::numeric) THEN round(((r.gross_profit / r.revenue) * (100)::numeric), 2)
            ELSE NULL::numeric
        END AS gross_margin_pct,
    COALESCE(r.free_goods_cost, (0)::numeric) AS free_goods_cost,
    COALESCE(r.discounts, (0)::numeric) AS discounts_given,
    COALESCE(c.direct_costs, (0)::numeric) AS direct_costs,
    (COALESCE(r.gross_profit, (0)::numeric) - COALESCE(c.direct_costs, (0)::numeric)) AS contribution_margin,
    COALESCE(c.overhead, (0)::numeric) AS allocated_overhead,
    (((COALESCE(r.gross_profit, (0)::numeric) - COALESCE(c.direct_costs, (0)::numeric)) - COALESCE(c.overhead, (0)::numeric)) + COALESCE(c.dna, (0)::numeric)) AS ebitda_contribution,
        CASE
            WHEN (COALESCE(r.revenue, (0)::numeric) > (0)::numeric) THEN round((((((COALESCE(r.gross_profit, (0)::numeric) - COALESCE(c.direct_costs, (0)::numeric)) - COALESCE(c.overhead, (0)::numeric)) + COALESCE(c.dna, (0)::numeric)) / r.revenue) * (100)::numeric), 2)
            ELSE NULL::numeric
        END AS ebitda_margin_pct
   FROM ((pharma_products p
     LEFT JOIN rev r ON ((r.product_id = p.id)))
     LEFT JOIN cost c ON ((c.product_id = p.id)))
  WHERE (p.deleted_at IS NULL);

-- depth 1
create or replace view public.pharma_territory_pl with (security_invoker=true) as
 WITH rev AS (
         SELECT pharma_revenue_lines.territory_id,
            sum(pharma_revenue_lines.revenue) AS revenue,
            sum(pharma_revenue_lines.gross_profit) AS gross_profit
           FROM pharma_revenue_lines
          WHERE (pharma_revenue_lines.territory_id IS NOT NULL)
          GROUP BY pharma_revenue_lines.territory_id
        ), cost AS (
         SELECT pharma_allocated_costs.territory_id,
            sum(pharma_allocated_costs.allocated_amount) AS costs
           FROM pharma_allocated_costs
          WHERE (pharma_allocated_costs.territory_id IS NOT NULL)
          GROUP BY pharma_allocated_costs.territory_id
        )
 SELECT t.id AS territory_id,
    t.name AS territory,
    t.level,
    COALESCE(r.revenue, (0)::numeric) AS revenue,
    COALESCE(r.gross_profit, (0)::numeric) AS gross_profit,
    COALESCE(c.costs, (0)::numeric) AS allocated_costs,
    (COALESCE(r.gross_profit, (0)::numeric) - COALESCE(c.costs, (0)::numeric)) AS contribution,
        CASE
            WHEN (COALESCE(r.revenue, (0)::numeric) > (0)::numeric) THEN round((((COALESCE(r.gross_profit, (0)::numeric) - COALESCE(c.costs, (0)::numeric)) / r.revenue) * (100)::numeric), 2)
            ELSE NULL::numeric
        END AS contribution_pct
   FROM ((pharma_territories t
     LEFT JOIN rev r ON ((r.territory_id = t.id)))
     LEFT JOIN cost c ON ((c.territory_id = t.id)))
  WHERE t.is_active;

-- depth 2
create or replace view public.analytics_fact_orders as
 SELECT o.id,
    o.created_at,
    o.order_date,
    o.organization_id AS org_id,
    NULL::text AS service,
    o.title,
    o.currency,
    e.revenue
   FROM (crm_orders o
     LEFT JOIN crm_order_ebitda e ON ((e.order_id = o.id)))
  WHERE (o.deleted_at IS NULL);

-- depth 2
create or replace view public.crm_budget_vs_actual with (security_invoker=true) as
 SELECT b.id,
    b.period,
    b.cost_centre_id,
    b.amount AS budget,
    b.currency,
    b.notes,
    COALESCE(c.name, 'Whole Company'::text) AS scope,
        CASE
            WHEN (b.cost_centre_id IS NULL) THEN COALESCE(( SELECT e.ledger_total
               FROM crm_expense_ledger_monthly e
              WHERE (e.period = b.period)), (0)::numeric)
            ELSE COALESCE(( SELECT sum(d.amount) AS sum
               FROM crm_daily_entries d
              WHERE ((d.status = 'approved'::text) AND (d.currency = 'PKR'::text) AND (d.cost_centre_id = b.cost_centre_id) AND (to_char((d.entry_date)::timestamp with time zone, 'YYYY-MM'::text) = b.period))), (0)::numeric)
        END AS actual_ledger,
        CASE
            WHEN (b.cost_centre_id IS NULL) THEN COALESCE(( SELECT l.direct_labour
               FROM crm_labour_monthly l
              WHERE (l.period = b.period)), (0)::numeric)
            ELSE (0)::numeric
        END AS actual_labour,
        CASE
            WHEN (b.cost_centre_id IS NULL) THEN COALESCE(( SELECT sum(crm_monthly_overhead_actual.monthly_total) AS sum
               FROM crm_monthly_overhead_actual
              WHERE (crm_monthly_overhead_actual.currency = 'PKR'::text)), (0)::numeric)
            ELSE COALESCE(( SELECT sum(o.monthly_total) AS sum
               FROM crm_monthly_overhead_actual o
              WHERE ((o.currency = 'PKR'::text) AND (o.cost_centre = c.name))), (0)::numeric)
        END AS modelled_recurring,
        CASE
            WHEN (b.cost_centre_id IS NULL) THEN COALESCE(( SELECT sum(crm_monthly_employee_cost.monthly_total) AS sum
               FROM crm_monthly_employee_cost
              WHERE (crm_monthly_employee_cost.currency = 'PKR'::text)), (0)::numeric)
            ELSE COALESCE(( SELECT sum(p.monthly_total) AS sum
               FROM crm_monthly_employee_cost p
              WHERE ((p.currency = 'PKR'::text) AND (p.cost_centre = c.name))), (0)::numeric)
        END AS modelled_payroll
   FROM (crm_budgets b
     LEFT JOIN crm_cost_centres c ON ((c.id = b.cost_centre_id)));

-- depth 2
create or replace view public.crm_cost_centre_report with (security_invoker=true) as
 SELECT 'recurring'::text AS source,
    crm_monthly_overhead_actual.cost_centre,
    crm_monthly_overhead_actual.currency,
    crm_monthly_overhead_actual.monthly_total
   FROM crm_monthly_overhead_actual
UNION ALL
 SELECT 'payroll'::text AS source,
    crm_monthly_employee_cost.cost_centre,
    crm_monthly_employee_cost.currency,
    crm_monthly_employee_cost.monthly_total
   FROM crm_monthly_employee_cost
UNION ALL
 SELECT 'daily_approved_this_month'::text AS source,
    COALESCE(c.name, 'Unassigned'::text) AS cost_centre,
    d.currency,
    sum(d.amount) AS monthly_total
   FROM (crm_daily_entries d
     LEFT JOIN crm_cost_centres c ON ((c.id = d.cost_centre_id)))
  WHERE ((d.status = 'approved'::text) AND (d.entry_date >= (date_trunc('month'::text, (CURRENT_DATE)::timestamp with time zone))::date))
  GROUP BY COALESCE(c.name, 'Unassigned'::text), d.currency;

-- depth 2
create or replace view public.crm_monthly_finance with (security_invoker=on) as
 SELECT to_char((m.month)::timestamp with time zone, 'YYYY-MM'::text) AS period,
    m.invoiced,
    m.collected,
    COALESCE(g.gross_profit, (0)::numeric) AS gross_profit,
    COALESCE(g.ebitda, (0)::numeric) AS ebitda
   FROM (( SELECT (date_trunc('month'::text, d.d))::date AS month,
            COALESCE(( SELECT sum(i.total) AS sum
                   FROM crm_invoices i
                  WHERE ((i.deleted_at IS NULL) AND (i.status <> ALL (ARRAY['draft'::text, 'pending_approval'::text, 'cancelled'::text])) AND (date_trunc('month'::text, (i.issue_date)::timestamp with time zone) = date_trunc('month'::text, d.d)))), (0)::numeric) AS invoiced,
            COALESCE(( SELECT sum(p.amount) AS sum
                   FROM crm_payments p
                  WHERE ((p.deleted_at IS NULL) AND p.is_verified AND (date_trunc('month'::text, (p.payment_date)::timestamp with time zone) = date_trunc('month'::text, d.d)))), (0)::numeric) AS collected
           FROM generate_series((date_trunc('month'::text, (CURRENT_DATE)::timestamp with time zone) - '11 mons'::interval), date_trunc('month'::text, (CURRENT_DATE)::timestamp with time zone), '1 mon'::interval) d(d)) m
     LEFT JOIN ( SELECT (date_trunc('month'::text, (crm_order_ebitda.order_date)::timestamp with time zone))::date AS month,
            sum((crm_order_ebitda.revenue - crm_order_ebitda.cogs)) AS gross_profit,
            sum(crm_order_ebitda.ebitda_contribution) AS ebitda
           FROM crm_order_ebitda
          GROUP BY ((date_trunc('month'::text, (crm_order_ebitda.order_date)::timestamp with time zone))::date)) g ON ((g.month = m.month)))
  ORDER BY m.month;

-- depth 2
create or replace view public.crm_order_costing_actual with (security_invoker=true) as
 SELECT e.order_id,
    e.order_number,
    e.order_date,
    e.currency,
    e.revenue,
    e.cogs,
    e.direct_expenses,
    COALESCE(l.hours, (0)::numeric) AS labour_hours,
    COALESCE(l.direct_labour, (0)::numeric) AS direct_labour,
    COALESCE(a.allocated, (0)::numeric) AS allocated_actual,
    round(((((e.revenue - e.cogs) - e.direct_expenses) - COALESCE(l.direct_labour, (0)::numeric)) - COALESCE(a.allocated, (0)::numeric)), 2) AS ebitda_actual,
        CASE
            WHEN (e.revenue <> (0)::numeric) THEN round(((((((e.revenue - e.cogs) - e.direct_expenses) - COALESCE(l.direct_labour, (0)::numeric)) - COALESCE(a.allocated, (0)::numeric)) / e.revenue) * (100)::numeric), 2)
            ELSE NULL::numeric
        END AS ebitda_actual_margin_pct,
    e.ebitda_contribution AS ebitda_notional,
    round((((((e.revenue - e.cogs) - e.direct_expenses) - COALESCE(l.direct_labour, (0)::numeric)) - COALESCE(a.allocated, (0)::numeric)) - e.ebitda_contribution), 2) AS variance_vs_notional
   FROM ((crm_order_ebitda e
     LEFT JOIN crm_order_direct_labour l ON ((l.order_id = e.order_id)))
     LEFT JOIN ( SELECT crm_cost_allocations.order_id,
            sum(crm_cost_allocations.allocated_amount) AS allocated
           FROM crm_cost_allocations
          GROUP BY crm_cost_allocations.order_id) a ON ((a.order_id = e.order_id)));

-- depth 2
create or replace view public.crm_report_client_value with (security_invoker=on) as
 SELECT g.id AS organization_id,
    g.legal_name,
    ( SELECT count(*) AS count
           FROM crm_enquiries e
          WHERE ((e.organization_id = g.id) AND (e.deleted_at IS NULL))) AS enquiries,
    ( SELECT count(*) AS count
           FROM crm_quotations q
          WHERE ((q.organization_id = g.id) AND (q.deleted_at IS NULL))) AS quotations,
    count(o.order_id) AS orders,
    COALESCE(sum(o.revenue), (0)::numeric) AS revenue,
    COALESCE(sum((o.revenue - o.cogs)), (0)::numeric) AS gross_profit,
    COALESCE(sum(o.ebitda_contribution), (0)::numeric) AS ebitda,
    COALESCE(( SELECT sum(i.outstanding) AS sum
           FROM crm_invoices i
          WHERE ((i.organization_id = g.id) AND (i.deleted_at IS NULL) AND (i.status = ANY (ARRAY['issued'::text, 'partially_paid'::text, 'overdue'::text])))), (0)::numeric) AS outstanding
   FROM (crm_organizations g
     LEFT JOIN crm_order_ebitda o ON ((o.organization_id = g.id)))
  WHERE (g.deleted_at IS NULL)
  GROUP BY g.id, g.legal_name;

-- depth 2
create or replace view public.crm_report_country with (security_invoker=on) as
 SELECT COALESCE(g.country, 'Unknown'::text) AS country,
    count(o.order_id) AS orders,
    COALESCE(sum(o.revenue), (0)::numeric) AS revenue,
    COALESCE(sum((o.revenue - o.cogs)), (0)::numeric) AS gross_profit
   FROM ((crm_orders ord
     JOIN crm_organizations g ON ((g.id = ord.organization_id)))
     LEFT JOIN crm_order_ebitda o ON ((o.order_id = ord.id)))
  WHERE (ord.deleted_at IS NULL)
  GROUP BY COALESCE(g.country, 'Unknown'::text);

-- depth 2
create or replace view public.crm_report_service_perf with (security_invoker=on) as
 SELECT s.id AS service_id,
    s.name AS service_name,
    count(o.order_id) AS orders,
    COALESCE(sum(o.revenue), (0)::numeric) AS revenue,
    COALESCE(sum((o.revenue - o.cogs)), (0)::numeric) AS gross_profit,
    COALESCE(sum(o.ebitda_contribution), (0)::numeric) AS ebitda
   FROM (crm_services s
     LEFT JOIN crm_order_ebitda o ON ((o.service_id = s.id)))
  GROUP BY s.id, s.name;

-- depth 2
create or replace view public.pharma_distributor_pl with (security_invoker=true) as
 WITH rev AS (
         SELECT pharma_revenue_lines.distributor_id,
            sum(pharma_revenue_lines.revenue) AS revenue,
            sum(pharma_revenue_lines.gross_profit) AS gross_profit,
            count(DISTINCT pharma_revenue_lines.order_id) AS orders
           FROM pharma_revenue_lines
          WHERE (pharma_revenue_lines.distributor_id IS NOT NULL)
          GROUP BY pharma_revenue_lines.distributor_id
        ), cost AS (
         SELECT pharma_allocated_costs.distributor_id,
            sum(pharma_allocated_costs.allocated_amount) AS costs
           FROM pharma_allocated_costs
          WHERE (pharma_allocated_costs.distributor_id IS NOT NULL)
          GROUP BY pharma_allocated_costs.distributor_id
        )
 SELECT d.id AS distributor_id,
    d.name,
    d.distributor_type,
    d.credit_limit,
    COALESCE(r.orders, (0)::bigint) AS orders,
    COALESCE(r.revenue, (0)::numeric) AS revenue,
    COALESCE(r.gross_profit, (0)::numeric) AS gross_profit,
    COALESCE(c.costs, (0)::numeric) AS allocated_costs,
    (COALESCE(r.gross_profit, (0)::numeric) - COALESCE(c.costs, (0)::numeric)) AS contribution,
    e.outstanding,
    e.credit_status
   FROM (((pharma_distributors d
     LEFT JOIN rev r ON ((r.distributor_id = d.id)))
     LEFT JOIN cost c ON ((c.distributor_id = d.id)))
     LEFT JOIN pharma_credit_exposure e ON ((e.distributor_id = d.id)))
  WHERE (d.deleted_at IS NULL);

-- depth 3
create or replace view public.crm_cashflow_monthly with (security_invoker=true) as
 SELECT mf.period,
    mf.collected AS cash_in,
    COALESCE(el.ledger_total, (0)::numeric) AS cash_out_ledger,
    round((mf.collected - COALESCE(el.ledger_total, (0)::numeric)), 2) AS net_operating_cash
   FROM (crm_monthly_finance mf
     LEFT JOIN crm_expense_ledger_monthly el ON ((el.period = mf.period)));

-- depth 3
create or replace view public.crm_pl_actual_monthly with (security_invoker=true) as
 SELECT mf.period,
    mf.invoiced,
    mf.collected,
    mf.gross_profit,
    COALESCE(el.direct_total, (0)::numeric) AS direct_expenses,
    COALESCE(lm.direct_labour, (0)::numeric) AS direct_labour,
    COALESCE(am.allocated, (0)::numeric) AS allocated_overheads,
    round((((mf.gross_profit - COALESCE(el.direct_total, (0)::numeric)) - COALESCE(lm.direct_labour, (0)::numeric)) - COALESCE(am.allocated, (0)::numeric)), 2) AS ebitda_actual,
    mf.ebitda AS ebitda_notional,
    (am.allocated IS NOT NULL) AS complete
   FROM (((crm_monthly_finance mf
     LEFT JOIN crm_expense_ledger_monthly el ON ((el.period = mf.period)))
     LEFT JOIN crm_labour_monthly lm ON ((lm.period = mf.period)))
     LEFT JOIN crm_allocations_monthly am ON ((am.period = mf.period)));
