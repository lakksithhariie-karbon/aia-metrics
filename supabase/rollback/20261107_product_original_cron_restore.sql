-- Product rollback, exact live original 8 Product cron job schedules/commands.
-- Captured 2026-11-07 before any Product writer or production reader cutover.
-- Use only if restoring legacy production source routing.
SET LOCAL lock_timeout='7s';
DO $rollback$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid=7 AND jobname='sync-incremental-hourly') THEN
    RAISE EXCEPTION 'Expected production Product cron job 7 absent';
  END IF;
  PERFORM cron.alter_job(job_id => 7, schedule => '5 * * * *', command => '
      SELECT net.http_post(
        url := (
          SELECT decrypted_secret
          FROM vault.decrypted_secrets
          WHERE name = ''sync_incremental_function_url''
        ),
        headers := jsonb_build_object(
          ''Content-Type'', ''application/json'',
          ''Authorization'', ''Bearer '' || (
            SELECT decrypted_secret
            FROM vault.decrypted_secrets
            WHERE name = ''sync_incremental_service_role''
          ),
          ''x-cron-secret'', (
            SELECT decrypted_secret
            FROM vault.decrypted_secrets
            WHERE name = ''sync_incremental_cron''
          )
        ),
        body := ''{}''::jsonb,
        timeout_milliseconds := 150000
      );
    ', active => true);

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid=29 AND jobname='companies-monthly-cache-hourly') THEN
    RAISE EXCEPTION 'Expected production Product cron job 29 absent';
  END IF;
  PERFORM cron.alter_job(job_id => 29, schedule => '16 * * * *', command => 'select public.refresh_companies_monthly_cache();', active => true);

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid=39 AND jobname='retention-dashboard-v3-watch') THEN
    RAISE EXCEPTION 'Expected production Product cron job 39 absent';
  END IF;
  PERFORM cron.alter_job(job_id => 39, schedule => '13,43 * * * *', command => 'select public.refresh_retention_dashboard_v3(false);', active => true);

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid=40 AND jobname='companies-monthly-core-v2-hourly') THEN
    RAISE EXCEPTION 'Expected production Product cron job 40 absent';
  END IF;
  PERFORM cron.alter_job(job_id => 40, schedule => '22 * * * *', command => 'SELECT public.refresh_companies_monthly_core_v2();', active => true);

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid=41 AND jobname='retention-independent-core-v5-watch') THEN
    RAISE EXCEPTION 'Expected production Product cron job 41 absent';
  END IF;
  PERFORM cron.alter_job(job_id => 41, schedule => '19,49 * * * *', command => 'SELECT public.refresh_retention_dashboard_v4(false);', active => true);

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid=42 AND jobname='overview-verified-history-daily') THEN
    RAISE EXCEPTION 'Expected production Product cron job 42 absent';
  END IF;
  PERFORM cron.alter_job(job_id => 42, schedule => '0 5 * * *', command => 'SELECT public.refresh_overview_history_v1();', active => true);

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid=45 AND jobname='overview-independent-core-cache-watch') THEN
    RAISE EXCEPTION 'Expected production Product cron job 45 absent';
  END IF;
  PERFORM cron.alter_job(job_id => 45, schedule => '*/5 * * * *', command => 'SELECT metrics_private.refresh_overview_independent_core_kpi_cache_v1(20);', active => true);

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid=46 AND jobname='overview-chart-summary-cache-watch') THEN
    RAISE EXCEPTION 'Expected production Product cron job 46 absent';
  END IF;
  PERFORM cron.alter_job(job_id => 46, schedule => '2,7,12,17,22,27,32,37,42,47,52,57 * * * *', command => 'SELECT metrics_private.refresh_overview_chart_summary_cache_v1(4);', active => true);
END $rollback$;
