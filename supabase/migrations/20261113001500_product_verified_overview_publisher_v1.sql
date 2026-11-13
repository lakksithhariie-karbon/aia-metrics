-- Fail-closed Overview publication coordinator for the numbered Product schema.
-- Does not construct or fake any missing report. Existing canonical legacy
-- public + metrics_private readers/writers are untouched.
-- Publishes an atomic five-kind manifest ONLY when every candidate is sealed,
-- has populated drill headers and members, carries a full payload contract,
-- and matches the exact live completed ingestion generation.
CREATE OR REPLACE FUNCTION "01_product_schema".try_publish_verified_overview_v1()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog'
SET statement_timeout TO '120s'
AS $fn$
DECLARE
 v_status text; v_wm timestamptz; v_n_events bigint; v_kinds text[]:=
 ARRAY['overview','overview-funnel','overview-feature-usage','overview-module-mix','overview-friction'];
 v_kind text; v_id bigint; v_requested jsonb:='[]'::jsonb; v_missing text[]:='{}'; v_pub bigint;
BEGIN
 SELECT status,last_success_at INTO v_status,v_wm
 FROM "01_product_schema".export_watermarks WHERE job_name='incremental';
 IF v_status IS DISTINCT FROM 'ok' OR v_wm IS NULL
    OR v_wm<now()-interval '24 hours' OR v_wm>now() THEN
   RETURN jsonb_build_object('status','blocked','reason','source_ingestion_not_fresh');
 END IF;
 SELECT count(*) INTO v_n_events FROM "01_product_schema".events;
 FOREACH v_kind IN ARRAY v_kinds LOOP
  -- Source generation, full family-specific payload contract, seal and
  -- member/header coverage are all mandatory. Cannot use an old report with
  -- a replaced timestamp or a partial payload.
  SELECT s.id INTO v_id
  FROM "01_product_schema".product_snapshot s
  WHERE s.kind=v_kind AND s.scope_key='' AND s.source_status='ok'
    AND s.source_watermark_at=v_wm AND s.n_events=v_n_events
    AND s.build_key IS NOT NULL
    AND s.payload->>'schema'='1'
    AND CASE s.kind
      WHEN 'overview' THEN
        jsonb_typeof(s.payload#>'{value,active_users}')='object'
        AND jsonb_typeof(s.payload#>'{value,active_usage_charts}')='object'
        AND jsonb_typeof(s.payload#>'{value,integration_adoption}')='object'
      WHEN 'overview-funnel' THEN
        jsonb_typeof(s.payload#>'{value,root}')='object'
        AND (s.payload#>>'{value,cohort_size}') IS NOT NULL
      WHEN 'overview-feature-usage' THEN
        jsonb_typeof(s.payload#>'{value,weeks}')='array'
        AND jsonb_array_length(s.payload#>'{value,weeks}')=12
      WHEN 'overview-module-mix' THEN
        jsonb_typeof(s.payload#>'{value,buckets}')='array'
        AND jsonb_array_length(s.payload#>'{value,buckets}')=8
      WHEN 'overview-friction' THEN
        jsonb_typeof(s.payload#>'{value,issues}')='array'
        AND jsonb_array_length(s.payload#>'{value,issues}')=5
      ELSE false END
    AND (
      (v_kind='overview-funnel'
       AND EXISTS(SELECT 1 FROM "01_product_schema".product_funnel_seal z WHERE z.snapshot_id=s.id)
       AND (SELECT count(*) FROM "01_product_schema".product_funnel_member m WHERE m.snapshot_id=s.id)>=1
       AND (SELECT count(*) FROM "01_product_schema".product_funnel_drill d WHERE d.snapshot_id=s.id)>=1)
      OR
      (v_kind<>'overview-funnel'
       AND EXISTS(SELECT 1 FROM "01_product_schema".product_overview_seal z WHERE z.snapshot_id=s.id)
       AND (SELECT count(*) FROM "01_product_schema".product_overview_member m WHERE m.snapshot_id=s.id)>=1
       AND (SELECT count(*) FROM "01_product_schema".product_overview_drill d WHERE d.snapshot_id=s.id)>=1)
    )
  ORDER BY s.id DESC LIMIT 1;
  IF v_id IS NULL THEN
    v_missing:=array_append(v_missing,v_kind);
  ELSE
    v_requested:=v_requested||jsonb_build_array(jsonb_build_object(
     'kind',v_kind,'scope_key','','snapshot_id',v_id));
  END IF;
  v_id:=NULL;
 END LOOP;
 IF cardinality(v_missing)>0 THEN
   RETURN jsonb_build_object('status','blocked',
    'reason','missing_complete_verified_five_kind_generation',
    'missing_kinds',to_jsonb(v_missing),'ready_count',jsonb_array_length(v_requested),
    'source_watermark_at',v_wm,'event_count',v_n_events);
 END IF;
 -- Underlying atomic publication function locks, validates all five, and
 -- re-checks the generation immediately before the one-pointer page swap.
 v_pub:="01_product_schema".publish_product_publication('overview',v_wm,v_n_events,v_requested);
 IF (SELECT count(*) FROM "01_product_schema".product_publication_member
      WHERE publication_id=v_pub)<>5
    OR NOT EXISTS(SELECT 1 FROM "01_product_schema".product_publication_current
                  WHERE page='overview' AND publication_id=v_pub) THEN
   RAISE EXCEPTION 'overview publication is incomplete, refusing commit';
 END IF;
 RETURN jsonb_build_object('status','published','publication_id',v_pub,
   'source_watermark_at',v_wm,'event_count',v_n_events,'members',v_requested);
END;
$fn$;
REVOKE ALL ON FUNCTION "01_product_schema".try_publish_verified_overview_v1()
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".try_publish_verified_overview_v1()
 TO service_role;
