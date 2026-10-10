-- Second-stage shadow Friction drill. Materialize the restricted event
-- stream ONCE for both company grouping and paged user breakdown, preserving
-- the exact original population, grouping, ordering and JSON contract.
-- Keep both v3 and v4 available for fallback and independent parity testing.

CREATE OR REPLACE FUNCTION public.read_overview_friction_companies_v5(p_snapshot_id bigint, p_issue_key text, p_period text DEFAULT 'current'::text, p_segment text DEFAULT 'affected'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
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
ev AS MATERIALIZED(
 SELECT e.* FROM scope s CROSS JOIN LATERAL
 public.overview_friction_events_scoped_v4(s.id,p_issue_key,p_period) e
 WHERE e.issue_key=p_issue_key AND e.period=p_period
),
grouped AS MATERIALIZED(
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
follow AS MATERIALIZED(
 SELECT g.issue_key,g.period,g.company_id,min(e.event_time) AS followup_at
 FROM grouped g
 JOIN ev e ON e.issue_key=g.issue_key AND e.period=g.period
  AND e.company_id=g.company_id AND e.is_success
  AND g.last_failure_at IS NOT NULL AND e.event_time>g.last_failure_at
 GROUP BY g.issue_key,g.period,g.company_id
),
facts AS MATERIALIZED(
 SELECT g.issue_key,g.period,g.company_id,
 g.eligible_events,g.failed_events,g.success_events,
 g.first_failure_at,g.last_failure_at,f.followup_at,
 g.last_event_at,g.observed_users
 FROM grouped g LEFT JOIN follow f
  ON f.issue_key=g.issue_key AND f.period=g.period AND f.company_id=g.company_id
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

REVOKE ALL ON FUNCTION public.read_overview_friction_companies_v5(bigint,text,text,text,text,integer,integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_friction_companies_v5(bigint,text,text,text,text,integer,integer) TO service_role;
