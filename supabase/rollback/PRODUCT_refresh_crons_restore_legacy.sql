-- MANUAL ROLLBACK for Product refresh cron switches.
-- This does not switch Product ingestion #7. Operator must restore original
-- vaulted URL and verify legacy writer before re-enabling shadow reconciliation.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $rollback$
BEGIN
  IF current_setting('aia_product_cutover.legacy_writer_restored',true) IS DISTINCT FROM 'yes'
  THEN RAISE EXCEPTION 'Restore original writer #7 and verify it BEFORE running this rollback';END IF;
  PERFORM cron.alter_job(29, command := 'SELECT public.refresh_companies_monthly_cache();');
  PERFORM cron.alter_job(39, command := 'SELECT public.refresh_retention_dashboard_v3(false);');
  PERFORM cron.alter_job(40, command := 'SELECT public.refresh_companies_monthly_core_v2();');
  PERFORM cron.alter_job(41, command := 'SELECT public.refresh_retention_dashboard_v4(false);');
  PERFORM cron.alter_job(42, command := 'SELECT public.refresh_overview_history_v1();');
  PERFORM cron.alter_job(45, command := 'SELECT metrics_private.refresh_overview_independent_core_kpi_cache_v1(20);');
  PERFORM cron.alter_job(46, command := 'SELECT metrics_private.refresh_overview_chart_summary_cache_v1(4);');
  PERFORM cron.alter_job(47,active:=true);
  PERFORM cron.alter_job(48,active:=true);
END $rollback$;
COMMIT;
