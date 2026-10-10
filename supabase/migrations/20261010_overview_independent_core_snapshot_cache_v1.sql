-- Read-through shadow cache for the independently-audited Overview WAU / MAU.
-- Additive only: existing v3 reader, event classification, and snapshot jobs unchanged.
-- Historical snapshot rows may be UPDATED in place; watermark + as-of are part of
-- the cache identity. Stale rows are never served.

CREATE TABLE IF NOT EXISTS metrics_private.overview_independent_core_kpi_cache_v1 (
  snapshot_id bigint PRIMARY KEY REFERENCES public.product_snapshot(id) ON DELETE CASCADE,
  source_watermark_at timestamptz NOT NULL,
  as_of_at timestamptz NOT NULL,
  kpis jsonb NOT NULL CHECK (jsonb_typeof(kpis) = 'object'),
  computed_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
REVOKE ALL ON metrics_private.overview_independent_core_kpi_cache_v1
  FROM PUBLIC, anon, authenticated;

-- Only a matching, verified generation is read. Any missing or stale cache
-- entry uses the existing, unchanged source-of-truth v3 calculation.
CREATE OR REPLACE FUNCTION public.read_overview_independent_core_kpis_v4(
  p_snapshot_id bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'metrics_private', 'pg_temp'
SET statement_timeout TO '30s'
AS $fn$
DECLARE
  v_snapshot_id bigint;
  v_source_watermark_at timestamptz;
  v_as_of_at timestamptz;
  v_cached jsonb;
BEGIN
  SELECT
    s.id,
    s.source_watermark_at,
    (s.payload #>> '{value,active_users,as_of}')::timestamptz
  INTO v_snapshot_id, v_source_watermark_at, v_as_of_at
  FROM public.product_snapshot s
  WHERE s.kind = 'overview'
    AND s.id = COALESCE(
      p_snapshot_id,
      (SELECT c.snapshot_id
       FROM public.product_snapshot_current c
       WHERE c.kind = 'overview' AND c.scope_key = '' LIMIT 1)
    )
    AND (
      s.scope_key = ''
      OR s.scope_key = 'asof=' || to_char(
        (s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date, 'YYYY-MM-DD'
      )
    )
    AND s.source_status = 'ok'
  LIMIT 1;

  IF v_snapshot_id IS NULL THEN RETURN NULL; END IF;

  SELECT c.kpis INTO v_cached
  FROM metrics_private.overview_independent_core_kpi_cache_v1 c
  WHERE c.snapshot_id = v_snapshot_id
    AND c.source_watermark_at IS NOT DISTINCT FROM v_source_watermark_at
    AND c.as_of_at IS NOT DISTINCT FROM v_as_of_at
    AND c.kpis ->> 'contract' = 'independent_core_v1'
    AND c.kpis ->> 'snapshot_id' = v_snapshot_id::text
    AND (c.kpis ->> 'as_of')::timestamptz = v_as_of_at
    AND (c.kpis ->> 'source_watermark_at')::timestamptz = v_source_watermark_at;

  IF v_cached IS NOT NULL THEN RETURN v_cached; END IF;

  RETURN public.read_overview_independent_core_kpis_v3(v_snapshot_id);
END;
$fn$;

REVOKE ALL ON FUNCTION public.read_overview_independent_core_kpis_v4(bigint)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_independent_core_kpis_v4(bigint)
  TO service_role;

-- Warm only active and supported historical Overview generations. Unlike the
-- reader, this is explicitly a maintenance write and should run out of band.
CREATE OR REPLACE FUNCTION metrics_private.refresh_overview_independent_core_kpi_cache_v1(
  p_limit integer DEFAULT 20
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'public', 'metrics_private', 'pg_temp'
SET statement_timeout TO '100s'
AS $fn$
DECLARE
  r record;
  v_payload jsonb;
  v_built integer := 0;
  v_ids jsonb := '[]'::jsonb;
BEGIN
  IF NOT pg_try_advisory_xact_lock(7242851, 20261010) THEN
    RETURN jsonb_build_object('status', 'busy', 'built', 0);
  END IF;

  FOR r IN
    SELECT s.id, s.source_watermark_at AS watermark,
      (s.payload #>> '{value,active_users,as_of}')::timestamptz AS as_of_at
    FROM public.product_snapshot s
    WHERE s.kind = 'overview'
      AND s.source_status = 'ok'
      AND s.source_watermark_at IS NOT NULL
      AND (s.payload #>> '{value,active_users,as_of}') IS NOT NULL
      AND (
        (s.scope_key = '' AND s.id = (
          SELECT c.snapshot_id FROM public.product_snapshot_current c
          WHERE c.kind = 'overview' AND c.scope_key = '' LIMIT 1
        ))
        OR (
          s.scope_key LIKE 'asof=%'
          AND s.scope_key >= 'asof=2026-03-31'
          AND s.scope_key = 'asof=' || to_char(
            (s.as_of_at AT TIME ZONE 'Asia/Kolkata')::date, 'YYYY-MM-DD'
          )
        )
      )
      AND NOT EXISTS (
        SELECT 1 FROM metrics_private.overview_independent_core_kpi_cache_v1 c
        WHERE c.snapshot_id = s.id
          AND c.source_watermark_at = s.source_watermark_at
          AND c.as_of_at = (s.payload #>> '{value,active_users,as_of}')::timestamptz
      )
    ORDER BY CASE WHEN s.scope_key = '' THEN 0 ELSE 1 END, s.id DESC
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50)
  LOOP
    v_payload := public.read_overview_independent_core_kpis_v3(r.id);
    IF v_payload IS NULL
       OR v_payload ->> 'contract' IS DISTINCT FROM 'independent_core_v1'
       OR v_payload ->> 'snapshot_id' IS DISTINCT FROM r.id::text
       OR (v_payload ->> 'as_of')::timestamptz IS DISTINCT FROM r.as_of_at
       OR (v_payload ->> 'source_watermark_at')::timestamptz IS DISTINCT FROM r.watermark
    THEN
      RAISE EXCEPTION 'Independent KPI payload failed generation validation for snapshot %', r.id;
    END IF;

    INSERT INTO metrics_private.overview_independent_core_kpi_cache_v1 (
      snapshot_id, source_watermark_at, as_of_at, kpis, computed_at
    ) VALUES (
      r.id, r.watermark, r.as_of_at, v_payload, clock_timestamp()
    )
    ON CONFLICT (snapshot_id) DO UPDATE SET
      source_watermark_at = EXCLUDED.source_watermark_at,
      as_of_at = EXCLUDED.as_of_at,
      kpis = EXCLUDED.kpis,
      computed_at = EXCLUDED.computed_at;

    v_built := v_built + 1;
    v_ids := v_ids || to_jsonb(r.id);
  END LOOP;

  RETURN jsonb_build_object('status', 'ok', 'built', v_built, 'snapshot_ids', v_ids);
END;
$fn$;

REVOKE ALL ON FUNCTION metrics_private.refresh_overview_independent_core_kpi_cache_v1(integer)
  FROM PUBLIC, anon, authenticated;
