# Jira Flow: published-snapshot stale-clock incident

**Date:** 2026-10-17. **Scope:** `jira.get_filtered_dashboard_flow_submodule` only.

## Root cause

The published `jira.metric_cohorts` Core population freezes stale membership at
`jira.dashboard_snapshot_refresh_state.refreshed_at`. However, the live Flow
submodule reads `fs.is_stale` and `fs.is_stale_blocked` from
`jira.v_issue_flow_state`, whose definitions are calculated with `now()`.
Between scheduled Jira syncs, the counts drift, triggering the intentional
`jira_delivery_population_reconciliation_failed` exception and blanking
Engineering Overview and Assignee Overview.

As checked on published sync **107** (2026-10-17 12:35 UTC):
- Open **794** on both Core/Flow.
- Core stale **260**, Flow moving-clock stale **581**.
- Core stale+blocked **13**, Flow moving-clock stale+blocked **38**.
- Core and Flow open bugs **302**, blocked issues **44**.

## Fix scope

Replace only `jira.get_filtered_dashboard_flow_submodule`. Its internal
`published_cutoff` CTE reads `refreshed_at`, and the Flow population uses
the same cutoff for `is_stale`, `is_stale_blocked`,
`stale_calc_days`, and `blocked_days`.

Do **not** change `jira.v_issue_flow_state`, since ingestion and cohort
refresh depend on that view; freezing it directly could cause the **next
sync's** cohort refresh to evaluate against the previous snapshot.

Do **not** change Core, deletion/tombstone filters, issue lists, security grants,
historical-sprint membership, or snapshot mismatch safeguards.

The rest of the Flow reader retains its existing contract (including bug-age,
stage and queue indicators); further reporting-clock alignment would require
separate parity checks and should not be silently bundled with this fix.

## Read-only regression evidence

Compared the **exact issue-key sets**, not just counts, between Core's
`stale_7d` and `stale_blocked` cohorts and Flow's projected
`refreshed_at - updated_at > interval '7 days'` test. Both directions of
set difference were zero in all eight scopes:
1. All Jira
2. Active Sprint 51 (1270)
3. Historical Sprint 49 (1238)
4. Module AP
5. Module Banking
6. Severity L1
7. Module AP, sub-module ap
8. Historical Sprint 50 (1268), module AP

Read-only execution of the proposed full Flow SQL yielded
`stale_all=260`, `stale_blocked=13`, `open_total=794`,
`blocked_all=44` and `open_bugs=302`, matching published Core totals.

## Release controls

1. Review / build the GitHub branch with migration+rollback.
2. Record current published sync, view state, function ACLs and before timings.
3. Apply one Supabase migration; do not mix it with other SQL/schema changes.
4. Verify exact post-migration cohort/Flow parity for no-filter, sprint,
   module/sub-module, severity and historical scopes, plus evidence totals.
5. Verify both production Engineering pages load without an unavailable-data
   state, with filters, date/sprint views and drill-downs still valid.
6. If the reader regresses, apply the exact original definition in
   `supabase/rollbacks/20261017_jira_flow_published_cutoff_v1.sql` as a
   separately reviewed emergency rollback.
7. Merge to main only after post-migration results are acceptable.

**No stale/sample data fallbacks or skipped reconciliation safeguards.**
