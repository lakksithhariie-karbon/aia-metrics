-- Restore the original job #47 cadence if new cadence causes regressions.
-- Independent of the production reader/writer rollback.
DO $$
DECLARE j cron.job%ROWTYPE;
BEGIN
  SELECT * INTO j FROM cron.job WHERE jobid=47;
  IF NOT FOUND OR j.jobname IS DISTINCT FROM 'product-shadow-reconcile-2838'
    OR btrim(j.command) IS DISTINCT FROM
       'SELECT "01_product_schema".assert_product_shadow_sync_v1(false);'
    OR j.schedule NOT IN ('28,58 * * * *', '12,28,58 * * * *')
  THEN
    RAISE EXCEPTION 'Refuse to alter unexpected Product shadow reconciliation job #47';
  END IF;
  IF j.schedule='12,28,58 * * * *' THEN
    PERFORM cron.alter_job(job_id := 47::bigint, schedule := '28,58 * * * *');
  END IF;
END $$;
