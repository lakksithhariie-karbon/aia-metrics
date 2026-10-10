# Jira reporting integrity audit | 10 October 2026

## Purpose

Two existing reporting defects were corrected on GitHub branch `fix/jira-data-foundation-v1` and applied as additive/reversible Supabase migrations.

1. `jira.v_sprint_discipline.done_now` incorrectly counted **all sprint issues**, not completed issues. It now uses `count(*) FILTER (WHERE is_done)` and reconciles with `scope_completion_pct`.
2. Jira-deleted issues were present in current/open reporting populations. All current-state read views now check `jira.raw_issues.deleted_at` without deleting raw events, derived issue rows, or history.

## Deployed database migrations

- `jira_reporting_definition_integrity_v1`: replaces the eight existing reporting view definitions without altering their column signatures, and creates `jira.v_metric_cohorts_active_v1` as a lightweight, snapshot-bounded correction adapter for eight count-based cohorts. Updates the existing `jira.get_filtered_metric_cohorts` reader.
- `jira_filtered_core_reader_alignment_v1`: preserves the exact signatures and return contracts of `jira.get_filtered_dashboard_core_025_base` and `jira.get_filtered_dashboard_core_025_base_submodule`, and changes only their published cohort row source to the validated adapter.

No new jobs, database copies, or data-destructive operations were created.

## Reconciliation results

All figures below were read from live Supabase project `hdgbmcerogqfocyxdnpw` after applying both migrations.

| Scope | Before | After | Validated against |
| --- | ---: | ---: | --- |
| Sprint 50 `done_now` | 998 | **459** | `scope_now=998`, `scope_completion_pct=46.0%`; filtered RPC returned 459 |
| Open issues | 819 | **808** | `v_wip_by_status`, `v_flow_counts.open_total`, normalized issues, verified cohort, both core RPCs |
| Open bugs | 305 | **304** | `v_bug_health`, verified cohort, both core RPCs |
| Stale issues (7d) | 589 | **578** | `v_issue_flow_state`, verified cohort, both core RPCs |
| QA queue | 84 | **84** | `v_qa_queue`, verified cohort, both core RPCs |
| Blocked | 41 | **41** | `v_issue_flow_state`, `v_flow_counts`, verified cohort |

For a scoped regression: Sprint 50 + module AP returns **93 open issues** and **33 open bugs**, matching the direct distinct source population. Both standard and sub-module core RPCs matched, with `scope_now=219` and `done_now=126`.

Total preserved source data: **6,931 raw issues**, **6,931 derived issues**, **71,307 history records**, and **15,586 sprint memberships**. The 11 deleted issues remain in storage with tombstones for auditability but do not appear in current-state reporting views. No malformed or orphaned sprint references were introduced.

The last published clean sync remains `93`; its cohort evidence is corrected using the deletion cutoff at that published sync, not a later unverified raw-data state.

## The original materialized snapshot is deliberately not rewritten

`jira.metric_cohorts` is a pre-existing, 23-row materialized view containing a large source query. Its **direct** `wip_open`, `open_bugs` and `stale_7d` rows still reflect the old definitions (**819/305/589**). Rebuilding or replacing the materialized view would have been a much more invasive migration, with unrelated 4–6-minute refresh and rollback risks.

**Do not read those direct materialized rows as published customer-facing metrics.** The authoritative count sources for the Engineering dashboard are now:

- `jira.v_metric_cohorts_active_v1` for snapshot-bounded, verified cohort values and full evidence rows
- `jira.get_filtered_metric_cohorts` for its existing filter/evidence contract
- `jira.get_filtered_dashboard_core` and `jira.get_filtered_dashboard_core_submodule` for consistent dashboard counts and sprint/module-scope filters
- `jira.v_wip_by_status`, `jira.v_issue_flow_state`, `jira.v_bug_health`, `jira.v_qa_queue`, and `jira.v_sprint_discipline` for current-state source truth

The adapter has no extra persistence or cron schedule; it reads the published cohort snapshot and filters only deletes already recorded by its clean-sync cutoff. The original materialized view remains available for safe rollback and for unaffected historical metrics.

## Runtime & security checks

- Standard filtered core RPC: ~3.36 s
- Sub-module filtered core RPC: ~2.88 s
- Both rendered the corrected values, and scoped AP/Sprint 50 populations matched direct database results.
- `jira.get_filtered_dashboard_flow` and `jira.get_filtered_dashboard_quality` both execute and retain their output contracts.
- `jira` schema still has no USAGE privilege for `anon` or `authenticated` roles, as before.
- Supabase `jira-sync` Edge Function v12, JWT verification, and source sync routines were **not changed** in this reporting step.
- Vercel production and GitHub `main` were **not changed**.

## Ongoing quality boundaries

Historical Jira sprint metrics calculated from *current* issue statuses are not necessarily point-in-time historical completion numbers; comparisons should state that limitation. Severity and module tags have substantial missing coverage and should display an explicit Untagged category. Original legacy cohort drill functions only apply a sprint filter when their row schema publishes a sprint-id field; do not equate differently scoped drill rows without checking scope metadata.

Future Engineering UI wiring should use only the verified read paths above, and should reconcile the displayed headline, its filtered population, and drill rows with the same scope before publishing.

## Repeatable verification

Run `supabase/tests/jira_reporting_integrity_checks.sql` with a read-only SQL editor to recheck lineage, populations, sprint completion and cohort count/evidence parity. The CI/prebuild static contract is `scripts/verify-jira-reporting-integrity.mjs`.

Rollback should be a reviewed migration restoring individual prior view/function definitions from their previous GitHub-tracked migrations. Do not delete any Jira issue/history data, undo the Edge Function authentication, or change the existing cron schedule.
