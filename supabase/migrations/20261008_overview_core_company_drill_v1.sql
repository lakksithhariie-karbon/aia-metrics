-- Snapshot-pinned company drill opened from an eligible user/company pair.
-- Returns authentic window activity, member users, weekly timeline and lifecycle facts.
CREATE OR REPLACE FUNCTION public.read_overview_core_company_v1(
 p_snapshot_id bigint,
 p_scope text,
 p_user_id text,
 p_company_id text
)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
SET statement_timeout TO '25s'
AS $function$
WITH published AS MATERIALIZED (
 SELECT s.id AS snapshot_id,
        (s.payload #>> '{value,active_users,as_of}')::timestamptz AS as_of_at,
        s.source_watermark_at,
        CASE WHEN p_scope='wau' THEN interval '7 days' ELSE interval '30 days' END AS period
 FROM public.product_snapshot_current c
 JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND c.snapshot_id=p_snapshot_id
   AND s.source_status='ok'
   AND p_scope IN ('wau','mau')
 LIMIT 1
),
qualified AS MATERIALIZED (
 SELECT e.distinct_id,e.email,e.event_time,e.event_name,
        (e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS day,
        date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS week_start,
        CASE
         WHEN e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill'
           OR e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill'
           OR e.event_name='Vendor Mismatch Resolved' THEN 'ap'
         WHEN e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice'
           OR e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice'
           OR e.event_name='Invoice Bulk Edited' THEN 'ar'
         ELSE 'transactions'
        END AS module
 FROM public.events e CROSS JOIN published p
 WHERE e.company_id=p_company_id
   AND EXISTS(SELECT 1 FROM public.client_company c WHERE c.company_id=e.company_id)
   AND e.event_time >= p.as_of_at-p.period AND e.event_time < p.as_of_at
   AND e.ingested_at <= p.source_watermark_at
   AND e.distinct_id IS NOT NULL AND e.distinct_id <> ''
   AND e.event_name <> 'Accounting Sync'
   AND public.is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
),
authorized AS (
 SELECT 1 AS allow FROM qualified WHERE distinct_id=p_user_id LIMIT 1
),
company_summary AS (
 SELECT count(*)::integer AS core_actions,
   count(DISTINCT distinct_id)::integer AS active_users,
   count(DISTINCT day)::integer AS active_days,
   min(event_time) AS first_activity_at,
   max(event_time) AS last_activity_at,
   count(*) FILTER(WHERE module='ap')::integer AS ap,
   count(*) FILTER(WHERE module='ar')::integer AS ar,
   count(*) FILTER(WHERE module='transactions')::integer AS transactions
 FROM qualified
),
membership AS MATERIALIZED (
 SELECT q.distinct_id AS id,max(nullif(q.email,'')) AS email,
   count(*)::integer AS actions,
   count(DISTINCT q.day)::integer AS active_days,
   max(q.event_time) AS last_active_at,
   count(*) FILTER(WHERE q.module='ap')::integer AS ap,
   count(*) FILTER(WHERE q.module='ar')::integer AS ar,
   count(*) FILTER(WHERE q.module='transactions')::integer AS transactions
 FROM qualified q GROUP BY q.distinct_id
),
period_weeks AS MATERIALIZED (
 SELECT week_start,count(*)::integer AS actions,
   count(DISTINCT distinct_id)::integer AS active_users,
   count(*) FILTER(WHERE module='ap')::integer AS ap,
   count(*) FILTER(WHERE module='ar')::integer AS ar,
   count(*) FILTER(WHERE module='transactions')::integer AS transactions
 FROM qualified GROUP BY week_start
),
milestones AS (
 SELECT
   min(e.event_time) FILTER(WHERE e.event_name='Company Created') AS first_created_at,
   min(e.event_time) FILTER(WHERE public.is_successful_integration(e.event_name,e.properties)) AS integration_at,
   min(e.event_time) FILTER(WHERE public.is_qualifying_sync(e.event_name,e.properties)) AS first_sync_at,
   max(e.event_time) FILTER(WHERE public.is_qualifying_sync(e.event_name,e.properties)) AS last_sync_at
 FROM public.events e CROSS JOIN published p
 WHERE e.company_id=p_company_id AND e.event_time<p.as_of_at
   AND e.ingested_at<=p.source_watermark_at
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
)
SELECT jsonb_build_object(
 'snapshot_id',p.snapshot_id,
 'scope',p_scope,
 'as_of',p.as_of_at,
 'source_watermark_at',p.source_watermark_at,
 'focus_user_id',p_user_id,
 'company',jsonb_build_object(
   'id',p_company_id,
   'name',coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),p_company_id),
   'is_test',coalesce(d.is_test,false)
 ),
 'window',jsonb_build_object('start',p.as_of_at-p.period,'end',p.as_of_at,'days',
                            CASE WHEN p_scope='wau' THEN 7 ELSE 30 END),
 'stats',jsonb_build_object(
   'core_actions',s.core_actions,'active_users',s.active_users,'active_days',s.active_days,
   'first_activity_at',s.first_activity_at,'last_activity_at',s.last_activity_at,
   'modules',jsonb_build_object('ap',s.ap,'ar',s.ar,'transactions',s.transactions)
 ),
 'milestones',jsonb_build_object(
   'company_created_at',coalesce(cp.signed_up_at,m.first_created_at),
   'integration_at',m.integration_at,
   'first_independent_activity_at',s.first_activity_at,
   'first_qualifying_sync_at',m.first_sync_at,
   'last_qualifying_sync_at',m.last_sync_at
 ),
 'users',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'id',u.id,'email',coalesce(u.email,u.id),
     'actions',u.actions,'active_days',u.active_days,'last_active_at',u.last_active_at,
     'modules',jsonb_build_object('ap',u.ap,'ar',u.ar,'transactions',u.transactions)
   ) ORDER BY u.actions DESC,u.id) FROM membership u
 ),'[]'::jsonb),
 'weeks',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'week_start',w.week_start,'actions',w.actions,'active_users',w.active_users,
     'modules',jsonb_build_object('ap',w.ap,'ar',w.ar,'transactions',w.transactions)
   ) ORDER BY w.week_start) FROM period_weeks w
 ),'[]'::jsonb),
 'recent_events',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'at',q.event_time,'event',q.event_name,'module',q.module,
     'user_id',q.distinct_id,'user_email',coalesce(nullif(q.email,''),q.distinct_id)
   ) ORDER BY q.event_time DESC)
   FROM (
     SELECT event_time,event_name,module,distinct_id,email
     FROM qualified ORDER BY event_time DESC LIMIT 30
   ) q
 ),'[]'::jsonb)
)
FROM published p CROSS JOIN authorized a CROSS JOIN company_summary s
LEFT JOIN public.company_directory d ON d.company_uuid::text=p_company_id
LEFT JOIN public.company_profile cp ON cp.company_id=p_company_id
CROSS JOIN milestones m;
$function$;

REVOKE ALL ON FUNCTION public.read_overview_core_company_v1(bigint,text,text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_core_company_v1(bigint,text,text,text)
 TO service_role;
