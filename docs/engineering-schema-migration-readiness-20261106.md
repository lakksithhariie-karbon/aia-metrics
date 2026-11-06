# Engineering schema migration: dependency audit and controlled cutover plan

**Audit date:** 2026-11-06
**Source:** `jira`
**Destination:** `"02_engineering_schema"`
**Status:** Audit complete, **no Engineering database migration or cutover applied**.
**Strict exclusions:** `feature_olap`, `product_source`, Infra, Model and Product.

## Confirmed live inventory

| Type | Count | Notes |
| --- | ---: | --- |
| Physical base tables | 20 | Writer tables, mapping dimensions, sync audit and snapshot state |
| Ordinary views | 39 | Interconnected reporting views |
| Materialized views | 4 | `metric_cohorts`, `mv_sprint_commitment_pending`, `mv_sprint_commitment_scope`, `v_module_counts` |
| Jira-schema functions | 35 | Some SECURITY DEFINER, many unqualified references using search_path |
| Public dashboard RPCs | 4 | `read_jira_delivery_dashboard_v1`, `read_jira_delivery_evidence_v1`, `read_jira_delivery_evidence_v2`, `read_jira_delivery_issue_v1` |
| Sequences | 3 | `issue_links_link_id_seq`, `sync_errors_id_seq`, `sync_log_id_seq` |
| Direct view/materialized dependency edges | 125 | 43 dependent views/materializations; 32 upstream Jira objects |

The private numbered schema already exists and has **zero objects**.
No ordinary or materialized views in external database schemas depend directly
on Jira views/tables through the PostgreSQL catalog. However, the four public
RPCs call Jira functions and read Jira relations by qualified names.

The `jira` schema grants USAGE to `jira_sync` and
`product_metrics_fetcher`. The 20 existing private Jira base tables have
RLS disabled; **do not expose** either `jira` or the numbered replacement
through the Supabase Data API, do not broaden `anon` or `authenticated`
privileges, and do not silently weaken current controls.

## Live ingestion and reporting dependencies

- Active Edge Function `jira-sync` **v12** is checked into the repo and
  currently deployed with identical source. It connects using
  `postgres(..., { connection: { search_path: "jira,public" } })`
  and performs unqualified PostgreSQL INSERT/UPDATE/UPSERT statements.
- Database role `jira_sync` also has a default
  `search_path=jira, public` setting.
- Active scheduled syncs:
  - `jira-sync-0230utc` at 02:30 UTC (08:00 IST), daily.
  - `jira-sync-1230utc` at 12:30 UTC (18:00 IST), daily.
  - `jira-dashboard-snapshot-watchdog` every five minutes, calling
    `jira.refresh_metric_cohorts()` and refreshing all four
    materialized views concurrently, then updating
    `jira.dashboard_snapshot_refresh_state`.
- Latest verified clean sync as of audit: ID **146**, finished on
  2026-11-06 at 02:30:34 UTC. It processed 28 issues, inserted
  89 history rows and recorded zero errors.
- Latest published snapshot state: `refreshed_sync_id = 146`,
  `refreshed_at = 2026-11-06 02:35:00 UTC`.
- Reference baseline: 7,523 `issues`, 7,523 `raw_issues`,
  78,530 `issue_field_history`, 57 `sprints`,
  16,843 `sprint_issues`, and 23 `metric_cohorts` rows.
- Live routes `/delivery` and `/delivery/assignees` both returned
  HTTP 200 during the audit.
- A repeated direct read of the existing dashboard RPC hit an
  `8s` nested Jira flow function statement timeout. This is a
  **pre-existing baseline concern**, not a migration regression.
  Runtime logs also recorded one assignee evidence HTTP 400
  on a previous production deployment in the last 24 hours.
  Do not infer that every baseline RPC always succeeds.

## Recommended cutover, not yet executed

**Prefer an object-preserving PostgreSQL schema rename over cloning/mirroring
the entire Jira graph.** It retains table/foreign-key/view/materialized-view
identity, indexes, existing rows, sequence ownership, privileges and catalog
dependencies without creating a second write system. A schema rename
**does not rewrite qualified names stored inside string-literal function
bodies**. All function source, role settings and jobs must therefore be
updated as one controlled release.

1. Capture full original definitions of the 35 Jira functions, four public
   RPCs, the three cron commands, role settings, grants, indexes, and the
   current sync/snapshot baselines. Prepare a complete reverse migration and
   validate function rewrite logic before executing DDL.
2. Deploy a backwards-compatible Jira Edge Function update using
   `search_path='"02_engineering_schema",jira,public'`. Before the
   rename, it still resolves all table/function names in `jira`; after
   the rename, it resolves them in the numbered schema. Keep existing
   authorization, retry handling and secrets unchanged.
3. In a **single database transaction** with a short lock timeout,
   preflight-check exact object counts and empty destination. Retire the
   **empty** reserved destination namespace only, then rename `jira`
   to `"02_engineering_schema"`. Update all 35 moved function definitions
   and their `SET search_path` attributes, plus four `public`
   RPC definitions, replacing schema-qualified `jira.` references with
   the quoted new identifier. Retarget the watchdog cron command and the
   `jira_sync` role search path. Keep the two HTTP-trigger cron jobs.
4. Within that transaction, assert all 20 tables, 39 views, four
   materialized views and 35 moved functions exist with unchanged
   object OIDs, existing ACLs and no stale `jira.` references in
   active function bodies or cron. Check nested SQL helpers and non-PII
   response-contract fields, then commit; otherwise roll back the
   entire transaction automatically.
5. Verify the production `/delivery` and `/delivery/assignees`
   routes, public RPC contracts and drilldowns, materialized counts,
   permission boundaries and no new runtime errors.
6. Observe the next five-minute snapshot watchdog and **both** daily
   Jira ingestion schedules before treating Engineering as fully complete.
   Preserve the former definitions and rollback SQL for recovery.

### Rollback design

The reverse transaction renames
`"02_engineering_schema"` back to `jira`, restores all original
function definitions and their search paths, restores the Jira cron
watchdog target and original `jira_sync` role configuration, and
recreates the empty numbered destination namespace. Because the data
objects retain their OIDs, rows, indexes and foreign keys are not
reloaded or rewritten. The dual-search-path Edge Function can continue
working on either side of the rollback.

### Hard safety gates

- Never modify or move any `feature_olap` or `product_source` object.
- Keep all Data API access unchanged; do not grant browser access to
  private engineering tables.
- Do not rename the live schema until the complete 39-function
  definition rewrite and rollback have been prepared and reviewed.
- Do not treat an HTTP 200 alone as proof of KPI or freshness parity;
  compare server-calculated sprint, cycle-time, quality, cohort and
  assignee metrics and a fresh successful sync.

**This file is a migration readiness report, not an authorization to run
a destructive or partially prepared schema rename.**