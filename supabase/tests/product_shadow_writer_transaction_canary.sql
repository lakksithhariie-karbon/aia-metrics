-- PRODUCT SHADOW DB BRIDGE CANARY, TRANSACTION-ROLLED BACK.
-- Exercises the isolated shadow ingestion writer using service_role grants.
-- This does NOT invoke the Edge Function, cannot certify its auth path, and
-- does not persist event/watermark/cache changes. Do not confuse with full E2E.
BEGIN;
SET LOCAL ROLE service_role;
DO $test$
DECLARE leased boolean; inserted_count integer;updated_count integer;mismatch_count integer;
        c record; n_snap integer;n_fun integer;n_over integer;
BEGIN
 SELECT public.shadow_product_try_begin_incremental() INTO leased;
 IF leased IS DISTINCT FROM true THEN RAISE EXCEPTION 'Shadow lease unavailable';END IF;
 SELECT u.inserted,u.updated,u.identity_mismatches INTO inserted_count,updated_count,mismatch_count
 FROM public.shadow_product_upsert_mixpanel_events_detail(
  (SELECT jsonb_build_array(to_jsonb(e)) FROM public.events e ORDER BY e.ingested_at DESC LIMIT 1)
 ) u;
 IF inserted_count IS DISTINCT FROM 0 OR updated_count IS DISTINCT FROM 0 OR mismatch_count IS DISTINCT FROM 0
 THEN RAISE EXCEPTION 'Shadow upsert not idempotent %/%/%',inserted_count,updated_count,mismatch_count;END IF;
 SELECT * INTO c FROM public.shadow_product_refresh_retention('"01_product_schema".events');
 IF c.n_client < 3000 OR c.n_activation < 500 OR c.n_cells < 100
 THEN RAISE EXCEPTION 'Shadow refresh unexpected results %',row_to_json(c);END IF;
 PERFORM public.shadow_product_finish_incremental(true,DATE '2026-11-07','shadow_service_role_transaction_canary_rolled_back');
 SELECT public.shadow_product_prune_product_snapshots(1000) INTO n_snap;
 SELECT public.shadow_product_prune_funnel_members(1000) INTO n_fun;
 SELECT public.shadow_product_prune_overview_members(1000) INTO n_over;
 IF n_snap<>0 OR n_fun<>0 OR n_over<>0 THEN
   RAISE EXCEPTION 'Unexpected shadow prune %/%/%',n_snap,n_fun,n_over;END IF;
 RAISE NOTICE 'Shadow DB bridge PASS: %, %, %',c.n_client,c.n_activation,c.n_cells;
END $test$;
ROLLBACK;
