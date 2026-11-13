-- Exact original public Product read RPCs, part 8/12, backed up 2026-11-07.
-- Rollback only. Original data and function grants remain in place.
-- Apply this together with all other Product rollback parts if a cutover must be reversed.
SET LOCAL lock_timeout='7s';

CREATE OR REPLACE FUNCTION public.read_overview_independent_core_kpis_v4(p_snapshot_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '30s'
AS $function$
DECLARE
  v_snapshot_id bigint;
  v_source_watermark_at timestamptz;
  v_as_of_at timestamptz;
  v_cached jsonb;
BEGIN
  SELECT
    s.id,
    s.source_watermark_at,
    (s.payload #>> '{value,active_users,as_of}')::timestamptz
  INTO v_snapshot_id, v_source_watermark_at, v_as_of_at
  FROM public.product_snapshot s
  WHERE s.kind = 'overview'
    AND s.id = COALESCE(
      p_snapshot_id,
      (SELECT c.snapshot_id
       FROM public.product_snapshot_current c
       WHERE c.kind = 'overview' AND c.scope_key = '' LIMIT 1)
    )
    AND (
      s.scope_key = ''
      OR s.scope_key = 'asof=' || to_char(
        (s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date, 'YYYY-MM-DD'
      )
    )
    AND s.source_status = 'ok'
  LIMIT 1;

  IF v_snapshot_id IS NULL THEN RETURN NULL; END IF;

  SELECT c.kpis INTO v_cached
  FROM metrics_private.overview_independent_core_kpi_cache_v1 c
  WHERE c.snapshot_id = v_snapshot_id
    AND c.source_watermark_at IS NOT DISTINCT FROM v_source_watermark_at
    AND c.as_of_at IS NOT DISTINCT FROM v_as_of_at
    AND c.kpis ->> 'contract' = 'independent_core_v1'
    AND c.kpis ->> 'snapshot_id' = v_snapshot_id::text
    AND (c.kpis ->> 'as_of')::timestamptz = v_as_of_at
    AND (c.kpis ->> 'source_watermark_at')::timestamptz = v_source_watermark_at;

  IF v_cached IS NOT NULL THEN RETURN v_cached; END IF;

  RETURN public.read_overview_independent_core_kpis_v3(v_snapshot_id);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_members(p_snapshot_id bigint, p_kind text, p_drill_key text, p_tab text, p_limit integer, p_offset integer)
 RETURNS TABLE(card jsonb, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT f.card, t.total_count
  FROM (
    SELECT count(*) AS total_count
    FROM public.product_overview_member AS m
    WHERE m.snapshot_id = p_snapshot_id
      AND m.kind = p_kind
      AND m.drill_key = p_drill_key
      AND m.tab = p_tab
  ) AS t
  LEFT JOIN LATERAL (
    SELECT m.card
    FROM public.product_overview_member AS m
    WHERE m.snapshot_id = p_snapshot_id
      AND m.kind = p_kind
      AND m.drill_key = p_drill_key
      AND m.tab = p_tab
    ORDER BY m.sort_position
    LIMIT p_limit
    OFFSET GREATEST(COALESCE(p_offset, 0), 0)
  ) AS f ON true;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_tab_counts(p_snapshot_id bigint, p_kind text, p_drill_key text)
 RETURNS TABLE(tab text, member_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT m.tab, count(*) AS member_count
  FROM public.product_overview_member AS m
  WHERE m.snapshot_id = p_snapshot_id
    AND m.kind = p_kind
    AND m.drill_key = p_drill_key
  GROUP BY m.tab;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_workflow_charts_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED (
 SELECT s.id,
  (s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
  s.source_watermark_at AS watermark,
  date_trunc('week',(s.payload#>>'{value,active_users,as_of}')::timestamptz
    AT TIME ZONE 'Asia/Kolkata')::date AS this_week
 FROM public.product_snapshot_current c
 JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
 LIMIT 1
),
ev AS MATERIALIZED (
 SELECT e.* FROM p CROSS JOIN LATERAL public.overview_workflow_events_v1(p.id) e
),
weeks AS(
 SELECT (p.this_week - gs.i*7)::date AS week_start
 FROM p CROSS JOIN generate_series(12,1,-1) gs(i)
),
weekly AS (
 SELECT w.week_start,
 count(DISTINCT e.distinct_id)::integer AS total,
 count(DISTINCT e.distinct_id) FILTER(WHERE e.module='ap')::integer AS ap,
 count(DISTINCT e.distinct_id) FILTER(WHERE e.module='ar')::integer AS ar,
 count(DISTINCT e.distinct_id) FILTER(WHERE e.module='transactions')::integer AS transactions
 FROM weeks w LEFT JOIN ev e ON e.week_start=w.week_start
 GROUP BY w.week_start
),
company_masks AS (
 SELECT CASE WHEN e.event_time>=p.asof-interval '28 days' THEN 'current' ELSE 'previous' END AS period,
 e.company_id,
 (CASE WHEN bool_or(e.module='ap') THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(e.module='ar') THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(e.module='transactions') THEN '1' ELSE '0' END) AS mask
 FROM ev e CROSS JOIN p
 WHERE e.event_time>=p.asof-interval '56 days'
 GROUP BY 1,2
),
periods AS (
 SELECT t.period,t.mask,count(m.company_id)::integer AS companies
 FROM (VALUES ('current'),('previous')) z(period)
 CROSS JOIN (VALUES ('100'),('010'),('001'),('110'),('101'),('011'),('111'),('000')) k(mask)
 CROSS JOIN LATERAL (SELECT z.period,k.mask) t
 LEFT JOIN company_masks m ON m.period=t.period AND m.mask=t.mask
 GROUP BY t.period,t.mask
),
totals AS (
 SELECT period,sum(companies)::integer AS total,
 sum(companies) FILTER(WHERE mask IN ('110','101','011','111'))::integer AS multi
 FROM periods GROUP BY period
)
SELECT jsonb_build_object(
 'contract','independent_workflow_v1',
 'snapshot_id',p.id,
 'as_of',p.asof,
 'source_watermark_at',p.watermark,
 'current_week',p.this_week,
 'weekly',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'week_start',w.week_start,'total',w.total,
   'ap',w.ap,'ar',w.ar,'transactions',w.transactions,
   'limited_tracking',w.week_start>=date '2026-05-01'
                  AND w.week_start<date '2026-08-01'
  ) ORDER BY w.week_start) FROM weekly w
 ),'[]'::jsonb),
 'mix',jsonb_build_object(
  'current_start',p.asof-interval '28 days',
  'current_end',p.asof,
  'previous_start',p.asof-interval '56 days',
  'previous_end',p.asof-interval '28 days',
  'current_total',(SELECT t.total FROM totals t WHERE t.period='current'),
  'previous_total',(SELECT t.total FROM totals t WHERE t.period='previous'),
  'current_multi',(SELECT t.multi FROM totals t WHERE t.period='current'),
  'previous_multi',(SELECT t.multi FROM totals t WHERE t.period='previous'),
  'rows',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
    'mask',k.mask,'current',coalesce(c.companies,0),
    'previous',coalesce(h.companies,0)
   ) ORDER BY k.n)
   FROM (VALUES
    (1,'001'),(2,'100'),(3,'101'),(4,'110'),
    (5,'111'),(6,'010'),(7,'011'),(8,'000')
   ) k(n,mask)
   LEFT JOIN periods c ON c.period='current' AND c.mask=k.mask
   LEFT JOIN periods h ON h.period='previous' AND h.mask=k.mask
  ),'[]'::jsonb)
 )
)
FROM p;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_workflow_charts_v2()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED (
 SELECT s.id,
  (s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
  s.source_watermark_at AS watermark,
  date_trunc('week',(s.payload#>>'{value,active_users,as_of}')::timestamptz
    AT TIME ZONE 'Asia/Kolkata')::date AS this_week
 FROM public.product_snapshot_current c
 JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
 LIMIT 1
),
ev AS MATERIALIZED (
 SELECT e.* FROM p CROSS JOIN LATERAL public.overview_workflow_events_v2(p.id) e
),
weeks AS(
 SELECT (p.this_week - gs.i*7)::date AS week_start
 FROM p CROSS JOIN generate_series(12,1,-1) gs(i)
),
weekly AS (
 SELECT w.week_start,
 count(DISTINCT e.distinct_id)::integer AS total,
 count(DISTINCT e.distinct_id) FILTER(WHERE e.module='ap')::integer AS ap,
 count(DISTINCT e.distinct_id) FILTER(WHERE e.module='ar')::integer AS ar,
 count(DISTINCT e.distinct_id) FILTER(WHERE e.module='transactions')::integer AS transactions
 FROM weeks w LEFT JOIN ev e ON e.week_start=w.week_start
 GROUP BY w.week_start
),
company_masks AS (
 SELECT CASE WHEN e.event_time>=p.asof-interval '28 days' THEN 'current' ELSE 'previous' END AS period,
 e.company_id,
 (CASE WHEN bool_or(e.module='ap') THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(e.module='ar') THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(e.module='transactions') THEN '1' ELSE '0' END) AS mask
 FROM ev e CROSS JOIN p
 WHERE e.event_time>=p.asof-interval '56 days'
 GROUP BY 1,2
),
periods AS (
 SELECT t.period,t.mask,count(m.company_id)::integer AS companies
 FROM (VALUES ('current'),('previous')) z(period)
 CROSS JOIN (VALUES ('100'),('010'),('001'),('110'),('101'),('011'),('111'),('000')) k(mask)
 CROSS JOIN LATERAL (SELECT z.period,k.mask) t
 LEFT JOIN company_masks m ON m.period=t.period AND m.mask=t.mask
 GROUP BY t.period,t.mask
),
totals AS (
 SELECT period,sum(companies)::integer AS total,
 sum(companies) FILTER(WHERE mask IN ('110','101','011','111'))::integer AS multi
 FROM periods GROUP BY period
)
SELECT jsonb_build_object(
 'contract','independent_workflow_v1',
 'snapshot_id',p.id,
 'as_of',p.asof,
 'source_watermark_at',p.watermark,
 'current_week',p.this_week,
 'weekly',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'week_start',w.week_start,'total',w.total,
   'ap',w.ap,'ar',w.ar,'transactions',w.transactions,
   'limited_tracking',w.week_start>=date '2026-05-01'
                  AND w.week_start<date '2026-08-01'
  ) ORDER BY w.week_start) FROM weekly w
 ),'[]'::jsonb),
 'mix',jsonb_build_object(
  'current_start',p.asof-interval '28 days',
  'current_end',p.asof,
  'previous_start',p.asof-interval '56 days',
  'previous_end',p.asof-interval '28 days',
  'current_total',(SELECT t.total FROM totals t WHERE t.period='current'),
  'previous_total',(SELECT t.total FROM totals t WHERE t.period='previous'),
  'current_multi',(SELECT t.multi FROM totals t WHERE t.period='current'),
  'previous_multi',(SELECT t.multi FROM totals t WHERE t.period='previous'),
  'rows',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
    'mask',k.mask,'current',coalesce(c.companies,0),
    'previous',coalesce(h.companies,0)
   ) ORDER BY k.n)
   FROM (VALUES
    (1,'001'),(2,'100'),(3,'101'),(4,'110'),
    (5,'111'),(6,'010'),(7,'011'),(8,'000')
   ) k(n,mask)
   LEFT JOIN periods c ON c.period='current' AND c.mask=k.mask
   LEFT JOIN periods h ON h.period='previous' AND h.mask=k.mask
  ),'[]'::jsonb)
 )
)
FROM p;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_workflow_charts_v3(p_snapshot_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED (
 SELECT s.id,
  (s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
  s.source_watermark_at AS watermark,
  date_trunc('week',(s.payload#>>'{value,active_users,as_of}')::timestamptz
    AT TIME ZONE 'Asia/Kolkata')::date AS this_week
 FROM public.product_snapshot s
 WHERE s.kind='overview'
 AND s.id=coalesce(p_snapshot_id,(SELECT c2.snapshot_id FROM public.product_snapshot_current c2 WHERE c2.kind='overview' AND c2.scope_key='' LIMIT 1)) AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD')) AND s.source_status='ok'
 LIMIT 1
),
ev AS MATERIALIZED (
 SELECT e.* FROM p CROSS JOIN LATERAL public.overview_workflow_events_v3(p.id) e
),
weeks AS(
 SELECT (p.this_week - gs.i*7)::date AS week_start
 FROM p CROSS JOIN generate_series(12,1,-1) gs(i)
),
weekly AS (
 SELECT w.week_start,
 count(DISTINCT e.distinct_id)::integer AS total,
 count(DISTINCT e.distinct_id) FILTER(WHERE e.module='ap')::integer AS ap,
 count(DISTINCT e.distinct_id) FILTER(WHERE e.module='ar')::integer AS ar,
 count(DISTINCT e.distinct_id) FILTER(WHERE e.module='transactions')::integer AS transactions
 FROM weeks w LEFT JOIN ev e ON e.week_start=w.week_start
 GROUP BY w.week_start
),
company_masks AS (
 SELECT CASE WHEN e.event_time>=p.asof-interval '28 days' THEN 'current' ELSE 'previous' END AS period,
 e.company_id,
 (CASE WHEN bool_or(e.module='ap') THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(e.module='ar') THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(e.module='transactions') THEN '1' ELSE '0' END) AS mask
 FROM ev e CROSS JOIN p
 WHERE e.event_time>=p.asof-interval '56 days'
 GROUP BY 1,2
),
periods AS (
 SELECT t.period,t.mask,count(m.company_id)::integer AS companies
 FROM (VALUES ('current'),('previous')) z(period)
 CROSS JOIN (VALUES ('100'),('010'),('001'),('110'),('101'),('011'),('111'),('000')) k(mask)
 CROSS JOIN LATERAL (SELECT z.period,k.mask) t
 LEFT JOIN company_masks m ON m.period=t.period AND m.mask=t.mask
 GROUP BY t.period,t.mask
),
totals AS (
 SELECT period,sum(companies)::integer AS total,
 sum(companies) FILTER(WHERE mask IN ('110','101','011','111'))::integer AS multi
 FROM periods GROUP BY period
)
SELECT jsonb_build_object(
 'contract','independent_workflow_v1',
 'snapshot_id',p.id,
 'as_of',p.asof,
 'source_watermark_at',p.watermark,
 'current_week',p.this_week,
 'weekly',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'week_start',w.week_start,'total',w.total,
   'ap',w.ap,'ar',w.ar,'transactions',w.transactions,
   'limited_tracking',w.week_start>=date '2026-05-01'
                  AND w.week_start<date '2026-08-01'
  ) ORDER BY w.week_start) FROM weekly w
 ),'[]'::jsonb),
 'mix',jsonb_build_object(
  'current_start',p.asof-interval '28 days',
  'current_end',p.asof,
  'previous_start',p.asof-interval '56 days',
  'previous_end',p.asof-interval '28 days',
  'current_total',(SELECT t.total FROM totals t WHERE t.period='current'),
  'previous_total',(SELECT t.total FROM totals t WHERE t.period='previous'),
  'current_multi',(SELECT t.multi FROM totals t WHERE t.period='current'),
  'previous_multi',(SELECT t.multi FROM totals t WHERE t.period='previous'),
  'rows',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
    'mask',k.mask,'current',coalesce(c.companies,0),
    'previous',coalesce(h.companies,0)
   ) ORDER BY k.n)
   FROM (VALUES
    (1,'001'),(2,'100'),(3,'101'),(4,'110'),
    (5,'111'),(6,'010'),(7,'011'),(8,'000')
   ) k(n,mask)
   LEFT JOIN periods c ON c.period='current' AND c.mask=k.mask
   LEFT JOIN periods h ON h.period='previous' AND h.mask=k.mask
  ),'[]'::jsonb)
 )
)
FROM p;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_workflow_charts_v4(p_snapshot_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
AS $function$
 SELECT metrics_private.read_overview_chart_summary_cached_v1(p_snapshot_id, 'workflow');
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_workflow_company_v1(p_snapshot_id bigint, p_scope text, p_company_id text, p_week text DEFAULT ''::text, p_module text DEFAULT ''::text, p_mask text DEFAULT ''::text, p_user_id text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_workflow_company_v2(p_snapshot_id bigint, p_scope text, p_company_id text, p_week text DEFAULT ''::text, p_module text DEFAULT ''::text, p_mask text DEFAULT ''::text, p_user_id text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
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
 public.overview_workflow_events_v2(s.id) e
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_workflow_company_v3(p_snapshot_id bigint, p_scope text, p_company_id text, p_week text DEFAULT ''::text, p_module text DEFAULT ''::text, p_mask text DEFAULT ''::text, p_user_id text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED (
 SELECT s.id,(s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
 s.source_watermark_at wm,
 date_trunc('week',(s.payload#>>'{value,active_users,as_of}')::timestamptz
   AT TIME ZONE 'Asia/Kolkata')::date AS this_week
 FROM public.product_snapshot s
 WHERE s.kind='overview' AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD')) AND s.id=p_snapshot_id
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
 public.overview_workflow_events_v3(s.id) e
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_workflow_mix_companies_v1(p_snapshot_id bigint, p_period text, p_mask text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED(
 SELECT s.id,(s.payload#>>'{value,active_users,as_of}')::timestamptz as asof,
 s.source_watermark_at wm
 FROM product_snapshot_current c JOIN product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND c.snapshot_id=p_snapshot_id
 AND s.source_status='ok' LIMIT 1
),
scope AS(
 SELECT p.*,
 CASE WHEN p_period='current' THEN p.asof-interval '28 days'
  ELSE p.asof-interval '56 days' END AS start_at,
 CASE WHEN p_period='current' THEN p.asof
  ELSE p.asof-interval '28 days' END AS end_at
 FROM p
 WHERE p_period IN ('current','previous') AND p_mask IN
 ('100','010','001','110','101','011','111','000')
),
events AS MATERIALIZED(
 SELECT e.* FROM scope s CROSS JOIN LATERAL
 public.overview_workflow_events_v1(s.id) e
 WHERE e.event_time>=s.start_at AND e.event_time<s.end_at
),
groups AS MATERIALIZED (
 SELECT e.company_id,
 (CASE WHEN bool_or(e.module='ap') THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(e.module='ar') THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(e.module='transactions') THEN '1' ELSE '0' END) mask,
 count(*)::int AS actions,
 count(DISTINCT e.distinct_id)::int AS users,
 count(DISTINCT e.activity_day)::int AS active_days,
 count(*) FILTER(WHERE e.module='ap')::int AS ap,
 count(*) FILTER(WHERE e.module='ar')::int AS ar,
 count(*) FILTER(WHERE e.module='transactions')::int AS transactions,
 max(e.event_time) AS last_at,
 max(nullif(e.event_company_name,'')) AS event_name
 FROM events e GROUP BY e.company_id
),
named AS MATERIALIZED(
 SELECT g.*,
 coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),
  g.event_name,g.company_id) AS name,
 coalesce(d.is_test,false) AS is_test
 FROM groups g
 LEFT JOIN company_directory d ON d.company_uuid::text=g.company_id
 LEFT JOIN company_profile cp ON cp.company_id=g.company_id
),
population AS MATERIALIZED(
 SELECT * FROM named WHERE mask=p_mask
),
matched AS MATERIALIZED(
 SELECT * FROM population n WHERE coalesce(btrim(p_query),'')=''
 OR n.name ILIKE '%'||left(btrim(p_query),80)||'%'
 OR n.company_id ILIKE '%'||left(btrim(p_query),80)||'%'
),
paged AS (
 SELECT * FROM matched ORDER BY last_at DESC NULLS LAST,company_id
 LIMIT greatest(1,least(coalesce(p_page_size,8),25))
 OFFSET (greatest(1,coalesce(p_page,1))-1)*
  greatest(1,least(coalesce(p_page_size,8),25))
)
SELECT jsonb_build_object(
 'contract','independent_workflow_mix_companies_v1',
 'snapshot_id',s.id,'as_of',s.asof,'source_watermark_at',s.wm,
 'period',p_period,'mask',p_mask,
 'window_start',s.start_at,'window_end',s.end_at,
 'segment_total',(SELECT count(*) FROM population),
 'total',(SELECT count(*) FROM matched),
 'page',greatest(1,coalesce(p_page,1)),
 'page_size',greatest(1,least(coalesce(p_page_size,8),25)),
 'rows',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'id',c.company_id,'name',c.name,'is_test',c.is_test,
   'mask',c.mask,'users',c.users,
   'actions',c.actions,'active_days',c.active_days,
   'last_active_at',c.last_at,
   'modules',jsonb_build_object('ap',c.ap,'ar',c.ar,'transactions',c.transactions)
  ) ORDER BY c.last_at DESC NULLS LAST,c.company_id)
  FROM paged c
 ),'[]'::jsonb)
)
FROM scope s;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_workflow_mix_companies_v2(p_snapshot_id bigint, p_period text, p_mask text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED(
 SELECT s.id,(s.payload#>>'{value,active_users,as_of}')::timestamptz as asof,
 s.source_watermark_at wm
 FROM product_snapshot_current c JOIN product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND c.snapshot_id=p_snapshot_id
 AND s.source_status='ok' LIMIT 1
),
scope AS(
 SELECT p.*,
 CASE WHEN p_period='current' THEN p.asof-interval '28 days'
  ELSE p.asof-interval '56 days' END AS start_at,
 CASE WHEN p_period='current' THEN p.asof
  ELSE p.asof-interval '28 days' END AS end_at
 FROM p
 WHERE p_period IN ('current','previous') AND p_mask IN
 ('100','010','001','110','101','011','111','000')
),
events AS MATERIALIZED(
 SELECT e.* FROM scope s CROSS JOIN LATERAL
 public.overview_workflow_events_v2(s.id) e
 WHERE e.event_time>=s.start_at AND e.event_time<s.end_at
),
groups AS MATERIALIZED (
 SELECT e.company_id,
 (CASE WHEN bool_or(e.module='ap') THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(e.module='ar') THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(e.module='transactions') THEN '1' ELSE '0' END) mask,
 count(*)::int AS actions,
 count(DISTINCT e.distinct_id)::int AS users,
 count(DISTINCT e.activity_day)::int AS active_days,
 count(*) FILTER(WHERE e.module='ap')::int AS ap,
 count(*) FILTER(WHERE e.module='ar')::int AS ar,
 count(*) FILTER(WHERE e.module='transactions')::int AS transactions,
 max(e.event_time) AS last_at,
 max(nullif(e.event_company_name,'')) AS event_name
 FROM events e GROUP BY e.company_id
),
named AS MATERIALIZED(
 SELECT g.*,
 coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),
  g.event_name,g.company_id) AS name,
 coalesce(d.is_test,false) AS is_test
 FROM groups g
 LEFT JOIN company_directory d ON d.company_uuid::text=g.company_id
 LEFT JOIN company_profile cp ON cp.company_id=g.company_id
),
population AS MATERIALIZED(
 SELECT * FROM named WHERE mask=p_mask
),
matched AS MATERIALIZED(
 SELECT * FROM population n WHERE coalesce(btrim(p_query),'')=''
 OR n.name ILIKE '%'||left(btrim(p_query),80)||'%'
 OR n.company_id ILIKE '%'||left(btrim(p_query),80)||'%'
),
paged AS (
 SELECT * FROM matched ORDER BY last_at DESC NULLS LAST,company_id
 LIMIT greatest(1,least(coalesce(p_page_size,8),25))
 OFFSET (greatest(1,coalesce(p_page,1))-1)*
  greatest(1,least(coalesce(p_page_size,8),25))
)
SELECT jsonb_build_object(
 'contract','independent_workflow_mix_companies_v1',
 'snapshot_id',s.id,'as_of',s.asof,'source_watermark_at',s.wm,
 'period',p_period,'mask',p_mask,
 'window_start',s.start_at,'window_end',s.end_at,
 'segment_total',(SELECT count(*) FROM population),
 'total',(SELECT count(*) FROM matched),
 'page',greatest(1,coalesce(p_page,1)),
 'page_size',greatest(1,least(coalesce(p_page_size,8),25)),
 'rows',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'id',c.company_id,'name',c.name,'is_test',c.is_test,
   'mask',c.mask,'users',c.users,
   'actions',c.actions,'active_days',c.active_days,
   'last_active_at',c.last_at,
   'modules',jsonb_build_object('ap',c.ap,'ar',c.ar,'transactions',c.transactions)
  ) ORDER BY c.last_at DESC NULLS LAST,c.company_id)
  FROM paged c
 ),'[]'::jsonb)
)
FROM scope s;
$function$
;
