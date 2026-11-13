-- Deterministic feature generation fix: use completed source watermark as as_of.
-- Complete Feature Usage candidate builder from frozen raw events.
-- Writes ONLY to 01_product_schema. Never changes any current pointer or page.
-- Every failed/restarted build rolls back atomically.
CREATE OR REPLACE FUNCTION "01_product_schema".stage_feature_usage_generation_v1(
 p_as_of_at timestamptz DEFAULT now()
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'pg_catalog'
SET statement_timeout TO '150s'
AS $fn$
DECLARE
 v_wm timestamptz; v_status text; v_n_events bigint;
 v_payload jsonb; v_members jsonb; v_headers jsonb;
 v_population bigint; v_member_count bigint; v_header_count bigint;
 v_id bigint; v_loaded integer;
BEGIN
 IF p_as_of_at IS NULL OR p_as_of_at>now()+interval '1 minute' THEN
   RAISE EXCEPTION 'feature usage as_of invalid';
 END IF;
 SELECT status,last_success_at INTO v_status,v_wm
 FROM "01_product_schema".export_watermarks WHERE job_name='incremental';
 IF v_status IS DISTINCT FROM 'ok' OR v_wm IS NULL
 OR v_wm < now()-interval '24 hours' OR p_as_of_at < v_wm THEN
   RAISE EXCEPTION 'feature usage source not fresh and complete';
 END IF;
 SELECT count(*) INTO v_n_events FROM "01_product_schema".events;
 SELECT r->'payload' INTO v_payload
 FROM (SELECT "01_product_schema".build_overview_feature_usage_source_v1(
 v_wm,v_wm) AS r) x;
 IF v_payload#>>'{schema}' IS DISTINCT FROM '1'
 OR jsonb_array_length(v_payload#>'{value,weeks}')<>12 THEN
   RAISE EXCEPTION 'feature usage source payload contract invalid';
 END IF;
 SELECT jsonb_agg(jsonb_build_object(
  'kind','overview-feature-usage','drill_key',x.drill_key,'tab',x.tab,
  'member_id',x.member_id,'position',x.sort_position,'card',x.card
 )),count(*) INTO v_members,v_member_count
 FROM "01_product_schema".build_overview_feature_usage_cards_source_v1(
   v_wm,v_wm) x;
 SELECT jsonb_agg(jsonb_build_object(
  'kind','overview-feature-usage','drill_key',h.drill_key,'tab',h.tab,
  'header',h.header
  )),count(*) INTO v_headers,v_header_count
 FROM "01_product_schema".build_overview_feature_usage_headers_v1(
   v_wm,v_wm) h;
 SELECT count(*) INTO v_population
 FROM "01_product_schema".build_overview_feature_usage_population_v1(
   v_wm,v_wm);
 IF v_member_count<1 OR v_member_count<>v_population OR v_header_count<>156 THEN
   RAISE EXCEPTION 'feature usage population/header mismatch (%, %, %)',
    v_member_count,v_population,v_header_count;
 END IF;
 -- Fail closed if any writer has advanced before staging.
 PERFORM 1 FROM "01_product_schema".export_watermarks
 WHERE job_name='incremental' AND status='ok' AND last_success_at=v_wm;
 IF NOT FOUND OR v_n_events <> (SELECT count(*) FROM "01_product_schema".events) THEN
   RAISE EXCEPTION 'feature usage warehouse generation changed before staging';
 END IF;
 v_id := "01_product_schema".stage_product_snapshot_v2(
  'overview-feature-usage','',v_payload,v_wm::text,v_n_events,
  'feature-usage-source-v1|'||v_wm::text||'|'||v_n_events,
  NULL,NULL,v_wm
 );
 v_loaded := "01_product_schema".stage_overview_members(v_id,v_members,v_headers);
 PERFORM "01_product_schema".assert_product_snapshot_publishable(v_id,1);
 IF NOT EXISTS (SELECT 1 FROM "01_product_schema".product_overview_seal
                WHERE snapshot_id=v_id)
 OR v_loaded<>v_member_count+v_header_count
 OR EXISTS (SELECT 1 FROM "01_product_schema".product_snapshot_current
            WHERE snapshot_id=v_id)
 THEN RAISE EXCEPTION 'feature usage candidate not sealed, or unexpectedly active'; END IF;
 RETURN jsonb_build_object('status','staged_only','snapshot_id',v_id,
 'source_watermark_at',v_wm,'event_count',v_n_events,
 'members',v_member_count,'headers',v_header_count);
END;
$fn$;
REVOKE ALL ON FUNCTION "01_product_schema".stage_feature_usage_generation_v1(timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".stage_feature_usage_generation_v1(timestamptz)
 TO service_role;
