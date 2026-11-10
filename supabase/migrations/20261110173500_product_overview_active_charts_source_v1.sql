-- Read-only deterministic 12-week Overview chart reconstruction.
-- Source is the numbered Product schema at the caller's frozen ingestion cutoff.
-- No snapshot staging, pointer updates, or public API changes.
CREATE OR REPLACE FUNCTION "01_product_schema".build_overview_active_charts_source_v1(
 p_as_of_at timestamptz,p_source_watermark_at timestamptz)
 RETURNS jsonb
 LANGUAGE sql STABLE SECURITY INVOKER
 SET search_path TO 'pg_catalog'
 SET statement_timeout TO '40s'
AS $function$
WITH published AS MATERIALIZED (
 SELECT p_as_of_at AS as_of_at,p_source_watermark_at AS source_watermark_at,
 date_trunc('week',p_as_of_at AT TIME ZONE 'Asia/Kolkata')::date AS current_week
 WHERE p_as_of_at IS NOT NULL AND p_source_watermark_at IS NOT NULL
   AND p_as_of_at >= p_source_watermark_at
),
qualified AS MATERIALIZED (
 SELECT DISTINCT e.distinct_id,
   date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS week_start
 FROM "01_product_schema".events e CROSS JOIN published p
 WHERE e.event_time<p.as_of_at AND e.ingested_at<=p.source_watermark_at
   AND e.distinct_id IS NOT NULL AND e.distinct_id<>''
   AND e.event_name<>'Accounting Sync'
   AND "01_product_schema".is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT "01_product_schema".is_retention_internal_email_v2(e.email)
   AND EXISTS(SELECT 1 FROM "01_product_schema".client_company cc WHERE cc.company_id=e.company_id)
   AND NOT EXISTS (SELECT 1 FROM "01_product_schema".company_directory d WHERE d.company_uuid::text=e.company_id AND d.is_test)
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
 'contract','overview_active_charts_source_v1',
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
REVOKE ALL ON FUNCTION "01_product_schema".build_overview_active_charts_source_v1(timestamptz,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".build_overview_active_charts_source_v1(timestamptz,timestamptz)
 TO service_role;
