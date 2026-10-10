-- Shadow Overview v2 functions to exclude directory-marked test companies
-- from all event-backed usage, adoption, workflow, issues and drill populations.
-- The currently published v1 production dashboard is deliberately unchanged.
CREATE OR REPLACE VIEW metrics_private.events_no_test_v2 AS
SELECT e.*
FROM public.events e
WHERE NOT EXISTS (
 SELECT 1 FROM public.company_directory d
 WHERE d.company_uuid::text=e.company_id AND d.is_test
);
REVOKE ALL ON metrics_private.events_no_test_v2 FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.overview_workflow_events_v2(p_snapshot_id bigint)
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
 FROM public.product_snapshot_current c
 JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key=''
   AND s.source_status='ok' AND c.snapshot_id=p_snapshot_id
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
REVOKE ALL ON FUNCTION public.overview_workflow_events_v2(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.overview_workflow_events_v2(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.overview_adoption_company_facts_v2(p_snapshot_id bigint)
 RETURNS TABLE(company_id text, company_name text, integration_type text, is_test boolean, integrated_at timestamp with time zone, first_core_7d_at timestamp with time zone, first_core_28d_at timestamp with time zone, first_sync_after_core_at timestamp with time zone, training_sync_at timestamp with time zone, post_training_core_at timestamp with time zone, value_at timestamp with time zone, active_weeks integer, core_actions integer, ap_actions integer, ar_actions integer, transaction_actions integer, sync_events integer, last_core_at timestamp with time zone, step_flags jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH published AS MATERIALIZED (
  SELECT s.id, s.source_watermark_at,
    (s.payload #>> '{value,active_users,as_of}')::timestamptz AS as_of_at
  FROM public.product_snapshot_current c
  JOIN public.product_snapshot s ON s.id=c.snapshot_id
  WHERE c.kind='overview' AND c.scope_key=''
    AND s.source_status='ok' AND c.snapshot_id=p_snapshot_id
  LIMIT 1
),
base AS MATERIALIZED (
  SELECT m.member_id AS company_id,
    coalesce(nullif(m.card->>'company_name',''),m.member_id) AS company_name,
    coalesce(nullif(m.card->>'integration_type',''),'Unknown') AS integration_type,
    coalesce((m.card->>'is_test')::boolean,false) AS is_test,
    (m.card->>'integrated_at')::timestamptz AS integrated_at
  FROM public.product_overview_member m
  JOIN published p ON p.id=m.snapshot_id
  WHERE m.kind='overview' AND m.drill_key='core_adoption_7d'
    AND m.tab='all'
    AND NOT coalesce((m.card->>'is_test')::boolean,false)
    AND NOT EXISTS(SELECT 1 FROM public.company_directory d WHERE d.company_uuid::text=m.member_id AND d.is_test)
    AND (m.card->>'integrated_at')::timestamptz + interval '28 days'<=p.as_of_at
),
qualified AS MATERIALIZED (
  SELECT b.company_id,b.integrated_at,e.event_time,e.event_name,e.properties,
    floor(extract(epoch FROM (e.event_time-b.integrated_at))/604800)::int AS rel_week,
    (e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS local_day,
    public.is_qualifying_sync(e.event_name,e.properties) AS is_sync,
    (e.event_name<>'Accounting Sync' AND public.is_core_activity(e.event_name,e.properties))
      AS is_work,
    CASE
      WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill')
        OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill')
        OR e.event_name='Vendor Mismatch Resolved' THEN 'ap'
      WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice')
        OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice')
        OR e.event_name='Invoice Bulk Edited' THEN 'ar'
      ELSE 'transactions'
    END AS module
  FROM base b JOIN metrics_private.events_no_test_v2 e ON e.company_id=b.company_id
  CROSS JOIN published p
  WHERE e.event_time>=b.integrated_at
    AND e.event_time<b.integrated_at+interval '28 days'
    AND e.event_time<p.as_of_at
    AND e.ingested_at<=p.source_watermark_at
    AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
    AND NOT metrics_private.is_retention_internal_email_v2(e.email)
    AND (
      (e.event_name<>'Accounting Sync' AND public.is_core_activity(e.event_name,e.properties))
      OR public.is_qualifying_sync(e.event_name,e.properties)
    )
),
activity AS (
  SELECT q.company_id,
    min(q.event_time) FILTER(WHERE q.is_work AND q.rel_week=0) AS first_7,
    min(q.event_time) FILTER(WHERE q.is_work) AS first_28,
    min(q.event_time) FILTER(WHERE q.is_sync) AS first_training,
    count(DISTINCT q.rel_week) FILTER(WHERE q.is_work)::int AS active_weeks,
    count(*) FILTER(WHERE q.is_work)::int AS core_actions,
    count(*) FILTER(WHERE q.is_work AND q.module='ap')::int AS ap_actions,
    count(*) FILTER(WHERE q.is_work AND q.module='ar')::int AS ar_actions,
    count(*) FILTER(WHERE q.is_work AND q.module='transactions')::int AS transaction_actions,
    count(*) FILTER(WHERE q.is_sync)::int AS sync_events,
    max(q.event_time) FILTER(WHERE q.is_work) AS last_core_at,
    jsonb_build_object(
      'bill_upload',count(*) FILTER(WHERE q.is_work AND q.event_name='Upload'
                        AND lower(btrim(q.properties->>'type'))='bill')>0,
      'bill_entity',count(*) FILTER(WHERE q.is_work AND q.event_name='Entity Created'
                        AND lower(btrim(q.properties->>'entityType'))='bill')>0,
      'vendor_mismatch',count(*) FILTER(WHERE q.is_work AND q.event_name='Vendor Mismatch Resolved')>0,
      'invoice_upload',count(*) FILTER(WHERE q.is_work AND q.event_name='Upload'
                        AND lower(btrim(q.properties->>'type'))='invoice')>0,
      'invoice_entity',count(*) FILTER(WHERE q.is_work AND q.event_name='Entity Created'
                        AND lower(btrim(q.properties->>'entityType'))='invoice')>0,
      'invoice_bulk',count(*) FILTER(WHERE q.is_work AND q.event_name='Invoice Bulk Edited')>0,
      'statement_upload',count(*) FILTER(WHERE q.is_work AND q.event_name='Upload'
                        AND lower(btrim(q.properties->>'type'))='statement')>0,
      'transaction_ledger',count(*) FILTER(WHERE q.is_work AND q.event_name='Transaction Ledger Updated')>0,
      'transaction_status',count(*) FILTER(WHERE q.is_work AND q.event_name='Transaction Status')>0,
      'transaction_type',count(*) FILTER(WHERE q.is_work AND q.event_name='Transaction Type Updated')>0
    ) AS step_flags
  FROM qualified q
  GROUP BY q.company_id
),
post_core_sync AS (
  SELECT q.company_id,min(q.event_time) AS sync_at
  FROM qualified q JOIN activity a ON a.company_id=q.company_id
  WHERE a.first_7 IS NOT NULL AND q.is_sync AND q.event_time>a.first_7
  GROUP BY q.company_id
),
post_training_core AS (
  SELECT q.company_id,min(q.event_time) AS post_core_at
  FROM qualified q JOIN activity a ON a.company_id=q.company_id
  WHERE q.is_work AND a.first_training IS NOT NULL
    AND q.local_day > (a.first_training AT TIME ZONE 'Asia/Kolkata')::date
  GROUP BY q.company_id
),
value_completion AS (
  SELECT q.company_id,min(q.event_time) AS value_at
  FROM qualified q JOIN post_training_core t ON t.company_id=q.company_id
  WHERE q.is_sync AND q.event_time>t.post_core_at
  GROUP BY q.company_id
)
SELECT
  b.company_id,b.company_name,b.integration_type,b.is_test,b.integrated_at,
  a.first_7,a.first_28,s.sync_at,
  a.first_training,t.post_core_at,v.value_at,
  coalesce(a.active_weeks,0),coalesce(a.core_actions,0),
  coalesce(a.ap_actions,0),coalesce(a.ar_actions,0),
  coalesce(a.transaction_actions,0),coalesce(a.sync_events,0),
  a.last_core_at,
  coalesce(a.step_flags,'{}'::jsonb)
FROM base b
LEFT JOIN activity a USING(company_id)
LEFT JOIN post_core_sync s USING(company_id)
LEFT JOIN post_training_core t USING(company_id)
LEFT JOIN value_completion v USING(company_id);
$function$;
REVOKE ALL ON FUNCTION public.overview_adoption_company_facts_v2(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.overview_adoption_company_facts_v2(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.overview_friction_events_v2(p_snapshot_id bigint)
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
 FROM metrics_private.events_no_test_v2 e CROSS JOIN p
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
REVOKE ALL ON FUNCTION public.overview_friction_events_v2(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.overview_friction_events_v2(bigint) TO service_role;

CREATE OR REPLACE FUNCTION public.overview_friction_company_facts_v2(p_snapshot_id bigint)
 RETURNS TABLE(issue_key text, period text, company_id text, eligible_events integer, failed_events integer, success_events integer, first_failure_at timestamp with time zone, last_failure_at timestamp with time zone, followup_at timestamp with time zone, last_event_at timestamp with time zone, observed_users integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH ev AS MATERIALIZED (
 SELECT * FROM public.overview_friction_events_v2(p_snapshot_id)
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
REVOKE ALL ON FUNCTION public.overview_friction_company_facts_v2(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.overview_friction_company_facts_v2(bigint) TO service_role;

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
$function$;
REVOKE ALL ON FUNCTION public.read_overview_independent_core_kpis_v2() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_independent_core_kpis_v2() TO service_role;

CREATE OR REPLACE FUNCTION public.read_overview_active_charts_v2()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '30s'
AS $function$
WITH published AS MATERIALIZED (
 SELECT s.id AS snapshot_id,
   (s.payload #>> '{value,active_users,as_of}')::timestamptz AS as_of_at,
   s.source_watermark_at,
   date_trunc('week',(s.payload #>> '{value,active_users,as_of}')::timestamptz
     AT TIME ZONE 'Asia/Kolkata')::date AS current_week
 FROM public.product_snapshot_current c
 JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
 LIMIT 1
),
qualified AS MATERIALIZED (
 SELECT DISTINCT e.distinct_id,
   date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS week_start
 FROM metrics_private.events_no_test_v2 e CROSS JOIN published p
 WHERE e.event_time<p.as_of_at AND e.ingested_at<=p.source_watermark_at
   AND e.distinct_id IS NOT NULL AND e.distinct_id<>''
   AND e.event_name<>'Accounting Sync'
   AND public.is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
   AND EXISTS(SELECT 1 FROM public.client_company cc WHERE cc.company_id=e.company_id)
),
first_observed AS (
 SELECT distinct_id,min(week_start) AS first_week
 FROM qualified GROUP BY distinct_id
),
weeks AS (
 SELECT (p.current_week - i*7)::date AS week_start
 FROM published p CROSS JOIN generate_series(12,1,-1) i
),
weekly AS (
 SELECT w.week_start,
   count(q.distinct_id)::integer AS users,
   count(q.distinct_id) FILTER(WHERE f.first_week=w.week_start)::integer AS first_observed,
   count(q.distinct_id) FILTER(WHERE f.first_week<w.week_start)::integer AS returning
 FROM weeks w LEFT JOIN qualified q ON q.week_start=w.week_start
 LEFT JOIN first_observed f ON f.distinct_id=q.distinct_id
 GROUP BY w.week_start
),
four_weeks AS (
 SELECT q.distinct_id,count(*)::integer AS active_weeks
 FROM qualified q CROSS JOIN published p
 WHERE q.week_start>=p.current_week - 28
   AND q.week_start<p.current_week
 GROUP BY q.distinct_id
),
buckets AS (
 SELECT g.weeks,
   count(f.distinct_id)::integer AS users
 FROM generate_series(1,4) g(weeks)
 LEFT JOIN four_weeks f ON f.active_weeks=g.weeks
 GROUP BY g.weeks
),
pop AS (SELECT coalesce(sum(users),0)::integer AS n FROM buckets)
SELECT jsonb_build_object(
 'contract','independent_core_active_charts_v1',
 'snapshot_id',p.snapshot_id,
 'as_of',p.as_of_at,
 'source_watermark_at',p.source_watermark_at,
 'current_incomplete_week',p.current_week,
 'first_observed_definition','first eligible recorded week in imported event history',
 'quality_notice','Activity tracking was incomplete during May-July 2026; first-observed is not a signup or activation metric.',
 'weekly',jsonb_build_object(
   'rows',coalesce((SELECT jsonb_agg(jsonb_build_object(
     'week_start',w.week_start,'users',w.users,'returning',w.returning,
     'first_observed',w.first_observed,
     'limited_tracking',w.week_start>=date '2026-05-01'
                        AND w.week_start<date '2026-08-01'
   ) ORDER BY w.week_start) FROM weekly w),'[]'::jsonb)
 ),
 'frequency',jsonb_build_object(
   'window_start',p.current_week - 28,
   'window_end',p.current_week,
   'total_users',pop.n,
   'rows',coalesce((SELECT jsonb_agg(jsonb_build_object(
     'active_weeks',b.weeks,'users',b.users,
     'share_pct',CASE WHEN pop.n>0
       THEN round(100.0*b.users::numeric/pop.n,1) ELSE 0 END
   ) ORDER BY b.weeks) FROM buckets b),'[]'::jsonb)
 )
)
FROM published p CROSS JOIN pop;
$function$;
REVOKE ALL ON FUNCTION public.read_overview_active_charts_v2() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_active_charts_v2() TO service_role;

CREATE OR REPLACE FUNCTION public.read_overview_adoption_journey_v2()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH published AS MATERIALIZED (
  SELECT s.id,
         (s.payload#>>'{value,active_users,as_of}')::timestamptz AS as_of_at,
         s.source_watermark_at
  FROM public.product_snapshot_current c
  JOIN public.product_snapshot s ON s.id=c.snapshot_id
  WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
  LIMIT 1
),
facts AS MATERIALIZED (
  SELECT f.* FROM published p CROSS JOIN LATERAL
  public.overview_adoption_company_facts_v2(p.id) AS f
),
counts AS (
  SELECT count(*)::integer AS integrated,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL)::integer AS core_7d,
    count(*) FILTER(WHERE first_sync_after_core_at IS NOT NULL)::integer AS sync_after_core,
    count(*) FILTER(WHERE value_at IS NOT NULL)::integer AS value_28d,
    count(*) FILTER(WHERE active_weeks>=2)::integer AS sustained_28d,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL AND ap_actions>0)::integer AS ap_companies,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL AND ar_actions>0)::integer AS ar_companies,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL AND transaction_actions>0)::integer AS txn_companies,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'bill_upload'='true')::integer AS bill_upload,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'bill_entity'='true')::integer AS bill_entity,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'vendor_mismatch'='true')::integer AS vendor_mismatch,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'invoice_upload'='true')::integer AS invoice_upload,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'invoice_entity'='true')::integer AS invoice_entity,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'invoice_bulk'='true')::integer AS invoice_bulk,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'statement_upload'='true')::integer AS statement_upload,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'transaction_ledger'='true')::integer AS transaction_ledger,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'transaction_status'='true')::integer AS transaction_status,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'transaction_type'='true')::integer AS transaction_type
  FROM facts
)
SELECT jsonb_build_object(
  'contract','mature_independent_adoption_v1',
  'snapshot_id',p.id,
  'as_of',p.as_of_at,
  'source_watermark_at',p.source_watermark_at,
  'cohort_start',p.as_of_at-interval '56 days',
  'cohort_end',p.as_of_at-interval '28 days',
  'total',c.integrated,
  'outcomes',jsonb_build_object(
    'core_7d',c.core_7d,
    'value_28d',c.value_28d,
    'sustained_28d',c.sustained_28d
  ),
  'stages',jsonb_build_object(
    'integration',c.integrated,
    'started_work',c.core_7d,
    'qualifying_sync',c.sync_after_core
  ),
  'modules',jsonb_build_object(
    'ap',c.ap_companies,'ar',c.ar_companies,'transactions',c.txn_companies
  ),
  'steps',jsonb_build_object(
    'bill_upload',c.bill_upload,'bill_entity',c.bill_entity,
    'vendor_mismatch',c.vendor_mismatch,
    'invoice_upload',c.invoice_upload,'invoice_entity',c.invoice_entity,
    'invoice_bulk',c.invoice_bulk,
    'statement_upload',c.statement_upload,
    'transaction_ledger',c.transaction_ledger,
    'transaction_status',c.transaction_status,
    'transaction_type',c.transaction_type
  ),
  'basis',jsonb_build_object(
    'integration','Successful recorded Tally/Zoho integration; mature 28-day cohort',
    'core_7d','Independent qualifying core work within 7 days',
    'qualifying_sync','Qualifying accounting sync after first 7-day core work, within 28 days',
    'value_28d','Integration, training sync, independent core on later IST day, and closing sync, in 28 days',
    'sustained_28d','Independent core work in at least 2 of the first 4 seven-day periods',
    'modules','Overlapping usage in first 28 days among companies that started within 7 days'
  )
)
FROM published p CROSS JOIN counts c;
$function$;
REVOKE ALL ON FUNCTION public.read_overview_adoption_journey_v2() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_adoption_journey_v2() TO service_role;

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
$function$;
REVOKE ALL ON FUNCTION public.read_overview_workflow_charts_v2() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_workflow_charts_v2() TO service_role;

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
$function$;
REVOKE ALL ON FUNCTION public.read_overview_friction_v2() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_friction_v2() TO service_role;

CREATE OR REPLACE FUNCTION public.read_overview_core_users_v2(p_snapshot_id bigint, p_segment text DEFAULT 'mau'::text, p_query text DEFAULT ''::text, p_module text DEFAULT 'all'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '25s'
AS $function$
WITH published AS MATERIALIZED (
  SELECT s.id AS snapshot_id,
         (s.payload #>> '{value,active_users,as_of}')::timestamptz AS as_of_at,
         s.source_watermark_at
  FROM public.product_snapshot_current c
  JOIN public.product_snapshot s ON s.id=c.snapshot_id
  WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
    AND c.snapshot_id=p_snapshot_id
  LIMIT 1
),
qualified AS MATERIALIZED (
  SELECT e.distinct_id, e.company_id, e.email, e.company, e.event_time,
         (e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS activity_day,
         CASE
           WHEN e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill'
             OR e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill'
             OR e.event_name='Vendor Mismatch Resolved'
             THEN 'ap'
           WHEN e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice'
             OR e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice'
             OR e.event_name='Invoice Bulk Edited'
             THEN 'ar'
           ELSE 'transactions'
         END AS module
  FROM metrics_private.events_no_test_v2 e CROSS JOIN published p
  WHERE e.event_time >= p.as_of_at - interval '30 days'
    AND e.event_time < p.as_of_at
    AND e.ingested_at <= p.source_watermark_at
    AND e.distinct_id IS NOT NULL AND e.distinct_id <> ''
    AND e.company_id IS NOT NULL AND e.company_id <> ''
    AND e.event_name <> 'Accounting Sync'
    AND public.is_core_activity(e.event_name,e.properties)
    AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
    AND NOT metrics_private.is_retention_internal_email_v2(e.email)
    AND EXISTS (SELECT 1 FROM public.client_company c WHERE c.company_id=e.company_id)
),
pairs AS MATERIALIZED (
  SELECT q.distinct_id, q.company_id, max(nullif(q.email,'')) AS email,
         max(nullif(q.company,'')) AS event_company_name,
         count(*)::integer AS actions_30,
         count(*) FILTER(WHERE q.event_time >= p.as_of_at-interval '7 days')::integer AS actions_7,
         count(DISTINCT q.activity_day)::integer AS active_days_30,
         count(DISTINCT q.activity_day) FILTER(WHERE q.event_time>=p.as_of_at-interval '7 days')::integer AS active_days_7,
         max(q.event_time) AS last_30,
         max(q.event_time) FILTER(WHERE q.event_time>=p.as_of_at-interval '7 days') AS last_7,
         count(*) FILTER(WHERE q.module='ap')::integer AS ap_30,
         count(*) FILTER(WHERE q.module='ar')::integer AS ar_30,
         count(*) FILTER(WHERE q.module='transactions')::integer AS transactions_30,
         count(*) FILTER(WHERE q.module='ap' AND q.event_time>=p.as_of_at-interval '7 days')::integer AS ap_7,
         count(*) FILTER(WHERE q.module='ar' AND q.event_time>=p.as_of_at-interval '7 days')::integer AS ar_7,
         count(*) FILTER(WHERE q.module='transactions' AND q.event_time>=p.as_of_at-interval '7 days')::integer AS transactions_7
  FROM qualified q CROSS JOIN published p
  GROUP BY q.distinct_id,q.company_id
),
named_pairs AS MATERIALIZED (
  SELECT a.*,coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),
      a.event_company_name,a.company_id) AS company_name,
      coalesce(d.is_test,false) AS is_test
  FROM pairs a
  LEFT JOIN public.company_directory d ON d.company_uuid::text=a.company_id
  LEFT JOIN public.company_profile cp ON cp.company_id=a.company_id
),
users AS MATERIALIZED (
  SELECT a.distinct_id AS id,max(a.email) AS email,
         sum(a.actions_30)::integer AS actions_30,
         sum(a.actions_7)::integer AS actions_7,
         sum(a.ap_30)::integer AS ap_30, sum(a.ar_30)::integer AS ar_30,
         sum(a.transactions_30)::integer AS transactions_30,
         sum(a.ap_7)::integer AS ap_7, sum(a.ar_7)::integer AS ar_7,
         sum(a.transactions_7)::integer AS transactions_7,
         max(a.last_30) AS last_30, max(a.last_7) AS last_7
  FROM named_pairs a GROUP BY a.distinct_id
),
user_days AS (
  SELECT q.distinct_id AS id,count(DISTINCT q.activity_day)::integer AS days_30,
         count(DISTINCT q.activity_day) FILTER(
           WHERE q.event_time>=p.as_of_at-interval '7 days'
         )::integer AS days_7
  FROM qualified q CROSS JOIN published p GROUP BY q.distinct_id
),
classified AS MATERIALIZED (
  SELECT u.*,d.days_30,d.days_7,
         CASE WHEN p_segment='wau' THEN u.actions_7>0
              WHEN p_segment='mau_only' THEN u.actions_7=0
              ELSE u.actions_30>0 END AS included
  FROM users u JOIN user_days d USING(id)
),
matched AS (
  SELECT u.*
  FROM classified u
  WHERE u.included
    AND (
      coalesce(btrim(p_query),'')=''
      OR u.email ILIKE '%'||left(btrim(p_query),80)||'%'
      OR EXISTS(
        SELECT 1 FROM named_pairs a WHERE a.distinct_id=u.id
        AND (p_segment<>'wau' OR a.actions_7>0)
        AND a.company_name ILIKE '%'||left(btrim(p_query),80)||'%'
      )
    )
    AND (
      p_module NOT IN ('ap','ar','transactions')
      OR (p_module='ap' AND
          CASE WHEN p_segment='wau' THEN u.ap_7 ELSE u.ap_30 END >0)
      OR (p_module='ar' AND
          CASE WHEN p_segment='wau' THEN u.ar_7 ELSE u.ar_30 END >0)
      OR (p_module='transactions' AND
          CASE WHEN p_segment='wau' THEN u.transactions_7 ELSE u.transactions_30 END >0)
    )
),
page_rows AS (
  SELECT u.* FROM matched u
  ORDER BY (CASE WHEN p_segment='wau' THEN u.last_7 ELSE u.last_30 END) DESC NULLS LAST, u.id
  LIMIT greatest(1,least(coalesce(p_page_size,10),25))
  OFFSET (greatest(coalesce(p_page,1),1)-1)*greatest(1,least(coalesce(p_page_size,10),25))
)
SELECT jsonb_build_object(
  'snapshot_id',p.snapshot_id,
  'segment',p_segment,
  'as_of',p.as_of_at,
  'source_watermark_at',p.source_watermark_at,
  'total',(SELECT count(*) FROM matched),
  'segment_total',(SELECT count(*) FROM classified WHERE included),
  'page',greatest(coalesce(p_page,1),1),
  'page_size',greatest(1,least(coalesce(p_page_size,10),25)),
  'rows',coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'id',u.id,
      'email',coalesce(u.email,u.id),
      'actions',CASE WHEN p_segment='wau' THEN u.actions_7 ELSE u.actions_30 END,
      'active_days',CASE WHEN p_segment='wau' THEN u.days_7 ELSE u.days_30 END,
      'last_active_at',CASE WHEN p_segment='wau' THEN u.last_7 ELSE u.last_30 END,
      'modules',jsonb_build_object(
        'ap',CASE WHEN p_segment='wau' THEN u.ap_7 ELSE u.ap_30 END,
        'ar',CASE WHEN p_segment='wau' THEN u.ar_7 ELSE u.ar_30 END,
        'transactions',CASE WHEN p_segment='wau' THEN u.transactions_7 ELSE u.transactions_30 END
      ),
      'companies',coalesce((
        SELECT jsonb_agg(jsonb_build_object(
          'id',a.company_id, 'name',a.company_name,'is_test',a.is_test,
          'actions',CASE WHEN p_segment='wau' THEN a.actions_7 ELSE a.actions_30 END,
          'active_days',CASE WHEN p_segment='wau' THEN a.active_days_7 ELSE a.active_days_30 END,
          'last_active_at',CASE WHEN p_segment='wau' THEN a.last_7 ELSE a.last_30 END,
          'modules',jsonb_build_object(
            'ap',CASE WHEN p_segment='wau' THEN a.ap_7 ELSE a.ap_30 END,
            'ar',CASE WHEN p_segment='wau' THEN a.ar_7 ELSE a.ar_30 END,
            'transactions',CASE WHEN p_segment='wau' THEN a.transactions_7 ELSE a.transactions_30 END
          )
        ) ORDER BY
          (CASE WHEN p_segment='wau' THEN a.last_7 ELSE a.last_30 END) DESC NULLS LAST,a.company_id)
        FROM named_pairs a
        WHERE a.distinct_id=u.id AND (p_segment<>'wau' OR a.actions_7>0)
      ),'[]'::jsonb)
    ) ORDER BY (CASE WHEN p_segment='wau' THEN u.last_7 ELSE u.last_30 END) DESC NULLS LAST,u.id)
    FROM page_rows u
  ),'[]'::jsonb)
)
FROM published p;
$function$;
REVOKE ALL ON FUNCTION public.read_overview_core_users_v2(bigint,text,text,text,integer,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_core_users_v2(bigint,text,text,text,integer,integer) TO service_role;

CREATE OR REPLACE FUNCTION public.read_overview_core_company_v2(p_snapshot_id bigint, p_scope text, p_user_id text, p_company_id text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
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
 FROM metrics_private.events_no_test_v2 e CROSS JOIN published p
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
 FROM metrics_private.events_no_test_v2 e CROSS JOIN published p
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
REVOKE ALL ON FUNCTION public.read_overview_core_company_v2(bigint,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_core_company_v2(bigint,text,text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.read_overview_active_chart_users_v2(p_snapshot_id bigint, p_kind text, p_key text, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_module text DEFAULT 'all'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '30s'
AS $function$
WITH published AS MATERIALIZED (
 SELECT s.id AS snapshot_id,
   (s.payload#>>'{value,active_users,as_of}')::timestamptz AS as_of_at,
   s.source_watermark_at AS watermark,
   date_trunc('week',(s.payload#>>'{value,active_users,as_of}')::timestamptz
     AT TIME ZONE 'Asia/Kolkata')::date AS current_week
 FROM public.product_snapshot_current c
 JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
   AND c.snapshot_id=p_snapshot_id
 LIMIT 1
),
scope AS (
 SELECT p.*,
   CASE WHEN p_kind='weekly' AND p_key ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        THEN p_key::date ELSE NULL::date END AS requested_week,
   CASE WHEN p_kind='frequency' AND p_key IN ('1','2','3','4')
        THEN p_key::int ELSE NULL::int END AS requested_frequency,
   CASE WHEN p_kind='weekly' AND p_key ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        THEN p_key::date ELSE (p.current_week-28)::date END AS window_date,
   CASE WHEN p_kind='weekly' THEN 7 ELSE 28 END AS window_days
 FROM published p
 WHERE (p_kind='weekly'
        AND p_key ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        AND (p.current_week-p_key::date) BETWEEN 7 AND 84
        AND (p.current_week-p_key::date)%7=0
        AND p_segment IN ('all','returning','first_observed'))
    OR (p_kind='frequency'
        AND p_key IN ('1','2','3','4') AND p_segment='all')
),
valid_week_pairs AS MATERIALIZED (
 SELECT DISTINCT e.distinct_id,
   date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS week_start
 FROM metrics_private.events_no_test_v2 e CROSS JOIN scope s
 WHERE e.event_time < s.as_of_at
   AND e.ingested_at<=s.watermark
   AND e.distinct_id IS NOT NULL AND e.distinct_id <> ''
   AND e.event_name <> 'Accounting Sync'
   AND public.is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
   AND EXISTS(SELECT 1 FROM public.client_company cc WHERE cc.company_id=e.company_id)
),
first_week AS (
 SELECT distinct_id,min(week_start) AS first_week
 FROM valid_week_pairs GROUP BY distinct_id
),
four_week_frequency AS (
 SELECT distinct_id,count(*)::integer AS weeks
 FROM valid_week_pairs q CROSS JOIN scope s
 WHERE q.week_start >= s.current_week-28
   AND q.week_start < s.current_week
 GROUP BY distinct_id
),
qualified_window AS MATERIALIZED (
 SELECT e.distinct_id,e.company_id,
   nullif(e.email,'') AS email,nullif(e.company,'') AS event_company_name,
   e.event_time,(e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS activity_day,
   CASE
     WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill')
       OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill')
       OR e.event_name='Vendor Mismatch Resolved' THEN 'ap'
     WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice')
       OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice')
       OR e.event_name='Invoice Bulk Edited' THEN 'ar'
     ELSE 'transactions'
   END AS module
 FROM metrics_private.events_no_test_v2 e CROSS JOIN scope s
 WHERE e.event_time >= (s.window_date::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.event_time < ((s.window_date+s.window_days)::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.ingested_at<=s.watermark
   AND e.distinct_id IS NOT NULL AND e.distinct_id <> ''
   AND e.company_id IS NOT NULL AND e.company_id <> ''
   AND e.event_name <> 'Accounting Sync'
   AND public.is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
   AND EXISTS(SELECT 1 FROM public.client_company cc WHERE cc.company_id=e.company_id)
),
per_company AS MATERIALIZED (
 SELECT e.distinct_id,e.company_id,
   max(e.email) AS email,max(e.event_company_name) AS event_company_name,
   count(*)::int AS actions,count(DISTINCT e.activity_day)::int AS active_days,
   max(e.event_time) AS last_active_at,
   count(*) FILTER(WHERE e.module='ap')::int AS ap,
   count(*) FILTER(WHERE e.module='ar')::int AS ar,
   count(*) FILTER(WHERE e.module='transactions')::int AS transactions
 FROM qualified_window e GROUP BY e.distinct_id,e.company_id
),
named_company AS MATERIALIZED (
 SELECT a.*,coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),
                        a.event_company_name,a.company_id) AS company_name,
        coalesce(d.is_test,false) AS is_test
 FROM per_company a
 LEFT JOIN public.company_directory d ON d.company_uuid::text=a.company_id
 LEFT JOIN public.company_profile cp ON cp.company_id=a.company_id
),
per_user AS MATERIALIZED (
 SELECT q.distinct_id AS id,max(q.email) AS email,
   count(*)::int AS actions,
   count(DISTINCT q.activity_day)::int AS active_days,
   max(q.event_time) AS last_active_at,
   count(*) FILTER(WHERE q.module='ap')::int AS ap,
   count(*) FILTER(WHERE q.module='ar')::int AS ar,
   count(*) FILTER(WHERE q.module='transactions')::int AS transactions
 FROM qualified_window q GROUP BY q.distinct_id
),
qualified_users AS MATERIALIZED (
 SELECT u.*
 FROM per_user u
 JOIN scope s ON true
 LEFT JOIN first_week f ON f.distinct_id=u.id
 LEFT JOIN four_week_frequency fw ON fw.distinct_id=u.id
 WHERE CASE WHEN p_kind='weekly' THEN
   CASE p_segment WHEN 'first_observed' THEN f.first_week=s.requested_week
                  WHEN 'returning' THEN f.first_week<s.requested_week
                  ELSE true END
 ELSE fw.weeks=s.requested_frequency END
),
matched AS MATERIALIZED (
 SELECT u.* FROM qualified_users u
 WHERE (coalesce(btrim(p_query),'')=''
        OR u.email ILIKE '%'||left(btrim(p_query),80)||'%'
        OR EXISTS (
          SELECT 1 FROM named_company c WHERE c.distinct_id=u.id
            AND c.company_name ILIKE '%'||left(btrim(p_query),80)||'%'
        ))
   AND (p_module NOT IN ('ap','ar','transactions')
        OR (p_module='ap' AND u.ap>0)
        OR (p_module='ar' AND u.ar>0)
        OR (p_module='transactions' AND u.transactions>0))
),
paged AS (
 SELECT u.* FROM matched u
 ORDER BY u.last_active_at DESC NULLS LAST,u.id
 LIMIT greatest(1,least(coalesce(p_page_size,10),25))
 OFFSET (greatest(coalesce(p_page,1),1)-1)
        *greatest(1,least(coalesce(p_page_size,10),25))
)
SELECT jsonb_build_object(
 'contract','independent_core_active_chart_users_v1',
 'snapshot_id',s.snapshot_id,
 'kind',p_kind,'key',p_key,'segment',p_segment,
 'as_of',s.as_of_at,'source_watermark_at',s.watermark,
 'window_start',s.window_date,
 'window_end',s.window_date+s.window_days,
 'segment_total',(SELECT count(*) FROM qualified_users),
 'total',(SELECT count(*) FROM matched),
 'page',greatest(coalesce(p_page,1),1),
 'page_size',greatest(1,least(coalesce(p_page_size,10),25)),
 'rows',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'id',u.id,'email',coalesce(u.email,u.id),
     'actions',u.actions,'active_days',u.active_days,
     'last_active_at',u.last_active_at,
     'modules',jsonb_build_object(
       'ap',u.ap,'ar',u.ar,'transactions',u.transactions
     ),
     'companies',coalesce((
       SELECT jsonb_agg(jsonb_build_object(
         'id',c.company_id,'name',c.company_name,'is_test',c.is_test,
         'actions',c.actions,'active_days',c.active_days,
         'last_active_at',c.last_active_at,
         'modules',jsonb_build_object(
           'ap',c.ap,'ar',c.ar,'transactions',c.transactions
         )
       ) ORDER BY c.last_active_at DESC NULLS LAST,c.company_id)
       FROM named_company c WHERE c.distinct_id=u.id
     ),'[]'::jsonb)
   ) ORDER BY u.last_active_at DESC NULLS LAST,u.id)
   FROM paged u
 ),'[]'::jsonb)
)
FROM scope s;
$function$;
REVOKE ALL ON FUNCTION public.read_overview_active_chart_users_v2(bigint,text,text,text,text,text,integer,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_active_chart_users_v2(bigint,text,text,text,text,text,integer,integer) TO service_role;

CREATE OR REPLACE FUNCTION public.read_overview_active_chart_company_v2(p_snapshot_id bigint, p_kind text, p_key text, p_segment text, p_user_id text, p_company_id text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '30s'
AS $function$
WITH published AS MATERIALIZED (
 SELECT s.id AS snapshot_id,
   (s.payload#>>'{value,active_users,as_of}')::timestamptz AS as_of_at,
   s.source_watermark_at AS watermark,
   date_trunc('week',(s.payload#>>'{value,active_users,as_of}')::timestamptz
    AT TIME ZONE 'Asia/Kolkata')::date AS current_week
 FROM public.product_snapshot_current c
 JOIN public.product_snapshot s ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
   AND c.snapshot_id=p_snapshot_id
 LIMIT 1
),
scope AS (
 SELECT p.*,
   CASE WHEN p_kind='weekly' THEN p_key::date
        ELSE p.current_week-28 END AS from_date,
   CASE WHEN p_kind='weekly' THEN 7 ELSE 28 END AS window_days,
   CASE WHEN p_kind='frequency' THEN p_key::int ELSE null::int END AS frequency_weeks
 FROM published p
 WHERE (p_kind='weekly' AND p_key~'^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        AND (p.current_week-p_key::date) BETWEEN 7 AND 84
        AND (p.current_week-p_key::date)%7=0
        AND p_segment IN ('all','returning','first_observed'))
    OR (p_kind='frequency' AND p_key IN ('1','2','3','4') AND p_segment='all')
),
focus_history AS (
 SELECT min(date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date)
        AS first_week
 FROM metrics_private.events_no_test_v2 e CROSS JOIN scope s
 WHERE e.distinct_id=p_user_id AND e.event_time<s.as_of_at
   AND e.ingested_at<=s.watermark
   AND e.event_name<>'Accounting Sync'
   AND public.is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
   AND EXISTS(SELECT 1 FROM public.client_company c WHERE c.company_id=e.company_id)
),
focus_frequency AS (
 SELECT count(DISTINCT date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date)::int AS weeks
 FROM metrics_private.events_no_test_v2 e CROSS JOIN scope s
 WHERE e.distinct_id=p_user_id
   AND e.event_time >= ((s.current_week-28)::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.event_time < (s.current_week::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.ingested_at<=s.watermark
   AND e.event_name<>'Accounting Sync'
   AND public.is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
   AND EXISTS(SELECT 1 FROM public.client_company c WHERE c.company_id=e.company_id)
),
qualified AS MATERIALIZED (
 SELECT e.distinct_id,e.email,e.event_time,e.event_name,
   (e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS day,
   date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS week_start,
   CASE
     WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill')
       OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill')
       OR e.event_name='Vendor Mismatch Resolved' THEN 'ap'
     WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice')
       OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice')
       OR e.event_name='Invoice Bulk Edited' THEN 'ar'
     ELSE 'transactions'
   END AS module
 FROM metrics_private.events_no_test_v2 e CROSS JOIN scope s
 WHERE e.company_id=p_company_id
   AND EXISTS(SELECT 1 FROM public.client_company cc WHERE cc.company_id=e.company_id)
   AND e.event_time >= (s.from_date::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.event_time < ((s.from_date+s.window_days)::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.ingested_at<=s.watermark
   AND e.distinct_id IS NOT NULL AND e.distinct_id <> ''
   AND e.event_name<>'Accounting Sync'
   AND public.is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
),
authorized AS (
 SELECT 1 AS allow
 FROM qualified q CROSS JOIN scope s
 CROSS JOIN focus_history f CROSS JOIN focus_frequency fw
 WHERE q.distinct_id=p_user_id
   AND CASE WHEN p_kind='weekly' THEN
      CASE p_segment WHEN 'first_observed' THEN f.first_week=s.from_date
                     WHEN 'returning' THEN f.first_week<s.from_date
                     ELSE true END
     ELSE fw.weeks=s.frequency_weeks END
 LIMIT 1
),
company_summary AS (
 SELECT count(*)::int AS core_actions,
    count(DISTINCT distinct_id)::int AS active_users,
    count(DISTINCT day)::int AS active_days,
    min(event_time) AS first_activity_at,
    max(event_time) AS last_activity_at,
    count(*) FILTER(WHERE module='ap')::int AS ap,
    count(*) FILTER(WHERE module='ar')::int AS ar,
    count(*) FILTER(WHERE module='transactions')::int AS transactions
 FROM qualified
),
members AS MATERIALIZED (
 SELECT q.distinct_id AS id,max(nullif(q.email,'')) AS email,
   count(*)::int AS actions,
   count(DISTINCT q.day)::int AS active_days,
   max(q.event_time) AS last_active_at,
   count(*) FILTER(WHERE q.module='ap')::int AS ap,
   count(*) FILTER(WHERE q.module='ar')::int AS ar,
   count(*) FILTER(WHERE q.module='transactions')::int AS transactions
 FROM qualified q GROUP BY q.distinct_id
),
weeks AS MATERIALIZED (
 SELECT week_start,count(*)::int AS actions,
    count(DISTINCT distinct_id)::int AS active_users,
    count(*) FILTER(WHERE module='ap')::int AS ap,
    count(*) FILTER(WHERE module='ar')::int AS ar,
    count(*) FILTER(WHERE module='transactions')::int AS transactions
 FROM qualified GROUP BY week_start
),
milestones AS (
 SELECT min(e.event_time) FILTER(WHERE e.event_name='Company Created') AS created_at,
   min(e.event_time) FILTER(WHERE public.is_successful_integration(e.event_name,e.properties)) AS integration_at,
   min(e.event_time) FILTER(WHERE public.is_qualifying_sync(e.event_name,e.properties)) AS first_sync_at,
   max(e.event_time) FILTER(WHERE public.is_qualifying_sync(e.event_name,e.properties)) AS last_sync_at
 FROM metrics_private.events_no_test_v2 e CROSS JOIN scope s
 WHERE e.company_id=p_company_id AND e.event_time<s.as_of_at
   AND e.ingested_at<=s.watermark
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
)
SELECT jsonb_build_object(
 'snapshot_id',s.snapshot_id,
 'scope',p_kind,
 'as_of',s.as_of_at,
 'source_watermark_at',s.watermark,
 'focus_user_id',p_user_id,
 'company',jsonb_build_object(
    'id',p_company_id,
    'name',coalesce(nullif(d.company_name,''),nullif(cp.company_name,''),p_company_id),
    'is_test',coalesce(d.is_test,false)
 ),
 'window',jsonb_build_object(
    'start',(s.from_date::timestamp AT TIME ZONE 'Asia/Kolkata'),
    'end',((s.from_date+s.window_days)::timestamp AT TIME ZONE 'Asia/Kolkata'),
    'days',s.window_days
 ),
 'stats',jsonb_build_object(
    'core_actions',a.core_actions,
    'active_users',a.active_users,'active_days',a.active_days,
    'first_activity_at',a.first_activity_at,'last_activity_at',a.last_activity_at,
    'modules',jsonb_build_object('ap',a.ap,'ar',a.ar,'transactions',a.transactions)
 ),
 'milestones',jsonb_build_object(
    'company_created_at',coalesce(cp.signed_up_at,m.created_at),
    'integration_at',m.integration_at,
    'first_independent_activity_at',a.first_activity_at,
    'first_qualifying_sync_at',m.first_sync_at,
    'last_qualifying_sync_at',m.last_sync_at
 ),
 'users',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'id',u.id,'email',coalesce(u.email,u.id),
     'actions',u.actions,'active_days',u.active_days,'last_active_at',u.last_active_at,
     'modules',jsonb_build_object('ap',u.ap,'ar',u.ar,'transactions',u.transactions)
   ) ORDER BY u.actions DESC,u.id) FROM members u
 ),'[]'::jsonb),
 'weeks',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'week_start',w.week_start,'actions',w.actions,'active_users',w.active_users,
     'modules',jsonb_build_object('ap',w.ap,'ar',w.ar,'transactions',w.transactions)
   ) ORDER BY w.week_start) FROM weeks w
 ),'[]'::jsonb),
 'recent_events',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'at',q.event_time,'event',q.event_name,'module',q.module,
     'user_id',q.distinct_id,
     'user_email',coalesce(nullif(q.email,''),q.distinct_id)
   ) ORDER BY q.event_time DESC)
   FROM (SELECT * FROM qualified ORDER BY event_time DESC LIMIT 30) q
 ),'[]'::jsonb)
)
FROM scope s CROSS JOIN authorized x CROSS JOIN company_summary a
LEFT JOIN public.company_directory d ON d.company_uuid::text=p_company_id
LEFT JOIN public.company_profile cp ON cp.company_id=p_company_id
CROSS JOIN milestones m;
$function$;
REVOKE ALL ON FUNCTION public.read_overview_active_chart_company_v2(bigint,text,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_active_chart_company_v2(bigint,text,text,text,text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.read_overview_adoption_companies_v2(p_snapshot_id bigint, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH published AS MATERIALIZED (
 SELECT s.id AS snapshot_id,
 (s.payload#>>'{value,active_users,as_of}')::timestamptz AS as_of_at,
 s.source_watermark_at
 FROM public.product_snapshot_current c JOIN public.product_snapshot s
 ON s.id=c.snapshot_id
 WHERE c.kind='overview' AND c.scope_key='' AND c.snapshot_id=p_snapshot_id
 AND s.source_status='ok'
 LIMIT 1
),
facts AS MATERIALIZED (
 SELECT f.* FROM published p CROSS JOIN LATERAL
 public.overview_adoption_company_facts_v2(p.snapshot_id) f
),
selection AS MATERIALIZED (
 SELECT f.*
 FROM facts f
 WHERE CASE p_segment
  WHEN 'all' THEN true
  WHEN 'core_7d' THEN f.first_core_7d_at IS NOT NULL
  WHEN 'not_core_7d' THEN f.first_core_7d_at IS NULL
  WHEN 'value_28d' THEN f.value_at IS NOT NULL
  WHEN 'not_value_28d' THEN f.value_at IS NULL
  WHEN 'sustained_28d' THEN f.active_weeks>=2
  WHEN 'not_sustained_28d' THEN f.active_weeks<2
  WHEN 'qualifying_sync' THEN f.first_sync_after_core_at IS NOT NULL
  WHEN 'stalled_after_integration' THEN f.first_core_7d_at IS NULL
  WHEN 'stalled_before_sync' THEN f.first_core_7d_at IS NOT NULL AND
     f.first_sync_after_core_at IS NULL
  WHEN 'module_ap' THEN f.first_core_7d_at IS NOT NULL AND f.ap_actions>0
  WHEN 'module_ar' THEN f.first_core_7d_at IS NOT NULL AND f.ar_actions>0
  WHEN 'module_transactions' THEN f.first_core_7d_at IS NOT NULL AND f.transaction_actions>0
  ELSE f.first_core_7d_at IS NOT NULL AND
    p_segment IN (
     'bill_upload','bill_entity','vendor_mismatch',
     'invoice_upload','invoice_entity','invoice_bulk',
     'statement_upload','transaction_ledger',
     'transaction_status','transaction_type'
    ) AND f.step_flags->>p_segment='true'
 END
),
matched AS MATERIALIZED (
 SELECT f.* FROM selection f
 WHERE btrim(coalesce(p_query,''))=''
 OR f.company_name ILIKE '%'||left(btrim(p_query),70)||'%'
 OR f.integration_type ILIKE '%'||left(btrim(p_query),70)||'%'
),
paged AS (
 SELECT f.* FROM matched f
 ORDER BY f.integrated_at DESC,f.company_id
 LIMIT greatest(1,least(coalesce(p_page_size,8),25))
 OFFSET (greatest(coalesce(p_page,1),1)-1)*greatest(1,least(coalesce(p_page_size,8),25))
)
SELECT jsonb_build_object(
 'contract','mature_independent_adoption_companies_v1',
 'snapshot_id',p.snapshot_id,
 'as_of',p.as_of_at,
 'source_watermark_at',p.source_watermark_at,
 'segment',p_segment,
 'segment_total',(SELECT count(*) FROM selection),
 'total',(SELECT count(*) FROM matched),
 'page',greatest(coalesce(p_page,1),1),
 'page_size',greatest(1,least(coalesce(p_page_size,8),25)),
 'rows',coalesce((
 SELECT jsonb_agg(jsonb_build_object(
  'id',f.company_id,
  'name',f.company_name,
  'integration_type',f.integration_type,
  'is_test',f.is_test,
  'integration_at',f.integrated_at,
  'first_core_7d_at',f.first_core_7d_at,
  'first_core_28d_at',f.first_core_28d_at,
  'sync_after_core_at',f.first_sync_after_core_at,
  'value_at',f.value_at,
  'active_weeks',f.active_weeks,
  'core_actions',f.core_actions,
  'last_core_at',f.last_core_at,
  'modules',jsonb_build_object('ap',f.ap_actions,'ar',f.ar_actions,
                                'transactions',f.transaction_actions),
  'users',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'id',u.id,'email',u.email,'core_actions',u.core_actions,
     'last_core_at',u.last_core_at,
     'modules',jsonb_build_object('ap',u.ap,'ar',u.ar,'transactions',u.txn)
   ) ORDER BY u.core_actions DESC,u.id)
   FROM (
    SELECT e.distinct_id AS id,coalesce(max(nullif(e.email,'')),e.distinct_id) AS email,
     count(*)::integer AS core_actions,
     max(e.event_time) AS last_core_at,
     count(*) FILTER(WHERE
      (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill')
      OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill')
      OR e.event_name='Vendor Mismatch Resolved')::integer AS ap,
     count(*) FILTER(WHERE
      (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice')
      OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice')
      OR e.event_name='Invoice Bulk Edited')::integer AS ar,
     count(*) FILTER(WHERE NOT (
      (e.event_name='Upload' AND lower(btrim(e.properties->>'type')) IN ('bill','invoice'))
      OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType')) IN ('bill','invoice'))
      OR e.event_name IN ('Vendor Mismatch Resolved','Invoice Bulk Edited')
     ))::integer AS txn
    FROM metrics_private.events_no_test_v2 e
    WHERE e.company_id=f.company_id
      AND e.event_time>=f.integrated_at
      AND e.event_time<f.integrated_at+interval '28 days'
      AND e.event_time<p.as_of_at
      AND e.ingested_at<=p.source_watermark_at
      AND e.distinct_id IS NOT NULL AND e.distinct_id<>''
      AND e.event_name<>'Accounting Sync'
      AND public.is_core_activity(e.event_name,e.properties)
      AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
      AND NOT metrics_private.is_retention_internal_email_v2(e.email)
    GROUP BY e.distinct_id
   ) u
  ),'[]'::jsonb)
 ) ORDER BY f.integrated_at DESC,f.company_id)
 FROM paged f
 ),'[]'::jsonb)
)
FROM published p;
$function$;
REVOKE ALL ON FUNCTION public.read_overview_adoption_companies_v2(bigint,text,text,integer,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_adoption_companies_v2(bigint,text,text,integer,integer) TO service_role;

CREATE OR REPLACE FUNCTION public.read_overview_adoption_company_v2(p_snapshot_id bigint, p_company_id text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '35s'
AS $function$
WITH published AS MATERIALIZED (
 SELECT s.id,
 (s.payload#>>'{value,active_users,as_of}')::timestamptz AS as_of_at,
 s.source_watermark_at
 FROM public.product_snapshot_current c JOIN public.product_snapshot s
 ON s.id=c.snapshot_id WHERE c.kind='overview' AND c.scope_key=''
 AND c.snapshot_id=p_snapshot_id AND s.source_status='ok' LIMIT 1
),
fact AS MATERIALIZED (
 SELECT f.* FROM published p CROSS JOIN LATERAL
 public.overview_adoption_company_facts_v2(p.id) f
 WHERE f.company_id=p_company_id
),
qualified AS MATERIALIZED (
 SELECT e.event_time,e.distinct_id,
 coalesce(nullif(e.email,''),e.distinct_id) AS email,
 e.event_name,e.properties,
 floor(extract(epoch FROM (e.event_time-f.integrated_at))/604800)::int AS week_index,
 (e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS day,
 public.is_qualifying_sync(e.event_name,e.properties) AS is_sync,
 (e.event_name<>'Accounting Sync' AND public.is_core_activity(e.event_name,e.properties)) AS is_work,
 CASE
  WHEN e.event_name='Accounting Sync' THEN 'sync'
  WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill')
   OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill')
   OR e.event_name='Vendor Mismatch Resolved' THEN 'ap'
  WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice')
   OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice')
   OR e.event_name='Invoice Bulk Edited' THEN 'ar'
  ELSE 'transactions'
 END AS module
 FROM fact f JOIN metrics_private.events_no_test_v2 e ON e.company_id=f.company_id
 CROSS JOIN published p
 WHERE e.event_time>=f.integrated_at
 AND e.event_time<f.integrated_at+interval '28 days'
 AND e.event_time<p.as_of_at AND e.ingested_at<=p.source_watermark_at
 AND e.distinct_id IS NOT NULL AND e.distinct_id<>''
 AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
 AND NOT metrics_private.is_retention_internal_email_v2(e.email)
 AND (public.is_qualifying_sync(e.event_name,e.properties)
 OR (e.event_name<>'Accounting Sync' AND public.is_core_activity(e.event_name,e.properties)))
),
users AS (
 SELECT q.distinct_id AS id,max(q.email) AS email,
 count(*) FILTER(WHERE q.is_work)::int AS core_actions,
 count(*) FILTER(WHERE q.is_sync)::int AS sync_events,
 count(DISTINCT q.day) FILTER(WHERE q.is_work)::int AS core_days,
 min(q.event_time) FILTER(WHERE q.is_work) AS first_core_at,
 max(q.event_time) FILTER(WHERE q.is_work) AS last_core_at,
 count(*) FILTER(WHERE q.module='ap' AND q.is_work)::int AS ap,
 count(*) FILTER(WHERE q.module='ar' AND q.is_work)::int AS ar,
 count(*) FILTER(WHERE q.module='transactions' AND q.is_work)::int AS txn
 FROM qualified q GROUP BY q.distinct_id
),
weeks AS (
 SELECT g.i AS relative_week,
  count(q.event_time) FILTER(WHERE q.is_work)::int AS core_actions,
  count(DISTINCT q.distinct_id) FILTER(WHERE q.is_work)::int AS active_users,
  count(*) FILTER(WHERE q.is_work AND q.module='ap')::int AS ap,
  count(*) FILTER(WHERE q.is_work AND q.module='ar')::int AS ar,
  count(*) FILTER(WHERE q.is_work AND q.module='transactions')::int AS txn,
  count(*) FILTER(WHERE q.is_sync)::int AS sync_events
 FROM generate_series(0,3) g(i)
 LEFT JOIN qualified q ON q.week_index=g.i
 GROUP BY g.i
)
SELECT jsonb_build_object(
 'contract','mature_independent_adoption_company_v1',
 'snapshot_id',p.id,
 'as_of',p.as_of_at,
 'source_watermark_at',p.source_watermark_at,
 'company',jsonb_build_object(
   'id',f.company_id,'name',f.company_name,
   'integration_type',f.integration_type,'is_test',f.is_test
 ),
 'window',jsonb_build_object(
   'start',f.integrated_at,'end',f.integrated_at+interval '28 days','days',28
 ),
 'outcomes',jsonb_build_object(
   'core_7d',f.first_core_7d_at IS NOT NULL,
   'value_28d',f.value_at IS NOT NULL,
   'sustained_28d',f.active_weeks>=2,
   'sync_after_core',f.first_sync_after_core_at IS NOT NULL
 ),
 'stats',jsonb_build_object(
   'core_actions',f.core_actions,'sync_events',f.sync_events,
   'active_weeks',f.active_weeks,
   'active_users',(SELECT count(*) FROM users WHERE core_actions>0),
   'last_core_at',f.last_core_at,
   'modules',jsonb_build_object('ap',f.ap_actions,'ar',f.ar_actions,
                                'transactions',f.transaction_actions)
 ),
 'milestones',jsonb_build_object(
   'integration_at',f.integrated_at,
   'first_core_7d_at',f.first_core_7d_at,
   'first_core_28d_at',f.first_core_28d_at,
   'training_sync_at',f.training_sync_at,
   'post_training_core_at',f.post_training_core_at,
   'sync_after_core_at',f.first_sync_after_core_at,
   'value_at',f.value_at
 ),
 'users',coalesce((
  SELECT jsonb_agg(jsonb_build_object(
    'id',u.id,'email',u.email,
    'core_actions',u.core_actions,'sync_events',u.sync_events,
    'core_days',u.core_days,'first_core_at',u.first_core_at,
    'last_core_at',u.last_core_at,
    'modules',jsonb_build_object('ap',u.ap,'ar',u.ar,'transactions',u.txn)
  ) ORDER BY u.core_actions DESC,u.id)
  FROM users u
 ),'[]'::jsonb),
 'weeks',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'week',w.relative_week+1,
     'start',f.integrated_at+w.relative_week*interval '7 days',
     'core_actions',w.core_actions,'active_users',w.active_users,
     'sync_events',w.sync_events,
     'modules',jsonb_build_object('ap',w.ap,'ar',w.ar,'transactions',w.txn)
   ) ORDER BY w.relative_week) FROM weeks w
 ),'[]'::jsonb),
 'recent_events',coalesce((
   SELECT jsonb_agg(jsonb_build_object(
     'at',e.event_time,'event',e.event_name,'module',e.module,
     'email',e.email,'user_id',e.distinct_id
   ) ORDER BY e.event_time DESC)
   FROM (SELECT * FROM qualified ORDER BY event_time DESC LIMIT 30) e
 ),'[]'::jsonb)
)
FROM published p JOIN fact f ON true;
$function$;
REVOKE ALL ON FUNCTION public.read_overview_adoption_company_v2(bigint,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_adoption_company_v2(bigint,text) TO service_role;

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
$function$;
REVOKE ALL ON FUNCTION public.read_overview_workflow_module_users_v2(bigint,text,text,text,integer,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_workflow_module_users_v2(bigint,text,text,text,integer,integer) TO service_role;

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
$function$;
REVOKE ALL ON FUNCTION public.read_overview_workflow_mix_companies_v2(bigint,text,text,text,integer,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_workflow_mix_companies_v2(bigint,text,text,text,integer,integer) TO service_role;

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
$function$;
REVOKE ALL ON FUNCTION public.read_overview_workflow_company_v2(bigint,text,text,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_workflow_company_v2(bigint,text,text,text,text,text,text) TO service_role;

CREATE OR REPLACE FUNCTION public.read_overview_friction_companies_v2(p_snapshot_id bigint, p_issue_key text, p_period text DEFAULT 'current'::text, p_segment text DEFAULT 'affected'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
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
 SELECT p.* FROM p WHERE p_issue_key IN(
  'review_reverted','bill_upload','type_update','invoice_upload','ledger_update')
 AND p_period IN ('current','previous')
 AND p_segment IN ('eligible','affected','later_success','needs_review')
),
facts AS MATERIALIZED(
 SELECT f.* FROM scope s CROSS JOIN LATERAL
  public.overview_friction_company_facts_v2(s.id) f
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
 public.overview_friction_events_v2(s.id) e
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
REVOKE ALL ON FUNCTION public.read_overview_friction_companies_v2(bigint,text,text,text,text,integer,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_friction_companies_v2(bigint,text,text,text,text,integer,integer) TO service_role;

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
$function$;
REVOKE ALL ON FUNCTION public.read_overview_friction_company_v2(bigint,text,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_friction_company_v2(bigint,text,text,text,text) TO service_role;
