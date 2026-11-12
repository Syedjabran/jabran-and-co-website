-- Baseline 04: every function in schema public (153), verbatim from
-- pg_get_functiondef(oid), ordered by name then oid. Owners are not included.
--
-- Several SQL-language functions reference views created in 05_views.sql, and
-- several views call these functions, so body validation is switched off for
-- this file (plpgsql bodies are never resolved at create time anyway).
set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.ai_activate_prompt(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a text;
begin
  if not public.crm_has_role(array['owner','super_admin','ceo']) then
    raise exception 'Governance roles only.';
  end if;
  select agent into a from public.ai_prompt_versions where id = p_id;
  if a is null then raise exception 'Prompt version not found.'; end if;
  update public.ai_prompt_versions set is_active = false where agent = a and is_active;
  update public.ai_prompt_versions set is_active = true  where id = p_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.ai_anonymize_conversation(p_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.crm_has_role(array['owner','super_admin']) then
    raise exception 'Owner / Super Admin only.';
  end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A reason is required.'; end if;
  update public.ai_conversations
     set contact_name = null, contact_email = null, contact_phone = null,
         contact_company = null, visitor_id = null, session_id = null,
         intent = null, updated_at = now()
   where id = p_id;
  update public.ai_messages
     set content = '[redacted — anonymised '||current_date||']'
   where conversation_id = p_id and sender_type in ('visitor','client');
  insert into public.ai_messages (conversation_id, sender_type, message_type, content)
  values (p_id, 'system', 'system_note',
          'Conversation anonymised by governance. Reason: '||p_reason);
end $function$
;

CREATE OR REPLACE FUNCTION public.ai_client_snapshot()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare org uuid; org_name text; snap jsonb := '{}'::jsonb;
        j jsonb; name_col text;
begin
  select pm.organization_id into org
    from public.crm_portal_members pm where pm.user_id = auth.uid() limit 1;
  if org is null then
    raise exception 'This account is not linked to a client organisation.';
  end if;

  begin
    select legal_name into org_name from public.crm_organizations where id = org;
  exception when others then org_name := null;
  end;
  snap := jsonb_build_object('organization', coalesce(org_name,'your organisation'),
                             'generated_at', now());

  -- orders (client-safe view from migration 003) + tracking + RM name
  begin
    select column_name into name_col from information_schema.columns
     where table_schema='public' and table_name='crm_employee_profiles'
       and column_name in ('full_name','name','display_name') limit 1;

    execute format($f$
      select coalesce(jsonb_agg(jsonb_build_object(
        'order_number', o.order_number,
        'title',        o.title,
        'status',       o.status,
        'progress_pct', t.progress_percentage,
        'is_delayed',   t.is_delayed,
        'next_milestone', case when exists (select 1 from crm_order_milestones m
                              where m.order_id = o.id and m.client_visible
                                and m.milestone_label = t.next_milestone)
                            then t.next_milestone end,
        'next_milestone_due', t.next_milestone_due_at,
        'expected_completion', coalesce(t.revised_completion_date, t.expected_completion_date),
        'latest_client_update', (select m.client_update from crm_order_milestones m
                                  where m.order_id = o.id and m.client_visible
                                    and m.client_update is not null
                                  order by m.updated_at desc limit 1),
        'relationship_manager', %s
      ) order by o.order_number), '[]'::jsonb)
      from public.crm_client_orders o
      left join public.crm_orders oo on oo.id = o.id
      left join public.crm_order_tracking t on t.order_id = o.id $f$,
      case when name_col is not null
        then '(select ep.'||quote_ident(name_col)||' from public.crm_employee_profiles ep
                where ep.user_id = oo.relationship_manager_id)'
        else 'null::text' end)
    into j;
    snap := snap || jsonb_build_object('orders', coalesce(j,'[]'::jsonb));
  exception when others then
    snap := snap || jsonb_build_object('orders','[]'::jsonb);
  end;

  -- invoices (client-safe view from migration 004)
  begin
    select coalesce(jsonb_agg(to_jsonb(i) - 'id' order by i.invoice_number), '[]'::jsonb)
      into j from public.crm_client_invoices i;
    snap := snap || jsonb_build_object('invoices', j);
  exception when others then
    snap := snap || jsonb_build_object('invoices','[]'::jsonb);
  end;

  -- open enquiries the client has submitted
  begin
    select coalesce(jsonb_agg(jsonb_build_object(
             'title', e.title, 'status', e.status,
             'submitted', e.created_at::date) order by e.created_at desc), '[]'::jsonb)
      into j
      from public.crm_enquiries e
     where e.organization_id = org
       and coalesce(e.status,'') not in ('closed','converted')
     limit 10;
    snap := snap || jsonb_build_object('open_enquiries', coalesce(j,'[]'::jsonb));
  exception when others then
    snap := snap || jsonb_build_object('open_enquiries','[]'::jsonb);
  end;

  -- client-visible shared documents (Increment 1 system)
  begin
    select coalesce(jsonb_agg(jsonb_build_object(
             'title', a.document_title, 'category', a.document_category,
             'shared', a.created_at::date) order by a.created_at desc), '[]'::jsonb)
      into j
      from public.crm_attachments a
     where a.organization_id = org and a.deleted_at is null
       and a.is_current_version and a.visibility_scope = 'client_visible'
     limit 15;
    snap := snap || jsonb_build_object('shared_documents', coalesce(j,'[]'::jsonb));
  exception when others then
    snap := snap || jsonb_build_object('shared_documents','[]'::jsonb);
  end;

  return snap;
end $function$
;

CREATE OR REPLACE FUNCTION public.ai_content_intelligence(p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare since timestamptz := now() - make_interval(days => greatest(1, coalesce(p_days,30)));
        j jsonb;
begin
  if not public.crm_has_role(array['owner','super_admin','ceo','read_only_auditor']) then
    raise exception 'Governance roles only.';
  end if;

  select jsonb_build_object(
    'window_days', p_days,

    'totals', (select jsonb_build_object(
        'conversations', count(*),
        'public',  count(*) filter (where conversation_type = 'public'),
        'client',  count(*) filter (where conversation_type = 'client'),
        'resolved', count(*) filter (where status = 'resolved'),
        'abandoned', count(*) filter (where status = 'abandoned'),
        'spam', count(*) filter (where status = 'spam'),
        'with_contact', count(*) filter (where contact_email is not null),
        'enquiries_created', count(*) filter (where enquiry_id is not null))
      from ai_conversations where started_at >= since),

    'lead_classes', (select coalesce(jsonb_object_agg(coalesce(lead_class,'unscored'), n), '{}'::jsonb)
      from (select lead_class, count(*) n from ai_conversations
             where started_at >= since and conversation_type = 'public'
             group by lead_class) t),

    'human_takeover', (select jsonb_build_object(
        'handoffs', count(*),
        'takeover_rate_pct', case when (select count(*) from ai_conversations
                                          where started_at >= since) = 0 then 0
          else round(count(distinct h.conversation_id) * 100.0 /
               (select count(*) from ai_conversations where started_at >= since), 1) end)
      from ai_agent_handoffs h
      join ai_conversations c on c.id = h.conversation_id
     where c.started_at >= since),

    'containment_rate_pct', (select case when count(*) = 0 then null
        else round(count(*) filter (where not exists (
               select 1 from ai_agent_handoffs h where h.conversation_id = c.id))
             * 100.0 / count(*), 1) end
      from ai_conversations c
     where c.started_at >= since and c.status in ('resolved','abandoned')),

    'top_service_interest', (select coalesce(jsonb_agg(jsonb_build_object('service', s, 'n', n)
          order by n desc), '[]'::jsonb)
      from (select service_context s, count(*) n from ai_conversations
             where started_at >= since and service_context is not null
             group by service_context order by n desc limit 8) t),

    'top_landing_pages', (select coalesce(jsonb_agg(jsonb_build_object('page', p, 'n', n)
          order by n desc), '[]'::jsonb)
      from (select landing_page p, count(*) n from ai_conversations
             where started_at >= since and landing_page is not null
             group by landing_page order by n desc limit 8) t),

    'top_campaigns', (select coalesce(jsonb_agg(jsonb_build_object('campaign', cmp, 'n', n)
          order by n desc), '[]'::jsonb)
      from (select utm_campaign cmp, count(*) n from ai_conversations
             where started_at >= since and utm_campaign is not null
             group by utm_campaign order by n desc limit 6) t),

    'handoff_reasons', (select coalesce(jsonb_agg(jsonb_build_object('reason', r, 'n', n)
          order by n desc), '[]'::jsonb)
      from (select left(coalesce(handoff_reason,'—'), 90) r, count(*) n
              from ai_agent_handoffs h
              join ai_conversations c on c.id = h.conversation_id
             where c.started_at >= since
             group by 1 order by n desc limit 8) t),

    'avg_visitor_messages', (select round(avg(n),1) from (
        select count(*) n from ai_messages m
          join ai_conversations c on c.id = m.conversation_id
         where c.started_at >= since and m.sender_type in ('visitor','client')
         group by m.conversation_id) t),

    -- FAQ mining: recent requirement summaries, truncated, no contact fields
    'recent_needs', (select coalesce(jsonb_agg(needs order by 1), '[]'::jsonb)
      from (select distinct left(intent, 140) needs from ai_conversations
             where started_at >= since and intent is not null
             order by 1 limit 12) t)
  ) into j;
  return j;
end $function$
;

CREATE OR REPLACE FUNCTION public.ai_conv_touch()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin new.updated_at := now(); return new; end $function$
;

CREATE OR REPLACE FUNCTION public.ai_export_conversation(p_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare j json;
begin
  if not public.crm_has_role(array['owner','super_admin','ceo','read_only_auditor']) then
    raise exception 'Governance roles only.';
  end if;
  select json_build_object(
    'conversation', row_to_json(c),
    'messages', (select coalesce(json_agg(row_to_json(m) order by m.created_at), '[]'::json)
                   from public.ai_messages m where m.conversation_id = p_id),
    'summaries', (select coalesce(json_agg(row_to_json(s) order by s.generated_at), '[]'::json)
                   from public.ai_conversation_summaries s where s.conversation_id = p_id),
    'handoffs',  (select coalesce(json_agg(row_to_json(h) order by h.requested_at), '[]'::json)
                   from public.ai_agent_handoffs h where h.conversation_id = p_id))
    into j from public.ai_conversations c where c.id = p_id;
  if j is null then raise exception 'Conversation not found.'; end if;
  return j;
end $function$
;

CREATE OR REPLACE FUNCTION public.ai_handoff_after()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r record; ref text;
begin
  select conversation_reference into ref from public.ai_conversations where id = new.conversation_id;
  update public.ai_conversations
     set status = 'human_requested', updated_at = now()
   where id = new.conversation_id and status in ('ai_active','waiting_client');

  begin
    if new.assigned_to is not null then
      perform public.crm_notify(new.assigned_to, 'Conversation handoff',
        'Conversation '||coalesce(ref,'')||' has been escalated to you. Reason: '||coalesce(new.handoff_reason,'—'),
        'crm-conversations.html', 'ai');
    else
      for r in select distinct user_id from public.crm_staff_roles
                where role in ('owner','super_admin','ceo') loop
        perform public.crm_notify(r.user_id, 'Unassigned conversation handoff',
          'Conversation '||coalesce(ref,'')||' needs a human. Reason: '||coalesce(new.handoff_reason,'—'),
          'crm-conversations.html', 'ai');
      end loop;
    end if;
  exception when others then null;
  end;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.ai_msg_after()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.ai_conversations
     set last_message_at = new.created_at, updated_at = now(),
         status = case
           when status = 'waiting_client' and new.sender_type in ('visitor','client') then 'ai_active'
           else status end
   where id = new.conversation_id;

  if new.requires_human_review then
    begin
      perform public.crm_notify(c.assigned_user_id,
        'AI reply flagged for review',
        'A low-confidence AI response in conversation '||c.conversation_reference||' needs a human check.',
        'crm-conversations.html', 'ai')
      from public.ai_conversations c
      where c.id = new.conversation_id and c.assigned_user_id is not null;
    exception when others then null;
    end;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.analytics_by_dimension(p_metric text, p_dimension text, p_from date, p_to date, p_limit integer DEFAULT 12)
 RETURNS TABLE(label text, value numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_orgs uuid[];
begin
  if not analytics_can('analytics.view') then
    raise exception 'analytics.view permission required';
  end if;
  if p_metric not in ('leads','qualified_leads','quotations','quotations_value','orders','revenue',
                      'website_users','sessions','engaged_sessions','search_clicks','search_impressions') then
    raise exception 'Unsupported metric: %', p_metric;
  end if;
  if p_dimension not in ('service','source','status','stage','organization',
                         'channel','search_query','utm_source','utm_campaign') then
    raise exception 'Unsupported dimension: %', p_dimension;
  end if;
  if p_metric = 'revenue' and not analytics_can('analytics.view_financial_metrics') then
    raise exception 'analytics.view_financial_metrics required for revenue';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 730 then
    raise exception 'Invalid date range.';
  end if;
  v_orgs  := analytics_scope_orgs();
  p_limit := least(greatest(coalesce(p_limit,12), 1), 50);

  -- ---- GA4 by channel ----
  if p_metric in ('website_users','sessions','engaged_sessions') then
    if v_orgs is not null then
      raise exception 'Website metrics are firm-wide and are not available in a client-scoped view.';
    end if;
    if p_dimension <> 'channel' then
      raise exception 'Website metrics support only the channel dimension.';
    end if;
    return query
      select coalesce(m.dimension->>'channel','(other)')::text,
             case p_metric when 'website_users' then coalesce(sum(m.users),0)
                           when 'sessions'      then coalesce(sum(m.sessions),0)
                           else coalesce(sum(m.engaged_sessions),0) end
        from analytics_daily_metrics m
       where m.source = 'ga4' and m.metric_date between p_from and p_to
       group by 1 order by 2 desc limit p_limit;

  -- ---- Search Console by query ----
  elsif p_metric in ('search_clicks','search_impressions') then
    if v_orgs is not null then
      raise exception 'Search metrics are firm-wide and are not available in a client-scoped view.';
    end if;
    if p_dimension <> 'search_query' then
      raise exception 'Search metrics support only the search_query dimension.';
    end if;
    return query
      select coalesce(c.search_query,'(unknown)')::text,
             case p_metric when 'search_clicks' then coalesce(sum(c.clicks),0)
                           else coalesce(sum(c.impressions),0) end
        from analytics_content_metrics c
       where c.source = 'search_console' and c.metric_date between p_from and p_to
       group by 1 order by 2 desc limit p_limit;

  -- ---- LEADS: now including channel / utm ----
  elsif p_metric = 'leads' then
    if p_dimension not in ('service','source','status','channel','utm_source','utm_campaign') then
      raise exception 'Dimension % is not available for leads', p_dimension;
    end if;
    return query
      select coalesce(
               case p_dimension
                 when 'service'      then e.service
                 when 'source'       then e.source
                 when 'status'       then e.status
                 when 'channel'      then e.channel
                 when 'utm_source'   then e.utm_source
                 else e.utm_campaign
               end, 'Unattributed')::text,
             count(*)::numeric
        from analytics_fact_enquiries e
       where e.created_at::date between p_from and p_to
         and (v_orgs is null or e.org_id = any(v_orgs))
       group by 1 order by 2 desc limit p_limit;

  elsif p_metric = 'qualified_leads' then
    return query
      select coalesce(case p_dimension when 'service' then o.service else o.stage end, 'Unspecified')::text,
             count(*)::numeric
        from analytics_fact_opportunities o
       where o.created_at::date between p_from and p_to
         and (v_orgs is null or o.org_id = any(v_orgs))
       group by 1 order by 2 desc limit p_limit;

  elsif p_metric in ('quotations','quotations_value') then
    return query
      select coalesce(case p_dimension when 'service' then q.service else q.status end, 'Unspecified')::text,
             case when p_metric = 'quotations' then count(*)::numeric else coalesce(sum(q.total),0) end
        from analytics_fact_quotations q
       where q.created_at::date between p_from and p_to
         and (v_orgs is null or q.org_id = any(v_orgs))
       group by 1 order by 2 desc limit p_limit;

  else
    return query
      select coalesce(case when p_dimension = 'organization'
                           then coalesce(org.legal_name, org.trading_name)
                           else o.service end, 'Unspecified')::text,
             case when p_metric = 'orders' then count(*)::numeric else coalesce(sum(o.revenue),0) end
        from analytics_fact_orders o
        left join crm_organizations org on org.id = o.org_id
       where o.order_date between p_from and p_to
         and (v_orgs is null or o.org_id = any(v_orgs))
       group by 1 order by 2 desc limit p_limit;
  end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.analytics_can(p_permission text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    exists (select 1 from crm_staff_roles sr
             where sr.user_id = auth.uid() and sr.role in ('owner','super_admin'))
    or exists (select 1 from crm_staff_roles sr
                join analytics_role_permissions rp on rp.role = sr.role
               where sr.user_id = auth.uid() and rp.permission = p_permission)
    or ( p_permission in ('analytics.view','analytics.query','analytics.view_client_scope')
         and exists (select 1 from crm_portal_members pm where pm.user_id = auth.uid())
         and coalesce((select (value #>> '{}')::boolean from crm_settings
                        where key = 'analytics_client_portal_enabled'), false) );
$function$
;

CREATE OR REPLACE FUNCTION public.analytics_connection_health()
 RETURNS TABLE(provider text, connected_at timestamp with time zone, connected_by_email text, scopes jsonb, account_ref text, access_expires timestamp with time zone, rotated_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not analytics_can('analytics.view') then
    raise exception 'analytics.view permission required';
  end if;
  return query
  select t.provider, t.connected_at, u.email::text, t.scopes, t.account_ref,
         t.access_expires, t.rotated_at
    from analytics_oauth_tokens t
    left join auth.users u on u.id = t.connected_by;
end $function$
;

CREATE OR REPLACE FUNCTION public.analytics_data_freshness()
 RETURNS TABLE(source text, display_name text, status text, last_data_at timestamp with time zone, note text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not analytics_can('analytics.view') then
    raise exception 'analytics.view permission required';
  end if;
  return query
  select c.platform, c.display_name, c.status,
    case c.platform
      when 'crm' then (
        select max(t) from (
          select max(created_at) as t from analytics_fact_enquiries
          union all select max(created_at) from analytics_fact_quotations
          union all select max(created_at) from analytics_fact_orders
        ) s)
      else (select max(d.ingested_at) from analytics_daily_metrics d where d.source = c.platform)
    end,
    coalesce(c.last_error, c.setup_note)
  from analytics_connections c
  order by (c.platform = 'crm') desc, c.display_name;
end $function$
;

CREATE OR REPLACE FUNCTION public.analytics_derive_channel(p_utm_source text, p_utm_medium text, p_referrer text, p_click_id text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select analytics_derive_channel(p_utm_source, p_utm_medium, p_referrer, p_click_id, null);
$function$
;

CREATE OR REPLACE FUNCTION public.analytics_derive_channel(p_utm_source text, p_utm_medium text, p_referrer text, p_click_id text, p_landing_page text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select case
    -- No web evidence whatsoever: do not guess. This lead reached us some other
    -- way (phone, WhatsApp, in person, staff entry) or predates capture.
    when coalesce(p_utm_source,'') = ''
     and coalesce(p_referrer,'')   = ''
     and coalesce(p_click_id,'')   = ''
     and coalesce(p_landing_page,'') = ''
      then 'Unattributed'

    -- Paid: a real ad click id, or an explicitly paid medium
    when coalesce(p_click_id,'') <> '' then
      case when lower(coalesce(p_utm_source,'')) ~ '(facebook|instagram|meta|linkedin)' then 'Paid Social'
           else 'Paid Search' end
    when lower(coalesce(p_utm_medium,'')) in ('cpc','ppc','paidsearch','paid_search') then 'Paid Search'
    when lower(coalesce(p_utm_medium,'')) in ('paid_social','paidsocial','cpm','display','banner') then 'Paid Social'

    -- Organic social
    when lower(coalesce(p_utm_source,'')) ~ '(facebook|instagram|linkedin|twitter|x\.com|youtube|tiktok|whatsapp)'
      or lower(coalesce(p_referrer,''))   ~ '(facebook|instagram|linkedin|twitter|x\.com|youtube|tiktok|whatsapp)'
      then 'Organic Social'

    when lower(coalesce(p_utm_medium,'')) in ('email','newsletter') then 'Email'

    -- Organic search
    when lower(coalesce(p_utm_medium,'')) = 'organic' then 'Organic Search'
    when lower(coalesce(p_referrer,'')) ~ '(google\.|bing\.|yahoo\.|duckduckgo\.|ecosia\.|yandex\.)'
      then 'Organic Search'

    -- Referral from another site
    when coalesce(p_referrer,'') <> ''
     and lower(p_referrer) not like '%jabranandco.com%' then 'Referral'

    -- A genuine Direct visit: they landed on the site, with no referrer and no
    -- campaign. The landing page is the evidence that a visit happened at all.
    when coalesce(p_landing_page,'') <> ''
     and coalesce(p_utm_source,'') = ''
     and coalesce(p_referrer,'')   = '' then 'Direct'

    when coalesce(p_utm_source,'') <> '' then initcap(p_utm_source)

    else 'Unattributed'
  end;
$function$
;

CREATE OR REPLACE FUNCTION public.analytics_metric_catalog()
 RETURNS TABLE(code text, label text, category text, unit text, formula text, available boolean, unavailable_reason text, supports_timeseries boolean, supports_dimensions text[])
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not analytics_can('analytics.view') then
    raise exception 'analytics.view permission required';
  end if;
  return query
  with facts as (
    select
      exists (select 1 from analytics_daily_metrics   where source = 'ga4' limit 1)             as has_ga4,
      exists (select 1 from analytics_content_metrics where source = 'search_console' limit 1)  as has_sc,
      exists (select 1 from analytics_daily_metrics
               where source in ('google_ads','meta_ads','linkedin_ads')
                 and spend is not null limit 1)                                                 as has_spend,
      coalesce((select fm.columns->>'value' from analytics_fact_map fm
                 where fm.fact = 'opportunities'), '') <> ''                                    as has_opp_value
  )
  select d.code, d.label, d.category, d.unit, d.formula,
    case
      when d.needs_permission is not null and not analytics_can(d.needs_permission) then false
      when d.needs_source = 'ads'            and not f.has_spend then false
      when d.needs_source = 'ga4'            and not f.has_ga4   then false
      when d.needs_source = 'search_console' and not f.has_sc    then false
      when d.code in ('pipeline_value','weighted_pipeline') and not f.has_opp_value then false
      else true
    end,
    case
      when d.needs_permission is not null and not analytics_can(d.needs_permission)
        then 'Your role does not include ' || d.needs_permission
      when d.needs_source = 'ads' and not f.has_spend
        then 'No advertising spend has been synced. Spend-based metrics cannot be calculated and will never be estimated.'
      when d.needs_source = 'ga4' and not f.has_ga4
        then case when exists (select 1 from analytics_connections c where c.platform = 'ga4' and c.status = 'connected')
                  then 'Google Analytics is connected but has never been synced — tap Sync now on that source.'
                  else 'Google Analytics 4 is not connected.' end
      when d.needs_source = 'search_console' and not f.has_sc
        then case when exists (select 1 from analytics_connections c where c.platform = 'search_console' and c.status = 'connected')
                  then 'Search Console is connected but has never been synced — tap Sync now on that source.'
                  else 'Google Search Console is not connected.' end
      when d.code in ('pipeline_value','weighted_pipeline') and not f.has_opp_value
        then 'crm_opportunities has no recognised value column on this schema.'
      else null
    end,
    d.supports_timeseries, d.supports_dimensions
  from analytics_metric_definitions d, facts f
  order by d.sort_order;
end $function$
;

CREATE OR REPLACE FUNCTION public.analytics_my_permissions()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select array(
    select p from unnest(array[
      'analytics.view','analytics.query','analytics.connect_sources',
      'analytics.manage_connections','analytics.export','analytics.schedule_reports',
      'analytics.view_financial_metrics','analytics.view_all_departments',
      'analytics.view_client_scope','analytics.admin'
    ]) as p
    where analytics_can(p)
  );
$function$
;

CREATE OR REPLACE FUNCTION public.analytics_overview(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_orgs uuid[];
  v_fin  boolean;
  v_days int;
  v_pfrom date; v_pto date;
  v_res jsonb;
  v_traffic jsonb := '{}'::jsonb;
  v_sources jsonb := jsonb_build_array('crm');
  v_has_ga4 boolean;
  v_closed text[] := array['won','lost','closed','closed_won','closed_lost','cancelled'];
begin
  if not analytics_can('analytics.view') then
    raise exception 'analytics.view permission required';
  end if;
  if p_from is null or p_to is null or p_to < p_from then
    raise exception 'Invalid date range.';
  end if;
  if p_to - p_from > 730 then
    raise exception 'Date range is limited to 24 months.';
  end if;

  v_orgs  := analytics_scope_orgs();
  v_fin   := analytics_can('analytics.view_financial_metrics');
  v_days  := (p_to - p_from) + 1;
  v_pto   := p_from - 1;
  v_pfrom := v_pto - (v_days - 1);

  select exists (select 1 from analytics_daily_metrics where source = 'ga4' limit 1) into v_has_ga4;

  if v_has_ga4 and v_orgs is null then
    select jsonb_build_object(
      'website_users', jsonb_build_object(
        'value',    (select coalesce(sum(users),0) from analytics_daily_metrics
                      where source='ga4' and metric_date between p_from and p_to),
        'previous', (select coalesce(sum(users),0) from analytics_daily_metrics
                      where source='ga4' and metric_date between v_pfrom and v_pto)),
      'sessions', jsonb_build_object(
        'value',    (select coalesce(sum(sessions),0) from analytics_daily_metrics
                      where source='ga4' and metric_date between p_from and p_to),
        'previous', (select coalesce(sum(sessions),0) from analytics_daily_metrics
                      where source='ga4' and metric_date between v_pfrom and v_pto)),
      'engaged_sessions', jsonb_build_object(
        'value',    (select coalesce(sum(engaged_sessions),0) from analytics_daily_metrics
                      where source='ga4' and metric_date between p_from and p_to),
        'previous', (select coalesce(sum(engaged_sessions),0) from analytics_daily_metrics
                      where source='ga4' and metric_date between v_pfrom and v_pto))
    ) into v_traffic;
    v_sources := v_sources || jsonb_build_array('ga4');
  end if;

  with
  cur as (
    select
      (select count(*) from analytics_fact_enquiries e
        where e.created_at::date between p_from and p_to
          and (v_orgs is null or e.org_id = any(v_orgs)))                 as leads,
      (select count(*) from analytics_fact_opportunities o
        where o.created_at::date between p_from and p_to
          and (v_orgs is null or o.org_id = any(v_orgs)))                 as qualified_leads,
      (select count(*) from analytics_fact_quotations q
        where q.created_at::date between p_from and p_to
          and (v_orgs is null or q.org_id = any(v_orgs)))                 as quotations,
      (select coalesce(sum(q.total),0) from analytics_fact_quotations q
        where q.created_at::date between p_from and p_to
          and (v_orgs is null or q.org_id = any(v_orgs)))                 as quotations_value,
      (select count(*) from analytics_fact_orders o
        where o.order_date between p_from and p_to
          and (v_orgs is null or o.org_id = any(v_orgs)))                 as orders,
      (select coalesce(sum(o.revenue),0) from analytics_fact_orders o
        where o.order_date between p_from and p_to
          and (v_orgs is null or o.org_id = any(v_orgs)))                 as revenue
  ),
  prev as (
    select
      (select count(*) from analytics_fact_enquiries e
        where e.created_at::date between v_pfrom and v_pto
          and (v_orgs is null or e.org_id = any(v_orgs)))                 as leads,
      (select count(*) from analytics_fact_opportunities o
        where o.created_at::date between v_pfrom and v_pto
          and (v_orgs is null or o.org_id = any(v_orgs)))                 as qualified_leads,
      (select count(*) from analytics_fact_quotations q
        where q.created_at::date between v_pfrom and v_pto
          and (v_orgs is null or q.org_id = any(v_orgs)))                 as quotations,
      (select count(*) from analytics_fact_orders o
        where o.order_date between v_pfrom and v_pto
          and (v_orgs is null or o.org_id = any(v_orgs)))                 as orders,
      (select coalesce(sum(o.revenue),0) from analytics_fact_orders o
        where o.order_date between v_pfrom and v_pto
          and (v_orgs is null or o.org_id = any(v_orgs)))                 as revenue
  ),
  pipe as (
    select
      coalesce(sum(o.est_value),0)                                        as pipeline_value,
      coalesce(sum(o.est_value * coalesce(o.probability,0) / 100.0),0)    as weighted_pipeline,
      count(*)                                                            as open_opportunities
    from analytics_fact_opportunities o
    where (v_orgs is null or o.org_id = any(v_orgs))
      and coalesce(lower(o.stage),'') <> all (v_closed)
  )
  select jsonb_build_object(
    'period', jsonb_build_object('from', p_from, 'to', p_to, 'days', v_days),
    'compare_period', jsonb_build_object('from', v_pfrom, 'to', v_pto),
    'scope', case when v_orgs is null then 'all_organisations' else 'client_scoped' end,
    'metrics', jsonb_build_object(
      'leads',             jsonb_build_object('value', cur.leads,            'previous', prev.leads),
      'qualified_leads',   jsonb_build_object('value', cur.qualified_leads,  'previous', prev.qualified_leads),
      'quotations',        jsonb_build_object('value', cur.quotations,       'previous', prev.quotations),
      'quotations_value',  jsonb_build_object('value', cur.quotations_value, 'previous', null),
      'orders',            jsonb_build_object('value', cur.orders,           'previous', prev.orders),
      'revenue',           case when v_fin
                                then jsonb_build_object('value', cur.revenue, 'previous', prev.revenue)
                                else jsonb_build_object('value', null, 'previous', null,
                                     'withheld', 'analytics.view_financial_metrics required') end,
      'pipeline_value',    jsonb_build_object('value', pipe.pipeline_value,    'previous', null),
      'weighted_pipeline', jsonb_build_object('value', pipe.weighted_pipeline, 'previous', null),
      'open_opportunities',jsonb_build_object('value', pipe.open_opportunities,'previous', null),
      'enquiry_to_opportunity_rate', jsonb_build_object('value',
        case when cur.leads > 0 then round(cur.qualified_leads::numeric / cur.leads * 100, 2) end),
      'quote_to_win_rate', jsonb_build_object('value',
        case when cur.quotations > 0 then round(cur.orders::numeric / cur.quotations * 100, 2) end),
      'lead_to_client_rate', jsonb_build_object('value',
        case when cur.leads > 0 then round(cur.orders::numeric / cur.leads * 100, 2) end),
      'avg_order_value', jsonb_build_object('value',
        case when v_fin and cur.orders > 0 then round(cur.revenue / cur.orders, 2) end)
    ) || v_traffic,
    'sources_used', v_sources,
    'notes', (
      select jsonb_agg(n) from unnest(array[
        'All figures are computed from live records. Nothing is estimated.',
        case when not v_fin then 'Revenue metrics withheld: your role lacks analytics.view_financial_metrics.' end,
        case when v_has_ga4 and v_orgs is null
             then 'Website traffic comes from Google Analytics 4 as of its last sync.' end,
        case when not v_has_ga4
             then 'No website traffic data: Google Analytics 4 has not been synced.' end,
        case when coalesce((select fm.columns->>'source' from analytics_fact_map fm where fm.fact = 'enquiries'),'') = ''
             then 'Lead source/UTM is not stored on crm_enquiries, so channel attribution between traffic and leads cannot be reported yet.' end,
        case when not exists (select 1 from analytics_daily_metrics
                               where source in ('google_ads','meta_ads','linkedin_ads') and spend is not null limit 1)
             then 'No advertising spend is connected: cost per lead, CAC and ROAS remain unavailable.' end
      ]) n where n is not null
    )
  ) into v_res
  from cur, prev, pipe;

  return v_res;
end $function$
;

CREATE OR REPLACE FUNCTION public.analytics_pick_col(p_table text, p_cands text[])
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select c.column_name
    from information_schema.columns c
   where c.table_schema = 'public'
     and c.table_name = p_table
     and c.column_name = any(p_cands)
   order by array_position(p_cands, c.column_name)
   limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.analytics_purge_oauth_states()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer;
begin
  delete from analytics_oauth_states
   where expires_at < now() - interval '1 hour';
  get diagnostics n = row_count;
  return n;
end $function$
;

CREATE OR REPLACE FUNCTION public.analytics_scope_orgs()
 RETURNS uuid[]
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_orgs uuid[];
begin
  if exists (select 1 from crm_staff_roles sr
              where sr.user_id = auth.uid()
                and sr.role in ('owner','super_admin','ceo','finance_manager'))
     or analytics_can('analytics.view_all_departments') then
    return null;
  end if;
  select array_agg(org_id) into v_orgs from analytics_my_orgs where org_id is not null;
  if v_orgs is null and crm_is_staff() then
    return null;
  end if;
  return coalesce(v_orgs, array[]::uuid[]);
end $function$
;

CREATE OR REPLACE FUNCTION public.analytics_timeseries(p_metric text, p_from date, p_to date, p_grain text DEFAULT 'day'::text)
 RETURNS TABLE(bucket date, value numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_orgs uuid[];
begin
  if not analytics_can('analytics.view') then
    raise exception 'analytics.view permission required';
  end if;
  if p_metric not in ('leads','qualified_leads','quotations','quotations_value','orders','revenue',
                      'website_users','sessions','engaged_sessions','search_clicks','search_impressions') then
    raise exception 'Unsupported metric for timeseries: %', p_metric;
  end if;
  if p_metric = 'revenue' and not analytics_can('analytics.view_financial_metrics') then
    raise exception 'analytics.view_financial_metrics required for revenue';
  end if;
  if p_grain not in ('day','week','month') then
    raise exception 'Grain must be day, week or month.';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 730 then
    raise exception 'Invalid date range.';
  end if;
  v_orgs := analytics_scope_orgs();

  -- Website/search traffic is firm-wide, never client-specific. A client-scoped
  -- caller is told so rather than shown someone else's numbers.
  if p_metric in ('website_users','sessions','engaged_sessions','search_clicks','search_impressions')
     and v_orgs is not null then
    raise exception 'Website and search metrics are firm-wide and are not available in a client-scoped view.';
  end if;

  if p_metric = 'leads' then
    return query select date_trunc(p_grain, e.created_at)::date, count(*)::numeric
      from analytics_fact_enquiries e
      where e.created_at::date between p_from and p_to
        and (v_orgs is null or e.org_id = any(v_orgs))
      group by 1 order by 1;
  elsif p_metric = 'qualified_leads' then
    return query select date_trunc(p_grain, o.created_at)::date, count(*)::numeric
      from analytics_fact_opportunities o
      where o.created_at::date between p_from and p_to
        and (v_orgs is null or o.org_id = any(v_orgs))
      group by 1 order by 1;
  elsif p_metric = 'quotations' then
    return query select date_trunc(p_grain, q.created_at)::date, count(*)::numeric
      from analytics_fact_quotations q
      where q.created_at::date between p_from and p_to
        and (v_orgs is null or q.org_id = any(v_orgs))
      group by 1 order by 1;
  elsif p_metric = 'quotations_value' then
    return query select date_trunc(p_grain, q.created_at)::date, coalesce(sum(q.total),0)
      from analytics_fact_quotations q
      where q.created_at::date between p_from and p_to
        and (v_orgs is null or q.org_id = any(v_orgs))
      group by 1 order by 1;
  elsif p_metric = 'orders' then
    return query select date_trunc(p_grain, o.order_date)::date, count(*)::numeric
      from analytics_fact_orders o
      where o.order_date between p_from and p_to
        and (v_orgs is null or o.org_id = any(v_orgs))
      group by 1 order by 1;
  elsif p_metric = 'revenue' then
    return query select date_trunc(p_grain, o.order_date)::date, coalesce(sum(o.revenue),0)
      from analytics_fact_orders o
      where o.order_date between p_from and p_to
        and (v_orgs is null or o.org_id = any(v_orgs))
      group by 1 order by 1;

  -- ---- GA4 ----
  elsif p_metric = 'website_users' then
    return query select date_trunc(p_grain, m.metric_date)::date, coalesce(sum(m.users),0)
      from analytics_daily_metrics m
      where m.source = 'ga4' and m.metric_date between p_from and p_to
      group by 1 order by 1;
  elsif p_metric = 'sessions' then
    return query select date_trunc(p_grain, m.metric_date)::date, coalesce(sum(m.sessions),0)
      from analytics_daily_metrics m
      where m.source = 'ga4' and m.metric_date between p_from and p_to
      group by 1 order by 1;
  elsif p_metric = 'engaged_sessions' then
    return query select date_trunc(p_grain, m.metric_date)::date, coalesce(sum(m.engaged_sessions),0)
      from analytics_daily_metrics m
      where m.source = 'ga4' and m.metric_date between p_from and p_to
      group by 1 order by 1;

  -- ---- Search Console ----
  elsif p_metric = 'search_clicks' then
    return query select date_trunc(p_grain, c.metric_date)::date, coalesce(sum(c.clicks),0)
      from analytics_content_metrics c
      where c.source = 'search_console' and c.metric_date between p_from and p_to
      group by 1 order by 1;
  else
    return query select date_trunc(p_grain, c.metric_date)::date, coalesce(sum(c.impressions),0)
      from analytics_content_metrics c
      where c.source = 'search_console' and c.metric_date between p_from and p_to
      group by 1 order by 1;
  end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_agent_add_enquiry_note(p_enquiry_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;
begin
  if not crm_is_agent() then raise exception 'agent only'; end if;
  if coalesce(p_note,'') = '' then raise exception 'note is required'; end if;
  insert into crm_enquiry_activity (enquiry_id, kind, visibility, body, created_by)
  values (p_enquiry_id, 'comment', 'internal_only', p_note, auth.uid())
  returning id into v_id;
  perform crm_agent_audit('agent_note', 'crm_enquiry_activity', v_id::text,
                          jsonb_build_object('enquiry_id', p_enquiry_id,
                                             'note', left(p_note, 500)));
  return jsonb_build_object('id', v_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_agent_audit(p_action text, p_entity text, p_entity_id text, p_after jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  insert into crm_audit_logs (user_id, action, entity, entity_id,
                              after_value, occurred_at, source)
  values (auth.uid(), p_action, p_entity, p_entity_id, p_after, now(),
          'ai-agent');
$function$
;

CREATE OR REPLACE FUNCTION public.crm_agent_insert_contact(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;
begin
  if not crm_is_agent() then raise exception 'agent only'; end if;
  if coalesce(p->>'full_name','') = '' then
    raise exception 'full_name is required';
  end if;
  if coalesce(p->>'organization_id','') = '' then
    raise exception 'organization_id is required (use crm_agent_search or crm_agent_insert_organization first)';
  end if;
  insert into crm_contacts (organization_id, full_name, designation, email,
      phone, whatsapp, is_primary, notes, created_by, updated_by)
  values ((p->>'organization_id')::uuid, p->>'full_name', p->>'designation',
      p->>'email', p->>'phone', p->>'whatsapp',
      coalesce((p->>'is_primary')::boolean, false), p->>'notes',
      auth.uid(), auth.uid())
  returning id into v_id;
  perform crm_agent_audit('agent_insert', 'crm_contacts', v_id::text, p);
  return jsonb_build_object('id', v_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_agent_insert_enquiry(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid; v_num text;
begin
  if not crm_is_agent() then raise exception 'agent only'; end if;
  if coalesce(p->>'title','') = '' then
    raise exception 'title is required';
  end if;
  v_num := crm_agent_next_number('enquiry');
  insert into crm_enquiries (enquiry_number, organization_id, contact_id,
      enquiry_type, title, requirement_detail, location, country,
      estimated_budget, budget_currency, required_by_date, urgency, priority,
      source, submitter_name, submitter_email, submitter_phone,
      submitter_company, followup_date, quotation_required, status,
      created_by, updated_by)
  values (v_num, nullif(p->>'organization_id','')::uuid,
      nullif(p->>'contact_id','')::uuid, p->>'enquiry_type', p->>'title',
      p->>'requirement_detail', p->>'location', p->>'country',
      nullif(p->>'estimated_budget','')::numeric, p->>'budget_currency',
      nullif(p->>'required_by_date','')::date, p->>'urgency',
      coalesce(p->>'priority','medium'), coalesce(p->>'source','agent'),
      p->>'submitter_name', p->>'submitter_email', p->>'submitter_phone',
      p->>'submitter_company', nullif(p->>'followup_date','')::date,
      coalesce((p->>'quotation_required')::boolean, false),
      coalesce(p->>'status','new'), auth.uid(), auth.uid())
  returning id into v_id;
  perform crm_agent_audit('agent_insert', 'crm_enquiries', v_id::text, p);
  return jsonb_build_object('id', v_id, 'enquiry_number', v_num);
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_agent_insert_organization(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid; v_num text;
begin
  if not crm_is_agent() then raise exception 'agent only'; end if;
  if coalesce(p->>'legal_name','') = '' then
    raise exception 'legal_name is required';
  end if;
  v_num := crm_agent_next_number('org');
  insert into crm_organizations (org_number, legal_name, trading_name,
      business_type, industry, country, city, website, primary_email, phone,
      whatsapp, preferred_currency, classification, status, internal_remarks,
      created_by, updated_by)
  values (v_num, p->>'legal_name', p->>'trading_name', p->>'business_type',
      p->>'industry', p->>'country', p->>'city', p->>'website',
      p->>'primary_email', p->>'phone', p->>'whatsapp',
      p->>'preferred_currency', p->>'classification',
      coalesce(p->>'status','active'), p->>'internal_remarks',
      auth.uid(), auth.uid())
  returning id into v_id;
  perform crm_agent_audit('agent_insert', 'crm_organizations', v_id::text, p);
  return jsonb_build_object('id', v_id, 'org_number', v_num);
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_agent_insert_prospect(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid; v_num text;
begin
  if not crm_is_agent() then raise exception 'agent only'; end if;
  if coalesce(p->>'full_name','') = '' then
    raise exception 'full_name is required';
  end if;
  v_num := crm_agent_next_number('prospect');
  insert into crm_prospects (prospect_number, full_name, company_name,
      designation, email, phone, whatsapp, country, city, industry, website,
      lead_source, product_interest, requirement_summary, estimated_quantity,
      expected_budget, budget_currency, priority, stage, internal_notes,
      next_followup_date, created_by, updated_by)
  values (v_num, p->>'full_name', p->>'company_name', p->>'designation',
      p->>'email', p->>'phone', p->>'whatsapp', p->>'country', p->>'city',
      p->>'industry', p->>'website', coalesce(p->>'lead_source','manual'),
      p->>'product_interest', p->>'requirement_summary',
      p->>'estimated_quantity', nullif(p->>'expected_budget','')::numeric,
      p->>'budget_currency', coalesce(p->>'priority','medium'),
      coalesce(p->>'stage','new'), p->>'internal_notes',
      nullif(p->>'next_followup_date','')::date, auth.uid(), auth.uid())
  returning id into v_id;
  perform crm_agent_audit('agent_insert', 'crm_prospects', v_id::text, p);
  return jsonb_build_object('id', v_id, 'prospect_number', v_num);
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_agent_next_number(p_entity text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year int := extract(year from now())::int;
  v_seq int; v_prefix text;
begin
  if not crm_is_agent() then
    raise exception 'agent only';
  end if;
  select coalesce(value #>> '{}', 'JCO') into v_prefix
    from crm_settings where key = 'numbering_prefix';
  insert into crm_counters (entity, year, last_seq)
       values (p_entity, v_year, 1)
  on conflict (entity, year)
       do update set last_seq = crm_counters.last_seq + 1
  returning last_seq into v_seq;
  return format('%s-%s-%s-%s', v_prefix, upper(p_entity), v_year,
                lpad(v_seq::text, 4, '0'));
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_agent_register_attachment(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;
begin
  if not crm_is_agent() then raise exception 'agent only'; end if;
  if coalesce(p->>'file_path','') not like 'attachments/agent/%' then
    raise exception 'file_path must be under attachments/agent/';
  end if;
  if coalesce(p->>'module','') = '' or coalesce(p->>'record_id','') = '' then
    raise exception 'module and record_id are required';
  end if;
  insert into crm_attachments (module, record_id, file_path, file_name,
      label, content_type, size_bytes, organization_id, document_category,
      document_title, description, visibility_scope, uploaded_by,
      uploaded_by_type, source)
  values (p->>'module', (p->>'record_id')::uuid, p->>'file_path', p->>'file_name',
      p->>'label', p->>'content_type', nullif(p->>'size_bytes','')::bigint,
      nullif(p->>'organization_id','')::uuid, p->>'document_category',
      p->>'document_title', p->>'description',
      coalesce(p->>'visibility_scope','internal'), auth.uid(), 'ai_agent',
      'ai-agent')
  returning id into v_id;
  perform crm_agent_audit('agent_attachment', p->>'module', p->>'record_id', p);
  return jsonb_build_object('id', v_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_agent_search(p_term text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb;
begin
  if not crm_is_agent() then raise exception 'agent only'; end if;
  if length(coalesce(p_term,'')) < 3 then
    raise exception 'search term must be at least 3 characters';
  end if;
  select jsonb_build_object(
    'organizations', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'org_number', org_number, 'legal_name', legal_name,
        'city', city, 'country', country, 'primary_email', primary_email,
        'phone', phone))
      from (select * from crm_organizations
             where deleted_at is null
               and (legal_name ilike '%'||p_term||'%'
                    or trading_name ilike '%'||p_term||'%'
                    or primary_email ilike '%'||p_term||'%'
                    or phone ilike '%'||p_term||'%'
                    or whatsapp ilike '%'||p_term||'%')
             limit 8) o), '[]'::jsonb),
    'contacts', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'full_name', full_name, 'email', email, 'phone', phone,
        'organization_id', organization_id))
      from (select * from crm_contacts
             where deleted_at is null
               and (full_name ilike '%'||p_term||'%'
                    or email ilike '%'||p_term||'%'
                    or phone ilike '%'||p_term||'%'
                    or whatsapp ilike '%'||p_term||'%')
             limit 8) c), '[]'::jsonb),
    'prospects', coalesce((select jsonb_agg(jsonb_build_object(
        'id', id, 'prospect_number', prospect_number, 'full_name', full_name,
        'company_name', company_name, 'email', email, 'phone', phone,
        'stage', stage))
      from (select * from crm_prospects
             where deleted_at is null
               and (full_name ilike '%'||p_term||'%'
                    or company_name ilike '%'||p_term||'%'
                    or email ilike '%'||p_term||'%'
                    or phone ilike '%'||p_term||'%'
                    or whatsapp ilike '%'||p_term||'%')
             limit 8) p), '[]'::jsonb)
  ) into v;
  return v;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_alerts_now()
 RETURNS TABLE(alert_key text, severity text, category text, title text, detail text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_min_margin  numeric := 10;
  v_large_entry numeric := 100000;
  v_emp_cap     numeric := 0;
  v_cur_period  text := to_char(current_date, 'YYYY-MM');
begin
  if not crm_has_role(array['owner','super_admin','ceo','finance_manager']) then
    raise exception 'Alerts are restricted to management.';
  end if;

  select coalesce(nullif(value #>> '{}','')::numeric, 10)     into v_min_margin  from crm_settings where key = 'alert_min_margin_pct';
  select coalesce(nullif(value #>> '{}','')::numeric, 100000) into v_large_entry from crm_settings where key = 'alert_large_entry_pkr';
  select coalesce(nullif(value #>> '{}','')::numeric, 0)      into v_emp_cap     from crm_settings where key = 'alert_max_employee_cost_pkr';

  -- 1 · SUBSCRIPTION RENEWALS (≤30 days warn, ≤7 or overdue critical)
  return query
  select 'renewal:' || r.id || ':' || r.renewal_date,
         case when r.days_to_renewal <= 7 then 'critical' else 'warning' end,
         'Subscription Renewal',
         r.software_name || case when r.days_to_renewal < 0 then ' renewal OVERDUE'
                                 else ' renews in ' || r.days_to_renewal || ' day(s)' end,
         coalesce(r.plan_name,'') || ' · ' || r.currency || ' ' || r.cost || ' / ' || r.billing_cycle
           || ' · ' || r.renewal_date || case when r.auto_renewal then ' · auto-renew ON' else ' · auto-renew OFF' end
  from crm_upcoming_renewals r
  where r.days_to_renewal <= 30;

  -- 2 · BUDGET EXCEEDED
  return query
  select 'budget:' || b.id || ':' || b.period, 'critical', 'Budget Exceeded',
         b.scope || ' over budget for ' || b.period,
         'Budget PKR ' || b.budget || ' · actual PKR '
           || (b.actual_ledger + b.actual_labour + b.modelled_recurring + b.modelled_payroll)
           || ' (includes recurring/payroll modelled at current rates)'
  from crm_budget_vs_actual b
  where (b.actual_ledger + b.actual_labour + b.modelled_recurring + b.modelled_payroll) > b.budget;

  -- 3 · ORDERS LOSING MONEY / 4 · MARGIN BELOW THRESHOLD
  return query
  select 'orderloss:' || c.order_id, 'critical', 'Order Losing Money',
         c.order_number || ' is EBITDA-negative ('
           || case when c.allocated_actual > 0 then 'actual model' else 'notional model' end || ')',
         'Revenue ' || c.currency || ' ' || c.revenue || ' · EBITDA '
           || case when c.allocated_actual > 0 then c.ebitda_actual else c.ebitda_notional end
  from crm_order_costing_actual c
  where case when c.allocated_actual > 0 then c.ebitda_actual else c.ebitda_notional end < 0;

  return query
  select 'lowmargin:' || c.order_id, 'warning', 'Margin Below Threshold',
         c.order_number || ' margin below ' || v_min_margin || '%',
         'Margin '
           || case when c.allocated_actual > 0 then coalesce(c.ebitda_actual_margin_pct, 0)
                   else round(c.ebitda_notional / nullif(c.revenue,0) * 100, 2) end
           || '% (' || case when c.allocated_actual > 0 then 'actual' else 'notional' end || ' model)'
  from crm_order_costing_actual c
  where c.revenue > 0
    and case when c.allocated_actual > 0 then coalesce(c.ebitda_actual_margin_pct, 0)
             else round(c.ebitda_notional / nullif(c.revenue,0) * 100, 2) end >= 0
    and case when c.allocated_actual > 0 then coalesce(c.ebitda_actual_margin_pct, 0)
             else round(c.ebitda_notional / nullif(c.revenue,0) * 100, 2) end < v_min_margin;

  -- 5 · COMPANY MONTH WITH NEGATIVE ACTUAL EBITDA (complete months, last 6)
  return query
  select 'negmonth:' || p.period, 'critical', 'Negative EBITDA',
         'Company EBITDA (actual) negative in ' || p.period,
         'EBITDA actual PKR ' || p.ebitda_actual || ' · gross profit ' || p.gross_profit
           || ' · allocated ' || p.allocated_overheads
  from crm_pl_actual_monthly p
  where p.complete and p.ebitda_actual < 0
    and p.period >= to_char(current_date - interval '6 months', 'YYYY-MM');

  -- 6 · EXPENSE SPIKE (needs 3 real prior months; >150% of their average)
  return query
  select 'spike:' || v_cur_period, 'warning', 'Expense Spike',
         'This month''s ledger expenses exceed 150% of the 3-month average',
         'Current PKR ' || cur.t || ' vs trailing average PKR ' || round(hist.avg_t, 0)
  from (select coalesce(ledger_total, 0) as t from crm_expense_ledger_monthly where period = v_cur_period) cur,
       (select avg(ledger_total) as avg_t, count(*) as n
          from crm_expense_ledger_monthly
         where period < v_cur_period
           and period >= to_char(current_date - interval '4 months', 'YYYY-MM')
           and ledger_total > 0) hist
  where hist.n >= 3 and hist.avg_t > 0 and cur.t > hist.avg_t * 1.5;

  -- 7 · DUPLICATE EXPENSES (same amount + date + category, last 60 days)
  return query
  select 'dupexp:' || e.expense_date || ':' || e.amount || ':' || e.category, 'warning', 'Duplicate Expense',
         count(*) || ' identical ledger entries on ' || e.expense_date,
         e.category || ' · ' || e.currency || ' ' || e.amount || ' · ' || string_agg(coalesce(e.expense_number, left(e.description, 20)), ', ')
  from crm_expenses e
  where e.deleted_at is null and e.expense_date >= current_date - 60
  group by e.expense_date, e.amount, e.category, e.currency
  having count(*) > 1;

  -- 8 · SUSPICIOUS / LARGE ENTRIES (last 30 days, at/above threshold)
  return query
  select 'large:' || d.id, 'warning', 'Large Entry',
         'Daily entry of ' || d.currency || ' ' || d.amount || ' (' || d.status || ')',
         coalesce(d.entry_number, '') || ' · ' || d.entry_date || ' · ' || left(d.description, 60)
  from crm_daily_entries d
  where d.status <> 'rejected'
    and d.entry_date >= current_date - 30
    and d.currency = 'PKR' and d.amount >= v_large_entry;

  -- 9 · EMPLOYEE COST ABOVE CAP (only when the Owner sets a cap)
  if v_emp_cap > 0 then
    return query
    select 'empcost:' || r.id, 'warning', 'Employee Cost Above Cap',
           r.employee_name || ' costs PKR ' || r.total_monthly_cost || ' / month',
           'Cap PKR ' || v_emp_cap || ' · salary ' || r.monthly_salary
             || ' · allowances ' || r.allowances_monthly
    from crm_employee_cost_rates r
    where r.status = 'active' and r.currency = 'PKR' and r.total_monthly_cost > v_emp_cap;
  end if;

  -- 10 · ORDERS WITH NO INVOICED REVENUE (14+ days old)
  return query
  select 'noinv:' || c.order_id, 'info', 'No Invoiced Revenue',
         c.order_number || ' has no invoiced revenue recorded',
         'Order date ' || c.order_date || ' — invoice it or close it out'
  from crm_order_costing_actual c
  where coalesce(c.revenue, 0) = 0 and c.order_date < current_date - 14;

  -- 11 · PENDING APPROVALS (aging → warning; fresh → info)
  return query
  select 'pending:' || v_cur_period,
         case when min(d.created_at) < now() - interval '3 days' then 'warning' else 'info' end,
         'Pending Approvals',
         count(*) || ' daily entr' || case when count(*) = 1 then 'y' else 'ies' end || ' awaiting review',
         'Oldest submitted ' || to_char(min(d.created_at), 'YYYY-MM-DD') || ' · total PKR '
           || coalesce(sum(d.amount) filter (where d.currency = 'PKR'), 0)
  from crm_daily_entries d
  where d.status = 'pending'
  having count(*) > 0;

  return;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_allocation_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_pay crm_payments%rowtype; v_inv_org uuid; v_allocated numeric;
begin
  select * into v_pay from crm_payments where id = new.payment_id and deleted_at is null;
  if not found then raise exception 'Payment not found'; end if;
  select organization_id into v_inv_org from crm_invoices
   where id = new.invoice_id and deleted_at is null;
  if not found then raise exception 'Invoice not found'; end if;
  if v_inv_org <> v_pay.organization_id then
    raise exception 'Payment and invoice belong to different organizations';
  end if;
  select coalesce(sum(amount),0) into v_allocated
    from crm_payment_allocations
   where payment_id = new.payment_id and id is distinct from new.id;
  if v_allocated + new.amount > v_pay.amount then
    raise exception 'Allocation (%.2f) exceeds unallocated payment balance (%.2f)',
      new.amount, v_pay.amount - v_allocated;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_allocations_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform crm_apply_allocation_totals(coalesce(new.invoice_id, old.invoice_id));
  return coalesce(new, old);
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_apply_allocation_totals(p_invoice_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_paid numeric(16,2); v_total numeric(16,2); v_due date; v_status text;
begin
  select coalesce(sum(a.amount),0) into v_paid
    from crm_payment_allocations a
    join crm_payments p on p.id = a.payment_id and p.deleted_at is null
   where a.invoice_id = p_invoice_id;
  select total, due_date, status into v_total, v_due, v_status
    from crm_invoices where id = p_invoice_id;
  update crm_invoices set
    paid_amount = v_paid,
    outstanding = greatest(v_total - v_paid, 0),
    status = case
      when v_status in ('cancelled','written_off','refunded','disputed','draft','pending_approval') then v_status
      when v_paid >= v_total and v_total > 0 then 'paid'
      when v_paid > 0 then 'partially_paid'
      when v_due is not null and v_due < current_date then 'overdue'
      else 'issued' end
  where id = p_invoice_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_apply_quotation_validity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_days int;
begin
  if new.status = 'issued' and old.status is distinct from 'issued'
     and new.expiry_date is null then
    select coalesce((value #>> '{}')::int, 30) into v_days
      from crm_settings where key = 'quotation_validity_days';
    new.expiry_date := coalesce(new.issue_date, current_date) + coalesce(v_days,30);
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_att_enforce()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pol public.crm_attachment_policy%rowtype;
        ext text;
        is_image boolean;
        cap bigint;
        is_client boolean := not (public.crm_is_staff() or public.crm_is_agent());
begin
  select * into pol from public.crm_attachment_policy limit 1;

  ext := lower(coalesce(new.file_extension,
           nullif(regexp_replace(coalesce(new.file_name,''), '^.*\.', ''), coalesce(new.file_name,''))));
  new.file_extension := ext;

  if ext is null or ext = '' then
    raise exception 'File has no extension — not permitted.';
  end if;
  if ext = any (pol.blocked_extensions) then
    raise exception 'File type ".%" is blocked by policy.', ext;
  end if;
  if not (ext = any (pol.allowed_extensions)) then
    raise exception 'File type ".%" is not on the approved list.', ext;
  end if;

  is_image := ext in ('png','jpg','jpeg','webp');
  cap := case when is_client then pol.max_client_bytes
              when is_image  then pol.max_image_bytes
              else pol.max_document_bytes end;
  if coalesce(new.size_bytes,0) > cap then
    raise exception 'File exceeds the % MB limit.', round(cap/1048576.0,1);
  end if;

  -- identity stamping (server-side truth, ignore client-supplied values)
  new.uploaded_by      := auth.uid();
  new.uploaded_by_type := case when public.crm_is_agent() then 'ai_agent' when is_client then 'client' else 'staff' end;

  -- clients: force safe values regardless of payload
  if is_client then
    new.visibility_scope := 'client_uploaded';
    new.source           := 'portal';
    new.is_confidential  := false;
    new.approval_status  := 'pending';
  end if;

  new.organization_id := coalesce(new.organization_id,
                                  public.crm_att_resolve_org(new.module, new.record_id::text));

  -- clients may only attach into their own organization
  if is_client and (new.organization_id is null or not exists (
      select 1 from public.crm_portal_members pm
       where pm.user_id = auth.uid() and pm.organization_id = new.organization_id)) then
    raise exception 'You can only attach documents to your own records.';
  end if;

  new.original_file_name := coalesce(new.original_file_name, new.file_name);
  new.document_title     := coalesce(new.document_title, new.label, new.file_name);
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_att_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_op = 'INSERT' then
    insert into public.crm_attachment_events (attachment_id,event_type,detail,actor,actor_type)
    values (new.id,'upload', new.module||'/'||new.record_id||' · '||coalesce(new.file_name,''),
            auth.uid(), new.uploaded_by_type);
  elsif tg_op = 'UPDATE' then
    if new.deleted_at is not null and old.deleted_at is null then
      insert into public.crm_attachment_events (attachment_id,event_type,detail,actor)
      values (new.id,'archive', coalesce(new.file_name,''), auth.uid());
    elsif new.deleted_at is null and old.deleted_at is not null then
      insert into public.crm_attachment_events (attachment_id,event_type,detail,actor)
      values (new.id,'restore', coalesce(new.file_name,''), auth.uid());
    end if;
    if new.visibility_scope is distinct from old.visibility_scope then
      insert into public.crm_attachment_events (attachment_id,event_type,detail,actor)
      values (new.id,'visibility_change', old.visibility_scope||' → '||new.visibility_scope, auth.uid());
    end if;
    if new.document_category is distinct from old.document_category then
      insert into public.crm_attachment_events (attachment_id,event_type,detail,actor)
      values (new.id,'recategorize', old.document_category||' → '||new.document_category, auth.uid());
    end if;
    if new.approval_status is distinct from old.approval_status
       and new.approval_status in ('approved','rejected') then
      insert into public.crm_attachment_events (attachment_id,event_type,detail,actor)
      values (new.id, case new.approval_status when 'approved' then 'approve' else 'reject' end,
              coalesce(new.file_name,''), auth.uid());
    end if;
  end if;
  return coalesce(new, old);
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_att_resolve_org(p_module text, p_record_id text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v uuid;
begin
  -- best effort: each lookup isolated so a missing table/column never aborts
  begin
    if p_module = 'organizations' then
      v := p_record_id::uuid;
    elsif p_module in ('enquiries','opportunities','quotations','orders','invoices',
                       'payments','projects','shipments','contacts','cost_sheets') then
      execute format('select organization_id from public.crm_%I where id = $1', p_module)
        into v using p_record_id::uuid;
    end if;
  exception when others then v := null;
  end;
  return v;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_att_touch()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin new.updated_at := now(); return new; end $function$
;

CREATE OR REPLACE FUNCTION public.crm_audit_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_row jsonb;
  v_id  text;
begin
  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_id  := coalesce(v_row ->> 'id', v_row ->> 'key', v_row ->> 'cost_pool', tg_table_name);

  insert into crm_audit_logs (action, entity, entity_id, after_value)
  values (tg_op, tg_table_name, v_id, v_row);

  return case when tg_op = 'DELETE' then old else new end;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_block_role_conflict()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if tg_table_name = 'crm_staff_roles' then
    if exists (select 1 from crm_portal_members where user_id = new.user_id) then
      raise exception 'This account is a CLIENT portal member — it cannot be granted a staff role. Remove the portal membership first if this person has genuinely joined the firm.';
    end if;
  elsif tg_table_name = 'crm_portal_members' then
    if exists (select 1 from crm_staff_roles where user_id = new.user_id) then
      raise exception 'This account holds STAFF roles — it cannot be linked to a client organization. Remove the staff roles first.';
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_cc_productivity()
 RETURNS TABLE(person text, opportunities bigint, quotations bigint, orders bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(e.full_name, split_part(u.email,'@',1)) as person,
         count(distinct o.id)  as opportunities,
         count(distinct q.id)  as quotations,
         count(distinct d.id)  as orders
  from auth.users u
  join crm_staff_roles r on r.user_id = u.id
  left join crm_employee_profiles e on e.user_id = u.id
  left join crm_opportunities o on o.created_by = u.id and o.deleted_at is null
        and o.created_at >= date_trunc('year', current_date)
  left join crm_quotations q on q.created_by = u.id and q.deleted_at is null
        and q.created_at >= date_trunc('year', current_date)
  left join crm_orders d on d.created_by = u.id and d.deleted_at is null
        and d.created_at >= date_trunc('year', current_date)
  where crm_has_role(array['owner','super_admin','ceo'])
  group by u.id, u.email, e.full_name
  order by 2 desc, 3 desc;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_client_quotation_action(p_quotation_id uuid, p_action text, p_comment text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_q crm_quotations%rowtype;
begin
  select * into v_q from crm_quotations where id = p_quotation_id and deleted_at is null;
  if not found then raise exception 'Quotation not found'; end if;
  if v_q.organization_id not in (select crm_my_org_ids()) and not crm_is_staff() then
    raise exception 'Not authorized';
  end if;
  if v_q.status not in ('issued','viewed') then
    raise exception 'Quotation is not open for a decision (current: %)', v_q.status;
  end if;
  if p_action not in ('accepted','rejected','revision_requested') then
    raise exception 'Invalid action';
  end if;
  update crm_quotations
     set status = p_action,
         client_action_by = auth.uid(),
         client_action_at = now(),
         client_action_comment = p_comment
   where id = p_quotation_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_client_tracking(p_order_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare j json;
begin
  if not exists (select 1 from public.crm_orders o
                  join public.crm_portal_members pm on pm.organization_id = o.organization_id
                 where o.id = p_order_id and pm.user_id = auth.uid()) then
    raise exception 'Not authorised.';
  end if;
  select json_build_object(
    'progress', t.progress_percentage,
    'expected_completion', coalesce(t.revised_completion_date, t.expected_completion_date),
    'is_delayed', t.is_delayed,
    'next_milestone', case when exists (select 1 from crm_order_milestones m
                                         where m.order_id = p_order_id and m.client_visible
                                           and m.milestone_label = t.next_milestone)
                           then t.next_milestone end,
    'milestones', (select coalesce(json_agg(json_build_object(
                     'label', m.milestone_label, 'status', m.status,
                     'due', m.planned_due_at, 'completed_at', m.completed_at,
                     'update', m.client_update) order by m.sequence_number), '[]'::json)
                     from crm_order_milestones m
                    where m.order_id = p_order_id and m.client_visible))
    into j
    from crm_order_tracking t where t.order_id = p_order_id;
  return coalesce(j, json_build_object('milestones','[]'::json));
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_convert_opportunity_to_quotation(p_opportunity_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_o crm_opportunities%rowtype; v_qtn uuid;
begin
  if not crm_is_staff() then raise exception 'Not authorized'; end if;
  select * into v_o from crm_opportunities
   where id = p_opportunity_id and deleted_at is null for update;
  if not found then raise exception 'Opportunity not found'; end if;
  if v_o.organization_id is null then
    raise exception 'Link this opportunity to a client organization first';
  end if;
  if v_o.converted_quotation_id is not null then
    raise exception 'A quotation already exists for this opportunity';
  end if;

  insert into crm_quotations
    (quotation_number, organization_id, contact_id, enquiry_id, service_id,
     title, currency, status, created_by)
  values
    (crm_next_number('qtn'), v_o.organization_id, v_o.contact_id,
     v_o.enquiry_id, v_o.service_id, v_o.title, v_o.currency, 'draft', auth.uid())
  returning id into v_qtn;

  update crm_opportunities
     set converted_quotation_id = v_qtn,
         stage = case when stage in ('qualification','needs_analysis',
                       'solution_design','costing') then 'proposal_preparation'
                      else stage end
   where id = p_opportunity_id;

  insert into crm_opportunity_activity (opportunity_id, kind, body, created_by)
  values (p_opportunity_id, 'system', 'Draft quotation created', auth.uid());
  return v_qtn;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_convert_prospect(p_prospect_id uuid, p_create_enquiry boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_p        crm_prospects%rowtype;
  v_org_id   uuid;
  v_ct_id    uuid;
  v_enq_id   uuid;
begin
  if not crm_has_role(array['super_admin','ceo','business_development',
                            'account_manager','operations_manager']) then
    raise exception 'Not authorized to convert prospects';
  end if;

  select * into v_p from crm_prospects
   where id = p_prospect_id and deleted_at is null for update;
  if not found then raise exception 'Prospect not found'; end if;
  if v_p.converted_org_id is not null then
    raise exception 'Prospect already converted';
  end if;

  insert into crm_organizations
    (org_number, legal_name, industry, country, city, website,
     primary_email, phone, whatsapp, created_by)
  values
    (crm_next_number('org'), coalesce(v_p.company_name, v_p.full_name),
     v_p.industry, v_p.country, v_p.city, v_p.website,
     v_p.email, v_p.phone, v_p.whatsapp, auth.uid())
  returning id into v_org_id;

  insert into crm_contacts
    (organization_id, full_name, designation, email, phone, whatsapp, is_primary, created_by)
  values
    (v_org_id, v_p.full_name, v_p.designation, v_p.email, v_p.phone, v_p.whatsapp, true, auth.uid())
  returning id into v_ct_id;

  if p_create_enquiry then
    insert into crm_enquiries
      (enquiry_number, organization_id, contact_id, service_id, title,
       requirement_detail, country, estimated_budget, budget_currency,
       source, status, quotation_required, created_by)
    values
      (crm_next_number('enq'), v_org_id, v_ct_id, v_p.interested_service_id,
       coalesce('Enquiry — ' || v_p.company_name, 'Enquiry — ' || v_p.full_name),
       v_p.requirement_summary, v_p.country, v_p.expected_budget,
       v_p.budget_currency, 'prospect_conversion', 'new',
       (v_p.stage in ('quotation_required','quotation_sent')), auth.uid())
    returning id into v_enq_id;
  end if;

  update crm_prospects
     set stage = 'won',
         converted_org_id = v_org_id,
         converted_contact_id = v_ct_id,
         converted_enquiry_id = v_enq_id,
         converted_at = now()
   where id = p_prospect_id;

  return jsonb_build_object('organization_id', v_org_id,
                            'contact_id', v_ct_id,
                            'enquiry_id', v_enq_id);
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_convert_quotation_to_order(p_quotation_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_q crm_quotations%rowtype; v_order_id uuid; v_type text;
begin
  if not crm_has_role(array['super_admin','ceo','operations_manager',
                            'finance_manager','trade_sourcing_manager']) then
    raise exception 'Not authorized to convert quotations to orders';
  end if;
  select * into v_q from crm_quotations
   where id = p_quotation_id and deleted_at is null for update;
  if not found then raise exception 'Quotation not found'; end if;
  if v_q.status <> 'accepted' then
    raise exception 'Only an accepted quotation can be converted (current: %)', v_q.status;
  end if;

  select case when e.enquiry_type in ('sourcing','customs') then 'trade' else 'service' end
    into v_type from crm_enquiries e where e.id = v_q.enquiry_id;

  insert into crm_orders
    (order_number, organization_id, quotation_id, enquiry_id, cost_sheet_id,
     service_id, order_type, title, currency, order_value,
     payment_terms, delivery_terms, incoterm, status, created_by)
  values
    (crm_next_number('ord'), v_q.organization_id, v_q.id, v_q.enquiry_id,
     v_q.cost_sheet_id, v_q.service_id, coalesce(v_type,'trade'),
     v_q.title, v_q.currency, v_q.total,
     v_q.payment_terms, v_q.delivery_terms, v_q.incoterm, 'confirmed', auth.uid())
  returning id into v_order_id;

  insert into crm_order_items (order_id, description, quantity, unit, unit_price, sort_order)
  select v_order_id, description, quantity, unit, unit_price, sort_order
    from crm_quotation_items where quotation_id = p_quotation_id;

  insert into crm_order_events (order_id, kind, body, visibility, created_by)
  values (v_order_id, 'system',
          'Order created from accepted quotation ' || v_q.quotation_number || ' v' || v_q.version,
          'client_visible', auth.uid());

  update crm_quotations set status='converted_to_order' where id = p_quotation_id;
  if v_q.enquiry_id is not null then
    update crm_enquiries set status='converted_to_order' where id = v_q.enquiry_id;
  end if;
  return v_order_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_cost_line_options(p_service_tag text DEFAULT NULL::text)
 RETURNS TABLE(id uuid, code text, name text, category_code text, category_name text, letter text, line_kind text, default_unit text, default_borne_by text, default_rate numeric, sort_order integer, billing_basis text, basis_name text, qty_label text, rate_label text, needs_qty boolean, allows_resources boolean, allows_overtime boolean, is_percentage boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select l.id, l.code, l.name, l.category_code, c.name, c.letter,
         l.line_kind, l.default_unit, l.default_borne_by, l.default_rate,
         (c.sort_order * 1000) + l.sort_order,
         l.billing_basis, b.name, b.qty_label, b.rate_label,
         b.needs_qty, b.allows_resources, b.allows_overtime, b.is_percentage
    from crm_cost_lines l
    join crm_cost_categories c on c.code = l.category_code
    left join crm_billing_bases b on b.code = l.billing_basis
   where crm_is_staff()
     and l.is_active and c.is_active
     and ( p_service_tag is null
           or 'all' = any(l.service_tags)
           or p_service_tag = any(l.service_tags) )
   order by (c.sort_order * 1000) + l.sort_order;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_create_opportunity_from_enquiry(p_enquiry_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_e crm_enquiries%rowtype; v_opp uuid;
begin
  if not crm_has_role(array['owner','super_admin','ceo','business_development',
                            'account_manager','operations_manager']) then
    raise exception 'Not authorized to create opportunities';
  end if;
  select * into v_e from crm_enquiries
   where id = p_enquiry_id and deleted_at is null for update;
  if not found then raise exception 'Enquiry not found'; end if;
  if exists (select 1 from crm_opportunities
              where enquiry_id = p_enquiry_id and deleted_at is null) then
    raise exception 'An opportunity already exists for this enquiry';
  end if;

  insert into crm_opportunities
    (opportunity_number, enquiry_id, organization_id, contact_id, service_id,
     title, description, estimated_value, currency, priority, created_by)
  values
    (crm_next_number('opp'), v_e.id, v_e.organization_id, v_e.contact_id,
     v_e.service_id, v_e.title, v_e.requirement_detail,
     v_e.estimated_budget, coalesce(v_e.budget_currency,'PKR'),
     v_e.priority, auth.uid())
  returning id into v_opp;

  update crm_enquiries set status = 'converted_to_opportunity'
   where id = p_enquiry_id and status in ('new','under_review','assigned',
         'information_required','feasibility_assessment');

  insert into crm_opportunity_activity (opportunity_id, kind, body, created_by)
  values (v_opp, 'system',
          'Created from enquiry ' || coalesce(v_e.enquiry_number,''), auth.uid());
  return v_opp;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_decide_quotation(p_quotation_id uuid, p_decision text, p_comments text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not crm_has_role(array['super_admin','ceo']) then
    raise exception 'Only CEO / Super Admin may approve quotations';
  end if;
  if p_decision not in ('approved','rejected','revision_requested') then
    raise exception 'Invalid decision';
  end if;
  update crm_quotation_approvals
     set decided_by=auth.uid(), decided_at=now(), decision=p_decision, comments=p_comments
   where quotation_id = p_quotation_id and decided_at is null;
  update crm_quotations
     set approval_status = case when p_decision='approved' then 'approved' else 'rejected' end,
         status = case when p_decision='approved' then 'approved'
                       when p_decision='rejected' then 'draft'
                       else 'costing_review' end,
         approved_by = case when p_decision='approved' then auth.uid() else null end,
         approved_at = case when p_decision='approved' then now() else null end
   where id = p_quotation_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_delete_custom_field(p_module text, p_field_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not crm_has_role(array['owner']) then
    raise exception 'Only the Owner may delete custom fields';
  end if;
  delete from crm_custom_values where module = p_module and field_key = p_field_id;
  delete from crm_field_config
   where module = p_module and field_id = p_field_id and is_custom = true;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_eligible_rms()
 RETURNS TABLE(user_id uuid, full_name text, active_orders bigint, over_threshold boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare name_col text; active_col text; q text; thr int;
begin
  if not public.crm_is_staff() then raise exception 'Staff only.'; end if;
  select max_active_orders into thr from public.crm_rm_policy limit 1;
  thr := coalesce(thr, 8);

  select column_name into name_col from information_schema.columns
   where table_schema='public' and table_name='crm_employee_profiles'
     and column_name in ('full_name','name','display_name') limit 1;
  select column_name into active_col from information_schema.columns
   where table_schema='public' and table_name='crm_employee_profiles'
     and column_name in ('is_active','active') limit 1;

  q := format($f$
    select sr.user_id,
           coalesce(%s, split_part(u.email,'@',1), 'Staff member') as full_name,
           count(o.id) as active_orders,
           count(o.id) >= %s as over_threshold
      from (select distinct user_id from public.crm_staff_roles
             where role in ('owner','super_admin','ceo','account_manager','business_development',
                            'project_manager','operations_manager','trade_sourcing_manager',
                            'customs_manager','consultancy_manager')) sr
      left join public.crm_employee_profiles ep on ep.user_id = sr.user_id
      left join auth.users u on u.id = sr.user_id
      left join public.crm_orders o
             on o.relationship_manager_id = sr.user_id
            and coalesce(o.status,'') not in ('completed','cancelled','refunded','closed')
     %s
     group by sr.user_id, %s, u.email
     order by 2 $f$,
    case when name_col is not null then 'max(ep.'||quote_ident(name_col)||')' else 'null::text' end,
    thr,
    case when active_col is not null then 'where coalesce(ep.'||quote_ident(active_col)||', true)' else '' end,
    case when name_col is not null then 'ep.'||quote_ident(name_col) else 'u.email' end);
  return query execute q;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_employee_cost_track()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into crm_employee_cost_history (employee_cost_id, action, old_data, changed_by)
  values (old.id,
          case when new.deleted_at is not null and old.deleted_at is null then 'delete'
               else 'update' end,
          to_jsonb(old), auth.uid());
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_enquiry_attribution()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_conf text;
begin
  v_conf := case
    when new.click_id is not null and new.click_id <> ''            then 'high'    -- a real ad click id
    when coalesce(new.utm_source,'') <> ''                          then 'high'    -- explicit campaign tag
    when coalesce(new.referrer,'') <> ''                            then 'medium'  -- referrer only
    when coalesce(new.landing_page,'') <> ''                        then 'low'     -- landed, no origin
    else 'unknown'                                                                  -- nothing captured
  end;

  insert into analytics_attribution (
    entity, entity_id, org_id, first_touch, last_touch,
    utm_source, utm_medium, utm_campaign, utm_content, utm_term,
    referrer, landing_page, click_id, confidence)
  values (
    'enquiry', new.id, new.organization_id,
    coalesce(new.first_touch, '{}'::jsonb), coalesce(new.last_touch, '{}'::jsonb),
    new.utm_source, new.utm_medium, new.utm_campaign, new.utm_content, new.utm_term,
    new.referrer, new.landing_page, new.click_id, v_conf)
  on conflict (entity, entity_id) do update set
    utm_source = excluded.utm_source, utm_medium = excluded.utm_medium,
    utm_campaign = excluded.utm_campaign, referrer = excluded.referrer,
    landing_page = excluded.landing_page, click_id = excluded.click_id,
    first_touch = excluded.first_touch, last_touch = excluded.last_touch,
    confidence = excluded.confidence;

  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_enquiry_autonumber()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_seq int; v_prefix text;
begin
  if new.enquiry_number is null then
    select coalesce(value #>> '{}', 'JCO') into v_prefix
      from crm_settings where key = 'numbering_prefix';
    insert into crm_counters (entity, year, last_seq)
         values ('enq', extract(year from now())::int, 1)
    on conflict (entity, year)
         do update set last_seq = crm_counters.last_seq + 1
    returning last_seq into v_seq;
    new.enquiry_number := format('%s-ENQ-%s-%s', v_prefix,
      extract(year from now())::int, lpad(v_seq::text, 4, '0'));
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_enquiry_status_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status is distinct from old.status then
    insert into crm_enquiry_activity (enquiry_id, kind, old_value, new_value, visibility, created_by)
    values (new.id, 'status_change', old.status, new.status, 'internal_only', auth.uid());
  end if;
  if new.assigned_to is distinct from old.assigned_to then
    insert into crm_enquiry_activity (enquiry_id, kind, old_value, new_value, visibility, created_by)
    values (new.id, 'assignment', old.assigned_to::text, new.assigned_to::text, 'internal_only', auth.uid());
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_fixed_expense_track()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into crm_fixed_expense_history (fixed_expense_id, action, old_data, changed_by)
  values (old.id,
          case when new.deleted_at is not null and old.deleted_at is null then 'delete'
               when new.status = 'archived' and old.status <> 'archived' then 'archive'
               else 'update' end,
          to_jsonb(old), auth.uid());
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_generate_milestones(p_order_id uuid, p_template_id uuid DEFAULT NULL::uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare tid uuid; d date := current_date; n int := 0; s record; rm uuid; ord_no text;
begin
  if not public.crm_is_staff() and current_setting('jco.sys', true) <> '1' then
    raise exception 'Staff only.';
  end if;
  if exists (select 1 from public.crm_order_milestones where order_id = p_order_id) then
    raise exception 'Milestones already exist for this order. Use the tracking screen to adjust them.';
  end if;
  tid := coalesce(p_template_id, public.crm_resolve_template(p_order_id));
  if tid is null then raise exception 'No active tracking template found.'; end if;

  for s in select * from public.crm_tracking_template_steps
            where template_id = tid order by sequence_number loop
    d := d + s.default_duration_days;
    insert into public.crm_order_milestones
      (order_id, milestone_code, milestone_label, sequence_number,
       planned_start_at, planned_due_at, weight, client_visible,
       evidence_required, status, actual_start_at, completion_percentage)
    values
      (p_order_id, s.step_code, s.step_label, s.sequence_number,
       case when s.sequence_number = 1 then current_date else d - s.default_duration_days end,
       d, s.weight, s.client_visible, s.requires_attachment,
       case when s.sequence_number = 1 then 'in_progress' else 'pending' end,
       case when s.sequence_number = 1 then now() else null end,
       0);
    n := n + 1;
  end loop;

  insert into public.crm_order_tracking (order_id, tracking_template_id, expected_completion_date, updated_by)
  values (p_order_id, tid, d, auth.uid())
  on conflict (order_id) do update
    set tracking_template_id = excluded.tracking_template_id,
        expected_completion_date = excluded.expected_completion_date,
        updated_at = now();

  perform public.crm_recalc_tracking(p_order_id);

  begin
    select relationship_manager_id, coalesce(order_number, left(id::text,8))
      into rm, ord_no from public.crm_orders where id = p_order_id;
    if rm is not null then
      perform public.crm_notify(rm, 'Tracking plan created',
        n||' milestones generated for order '||ord_no||'. First milestone is now active.',
        'crm-orders.html', 'tracking');
    end if;
  exception when others then null;
  end;
  return n;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_has_role(roles text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when crm_is_suspended() then false else
    is_admin()
    or exists (select 1 from crm_staff_roles
                where user_id = auth.uid() and role = 'owner')
    or exists (select 1 from crm_staff_roles
                where user_id = auth.uid() and role = any(roles))
  end;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_invoice_items_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform crm_invoice_recalc(coalesce(new.invoice_id, old.invoice_id));
  return coalesce(new, old);
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_invoice_items_lock_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_status text;
begin
  select status into v_status from crm_invoices
   where id = coalesce(new.invoice_id, old.invoice_id);
  if v_status in ('issued','partially_paid','paid','overdue','refunded','written_off') then
    raise exception 'Items of an issued invoice are locked. Issue a credit or debit note.';
  end if;
  return coalesce(new, old);
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_invoice_lock_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  if old.status in ('issued','partially_paid','paid','overdue','refunded','written_off') then
    if new.discount_pct is distinct from old.discount_pct
       or new.tax_pct is distinct from old.tax_pct
       or new.freight_amount is distinct from old.freight_amount
       or new.other_charges is distinct from old.other_charges
       or new.currency is distinct from old.currency then
      raise exception 'Issued invoice financials are locked. Issue a credit or debit note.';
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_invoice_rates_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.discount_pct is distinct from old.discount_pct
     or new.tax_pct is distinct from old.tax_pct
     or new.freight_amount is distinct from old.freight_amount
     or new.other_charges is distinct from old.other_charges then
    perform crm_invoice_recalc(new.id);
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_invoice_recalc(p_invoice_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_sub numeric(16,2);
begin
  select coalesce(sum(line_total),0) into v_sub
    from crm_invoice_items where invoice_id = p_invoice_id;
  update crm_invoices set
    subtotal        = v_sub,
    discount_amount = round(v_sub * coalesce(discount_pct,0)/100.0, 2),
    tax_amount      = round((v_sub - round(v_sub * coalesce(discount_pct,0)/100.0, 2))
                            * coalesce(tax_pct,0)/100.0, 2),
    total           = round(v_sub
                        - round(v_sub * coalesce(discount_pct,0)/100.0, 2)
                        + round((v_sub - round(v_sub * coalesce(discount_pct,0)/100.0, 2))
                                * coalesce(tax_pct,0)/100.0, 2)
                        + coalesce(freight_amount,0) + coalesce(other_charges,0), 2),
    outstanding     = greatest(round(v_sub
                        - round(v_sub * coalesce(discount_pct,0)/100.0, 2)
                        + round((v_sub - round(v_sub * coalesce(discount_pct,0)/100.0, 2))
                                * coalesce(tax_pct,0)/100.0, 2)
                        + coalesce(freight_amount,0) + coalesce(other_charges,0), 2)
                        - paid_amount, 0)
  where id = p_invoice_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_is_agent()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from crm_agent_accounts
                  where user_id = auth.uid() and active);
$function$
;

CREATE OR REPLACE FUNCTION public.crm_is_finance()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select crm_has_role(array['super_admin','ceo','finance_manager']);
$function$
;

CREATE OR REPLACE FUNCTION public.crm_is_staff()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from crm_staff_roles   sr where sr.user_id = auth.uid())
     and not exists (select 1 from crm_portal_members pm where pm.user_id = auth.uid());
$function$
;

CREATE OR REPLACE FUNCTION public.crm_is_suspended()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from crm_employee_profiles
                  where user_id = auth.uid() and is_active = false);
$function$
;

CREATE OR REPLACE FUNCTION public.crm_issue_invoice(p_invoice_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_status text; v_total numeric;
begin
  if not crm_is_finance() then raise exception 'Only finance may issue invoices'; end if;
  select status, total into v_status, v_total from crm_invoices
   where id = p_invoice_id and deleted_at is null;
  if v_status is distinct from 'draft' and v_status is distinct from 'pending_approval' then
    raise exception 'Only draft invoices can be issued (current: %)', coalesce(v_status,'?');
  end if;
  if coalesce(v_total,0) <= 0 then raise exception 'Invoice has no items / zero total'; end if;
  update crm_invoices
     set status='issued', approved_by=auth.uid(),
         issue_date=coalesce(issue_date,current_date),
         due_date=coalesce(due_date,current_date+15)
   where id = p_invoice_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_issue_quotation(p_quotation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_status text;
begin
  if not crm_has_role(array['super_admin','ceo','operations_manager','finance_manager']) then
    raise exception 'Not authorized to issue quotations';
  end if;
  select status into v_status from crm_quotations where id = p_quotation_id and deleted_at is null;
  if v_status is distinct from 'approved' then
    raise exception 'Only approved quotations can be issued (current: %)', coalesce(v_status,'?');
  end if;
  update crm_quotations
     set status='issued',
         issue_date = coalesce(issue_date, current_date),
         expiry_date = coalesce(expiry_date, current_date + 30)
   where id = p_quotation_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_list_staff()
 RETURNS TABLE(user_id uuid, email text, full_name text, department text, designation text, roles text[], is_active boolean, approval_limit numeric, quotation_authority boolean, finance_authority boolean, sourcing_authority boolean, project_authority boolean, last_login timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select u.id, u.email::text,
         e.full_name, e.department, e.designation,
         coalesce(array_agg(r.role) filter (where r.role is not null), '{}') as roles,
         coalesce(e.is_active, true),
         e.approval_limit,
         coalesce(e.quotation_authority,false), coalesce(e.finance_authority,false),
         coalesce(e.sourcing_authority,false), coalesce(e.project_authority,false),
         (select max(h.created_at) from crm_login_history h
           where h.user_id = u.id and h.event = 'login')
  from auth.users u
  left join crm_employee_profiles e on e.user_id = u.id
  left join crm_staff_roles r on r.user_id = u.id
  where crm_has_role(array['owner','super_admin','ceo'])
  group by u.id, u.email, e.full_name, e.department, e.designation,
           e.is_active, e.approval_limit, e.quotation_authority,
           e.finance_authority, e.sourcing_authority, e.project_authority;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_log_activity(p_event text, p_entity text DEFAULT NULL::text, p_entity_id uuid DEFAULT NULL::uuid, p_detail text DEFAULT NULL::text, p_user_agent text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then return; end if;
  if p_event not in ('view','print','download','export') then return; end if;
  insert into crm_activity_events (user_id, event, entity, entity_id, detail, user_agent)
  values (auth.uid(), p_event, left(coalesce(p_entity,''),60), p_entity_id,
          left(coalesce(p_detail,''),300), left(coalesce(p_user_agent,''),300));
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_log_login_event(p_event text, p_user_agent text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then return; end if;
  if p_event not in ('login','logout','logout_all','timeout') then return; end if;
  insert into crm_login_history (user_id, event, user_agent)
  values (auth.uid(), p_event, left(coalesce(p_user_agent,''), 300));
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_mark_quotation_viewed(p_quotation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update crm_quotations set status='viewed'
   where id = p_quotation_id and status='issued'
     and (organization_id in (select crm_my_org_ids()) or crm_is_staff());
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_my_employee_cost_id()
 RETURNS TABLE(id uuid, employee_name text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select id, employee_name
    from crm_employee_costs
   where user_id = auth.uid() and deleted_at is null
   limit 1;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_my_enquiry_journey()
 RETURNS TABLE(enquiry_id uuid, enquiry_number text, title text, enquiry_status text, enquiry_date date, quotation_id uuid, quotation_number text, quotation_version integer, quotation_status text, quotation_total numeric, currency text, quotation_issue_date date, order_id uuid, order_number text, order_status text, order_date date, promised_date date)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    e.id, e.enquiry_number, e.title, e.status::text,
    e.created_at::date,
    q.id, q.quotation_number, q.version,
    q.status::text, q.total, q.currency,
    q.issue_date,
    o.id, o.order_number, o.status::text,
    o.order_date, o.promised_date
  from crm_enquiries e
  left join lateral (
    select * from crm_quotations q0
    where q0.enquiry_id = e.id
      and q0.status in ('issued','viewed','accepted','rejected',
                        'revision_requested','converted_to_order')
      and q0.deleted_at is null
    order by q0.version desc, q0.created_at desc
    limit 1
  ) q on true
  left join lateral (
    select * from crm_orders o0
    where o0.quotation_id = q.id and o0.deleted_at is null
    order by o0.created_at desc
    limit 1
  ) o on true
  where e.deleted_at is null
    and e.organization_id in (select crm_my_org_ids())
  order by e.created_at desc;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_my_org_ids()
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select organization_id from crm_portal_members
  where user_id = auth.uid() and is_active = true;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_my_team()
 RETURNS TABLE(user_id uuid, reporting_manager uuid, depth integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with recursive team as (
    select p.user_id, p.reporting_manager, 1 as depth
      from crm_employee_profiles p
     where p.reporting_manager = auth.uid()
    union all
    select p.user_id, p.reporting_manager, t.depth + 1
      from crm_employee_profiles p
      join team t on p.reporting_manager = t.user_id
     where t.depth < 10
  )
  select * from team;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_next_number(p_entity text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_year   int := extract(year from now())::int;
  v_seq    int;
  v_prefix text;
begin
  if not crm_is_staff() then
    raise exception 'Not authorized to generate document numbers';
  end if;
  select coalesce(value #>> '{}', 'JCO') into v_prefix
    from crm_settings where key = 'numbering_prefix';
  insert into crm_counters (entity, year, last_seq)
       values (p_entity, v_year, 1)
  on conflict (entity, year)
       do update set last_seq = crm_counters.last_seq + 1
  returning last_seq into v_seq;
  return format('%s-%s-%s-%s', v_prefix, upper(p_entity), v_year, lpad(v_seq::text, 4, '0'));
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_notify(p_user uuid, p_title text, p_body text DEFAULT NULL::text, p_link text DEFAULT NULL::text, p_kind text DEFAULT 'info'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_user is null then return; end if;
  insert into public.crm_notifications (user_id, title, body, link, kind)
  values (p_user, p_title, p_body, p_link, p_kind);
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_om_after()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform public.crm_recalc_tracking(coalesce(new.order_id, old.order_id));
  return coalesce(new, old);
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_om_before()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    if new.evidence_required and not exists (
        select 1 from public.crm_attachments a
         where a.deleted_at is null
           and ((a.module = 'order_milestones' and a.record_id = new.id::text)
             or (a.module = 'orders' and a.record_id = new.order_id::text))) then
      raise exception 'This milestone requires supporting evidence — attach a document to the order first.';
    end if;
    new.completed_at := now();
    new.completion_percentage := 100;
  end if;
  if new.status = 'in_progress' and old.status = 'pending' and new.actual_start_at is null then
    new.actual_start_at := now();
  end if;
  if new.client_update is distinct from old.client_update and new.client_update is not null then
    update public.crm_order_tracking set last_client_update_at = now()
     where order_id = new.order_id;
  end if;
  new.updated_at := now();
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_opportunity_autoresult()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status is distinct from old.status then
    if new.status in ('accepted','converted_to_order') then
      update crm_opportunities set stage='won'
       where converted_quotation_id = new.id and stage <> 'won' and deleted_at is null;
    elsif new.status = 'rejected' then
      update crm_opportunities set stage='lost',
             loss_reason = coalesce(loss_reason,'Quotation declined by client')
       where converted_quotation_id = new.id
         and stage not in ('won','lost') and deleted_at is null;
    elsif new.status in ('issued','viewed') then
      update crm_opportunities set stage='proposal_sent'
       where converted_quotation_id = new.id
         and stage in ('proposal_preparation','costing') and deleted_at is null;
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_opportunity_stage_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.stage is distinct from old.stage then
    insert into crm_opportunity_activity
      (opportunity_id, kind, old_value, new_value, created_by)
    values (new.id, 'stage_change', old.stage, new.stage, auth.uid());
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_order_autotrack()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if (select auto_assign from public.crm_tracking_policy limit 1) then
    begin
      perform set_config('jco.sys','1', true);
      perform public.crm_generate_milestones(new.id, null);
      perform set_config('jco.sys','0', true);
    exception when others then null;  -- tracking must never block order creation
    end;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_order_client_status(p_status text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case p_status
    when 'draft' then 'Being Prepared'
    when 'confirmed' then 'Confirmed'
    when 'awaiting_advance' then 'Awaiting Advance Payment'
    when 'advance_received' then 'Confirmed'
    when 'supplier_confirmation' then 'In Progress'
    when 'in_production' then 'In Production'
    when 'inspection' then 'Quality Inspection'
    when 'ready_for_dispatch' then 'Ready for Dispatch'
    when 'shipment_booked' then 'Shipment Booked'
    when 'dispatched' then 'Shipped'
    when 'in_transit' then 'In Transit'
    when 'customs_clearance' then 'In Customs Clearance'
    when 'cleared' then 'Customs Cleared'
    when 'local_delivery' then 'Out for Delivery'
    when 'delivered' then 'Delivered'
    when 'completed' then 'Completed'
    when 'on_hold' then 'On Hold'
    when 'cancelled' then 'Cancelled'
    when 'disputed' then 'Under Review'
    when 'refunded' then 'Refunded'
    else 'In Progress' end;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_order_status_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status is distinct from old.status then
    if old.status in ('completed','cancelled','refunded') then
      raise exception 'Order in terminal status % cannot change status', old.status;
    end if;
    insert into crm_order_events (order_id, kind, old_value, new_value, visibility, created_by)
    values (new.id, 'status_change', old.status, new.status, 'client_visible', auth.uid());
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_outsourced_category_options(p_branch text DEFAULT NULL::text)
 RETURNS TABLE(code text, name text, branch_code text, branch_name text, letter text, typical_basis text, added_by_system boolean, sort_order integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select c.code, c.name, c.branch_code, b.name, b.letter, c.typical_basis,
         c.added_by_system, (b.sort_order * 1000) + c.sort_order
    from crm_outsourced_categories c
    join crm_service_branches b on b.code = c.branch_code
   where crm_is_staff() and c.is_active and b.is_active
     and (p_branch is null or c.branch_code = p_branch)
   order by (b.sort_order * 1000) + c.sort_order;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_protect_last_owner()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_owners int;
begin
  if (tg_op = 'DELETE' and old.role = 'owner')
     or (tg_op = 'UPDATE' and old.role = 'owner' and new.role <> 'owner') then
    select count(*) into v_owners from crm_staff_roles where role = 'owner';
    if v_owners <= 1 then
      raise exception 'Cannot remove the only Owner. Assign Owner to another account first.';
    end if;
  end if;
  return coalesce(new, old);
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_quotation_item_billable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare v_kind text;
begin
  if new.cost_line_id is null then
    return new;                      -- free text stays permitted
  end if;
  select line_kind into v_kind from crm_cost_lines where id = new.cost_line_id;
  if v_kind = 'internal_cost' then
    raise exception 'This is an internal cost line and cannot be billed on a client quotation. Put it on the cost sheet, and recover it through a fee.';
  end if;
  if v_kind = 'deposit' then
    raise exception 'This is a refundable deposit, not a charge. Record it on the cost sheet as pass-through.';
  end if;
  if v_kind = 'penalty' then
    raise exception 'A penalty is an avoidable loss, not a service. It cannot be billed to a client as a quotation line.';
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_quotation_items_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform crm_quotation_recalc(coalesce(new.quotation_id, old.quotation_id));
  return coalesce(new, old);
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_quotation_items_lock_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_status text;
begin
  select status into v_status from crm_quotations
   where id = coalesce(new.quotation_id, old.quotation_id);
  if v_status in ('issued','viewed','revision_requested','accepted','rejected',
                  'expired','withdrawn','converted_to_order') then
    raise exception 'Items of an issued quotation are locked. Create a revision.';
  end if;
  return coalesce(new, old);
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_quotation_lock_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare allowed_status_targets text[];
begin
  if old.status in ('issued','viewed','revision_requested','accepted','rejected',
                    'expired','withdrawn','converted_to_order') then
    -- Only status/client-action columns may move, via the definer RPCs below.
    if new.subtotal is distinct from old.subtotal
       or new.total is distinct from old.total
       or new.discount_pct is distinct from old.discount_pct
       or new.tax_pct is distinct from old.tax_pct
       or new.freight_amount is distinct from old.freight_amount
       or new.other_charges is distinct from old.other_charges
       or new.currency is distinct from old.currency then
      raise exception 'Issued quotation is locked. Create a revision instead.';
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_quotation_rates_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.discount_pct is distinct from old.discount_pct
     or new.tax_pct is distinct from old.tax_pct
     or new.freight_amount is distinct from old.freight_amount
     or new.other_charges is distinct from old.other_charges then
    perform crm_quotation_recalc(new.id);
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_quotation_recalc(p_quotation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_sub numeric(16,2); v_q crm_quotations%rowtype;
begin
  select * into v_q from crm_quotations where id = p_quotation_id;
  if not found then return; end if;
  select coalesce(sum(line_total),0) into v_sub
    from crm_quotation_items where quotation_id = p_quotation_id;
  update crm_quotations set
    subtotal        = v_sub,
    discount_amount = round(v_sub * coalesce(discount_pct,0)/100.0, 2),
    tax_amount      = round((v_sub - round(v_sub * coalesce(discount_pct,0)/100.0, 2))
                            * coalesce(tax_pct,0)/100.0, 2),
    total           = round(v_sub
                        - round(v_sub * coalesce(discount_pct,0)/100.0, 2)
                        + round((v_sub - round(v_sub * coalesce(discount_pct,0)/100.0, 2))
                                * coalesce(tax_pct,0)/100.0, 2)
                        + coalesce(freight_amount,0) + coalesce(other_charges,0), 2)
  where id = p_quotation_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_reassign_rm(p_order_id uuid, p_new_rm uuid, p_reason text, p_handover text DEFAULT NULL::text, p_effective timestamp with time zone DEFAULT now())
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare old_rm uuid; ord_no text;
begin
  if not public.crm_is_staff() then raise exception 'Staff only.'; end if;
  if p_new_rm is null then raise exception 'Select the new Relationship Manager.'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'A reassignment reason is required.'; end if;
  if not exists (select 1 from public.crm_eligible_rms() e where e.user_id = p_new_rm) then
    raise exception 'The selected person is not an eligible Relationship Manager.';
  end if;

  select relationship_manager_id, coalesce(order_number, left(id::text,8))
    into old_rm, ord_no
    from public.crm_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found.'; end if;
  if old_rm is not distinct from p_new_rm then raise exception 'That person is already the assigned RM.'; end if;

  -- non-governance staff may assign a first RM, but only governance may transfer
  if old_rm is not null
     and not public.crm_has_role(array['owner','super_admin','ceo','operations_manager']) then
    raise exception 'Reassignment requires management authorisation.';
  end if;

  update public.crm_record_assignments
     set effective_to = p_effective, status = 'ended',
         handover_notes = coalesce(p_handover, handover_notes), updated_at = now()
   where entity_type = 'orders' and entity_id = p_order_id
     and assignment_type = 'relationship_manager' and status = 'active';

  insert into public.crm_record_assignments
    (entity_type, entity_id, assignment_type, user_id, effective_from,
     assigned_by, assignment_reason, handover_notes)
  values ('orders', p_order_id, 'relationship_manager', p_new_rm, p_effective,
          auth.uid(), p_reason, p_handover);

  perform set_config('jco.rm_rpc','1', true);
  update public.crm_orders set relationship_manager_id = p_new_rm where id = p_order_id;
  perform set_config('jco.rm_rpc','0', true);

  perform public.crm_notify(p_new_rm, 'Order assigned to you',
    'You are now the Relationship Manager for order '||ord_no||'. Reason: '||p_reason||
    coalesce(' · Handover: '||p_handover,''), 'crm-orders.html', 'assignment');
  if old_rm is not null then
    perform public.crm_notify(old_rm, 'Order reassigned',
      'Order '||ord_no||' has been transferred. Reason: '||p_reason, 'crm-orders.html', 'assignment');
  end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_recalc_tracking(p_order_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare prog numeric; nxt record; delayed boolean; dreason text; rm uuid; ord_no text;
        was_delayed boolean;
begin
  select coalesce(round(
           sum(weight * case status when 'completed' then 100 when 'skipped' then 100
                        else completion_percentage end) / nullif(sum(weight),0), 1), 0)
    into prog
    from public.crm_order_milestones where order_id = p_order_id;

  select milestone_label, planned_due_at into nxt
    from public.crm_order_milestones
   where order_id = p_order_id and status not in ('completed','skipped')
   order by sequence_number limit 1;

  select exists (select 1 from public.crm_order_milestones
                  where order_id = p_order_id
                    and status not in ('completed','skipped')
                    and planned_due_at < current_date),
         (select string_agg(milestone_label, ', ')
            from public.crm_order_milestones
           where order_id = p_order_id
             and status not in ('completed','skipped')
             and planned_due_at < current_date)
    into delayed, dreason;

  select is_delayed into was_delayed from public.crm_order_tracking where order_id = p_order_id;

  update public.crm_order_tracking
     set progress_percentage = prog,
         next_milestone = nxt.milestone_label,
         next_milestone_due_at = nxt.planned_due_at,
         is_delayed = coalesce(delayed,false),
         delay_reason = case when coalesce(delayed,false)
                             then coalesce('Overdue: '||dreason, delay_reason) else null end,
         last_update_at = now(), updated_at = now(), updated_by = auth.uid()
   where order_id = p_order_id;

  if coalesce(delayed,false) and not coalesce(was_delayed,false) then
    begin
      select relationship_manager_id, coalesce(order_number,left(id::text,8))
        into rm, ord_no from public.crm_orders where id = p_order_id;
      if rm is not null then
        perform public.crm_notify(rm, '⚠ Order delayed',
          'Order '||ord_no||' has overdue milestones: '||coalesce(dreason,'—'),
          'crm-orders.html', 'delay');
      end if;
    exception when others then null;
    end;
  end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_recent_activity(p_limit integer DEFAULT 50)
 RETURNS TABLE(who text, event text, entity text, detail text, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(e.full_name, u.email::text), a.event, a.entity, a.detail, a.created_at
  from crm_activity_events a
  join auth.users u on u.id = a.user_id
  left join crm_employee_profiles e on e.user_id = a.user_id
  where crm_has_role(array['owner','super_admin','ceo','read_only_auditor'])
  order by a.created_at desc
  limit least(greatest(coalesce(p_limit,50),1),200);
$function$
;

CREATE OR REPLACE FUNCTION public.crm_related_records(p_entity text, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_enq uuid; v_out jsonb := '[]'::jsonb;
begin
  if not crm_is_staff() then return '[]'::jsonb; end if;

  -- Resolve the enquiry that anchors the chain
  v_enq := case p_entity
    when 'enquiry'     then p_id
    when 'opportunity' then (select enquiry_id from crm_opportunities where id = p_id)
    when 'quotation'   then (select enquiry_id from crm_quotations    where id = p_id)
    when 'order'       then (select enquiry_id from crm_orders        where id = p_id)
    when 'invoice'     then (select o.enquiry_id from crm_invoices i
                              left join crm_orders o on o.id = i.order_id
                              where i.id = p_id)
    else null end;

  select coalesce(jsonb_agg(r order by r->>'sort'), '[]'::jsonb) into v_out from (
    select jsonb_build_object('sort','1','kind','Enquiry','number',e.enquiry_number,
             'label',e.title,'id',e.id,'page','crm.html','status',e.status) as r
      from crm_enquiries e where e.id = v_enq and e.deleted_at is null
    union all
    select jsonb_build_object('sort','2','kind','Opportunity','number',o.opportunity_number,
             'label',o.title,'id',o.id,'page','crm-opportunities.html','status',o.stage)
      from crm_opportunities o
     where o.deleted_at is null
       and (o.id = p_id or (v_enq is not null and o.enquiry_id = v_enq))
    union all
    select jsonb_build_object('sort','3','kind','Quotation',
             'number',q.quotation_number || ' v' || q.version,
             'label',q.title,'id',q.id,'page','quotation-view.html','status',q.status)
      from crm_quotations q
     where q.deleted_at is null
       and (q.id = p_id or (v_enq is not null and q.enquiry_id = v_enq))
    union all
    select jsonb_build_object('sort','4','kind','Order','number',d.order_number,
             'label',d.title,'id',d.id,'page','crm-orders.html','status',d.status)
      from crm_orders d
     where d.deleted_at is null
       and (d.id = p_id or (v_enq is not null and d.enquiry_id = v_enq))
    union all
    select jsonb_build_object('sort','5','kind','Invoice','number',i.invoice_number,
             'label',i.title,'id',i.id,'page','crm-finance.html','status',i.status)
      from crm_invoices i
     where i.deleted_at is null
       and (i.id = p_id or i.order_id in (
             select id from crm_orders
              where deleted_at is null
                and (id = p_id or (v_enq is not null and enquiry_id = v_enq))))
    union all
    select jsonb_build_object('sort','6','kind','Shipment','number',s.shipment_number,
             'label',coalesce(s.destination_port,''),'id',s.id,
             'page','crm-orders.html','status',s.status)
      from crm_shipments s
     where s.deleted_at is null
       and s.order_id in (
             select id from crm_orders
              where deleted_at is null
                and (id = p_id or (v_enq is not null and enquiry_id = v_enq)))
    union all
    select jsonb_build_object('sort','7','kind','Project','number',p.project_number,
             'label',p.title,'id',p.id,'page','crm-orders.html','status',p.status)
      from crm_projects p
     where p.deleted_at is null
       and (v_enq is not null and p.order_id in (
             select id from crm_orders where enquiry_id = v_enq and deleted_at is null))
  ) x;
  return v_out;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_replace_attachment(p_attachment_id uuid, p_file_path text, p_file_name text, p_content_type text, p_size_bytes bigint, p_reason text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare old_row public.crm_attachments%rowtype; new_id uuid;
begin
  if not public.crm_is_staff() then
    raise exception 'Staff only.';
  end if;
  select * into old_row from public.crm_attachments
   where id = p_attachment_id and deleted_at is null for update;
  if not found then raise exception 'Attachment not found.'; end if;

  update public.crm_attachments set is_current_version = false where id = old_row.id;

  insert into public.crm_attachments
    (module, record_id, file_path, file_name, label, content_type, size_bytes,
     organization_id, document_category, document_title, description, visibility_scope,
     version_number, is_current_version, parent_attachment_id, source,
     is_confidential, replacement_reason)
  values
    (old_row.module, old_row.record_id, p_file_path, p_file_name, old_row.label,
     p_content_type, p_size_bytes,
     old_row.organization_id, old_row.document_category, old_row.document_title,
     old_row.description, old_row.visibility_scope,
     old_row.version_number + 1, true, old_row.id, 'crm',
     old_row.is_confidential, p_reason)
  returning id into new_id;

  insert into public.crm_attachment_events (attachment_id,event_type,detail,actor)
  values (new_id,'replace','v'||old_row.version_number||' → v'||(old_row.version_number+1)
          ||coalesce(' · '||p_reason,''), auth.uid());
  return new_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_resolve_template(p_order_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare svc text; tid uuid;
begin
  -- best effort: order → quotation → enquiry → service name → template code
  begin
    execute $q$
      select lower(coalesce(s.name,''))
        from public.crm_orders o
        left join public.crm_quotations q on q.id = o.quotation_id
        left join public.crm_enquiries e on e.id = coalesce(q.enquiry_id, o.enquiry_id)
        left join public.crm_services s on s.id = e.service_id
       where o.id = $1 $q$ into svc using p_order_id;
  exception when others then svc := null;
  end;
  if svc is not null then
    tid := (select id from public.crm_tracking_templates where is_active and
              case
                when svc like '%trad%' or svc like '%sourc%'   then service_code = 'global_trade'
                when svc like '%custom%' or svc like '%clear%' then service_code = 'customs'
                when svc like '%audit%' or svc like '%plant%' or svc like '%production%'
                                                               then service_code = 'plant_audit'
                when svc like '%architect%' or svc like '%interior%' or svc like '%construct%'
                                                               then service_code = 'aic'
                when svc like '%train%' or svc like '%academy%' then service_code = 'training'
                else false
              end
            limit 1);
  end if;
  if tid is null then
    select id into tid from public.crm_tracking_templates where is_default and is_active limit 1;
  end if;
  return tid;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_review_daily_entry(p_entry_id uuid, p_decision text, p_ledger_category text DEFAULT NULL::text, p_is_direct boolean DEFAULT false, p_note text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_entry   crm_daily_entries%rowtype;
  v_cat     text;
  v_exp_id  uuid;
  v_num     text;
begin
  if not crm_has_role(array['owner','super_admin','ceo','finance_manager']) then
    raise exception 'Only management can review daily entries.';
  end if;

  select * into v_entry from crm_daily_entries where id = p_entry_id for update;
  if not found then raise exception 'Entry not found.'; end if;
  if v_entry.status <> 'pending' then raise exception 'Entry has already been reviewed.'; end if;

  if p_decision = 'reject' then
    update crm_daily_entries
       set status = 'rejected', reviewed_by = auth.uid(),
           reviewed_at = now(), review_note = p_note
     where id = p_entry_id;
    return null;
  end if;

  if p_decision <> 'approve' then
    raise exception 'Decision must be approve or reject.';
  end if;

  -- Final ledger category: reviewer's choice if valid, otherwise mapped.
  v_cat := case
    when p_ledger_category in ('travel','inspection','commission','marketing',
                               'professional_fees','logistics','office','other')
      then p_ledger_category
    else case v_entry.category
      when 'fuel'                  then 'travel'
      when 'travel'                then 'travel'
      when 'parking_toll'          then 'travel'
      when 'courier'               then 'logistics'
      when 'customs'               then 'logistics'
      when 'marketing'             then 'marketing'
      when 'professional_fees'     then 'professional_fees'
      when 'food_entertainment'    then 'office'
      when 'office_supplies'       then 'office'
      when 'software_subscription' then 'office'
      when 'domain_hosting'        then 'office'
      when 'utilities'             then 'office'
      when 'phone_internet'        then 'office'
      when 'repairs'               then 'office'
      else 'other'
    end
  end;

  v_num := crm_next_number('exp');

  insert into crm_expenses
    (expense_number, category, order_id, project_id, expense_date,
     currency, amount, description, is_direct)
  values
    (v_num, v_cat, v_entry.order_id, v_entry.project_id, v_entry.entry_date,
     v_entry.currency, v_entry.amount,
     v_entry.description || ' [' || coalesce(v_entry.entry_number, 'daily entry') || ']',
     coalesce(p_is_direct, false))
  returning id into v_exp_id;

  update crm_daily_entries
     set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now(),
         review_note = p_note, expense_id = v_exp_id
   where id = p_entry_id;

  return v_exp_id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_revise_quotation(p_quotation_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_old crm_quotations%rowtype; v_new_id uuid; v_next int;
begin
  if not crm_is_staff() then raise exception 'Not authorized'; end if;
  select * into v_old from crm_quotations where id = p_quotation_id and deleted_at is null;
  if not found then raise exception 'Quotation not found'; end if;
  select coalesce(max(version),0)+1 into v_next
    from crm_quotations where quotation_group = v_old.quotation_group;

  insert into crm_quotations
    (quotation_number, version, quotation_group, organization_id, contact_id,
     enquiry_id, cost_sheet_id, service_id, title, currency, discount_pct, tax_pct,
     freight_amount, other_charges, payment_terms, delivery_terms, incoterm,
     delivery_timeline, warranty, assumptions, exclusions, terms_conditions,
     internal_notes, client_notes, status)
  values
    (v_old.quotation_number, v_next, v_old.quotation_group, v_old.organization_id,
     v_old.contact_id, v_old.enquiry_id, v_old.cost_sheet_id, v_old.service_id,
     v_old.title, v_old.currency, v_old.discount_pct, v_old.tax_pct,
     v_old.freight_amount, v_old.other_charges, v_old.payment_terms,
     v_old.delivery_terms, v_old.incoterm, v_old.delivery_timeline, v_old.warranty,
     v_old.assumptions, v_old.exclusions, v_old.terms_conditions,
     v_old.internal_notes, v_old.client_notes, 'draft')
  returning id into v_new_id;

  insert into crm_quotation_items (quotation_id, description, quantity, unit, unit_price, sort_order)
  select v_new_id, description, quantity, unit, unit_price, sort_order
    from crm_quotation_items where quotation_id = p_quotation_id;

  update crm_quotations set status='revised' where id = p_quotation_id and status <> 'revised';
  return v_new_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_rm_dashboard()
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare j json;
begin
  if not public.crm_is_staff() then raise exception 'Staff only.'; end if;
  select json_build_object(
    'active_orders', (select count(*) from crm_orders
        where relationship_manager_id = auth.uid()
          and coalesce(status,'') not in ('completed','cancelled','refunded','closed')),
    'total_orders', (select count(*) from crm_orders where relationship_manager_id = auth.uid()),
    'by_status', (select coalesce(json_agg(t), '[]'::json) from (
        select status, count(*) as n from crm_orders
         where relationship_manager_id = auth.uid()
           and coalesce(status,'') not in ('completed','cancelled','refunded','closed')
         group by status order by n desc) t),
    'unassigned_orders', case when public.crm_has_role(array['owner','super_admin','ceo','operations_manager'])
        then (select count(*) from crm_orders
               where relationship_manager_id is null and not coalesce(rm_exempt,false)
                 and coalesce(status,'') not in ('completed','cancelled','refunded','closed'))
        else null end,
    'unread_notifications', (select count(*) from crm_notifications
        where user_id = auth.uid() and read_at is null)
  ) into j;
  return j;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_rm_enforce()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- rm_exempt may only be changed by governance
  if new.rm_exempt is distinct from old.rm_exempt
     and not public.crm_has_role(array['owner','super_admin']) then
    raise exception 'Only the Owner may set the Relationship-Manager exception on an order.';
  end if;
  -- block progression without an RM (cancellation always allowed)
  if new.status is distinct from old.status
     and new.relationship_manager_id is null
     and not coalesce(new.rm_exempt, false)
     and coalesce(new.status,'') not in ('cancelled') then
    raise exception 'Assign a Relationship Manager before progressing this order (or the Owner may grant an exception).';
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_rm_track()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ord_no text;
begin
  if current_setting('jco.rm_rpc', true) = '1' then return new; end if;
  if tg_op = 'UPDATE'
     and new.relationship_manager_id is not distinct from old.relationship_manager_id then
    return new;
  end if;
  if tg_op = 'INSERT' and new.relationship_manager_id is null then return new; end if;

  update public.crm_record_assignments
     set effective_to = now(), status = 'ended', updated_at = now()
   where entity_type = 'orders' and entity_id = new.id
     and assignment_type = 'relationship_manager' and status = 'active';

  if new.relationship_manager_id is not null then
    insert into public.crm_record_assignments
      (entity_type, entity_id, assignment_type, user_id, assigned_by)
    values ('orders', new.id, 'relationship_manager', new.relationship_manager_id, auth.uid());
  end if;

  begin
    ord_no := coalesce(new.order_number, left(new.id::text, 8));
    if new.relationship_manager_id is not null then
      perform public.crm_notify(new.relationship_manager_id,
        'Order assigned to you', 'You are now the Relationship Manager for order '||ord_no||'.',
        'crm-orders.html', 'assignment');
    end if;
    if tg_op = 'UPDATE' and old.relationship_manager_id is not null
       and old.relationship_manager_id is distinct from new.relationship_manager_id then
      perform public.crm_notify(old.relationship_manager_id,
        'Order reassigned', 'Order '||ord_no||' has been transferred to another Relationship Manager.',
        'crm-orders.html', 'assignment');
    end if;
  exception when others then null; -- notifications must never block the order write
  end;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_run_allocation(p_period text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_start date; v_end date;
  v_overhead_pool numeric := 0;
  v_payroll_pool  numeric := 0;
  v_direct_labour numeric := 0;
  v_method_overhead text; v_method_payroll text;
  v_excluded_overhead int := 0; v_excluded_payroll int := 0; v_excluded_orders int := 0;
  v_rows int := 0;
begin
  if not crm_has_role(array['owner','super_admin','ceo','finance_manager']) then
    raise exception 'Only management can run allocations.';
  end if;
  if p_period !~ '^\d{4}-\d{2}$' then
    raise exception 'Period must be YYYY-MM.';
  end if;
  v_start := to_date(p_period || '-01', 'YYYY-MM-DD');
  v_end   := (v_start + interval '1 month')::date;

  select method into v_method_overhead from crm_allocation_rules where cost_pool = 'overhead';
  select method into v_method_payroll  from crm_allocation_rules where cost_pool = 'payroll';

  -- POOL 1 · OVERHEAD (PKR): recurring fixed + subscriptions + overhead ledger
  select coalesce(sum(monthly_equivalent), 0) into v_overhead_pool
    from crm_overhead_lines where currency = 'PKR';
  select count(*) into v_excluded_overhead
    from crm_overhead_lines where currency <> 'PKR';
  v_overhead_pool := v_overhead_pool + coalesce((
    select sum(amount) from crm_expenses
     where is_direct = false and deleted_at is null and currency = 'PKR'
       and expense_date >= v_start and expense_date < v_end), 0);

  -- POOL 2 · PAYROLL (PKR): active payroll − direct labour charged in period
  select coalesce(sum(total_monthly_cost), 0) into v_payroll_pool
    from crm_employee_cost_rates where status = 'active' and currency = 'PKR';
  select count(*) into v_excluded_payroll
    from crm_employee_cost_rates where status = 'active' and currency <> 'PKR';
  select coalesce(sum(t.hours * t.rate_snapshot), 0) into v_direct_labour
    from crm_timesheets t
   where t.work_date >= v_start and t.work_date < v_end
     and (t.order_id is not null or t.project_id is not null)
     and coalesce(t.rate_currency, 'PKR') = 'PKR';
  v_payroll_pool := greatest(v_payroll_pool - v_direct_labour, 0);

  select count(*) into v_excluded_orders
    from crm_order_ebitda where currency is distinct from 'PKR';

  -- Basis weights per order, per method (PKR orders only)
  create temp table _targets on commit drop as
  with orders as (
    select order_id, order_date, coalesce(revenue,0) as revenue
      from crm_order_ebitda where currency = 'PKR'
  ),
  hrs as (
    select order_id, sum(hours) as h, count(distinct employee_cost_id) as heads
      from crm_timesheets
     where order_id is not null and work_date >= v_start and work_date < v_end
     group by order_id
  ),
  eq as (  -- orders dated in the period; if none, every order
    select order_id, 1::numeric as w
      from orders
     where (order_date >= v_start and order_date < v_end)
        or not exists (select 1 from orders o2
                        where o2.order_date >= v_start and o2.order_date < v_end)
  )
  select o.order_id,
         case v_method_overhead
           when 'revenue_pct' then o.revenue
           when 'hours'       then coalesce(h.h, 0)
           when 'headcount'   then coalesce(h.heads, 0)
           when 'equal'       then coalesce((select w from eq where eq.order_id = o.order_id), 0)
           when 'manual_pct'  then coalesce((select weight from crm_allocation_targets a where a.order_id = o.order_id), 0)
         end as w_overhead,
         case v_method_payroll
           when 'revenue_pct' then o.revenue
           when 'hours'       then coalesce(h.h, 0)
           when 'headcount'   then coalesce(h.heads, 0)
           when 'equal'       then coalesce((select w from eq where eq.order_id = o.order_id), 0)
           when 'manual_pct'  then coalesce((select weight from crm_allocation_targets a where a.order_id = o.order_id), 0)
         end as w_payroll
    from orders o
    left join hrs h on h.order_id = o.order_id;

  -- Replace this period's results
  delete from crm_cost_allocations where period = p_period;

  insert into crm_cost_allocations (period, order_id, cost_pool, method, basis_label, allocated_amount, currency, run_by)
  select p_period, t.order_id, 'overhead', v_method_overhead,
         'share ' || round(t.w_overhead / nullif(s.tot,0) * 100, 2) || '%',
         round(v_overhead_pool * t.w_overhead / nullif(s.tot,0), 2), 'PKR', auth.uid()
    from _targets t, (select sum(w_overhead) as tot from _targets) s
   where t.w_overhead > 0 and s.tot > 0 and v_overhead_pool > 0;
  get diagnostics v_rows = row_count;

  insert into crm_cost_allocations (period, order_id, cost_pool, method, basis_label, allocated_amount, currency, run_by)
  select p_period, t.order_id, 'payroll', v_method_payroll,
         'share ' || round(t.w_payroll / nullif(s.tot,0) * 100, 2) || '%',
         round(v_payroll_pool * t.w_payroll / nullif(s.tot,0), 2), 'PKR', auth.uid()
    from _targets t, (select sum(w_payroll) as tot from _targets) s
   where t.w_payroll > 0 and s.tot > 0 and v_payroll_pool > 0;

  return jsonb_build_object(
    'period', p_period,
    'overhead_pool_pkr', v_overhead_pool,
    'payroll_pool_pkr', v_payroll_pool,
    'direct_labour_deducted_pkr', v_direct_labour,
    'overhead_method', v_method_overhead,
    'payroll_method', v_method_payroll,
    'overhead_rows', v_rows,
    'excluded_non_pkr', jsonb_build_object(
      'overhead_lines', v_excluded_overhead,
      'employees', v_excluded_payroll,
      'orders', v_excluded_orders)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_select_supplier_offer(p_offer_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_enquiry uuid;
begin
  if not crm_has_role(array['super_admin','ceo','trade_sourcing_manager','operations_manager']) then
    raise exception 'Not authorized to select suppliers';
  end if;
  select enquiry_id into v_enquiry from crm_supplier_offers where id = p_offer_id and deleted_at is null;
  if not found then raise exception 'Offer not found'; end if;
  update crm_supplier_offers set is_selected=false, selected_by=null, selected_at=null
   where enquiry_id = v_enquiry;
  update crm_supplier_offers set is_selected=true, selected_by=auth.uid(), selected_at=now()
   where id = p_offer_id;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_service_offer_approval()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status = 'approved' and coalesce(old.status,'') <> 'approved' then
    if not crm_has_role(array['owner','super_admin','ceo','finance_manager']) then
      raise exception 'Only the Owner, Super Admin, CEO or Finance Manager may approve a service offer.';
    end if;
    new.approved_by := auth.uid();
    new.approved_at := now();
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_service_offer_number()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.offer_number is null then
    begin
      new.offer_number := crm_next_number(jsonb_build_object('p_entity','oso'));
    exception when others then
      new.offer_number := 'JCO-OSO-' || to_char(now(),'YYYY') || '-' ||
                          lpad((floor(random()*9999)+1)::text, 4, '0');
    end;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_service_provider_number()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.provider_number is null then
    begin
      new.provider_number := crm_next_number(jsonb_build_object('p_entity','osp'));
    exception when others then
      new.provider_number := 'JCO-OSP-' || to_char(now(),'YYYY') || '-' ||
                             lpad((floor(random()*9999)+1)::text, 4, '0');
    end;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_session_context()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid    uuid := auth.uid();
  v_roles  text[];
  v_perms  text[];
  v_name   text;
  v_email  text;
  v_portal boolean := false;
  v_staff  boolean := false;
begin
  if v_uid is null then
    return null;                                   -- not signed in
  end if;

  select coalesce(array_agg(sr.role order by sr.role), array[]::text[])
    into v_roles
    from crm_staff_roles sr
   where sr.user_id = v_uid;

  select exists (select 1 from crm_portal_members pm where pm.user_id = v_uid)
    into v_portal;

  select u.email into v_email from auth.users u where u.id = v_uid;

  begin
    v_staff := crm_is_staff();
  exception when others then
    v_staff := false;
  end;

  -- display name via the existing helper (no schema guessing)
  begin
    select n.display_name into v_name from crm_staff_names() n where n.user_id = v_uid;
  exception when others then
    v_name := null;
  end;

  -- analytics permissions (absent until migration 026 has run)
  begin
    v_perms := analytics_my_permissions();
  exception when others then
    v_perms := array[]::text[];
  end;

  return jsonb_build_object(
    'user_id',          v_uid,
    'email',            coalesce(v_email, ''),
    'display_name',     coalesce(nullif(v_name, ''), split_part(coalesce(v_email, 'account'), '@', 1)),
    'is_staff',         v_staff,
    'is_portal_member', v_portal,
    'roles',            to_jsonb(v_roles),
    'analytics',        to_jsonb(coalesce(v_perms, array[]::text[])),
    'generated_at',     now()
  );
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_session_policy()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'idle_timeout_minutes',
      coalesce((select (value #>> '{}')::int from crm_settings
                 where key='session_idle_timeout_minutes'), 30),
    'remember_me_days',
      coalesce((select (value #>> '{}')::int from crm_settings
                 where key='remember_me_days'), 30));
$function$
;

CREATE OR REPLACE FUNCTION public.crm_set_employee_active(p_user_id uuid, p_active boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_owners int;
begin
  if not crm_has_role(array['owner','super_admin','ceo']) then
    raise exception 'Only Owner / Super Admin / CEO may suspend employees';
  end if;
  if not p_active then
    select count(*) into v_owners
      from crm_staff_roles r
      left join crm_employee_profiles e on e.user_id = r.user_id
     where r.role = 'owner'
       and coalesce(e.is_active, true) = true
       and r.user_id <> p_user_id;
    if v_owners = 0 and exists (select 1 from crm_staff_roles
                                 where user_id = p_user_id and role = 'owner') then
      raise exception 'Cannot suspend the only active Owner.';
    end if;
  end if;
  insert into crm_employee_profiles (user_id, is_active, suspended_at)
  values (p_user_id, p_active, case when p_active then null else now() end)
  on conflict (user_id) do update
    set is_active = p_active,
        suspended_at = case when p_active then null else now() end;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_set_roles(p_user_id uuid, p_roles text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not crm_has_role(array['owner','super_admin','ceo']) then
    raise exception 'Only Owner / Super Admin / CEO may assign roles';
  end if;
  delete from crm_staff_roles
   where user_id = p_user_id and role <> all(coalesce(p_roles,'{}'));
  insert into crm_staff_roles (user_id, role)
  select p_user_id, r from unnest(coalesce(p_roles,'{}')) as r
  on conflict (user_id, role) do nothing;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_shipment_status_log()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status is distinct from old.status then
    insert into crm_order_events (order_id, kind, body, old_value, new_value, visibility, created_by)
    values (new.order_id, 'milestone',
            'Shipment ' || coalesce(new.shipment_number,'') || ' status updated',
            old.status, new.status, 'client_visible', auth.uid());
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_snapshot_service_offer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o record; p record;
begin
  if new.service_offer_id is null then
    new.offer_snapshot := null;
    return new;
  end if;
  if tg_op = 'UPDATE' and new.service_offer_id is not distinct from old.service_offer_id then
    return new;                              -- unchanged link: keep the original snapshot
  end if;
  select * into o from crm_service_offers where id = new.service_offer_id;
  if not found then
    raise exception 'That service offer does not exist.';
  end if;
  select legal_name, contact_person into p from crm_service_providers where id = o.provider_id;
  new.offer_snapshot := jsonb_build_object(
    'frozen_at',      now(),
    'offer_number',   o.offer_number,
    'provider',       p.legal_name,
    'contact',        p.contact_person,
    'category_code',  o.category_code,
    'billing_basis',  o.billing_basis,
    'rate',           o.rate,
    'currency',       o.currency,
    'estimated_qty',  o.estimated_qty,
    'resources',      o.resources,
    'tax_pct',        o.tax_pct,
    'final_amount',   o.final_amount,
    'valid_until',    o.valid_until,
    'payment_terms',  o.payment_terms,
    'status_at_link', o.status
  );
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_staff_names()
 RETURNS TABLE(user_id uuid, display_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select u.id,
         coalesce(e.full_name, split_part(u.email, '@', 1))::text
  from auth.users u
  join crm_staff_roles r on r.user_id = u.id
  left join crm_employee_profiles e on e.user_id = u.id
  where crm_is_staff()
  group by u.id, e.full_name, u.email;
$function$
;

-- NOTE: on production the body of this function (and of
-- crm_stockists_set_updated_at) uses CRLF line endings; normalised to LF here.
CREATE OR REPLACE FUNCTION public.crm_stockists_assign_number()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_num text;
begin
  if new.stockist_number is null or new.stockist_number = '' then
    -- Prefer the CRM's central numbering so format/year stays consistent.
    begin
      v_num := public.crm_next_number('stk');
    exception when others then
      v_num := null;                      -- helper/counter not present → fallback
    end;

    if v_num is null or v_num = '' then
      v_num := 'JCO-STK-' || to_char(now(), 'YYYY') || '-' ||
               lpad(nextval('public.crm_stockists_fallback_seq')::text, 4, '0');
    end if;

    new.stockist_number := v_num;
  end if;
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_stockists_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_submit_quotation(p_quotation_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_q crm_quotations%rowtype;
  v_min_margin numeric; v_max_disc numeric;
  v_est_cost numeric; v_margin_pct numeric; v_reason text := null;
begin
  if not crm_is_staff() then raise exception 'Not authorized'; end if;
  select * into v_q from crm_quotations where id = p_quotation_id and deleted_at is null;
  if not found then raise exception 'Quotation not found'; end if;
  if v_q.status not in ('draft','costing_review','revised') then
    raise exception 'Only draft/revised quotations can be submitted (current: %)', v_q.status;
  end if;

  -- Validate on GROSS line-item value, not the net total, so a legitimate
  -- 100%-discount complimentary quotation (net 0) can still be submitted.
  if coalesce((
        select sum(coalesce(quantity,0) * coalesce(unit_price,0))
        from crm_quotation_items
        where quotation_id = p_quotation_id
     ), 0) <= 0 then
    raise exception 'Quotation has no line items / zero gross value';
  end if;

  select (value #>> '{}')::numeric into v_min_margin from crm_settings where key='approval_min_margin_pct';
  select (value #>> '{}')::numeric into v_max_disc   from crm_settings where key='approval_max_discount_pct';

  if v_q.discount_pct > coalesce(v_max_disc, 5) then
    v_reason := 'high_discount';
  end if;
  if v_q.cost_sheet_id is not null then
    select est_total_with_contingency into v_est_cost
      from crm_cost_sheet_totals where cost_sheet_id = v_q.cost_sheet_id;
    if v_est_cost is not null and v_q.total > 0 then
      v_margin_pct := round((v_q.total - v_est_cost) / v_q.total * 100, 2);
      if v_margin_pct < coalesce(v_min_margin, 10) then
        v_reason := coalesce(v_reason || '+', '') || 'low_margin';
      end if;
    end if;
  end if;

  if v_reason is not null then
    update crm_quotations
       set status='pending_approval', approval_status='pending', reviewed_by=auth.uid()
     where id = p_quotation_id;
    insert into crm_quotation_approvals (quotation_id, reason) values (p_quotation_id, v_reason);
    return 'pending_approval';
  else
    update crm_quotations
       set status='approved', approval_status='not_required', reviewed_by=auth.uid()
     where id = p_quotation_id;
    return 'approved';
  end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_subscription_price_track()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into crm_subscription_price_history
    (subscription_id, old_cost, new_cost, old_billing_cycle, new_billing_cycle, changed_by)
  values (old.id, old.cost, new.cost, old.billing_cycle, new.billing_cycle, auth.uid());
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_timesheet_rate_snapshot()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  select r.effective_hourly_rate, r.currency
    into new.rate_snapshot, new.rate_currency
    from crm_employee_cost_rates r
   where r.id = new.employee_cost_id;
  new.rate_snapshot := coalesce(new.rate_snapshot, 0);
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_touch_row()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.crm_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_tracking_alerts()
 RETURNS TABLE(order_id uuid, order_number text, kind text, detail text, due_at date)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare soon int; stale int;
begin
  if not public.crm_is_staff() then raise exception 'Staff only.'; end if;
  select due_soon_hours, stale_after_days into soon, stale from public.crm_tracking_policy limit 1;
  return query
  select m.order_id, coalesce(o.order_number, left(o.id::text,8)), 'overdue'::text,
         m.milestone_label, m.planned_due_at
    from public.crm_order_milestones m join public.crm_orders o on o.id = m.order_id
   where m.status not in ('completed','skipped') and m.planned_due_at < current_date
  union all
  select m.order_id, coalesce(o.order_number, left(o.id::text,8)), 'due_soon',
         m.milestone_label, m.planned_due_at
    from public.crm_order_milestones m join public.crm_orders o on o.id = m.order_id
   where m.status not in ('completed','skipped')
     and m.planned_due_at >= current_date
     and m.planned_due_at <= current_date + greatest(1, ceil(coalesce(soon,48)/24.0))::int
  union all
  select t.order_id, coalesce(o.order_number, left(o.id::text,8)), 'stale',
         'No tracking update for '||coalesce(stale,7)||'+ days', t.last_update_at::date
    from public.crm_order_tracking t join public.crm_orders o on o.id = t.order_id
   where t.last_update_at < now() - make_interval(days => coalesce(stale,7))
     and coalesce(o.status,'') not in ('completed','cancelled','refunded','closed')
  order by 5 nulls last;
end $function$
;

CREATE OR REPLACE FUNCTION public.crm_verify_payment(p_payment_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_p crm_payments%rowtype; v_receipt uuid;
begin
  if not crm_is_finance() then raise exception 'Only finance may verify payments'; end if;
  select * into v_p from crm_payments where id = p_payment_id and deleted_at is null for update;
  if not found then raise exception 'Payment not found'; end if;
  if v_p.is_verified then raise exception 'Payment already verified'; end if;
  update crm_payments
     set is_verified=true, verified_by=auth.uid(), verified_at=now()
   where id = p_payment_id;
  insert into crm_receipts (receipt_number, payment_id, organization_id, amount, currency)
  values (crm_next_number('rcp'), p_payment_id, v_p.organization_id, v_p.amount, v_p.currency)
  returning id into v_receipt;
  return v_receipt;
end $function$
;

CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(select 1 from profiles where id = auth.uid() and role = 'admin');
$function$
;

CREATE OR REPLACE FUNCTION public.jco_autocreate_service_project()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  rec       jsonb := to_jsonb(NEW);
  v_qid     uuid;
  v_service uuid;
  v_org     uuid;
  v_scope   text;
  v_qtitle  text;
  v_ftype   text;
  v_prjnum  text;
  v_pid     uuid;
begin
  v_qid := nullif(rec->>'quotation_id', '')::uuid;
  if v_qid is null then
    v_qid := nullif(rec->>'source_quotation_id', '')::uuid;
  end if;

  v_service := nullif(rec->>'service_id', '')::uuid;
  v_org     := nullif(rec->>'organization_id', '')::uuid;

  if v_qid is not null and (v_service is null or v_org is null) then
    select coalesce(v_service, q.service_id),
           coalesce(v_org,     q.organization_id),
           q.scope_of_work,
           q.title
      into v_service, v_org, v_scope, v_qtitle
      from public.crm_quotations q
     where q.id = v_qid;
  elsif v_qid is not null then
    select q.scope_of_work, q.title
      into v_scope, v_qtitle
      from public.crm_quotations q
     where q.id = v_qid;
  end if;

  if v_qid is null or v_service is null then
    return NEW;
  end if;

  select fulfilment_type into v_ftype
    from public.crm_services where id = v_service;

  if coalesce(v_ftype, 'service') <> 'service' then
    return NEW;
  end if;

  if exists (
    select 1 from public.crm_projects
     where order_id = NEW.id and deleted_at is null
  ) then
    return NEW;
  end if;

  begin
    v_prjnum := public.crm_next_number('prj');
    insert into public.crm_projects
      (project_number, title, organization_id, service_id, order_id,
       status, scope, completion_pct, client_visible)
    values
      (v_prjnum,
       coalesce(nullif(rec->>'title', ''), v_qtitle, 'Service Project'),
       v_org, v_service, NEW.id,
       'planned',
       v_scope,
       0,
       false)                              -- start HIDDEN until published
    returning id into v_pid;

    insert into public.crm_project_milestones
      (project_id, title, due_date, visibility, status, sort_order)
    select v_pid,
           t.title,
           case when t.offset_days is not null
                then (current_date + make_interval(days => t.offset_days))::date
                else null end,
           t.visibility,
           'pending',
           t.sort_order
      from public.crm_service_milestone_templates t
     where t.service_id = v_service
       and t.is_active = true
     order by t.sort_order;

    raise notice '[J&Co 042] hidden draft project % created + seeded for order %',
      v_prjnum, NEW.id;
  exception when others then
    raise notice '[J&Co 042] auto-project/milestones skipped for order %: %',
      NEW.id, sqlerrm;
  end;

  return NEW;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.pharma_alerts_now()
 RETURNS TABLE(severity text, category text, title text, detail text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not pharma_can('pharma.view') then
    raise exception 'pharma.view permission required.';
  end if;

  -- expiring registrations
  return query
  select case when r.expires_on < current_date then 'critical' else 'warning' end,
         'regulatory',
         p.brand_name || ' — registration ' ||
           case when r.expires_on < current_date then 'EXPIRED' else 'expiring' end,
         'Registration ' || coalesce(r.reference_no,'(no ref)') || ' with ' || coalesce(r.authority,'authority') ||
         ' ' || case when r.expires_on < current_date then 'expired on ' else 'expires on ' end || r.expires_on
    from pharma_product_regulatory r
    join pharma_products p on p.id = r.product_id
   where r.expires_on is not null and r.expires_on < current_date + 90
     and r.status = 'approved';

  -- near-expiry / expired stock
  return query
  select case when s.stock_status = 'expired' then 'critical' else 'warning' end,
         'inventory',
         s.brand_name || ' batch ' || s.batch_number || ' — ' || s.stock_status,
         s.on_hand || ' units, expiry ' || s.expiry_date ||
         ', value ' || round(s.stock_value, 0)
    from pharma_stock_positions s
   where s.on_hand > 0 and s.stock_status in ('expired','near expiry');

  -- credit limits breached
  return query
  select 'critical', 'credit',
         c.name || ' is over its credit limit',
         'Outstanding ' || round(c.outstanding,0) || ' against a limit of ' || round(c.credit_limit,0) ||
         '. Worst overdue: ' || c.worst_overdue_days || ' days.'
    from pharma_credit_exposure c
   where c.credit_status = 'OVER LIMIT';

  -- receivables over 90 days
  return query
  select 'critical', 'collections',
         a.customer || ' — invoice ' || a.invoice_number || ' overdue ' || a.days_overdue || ' days',
         'Outstanding ' || round(a.outstanding,0) || ' in bucket ' || a.ageing_bucket
    from pharma_receivables_ageing a
   where a.days_overdue > 90 and a.outstanding > 0;

  -- doctor spend caps
  return query
  select 'warning', 'compliance',
         d.full_name || ' — engagement spend ' || d.cap_status,
         'Spent ' || round(d.spent_this_year,0) || ' of ' || round(d.annual_spend_cap,0) ||
         ' (' || d.used_pct || '%) this year.'
    from pharma_doctor_spend_status d
   where d.cap_status in ('approaching cap','cap reached');

  -- offers expiring
  return query
  select 'warning', 'promotion',
         o.name || ' — offer ends ' || o.end_date,
         'Category ' || o.category_code || ', budget ' || coalesce(round(o.budget,0),0) ||
         ', spent ' || round(o.spent_to_date,0)
    from pharma_promotional_offers o
   where o.status = 'running' and o.end_date between current_date and current_date + 14
     and o.deleted_at is null;

  -- tenders closing
  return query
  select 'warning', 'tender',
         'Tender ' || coalesce(t.tender_ref, t.tender_code) || ' closes ' ||
           to_char(t.submission_deadline, 'DD Mon HH24:MI'),
         coalesce(h.legal_name, t.authority, 'Unknown authority') ||
         ' — technical status: ' || coalesce(t.technical_status, 'not recorded')
    from pharma_tenders t
    left join pharma_hospitals h on h.id = t.hospital_id
   where t.submission_deadline between now() and now() + interval '14 days'
     and coalesce(t.result,'pending') = 'pending' and t.deleted_at is null;

  -- batches awaiting release
  return query
  select 'info', 'production',
         'Batch ' || b.batch_number || ' awaiting release',
         p.brand_name || ' — stage ' || b.stage || ', QC ' || coalesce(b.qc_result,'not recorded')
    from pharma_production_batches b
    join pharma_products p on p.id = b.product_id
   where b.stage in ('qc_testing','qa_review');

  -- open critical complaints
  return query
  select 'critical', 'quality',
         'Critical complaint open: ' || c.complaint_type,
         coalesce(p.brand_name,'(no product)') || ' — received ' || c.received_on ||
         ', status ' || c.status
    from pharma_complaints c
    left join pharma_products p on p.id = c.product_id
   where c.severity = 'critical' and c.status not in ('closed','resolved');
end $function$
;

CREATE OR REPLACE FUNCTION public.pharma_allocation_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_total numeric; v_amount numeric; v_num text;
begin
  select coalesce(sum(allocation_pct), 0) into v_total
    from pharma_expense_dimensions
   where crm_expense_id = new.crm_expense_id
     and (tg_op = 'INSERT' or id <> new.id);

  if v_total + new.allocation_pct > 100.001 then     -- tolerance for numeric drift
    select amount, expense_number into v_amount, v_num from crm_expenses where id = new.crm_expense_id;
    raise exception 'Over-allocation on expense %: % %% already allocated, this line adds % %%. A cost cannot exceed 100%% of itself.',
      coalesce(v_num, new.crm_expense_id::text), v_total, new.allocation_pct;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.pharma_batch_release_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.stage = 'released' and coalesce(old.stage,'') <> 'released' then
    if coalesce(new.qc_result,'') <> 'pass' then
      raise exception 'Batch % cannot be released: QC result is "%". A pass is required.',
        new.batch_number, coalesce(new.qc_result,'not recorded');
    end if;
    if not (pharma_can('pharma.approve') or pharma_can('pharma.admin')) then
      raise exception 'You do not have pharma.approve. Only authorised staff may release a batch.';
    end if;
    new.released_by := auth.uid();
    new.released_at := now();
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.pharma_branch_contribution(p_from date, p_to date)
 RETURNS TABLE(period date, pharma_revenue numeric, company_invoiced numeric, revenue_share_pct numeric, pharma_gross_profit numeric, company_gross_profit numeric, gp_share_pct numeric, pharma_ebitda numeric, company_ebitda numeric, ebitda_share_pct numeric, caveat text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (pharma_can('pharma.view_financial') or pharma_can('pharma.admin')) then
    raise exception 'pharma.view_financial permission required.';
  end if;
  return query
  select p.period,
         p.revenue, coalesce(f.invoiced, 0),
         case when coalesce(f.invoiced,0) > 0 then round(p.revenue / f.invoiced * 100, 1) end,
         p.gross_profit, coalesce(f.gross_profit, 0),
         case when coalesce(f.gross_profit,0) > 0 then round(p.gross_profit / f.gross_profit * 100, 1) end,
         p.ebitda, coalesce(f.ebitda, 0),
         case when coalesce(f.ebitda,0) <> 0 then round(p.ebitda / f.ebitda * 100, 1) end,
         case when coalesce(p.cost_coverage_pct, 0) < 80
              then 'Only ' || coalesce(p.cost_coverage_pct,0) ||
                   '% of this month''s expenses are attributed to a pharma dimension. Treat the share as indicative, not final.'
              else 'Cost attribution ' || coalesce(p.cost_coverage_pct,0) || '% — reliable.' end
    from pharma_pl(p_from, p_to) p
    left join crm_monthly_finance f on f.period = p.period
   order by p.period;
end $function$
;

CREATE OR REPLACE FUNCTION public.pharma_can(p_permission text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from crm_staff_roles sr
                  where sr.user_id = auth.uid() and sr.role in ('owner','super_admin'))
      or exists (select 1 from crm_staff_roles sr
                  join pharma_role_permissions pp on pp.role = sr.role
                 where sr.user_id = auth.uid() and pp.permission = p_permission);
$function$
;

CREATE OR REPLACE FUNCTION public.pharma_credit_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_limit numeric; v_out numeric; v_name text;
begin
  if new.status not in ('confirmed','dispatched') then return new; end if;
  if new.distributor_id is null then return new; end if;

  if new.credit_override then
    if not (pharma_can('pharma.approve') or pharma_can('pharma.admin')) then
      raise exception 'A credit override requires pharma.approve.';
    end if;
    if coalesce(new.credit_override_reason,'') = '' then
      raise exception 'A credit override must state a reason. It is recorded against you.';
    end if;
    new.credit_override_by := auth.uid();
    return new;
  end if;

  select credit_limit, name into v_limit, v_name from pharma_distributors where id = new.distributor_id;
  if v_limit is null then return new; end if;
  select coalesce(outstanding,0) into v_out from pharma_credit_exposure where distributor_id = new.distributor_id;
  if v_out > v_limit then
    raise exception '% is over its credit limit (outstanding % vs limit %). Approve a credit override to proceed.',
      v_name, v_out, v_limit;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.pharma_doctor_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
begin
  if new.do_not_contact and new.category not in ('restricted','inactive') then
    new.category := 'restricted';
  end if;
  if new.consent_status = 'withdrawn' then
    new.do_not_contact := true;
    new.category := 'restricted';
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.pharma_editor()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select pharma_can('pharma.manage_master') or pharma_can('pharma.admin');
$function$
;

CREATE OR REPLACE FUNCTION public.pharma_fefo_batch(p_product uuid, p_qty numeric, p_warehouse uuid DEFAULT NULL::uuid)
 RETURNS TABLE(batch_id uuid, batch_number text, expiry_date date, on_hand numeric, sufficient boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select s.batch_id, s.batch_number, s.expiry_date, s.on_hand, (s.on_hand >= p_qty)
    from pharma_stock_positions s
   where pharma_can('pharma.view')
     and s.product_id = p_product
     and s.is_sellable
     and s.on_hand > 0
     and (p_warehouse is null or s.warehouse_id = p_warehouse)
   order by s.expiry_date asc;
$function$
;

CREATE OR REPLACE FUNCTION public.pharma_my_permissions()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select array(select p from unnest(array[
    'pharma.view','pharma.manage_master','pharma.manage_field','pharma.approve',
    'pharma.view_financial','pharma.view_medical','pharma.export','pharma.admin'
  ]) as p where pharma_can(p));
$function$
;

CREATE OR REPLACE FUNCTION public.pharma_offer_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_applies text[]; v_needs boolean;
begin
  select applies_to, requires_approval into v_applies, v_needs
    from pharma_offer_categories where code = new.category_code;
  if v_applies is not null and not (new.target_type = any(v_applies)) then
    raise exception 'Offer category % cannot target %. Permitted: %',
      new.category_code, new.target_type, array_to_string(v_applies, ', ');
  end if;

  if new.approval_status = 'approved' and coalesce(old.approval_status,'') <> 'approved' then
    if not (pharma_can('pharma.approve') or pharma_can('pharma.admin')) then
      raise exception 'You do not have pharma.approve. Only authorised management may approve a promotional offer.';
    end if;
    if new.compliance_status = 'blocked' then
      raise exception 'This offer is blocked by compliance review and cannot be approved.';
    end if;
    new.approved_by := auth.uid();
    new.approved_at := now();
  end if;

  -- A running offer must be approved. No informal schemes.
  if new.status = 'running' and new.approval_status <> 'approved' then
    raise exception 'An offer cannot run before it is approved.';
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.pharma_offer_target_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_dnc boolean; v_name text;
begin
  if new.doctor_id is not null then
    select do_not_contact, full_name into v_dnc, v_name from pharma_doctors where id = new.doctor_id;
    if v_dnc then
      raise exception '% is marked do-not-contact and cannot be targeted by a promotional offer.', v_name;
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.pharma_order_item_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_status text; v_exp date; v_hand numeric; v_batch text;
begin
  if new.batch_id is null then return new; end if;
  select quality_status, expiry_date, on_hand, batch_number
    into v_status, v_exp, v_hand, v_batch
    from pharma_stock_positions where batch_id = new.batch_id;

  if v_status = 'recalled' then
    raise exception 'Batch % is RECALLED and cannot be sold.', v_batch;
  end if;
  if v_exp is not null and v_exp < current_date then
    raise exception 'Batch % expired on % and cannot be sold.', v_batch, v_exp;
  end if;
  if coalesce(v_hand,0) < (new.quantity + coalesce(new.free_quantity,0)) then
    raise exception 'Batch % holds only %; cannot commit % units.',
      v_batch, coalesce(v_hand,0), new.quantity + coalesce(new.free_quantity,0);
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.pharma_pl(p_from date, p_to date)
 RETURNS TABLE(period date, revenue numeric, cogs numeric, gross_profit numeric, gross_margin_pct numeric, direct_selling numeric, distribution numeric, promotion numeric, regulatory numeric, contribution_margin numeric, contribution_margin_pct numeric, admin_overhead numeric, operating_profit numeric, depreciation numeric, amortisation numeric, ebitda numeric, ebitda_margin_pct numeric, cost_coverage_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not (pharma_can('pharma.view_financial') or pharma_can('pharma.admin')) then
    raise exception 'pharma.view_financial permission required to read profitability.';
  end if;
  return query
  with months as (
    select generate_series(date_trunc('month', p_from), date_trunc('month', p_to), interval '1 month')::date as period
  ),
  rev as (
    select r.period, sum(r.revenue) as revenue, sum(r.cogs) as cogs
      from pharma_revenue_lines r
     where r.order_date between p_from and p_to
     group by r.period
  ),
  cost as (
    select c.period,
           sum(c.allocated_amount) filter (where c.pl_layer = 'cogs')           as cogs_alloc,
           sum(c.allocated_amount) filter (where c.pl_layer = 'direct_selling') as direct_selling,
           sum(c.allocated_amount) filter (where c.pl_layer = 'distribution')   as distribution,
           sum(c.allocated_amount) filter (where c.pl_layer = 'promotion')      as promotion,
           sum(c.allocated_amount) filter (where c.pl_layer = 'regulatory')     as regulatory,
           sum(c.allocated_amount) filter (where c.pl_layer = 'admin_overhead') as admin_overhead,
           sum(c.allocated_amount) filter (where c.pl_layer = 'depreciation')   as depreciation,
           sum(c.allocated_amount) filter (where c.pl_layer = 'amortisation')   as amortisation
      from pharma_allocated_costs c
     where c.expense_date between p_from and p_to
     group by c.period
  ),
  cover as (
    select date_trunc('month', e.expense_date)::date as period,
           sum(e.amount) as total_ledger,
           sum(coalesce(a.alloc, 0)) as attributed
      from crm_expenses e
      left join (select crm_expense_id, sum(allocated_amount) as alloc
                   from pharma_allocated_costs group by crm_expense_id) a
             on a.crm_expense_id = e.id
     where e.deleted_at is null and e.expense_date between p_from and p_to
     group by 1
  )
  select m.period,
         coalesce(rev.revenue, 0),
         coalesce(rev.cogs, 0) + coalesce(cost.cogs_alloc, 0),
         coalesce(rev.revenue, 0) - (coalesce(rev.cogs, 0) + coalesce(cost.cogs_alloc, 0)),
         case when coalesce(rev.revenue,0) > 0
              then round((coalesce(rev.revenue,0) - (coalesce(rev.cogs,0) + coalesce(cost.cogs_alloc,0)))
                         / rev.revenue * 100, 2) end,
         coalesce(cost.direct_selling, 0),
         coalesce(cost.distribution, 0),
         coalesce(cost.promotion, 0),
         coalesce(cost.regulatory, 0),
         -- Contribution margin
         coalesce(rev.revenue,0) - (coalesce(rev.cogs,0) + coalesce(cost.cogs_alloc,0))
           - coalesce(cost.direct_selling,0) - coalesce(cost.distribution,0)
           - coalesce(cost.promotion,0) - coalesce(cost.regulatory,0),
         case when coalesce(rev.revenue,0) > 0
              then round((coalesce(rev.revenue,0) - (coalesce(rev.cogs,0) + coalesce(cost.cogs_alloc,0))
                          - coalesce(cost.direct_selling,0) - coalesce(cost.distribution,0)
                          - coalesce(cost.promotion,0) - coalesce(cost.regulatory,0))
                         / rev.revenue * 100, 2) end,
         coalesce(cost.admin_overhead, 0),
         -- Operating profit
         coalesce(rev.revenue,0) - (coalesce(rev.cogs,0) + coalesce(cost.cogs_alloc,0))
           - coalesce(cost.direct_selling,0) - coalesce(cost.distribution,0)
           - coalesce(cost.promotion,0) - coalesce(cost.regulatory,0)
           - coalesce(cost.admin_overhead,0),
         coalesce(cost.depreciation, 0),
         coalesce(cost.amortisation, 0),
         -- EBITDA = operating profit + depreciation + amortisation
         coalesce(rev.revenue,0) - (coalesce(rev.cogs,0) + coalesce(cost.cogs_alloc,0))
           - coalesce(cost.direct_selling,0) - coalesce(cost.distribution,0)
           - coalesce(cost.promotion,0) - coalesce(cost.regulatory,0)
           - coalesce(cost.admin_overhead,0)
           + coalesce(cost.depreciation,0) + coalesce(cost.amortisation,0),
         case when coalesce(rev.revenue,0) > 0
              then round((coalesce(rev.revenue,0) - (coalesce(rev.cogs,0) + coalesce(cost.cogs_alloc,0))
                          - coalesce(cost.direct_selling,0) - coalesce(cost.distribution,0)
                          - coalesce(cost.promotion,0) - coalesce(cost.regulatory,0)
                          - coalesce(cost.admin_overhead,0)
                          + coalesce(cost.depreciation,0) + coalesce(cost.amortisation,0))
                         / rev.revenue * 100, 2) end,
         -- How much of that month's ledger is actually attributed to pharma.
         -- Read this before you trust the EBITDA above it.
         case when coalesce(cover.total_ledger,0) > 0
              then round(coalesce(cover.attributed,0) / cover.total_ledger * 100, 1) end
    from months m
    left join rev  on rev.period  = m.period
    left join cost on cost.period = m.period
    left join cover on cover.period = m.period
   order by m.period;
end $function$
;

CREATE OR REPLACE FUNCTION public.pharma_recall_effect()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update pharma_inventory_batches
     set quality_status = 'recalled'
   where product_id = new.product_id and batch_number = new.batch_number;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.pharma_receipt_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.receipt_type = 'write_off' and not (pharma_can('pharma.approve') or pharma_can('pharma.admin')) then
    raise exception 'A write-off requires pharma.approve.';
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.pharma_sample_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_bal numeric; v_exp date; v_name text; v_dnc boolean; v_doc text;
begin
  select expiry_date, name into v_exp, v_name from pharma_sample_items where id = new.item_id;

  if new.txn_type like 'issue%' then
    if v_exp is not null and v_exp < current_date then
      raise exception 'Sample "%" expired on % and cannot be issued.', v_name, v_exp;
    end if;
    select balance into v_bal from pharma_sample_balances where item_id = new.item_id;
    if coalesce(v_bal,0) < new.quantity then
      raise exception 'Only % of "%" remain in stock; cannot issue %.', coalesce(v_bal,0), v_name, new.quantity;
    end if;
  end if;

  if new.doctor_id is not null then
    select do_not_contact, full_name into v_dnc, v_doc from pharma_doctors where id = new.doctor_id;
    if v_dnc then
      raise exception '% is marked do-not-contact. No samples may be issued to them.', v_doc;
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.pharma_spend_cap_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_cap numeric; v_used numeric; v_name text; v_dnc boolean;
begin
  if new.doctor_id is null then return new; end if;

  select annual_spend_cap, full_name, do_not_contact
    into v_cap, v_name, v_dnc from pharma_doctors where id = new.doctor_id;

  if v_dnc then
    raise exception '% is marked do-not-contact. No engagement spend may be recorded against them.', v_name;
  end if;

  if v_cap is null then
    return new;                       -- no cap set: allowed, and visible in reporting
  end if;

  select coalesce(sum(amount),0) into v_used
    from pharma_engagement_spend
   where doctor_id = new.doctor_id
     and date_trunc('year', spend_date) = date_trunc('year', new.spend_date)
     and (tg_op = 'INSERT' or id <> new.id);

  if v_used + new.amount > v_cap then
    raise exception 'Annual engagement cap exceeded for %. Cap % , already spent % , this entry % . Approve a higher cap or reduce the amount.',
      v_name, v_cap, v_used, new.amount;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.pharma_territory_options()
 RETURNS TABLE(id uuid, code text, name text, level text, path text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with recursive t as (
    select id, code, name, level, parent_id, name::text as path
      from pharma_territories where parent_id is null and is_active
    union all
    select c.id, c.code, c.name, c.level, c.parent_id, (t.path || ' › ' || c.name)::text
      from pharma_territories c join t on c.parent_id = t.id where c.is_active
  )
  select t.id, t.code, t.name, t.level, t.path from t
   where pharma_can('pharma.view') order by t.path;
$function$
;

CREATE OR REPLACE FUNCTION public.pharma_visit_after()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.status = 'completed' then
    if new.doctor_id is not null then
      update pharma_doctors set last_visit = new.visited_at::date,
             next_visit = coalesce(new.follow_up_date, next_visit)
       where id = new.doctor_id;
    elsif new.pharmacy_id is not null then
      update pharma_pharmacies set last_visit = new.visited_at::date,
             next_visit = coalesce(new.follow_up_date, next_visit)
       where id = new.pharmacy_id;
    elsif new.hospital_id is not null then
      update pharma_hospitals set last_contact = new.visited_at::date where id = new.hospital_id;
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.pharma_visit_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_dnc boolean; v_consent text; v_name text;
begin
  if new.doctor_id is not null then
    select do_not_contact, consent_status, full_name
      into v_dnc, v_consent, v_name from pharma_doctors where id = new.doctor_id;
    if v_dnc then
      raise exception '% is marked do-not-contact. This visit cannot be recorded.', v_name;
    end if;
    if v_consent = 'refused' then
      raise exception '% has refused contact consent. This visit cannot be recorded.', v_name;
    end if;
  end if;
  return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.social_is_manager()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(crm_has_role(array['owner','super_admin','ceo']::text[]), false);
$function$
;

CREATE OR REPLACE FUNCTION public.social_is_staff()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select public.is_admin()
      or exists (select 1 from public.crm_staff_roles where user_id = auth.uid());
$function$
;

CREATE OR REPLACE FUNCTION public.social_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

reset check_function_bodies;
