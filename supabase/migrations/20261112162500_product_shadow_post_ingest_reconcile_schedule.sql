-- Reduce post-ingestion shadow lag without switching production writers/readers.
-- Legacy incremental writer #7 runs at minute 05; source mirror previously waited
-- until minute 28. Add minute 12, keeping both existing 28/58 runs.
-- Guard the original job identity/command, and fail on unexpected scheduling changes.
DO $$
DECLARE j cron.job%ROWTYPE;
BEGIN
  SELECT * INTO j FROM cron.job WHERE jobid=47 FOR UPDATE;
  IF NOT FOUND OR j.jobname IS DISTINCT FROM 'product-shadow-reconcile-2838'
    OR NOT j.active
    OR btrim(j.command) IS DISTINCT FROM
       'SELECT "01_product_schema".assert_product_shadow_sync_v1(false);'
    OR j.schedule NOT IN ('28,58 * * * *', '12,28,58 * * * *')
  THEN
    RAISE EXCEPTION 'Refuse to alter unexpected Product shadow reconciliation job #47';
  END IF;

  IF j.schedule = '28,58 * * * *' THEN
    PERFORM cron.alter_job(job_id := 47::bigint, schedule := '12,28,58 * * * *');
  END IF;
END $$;
