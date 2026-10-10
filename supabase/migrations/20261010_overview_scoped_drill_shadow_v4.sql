-- Shadow drill readers: push selected week/issue/period into event scans.
-- Original v3 sources and drill RPCs remain unchanged.
-- Promote only after exact JSON parity, security and latency tests.

CREATE OR REPLACE FUNCTION public.overview_workflow_events_week_v4(p_snapshot_id bigint, p_week date)
 RETURNS TABLE(snapshot_id bigint, as_of_at timestamp with time zone, source_watermark_at timestamp with time zone, current_week date, distinct_id text, company_id text, email text, event_company_name text, event_time timestamp with time zone, activity_day date, week_start date, module text, event_name text)
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
 WHERE s.kind='overview' AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD'))
   AND s.source_status='ok' AND s.id=p_snapshot_id
 LIMIT 1
)
SELECT p.id,p.asof,p.watermark,p.this_week,
 e.distinct_id,e.company_id,e.email,e.company,e.event_time,
 (e.event_time AT TIME ZONE 'Asia/Kolkata')::date,
 date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date,
 CASE
  WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill')
   OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill')
   OR e.event_name='Vendor Mismatch Resolved' THEN 'ap'
  WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice')
   OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice')
   OR e.event_name='Invoice Bulk Edited' THEN 'ar'
  ELSE 'transactions'
 END AS module,
 e.event_name
FROM metrics_private.events_no_test_v2 e CROSS JOIN p
WHERE e.event_time >= ((p.this_week-84)::timestamp AT TIME ZONE 'Asia/Kolkata')
  AND e.event_time >= (p_week::timestamp AT TIME ZONE 'Asia/Kolkata')
  AND e.event_time < ((p_week + 7)::timestamp AT TIME ZONE 'Asia/Kolkata')
  AND e.event_time < p.asof
  AND e.ingested_at <= p.watermark
  AND e.distinct_id IS NOT NULL AND e.distinct_id <> ''
  AND e.company_id IS NOT NULL AND e.company_id <> ''
  AND e.event_name <> 'Accounting Sync'
  AND public.is_core_activity(e.event_name,e.properties)
  AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
  AND NOT metrics_private.is_retention_internal_email_v2(e.email)
  AND EXISTS(SELECT 1 FROM public.client_company c WHERE c.company_id=e.company_id);
$function$;


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
$function$;


CREATE OR REPLACE FUNCTION public.overview_friction_events_scoped_v4(p_snapshot_id bigint, p_issue_key text, p_period text)
 RETURNS TABLE(company_id text, distinct_id text, email text, event_time timestamp with time zone, period text, issue_key text, is_failure boolean, is_success boolean, event_name text, status text, activity_type text, action text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED (
 SELECT s.id,
 (s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
 s.source_watermark_at AS wm
 FROM public.product_snapshot s
 WHERE s.kind='overview' AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD'))
 AND s.source_status='ok' AND s.id=p_snapshot_id
 LIMIT 1
),
normalized AS MATERIALIZED(
 SELECT e.company_id,e.distinct_id,e.email,e.event_time,
  CASE WHEN e.event_time>=p.asof-interval '28 days'
    THEN 'current' ELSE 'previous' END AS period,
  e.event_name,
  lower(btrim(coalesce(e.properties->>'status',''))) AS status,
  lower(btrim(coalesce(e.properties->>'type',''))) AS activity_type,
  lower(btrim(coalesce(e.properties->>'action',''))) AS action
 FROM metrics_private.events_no_test_v2 e CROSS JOIN p
 WHERE e.event_time>=p.asof-interval '56 days'
 AND e.event_time>=CASE WHEN p_period='current' THEN p.asof-interval '28 days' ELSE p.asof-interval '56 days' END
 AND e.event_time<CASE WHEN p_period='previous' THEN p.asof-interval '28 days' ELSE p.asof END
 AND (
  (p_issue_key='review_reverted' AND e.event_name='Transaction Status')
  OR (p_issue_key='bill_upload' AND e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill')
  OR (p_issue_key='invoice_upload' AND e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice')
  OR (p_issue_key='type_update' AND e.event_name='Transaction Type Updated')
  OR (p_issue_key='ledger_update' AND e.event_name='Transaction Ledger Updated')
 )
 AND e.event_time<p.asof AND e.ingested_at<=p.wm
 AND e.company_id IS NOT NULL AND e.company_id<>''
 AND e.distinct_id IS NOT NULL AND e.distinct_id<>''
 AND e.event_name IN ('Transaction Status','Upload',
                       'Transaction Type Updated','Transaction Ledger Updated')
 AND NOT metrics_private.is_retention_internal_email_v2(e.email)
 AND EXISTS(SELECT 1 FROM public.client_company c WHERE c.company_id=e.company_id)
),
classified AS(
 SELECT n.*,
 CASE
  WHEN n.event_name='Transaction Status'
   AND (n.status='accounting ready' OR (n.status='pending'
      AND n.action='revert to needs review'))
   THEN 'review_reverted'
  WHEN n.event_name='Upload' AND n.activity_type='bill'
   AND n.status IN ('failed','success') THEN 'bill_upload'
  WHEN n.event_name='Upload' AND n.activity_type='invoice'
   AND n.status IN ('failed','success') THEN 'invoice_upload'
  WHEN n.event_name='Transaction Type Updated'
   AND n.status IN ('failed','success') THEN 'type_update'
  WHEN n.event_name='Transaction Ledger Updated'
   AND n.status IN ('failed','success') THEN 'ledger_update'
  ELSE NULL
 END AS issue_key
 FROM normalized n
)
SELECT n.company_id,n.distinct_id,n.email,n.event_time,n.period,n.issue_key,
 CASE WHEN n.issue_key='review_reverted' THEN n.status='pending'
      ELSE n.status='failed' END AS is_failure,
 CASE WHEN n.issue_key='review_reverted' THEN n.status='accounting ready'
      ELSE n.status='success' END AS is_success,
 n.event_name,n.status,n.activity_type,n.action
FROM classified n WHERE n.issue_key=p_issue_key AND n.period=p_period;
$function$;


CREATE OR REPLACE FUNCTION public.overview_friction_company_facts_scoped_v4(p_snapshot_id bigint, p_issue_key text, p_period text)
 RETURNS TABLE(issue_key text, period text, company_id text, eligible_events integer, failed_events integer, success_events integer, first_failure_at timestamp with time zone, last_failure_at timestamp with time zone, followup_at timestamp with time zone, last_event_at timestamp with time zone, observed_users integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH ev AS MATERIALIZED (
 SELECT * FROM public.overview_friction_events_scoped_v4(p_snapshot_id,p_issue_key,p_period)
),
grouped AS (
 SELECT e.issue_key,e.period,e.company_id,
  count(*)::integer eligible_events,
  count(*) FILTER(WHERE e.is_failure)::integer failed_events,
  count(*) FILTER(WHERE e.is_success)::integer success_events,
  min(e.event_time) FILTER(WHERE e.is_failure) first_failure_at,
  max(e.event_time) FILTER(WHERE e.is_failure) last_failure_at,
  max(e.event_time) last_event_at,
  count(DISTINCT e.distinct_id)::integer observed_users
 FROM ev e GROUP BY e.issue_key,e.period,e.company_id
),
follow AS (
 SELECT g.issue_key,g.period,g.company_id,
  min(e.event_time) AS followup_at
 FROM grouped g
 JOIN ev e ON e.issue_key=g.issue_key AND e.period=g.period
   AND e.company_id=g.company_id AND e.is_success
   AND g.last_failure_at IS NOT NULL AND e.event_time>g.last_failure_at
 GROUP BY g.issue_key,g.period,g.company_id
)
SELECT g.issue_key,g.period,g.company_id,
 g.eligible_events,g.failed_events,g.success_events,
 g.first_failure_at,g.last_failure_at,
 f.followup_at,
 g.last_event_at,g.observed_users
FROM grouped g
LEFT JOIN follow f ON f.issue_key=g.issue_key AND f.period=g.period
 AND f.company_id=g.company_id;
$function$;


CREATE OR REPLACE FUNCTION public.read_overview_friction_companies_v4(p_snapshot_id bigint, p_issue_key text, p_period text DEFAULT 'current'::text, p_segment text DEFAULT 'affected'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED(
 SELECT s.id,(s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
 s.source_watermark_at wm
 FROM public.product_snapshot s
 WHERE s.kind='overview' AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD')) AND s.source_status='ok'
 AND s.id=p_snapshot_id LIMIT 1
),
scope AS MATERIALIZED(
 SELECT p.* FROM p WHERE p_issue_key IN(
  'review_reverted','bill_upload','type_update','invoice_upload','ledger_update')
 AND p_period IN ('current','previous')
 AND p_segment IN ('eligible','affected','later_success','needs_review')
),
facts AS MATERIALIZED(
 SELECT f.* FROM scope s CROSS JOIN LATERAL
  public.overview_friction_company_facts_scoped_v4(s.id,p_issue_key,p_period) f
 WHERE f.issue_key=p_issue_key AND f.period=p_period
),
population AS MATERIALIZED(
 SELECT f.* FROM facts f WHERE
 p_segment='eligible'
 OR (p_segment='affected' AND f.failed_events>0)
 OR (p_segment='later_success' AND f.failed_events>0 AND f.followup_at IS NOT NULL)
 OR (p_segment='needs_review' AND f.failed_events>0 AND f.followup_at IS NULL)
),
named AS MATERIALIZED(
 SELECT f.*,
 coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),f.company_id) AS company_name,
 coalesce(d.is_test,false) AS is_test
 FROM population f
 LEFT JOIN public.company_directory d ON d.company_uuid::text=f.company_id
 LEFT JOIN public.company_profile cp ON cp.company_id=f.company_id
),
matched AS MATERIALIZED(
 SELECT * FROM named n WHERE btrim(coalesce(p_query,''))=''
 OR n.company_name ILIKE '%'||left(btrim(p_query),80)||'%'
 OR n.company_id ILIKE '%'||left(btrim(p_query),80)||'%'
),
paged AS MATERIALIZED(
 SELECT * FROM matched n
 ORDER BY n.last_failure_at DESC NULLS LAST,n.last_event_at DESC NULLS LAST,n.company_id
 LIMIT greatest(1,least(coalesce(p_page_size,8),25))
 OFFSET (greatest(coalesce(p_page,1),1)-1)*greatest(1,least(coalesce(p_page_size,8),25))
),
ev AS MATERIALIZED(
 SELECT e.* FROM scope s CROSS JOIN LATERAL
 public.overview_friction_events_scoped_v4(s.id,p_issue_key,p_period) e
 WHERE e.issue_key=p_issue_key AND e.period=p_period
),
users AS MATERIALIZED(
 SELECT e.company_id,e.distinct_id AS id,
 coalesce(max(nullif(e.email,'')),e.distinct_id) AS email,
 count(*)::integer AS attempts,
 count(*) FILTER(WHERE e.is_failure)::integer AS failures,
 count(*) FILTER(WHERE e.is_success)::integer AS successes,
 max(e.event_time) AS last_at
 FROM ev e JOIN paged n ON n.company_id=e.company_id
 GROUP BY e.company_id,e.distinct_id
)
SELECT jsonb_build_object(
 'contract','observed_company_friction_list_v1',
 'snapshot_id',s.id,'as_of',s.asof,'source_watermark_at',s.wm,
 'issue_key',p_issue_key,'period',p_period,'segment',p_segment,
 'segment_total',(SELECT count(*) FROM population),
 'total',(SELECT count(*) FROM matched),
 'page',greatest(coalesce(p_page,1),1),
 'page_size',greatest(1,least(coalesce(p_page_size,8),25)),
 'rows',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'id',n.company_id,'name',n.company_name,'is_test',n.is_test,
   'eligible_events',n.eligible_events,'failed_events',n.failed_events,
   'success_events',n.success_events,
   'first_failure_at',n.first_failure_at,'last_failure_at',n.last_failure_at,
   'followup_at',n.followup_at,'last_event_at',n.last_event_at,
   'observed_users',n.observed_users,
   'users',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
     'id',u.id,'email',u.email,'attempts',u.attempts,'failures',u.failures,
     'successes',u.successes,'last_at',u.last_at
    ) ORDER BY u.failures DESC,u.attempts DESC,u.id)
    FROM users u WHERE u.company_id=n.company_id
   ),'[]'::jsonb)
  ) ORDER BY n.last_failure_at DESC NULLS LAST,n.last_event_at DESC NULLS LAST,n.company_id)
  FROM paged n
 ),'[]'::jsonb)
)
FROM scope s;
$function$;


REVOKE ALL ON FUNCTION public.overview_workflow_events_week_v4(bigint,date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.read_overview_workflow_module_users_v4(bigint,text,text,text,integer,integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.overview_friction_events_scoped_v4(bigint,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.overview_friction_company_facts_scoped_v4(bigint,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.read_overview_friction_companies_v4(bigint,text,text,text,text,integer,integer) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.overview_workflow_events_week_v4(bigint,date) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_overview_workflow_module_users_v4(bigint,text,text,text,integer,integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.overview_friction_events_scoped_v4(bigint,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.overview_friction_company_facts_scoped_v4(bigint,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_overview_friction_companies_v4(bigint,text,text,text,text,integer,integer) TO service_role;
