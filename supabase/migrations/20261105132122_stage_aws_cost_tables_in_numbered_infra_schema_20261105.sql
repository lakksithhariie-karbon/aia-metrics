-- Infra migration, stage 1. Applied in Supabase as 20261105132122.
-- Copy AWS source tables into private "03_infra_schema" and preserve originals.
-- Teammate-owned feature_olap and product_source are strictly out of scope.
DO $preflight$
BEGIN
 IF to_regclass('"03_infra_schema".aws_costs') IS NOT NULL OR
    to_regclass('"03_infra_schema".aws_cost_sync_runs') IS NOT NULL THEN
  RAISE EXCEPTION 'Infra destination already populated; refusing overwrite';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='aia_infra.aws_costs'::regclass AND relrowsecurity) OR
    NOT EXISTS(SELECT 1 FROM pg_class WHERE oid='aia_infra.aws_cost_sync_runs'::regclass AND relrowsecurity) THEN
  RAISE EXCEPTION 'Expected source RLS protections absent';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='aws-cost-sync'
    AND active AND schedule='17 4 * * *' AND position('interval ''20 hours''' in command)>0) THEN
  RAISE EXCEPTION 'Expected daily AWS cron not active';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM aia_infra.aws_cost_sync_runs WHERE ok AND finished_at>now()-interval '3 days') THEN
  RAISE EXCEPTION 'Latest successful AWS run is stale';
 END IF;
END;
$preflight$;

LOCK TABLE aia_infra.aws_costs,aia_infra.aws_cost_sync_runs IN SHARE MODE;
CREATE TABLE "03_infra_schema".aws_costs (LIKE aia_infra.aws_costs INCLUDING ALL);
CREATE TABLE "03_infra_schema".aws_cost_sync_runs (LIKE aia_infra.aws_cost_sync_runs INCLUDING ALL);
CREATE SEQUENCE "03_infra_schema".aws_cost_sync_runs_id_seq AS bigint
 OWNED BY "03_infra_schema".aws_cost_sync_runs.id;
ALTER TABLE "03_infra_schema".aws_cost_sync_runs
 ALTER COLUMN id SET DEFAULT nextval('"03_infra_schema".aws_cost_sync_runs_id_seq'::regclass);
INSERT INTO "03_infra_schema".aws_costs SELECT * FROM aia_infra.aws_costs;
INSERT INTO "03_infra_schema".aws_cost_sync_runs SELECT * FROM aia_infra.aws_cost_sync_runs;
SELECT setval('"03_infra_schema".aws_cost_sync_runs_id_seq'::regclass,
 coalesce((SELECT max(id) FROM "03_infra_schema".aws_cost_sync_runs),1),true);

ALTER TABLE "03_infra_schema".aws_costs ENABLE ROW LEVEL SECURITY;
ALTER TABLE "03_infra_schema".aws_cost_sync_runs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE "03_infra_schema".aws_costs FROM PUBLIC,anon,authenticated;
REVOKE ALL ON TABLE "03_infra_schema".aws_cost_sync_runs FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE "03_infra_schema".aws_cost_sync_runs_id_seq FROM PUBLIC,anon,authenticated;
GRANT USAGE ON SCHEMA "03_infra_schema" TO aws_cost_sync,product_metrics_fetcher;
GRANT SELECT,INSERT,UPDATE ON TABLE "03_infra_schema".aws_costs TO aws_cost_sync;
GRANT SELECT,INSERT,UPDATE ON TABLE "03_infra_schema".aws_cost_sync_runs TO aws_cost_sync;
GRANT USAGE ON SEQUENCE "03_infra_schema".aws_cost_sync_runs_id_seq TO aws_cost_sync;
GRANT SELECT ON TABLE "03_infra_schema".aws_costs, "03_infra_schema".aws_cost_sync_runs TO product_metrics_fetcher;
CREATE POLICY aws_costs_sync_writer ON "03_infra_schema".aws_costs FOR ALL
 TO aws_cost_sync USING (true) WITH CHECK (true);
CREATE POLICY aws_costs_fetcher_reader ON "03_infra_schema".aws_costs FOR SELECT
 TO product_metrics_fetcher USING (true);
CREATE POLICY aws_cost_runs_sync_writer ON "03_infra_schema".aws_cost_sync_runs FOR ALL
 TO aws_cost_sync USING (true) WITH CHECK (true);
CREATE POLICY aws_cost_runs_fetcher_reader ON "03_infra_schema".aws_cost_sync_runs FOR SELECT
 TO product_metrics_fetcher USING (true);

COMMENT ON TABLE "03_infra_schema".aws_costs IS
 'Prepared target of AWS Cost Explorer monthly detail; canonical write remains aia_infra until cutover.';
COMMENT ON TABLE "03_infra_schema".aws_cost_sync_runs IS
 'Prepared target of AWS Cost Explorer sync run audit; canonical write remains aia_infra until cutover.';

DO $verify$
BEGIN
 IF (SELECT count(*) FROM "03_infra_schema".aws_costs)<>(SELECT count(*) FROM aia_infra.aws_costs)
 OR (SELECT count(*) FROM "03_infra_schema".aws_cost_sync_runs)<>(SELECT count(*) FROM aia_infra.aws_cost_sync_runs)
 OR (SELECT sum(cost_usd) FROM "03_infra_schema".aws_costs)
    IS DISTINCT FROM (SELECT sum(cost_usd) FROM aia_infra.aws_costs)
 OR (SELECT max(id) FROM "03_infra_schema".aws_cost_sync_runs)
    <> (SELECT max(id) FROM aia_infra.aws_cost_sync_runs)
 THEN RAISE EXCEPTION 'Infra copy inconsistent; roll back'; END IF;
END;
$verify$;
