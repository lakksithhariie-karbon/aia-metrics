-- Exact user and company populations for the module trend and combination chart.
-- All memberships use the same immutable published snapshot as their parent chart.
CREATE OR REPLACE FUNCTION public.read_overview_workflow_module_users_v1(
 p_snapshot_id bigint,p_week text,p_module text,
 p_query text DEFAULT '',p_page integer DEFAULT 1,p_page_size integer DEFAULT 10
)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED(
 SELECT s.id,(s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
 s.source_watermark_at wm,
 date_trunc('week',(s.payload#>>'{value,active_users,as_of}')::timestamptz
  AT TIME ZONE 'Asia/Kolkata')::date AS this_week
 FROM product_snapshot_current c JOIN product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND c.snapshot_id=p_snapshot_id
  AND s.source_status='ok' LIMIT 1
),
scope AS (
 SELECT p.*,p_week::date AS wk FROM p
 WHERE p_module IN ('ap','ar','transactions')
 AND p_week ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
 AND (p.this_week-p_week::date) BETWEEN 7 AND 84
 AND (p.this_week-p_week::date)%7=0
),
events AS MATERIALIZED(
 SELECT e.* FROM scope s
 CROSS JOIN LATERAL public.overview_workflow_events_v1(s.id) e
 WHERE e.week_start=s.wk AND e.module=p_module
),
per_company AS MATERIALIZED(
 SELECT e.distinct_id,e.company_id,
 max(nullif(e.email,'')) AS email,
 max(nullif(e.event_company_name,'')) AS event_company_name,
 count(*)::int AS actions,count(DISTINCT e.activity_day)::int AS active_days,
 max(e.event_time) last_at
 FROM events e GROUP BY e.distinct_id,e.company_id
),
named AS MATERIALIZED (
 SELECT a.*,coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),
                         a.event_company_name,a.company_id) AS name,
 coalesce(d.is_test,false) is_test
 FROM per_company a
 LEFT JOIN company_directory d ON d.company_uuid::text=a.company_id
 LEFT JOIN company_profile cp ON cp.company_id=a.company_id
),
user_days AS(
 SELECT distinct_id,count(DISTINCT activity_day)::int active_days
 FROM events GROUP BY distinct_id
),
per_user AS MATERIALIZED (
 SELECT c.distinct_id AS id,max(c.email) email,
 sum(c.actions)::int AS actions,
 max(c.last_at) AS last_at,
 count(*)::int AS companies,
 max(d.active_days) AS active_days
 FROM named c JOIN user_days d USING(distinct_id) GROUP BY c.distinct_id
),
matched AS MATERIALIZED(
 SELECT u.* FROM per_user u WHERE
 coalesce(btrim(p_query),'')='' OR u.email ILIKE '%'||left(btrim(p_query),80)||'%'
 OR EXISTS(
  SELECT 1 FROM named a WHERE a.distinct_id=u.id
  AND a.name ILIKE '%'||left(btrim(p_query),80)||'%'
 )
),
paged AS(
 SELECT u.* FROM matched u ORDER BY u.last_at DESC NULLS LAST,u.id
 LIMIT greatest(1,least(coalesce(p_page_size,10),25))
 OFFSET (greatest(1,coalesce(p_page,1))-1)*
  greatest(1,least(coalesce(p_page_size,10),25))
)
SELECT jsonb_build_object(
 'contract','independent_workflow_module_users_v1',
 'snapshot_id',s.id,'week_start',s.wk,
 'module',p_module,'as_of',s.asof,'source_watermark_at',s.wm,
 'segment_total',(SELECT count(*) FROM per_user),
 'total',(SELECT count(*) FROM matched),
 'page',greatest(1,coalesce(p_page,1)),
 'page_size',greatest(1,least(coalesce(p_page_size,10),25)),
 'rows',coalesce((
 SELECT jsonb_agg(jsonb_build_object(
  'id',u.id,'email',coalesce(u.email,u.id),
  'actions',u.actions,'active_days',u.active_days,
  'last_active_at',u.last_at,'companies_count',u.companies,
  'companies',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
    'id',a.company_id,'name',a.name,'is_test',a.is_test,
    'actions',a.actions,'active_days',a.active_days,
    'last_active_at',a.last_at
   ) ORDER BY a.last_at DESC NULLS LAST,a.company_id)
   FROM named a WHERE a.distinct_id=u.id
  ),'[]'::jsonb)
 ) ORDER BY u.last_at DESC NULLS LAST,u.id)
 FROM paged u
 ),'[]'::jsonb)
)
FROM scope s;
$function$;
REVOKE ALL ON FUNCTION public.read_overview_workflow_module_users_v1(bigint,text,text,text,integer,integer)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_workflow_module_users_v1(bigint,text,text,text,integer,integer)
 TO service_role;

CREATE OR REPLACE FUNCTION public.read_overview_workflow_mix_companies_v1(
 p_snapshot_id bigint,p_period text,p_mask text,
 p_query text DEFAULT '',p_page integer DEFAULT 1,p_page_size integer DEFAULT 8
)
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
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
$function$;
REVOKE ALL ON FUNCTION public.read_overview_workflow_mix_companies_v1(bigint,text,text,text,integer,integer)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_workflow_mix_companies_v1(bigint,text,text,text,integer,integer)
 TO service_role;
