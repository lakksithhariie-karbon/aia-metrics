-- MANUAL, GUARDED, POST-CANARY CUTOVER OF PRODUCT REFRESH CRONS.
-- Not a Supabase migration, never executed automatically.
-- Run only after authorized authenticated shadow Edge ingestion succeeds AND
-- the canonical writer #7 is separately routed to shadow through a managed
-- Vault URL, with a validated rollback. Do not change #7 via this script.
-- In the SAME coordinated maintenance window:
--  1. Switch job #7 from the vaulted legacy Edge URL to a NEW vaulted shadow URL.
--     Never replace or delete the original Vault secret. Do not paste secrets in SQL.
--  2. Run this transaction to reroute seven cache refresh jobs and stop
--     legacy→new replication #47/#48 before new canonical writes diverge.
--  3. Apply guarded reader RPC switch and deploy Companies Edge compatibility.
--  4. Verify each function/cron response and retain rollback path.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='120s';
DO $guard$
BEGIN
  IF current_setting('aia_product_cutover.approved',true) IS DISTINCT FROM 'yes'
     OR current_setting('aia_product_cutover.authenticated_canary_passed',true) IS DISTINCT FROM 'yes'
     OR current_setting('aia_product_cutover.canonical_writer_active',true) IS DISTINCT FROM 'yes'
     OR current_setting('aia_product_cutover.companies_compatible',true) IS DISTINCT FROM 'yes'
  THEN RAISE EXCEPTION 'Cannot reroute refresh cron until authorized ingestion, writer and Companies API pass'; END IF;
  IF (SELECT count(*) FROM cron.job WHERE jobid IN (29,39,40,41,42,45,46,47,48) AND active)<>9
  THEN RAISE EXCEPTION 'Unexpected Product cron inventory; stop and inspect manually';END IF;
  IF (SELECT count(*) FROM "01_product_schema".events)<>(SELECT count(*) FROM public.events)
  THEN RAISE EXCEPTION 'Product events parity mismatch';END IF;
  PERFORM cron.alter_job(29, command := 'SELECT "01_product_schema".refresh_companies_monthly_cache();');
  PERFORM cron.alter_job(39, command := 'SELECT "01_product_schema".refresh_retention_dashboard_v3(false);');
  PERFORM cron.alter_job(40, command := 'SELECT "01_product_schema".refresh_companies_monthly_core_v2();');
  PERFORM cron.alter_job(41, command := 'SELECT "01_product_schema".refresh_retention_dashboard_v4(false);');
  PERFORM cron.alter_job(42, command := 'SELECT "01_product_schema".refresh_overview_history_v1();');
  PERFORM cron.alter_job(45, command := 'SELECT "01_product_schema".refresh_overview_independent_core_kpi_cache_v1(20);');
  PERFORM cron.alter_job(46, command := 'SELECT "01_product_schema".refresh_overview_chart_summary_cache_v1(4);');
  -- Prevent old public source from overwriting the new canonical Product data.
  PERFORM cron.alter_job(47, active := false);
  PERFORM cron.alter_job(48, active := false);
END $guard$;
COMMIT;
