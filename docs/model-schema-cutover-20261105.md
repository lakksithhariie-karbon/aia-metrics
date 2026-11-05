# Model schema read cutover and live mirror, 2026-11-05

## Status

**LIVE: Model reporting reads `"04_model_schema"`. Ingestion is deliberately unchanged.**

Two RLS-protected physical tables plus a private reporting view now exist:

| New object | Legacy source | Role |
| --- | --- | --- |
| `"04_model_schema".companies` | `aia_infra.companies` | Mirrored physical company lookup |
| `"04_model_schema".bill_costs` | `aia_infra.bill_costs` | Mirrored physical prediction-grain cost rows |
| `"04_model_schema".bill_extraction_reporting_v1` | `aia_infra.bill_extraction_reporting_v1` | Active private reporting view |

**Not a final writer move:** A separate existing ingestion process runs as
`postgres` and issues quoted `INSERT INTO "aia_infra"."companies" ... ON CONFLICT`
and `INSERT INTO "aia_infra"."bill_costs" ... ON CONFLICT`.
Automatically updatable views at the legacy path would not support the
`ON CONFLICT DO UPDATE` statements, so the legacy physical tables cannot be
replaced with compatibility views without changing that external writer.

Instead, existing-source row-level AFTER INSERT, UPDATE and DELETE triggers
automatically mirror changes to the two new physical tables. The triggers run
with the trusted owner, a fixed empty search path, no public EXECUTE grants,
and generated cost/latency columns are recalculated by PostgreSQL. The new
bill_costs foreign key points to the new companies lookup.

Do **not** drop or rename the legacy tables, disable mirroring, or change the
external writer until its owner is identified and the next ingestion has been
validated. Cross-schema source \`public.company_directory\` remains unchanged,
and test/unverified-customer classification is preserved.

## Reporting compatibility and permissions

- \`public.read_ai_bill_extraction_v1\` and \`public.read_ai_bill_analytics_v1\`
  are still the same server-only, service-role-EXECUTE RPCs and are now
  sourced from \`"04_model_schema".bill_extraction_reporting_v1\`.
- No frontend URL, Next.js API or UI change was required. The existing Vercel
  authenticated route \`/api/ai-services/report\` returns the same contracts.
- Both new tables have RLS enabled; \`product_metrics_fetcher\` has only SELECT.
  \`anon\`, \`authenticated\`, and direct \`service_role\` reads are denied.
  The new view preserves the private owner's security-barrier design.
- This migration does NOT expose the new schema in Supabase Data API.

## Production verification

At the cutover transaction:

- **37,737** bill-cost source rows, copied and matched individually.
- **705** company source rows, copied and matched individually.
- **37,737** reporting rows, with every original vs new JSONB projection
  identical; verified-customer **35,876**, test **1,588**,
  unverified **273**; known cost total **1165.86931769** source units.
- The published report and analytics RPC values matched *before vs after*
  cutover within the same transaction, including KPI, monthly, document,
  review, exception, selected-cohort, and page-analytics outputs.
- A fully rolled-back transaction tested new company INSERT/UPDATE/DELETE,
  bill INSERT/UPDATE/DELETE, and generated cost recomputation through
  the original writer path. No test data remained.
- Repeatable test: \`supabase/tests/model_schema_mirror_contract.sql\`
  passes **10/10** checks.
- Production \`GET /api/ai-services/report?from=2026-09&to=2026-11&scope=verified_customer&doc=all&status=all&search=\`
  responded HTTP 200 with \`ai_bill_extraction_live_v1\`, 26,063 selected
  predictions, 23,446 known-cost predictions, and \`ai_bill_analytics_v1\`.
- Production /ai-services, /infra and /product responded HTTP 200 after
  database cutover.

Cost currency and latency units remain **unverified**. Nothing in this
migration changes their definitions or customer-scope behavior.

## Rollback

Emergency **read-only rollback**:
\`supabase/rollback/20261105_model_reader_cutover_rollback.sql\`
restores the two public RPCs to the old reporting view. It leaves both
physical mirrors, triggers, original source tables and their records
untouched, so ingestion never depends on a data restore.

If mirroring itself fails, inspect the source transactions first. Disabling
triggers would make the mirror stale, and is a separate manual decision
requiring reconciliation before the next read cutover.

## Future final writer migration

1. Identify the owner and scheduled cadence of the external \`postgres\`
   ingestion connector; request a change to the SQL target names.
2. Confirm ON CONFLICT, column defaults, generated columns, foreign keys,
   least-privilege database access, and production ingest timestamp.
3. Coordinate a controlled switch of both company and bill upserts together.
4. Observe fresh data appearing **directly** in the new physical tables;
   compare counts, per-prediction values, company scopes, and API totals.
5. Only after a separate change and successful ingestion, retire mirroring
   and legacy tables in a dedicated reviewed migration. Keep a rollback plan.

**Strictly excluded from this project:** teammate-owned
\`feature_olap\` and \`product_source\`, AWS Infra's
\`"03_infra_schema"\`, and unrelated Product/Jira structures.
