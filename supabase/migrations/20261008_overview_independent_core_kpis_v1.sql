-- Human-work product usage metrics.
-- Read-only, snapshot-anchored RPC for the native Product Overview KPI strip.
-- It does not replace existing published overview generations or modify event data.
CREATE OR REPLACE FUNCTION public.read_overview_independent_core_kpis_v1()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
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
$function$;

-- This server-only aggregate must not be callable using public browser keys.
REVOKE ALL ON FUNCTION public.read_overview_independent_core_kpis_v1()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_independent_core_kpis_v1()
  TO service_role;
