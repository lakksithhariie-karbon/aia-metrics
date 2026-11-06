-- Engineering rebuild stage E1: populate three independent materializations.
-- New schema ONLY. Legacy Jira cron and materializations remain untouched.
SET LOCAL lock_timeout = '8s';
SET LOCAL statement_timeout = '180s';
DO $refresh$
BEGIN
 IF (SELECT count(*) FROM pg_class WHERE relnamespace='02_engineering_schema'::regnamespace AND relkind='m')<>4
 THEN RAISE EXCEPTION 'New Engineering materialized view inventory incomplete'; END IF;
 REFRESH MATERIALIZED VIEW "02_engineering_schema".mv_sprint_commitment_pending;
 REFRESH MATERIALIZED VIEW "02_engineering_schema".mv_sprint_commitment_scope;
 REFRESH MATERIALIZED VIEW "02_engineering_schema".v_module_counts;
 IF EXISTS (SELECT 1 FROM pg_class WHERE relnamespace='02_engineering_schema'::regnamespace
    AND relname IN('mv_sprint_commitment_pending','mv_sprint_commitment_scope','v_module_counts')
    AND NOT relispopulated)
 THEN RAISE EXCEPTION 'Independent materialized views not populated'; END IF;
END;
$refresh$;