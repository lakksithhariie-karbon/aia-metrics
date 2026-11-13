-- Restore previous shadow-only cron commands. Does not change production ingestion jobs.
SET LOCAL lock_timeout='7s';
SELECT cron.alter_job(job_id=>47,command=>'SELECT "01_product_schema".sync_legacy_product_shadow_v1(false);');
SELECT cron.alter_job(job_id=>48,command=>'SELECT "01_product_schema".sync_legacy_product_shadow_v1(true);');
