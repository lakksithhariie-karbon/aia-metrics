-- Product migration remains in strict mirror mode.
-- FAIL CLOSED: do not stage a persistent shadow-only candidate and break
-- the mirrored 58-table exact parity. No production pointers may change.
BEGIN;
SET LOCAL statement_timeout='60s';
DO $do$
DECLARE v_err text; v_publisher jsonb; v_old_count bigint; v_new_count bigint;
 v_legacy_current bigint; v_shadow_publication bigint;
BEGIN
 IF (SELECT count(*) FROM cron.job WHERE jobid IN(47,48) AND active)<>2 THEN
   RAISE EXCEPTION 'This guard test requires strict shadow mirror jobs active';
 END IF;
 SELECT count(*) INTO v_old_count FROM public.events;
 SELECT count(*) INTO v_new_count FROM "01_product_schema".events;
 SELECT count(*) INTO v_legacy_current FROM public.product_snapshot_current;
 SELECT count(*) INTO v_shadow_publication FROM "01_product_schema".product_publication_current;
 BEGIN
   PERFORM "01_product_schema".stage_feature_usage_generation_v1(now());
   RAISE EXCEPTION 'persistent stage unexpectedly succeeded while mirror active';
 EXCEPTION WHEN OTHERS THEN
   GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
   IF v_err<>'feature_usage_stage_blocked_while_strict_shadow_mirror_active' THEN
     RAISE EXCEPTION 'stage blocked for wrong reason: %',v_err;
   END IF;
 END;
 v_publisher:="01_product_schema".try_publish_verified_overview_v1();
 IF v_publisher->>'status'<>'blocked'
 OR v_publisher->>'reason'<>'missing_complete_verified_five_kind_generation' THEN
   RAISE EXCEPTION 'incomplete page unexpectedly published: %',v_publisher;
 END IF;
 IF v_old_count<>(SELECT count(*) FROM public.events)
 OR v_new_count<>(SELECT count(*) FROM "01_product_schema".events)
 OR v_legacy_current<>(SELECT count(*) FROM public.product_snapshot_current)
 OR v_shadow_publication<>(SELECT count(*) FROM "01_product_schema".product_publication_current)
 THEN RAISE EXCEPTION 'guard test changed a source count or publication pointer'; END IF;
END;
$do$;
ROLLBACK;
