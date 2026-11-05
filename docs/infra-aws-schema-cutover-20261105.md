# AWS Infra schema cutover, 5 November 2026

## Outcome and scope

The canonical AWS Cost Explorer cost-detail and sync-run tables now live in
\`"03_infra_schema"\`. The former tables in \`aia_infra\` remain fully
populated as rollback copies; no rows were deleted.

This scope **does not modify** \`feature_olap\`, \`product_source\`, the
product/retention/Jira data pipeline, or \`aia_infra.bill_costs\`,
\`aia_infra.companies\` and the model reporting view.

## Production components

| Component | Old | Current |
|---|---|---|
| AWS Edge Function | aws-cost-sync v5 (writes to aia_infra) | aws-cost-sync **v6**, writes to "03_infra_schema" |
| Cost table | aia_infra.aws_costs | "03_infra_schema".aws_costs |
| Run audit | aia_infra.aws_cost_sync_runs | "03_infra_schema".aws_cost_sync_runs |
| Cron | aws-cost-sync, 04:17 UTC daily, 20-hour successful-run guard | Same schedule; guard now reads new run table |
| Server RPC | public.read_infra_aws_live_v1() | Same function name, contract, RLS and ACL, new table source |
| Vercel UI | /infra, server-side fetch, no caching | No frontend changes required |

The Edge Function still requires the existing service-role bearer token and
cron secret. Its dedicated Postgres role \`aws_cost_sync\` has USAGE and
SELECT/INSERT/UPDATE rights in the new private schema. The published
snapshot remains masked and is only available through the audited service-role RPC.

## Baseline and verification

- Latest completed AWS sync at cutover:
  2026-11-05T04:17:16.390954Z; success; 12,535 rows processed,
  14 months, 16 accounts, grouped AWS reference USD 44,845.12,
  detail reconciliation difference -USD 0.0116.
- Source copied atomically with matching 14,334 stored cost rows,
  14 sync-run rows and USD 49,769.0810 stored across all rows
  (including historical upserts). Full stored sum is NOT the latest published
  reconciliation total; the RPC filters by the latest run's fetched_at window.
- RLS enabled on both new tables with role-scoped policies.
  \`anon\` and \`authenticated\` have no direct table SELECT access.
- SQL checks: source/target sums and counts exact; new table writer privileges
  verified; public reporting RPC retains SECURITY DEFINER and EXECUTE restricted
  to service_role.
- Deployed Edge Function diagnostic via pg_net returned HTTP 200:
  dedicated database role \`aws_cost_sync\`, with new schema USAGE,
  INSERT into cost and INSERT into run audit all true.
- The live /infra dashboard returned HTTP 200 and displayed
  the 5 Nov 2026 sync timestamp. September USD 4,016.56,
  October USD 4,495.91, and November-to-date USD 1,211.66
  were retrieved directly from the reconciled latest run.

## Next daily ingestion must be observed

Next regular scheduled run is 2026-11-06 04:17 UTC (09:47 IST),
subject to the existing 20-hour duplicate guard. No post-cutover AWS
Cost Explorer write was deliberately triggered during the migration,
to avoid resetting the morning refresh cadence. The Edge Function's
database connectivity and write grants were verified without an
additional AWS billable data pull.

After this run, verify:

\`\`\`sql
SELECT id, started_at, finished_at, ok, months_covered, accounts,
       rows_upserted, total_usd, drift_usd, error
FROM "03_infra_schema".aws_cost_sync_runs
ORDER BY id DESC LIMIT 3;

SELECT public.read_infra_aws_live_v1();
SELECT jobname, active, schedule
FROM cron.job WHERE jobname = 'aws-cost-sync';
\`\`\`

Check that the latest successful run id is greater than 15,
that the refreshed dashboard timestamp matches its finished_at,
and that the stored detail reconciliation is within USD 0.05.

## Rollback

1. Redeploy \`supabase/rollback/aws-cost-sync-v5/index.ts\` with the adjacent
   \`deno.json\`, keeping \`verify_jwt=false\` and existing secrets unchanged.
2. Execute \`supabase/rollback/20261105_aws_infra_schema_rollback.sql\`.
   This backfills any new run/cost records into the old tables (preserving
   fetched_at), re-points \`public.read_infra_aws_live_v1\` and the daily cron
   to \`aia_infra\`, reconciles the returned report, and commits transactionally.
3. Verify the dashboard and next scheduled ingestion. Retain new tables as
   snapshots for later cleanup after separate approval.

**Do not drop the original \`aia_infra\` tables yet.**
