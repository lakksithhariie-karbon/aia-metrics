# Jira Engineering page performance investigation

**Date:** 2026-10-11. **Status:** Preview-only instrumentation deployed; SQL optimizer migration **prepared, not applied**.

## Pages in scope

- `/delivery`: Engineering Overview, single source-validated dashboard RPC.
- `/delivery/assignees`: the same dashboard plus three full, separately validated issue cohorts. The preview currently starts all four requests concurrently and reconciles every response against the same published snapshot before rendering.

Both pages use the audited Jira readers. No fake counts, client-side approximate denominators, or stale aggregate caching are permitted.

## Measurements

Read-only PostgreSQL `EXPLAIN (ANALYZE, COSTS OFF)` samples on the live database, without writing data:

| Function / scope | Normal (ms) | `SET LOCAL enable_nestloop=off` (ms) |
| --- | ---: | ---: |
| Unfiltered dashboard facade | 10,261 | 5,528 |
| Unfiltered Core reader | 3,585 | 2,505 |
| Unfiltered Flow reader | 5,952 | 1,507 |
| Unfiltered Quality reader | 1,423 | 1,387 |
| Dashboard: Sprint 50 + AP | 1,855 | 1,814 |
| Full `wip_open` evidence | 3,684 | 3,947 |

On Sprint 50 + AP, nested-loops-on/off both returned the **same published snapshot 95, 87 open, 28 open bugs, 0 blocked, 0 stale, and 2 issue-type groups**. Query-plan changes do not intentionally change calculations; the final audit must validate broader scopes, historical filters and drill parity.

Increasing `work_mem` from 5 MB to 64 MB did not materially improve Flow latency. Forcing a custom plan did not materially improve it either.

## Vercel observations

- At commit `35b4d4c`, Assignee Overview took ~24.2s via the authenticated preview probe, roughly matching the prior branch's ~23.9s. Initial evidence parallelization alone did **not** demonstrate a meaningful cold-page speedup.
- Shared server-side RPC timing was added with no Jira records or secrets in logs.
- Vercel function logs show executions in `iad1` while Supabase is in `ap-south-1`. The route-segment `preferredRegion="bom1"` hint did not override the Vercel Hobby project's single default region. **Do not claim the region is fixed.** Changing the project-wide function region requires separate approval because it could affect other pages or production.

## Proposed SQL change

The un-applied migration `20261011_jira_delivery_dashboard_join_plan_v1.sql` sets `enable_nestloop=off` **on the existing dashboard facade only**. Because the setting is function-local, the caller, filter signatures, snapshot logic, API permissions and all report output contracts remain unchanged. It does not rewrite any SQL and does not touch the evidence/issue APIs. It should benefit both pages because both use this dashboard facade.

**Approval is required before applying any live Supabase DDL.**

## Safe release sequence

1. Obtain explicit approval for the one-function optimizer-only migration.
2. Apply with change-control, verify the function retains `SECURITY DEFINER`, existing `search_path`, `statement_timeout`, and service-role grants.
3. Re-run the same read-only EXPLAIN benchmarks on the live optimized function and record variance.
4. Reconcile all five filter dimensions, selected historical sprints, snapshot coherence, visible totals, and issue drill counts against the existing audited readers.
5. Measure cold/warm Engineering and Assignee page timings. If worse, revert with `ALTER FUNCTION ... RESET enable_nestloop` and revalidate.
6. Keep PR #22 unmerged until the final independent release audit and user approval.

No production Jira, schema, permissions, scheduler or environment changes were made during preparation.
