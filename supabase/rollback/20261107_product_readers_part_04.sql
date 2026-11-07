-- Exact original public Product read RPCs, part 4/12, backed up 2026-11-07.
-- Rollback only. Original data and function grants remain in place.
-- Apply this together with all other Product rollback parts if a cutover must be reversed.
SET LOCAL lock_timeout='7s';

CREATE OR REPLACE FUNCTION public.read_overview_active_charts_v1()
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
 FROM public.events e CROSS JOIN published p
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
$function$
;

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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_active_charts_v3(p_snapshot_id bigint DEFAULT NULL::bigint)
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
 FROM public.product_snapshot s
 WHERE s.kind='overview'
 AND s.id=coalesce(p_snapshot_id,(SELECT c2.snapshot_id FROM public.product_snapshot_current c2 WHERE c2.kind='overview' AND c2.scope_key='' LIMIT 1)) AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD')) AND s.source_status='ok'
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_active_charts_v4(p_snapshot_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
AS $function$
 SELECT metrics_private.read_overview_chart_summary_cached_v1(p_snapshot_id, 'active');
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_adoption_companies_v1(p_snapshot_id bigint, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
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
 public.overview_adoption_company_facts_v1(p.snapshot_id) f
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
    FROM public.events e
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
$function$
;

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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_adoption_companies_v3(p_snapshot_id bigint, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
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
 FROM public.product_snapshot s
 WHERE s.kind='overview' AND (s.scope_key='' OR s.scope_key='asof='||to_char((s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date,'YYYY-MM-DD')) AND s.id=p_snapshot_id
 AND s.source_status='ok'
 LIMIT 1
),
facts AS MATERIALIZED (
 SELECT f.* FROM published p CROSS JOIN LATERAL
 public.overview_adoption_company_facts_v3(p.snapshot_id) f
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_overview_adoption_company_v1(p_snapshot_id bigint, p_company_id text)
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
 public.overview_adoption_company_facts_v1(p.id) f
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
 FROM fact f JOIN public.events e ON e.company_id=f.company_id
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
$function$
;
