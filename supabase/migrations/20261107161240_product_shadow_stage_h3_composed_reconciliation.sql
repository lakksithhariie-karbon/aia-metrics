-- Product H3: private wrapper to reconcile sealed generations before hot data.
-- Does not schedule any job and does not route production readers or writers.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='90s';
CREATE OR REPLACE FUNCTION "01_product_schema".sync_legacy_product_shadow_v1(p_full boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
SET statement_timeout TO '300s'
AS $fn$
DECLARE snapshots jsonb; hot jsonb;
BEGIN
 snapshots:="01_product_schema".reconcile_sealed_product_shadow_v1();
 IF snapshots->>'status' IS DISTINCT FROM 'ok' THEN
   RETURN jsonb_build_object('status','skipped','stage','snapshots','details',snapshots);
 END IF;
 hot:="01_product_schema".reconcile_hot_product_shadow_v1(p_full);
 IF hot->>'status' IS DISTINCT FROM 'ok' THEN
   RETURN jsonb_build_object('status','skipped','stage','hot','details',hot);
 END IF;
 RETURN jsonb_build_object('status','ok','snapshots',snapshots,'hot',hot);
END $fn$;
REVOKE ALL ON FUNCTION "01_product_schema".sync_legacy_product_shadow_v1(boolean)
 FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher;
