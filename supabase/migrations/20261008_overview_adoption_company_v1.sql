-- Full snapshot-pinned company profile for the mature integration cohort.
-- All activity is restricted to the first 28 days after recorded integration.
CREATE OR REPLACE FUNCTION public.read_overview_adoption_company_v1(
  p_snapshot_id bigint,
  p_company_id text
)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
SET statement_timeout TO '35s'
AS $function$
WITH published AS MATERIALIZED (
 SELECT s.id,
 (s.payload#>>'{value,active_users,as_of}')::timestamptz AS as_of_at,
 s.source_watermark_at
 FROM public.product_snapshot_current c JOIN public.product_snapshot s
 ON s.id=c.snapshot_id WHERE c.kind='overview' AND c.scope_key=''
 AND c.snapshot_id=p_snapshot_id AND s.source_status='ok' LIMIT 1
),
fact AS MATERIALIZED (
 SELECT f.* FROM published p CROSS JOIN LATERAL
 public.overview_adoption_company_facts_v1(p.id) f
 WHERE f.company_id=p_company_id
),
qualified AS MATERIALIZED (
 SELECT e.event_time,e.distinct_id,
 coalesce(nullif(e.email,''),e.distinct_id) AS email,
 e.event_name,e.properties,
 floor(extract(epoch FROM (e.event_time-f.integrated_at))/604800)::int AS week_index,
 (e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS day,
 public.is_qualifying_sync(e.event_name,e.properties) AS is_sync,
 (e.event_name<>'Accounting Sync' AND public.is_core_activity(e.event_name,e.properties)) AS is_work,
 CASE
  WHEN e.event_name='Accounting Sync' THEN 'sync'
  WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill')
   OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill')
   OR e.event_name='Vendor Mismatch Resolved' THEN 'ap'
  WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice')
   OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice')
   OR e.event_name='Invoice Bulk Edited' THEN 'ar'
  ELSE 'transactions'
 END AS module
 FROM fact f JOIN public.events e ON e.company_id=f.company_id
 CROSS JOIN published p
 WHERE e.event_time>=f.integrated_at
 AND e.event_time<f.integrated_at+interval '28 days'
 AND e.event_time<p.as_of_at AND e.ingested_at<=p.source_watermark_at
 AND e.distinct_id IS NOT NULL AND e.distinct_id<>''
 AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
 AND NOT metrics_private.is_retention_internal_email_v2(e.email)
 AND (public.is_qualifying_sync(e.event_name,e.properties)
 OR (e.event_name<>'Accounting Sync' AND public.is_core_activity(e.event_name,e.properties)))
),
users AS (
 SELECT q.distinct_id AS id,max(q.email) AS email,
 count(*) FILTER(WHERE q.is_work)::int AS core_actions,
 count(*) FILTER(WHERE q.is_sync)::int AS sync_events,
 count(DISTINCT q.day) FILTER(WHERE q.is_work)::int AS core_days,
 min(q.event_time) FILTER(WHERE q.is_work) AS first_core_at,
 max(q.event_time) FILTER(WHERE q.is_work) AS last_core_at,
 count(*) FILTER(WHERE q.module='ap' AND q.is_work)::int AS ap,
 count(*) FILTER(WHERE q.module='ar' AND q.is_work)::int AS ar,
 count(*) FILTER(WHERE q.module='transactions' AND q.is_work)::int AS txn
 FROM qualified q GROUP BY q.distinct_id
),
weeks AS (
 SELECT g.i AS relative_week,
  count(q.event_time) FILTER(WHERE q.is_work)::int AS core_actions,
  count(DISTINCT q.distinct_id) FILTER(WHERE q.is_work)::int AS active_users,
  count(*) FILTER(WHERE q.is_work AND q.module='ap')::int AS ap,
  count(*) FILTER(WHERE q.is_work AND q.module='ar')::int AS ar,
  count(*) FILTER(WHERE q.is_work AND q.module='transactions')::int AS txn,
  count(*) FILTER(WHERE q.is_sync)::int AS sync_events
 FROM generate_series(0,3) g(i)
 LEFT JOIN qualified q ON q.week_index=g.i
 GROUP BY g.i
)
SELECT jsonb_build_object(
 'contract','mature_independent_adoption_company_v1',
 'snapshot_id',p.id,
 'as_of',p.as_of_at,
 'source_watermark_at',p.source_watermark_at,
 'company',jsonb_build_object(
   'id',f.company_id,'name',f.company_name,
   'integration_type',f.integration_type,'is_test',f.is_test
 ),
 'window',jsonb_build_object(
   'start',f.integrated_at,'end',f.integrated_at+interval '28 days','days',28
 ),
 'outcomes',jsonb_build_object(
   'core_7d',f.first_core_7d_at IS NOT NULL,
   'value_28d',f.value_at IS NOT NULL,
   'sustained_28d',f.active_weeks>=2,
   'sync_after_core',f.first_sync_after_core_at IS NOT NULL
 ),
 'stats',jsonb_build_object(
   'core_actions',f.core_actions,'sync_events',f.sync_events,
   'active_weeks',f.active_weeks,
   'active_users',(SELECT count(*) FROM users WHERE core_actions>0),
   'last_core_at',f.last_core_at,
   'modules',jsonb_build_object('ap',f.ap_actions,'ar',f.ar_actions,
                                'transactions',f.transaction_actions)
 ),
 'milestones',jsonb_build_object(
   'integration_at',f.integrated_at,
   'first_core_7d_at',f.first_core_7d_at,
   'first_core_28d_at',f.first_core_28d_at,
   'training_sync_at',f.training_sync_at,
   'post_training_core_at',f.post_training_core_at,
   'sync_after_core_at',f.first_sync_after_core_at,
   'value_at',f.value_at
 ),
 'users',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
    'id',u.id,'email',u.email,
    'core_actions',u.core_actions,'sync_events',u.sync_events,
    'core_days',u.core_days,'first_core_at',u.first_core_at,
    'last_core_at',u.last_core_at,
    'modules',jsonb_build_object('ap',u.ap,'ar',u.ar,'transactions',u.txn)
  ) ORDER BY u.core_actions DESC,u.id)
  FROM users u
 ),'[]'::jsonb),
 'weeks',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'week',w.relative_week+1,
     'start',f.integrated_at+w.relative_week*interval '7 days',
     'core_actions',w.core_actions,'active_users',w.active_users,
     'sync_events',w.sync_events,
     'modules',jsonb_build_object('ap',w.ap,'ar',w.ar,'transactions',w.txn)
   ) ORDER BY w.relative_week) FROM weeks w
 ),'[]'::jsonb),
 'recent_events',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'at',e.event_time,'event',e.event_name,'module',e.module,
     'email',e.email,'user_id',e.distinct_id
   ) ORDER BY e.event_time DESC)
   FROM (SELECT * FROM qualified ORDER BY event_time DESC LIMIT 30) e
 ),'[]'::jsonb)
)
FROM published p JOIN fact f ON true;
$function$;

REVOKE ALL ON FUNCTION public.read_overview_adoption_company_v1(bigint,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_adoption_company_v1(bigint,text)
 TO service_role;
