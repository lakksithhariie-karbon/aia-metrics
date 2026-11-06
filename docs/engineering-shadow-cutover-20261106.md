# Engineering shadow-schema migration: 6 November 2026

## Objective and exclusions

Rebuild the Engineering/Jira reporting domain in `"02_engineering_schema"` alongside `jira`, without renaming, deleting or modifying old Jira tables. Do not touch teammate-owned `feature_olap` or `product_source`, nor Product, Model, or Infra.

## Rebuilt objects

- 20 base tables with original rows and constraints, 39 views, four materialized views.
- 35 cloned Jira helper routines and four private read_jira_delivery_* shadow RPCs.
- All 20 tables have RLS enabled and no direct anonymous or authenticated access.
- Database migrations Stage A-F and trusted-role grants are copied here exactly from Supabase's applied migration history.

## 6 November pre-cutover verification

- 20/20 table row counts and full row content matched old Jira prior to the shadow writer test.
- New reporting/view definitions reference `"02_engineering_schema"`, not `jira`.
- The old source is still the production reader/writer.
- The isolated writer `jira-sync-engineering` is deployed, JWT verification enabled, with only connection search_path changed to `"02_engineering_schema",jira,public`.
- Shadow writer canary: sync #148 at 09:44-09:45 UTC, 30 issues and 54 history rows, 0 errors, HTTP 200. The source `jira` sync remains #147.
- Shadow materialized views refreshed and shadow snapshot published for sync #148.
- Before switching public RPCs, compare returned JSON structures, targeted metrics, all issue/sprint drilldowns, and record counts after the next source/target shared sync point.

## Pre-cutover gates

1. No unpublished/failed shadow sync; no conflicting Jira jobs running.
2. Snapshot latest sync ID equals the latest successful shadow sync and default/active sprint read functions succeed.
3. Check source-vs-target count/hash differences, distinguishing legitimate new Jira events from lost records.
4. Original cron commands, original four public RPC definitions and permissions must be available for immediate rollback.
5. New writer `jira_sync` role grants, RLS policies, and production service_role-only RPC execution must remain intact.
6. Update cron writer URLs, 5-minute refresh watchdog, and public RPC routing as one guarded change, preserving job schedules and APIs.
7. Validate new scheduled ingestion and dashboard smoke tests before retiring any old objects.

## Rollback

Restore the two cron writer commands to the existing `jira-sync` function, restore the watchdog to `jira.refresh_metric_cohorts()`, and restore all four public RPC definitions from the pre-cutover backup. Keep `jira` data available and replay any missed Jira sync before serving old data. Never delete either schema during validation.

The earlier schema rename draft PR #37 is blocked and must not be merged as the migration strategy.

## Verified rollback artifact

The exact original four public RPC definitions and all three scheduled job commands were captured before cutover in `supabase/rollback/20261106_engineering_shadow_restore_public_rpc_and_cron.sql`. This rollback updates only routing and restores the pre-cutover behavior. The source `jira` schema and original `jira-sync` Edge Function are never removed. After any rollback, run/replay the original incremental sync and validate snapshot freshness.
