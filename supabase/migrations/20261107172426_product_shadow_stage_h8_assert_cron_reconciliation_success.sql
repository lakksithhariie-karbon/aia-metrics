-- Product H8: make shadow cron success mean actual reconciliation success.
-- Only modifies private shadow cron jobs #47/#48; live Product jobs remain intact.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='60s';
DO $preflight$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobid=47
   AND jobname='product-shadow-reconcile-2838'
   AND schedule='28,58 * * * *' AND active
   AND command='SELECT "01_product_schema".sync_legacy_product_shadow_v1(false);')
 OR NOT EXISTS(SELECT 1 FROM cron.job WHERE jobid=48
   AND jobname='product-shadow-daily-full-0308'
   AND schedule='8 3 * * *' AND active
   AND command='SELECT "01_product_schema".sync_legacy_product_shadow_v1(true);')
 THEN RAISE EXCEPTION 'Shadow job inventory changed, abort';END IF;
END $preflight$;
CREATE OR REPLACE FUNCTION "01_product_schema".assert_product_shadow_sync_v1(p_full boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog,pg_temp
SET statement_timeout TO '300s'
AS $f$
DECLARE result jsonb;
BEGIN
  result:="01_product_schema".sync_legacy_product_shadow_v1(p_full);
  IF result->>'status' IS DISTINCT FROM 'ok'
     OR result#>>'{snapshots,status}' IS DISTINCT FROM 'ok'
     OR result#>>'{hot,status}' IS DISTINCT FROM 'ok'
     OR result#>>'{hot,hot_details,status}' IS DISTINCT FROM 'ok'
     OR (result#>>'{hot,hot_details,hot_tables}')::integer IS DISTINCT FROM 39
  THEN RAISE EXCEPTION 'product_shadow_reconciliation_not_ok: %',result;END IF;
  RETURN result;
END $f$;
REVOKE ALL ON FUNCTION "01_product_schema".assert_product_shadow_sync_v1(boolean)
  FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher;
SELECT cron.alter_job(job_id=>47, command=>'SELECT "01_product_schema".assert_product_shadow_sync_v1(false);');
SELECT cron.alter_job(job_id=>48, command=>'SELECT "01_product_schema".assert_product_shadow_sync_v1(true);');
DO $post$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobid=47
      AND command='SELECT "01_product_schema".assert_product_shadow_sync_v1(false);' AND active)
 OR NOT EXISTS(SELECT 1 FROM cron.job WHERE jobid=48
      AND command='SELECT "01_product_schema".assert_product_shadow_sync_v1(true);' AND active)
 THEN RAISE EXCEPTION 'Shadow cron verification failed';END IF;
END $post$;
