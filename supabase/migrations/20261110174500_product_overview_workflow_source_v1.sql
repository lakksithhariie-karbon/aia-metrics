-- Read-only Overview workflow source replay, no publication or pointers.
-- Preserves v3 filtered events with a supplied frozen Product watermark.
CREATE OR REPLACE FUNCTION "01_product_schema".build_overview_workflow_source_v1(
 p_as_of_at timestamptz,p_source_watermark_at timestamptz)
 RETURNS jsonb
 LANGUAGE sql STABLE SECURITY INVOKER
 SET search_path TO 'pg_catalog'
 SET statement_timeout TO '40s'
AS $function$
WITH p AS MATERIALIZED (
 SELECT p_as_of_at AS asof,p_source_watermark_at AS watermark,
   date_trunc('week',p_as_of_at AT TIME ZONE 'Asia/Kolkata')::date AS this_week
 WHERE p_as_of_at IS NOT NULL AND p_source_watermark_at IS NOT NULL
  AND p_as_of_at >= p_source_watermark_at
),
ev AS MATERIALIZED (
 SELECT e.distinct_id,e.company_id,e.event_time,
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
 FROM "01_product_schema".events e CROSS JOIN p
 WHERE e.event_time >= ((p.this_week-84)::timestamp AT TIME ZONE 'Asia/Kolkata')
   AND e.event_time < p.asof AND e.ingested_at<=p.watermark
   AND NULLIF(e.distinct_id,'') IS NOT NULL
   AND NULLIF(e.company_id,'') IS NOT NULL
   AND e.event_name<>'Accounting Sync'
   AND "01_product_schema".is_core_activity(e.event_name,e.properties)
   AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
   AND NOT "01_product_schema".is_retention_internal_email_v2(e.email)
   AND EXISTS(SELECT 1 FROM "01_product_schema".client_company cc WHERE cc.company_id=e.company_id)
   AND NOT EXISTS(SELECT 1 FROM "01_product_schema".company_directory d
       WHERE d.company_uuid::text=e.company_id AND d.is_test)
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
 'contract','overview_workflow_source_v1',
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
REVOKE ALL ON FUNCTION "01_product_schema".build_overview_workflow_source_v1(timestamptz,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".build_overview_workflow_source_v1(timestamptz,timestamptz)
 TO service_role;
