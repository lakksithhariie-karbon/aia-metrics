-- Exact original public Product read RPCs, part 5/12, backed up 2026-11-07.
-- Rollback only. Original data and function grants remain in place.
-- Apply this together with all other Product rollback parts if a cutover must be reversed.
SET LOCAL lock_timeout='7s';

CREATE OR REPLACE FUNCTION public.read_overview_adoption_company_v3(p_snapshot_id bigint, p_company_id text)
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
 FROM public.product_snapshot s WHERE s.kind='overview' AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD'))
 AND s.id=p_snapshot_id AND s.source_status='ok' LIMIT 1
),
fact AS MATERIALIZED (
 SELECT f.* FROM published p CROSS JOIN LATERAL
 public.overview_adoption_company_facts_v3(p.id) f
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_adoption_journey_v1()
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
  public.overview_adoption_company_facts_v1(p.id) AS f
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
$function$
;

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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_adoption_journey_v3(p_snapshot_id bigint DEFAULT NULL::bigint)
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
  FROM public.product_snapshot s
  WHERE s.kind='overview'
 AND s.id=coalesce(p_snapshot_id,(SELECT c2.snapshot_id FROM public.product_snapshot_current c2 WHERE c2.kind='overview' AND c2.scope_key='' LIMIT 1)) AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD')) AND s.source_status='ok'
  LIMIT 1
),
facts AS MATERIALIZED (
  SELECT f.* FROM published p CROSS JOIN LATERAL
  public.overview_adoption_company_facts_v3(p.id) AS f
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_adoption_journey_v4(p_snapshot_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
AS $function$
 SELECT metrics_private.read_overview_chart_summary_cached_v1(p_snapshot_id, 'adoption');
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_core_company_v1(p_snapshot_id bigint, p_scope text, p_user_id text, p_company_id text)
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
 FROM public.events e CROSS JOIN published p
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
 FROM public.events e CROSS JOIN published p
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
$function$
;

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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_core_company_v3(p_snapshot_id bigint, p_scope text, p_user_id text, p_company_id text)
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
 FROM public.product_snapshot s
 WHERE s.kind='overview' AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD')) AND s.id=p_snapshot_id
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
$function$
;
