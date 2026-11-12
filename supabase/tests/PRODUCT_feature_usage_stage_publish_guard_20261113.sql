-- Isolated, rollback-only integration test for candidate + guarded Overview publication.
-- An incomplete five-kind page MUST NOT publish. Legacy must stay untouched.
BEGIN;
SET LOCAL statement_timeout='170s';
DO $$
DECLARE v_stage jsonb; v_pub jsonb; v_legacy_current bigint; v_private_current bigint;
v_legacy_events bigint;
BEGIN
 SELECT count(*) INTO v_legacy_current FROM public.product_snapshot_current;
 SELECT count(*) INTO v_private_current FROM "01_product_schema".product_publication_current;
 SELECT count(*) INTO v_legacy_events FROM public.events;
 v_stage:="01_product_schema".stage_feature_usage_generation_v1(now());
 IF v_stage->>'status'<>'staged_only' OR (v_stage->>'members')::int<1
   OR (v_stage->>'headers')::int<>156
 THEN RAISE EXCEPTION 'feature usage staging did not produce a sealed complete generation'; END IF;
 v_pub:="01_product_schema".try_publish_verified_overview_v1();
 IF v_pub->>'status'<>'blocked'
    OR v_pub->>'reason'<>'missing_complete_verified_five_kind_generation'
 THEN RAISE EXCEPTION 'publisher unexpectedly published a partial page: %',v_pub; END IF;
 IF v_legacy_current <> (SELECT count(*) FROM public.product_snapshot_current)
 OR v_legacy_events<>(SELECT count(*) FROM public.events)
 OR v_private_current <> (SELECT count(*) FROM "01_product_schema".product_publication_current)
 THEN RAISE EXCEPTION 'publication guard affected legacy or active publication'; END IF;
 IF has_function_privilege('anon',
 '"01_product_schema".try_publish_verified_overview_v1()','EXECUTE')
 OR has_function_privilege('authenticated',
 '"01_product_schema".try_publish_verified_overview_v1()','EXECUTE')
 THEN RAISE EXCEPTION 'private publisher leaked EXECUTE'; END IF;
END $$;
ROLLBACK;
