-- Exact original public Product read RPCs, part 7/12, backed up 2026-11-07.
-- Rollback only. Original data and function grants remain in place.
-- Apply this together with all other Product rollback parts if a cutover must be reversed.
SET LOCAL lock_timeout='7s';

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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_friction_company_v1(p_snapshot_id bigint, p_issue_key text, p_period text, p_segment text, p_company_id text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_friction_company_v2(p_snapshot_id bigint, p_issue_key text, p_period text, p_segment text, p_company_id text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
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
 public.overview_friction_company_facts_v2(s.id) f
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
 CROSS JOIN LATERAL public.overview_friction_events_v2(s.id) e
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
 FROM metrics_private.events_no_test_v2 e CROSS JOIN scope s JOIN fact f ON true
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_friction_company_v3(p_snapshot_id bigint, p_issue_key text, p_period text, p_segment text, p_company_id text)
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
 public.overview_friction_company_facts_v3(s.id) f
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
 CROSS JOIN LATERAL public.overview_friction_events_v3(s.id) e
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
 FROM metrics_private.events_no_test_v2 e CROSS JOIN scope s JOIN fact f ON true
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_friction_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED (
 SELECT s.id,
 (s.payload#>>'{value,active_users,as_of}')::timestamptz as asof,
 s.source_watermark_at wm
 FROM public.product_snapshot_current c
 JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
 LIMIT 1
),
facts AS MATERIALIZED(
 SELECT f.* FROM p CROSS JOIN LATERAL
 public.overview_friction_company_facts_v1(p.id) f
),
issue_catalog AS (
 SELECT * FROM (VALUES
  ('review_reverted'::text,'Reverted to review'::text,'Transactions'::text,'Rework'::text,1),
  ('bill_upload','Bill upload failed','Uploads','Failure',2),
  ('type_update','Type update failed','Transactions','Failure',3),
  ('invoice_upload','Invoice upload failed','Uploads','Failure',4),
  ('ledger_update','Ledger update failed','Transactions','Failure',5)
 ) AS k(issue_key,label,module,kind,display_order)
),
per_period AS (
 SELECT issue_key,period,
  count(*)::integer eligible,
  count(*) FILTER(WHERE failed_events>0)::integer affected,
  count(*) FILTER(WHERE failed_events>0 AND followup_at IS NOT NULL)::integer later_success,
  count(*) FILTER(WHERE failed_events>0 AND followup_at IS NULL)::integer needs_review
 FROM facts GROUP BY issue_key,period
),
rows AS (
 SELECT k.*,coalesce(c.eligible,0) AS current_eligible,
 coalesce(c.affected,0) AS current_affected,
 coalesce(c.later_success,0) AS current_followup,
 coalesce(c.needs_review,0) AS current_no_followup,
 coalesce(h.eligible,0) AS previous_eligible,
 coalesce(h.affected,0) AS previous_affected,
 coalesce(h.later_success,0) AS previous_followup,
 coalesce(h.needs_review,0) AS previous_no_followup,
 CASE WHEN coalesce(c.eligible,0)>0
  THEN round(c.affected::numeric*100/c.eligible,1) ELSE NULL END AS current_pct,
 CASE WHEN coalesce(h.eligible,0)>0
  THEN round(h.affected::numeric*100/h.eligible,1) ELSE NULL END AS previous_pct
 FROM issue_catalog k
 LEFT JOIN per_period c ON c.issue_key=k.issue_key AND c.period='current'
 LEFT JOIN per_period h ON h.issue_key=k.issue_key AND h.period='previous'
)
SELECT jsonb_build_object(
 'contract','observed_company_friction_v1',
 'snapshot_id',p.id,'as_of',p.asof,'source_watermark_at',p.wm,
 'window',jsonb_build_object(
  'current_start',p.asof-interval '28 days',
  'current_end',p.asof,
  'previous_start',p.asof-interval '56 days',
  'previous_end',p.asof-interval '28 days'
 ),
 'rows',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'key',r.issue_key,'label',r.label,'module',r.module,'kind',r.kind,
   'current',jsonb_build_object(
    'eligible',r.current_eligible,'affected',r.current_affected,
    'followup',r.current_followup,'needs_review',r.current_no_followup,
    'incidence_pct',r.current_pct,
    'followup_pct',CASE WHEN r.current_affected>0
      THEN round(r.current_followup::numeric*100/r.current_affected,1) ELSE NULL END
   ),
   'previous',jsonb_build_object(
    'eligible',r.previous_eligible,'affected',r.previous_affected,
    'followup',r.previous_followup,'needs_review',r.previous_no_followup,
    'incidence_pct',r.previous_pct
   ),
   'change_pp',CASE WHEN r.current_pct IS NOT NULL AND r.previous_pct IS NOT NULL
      THEN round(r.current_pct-r.previous_pct,1) ELSE NULL END
  ) ORDER BY r.current_no_followup DESC,r.current_affected DESC,r.display_order)
  FROM rows r),'[]'::jsonb),
 'basis',jsonb_build_object(
  'population','Distinct external client companies that attempted the given workflow in each rolling 28-day window',
  'affected','Distinct eligible companies with a failed action or an explicit revert to review',
  'later_success','A later success of the same workflow in that company, after its latest recorded failure in the selected period',
  'needs_review','Affected companies with no later success of that workflow observed by the end of the selected period',
  'limitation','Same company and workflow are observed, not the same transaction or upload attempt. These are follow-up signals, not confirmed resolution.',
  'revert','Explicit Revert to Needs Review is a rework action, not a product error'
 )
)
FROM p;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_friction_v2()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED (
 SELECT s.id,
 (s.payload#>>'{value,active_users,as_of}')::timestamptz as asof,
 s.source_watermark_at wm
 FROM public.product_snapshot_current c
 JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
 LIMIT 1
),
facts AS MATERIALIZED(
 SELECT f.* FROM p CROSS JOIN LATERAL
 public.overview_friction_company_facts_v2(p.id) f
),
issue_catalog AS (
 SELECT * FROM (VALUES
  ('review_reverted'::text,'Reverted to review'::text,'Transactions'::text,'Rework'::text,1),
  ('bill_upload','Bill upload failed','Uploads','Failure',2),
  ('type_update','Type update failed','Transactions','Failure',3),
  ('invoice_upload','Invoice upload failed','Uploads','Failure',4),
  ('ledger_update','Ledger update failed','Transactions','Failure',5)
 ) AS k(issue_key,label,module,kind,display_order)
),
per_period AS (
 SELECT issue_key,period,
  count(*)::integer eligible,
  count(*) FILTER(WHERE failed_events>0)::integer affected,
  count(*) FILTER(WHERE failed_events>0 AND followup_at IS NOT NULL)::integer later_success,
  count(*) FILTER(WHERE failed_events>0 AND followup_at IS NULL)::integer needs_review
 FROM facts GROUP BY issue_key,period
),
rows AS (
 SELECT k.*,coalesce(c.eligible,0) AS current_eligible,
 coalesce(c.affected,0) AS current_affected,
 coalesce(c.later_success,0) AS current_followup,
 coalesce(c.needs_review,0) AS current_no_followup,
 coalesce(h.eligible,0) AS previous_eligible,
 coalesce(h.affected,0) AS previous_affected,
 coalesce(h.later_success,0) AS previous_followup,
 coalesce(h.needs_review,0) AS previous_no_followup,
 CASE WHEN coalesce(c.eligible,0)>0
  THEN round(c.affected::numeric*100/c.eligible,1) ELSE NULL END AS current_pct,
 CASE WHEN coalesce(h.eligible,0)>0
  THEN round(h.affected::numeric*100/h.eligible,1) ELSE NULL END AS previous_pct
 FROM issue_catalog k
 LEFT JOIN per_period c ON c.issue_key=k.issue_key AND c.period='current'
 LEFT JOIN per_period h ON h.issue_key=k.issue_key AND h.period='previous'
)
SELECT jsonb_build_object(
 'contract','observed_company_friction_v1',
 'snapshot_id',p.id,'as_of',p.asof,'source_watermark_at',p.wm,
 'window',jsonb_build_object(
  'current_start',p.asof-interval '28 days',
  'current_end',p.asof,
  'previous_start',p.asof-interval '56 days',
  'previous_end',p.asof-interval '28 days'
 ),
 'rows',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'key',r.issue_key,'label',r.label,'module',r.module,'kind',r.kind,
   'current',jsonb_build_object(
    'eligible',r.current_eligible,'affected',r.current_affected,
    'followup',r.current_followup,'needs_review',r.current_no_followup,
    'incidence_pct',r.current_pct,
    'followup_pct',CASE WHEN r.current_affected>0
      THEN round(r.current_followup::numeric*100/r.current_affected,1) ELSE NULL END
   ),
   'previous',jsonb_build_object(
    'eligible',r.previous_eligible,'affected',r.previous_affected,
    'followup',r.previous_followup,'needs_review',r.previous_no_followup,
    'incidence_pct',r.previous_pct
   ),
   'change_pp',CASE WHEN r.current_pct IS NOT NULL AND r.previous_pct IS NOT NULL
      THEN round(r.current_pct-r.previous_pct,1) ELSE NULL END
  ) ORDER BY r.current_no_followup DESC,r.current_affected DESC,r.display_order)
  FROM rows r),'[]'::jsonb),
 'basis',jsonb_build_object(
  'population','Distinct external client companies that attempted the given workflow in each rolling 28-day window',
  'affected','Distinct eligible companies with a failed action or an explicit revert to review',
  'later_success','A later success of the same workflow in that company, after its latest recorded failure in the selected period',
  'needs_review','Affected companies with no later success of that workflow observed by the end of the selected period',
  'limitation','Same company and workflow are observed, not the same transaction or upload attempt. These are follow-up signals, not confirmed resolution.',
  'revert','Explicit Revert to Needs Review is a rework action, not a product error'
 )
)
FROM p;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_friction_v3(p_snapshot_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED (
 SELECT s.id,
 (s.payload#>>'{value,active_users,as_of}')::timestamptz as asof,
 s.source_watermark_at wm
 FROM public.product_snapshot s
 WHERE s.kind='overview'
 AND s.id=coalesce(p_snapshot_id,(SELECT c2.snapshot_id FROM public.product_snapshot_current c2 WHERE c2.kind='overview' AND c2.scope_key='' LIMIT 1)) AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD')) AND s.source_status='ok'
 LIMIT 1
),
facts AS MATERIALIZED(
 SELECT f.* FROM p CROSS JOIN LATERAL
 public.overview_friction_company_facts_v3(p.id) f
),
issue_catalog AS (
 SELECT * FROM (VALUES
  ('review_reverted'::text,'Reverted to review'::text,'Transactions'::text,'Rework'::text,1),
  ('bill_upload','Bill upload failed','Uploads','Failure',2),
  ('type_update','Type update failed','Transactions','Failure',3),
  ('invoice_upload','Invoice upload failed','Uploads','Failure',4),
  ('ledger_update','Ledger update failed','Transactions','Failure',5)
 ) AS k(issue_key,label,module,kind,display_order)
),
per_period AS (
 SELECT issue_key,period,
  count(*)::integer eligible,
  count(*) FILTER(WHERE failed_events>0)::integer affected,
  count(*) FILTER(WHERE failed_events>0 AND followup_at IS NOT NULL)::integer later_success,
  count(*) FILTER(WHERE failed_events>0 AND followup_at IS NULL)::integer needs_review
 FROM facts GROUP BY issue_key,period
),
rows AS (
 SELECT k.*,coalesce(c.eligible,0) AS current_eligible,
 coalesce(c.affected,0) AS current_affected,
 coalesce(c.later_success,0) AS current_followup,
 coalesce(c.needs_review,0) AS current_no_followup,
 coalesce(h.eligible,0) AS previous_eligible,
 coalesce(h.affected,0) AS previous_affected,
 coalesce(h.later_success,0) AS previous_followup,
 coalesce(h.needs_review,0) AS previous_no_followup,
 CASE WHEN coalesce(c.eligible,0)>0
  THEN round(c.affected::numeric*100/c.eligible,1) ELSE NULL END AS current_pct,
 CASE WHEN coalesce(h.eligible,0)>0
  THEN round(h.affected::numeric*100/h.eligible,1) ELSE NULL END AS previous_pct
 FROM issue_catalog k
 LEFT JOIN per_period c ON c.issue_key=k.issue_key AND c.period='current'
 LEFT JOIN per_period h ON h.issue_key=k.issue_key AND h.period='previous'
)
SELECT jsonb_build_object(
 'contract','observed_company_friction_v1',
 'snapshot_id',p.id,'as_of',p.asof,'source_watermark_at',p.wm,
 'window',jsonb_build_object(
  'current_start',p.asof-interval '28 days',
  'current_end',p.asof,
  'previous_start',p.asof-interval '56 days',
  'previous_end',p.asof-interval '28 days'
 ),
 'rows',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
   'key',r.issue_key,'label',r.label,'module',r.module,'kind',r.kind,
   'current',jsonb_build_object(
    'eligible',r.current_eligible,'affected',r.current_affected,
    'followup',r.current_followup,'needs_review',r.current_no_followup,
    'incidence_pct',r.current_pct,
    'followup_pct',CASE WHEN r.current_affected>0
      THEN round(r.current_followup::numeric*100/r.current_affected,1) ELSE NULL END
   ),
   'previous',jsonb_build_object(
    'eligible',r.previous_eligible,'affected',r.previous_affected,
    'followup',r.previous_followup,'needs_review',r.previous_no_followup,
    'incidence_pct',r.previous_pct
   ),
   'change_pp',CASE WHEN r.current_pct IS NOT NULL AND r.previous_pct IS NOT NULL
      THEN round(r.current_pct-r.previous_pct,1) ELSE NULL END
  ) ORDER BY r.current_no_followup DESC,r.current_affected DESC,r.display_order)
  FROM rows r),'[]'::jsonb),
 'basis',jsonb_build_object(
  'population','Distinct external client companies that attempted the given workflow in each rolling 28-day window',
  'affected','Distinct eligible companies with a failed action or an explicit revert to review',
  'later_success','A later success of the same workflow in that company, after its latest recorded failure in the selected period',
  'needs_review','Affected companies with no later success of that workflow observed by the end of the selected period',
  'limitation','Same company and workflow are observed, not the same transaction or upload attempt. These are follow-up signals, not confirmed resolution.',
  'revert','Explicit Revert to Needs Review is a rework action, not a product error'
 )
)
FROM p;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_friction_v4(p_snapshot_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
AS $function$
 SELECT metrics_private.read_overview_chart_summary_cached_v1(p_snapshot_id, 'friction');
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_generation(p_snapshot_id bigint)
 RETURNS TABLE(snapshot_id bigint, kind text, scope_key text, published_at timestamp with time zone, source_watermark_at timestamp with time zone, n_events bigint, is_current boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT s.id, s.kind, s.scope_key, c.published_at,
         s.source_watermark_at, s.n_events,
         EXISTS (SELECT 1 FROM public.product_snapshot_current AS cc WHERE cc.snapshot_id = s.id) AS is_current
  FROM public.product_snapshot AS s
  LEFT JOIN public.product_snapshot_current AS c
    ON c.kind = s.kind AND c.scope_key = s.scope_key AND c.snapshot_id = s.id
  WHERE s.id = p_snapshot_id
    AND s.kind IN ('overview', 'overview-feature-usage', 'overview-module-mix', 'overview-friction');
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_history_id_v1(p_as_of date)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
AS $function$
 SELECT s.id FROM public.product_snapshot s
 WHERE s.kind='overview'
 AND s.scope_key='asof='||to_char(p_as_of,'YYYY-MM-DD')
 AND s.source_status='ok'
 AND p_as_of=(date_trunc('month',p_as_of::timestamp)+interval '1 month'-interval '1 day')::date
 AND p_as_of >= date '2026-03-31'
 AND s.source_watermark_at IS NOT NULL
 LIMIT 1;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_independent_core_kpis_v1()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '30s'
AS $function$
WITH published AS MATERIALIZED (
  SELECT
    s.id AS snapshot_id,
    (s.payload #>> '{value,active_users,as_of}')::timestamptz AS as_of_at,
    s.source_watermark_at
  FROM public.product_snapshot_current AS c
  JOIN public.product_snapshot AS s ON s.id = c.snapshot_id
  WHERE c.kind = 'overview'
    AND c.scope_key = ''
    AND s.source_status = 'ok'
  LIMIT 1
),
qualified AS MATERIALIZED (
  SELECT e.distinct_id, e.event_time
  FROM public.events AS e
  CROSS JOIN published AS p
  WHERE e.event_time >= p.as_of_at - interval '60 days'
    AND e.event_time < p.as_of_at
    -- Freeze reads to the same ingestion watermark as the published generation.
    AND e.ingested_at <= p.source_watermark_at
    AND e.distinct_id IS NOT NULL
    AND e.distinct_id <> ''
    -- Mixpanel Accounting Sync has no actor/trigger field. Never count it as
    -- independent human activity, even if it is a qualifying accounting sync.
    AND e.event_name <> 'Accounting Sync'
    AND public.is_core_activity(e.event_name, e.properties)
    AND lower(btrim(coalesce(e.properties->>'status', ''))) <> 'failed'
    AND NOT metrics_private.is_retention_internal_email_v2(e.email)
    AND EXISTS (
      SELECT 1
      FROM public.client_company AS c
      WHERE c.company_id = e.company_id
    )
),
totals AS (
  SELECT
    count(DISTINCT q.distinct_id) FILTER (
      WHERE q.event_time >= p.as_of_at - interval '7 days'
    )::integer AS wau_current,
    count(DISTINCT q.distinct_id) FILTER (
      WHERE q.event_time >= p.as_of_at - interval '14 days'
        AND q.event_time < p.as_of_at - interval '7 days'
    )::integer AS wau_previous,
    count(DISTINCT q.distinct_id) FILTER (
      WHERE q.event_time >= p.as_of_at - interval '30 days'
    )::integer AS mau_current,
    count(DISTINCT q.distinct_id) FILTER (
      WHERE q.event_time < p.as_of_at - interval '30 days'
    )::integer AS mau_previous
  FROM published AS p
  LEFT JOIN qualified AS q ON true
  GROUP BY p.as_of_at
)
SELECT jsonb_build_object(
  'contract', 'independent_core_v1',
  'snapshot_id', p.snapshot_id,
  'as_of', p.as_of_at,
  'source_watermark_at', p.source_watermark_at,
  'wau', jsonb_build_object(
    'current', t.wau_current,
    'previous', t.wau_previous
  ),
  'mau', jsonb_build_object(
    'current', t.mau_current,
    'previous', t.mau_previous
  )
)
FROM published AS p
JOIN totals AS t ON true;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_independent_core_kpis_v2()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '30s'
AS $function$
WITH published AS MATERIALIZED (
  SELECT
    s.id AS snapshot_id,
    (s.payload #>> '{value,active_users,as_of}')::timestamptz AS as_of_at,
    s.source_watermark_at
  FROM public.product_snapshot_current AS c
  JOIN public.product_snapshot AS s ON s.id = c.snapshot_id
  WHERE c.kind = 'overview'
    AND c.scope_key = ''
    AND s.source_status = 'ok'
  LIMIT 1
),
qualified AS MATERIALIZED (
  SELECT e.distinct_id, e.event_time
  FROM metrics_private.events_no_test_v2 AS e
  CROSS JOIN published AS p
  WHERE e.event_time >= p.as_of_at - interval '60 days'
    AND e.event_time < p.as_of_at
    -- Freeze reads to the same ingestion watermark as the published generation.
    AND e.ingested_at <= p.source_watermark_at
    AND e.distinct_id IS NOT NULL
    AND e.distinct_id <> ''
    -- Mixpanel Accounting Sync has no actor/trigger field. Never count it as
    -- independent human activity, even if it is a qualifying accounting sync.
    AND e.event_name <> 'Accounting Sync'
    AND public.is_core_activity(e.event_name, e.properties)
    AND lower(btrim(coalesce(e.properties->>'status', ''))) <> 'failed'
    AND NOT metrics_private.is_retention_internal_email_v2(e.email)
    AND EXISTS (
      SELECT 1
      FROM public.client_company AS c
      WHERE c.company_id = e.company_id
    )
),
totals AS (
  SELECT
    count(DISTINCT q.distinct_id) FILTER (
      WHERE q.event_time >= p.as_of_at - interval '7 days'
    )::integer AS wau_current,
    count(DISTINCT q.distinct_id) FILTER (
      WHERE q.event_time >= p.as_of_at - interval '14 days'
        AND q.event_time < p.as_of_at - interval '7 days'
    )::integer AS wau_previous,
    count(DISTINCT q.distinct_id) FILTER (
      WHERE q.event_time >= p.as_of_at - interval '30 days'
    )::integer AS mau_current,
    count(DISTINCT q.distinct_id) FILTER (
      WHERE q.event_time < p.as_of_at - interval '30 days'
    )::integer AS mau_previous
  FROM published AS p
  LEFT JOIN qualified AS q ON true
  GROUP BY p.as_of_at
)
SELECT jsonb_build_object(
  'contract', 'independent_core_v1',
  'snapshot_id', p.snapshot_id,
  'as_of', p.as_of_at,
  'source_watermark_at', p.source_watermark_at,
  'wau', jsonb_build_object(
    'current', t.wau_current,
    'previous', t.wau_previous
  ),
  'mau', jsonb_build_object(
    'current', t.mau_current,
    'previous', t.mau_previous
  )
)
FROM published AS p
JOIN totals AS t ON true;
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_independent_core_kpis_v3(p_snapshot_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '30s'
AS $function$
WITH published AS MATERIALIZED (
  SELECT
    s.id AS snapshot_id,
    (s.payload #>> '{value,active_users,as_of}')::timestamptz AS as_of_at,
    s.source_watermark_at
  FROM public.product_snapshot s
  WHERE s.kind='overview'
 AND s.id=coalesce(p_snapshot_id,(SELECT c2.snapshot_id FROM public.product_snapshot_current c2 WHERE c2.kind='overview' AND c2.scope_key='' LIMIT 1))
    AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD'))
    AND s.source_status = 'ok'
  LIMIT 1
),
qualified AS MATERIALIZED (
  SELECT e.distinct_id, e.event_time
  FROM metrics_private.events_no_test_v2 AS e
  CROSS JOIN published AS p
  WHERE e.event_time >= p.as_of_at - interval '60 days'
    AND e.event_time < p.as_of_at
    -- Freeze reads to the same ingestion watermark as the published generation.
    AND e.ingested_at <= p.source_watermark_at
    AND e.distinct_id IS NOT NULL
    AND e.distinct_id <> ''
    -- Mixpanel Accounting Sync has no actor/trigger field. Never count it as
    -- independent human activity, even if it is a qualifying accounting sync.
    AND e.event_name <> 'Accounting Sync'
    AND public.is_core_activity(e.event_name, e.properties)
    AND lower(btrim(coalesce(e.properties->>'status', ''))) <> 'failed'
    AND NOT metrics_private.is_retention_internal_email_v2(e.email)
    AND EXISTS (
      SELECT 1
      FROM public.client_company AS c
      WHERE c.company_id = e.company_id
    )
),
totals AS (
  SELECT
    count(DISTINCT q.distinct_id) FILTER (
      WHERE q.event_time >= p.as_of_at - interval '7 days'
    )::integer AS wau_current,
    count(DISTINCT q.distinct_id) FILTER (
      WHERE q.event_time >= p.as_of_at - interval '14 days'
        AND q.event_time < p.as_of_at - interval '7 days'
    )::integer AS wau_previous,
    count(DISTINCT q.distinct_id) FILTER (
      WHERE q.event_time >= p.as_of_at - interval '30 days'
    )::integer AS mau_current,
    count(DISTINCT q.distinct_id) FILTER (
      WHERE q.event_time < p.as_of_at - interval '30 days'
    )::integer AS mau_previous
  FROM published AS p
  LEFT JOIN qualified AS q ON true
  GROUP BY p.as_of_at
)
SELECT jsonb_build_object(
  'contract', 'independent_core_v1',
  'snapshot_id', p.snapshot_id,
  'as_of', p.as_of_at,
  'source_watermark_at', p.source_watermark_at,
  'wau', jsonb_build_object(
    'current', t.wau_current,
    'previous', t.wau_previous
  ),
  'mau', jsonb_build_object(
    'current', t.mau_current,
    'previous', t.mau_previous
  )
)
FROM published AS p
JOIN totals AS t ON true;
$function$
;
