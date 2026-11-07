-- Product H4: safe, independent shadow-only reconciliation schedule.
-- Do NOT change production job IDs/commands; this job reads original data and writes private shadows.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='60s';
DO $schedule$
DECLARE id bigint;
BEGIN
 IF EXISTS (SELECT 1 FROM cron.job WHERE jobname='product-shadow-reconcile-2838') THEN
   RAISE EXCEPTION 'Product shadow reconciliation job already exists';END IF;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
     WHERE ns.nspname='01_product_schema' AND p.proname IN
      ('reconcile_sealed_product_shadow_v1','reconcile_hot_product_shadow_v1',
       'sync_legacy_product_shadow_v1'))<>3
 THEN RAISE EXCEPTION 'Required guarded shadow sync functions are missing';END IF;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
      WHERE ns.nspname='01_product_schema' AND c.relkind='r' AND c.relrowsecurity)<>58
 THEN RAISE EXCEPTION 'Product schema privacy check failed';END IF;
 SELECT cron.schedule(
   'product-shadow-reconcile-2838',
   '28,58 * * * *',
   'SELECT "01_product_schema".sync_legacy_product_shadow_v1(false);'
 ) INTO id;
 IF id IS NULL OR NOT EXISTS (
    SELECT 1 FROM cron.job WHERE jobid=id
      AND jobname='product-shadow-reconcile-2838'
      AND schedule='28,58 * * * *' AND active=true
      AND command='SELECT "01_product_schema".sync_legacy_product_shadow_v1(false);')
 THEN RAISE EXCEPTION 'Shadow reconciliation cron not verified';END IF;
END $schedule$;
