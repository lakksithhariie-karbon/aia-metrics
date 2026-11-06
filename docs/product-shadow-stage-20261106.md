# Product numbered-schema migration, staged 6 November 2026

## Migration scope

Source tables: exactly 32 in `public` plus exactly 26 in `metrics_private`.
New private destination: `"01_product_schema"`.

Strict exclusions: do not change, rename, truncate or delete original `public` and `metrics_private` tables, Model and Engineering schemas, or teammate-owned `feature_olap` and `product_source`.

## Applied migrations and live validation

- Stage A creates 58 private shadow tables with all original columns, identities, NOT NULL, CHECK, primary/unique and other indexes, 58 RLS-enabled tables; removes public grants. Exactly 107 indexes.
- Stage B1/B2 snapshots all 26 private and 27 smaller public tables, preserving existing identity values and reseeding cloned identity sequences.
- Stages B3-B6 snapshot the five large public tables, including events, in separate, non-destructive transactions.
- Stage C recreates and validates all 18 foreign-key constraints on target-only table relationships. No FKs to original tables.
- Stage D creates four private reporting views, with catalog verification of their table dependencies within the new schema.
- Initial shadow size about 780 MB. Source row/key parity: 57 of 58 tables exact at the time of verification. `metrics_private.retention_core_day_v4` gained one additional source row during continuing production refreshes.
- `retention_kpis`: exact JSON row match. `company_week_product_qa`: 4,329 rows on each side. `upload_type_coverage_qa`: 37 rows on each side. `events_no_test_v2`: 539,172 rows on each side.

## Not yet cut over

- Product ingestion: hourly `sync-incremental-hourly` still populates original `public` tables.
- Existing Product readers and refresh jobs still point at `public`/`metrics_private`. No Product production reader, writer, public RPC or cron job has been switched.
- Product SQL reporting functions: many remain in `public`; 81 refer explicitly to `metrics_private`. The new schema holds tables and four views only, not all reporting functions.
- Model's `bill_extraction_reporting_v1` joins `public.company_directory`. Preserve this compatibility when the Product cutover is designed.
- The new tables are static point-in-time copies. Source writes after the snapshots are not replicated automatically.

## Required next gates

1. Audit and clone Product read/report functions to private shadows, retaining public endpoint contracts and narrowly scoped grants.
2. Plan and test fresh-data synchronization of all 58 tables without degrading production ingestion. Reconcile the source-key drift after establishing a live-data strategy.
3. Verify correct event ingestion trigger semantics on the destination; copying the original event trigger was intentionally deferred to avoid side effects.
4. Validate full Overview, Companies, Retention, funnel, historical snapshot and per-member drilldown JSON parity.
5. Record original RPC, writer and cron definitions as rollback artifacts before cutover; switch only when all canaries and automated refreshes pass.
6. Keep legacy `public`/`metrics_private` data available throughout validation. Do not merge this draft PR as a production cutover.

## Engineering status

6 PM IST (12:30 UTC) post-cutover Jira sync completed successfully: Engineering sync ID 150, 20 issues, 45 history records, zero errors. Five-minute watchdog published snapshot ID 150 at 12:35 UTC.

## Confirmed live writer dependency, do not naively redirect

The active `sync-incremental` Supabase Edge Function (v11) uses the Supabase service-role client and the existing public RPCs `try_begin_incremental`, `upsert_mixpanel_events_detail`, `finish_incremental`, `refresh_retention`, `prune_product_snapshots`, `prune_funnel_members`, and `prune_overview_members`. It reads `public.export_watermarks` directly. This is **not** a single-schema SQL writer like Engineering's `jira-sync`, so changing a PostgreSQL `search_path` alone cannot switch Product ingestion. The production function, public RPC contracts, and existing hourly cron must remain unchanged until a deliberately designed and tested shadow writer path exists.

Supabase Security Advisor emits 58 informational `rls_enabled_no_policy` findings for new shadow tables. This is deliberate deny-by-default protection during staging: all 58 enable RLS and anon/authenticated have neither schema usage nor table SELECT. Reference: https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy.
