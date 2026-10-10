-- Additive, service-role-only Companies drill insights. The existing v2 monthly
-- grid and breakdown remain authoritative and unchanged.
-- Every aggregation uses the SAME integration cutoff, IST month, successful-work
-- classifier, internal-user exclusion and published ingestion watermark as v2.
CREATE OR REPLACE FUNCTION public.read_companies_monthly_insights_v1(
  p_company_id text,
  p_module text,
  p_user_key text DEFAULT NULL,
  p_usage_month date DEFAULT NULL
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'metrics_private', 'pg_temp'
SET statement_timeout TO '12s'
AS $fn$
WITH identity AS MATERIALIZED (
  SELECT i.company_id,i.company_name,i.integration_at,i.integration_month
  FROM metrics_private.company_monthly_identity i
  WHERE i.company_id=p_company_id AND NOT i.is_test
),
selected_month AS (
  SELECT date_trunc('month',coalesce(p_usage_month,current_date)::timestamp)::date AS month_start
),
anchor AS MATERIALIZED (
  SELECT i.company_id,i.company_name, m.month_start,
    greatest(m.month_start::timestamp AT TIME ZONE 'Asia/Kolkata',i.integration_at) AS start_at,
    (m.month_start+interval '1 month')::timestamp AT TIME ZONE 'Asia/Kolkata' AS end_at,
    wm.source_watermark_at
  FROM identity i CROSS JOIN selected_month m
  JOIN metrics_private.company_monthly_meta_v2 wm ON wm.singleton
  WHERE m.month_start>=i.integration_month
    AND p_module IN ('ap','ar','transactions','gst')
),
qualified AS MATERIALIZED (
  SELECT
    e.event_name,
    CASE
      WHEN e.event_name='Transaction Status' THEN 'status'
      WHEN e.event_name='Transaction Ledger Updated' THEN 'ledger'
      WHEN e.event_name='Transaction Type Updated' THEN 'type_change'
      WHEN e.event_name='Upload' THEN 'upload'
      WHEN e.event_name='Entity Created' THEN 'entity'
      WHEN e.event_name='Vendor Mismatch Resolved' THEN 'vendor_mismatch'
      WHEN e.event_name='Recon Processed' THEN 'reconciliation'
      WHEN e.event_name='Transaction Configuration Edited' THEN 'configuration'
      WHEN e.event_name='Invoice Bulk Edited' THEN 'invoice_edit'
      ELSE 'other'
    END AS category,
    e.event_time,
    (e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS activity_day,
    coalesce(nullif(btrim(e.distinct_id),''),'__unattributed__') AS user_key,
    nullif(btrim(e.email),'') AS email,
    nullif(left(btrim(e.properties->>'type'),80),'') AS event_type,
    nullif(left(btrim(e.properties->>'subType'),80),'') AS sub_type,
    nullif(left(btrim(e.properties->>'entityType'),80),'') AS entity_type,
    CASE
      WHEN (e.properties->>'transactionType') ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN 'Other / custom transaction type'
      ELSE nullif(left(btrim(e.properties->>'transactionType'),80),'')
    END AS transaction_type,
    nullif(left(btrim(e.properties->>'action'),80),'') AS action,
    nullif(left(btrim(e.properties->>'status'),80),'') AS status,
    nullif(left(btrim(e.properties->>'source'),80),'') AS source,
    nullif(left(btrim(e.properties->>'fileType'),120),'') AS file_type,
    nullif(left(btrim(e.properties->>'resolutionType'),80),'') AS resolution_type,
    public.company_items_for(e.event_name,coalesce(e.properties,'{}'::jsonb)) AS items
  FROM public.events e CROSS JOIN anchor a
  WHERE e.company_id=a.company_id
    AND e.event_time>=a.start_at AND e.event_time<a.end_at
    AND e.ingested_at<=a.source_watermark_at
    AND NOT public.is_internal_email(e.email)
    AND metrics_private.company_work_module_v2(
      e.event_name,coalesce(e.properties,'{}'::jsonb)
    )=p_module
    AND (
      p_user_key IS NULL
      OR (p_user_key='' AND nullif(btrim(e.distinct_id),'') IS NULL)
      OR (p_user_key<>'' AND e.distinct_id=p_user_key)
    )
),
summary AS MATERIALIZED (
 SELECT count(*)::bigint total,
   count(DISTINCT user_key) FILTER(WHERE user_key<>'__unattributed__')::integer active_users,
   count(DISTINCT activity_day)::integer active_days,
   count(*) FILTER(WHERE user_key='__unattributed__')::integer unattributed_events,
   sum(items)::bigint item_total,
   count(items)::integer instrumented_events,
   min(event_time) first_at, max(event_time) last_at
 FROM qualified
),
slices AS MATERIALIZED (
 SELECT category,event_name,event_type,sub_type,entity_type,transaction_type,
   action,status,source,file_type,resolution_type,
   count(*)::bigint events,
   sum(items)::bigint items,
   count(items)::integer instrumented,
   max(event_time) latest_at
 FROM qualified
 GROUP BY category,event_name,event_type,sub_type,entity_type,transaction_type,
    action,status,source,file_type,resolution_type
),
categories AS MATERIALIZED (
 SELECT category,count(*)::bigint events,
   sum(items)::bigint items,count(items)::integer instrumented
 FROM qualified GROUP BY category
),
daily AS MATERIALIZED (
 SELECT activity_day,count(*)::bigint events,
    count(DISTINCT user_key) FILTER(WHERE user_key<>'__unattributed__')::integer users
 FROM qualified GROUP BY activity_day
),
sources AS MATERIALIZED (
 SELECT coalesce(source,'Not captured') AS source,count(*)::bigint events
 FROM qualified GROUP BY coalesce(source,'Not captured')
),
user_groups AS MATERIALIZED (
 SELECT user_key,
  coalesce(max(email) FILTER(WHERE email IS NOT NULL), user_key) AS label,
  count(*)::bigint events,
  count(DISTINCT activity_day)::integer active_days,
  min(event_time) first_at,max(event_time) last_at,
  count(*) FILTER(WHERE category='status')::integer status_events,
  count(*) FILTER(WHERE category='ledger')::integer ledger_events,
  count(*) FILTER(WHERE category='type_change')::integer type_events,
  count(*) FILTER(WHERE category='upload')::integer upload_events,
  count(*) FILTER(WHERE category='entity')::integer entity_events,
  count(*) FILTER(WHERE category='vendor_mismatch')::integer vendor_events,
  count(*) FILTER(WHERE category='reconciliation')::integer reconciliation_events,
  count(*) FILTER(WHERE category IN ('other','configuration','invoice_edit'))::integer other_events
 FROM qualified GROUP BY user_key
),
top_users AS MATERIALIZED (
 SELECT * FROM user_groups ORDER BY events DESC,user_key LIMIT 50
)
SELECT jsonb_build_object(
 'contract','companies_monthly_drill_insights_v1',
 'company_id',a.company_id,
 'company_name',a.company_name,
 'module',p_module,
 'month',a.month_start,
 'user_key',p_user_key,
 'window_start',a.start_at,
 'window_end',a.end_at,
 'source_watermark_at',a.source_watermark_at,
 'total',s.total,
 'item_total',s.item_total,
 'instrumented_events',s.instrumented_events,
 'active_users',s.active_users,
 'active_days',s.active_days,
 'unattributed_events',s.unattributed_events,
 'first_at',s.first_at,
 'last_at',s.last_at,
 'user_groups_total',(SELECT count(*) FROM user_groups),
 'categories',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'key',c.category,'events',c.events,'items',c.items,
     'instrumented',c.instrumented
   ) ORDER BY c.events DESC,c.category) FROM categories c
 ),'[]'::jsonb),
 'slices',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'category',sl.category,'event',sl.event_name,'type',sl.event_type,
     'subtype',sl.sub_type,'entity_type',sl.entity_type,
     'transaction_type',sl.transaction_type,'action',sl.action,
     'status',sl.status,'source',sl.source,'file_type',sl.file_type,
     'resolution_type',sl.resolution_type,
     'events',sl.events,'items',sl.items,'instrumented',sl.instrumented,
     'latest_at',sl.latest_at
   ) ORDER BY sl.events DESC,sl.event_name,sl.status NULLS LAST)
   FROM slices sl
 ),'[]'::jsonb),
 'days',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'date',d.activity_day,'events',d.events,'users',d.users
   ) ORDER BY d.activity_day) FROM daily d
 ),'[]'::jsonb),
 'sources',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'source',src.source,'events',src.events
   ) ORDER BY src.events DESC,src.source) FROM sources src
 ),'[]'::jsonb),
 'users',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'id',u.user_key,'label',u.label,'events',u.events,
     'active_days',u.active_days,'first_at',u.first_at,'last_at',u.last_at,
     'counts',jsonb_build_object(
       'status',u.status_events,'ledger',u.ledger_events,
       'type_change',u.type_events,'upload',u.upload_events,
       'entity',u.entity_events,'vendor_mismatch',u.vendor_events,
       'reconciliation',u.reconciliation_events,'other',u.other_events
     )
   ) ORDER BY u.events DESC,u.user_key) FROM top_users u
 ),'[]'::jsonb)
)
FROM anchor a CROSS JOIN summary s;
$fn$;

REVOKE ALL ON FUNCTION public.read_companies_monthly_insights_v1(text,text,text,date)
 FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_companies_monthly_insights_v1(text,text,text,date)
 TO service_role;
