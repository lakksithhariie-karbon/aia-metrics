-- Product H7: daily full event correction catch-up, independent of live ingestion.
-- Normal shadow reconciliation is incremental every 30 minutes.
-- The daily full pass also checks pre-seven-day event property updates.
SET LOCAL lock_timeout='7s'; SET LOCAL statement_timeout='60s';
DO $schedule$
DECLARE id bigint;
BEGIN
 IF EXISTS(SELECT 1 FROM cron.job WHERE jobname='product-shadow-daily-full-0308') THEN
  RAISE EXCEPTION 'Daily shadow correction job already exists';END IF;
 IF (SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
     WHERE ns.nspname='01_product_schema' AND p.proname IN
       ('sync_legacy_product_shadow_v1','reconcile_product_hot_delta_v2',
        'reconcile_hot_product_shadow_v1'))<>3
 THEN RAISE EXCEPTION 'Expected Product shadow reconciliation functions missing';END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
      WHERE ns.nspname='01_product_schema' AND
        p.proname IN ('sync_legacy_product_shadow_v1','reconcile_product_hot_delta_v2',
          'reconcile_hot_product_shadow_v1')
      AND has_function_privilege('anon',p.oid,'EXECUTE'))
 THEN RAISE EXCEPTION 'Unexpected public Product shadow function access';END IF;
 SELECT cron.schedule('product-shadow-daily-full-0308','8 3 * * *',
    'SELECT "01_product_schema".sync_legacy_product_shadow_v1(true);') INTO id;
 IF id IS NULL OR NOT EXISTS(SELECT 1 FROM cron.job WHERE jobid=id
     AND jobname='product-shadow-daily-full-0308' AND schedule='8 3 * * *'
     AND active AND command='SELECT "01_product_schema".sync_legacy_product_shadow_v1(true);')
 THEN RAISE EXCEPTION 'Product daily full reconciliation not scheduled correctly';END IF;
END $schedule$;
