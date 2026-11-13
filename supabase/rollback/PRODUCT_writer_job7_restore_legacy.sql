-- MANUAL WRITER #7 ROLLBACK, NOT APPLIED.
-- Restores the original Vault URL name without retrieving the underlying
-- service_role JWT or CRON_SECRET. Run before refresh/reconcile rollback.
BEGIN;
SET LOCAL lock_timeout='5s';
DO $restore$
DECLARE shadow_cmd text;
BEGIN
 IF current_setting('aia_product_cutover.rollback_authorized',true) IS DISTINCT FROM 'yes'
 THEN RAISE EXCEPTION 'Explicit rollback authorization required';END IF;
 SELECT command INTO shadow_cmd FROM cron.job
 WHERE jobid=7 AND jobname='sync-incremental-hourly' AND active FOR UPDATE;
 IF shadow_cmd IS NULL OR
 length(shadow_cmd)-length(replace(shadow_cmd,'''product_shadow_canonical_function_url_v1''','')) <> length('''product_shadow_canonical_function_url_v1''')
 THEN RAISE EXCEPTION 'Writer job does not point to expected shadow URL';END IF;
 IF NOT EXISTS(SELECT 1 FROM vault.secrets WHERE name='sync_incremental_function_url')
 THEN RAISE EXCEPTION 'Original Vault URL name is missing';END IF;
 PERFORM cron.alter_job(7, command := replace(shadow_cmd,
   '''product_shadow_canonical_function_url_v1''','''sync_incremental_function_url'''));
END $restore$;
COMMIT;
