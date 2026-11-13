-- Exact original public Product read RPCs, part 9/12, backed up 2026-11-07.
-- Rollback only. Original data and function grants remain in place.
-- Apply this together with all other Product rollback parts if a cutover must be reversed.
SET LOCAL lock_timeout='7s';

CREATE OR REPLACE FUNCTION public.read_overview_workflow_mix_companies_v3(p_snapshot_id bigint, p_period text, p_mask text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED(
 SELECT s.id,(s.payload#>>'{value,active_users,as_of}')::timestamptz as asof,
 s.source_watermark_at wm
 FROM public.product_snapshot s
 WHERE s.kind='overview' AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD')) AND s.id=p_snapshot_id
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
 public.overview_workflow_events_v3(s.id) e
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

CREATE OR REPLACE FUNCTION public.read_overview_workflow_module_users_v1(p_snapshot_id bigint, p_week text, p_module text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_workflow_module_users_v2(p_snapshot_id bigint, p_week text, p_module text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
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
 CROSS JOIN LATERAL public.overview_workflow_events_v2(s.id) e
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_workflow_module_users_v3(p_snapshot_id bigint, p_week text, p_module text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED(
 SELECT s.id,(s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
 s.source_watermark_at wm,
 date_trunc('week',(s.payload#>>'{value,active_users,as_of}')::timestamptz
  AT TIME ZONE 'Asia/Kolkata')::date AS this_week
 FROM public.product_snapshot s
 WHERE s.kind='overview' AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD')) AND s.id=p_snapshot_id
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
 CROSS JOIN LATERAL public.overview_workflow_events_v3(s.id) e
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_workflow_module_users_v4(p_snapshot_id bigint, p_week text, p_module text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED(
 SELECT s.id,(s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
 s.source_watermark_at wm,
 date_trunc('week',(s.payload#>>'{value,active_users,as_of}')::timestamptz
  AT TIME ZONE 'Asia/Kolkata')::date AS this_week
 FROM public.product_snapshot s
 WHERE s.kind='overview' AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD')) AND s.id=p_snapshot_id
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
 CROSS JOIN LATERAL public.overview_workflow_events_week_v4(s.id,s.wk) e
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_product_page(p_page text)
 RETURNS TABLE(publication_id bigint, kind text, scope_key text, snapshot_id bigint, payload jsonb, published_at timestamp with time zone, source_watermark_at timestamp with time zone, n_events bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT c.publication_id, m.kind, m.scope_key, s.id, s.payload,
         p.published_at, p.source_watermark_at, p.n_events
  FROM public.product_publication_current AS c
  JOIN public.product_publication AS p
    ON p.publication_id = c.publication_id
  JOIN public.product_publication_member AS m
    ON m.publication_id = c.publication_id
  JOIN public.product_snapshot AS s
    ON s.id = m.snapshot_id
  WHERE c.page = p_page;
$function$
;

CREATE OR REPLACE FUNCTION public.read_product_snapshot(p_kind text, p_scope_key text)
 RETURNS TABLE(snapshot_id bigint, payload jsonb, published_at timestamp with time zone, source_status text, source_watermark_at timestamp with time zone, source_watermark_date date, n_events bigint, n_client integer, n_activation integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT s.id, s.payload, c.published_at,
         s.source_status, s.source_watermark_at, s.source_watermark_date,
         s.n_events, s.n_client, s.n_activation
  FROM public.product_snapshot_current AS c
  JOIN public.product_snapshot AS s ON s.id = c.snapshot_id
  WHERE c.kind = p_kind
    AND c.scope_key = COALESCE(p_scope_key, '');
$function$
;

CREATE OR REPLACE FUNCTION public.read_product_snapshot_with_generation(p_kind text, p_scope_key text)
 RETURNS TABLE(snapshot_id bigint, payload jsonb, published_at timestamp with time zone, source_status text, source_watermark_at timestamp with time zone, source_watermark_date date, n_events bigint, n_client integer, n_activation integer, build_key text, bounds_from timestamp with time zone, bounds_to timestamp with time zone, as_of_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT s.id, s.payload, c.published_at,
         s.source_status, s.source_watermark_at, s.source_watermark_date,
         s.n_events, s.n_client, s.n_activation,
         s.build_key, s.bounds_from, s.bounds_to, s.as_of_at
  FROM public.product_snapshot_current AS c
  JOIN public.product_snapshot AS s ON s.id = c.snapshot_id
  WHERE c.kind = p_kind
    AND c.scope_key = COALESCE(p_scope_key, '');
$function$
;

CREATE OR REPLACE FUNCTION public.read_retention_activation_company_detail_v1(p_company_id text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '5s'
AS $function$
with identity as (
  select
    a.company_id,
    coalesce(i.company_name,a.company_id) as company_name,
    coalesce(i.is_test,false) as is_test,
    coalesce(i.integration,'Unknown') as integration,
    a.integration_at,a.training_sync_at,a.post_training_core_at,a.activated_at
  from metrics_private.retention_activation_v3 a
  left join metrics_private.company_monthly_identity i using(company_id)
  where a.company_id=p_company_id
),
week_bounds as (
  select
    (date_trunc('week',now() at time zone 'Asia/Kolkata')::date - 56) as start_date,
    (date_trunc('week',now() at time zone 'Asia/Kolkata')::date - 1) as end_date
),
weeks as (
  select
    gs::date as week_start,
    (gs::date+6) as week_end
  from week_bounds b
  cross join lateral generate_series(
    b.start_date::timestamp,
    b.end_date::timestamp,
    interval '7 days'
  ) gs
),
company_events as (
  select e.*
  from public.events e
  join identity i on i.company_id=e.company_id
  where not metrics_private.is_retention_internal_email_v2(e.email)
),
signup as (
  select
    coalesce(
      min(event_time) filter(where event_name='Company Created'),
      min(event_time)
    ) as signup_at,
    case
      when min(event_time) filter(where event_name='Company Created') is not null
      then 'Company Created'
      else 'First seen'
    end as signup_kind
  from company_events
),
role_events as (
  select
    (
      select nullif(btrim(e.distinct_id),'')
      from company_events e,identity i
      where i.post_training_core_at is not null
        and e.event_time=i.post_training_core_at
      order by e.insert_id
      limit 1
    ) as core_user_key,
    (
      select nullif(btrim(e.distinct_id),'')
      from company_events e,identity i
      where i.activated_at is not null
        and e.event_time=i.activated_at
      order by e.insert_id
      limit 1
    ) as sync_user_key
),
recent_mapped as (
  select
    e.company_id,
    coalesce(nullif(btrim(e.distinct_id),''),'__unattributed__') as user_key,
    e.event_name,e.event_time,
    public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb)) as module
  from company_events e
  cross join week_bounds b
  where (e.event_time at time zone 'Asia/Kolkata')::date between b.start_date and b.end_date
    and public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb))
      in ('ap','ar','transactions','gst','sync')
),
week_usage as (
  select
    w.week_start,w.week_end,
    count(r.*) filter(where r.module='ap')::bigint as ap,
    count(r.*) filter(where r.module='ar')::bigint as ar,
    count(r.*) filter(where r.module='transactions')::bigint as transactions,
    count(r.*) filter(where r.module='gst')::bigint as gst,
    count(r.*) filter(where r.module='sync')::bigint as sync
  from weeks w
  left join recent_mapped r
    on (r.event_time at time zone 'Asia/Kolkata')::date between w.week_start and w.week_end
  group by w.week_start,w.week_end
),
user_recent as (
  select
    r.user_key,
    count(*) filter(where r.module='ap')::bigint as ap,
    count(*) filter(where r.module='ar')::bigint as ar,
    count(*) filter(where r.module='transactions')::bigint as transactions,
    count(*) filter(where r.module='gst')::bigint as gst,
    count(*) filter(where r.module='sync')::bigint as sync
  from recent_mapped r
  group by r.user_key
),
user_identity as (
  select
    u.user_key,
    coalesce(u.user_email,u.user_key) as user_email,
    u.first_seen_at,u.last_seen_at
  from metrics_private.company_monthly_user u
  where u.company_id=p_company_id
  union
  select
    '__unattributed__','Unattributed activity',
    min(event_time),max(event_time)
  from company_events
  where nullif(btrim(distinct_id),'') is null
    and public.company_module_for(event_name,coalesce(properties,'{}'::jsonb))
      in ('ap','ar','transactions','gst','sync')
  having count(*)>0
),
evidence_ranked as (
  select
    e.event_time as at,
    e.event_name as event,
    case public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb))
      when 'ap' then 'AP'
      when 'ar' then 'AR'
      when 'transactions' then 'Transaction'
      when 'gst' then 'GST'
      when 'sync' then 'Sync'
      else null
    end as module,
    coalesce(nullif(btrim(e.email),''),nullif(btrim(e.distinct_id),'')) as user_label,
    row_number() over(order by e.event_time,e.insert_id) as rn
  from company_events e
  cross join identity i
  where i.training_sync_at is not null
    and (e.event_time at time zone 'Asia/Kolkata')::date
        > (i.training_sync_at at time zone 'Asia/Kolkata')::date
    and (i.activated_at is null or e.event_time<=i.activated_at)
    and public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb))
        in ('ap','ar','transactions','gst','sync')
),
evidence as (
  select er.*
  from evidence_ranked er
  where er.rn<=9
  union all
  select er.*
  from evidence_ranked er
  cross join identity i
  where i.activated_at is not null
    and er.at=i.activated_at
    and er.rn>9
),
last_core as (
  select max(e.event_time) as last_core_activity_at
  from company_events e
  cross join identity i
  where (i.activated_at is null or e.event_time>=i.activated_at)
    and public.is_core_activity(e.event_name,coalesce(e.properties,'{}'::jsonb))
),
active_weeks as (
  select count(*)::bigint as n
  from week_usage
  where ap+ar+transactions+gst+sync>0
),
recent_total as (
  select coalesce(sum(ap+ar+transactions+gst+sync),0)::bigint as n
  from week_usage
)
select jsonb_build_object(
  'id',i.company_id,
  'name',i.company_name,
  'is_test',i.is_test,
  'integration',i.integration,
  'signup_at',s.signup_at,
  'signup_kind',s.signup_kind,
  'integration_at',i.integration_at,
  'training_sync_at',i.training_sync_at,
  'post_training_core_at',i.post_training_core_at,
  'activated_at',i.activated_at,
  'ttv_hours',case when i.activated_at is null then null else
    extract(epoch from (i.activated_at-i.integration_at))/3600.0 end,
  'last_core_activity_at',(select last_core_activity_at from last_core),
  'observed_users',(select count(*) from user_identity),
  'active_weeks_8',(select n from active_weeks),
  'module_events_8',(select n from recent_total),
  'evidence',coalesce((
    select jsonb_agg(jsonb_build_object(
      'at',at,'event',event,'module',module,'user',user_label
    ) order by rn)
    from evidence
  ),'[]'::jsonb),
  'users',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id',u.user_key,
        'email',u.user_email,
        'first_seen_at',u.first_seen_at,
        'last_seen_at',u.last_seen_at,
        'activation_role',case
          when u.user_key=r.core_user_key and u.user_key=r.sync_user_key then 'both'
          when u.user_key=r.core_user_key then 'core_job'
          when u.user_key=r.sync_user_key then 'closing_sync'
          else null
        end,
        'recent_totals',jsonb_build_object(
          'ap',coalesce(ur.ap,0),
          'ar',coalesce(ur.ar,0),
          'transactions',coalesce(ur.transactions,0),
          'gst',coalesce(ur.gst,0),
          'sync',coalesce(ur.sync,0)
        )
      )
      order by (u.user_key='__unattributed__'),lower(u.user_email)
    )
    from user_identity u
    cross join role_events r
    left join user_recent ur on ur.user_key=u.user_key
  ),'[]'::jsonb),
  'weeks',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'week_start',week_start,
        'week_end',week_end,
        'totals',jsonb_build_object(
          'ap',ap,'ar',ar,'transactions',transactions,'gst',gst,'sync',sync
        )
      )
      order by week_start
    )
    from week_usage
  ),'[]'::jsonb)
)
from identity i
cross join signup s;
$function$
;

CREATE OR REPLACE FUNCTION public.read_retention_activation_company_detail_v2(p_company_id text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '5s'
AS $function$
with identity as (
  select
    a.company_id,
    coalesce(i.company_name,a.company_id) as company_name,
    coalesce(i.is_test,false) as is_test,
    coalesce(i.integration,'Unknown') as integration,
    a.integration_at,a.training_sync_at,a.post_training_core_at,a.activated_at
  from metrics_private.retention_activation_v4 a
  left join metrics_private.company_monthly_identity i using(company_id)
  where a.company_id=p_company_id
),
week_bounds as (
  select
    (date_trunc('week',now() at time zone 'Asia/Kolkata')::date - 56) as start_date,
    (date_trunc('week',now() at time zone 'Asia/Kolkata')::date - 1) as end_date
),
weeks as (
  select
    gs::date as week_start,
    (gs::date+6) as week_end
  from week_bounds b
  cross join lateral generate_series(
    b.start_date::timestamp,
    b.end_date::timestamp,
    interval '7 days'
  ) gs
),
company_events as (
  select e.*
  from public.events e
  join identity i on i.company_id=e.company_id
  where not metrics_private.is_retention_internal_email_v2(e.email)
),
signup as (
  select
    coalesce(
      min(event_time) filter(where event_name='Company Created'),
      min(event_time)
    ) as signup_at,
    case
      when min(event_time) filter(where event_name='Company Created') is not null
      then 'Company Created'
      else 'First seen'
    end as signup_kind
  from company_events
),
role_events as (
  select
    (
      select nullif(btrim(e.distinct_id),'')
      from company_events e,identity i
      where i.post_training_core_at is not null
        and e.event_time=i.post_training_core_at
      order by e.insert_id
      limit 1
    ) as core_user_key,
    (
      select nullif(btrim(e.distinct_id),'')
      from company_events e,identity i
      where i.activated_at is not null
        and e.event_time=i.activated_at
      order by e.insert_id
      limit 1
    ) as sync_user_key
),
recent_mapped as (
  select
    e.company_id,
    coalesce(nullif(btrim(e.distinct_id),''),'__unattributed__') as user_key,
    e.event_name,e.event_time,
    public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb)) as module
  from company_events e
  cross join week_bounds b
  where (e.event_time at time zone 'Asia/Kolkata')::date between b.start_date and b.end_date
    and public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb))
      in ('ap','ar','transactions','gst','sync')
),
week_usage as (
  select
    w.week_start,w.week_end,
    count(r.*) filter(where r.module='ap')::bigint as ap,
    count(r.*) filter(where r.module='ar')::bigint as ar,
    count(r.*) filter(where r.module='transactions')::bigint as transactions,
    count(r.*) filter(where r.module='gst')::bigint as gst,
    count(r.*) filter(where r.module='sync')::bigint as sync
  from weeks w
  left join recent_mapped r
    on (r.event_time at time zone 'Asia/Kolkata')::date between w.week_start and w.week_end
  group by w.week_start,w.week_end
),
user_recent as (
  select
    r.user_key,
    count(*) filter(where r.module='ap')::bigint as ap,
    count(*) filter(where r.module='ar')::bigint as ar,
    count(*) filter(where r.module='transactions')::bigint as transactions,
    count(*) filter(where r.module='gst')::bigint as gst,
    count(*) filter(where r.module='sync')::bigint as sync
  from recent_mapped r
  group by r.user_key
),
user_identity as (
  select
    u.user_key,
    coalesce(u.user_email,u.user_key) as user_email,
    u.first_seen_at,u.last_seen_at
  from metrics_private.company_monthly_user u
  where u.company_id=p_company_id
  union
  select
    '__unattributed__','Unattributed activity',
    min(event_time),max(event_time)
  from company_events
  where nullif(btrim(distinct_id),'') is null
    and public.company_module_for(event_name,coalesce(properties,'{}'::jsonb))
      in ('ap','ar','transactions','gst','sync')
  having count(*)>0
),
evidence_ranked as (
  select
    e.event_time as at,
    e.event_name as event,
    case public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb))
      when 'ap' then 'AP'
      when 'ar' then 'AR'
      when 'transactions' then 'Transaction'
      when 'gst' then 'GST'
      when 'sync' then 'Sync'
      else null
    end as module,
    coalesce(nullif(btrim(e.email),''),nullif(btrim(e.distinct_id),'')) as user_label,
    row_number() over(order by e.event_time,e.insert_id) as rn
  from company_events e
  cross join identity i
  where i.training_sync_at is not null
    and (e.event_time at time zone 'Asia/Kolkata')::date
        > (i.training_sync_at at time zone 'Asia/Kolkata')::date
    and (i.activated_at is null or e.event_time<=i.activated_at)
    and public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb))
        in ('ap','ar','transactions','gst','sync')
),
evidence as (
  select er.*
  from evidence_ranked er
  where er.rn<=9
  union all
  select er.*
  from evidence_ranked er
  cross join identity i
  where i.activated_at is not null
    and er.at=i.activated_at
    and er.rn>9
),
last_core as (
  select max(e.event_time) as last_core_activity_at
  from company_events e
  cross join identity i
  where (i.activated_at is null or e.event_time>=i.activated_at)
    and public.is_core_activity(e.event_name,coalesce(e.properties,'{}'::jsonb))
),
active_weeks as (
  select count(*)::bigint as n
  from week_usage
  where ap+ar+transactions+gst+sync>0
),
recent_total as (
  select coalesce(sum(ap+ar+transactions+gst+sync),0)::bigint as n
  from week_usage
)
select jsonb_build_object(
  'id',i.company_id,
  'name',i.company_name,
  'is_test',i.is_test,
  'integration',i.integration,
  'signup_at',s.signup_at,
  'signup_kind',s.signup_kind,
  'integration_at',i.integration_at,
  'training_sync_at',i.training_sync_at,
  'post_training_core_at',i.post_training_core_at,
  'activated_at',i.activated_at,
  'ttv_hours',case when i.activated_at is null then null else
    extract(epoch from (i.activated_at-i.integration_at))/3600.0 end,
  'last_core_activity_at',(select last_core_activity_at from last_core),
  'observed_users',(select count(*) from user_identity),
  'active_weeks_8',(select n from active_weeks),
  'module_events_8',(select n from recent_total),
  'evidence',coalesce((
    select jsonb_agg(jsonb_build_object(
      'at',at,'event',event,'module',module,'user',user_label
    ) order by rn)
    from evidence
  ),'[]'::jsonb),
  'users',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id',u.user_key,
        'email',u.user_email,
        'first_seen_at',u.first_seen_at,
        'last_seen_at',u.last_seen_at,
        'activation_role',case
          when u.user_key=r.core_user_key and u.user_key=r.sync_user_key then 'both'
          when u.user_key=r.core_user_key then 'core_job'
          when u.user_key=r.sync_user_key then 'closing_sync'
          else null
        end,
        'recent_totals',jsonb_build_object(
          'ap',coalesce(ur.ap,0),
          'ar',coalesce(ur.ar,0),
          'transactions',coalesce(ur.transactions,0),
          'gst',coalesce(ur.gst,0),
          'sync',coalesce(ur.sync,0)
        )
      )
      order by (u.user_key='__unattributed__'),lower(u.user_email)
    )
    from user_identity u
    cross join role_events r
    left join user_recent ur on ur.user_key=u.user_key
  ),'[]'::jsonb),
  'weeks',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'week_start',week_start,
        'week_end',week_end,
        'totals',jsonb_build_object(
          'ap',ap,'ar',ar,'transactions',transactions,'gst',gst,'sync',sync
        )
      )
      order by week_start
    )
    from week_usage
  ),'[]'::jsonb)
)
from identity i
cross join signup s;
$function$
;

CREATE OR REPLACE FUNCTION public.read_retention_activation_drill_page_v1(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_query text DEFAULT ''::text, p_status text DEFAULT 'all'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '5s'
AS $function$
with args as (
  select
    greatest(coalesce(p_page,1),1) as page_no,
    least(greatest(coalesce(p_page_size,8),1),50) as page_size,
    lower(btrim(coalesce(p_query,''))) as q,
    case
      when p_status in ('activated','awaiting_sync','no_core','no_training') then p_status
      else 'all'
    end as status_filter
),
base as (
  select
    a.company_id,
    coalesce(i.company_name,a.company_id) as company_name,
    coalesce(i.is_test,false) as is_test,
    coalesce(i.integration,'Unknown') as integration,
    a.integration_at,
    a.training_sync_at,
    a.post_training_core_at,
    a.activated_at,
    case
      when a.activated_at is not null then 'activated'
      when a.post_training_core_at is not null then 'awaiting_sync'
      when a.training_sync_at is not null then 'no_core'
      else 'no_training'
    end as status
  from metrics_private.retention_activation_v3 a
  left join metrics_private.company_monthly_identity i using(company_id)
),
filtered as (
  select b.*
  from base b
  cross join args x
  where
    (p_from is null or (b.integration_at at time zone 'Asia/Kolkata')::date >= p_from)
    and (p_to is null or (b.integration_at at time zone 'Asia/Kolkata')::date <= p_to)
    and (x.status_filter='all' or b.status=x.status_filter)
    and (
      x.q=''
      or lower(b.company_name) like '%' || x.q || '%'
      or exists (
        select 1
        from metrics_private.company_monthly_user u
        where u.company_id=b.company_id
          and lower(coalesce(u.user_email,u.user_key)) like '%' || x.q || '%'
      )
    )
),
ranked as (
  select
    f.*,
    row_number() over(order by f.integration_at desc,f.company_id) as rn
  from filtered f
),
paged as (
  select r.*
  from ranked r
  cross join args x
  where r.rn>(x.page_no-1)*x.page_size
    and r.rn<=x.page_no*x.page_size
),
observed_users as (
  select
    p.company_id,
    nullif(btrim(e.distinct_id),'') as user_key,
    (
      array_agg(
        nullif(btrim(e.email),'')
        order by e.event_time desc,e.insert_id desc
      )
      filter (where nullif(btrim(e.email),'') is not null)
    )[1] as user_email
  from paged p
  join public.events e on e.company_id=p.company_id
  where e.event_time>=p.integration_at
    and nullif(btrim(e.distinct_id),'') is not null
    and not metrics_private.is_retention_internal_email_v2(e.email)
  group by p.company_id,nullif(btrim(e.distinct_id),'')
),
window_events as (
  select
    p.company_id,
    coalesce(nullif(btrim(e.distinct_id),''),'__unattributed__') as user_key,
    e.event_name,
    e.event_time,
    public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb)) as module
  from paged p
  join public.events e on e.company_id=p.company_id
  where p.training_sync_at is not null
    and e.event_time >= (
      (((p.training_sync_at at time zone 'Asia/Kolkata')::date + 1)::timestamp)
      at time zone 'Asia/Kolkata'
    )
    and (p.activated_at is null or e.event_time<=p.activated_at)
    and not metrics_private.is_retention_internal_email_v2(e.email)
),
mapped as (
  select *
  from window_events
  where module in ('ap','ar','transactions','gst')
),
company_totals as (
  select
    company_id,
    count(*) filter(where module='ap')::bigint as ap,
    count(*) filter(where module='ar')::bigint as ar,
    count(*) filter(where module='transactions')::bigint as transactions,
    count(*) filter(where module='gst')::bigint as gst
  from mapped
  group by company_id
),
user_totals as (
  select
    company_id,user_key,
    count(*) filter(where module='ap')::bigint as ap,
    count(*) filter(where module='ar')::bigint as ar,
    count(*) filter(where module='transactions')::bigint as transactions,
    count(*) filter(where module='gst')::bigint as gst
  from mapped
  group by company_id,user_key
),
user_population as (
  select
    ou.company_id,
    ou.user_key,
    coalesce(ou.user_email,ou.user_key) as user_email
  from observed_users ou

  union

  select
    ut.company_id,
    '__unattributed__'::text,
    'Unattributed activity'::text
  from user_totals ut
  where ut.user_key='__unattributed__'
),
rows_json as (
  select
    p.rn,
    jsonb_build_object(
      'id',p.company_id,
      'name',p.company_name,
      'is_test',p.is_test,
      'integration',p.integration,
      'integration_at',p.integration_at,
      'training_sync_at',p.training_sync_at,
      'post_training_core_at',p.post_training_core_at,
      'activated_at',p.activated_at,
      'status',p.status,
      'ttv_hours',case when p.activated_at is null then null else
        extract(epoch from (p.activated_at-p.integration_at))/3600.0 end,
      'totals',jsonb_build_object(
        'ap',coalesce(ct.ap,0),
        'ar',coalesce(ct.ar,0),
        'transactions',coalesce(ct.transactions,0),
        'gst',coalesce(ct.gst,0)
      ),
      'users',coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id',up.user_key,
            'email',up.user_email,
            'totals',jsonb_build_object(
              'ap',coalesce(ut.ap,0),
              'ar',coalesce(ut.ar,0),
              'transactions',coalesce(ut.transactions,0),
              'gst',coalesce(ut.gst,0)
            )
          )
          order by
            (up.user_key='__unattributed__'),
            lower(up.user_email),
            up.user_key
        )
        from user_population up
        left join user_totals ut
          on ut.company_id=up.company_id and ut.user_key=up.user_key
        where up.company_id=p.company_id
      ),'[]'::jsonb)
    ) as row
  from paged p
  left join company_totals ct using(company_id)
)
select jsonb_build_object(
  'rows',coalesce((select jsonb_agg(row order by rn) from rows_json),'[]'::jsonb),
  'total',(select count(*) from filtered),
  'page',(select page_no from args),
  'page_size',(select page_size from args)
);
$function$
;
