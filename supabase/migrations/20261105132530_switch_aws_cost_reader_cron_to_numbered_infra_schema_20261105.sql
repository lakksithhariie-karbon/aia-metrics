-- Infra migration, stage 2. Applied in Supabase as 20261105132530.
-- Requires deployed aws-cost-sync Edge Function v6 writing to "03_infra_schema".
-- Only update private dashboard reader + daily cron guard. Preserve original tables as backups.
DO $cutover$
DECLARE v_def text; v_cmd text; v_jobid bigint; v_report jsonb;
BEGIN
 IF (SELECT count(*) FROM "03_infra_schema".aws_costs)<>(SELECT count(*) FROM aia_infra.aws_costs)
 OR (SELECT count(*) FROM "03_infra_schema".aws_cost_sync_runs)<>(SELECT count(*) FROM aia_infra.aws_cost_sync_runs)
 OR (SELECT sum(cost_usd) FROM "03_infra_schema".aws_costs)
    IS DISTINCT FROM (SELECT sum(cost_usd) FROM aia_infra.aws_costs)
 THEN RAISE EXCEPTION 'AWS old and new copies mismatch: unsafe to cut over'; END IF;

 SELECT pg_get_functiondef('public.read_infra_aws_live_v1()'::regprocedure) INTO STRICT v_def;
 IF position('aia_infra.aws_costs' IN v_def)=0
 OR position('aia_infra.aws_cost_sync_runs' IN v_def)=0
 OR position('"03_infra_schema".aws_costs' IN v_def)>0 THEN
   RAISE EXCEPTION 'Reporting RPC already changed or differs from expected source';
 END IF;
 EXECUTE replace(replace(v_def,
   'aia_infra.aws_cost_sync_runs','"03_infra_schema".aws_cost_sync_runs'),
   'aia_infra.aws_costs','"03_infra_schema".aws_costs');

 SELECT jobid,command INTO STRICT v_jobid,v_cmd FROM cron.job
 WHERE jobname='aws-cost-sync' AND active AND schedule='17 4 * * *';
 IF position('aia_infra.aws_cost_sync_runs' IN v_cmd)=0
 OR position('interval ''20 hours''' IN v_cmd)=0 THEN
   RAISE EXCEPTION 'Daily AWS cron changed unexpectedly';
 END IF;
 PERFORM cron.alter_job(job_id:=v_jobid,
  command:=replace(v_cmd,'aia_infra.aws_cost_sync_runs',
                     '"03_infra_schema".aws_cost_sync_runs'));

 v_report:=public.read_infra_aws_live_v1();
 IF v_report IS NULL OR v_report->>'contract'<>'infra_aws_live_v1'
 OR v_report->>'mode'<>'live-aws-costs'
 OR (v_report->'awsRun'->>'rows')::int<>12535
 OR abs((v_report->'awsRun'->>'driftUsd')::numeric)>0.05 THEN
   RAISE EXCEPTION 'Reconciled reporting contract changed, abort cutover';
 END IF;
END;
$cutover$;

COMMENT ON TABLE "03_infra_schema".aws_costs IS
 'Canonical Cost Explorer detail written by AWS aws-cost-sync Edge Function v6. Restricted to trusted sync and fetcher roles.';
COMMENT ON TABLE "03_infra_schema".aws_cost_sync_runs IS
 'Canonical Cost Explorer sync audit; daily cron and dashboard reader refer here.';
COMMENT ON SCHEMA "03_infra_schema" IS
 'AWS cloud cost data and sync lineage, canonical since 2026-11-05. Private, not exposed to public Data API.';
COMMENT ON TABLE aia_infra.aws_costs IS
 'Retained read-only-by-convention pre-migration rollback snapshot. Do not write; remove only after follow-up verification and separate approval.';
COMMENT ON TABLE aia_infra.aws_cost_sync_runs IS
 'Retained pre-migration rollback snapshot. Do not write; remove only after follow-up verification and separate approval.';
