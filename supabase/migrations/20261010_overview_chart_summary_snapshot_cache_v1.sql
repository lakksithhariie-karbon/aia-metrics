-- Four additional Overview chart summaries, using the same frozen snapshot
-- invariants as the audited WAU/MAU cache. No existing RPC is replaced.
-- Drill-downs remain live, source-backed and intentionally uncached here.

CREATE TABLE IF NOT EXISTS metrics_private.overview_chart_summary_cache_v1 (
  snapshot_id bigint NOT NULL REFERENCES public.product_snapshot(id) ON DELETE CASCADE,
  family text NOT NULL CHECK (family IN ('active', 'adoption', 'workflow', 'friction')),
  source_watermark_at timestamptz NOT NULL,
  as_of_at timestamptz NOT NULL,
  payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object'),
  computed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (snapshot_id, family)
);
REVOKE ALL ON metrics_private.overview_chart_summary_cache_v1
  FROM PUBLIC, anon, authenticated;

-- A cache entry is usable only for the exact published generation and metric
-- contract. If absent or stale, read the original authoritative v3 function.
CREATE OR REPLACE FUNCTION metrics_private.read_overview_chart_summary_cached_v1(
  p_snapshot_id bigint, p_family text
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public', 'metrics_private', 'pg_temp'
SET statement_timeout TO '40s'
AS $fn$
DECLARE
  v_snapshot_id bigint;
  v_watermark timestamptz;
  v_as_of timestamptz;
  v_cached jsonb;
  v_contract text;
BEGIN
  v_contract := CASE p_family
    WHEN 'active' THEN 'independent_core_active_charts_v1'
    WHEN 'adoption' THEN 'mature_independent_adoption_v1'
    WHEN 'workflow' THEN 'independent_workflow_v1'
    WHEN 'friction' THEN 'observed_company_friction_v1'
    ELSE NULL END;
  IF v_contract IS NULL THEN RAISE EXCEPTION 'invalid_overview_family'; END IF;

  SELECT s.id, s.source_watermark_at,
    (s.payload #>> '{value,active_users,as_of}')::timestamptz
  INTO v_snapshot_id, v_watermark, v_as_of
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

  SELECT c.payload INTO v_cached
  FROM metrics_private.overview_chart_summary_cache_v1 c
  WHERE c.snapshot_id = v_snapshot_id
    AND c.family = p_family
    AND c.source_watermark_at IS NOT DISTINCT FROM v_watermark
    AND c.as_of_at IS NOT DISTINCT FROM v_as_of
    AND c.payload ->> 'contract' = v_contract
    AND c.payload ->> 'snapshot_id' = v_snapshot_id::text
    AND (c.payload ->> 'source_watermark_at')::timestamptz = v_watermark
    AND (c.payload ->> 'as_of')::timestamptz = v_as_of;
  IF v_cached IS NOT NULL THEN RETURN v_cached; END IF;

  CASE p_family
    WHEN 'active' THEN RETURN public.read_overview_active_charts_v3(v_snapshot_id);
    WHEN 'adoption' THEN RETURN public.read_overview_adoption_journey_v3(v_snapshot_id);
    WHEN 'workflow' THEN RETURN public.read_overview_workflow_charts_v3(v_snapshot_id);
    WHEN 'friction' THEN RETURN public.read_overview_friction_v3(v_snapshot_id);
  END CASE;
  RETURN NULL;
END;
$fn$;
REVOKE ALL ON FUNCTION metrics_private.read_overview_chart_summary_cached_v1(bigint,text)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.read_overview_active_charts_v4(
  p_snapshot_id bigint DEFAULT NULL
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'metrics_private', 'pg_temp'
AS $fn$
 SELECT metrics_private.read_overview_chart_summary_cached_v1(p_snapshot_id, 'active');
$fn$;

CREATE OR REPLACE FUNCTION public.read_overview_adoption_journey_v4(
  p_snapshot_id bigint DEFAULT NULL
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'metrics_private', 'pg_temp'
AS $fn$
 SELECT metrics_private.read_overview_chart_summary_cached_v1(p_snapshot_id, 'adoption');
$fn$;

CREATE OR REPLACE FUNCTION public.read_overview_workflow_charts_v4(
  p_snapshot_id bigint DEFAULT NULL
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'metrics_private', 'pg_temp'
AS $fn$
 SELECT metrics_private.read_overview_chart_summary_cached_v1(p_snapshot_id, 'workflow');
$fn$;

CREATE OR REPLACE FUNCTION public.read_overview_friction_v4(
  p_snapshot_id bigint DEFAULT NULL
) RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO 'public', 'metrics_private', 'pg_temp'
AS $fn$
 SELECT metrics_private.read_overview_chart_summary_cached_v1(p_snapshot_id, 'friction');
$fn$;

REVOKE ALL ON FUNCTION public.read_overview_active_charts_v4(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.read_overview_adoption_journey_v4(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.read_overview_workflow_charts_v4(bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.read_overview_friction_v4(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_active_charts_v4(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_overview_adoption_journey_v4(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_overview_workflow_charts_v4(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_overview_friction_v4(bigint) TO service_role;

-- Bounded, serialized warmer. A cron invocation computes at most four
-- family/snapshot pairs (approximately one generation), avoiding CPU bursts.
CREATE OR REPLACE FUNCTION metrics_private.refresh_overview_chart_summary_cache_v1(
  p_limit integer DEFAULT 4
) RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER
SET search_path TO 'public', 'metrics_private', 'pg_temp'
SET statement_timeout TO '100s'
AS $fn$
DECLARE
  r record;
  v_payload jsonb;
  v_built integer := 0;
  v_keys jsonb := '[]'::jsonb;
BEGIN
  IF NOT pg_try_advisory_xact_lock(7242851, 20261011) THEN
    RETURN jsonb_build_object('status', 'busy', 'built', 0);
  END IF;

  FOR r IN
    SELECT s.id AS snapshot_id, s.scope_key, s.source_watermark_at AS watermark,
      (s.payload #>> '{value,active_users,as_of}')::timestamptz AS as_of_at,
      f.family, f.contract
    FROM public.product_snapshot s
    CROSS JOIN (VALUES
      ('active', 'independent_core_active_charts_v1'),
      ('adoption', 'mature_independent_adoption_v1'),
      ('workflow', 'independent_workflow_v1'),
      ('friction', 'observed_company_friction_v1')
    ) f(family, contract)
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
        SELECT 1 FROM metrics_private.overview_chart_summary_cache_v1 c
        WHERE c.snapshot_id = s.id AND c.family = f.family
          AND c.source_watermark_at = s.source_watermark_at
          AND c.as_of_at = (s.payload #>> '{value,active_users,as_of}')::timestamptz
      )
    ORDER BY CASE WHEN s.scope_key = '' THEN 0 ELSE 1 END,
      s.id DESC, f.family
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 4), 1), 16)
  LOOP
    v_payload := CASE r.family
      WHEN 'active' THEN public.read_overview_active_charts_v3(r.snapshot_id)
      WHEN 'adoption' THEN public.read_overview_adoption_journey_v3(r.snapshot_id)
      WHEN 'workflow' THEN public.read_overview_workflow_charts_v3(r.snapshot_id)
      WHEN 'friction' THEN public.read_overview_friction_v3(r.snapshot_id)
      ELSE NULL END;

    IF v_payload IS NULL
      OR v_payload ->> 'contract' IS DISTINCT FROM r.contract
      OR v_payload ->> 'snapshot_id' IS DISTINCT FROM r.snapshot_id::text
      OR (v_payload ->> 'as_of')::timestamptz IS DISTINCT FROM r.as_of_at
      OR (v_payload ->> 'source_watermark_at')::timestamptz IS DISTINCT FROM r.watermark
    THEN RAISE EXCEPTION 'Chart summary failed validation for snapshot % family %', r.snapshot_id, r.family;
    END IF;

    INSERT INTO metrics_private.overview_chart_summary_cache_v1 (
      snapshot_id, family, source_watermark_at, as_of_at, payload, computed_at
    ) VALUES (
      r.snapshot_id, r.family, r.watermark, r.as_of_at, v_payload, clock_timestamp()
    )
    ON CONFLICT (snapshot_id, family) DO UPDATE SET
      source_watermark_at = EXCLUDED.source_watermark_at,
      as_of_at = EXCLUDED.as_of_at,
      payload = EXCLUDED.payload,
      computed_at = EXCLUDED.computed_at;

    v_built := v_built + 1;
    v_keys := v_keys || jsonb_build_array(jsonb_build_object(
      'snapshot_id', r.snapshot_id, 'family', r.family
    ));
  END LOOP;

  RETURN jsonb_build_object('status', 'ok', 'built', v_built, 'keys', v_keys);
END;
$fn$;

REVOKE ALL ON FUNCTION metrics_private.refresh_overview_chart_summary_cache_v1(integer)
  FROM PUBLIC, anon, authenticated;
