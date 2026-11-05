-- EMERGENCY ROLLBACK ONLY. NOT a forward migration and not auto-applied.
-- 1. Redeploy the original AWS Edge Function v5 (see adjacent rollback code).
-- 2. Run this SQL once to backfill any new data and repoint cron/reporting to old tables.
-- 3. Verify read_infra_aws_live_v1(), the Infra page and the next scheduled sync.
-- Keep the new target tables as backup. Never touch feature_olap or product_source.
BEGIN;
LOCK TABLE "03_infra_schema".aws_costs, "03_infra_schema".aws_cost_sync_runs IN SHARE MODE;

INSERT INTO aia_infra.aws_cost_sync_runs
 SELECT * FROM "03_infra_schema".aws_cost_sync_runs WHERE true
 ON CONFLICT (id) DO UPDATE SET
   started_at=excluded.started_at,finished_at=excluded.finished_at,
   ok=excluded.ok,months_covered=excluded.months_covered,
   accounts=excluded.accounts,rows_upserted=excluded.rows_upserted,
   drift_usd=excluded.drift_usd,total_usd=excluded.total_usd,error=excluded.error;

INSERT INTO aia_infra.aws_costs
 SELECT * FROM "03_infra_schema".aws_costs WHERE true
 ON CONFLICT (cost_month,linked_account,service,usage_type) DO UPDATE SET
  cost_usd=excluded.cost_usd,usage_qty=excluded.usage_qty,usage_unit=excluded.usage_unit,
  currency=excluded.currency,estimated=excluded.estimated,fetched_at=excluded.fetched_at;

SELECT setval('aia_infra.aws_cost_sync_runs_id_seq'::regclass,
  (SELECT max(id) FROM aia_infra.aws_cost_sync_runs),true);

DO $rollback$
DECLARE v_def text; v_cmd text; v_jobid bigint; v_report jsonb;
BEGIN
 SELECT pg_get_functiondef('public.read_infra_aws_live_v1()'::regprocedure) INTO STRICT v_def;
 IF position('"03_infra_schema".aws_costs' IN v_def)=0
 OR position('"03_infra_schema".aws_cost_sync_runs' IN v_def)=0 THEN
  RAISE EXCEPTION 'Reporting function not targeting expected new Infra tables';
 END IF;
 EXECUTE replace(replace(v_def,
  '"03_infra_schema".aws_cost_sync_runs','aia_infra.aws_cost_sync_runs'),
  '"03_infra_schema".aws_costs','aia_infra.aws_costs');

 SELECT jobid,command INTO STRICT v_jobid,v_cmd FROM cron.job
 WHERE jobname='aws-cost-sync' AND active AND schedule='17 4 * * *';
 IF position('"03_infra_schema".aws_cost_sync_runs' IN v_cmd)=0
 OR position('interval ''20 hours''' IN v_cmd)=0 THEN
  RAISE EXCEPTION 'AWS cron changed unexpectedly; manual rollback needed';
 END IF;
 PERFORM cron.alter_job(job_id:=v_jobid,
  command:=replace(v_cmd,'"03_infra_schema".aws_cost_sync_runs','aia_infra.aws_cost_sync_runs'));

 v_report:=public.read_infra_aws_live_v1();
 IF v_report IS NULL OR v_report->>'contract'<>'infra_aws_live_v1'
 OR abs((v_report->'awsRun'->>'driftUsd')::numeric)>0.05 THEN
  RAISE EXCEPTION 'Rolled-back report did not reconcile, undoing transaction';
 END IF;
END;
$rollback$;
COMMIT;
