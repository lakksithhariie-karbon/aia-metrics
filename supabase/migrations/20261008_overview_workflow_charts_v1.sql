-- Shared, snapshot-pinned independent accounting-work event contract.
-- This is deliberately aligned with published WAU/MAU eligibility.
CREATE OR REPLACE FUNCTION public.overview_workflow_events_v1(
  p_snapshot_id bigint
)
RETURNS TABLE (
  snapshot_id bigint,
  as_of_at timestamptz,
  source_watermark_at timestamptz,
  current_week date,
  distinct_id text,
  company_id text,
  email text,
  event_company_name text,
  event_time timestamptz,
  activity_day date,
  week_start date,
  module text,
  event_name text
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
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
FROM public.events e CROSS JOIN p
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
REVOKE ALL ON FUNCTION public.overview_workflow_events_v1(bigint)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.overview_workflow_events_v1(bigint)
 TO service_role;

-- Both charts consume the same classified user and company events.
CREATE OR REPLACE FUNCTION public.read_overview_workflow_charts_v1()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
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
 SELECT e.* FROM p CROSS JOIN LATERAL public.overview_workflow_events_v1(p.id) e
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
REVOKE ALL ON FUNCTION public.read_overview_workflow_charts_v1()
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_workflow_charts_v1()
 TO service_role;
