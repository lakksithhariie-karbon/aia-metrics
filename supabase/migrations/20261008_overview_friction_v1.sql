-- Observed friction signals in two adjacent rolling 28-day periods.
-- Each issue is an independently tracked action; company-level later successes
-- are follow-up signals and NOT confirmed repair of the original attempt.
-- Reverting to Needs Review is intentional rework, NOT a product error.
CREATE OR REPLACE FUNCTION public.overview_friction_events_v1(p_snapshot_id bigint)
RETURNS TABLE(
 company_id text,
 distinct_id text,
 email text,
 event_time timestamptz,
 period text,
 issue_key text,
 is_failure boolean,
 is_success boolean,
 event_name text,
 status text,
 activity_type text,
 action text
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
SET statement_timeout TO '35s'
AS $function$
WITH p AS MATERIALIZED (
 SELECT s.id,
 (s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
 s.source_watermark_at AS wm
 FROM public.product_snapshot_current c
 JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key=''
 AND s.source_status='ok' AND c.snapshot_id=p_snapshot_id
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
 FROM public.events e CROSS JOIN p
 WHERE e.event_time>=p.asof-interval '56 days'
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
FROM classified n WHERE n.issue_key IS NOT NULL;
$function$;
REVOKE ALL ON FUNCTION public.overview_friction_events_v1(bigint)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.overview_friction_events_v1(bigint)
 TO service_role;

CREATE OR REPLACE FUNCTION public.overview_friction_company_facts_v1(p_snapshot_id bigint)
RETURNS TABLE(
 issue_key text,period text,company_id text,
 eligible_events integer,failed_events integer,success_events integer,
 first_failure_at timestamptz,last_failure_at timestamptz,
 followup_at timestamptz,last_event_at timestamptz,
 observed_users integer
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
SET statement_timeout TO '35s'
AS $function$
WITH ev AS MATERIALIZED (
 SELECT * FROM public.overview_friction_events_v1(p_snapshot_id)
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
)
SELECT g.issue_key,g.period,g.company_id,
 g.eligible_events,g.failed_events,g.success_events,
 g.first_failure_at,g.last_failure_at,
 (SELECT min(x.event_time) FROM ev x
  WHERE x.issue_key=g.issue_key AND x.period=g.period AND x.company_id=g.company_id
  AND x.is_success AND x.event_time>g.last_failure_at) AS followup_at,
 g.last_event_at,g.observed_users
FROM grouped g;
$function$;
REVOKE ALL ON FUNCTION public.overview_friction_company_facts_v1(bigint)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.overview_friction_company_facts_v1(bigint)
 TO service_role;

CREATE OR REPLACE FUNCTION public.read_overview_friction_v1()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
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
$function$;
REVOKE ALL ON FUNCTION public.read_overview_friction_v1()
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_friction_v1()
 TO service_role;
