-- Snapshot-pinned, authorized company profile from a selected Workflow Usage
-- week/module or 28-day module combination. Company totals include all modules
-- in the selected period, while the parent chart membership is module-specific.
CREATE OR REPLACE FUNCTION public.read_overview_workflow_company_v1(
 p_snapshot_id bigint,
 p_scope text,
 p_company_id text,
 p_week text DEFAULT '',
 p_module text DEFAULT '',
 p_mask text DEFAULT '',
 p_user_id text DEFAULT ''
)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED (
 SELECT s.id,(s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
 s.source_watermark_at wm,
 date_trunc('week',(s.payload#>>'{value,active_users,as_of}')::timestamptz
   AT TIME ZONE 'Asia/Kolkata')::date AS this_week
 FROM product_snapshot_current c JOIN product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND c.snapshot_id=p_snapshot_id
 AND s.source_status='ok' LIMIT 1
),
scope AS(
 SELECT p.*,
 CASE WHEN p_scope='weekly' THEN (p_week::date::timestamp AT TIME ZONE 'Asia/Kolkata')
      WHEN p_scope='previous' THEN p.asof-interval '56 days'
      ELSE p.asof-interval '28 days' END AS from_at,
 CASE WHEN p_scope='weekly' THEN ((p_week::date+7)::timestamp AT TIME ZONE 'Asia/Kolkata')
      WHEN p_scope='previous' THEN p.asof-interval '28 days'
      ELSE p.asof END AS to_at
 FROM p
 WHERE (p_scope='weekly' AND p_week ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
  AND (p.this_week-p_week::date) BETWEEN 7 AND 84
  AND (p.this_week-p_week::date)%7=0
  AND p_module IN ('ap','ar','transactions')
  AND p_user_id <> '')
 OR (p_scope IN ('current','previous')
  AND p_mask IN ('100','010','001','110','101','011','111','000'))
),
ev AS MATERIALIZED (
 SELECT e.* FROM scope s CROSS JOIN LATERAL
 public.overview_workflow_events_v1(s.id) e
 WHERE e.company_id=p_company_id
 AND e.event_time>=s.from_at AND e.event_time<s.to_at
),
company_mask AS(
 SELECT (CASE WHEN bool_or(module='ap') THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(module='ar') THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(module='transactions') THEN '1' ELSE '0' END) AS mask
 FROM ev
),
authorized AS(
 SELECT 1 AS allowed
 FROM scope s CROSS JOIN company_mask m
 WHERE
 (p_scope='weekly' AND EXISTS(
    SELECT 1 FROM ev e WHERE e.distinct_id=p_user_id AND e.module=p_module
 ))
 OR (p_scope IN ('current','previous') AND m.mask=p_mask AND EXISTS(SELECT 1 FROM ev))
 LIMIT 1
),
summary AS(
 SELECT count(*)::int AS core_actions,
 count(DISTINCT distinct_id)::int AS active_users,
 count(DISTINCT activity_day)::int AS active_days,
 min(event_time) first_at,
 max(event_time) last_at,
 count(*) FILTER(WHERE module='ap')::int AS ap,
 count(*) FILTER(WHERE module='ar')::int AS ar,
 count(*) FILTER(WHERE module='transactions')::int AS transactions
 FROM ev
),
members AS MATERIALIZED(
 SELECT distinct_id AS id,max(nullif(email,'')) email,
 count(*)::int AS core_actions,
 count(DISTINCT activity_day)::int AS active_days,
 max(event_time) AS last_at,
 count(*) FILTER(WHERE module='ap')::int ap,
 count(*) FILTER(WHERE module='ar')::int ar,
 count(*) FILTER(WHERE module='transactions')::int transactions
 FROM ev GROUP BY distinct_id
),
week_history AS(
 SELECT week_start,
 count(*)::int core_actions,count(DISTINCT distinct_id)::int active_users,
 count(*) FILTER(WHERE module='ap')::int ap,
 count(*) FILTER(WHERE module='ar')::int ar,
 count(*) FILTER(WHERE module='transactions')::int transactions
 FROM ev GROUP BY week_start
),
milestones AS (
 SELECT
 min(e.event_time) FILTER(WHERE e.event_name='Company Created') created_at,
 min(e.event_time) FILTER(WHERE public.is_successful_integration(e.event_name,e.properties)) AS integrated_at,
 max(e.event_time) FILTER(WHERE public.is_qualifying_sync(e.event_name,e.properties)) AS last_sync_at
 FROM events e CROSS JOIN scope s
 WHERE e.company_id=p_company_id AND e.event_time<s.asof AND e.ingested_at<=s.wm
 AND NOT metrics_private.is_retention_internal_email_v2(e.email)
)
SELECT jsonb_build_object(
 'contract','independent_workflow_company_v1',
 'snapshot_id',s.id,'scope',p_scope,
 'as_of',s.asof,'source_watermark_at',s.wm,
 'focus_user_id',CASE WHEN p_scope='weekly' THEN p_user_id ELSE NULL END,
 'selected_module',CASE WHEN p_scope='weekly' THEN p_module ELSE NULL END,
 'mask',CASE WHEN p_scope='weekly' THEN NULL ELSE p_mask END,
 'company',jsonb_build_object(
   'id',p_company_id,
   'name',coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),
      (SELECT max(nullif(event_company_name,'')) FROM ev),p_company_id),
   'is_test',coalesce(d.is_test,false)
 ),
 'window',jsonb_build_object(
   'start',s.from_at,'end',s.to_at,
   'days',CASE WHEN p_scope='weekly' THEN 7 ELSE 28 END
 ),
 'stats',jsonb_build_object(
   'core_actions',a.core_actions,
   'active_users',a.active_users,
   'active_days',a.active_days,
   'first_activity_at',a.first_at,'last_activity_at',a.last_at,
   'modules',jsonb_build_object('ap',a.ap,'ar',a.ar,'transactions',a.transactions)
 ),
 'milestones',jsonb_build_object(
   'company_created_at',coalesce(cp.signed_up_at,m.created_at),
   'integration_at',m.integrated_at,'last_qualifying_sync_at',m.last_sync_at
 ),
 'users',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'id',u.id,'email',coalesce(u.email,u.id),
     'core_actions',u.core_actions,'active_days',u.active_days,
     'last_active_at',u.last_at,
     'modules',jsonb_build_object('ap',u.ap,'ar',u.ar,'transactions',u.transactions)
   ) ORDER BY u.core_actions DESC,u.id) FROM members u
 ),'[]'::jsonb),
 'weeks',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
    'week_start',w.week_start,'core_actions',w.core_actions,
    'active_users',w.active_users,
    'modules',jsonb_build_object('ap',w.ap,'ar',w.ar,'transactions',w.transactions)
  ) ORDER BY w.week_start) FROM week_history w
 ),'[]'::jsonb),
 'recent_events',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
    'at',t.event_time,'event',t.event_name,'module',t.module,
    'user_id',t.distinct_id,'email',coalesce(nullif(t.email,''),t.distinct_id)
  ) ORDER BY t.event_time DESC)
  FROM (SELECT * FROM ev ORDER BY event_time DESC LIMIT 30) t
 ),'[]'::jsonb)
)
FROM scope s CROSS JOIN authorized au CROSS JOIN summary a
LEFT JOIN company_directory d ON d.company_uuid::text=p_company_id
LEFT JOIN company_profile cp ON cp.company_id=p_company_id
CROSS JOIN milestones m;
$function$;
REVOKE ALL ON FUNCTION public.read_overview_workflow_company_v1(bigint,text,text,text,text,text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_workflow_company_v1(bigint,text,text,text,text,text,text)
 TO service_role;
