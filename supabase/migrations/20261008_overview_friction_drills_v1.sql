-- Server-only company-first drill and evidence profile.
-- Never calls a historical snapshot other than the currently published generation.
CREATE OR REPLACE FUNCTION public.read_overview_friction_companies_v1(
 p_snapshot_id bigint,
 p_issue_key text,
 p_period text DEFAULT 'current',
 p_segment text DEFAULT 'affected',
 p_query text DEFAULT '',
 p_page integer DEFAULT 1,
 p_page_size integer DEFAULT 8
)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED(
 SELECT s.id,(s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
 s.source_watermark_at wm
 FROM public.product_snapshot_current c
 JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
 AND c.snapshot_id=p_snapshot_id LIMIT 1
),
scope AS MATERIALIZED(
 SELECT p.* FROM p WHERE p_issue_key IN(
  'review_reverted','bill_upload','type_update','invoice_upload','ledger_update')
 AND p_period IN ('current','previous')
 AND p_segment IN ('eligible','affected','later_success','needs_review')
),
facts AS MATERIALIZED(
 SELECT f.* FROM scope s CROSS JOIN LATERAL
  public.overview_friction_company_facts_v1(s.id) f
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
 public.overview_friction_events_v1(s.id) e
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
REVOKE ALL ON FUNCTION public.read_overview_friction_companies_v1(bigint,text,text,text,text,integer,integer)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_friction_companies_v1(bigint,text,text,text,text,integer,integer)
 TO service_role;

CREATE OR REPLACE FUNCTION public.read_overview_friction_company_v1(
 p_snapshot_id bigint,
 p_issue_key text,
 p_period text,
 p_segment text,
 p_company_id text
)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED(
 SELECT s.id,(s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
 s.source_watermark_at wm
 FROM public.product_snapshot_current c
 JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
 AND c.snapshot_id=p_snapshot_id LIMIT 1
),
scope AS MATERIALIZED(
 SELECT p.*,
  CASE WHEN p_period='current' THEN p.asof-interval '28 days'
  ELSE p.asof-interval '56 days' END AS from_at,
  CASE WHEN p_period='current' THEN p.asof
  ELSE p.asof-interval '28 days' END AS to_at
 FROM p WHERE p_issue_key IN(
  'review_reverted','bill_upload','type_update','invoice_upload','ledger_update')
 AND p_period IN ('current','previous')
 AND p_segment IN ('eligible','affected','later_success','needs_review')
),
fact AS MATERIALIZED(
 SELECT f.* FROM scope s CROSS JOIN LATERAL
 public.overview_friction_company_facts_v1(s.id) f
 WHERE f.issue_key=p_issue_key AND f.period=p_period AND f.company_id=p_company_id
 AND (
  p_segment='eligible'
  OR (p_segment='affected' AND f.failed_events>0)
  OR (p_segment='later_success' AND f.failed_events>0 AND f.followup_at IS NOT NULL)
  OR (p_segment='needs_review' AND f.failed_events>0 AND f.followup_at IS NULL)
 )
),
ev AS MATERIALIZED(
 SELECT e.* FROM scope s JOIN fact f ON true
 CROSS JOIN LATERAL public.overview_friction_events_v1(s.id) e
 WHERE e.issue_key=p_issue_key AND e.period=p_period AND e.company_id=p_company_id
),
members AS MATERIALIZED(
 SELECT e.distinct_id AS id,
 coalesce(max(nullif(e.email,'')),e.distinct_id) AS email,
 count(*)::integer attempts,
 count(*) FILTER(WHERE e.is_failure)::integer failures,
 count(*) FILTER(WHERE e.is_success)::integer successes,
 min(e.event_time) AS first_at,max(e.event_time) AS last_at
 FROM ev e GROUP BY e.distinct_id
),
weeks AS MATERIALIZED(
 SELECT date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS week_start,
 count(*)::integer attempts,
 count(*) FILTER(WHERE e.is_failure)::integer failures,
 count(*) FILTER(WHERE e.is_success)::integer successes,
 count(DISTINCT e.distinct_id)::integer active_users
 FROM ev e GROUP BY 1
),
milestones AS(
 SELECT
 min(e.event_time) FILTER(WHERE e.event_name='Company Created') AS created_at,
 min(e.event_time) FILTER(WHERE public.is_successful_integration(e.event_name,e.properties))
  AS integration_at
 FROM public.events e CROSS JOIN scope s JOIN fact f ON true
 WHERE e.company_id=f.company_id AND e.event_time<s.asof
 AND e.ingested_at<=s.wm
 AND NOT metrics_private.is_retention_internal_email_v2(e.email)
)
SELECT jsonb_build_object(
 'contract','observed_company_friction_company_v1',
 'snapshot_id',s.id,'as_of',s.asof,'source_watermark_at',s.wm,
 'issue_key',p_issue_key,'period',p_period,'segment',p_segment,
 'company',jsonb_build_object(
  'id',f.company_id,
  'name',coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),f.company_id),
  'is_test',coalesce(d.is_test,false)
 ),
 'window',jsonb_build_object('start',s.from_at,'end',s.to_at,'days',28),
 'summary',jsonb_build_object(
  'attempts',f.eligible_events,'failures',f.failed_events,
  'successes',f.success_events,'users',f.observed_users,
  'first_failure_at',f.first_failure_at,'last_failure_at',f.last_failure_at,
  'followup_at',f.followup_at,'last_event_at',f.last_event_at
 ),
 'milestones',jsonb_build_object(
  'company_created_at',coalesce(cp.signed_up_at,m.created_at),
  'integration_at',m.integration_at
 ),
 'users',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'id',u.id,'email',u.email,'attempts',u.attempts,
   'failures',u.failures,'successes',u.successes,
   'first_at',u.first_at,'last_at',u.last_at
  ) ORDER BY u.failures DESC,u.attempts DESC,u.id)
  FROM members u
 ),'[]'::jsonb),
 'weeks',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'week_start',w.week_start,'attempts',w.attempts,
   'failures',w.failures,'successes',w.successes,'active_users',w.active_users
  ) ORDER BY w.week_start)
  FROM weeks w
 ),'[]'::jsonb),
 'events',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'at',e.event_time,'event',e.event_name,
   'status',e.status,'is_failure',e.is_failure,'is_success',e.is_success,
   'activity_type',e.activity_type,'action',e.action,
   'user_id',e.distinct_id,'email',coalesce(nullif(e.email,''),e.distinct_id)
  ) ORDER BY e.event_time DESC)
  FROM (SELECT * FROM ev ORDER BY event_time DESC LIMIT 60) e
 ),'[]'::jsonb)
)
FROM scope s JOIN fact f ON true
LEFT JOIN public.company_directory d ON d.company_uuid::text=f.company_id
LEFT JOIN public.company_profile cp ON cp.company_id=f.company_id
CROSS JOIN milestones m;
$function$;
REVOKE ALL ON FUNCTION public.read_overview_friction_company_v1(bigint,text,text,text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_friction_company_v1(bigint,text,text,text,text)
 TO service_role;
