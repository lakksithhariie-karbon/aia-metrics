-- Full company context for selected weekly/frequency chart member.
-- The selected user must match both the clicked chart population and company.
CREATE OR REPLACE FUNCTION public.read_overview_active_chart_company_v1(
 p_snapshot_id bigint,
 p_kind text,
 p_key text,
 p_segment text,
 p_user_id text,
 p_company_id text
)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
SET statement_timeout TO '30s'
AS $function$
WITH published AS MATERIALIZED (
 SELECT s.id AS snapshot_id,
   (s.payload#>>'{value,active_users,as_of}')::timestamptz AS as_of_at,
   s.source_watermark_at AS watermark,
   date_trunc('week',(s.payload#>>'{value,active_users,as_of}')::timestamptz
    AT TIME ZONE 'Asia/Kolkata')::date AS current_week
 FROM public.product_snapshot_current c
 JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
   AND c.snapshot_id=p_snapshot_id
 LIMIT 1
),
scope AS (
 SELECT p.*,
   CASE WHEN p_kind='weekly' THEN p_key::date
        ELSE p.current_week-28 END AS from_date,
   CASE WHEN p_kind='weekly' THEN 7 ELSE 28 END AS window_days,
   CASE WHEN p_kind='frequency' THEN p_key::int ELSE null::int END AS frequency_weeks
 FROM published p
 WHERE (p_kind='weekly' AND p_key~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        AND (p.current_week-p_key::date) BETWEEN 7 AND 84
        AND (p.current_week-p_key::date)%7=0
        AND p_segment IN ('all','returning','first_observed'))
    OR (p_kind='frequency' AND p_key IN ('1','2','3','4') AND p_segment='all')
),
focus_history AS (
 SELECT min(date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date)
        AS first_week
 FROM public.events e CROSS JOIN scope s
 WHERE e.distinct_id=p_user_id AND e.event_time<s.as_of_at
   AND e.ingested_at<=s.watermark
   AND e.event_name<>'Accounting Sync'
   AND public.is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
   AND EXISTS(SELECT 1 FROM public.client_company c WHERE c.company_id=e.company_id)
),
focus_frequency AS (
 SELECT count(DISTINCT date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date)::int AS weeks
 FROM public.events e CROSS JOIN scope s
 WHERE e.distinct_id=p_user_id
   AND e.event_time >= ((s.current_week-28)::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.event_time < (s.current_week::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.ingested_at<=s.watermark
   AND e.event_name<>'Accounting Sync'
   AND public.is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
   AND EXISTS(SELECT 1 FROM public.client_company c WHERE c.company_id=e.company_id)
),
qualified AS MATERIALIZED (
 SELECT e.distinct_id,e.email,e.event_time,e.event_name,
   (e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS day,
   date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS week_start,
   CASE
     WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill')
       OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill')
       OR e.event_name='Vendor Mismatch Resolved' THEN 'ap'
     WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice')
       OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice')
       OR e.event_name='Invoice Bulk Edited' THEN 'ar'
     ELSE 'transactions'
   END AS module
 FROM public.events e CROSS JOIN scope s
 WHERE e.company_id=p_company_id
   AND EXISTS(SELECT 1 FROM public.client_company cc WHERE cc.company_id=e.company_id)
   AND e.event_time >= (s.from_date::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.event_time < ((s.from_date+s.window_days)::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.ingested_at<=s.watermark
   AND e.distinct_id IS NOT NULL AND e.distinct_id <> ''
   AND e.event_name<>'Accounting Sync'
   AND public.is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
),
authorized AS (
 SELECT 1 AS allow
 FROM qualified q CROSS JOIN scope s
 CROSS JOIN focus_history f CROSS JOIN focus_frequency fw
 WHERE q.distinct_id=p_user_id
   AND CASE WHEN p_kind='weekly' THEN
      CASE p_segment WHEN 'first_observed' THEN f.first_week=s.from_date
                     WHEN 'returning' THEN f.first_week<s.from_date
                     ELSE true END
     ELSE fw.weeks=s.frequency_weeks END
 LIMIT 1
),
company_summary AS (
 SELECT count(*)::int AS core_actions,
    count(DISTINCT distinct_id)::int AS active_users,
    count(DISTINCT day)::int AS active_days,
    min(event_time) AS first_activity_at,
    max(event_time) AS last_activity_at,
    count(*) FILTER(WHERE module='ap')::int AS ap,
    count(*) FILTER(WHERE module='ar')::int AS ar,
    count(*) FILTER(WHERE module='transactions')::int AS transactions
 FROM qualified
),
members AS MATERIALIZED (
 SELECT q.distinct_id AS id,max(nullif(q.email,'')) AS email,
   count(*)::int AS actions,
   count(DISTINCT q.day)::int AS active_days,
   max(q.event_time) AS last_active_at,
   count(*) FILTER(WHERE q.module='ap')::int AS ap,
   count(*) FILTER(WHERE q.module='ar')::int AS ar,
   count(*) FILTER(WHERE q.module='transactions')::int AS transactions
 FROM qualified q GROUP BY q.distinct_id
),
weeks AS MATERIALIZED (
 SELECT week_start,count(*)::int AS actions,
    count(DISTINCT distinct_id)::int AS active_users,
    count(*) FILTER(WHERE module='ap')::int AS ap,
    count(*) FILTER(WHERE module='ar')::int AS ar,
    count(*) FILTER(WHERE module='transactions')::int AS transactions
 FROM qualified GROUP BY week_start
),
milestones AS (
 SELECT min(e.event_time) FILTER(WHERE e.event_name='Company Created') AS created_at,
   min(e.event_time) FILTER(WHERE public.is_successful_integration(e.event_name,e.properties)) AS integration_at,
   min(e.event_time) FILTER(WHERE public.is_qualifying_sync(e.event_name,e.properties)) AS first_sync_at,
   max(e.event_time) FILTER(WHERE public.is_qualifying_sync(e.event_name,e.properties)) AS last_sync_at
 FROM public.events e CROSS JOIN scope s
 WHERE e.company_id=p_company_id AND e.event_time<s.as_of_at
   AND e.ingested_at<=s.watermark
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
)
SELECT jsonb_build_object(
 'snapshot_id',s.snapshot_id,
 'scope',p_kind,
 'as_of',s.as_of_at,
 'source_watermark_at',s.watermark,
 'focus_user_id',p_user_id,
 'company',jsonb_build_object(
    'id',p_company_id,
    'name',coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),p_company_id),
    'is_test',coalesce(d.is_test,false)
 ),
 'window',jsonb_build_object(
    'start',(s.from_date::timestamp AT TIME ZONE 'Asia/Kolkata'),
    'end',((s.from_date+s.window_days)::timestamp AT TIME ZONE 'Asia/Kolkata'),
    'days',s.window_days
 ),
 'stats',jsonb_build_object(
    'core_actions',a.core_actions,
    'active_users',a.active_users,'active_days',a.active_days,
    'first_activity_at',a.first_activity_at,'last_activity_at',a.last_activity_at,
    'modules',jsonb_build_object('ap',a.ap,'ar',a.ar,'transactions',a.transactions)
 ),
 'milestones',jsonb_build_object(
    'company_created_at',coalesce(cp.signed_up_at,m.created_at),
    'integration_at',m.integration_at,
    'first_independent_activity_at',a.first_activity_at,
    'first_qualifying_sync_at',m.first_sync_at,
    'last_qualifying_sync_at',m.last_sync_at
 ),
 'users',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'id',u.id,'email',coalesce(u.email,u.id),
     'actions',u.actions,'active_days',u.active_days,'last_active_at',u.last_active_at,
     'modules',jsonb_build_object('ap',u.ap,'ar',u.ar,'transactions',u.transactions)
   ) ORDER BY u.actions DESC,u.id) FROM members u
 ),'[]'::jsonb),
 'weeks',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'week_start',w.week_start,'actions',w.actions,'active_users',w.active_users,
     'modules',jsonb_build_object('ap',w.ap,'ar',w.ar,'transactions',w.transactions)
   ) ORDER BY w.week_start) FROM weeks w
 ),'[]'::jsonb),
 'recent_events',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'at',q.event_time,'event',q.event_name,'module',q.module,
     'user_id',q.distinct_id,
     'user_email',coalesce(nullif(q.email,''),q.distinct_id)
   ) ORDER BY q.event_time DESC)
   FROM (SELECT * FROM qualified ORDER BY event_time DESC LIMIT 30) q
 ),'[]'::jsonb)
)
FROM scope s CROSS JOIN authorized x CROSS JOIN company_summary a
LEFT JOIN public.company_directory d ON d.company_uuid::text=p_company_id
LEFT JOIN public.company_profile cp ON cp.company_id=p_company_id
CROSS JOIN milestones m;
$function$;

REVOKE ALL ON FUNCTION public.read_overview_active_chart_company_v1(
 bigint,text,text,text,text,text
) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_active_chart_company_v1(
 bigint,text,text,text,text,text
) TO service_role;
