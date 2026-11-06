-- Engineering rebuild stage E2: calculate 23+ metric cohort snapshots in
-- private numbered schema, without altering Jira's live snapshot or cron.
SET LOCAL lock_timeout = '8s';
SET LOCAL statement_timeout = '240s';
REFRESH MATERIALIZED VIEW "02_engineering_schema".metric_cohorts;
DO $validate$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relnamespace='02_engineering_schema'::regnamespace
  AND relname='metric_cohorts' AND relkind='m' AND relispopulated)
 THEN RAISE EXCEPTION 'New metric cohort materialization is not populated'; END IF;
 IF (SELECT count(*) FROM "02_engineering_schema".metric_cohorts)<20
 THEN RAISE EXCEPTION 'Unexpectedly few new Engineering metric cohorts'; END IF;
END;
$validate$;