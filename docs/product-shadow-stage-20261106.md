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

## Stage E: reporting readers, 6 November 2026

The database has applied three independent Stage E migrations:
- `20261106133857_product_shadow_stage_e1_private_leaf_read_rpcs`
- `20261106134434_product_shadow_stage_e2_private_companies_read_rpcs`
- `20261106135113_product_shadow_stage_e3_retention_and_companies_read_rpcs`

All 27 staged functions are in the private Product schema. Production read functions remain unchanged. All new functions are private, with no anonymous, authenticated, or service-role EXECUTE grant.

Validation: 13 initial Product/Funnel/Overview calls exactly matched production; 5 of 6 Companies calls matched exactly, with the sixth (Companies context) matching after order-independent comparison of all 4,479 directory JSON items. Five of seven subsequent Retention/Companies calls matched exactly. `read_retention_dashboard_v5_base` and `read_retention_dashboard_v5` still differ because the staged Retention data is behind live source refreshes. Source Retention V4 watermark: 13:05 UTC. Staged copy: 12:05 UTC. Do not cut over until a live-sync mechanism and complete parity verification are in place.

The Stage E SQL is currently recorded in the Supabase migration history. The corresponding SQL files must be synchronized into this PR before it can be merged. The PR remains draft.

## November 7 reconciliation and reader coverage

- The private numbered schema has 58 tables, four views and 178 functions. The public production reporting functions and original 8 Product cron jobs are not redirected.
- All **105** Product `public.read_*` RPCs have shadow equivalents. Two additional Product Analytics RPCs, `product_analytics_usage` and `product_analytics_lifecycle`, are privately cloned. `product_analytics_features` and `product_analytics_olap` retain references to teammate-owned `product_source` and `feature_olap`, so they remain deliberately untouched.
- `read_retention_dashboard_v5`, Overview main charts/KPIs/Adoption/Workflow/Friction, Companies grids and populated drilldowns passed representative source/shadow parity checks. Product Analytics Lifecycle matched exactly; Product Analytics Usage data in `pairs` and `rows` matched exactly, while only `meta.source` differs, from `public.events` to `"01_product_schema".events`.
- H1-H4 created a guarded, independent legacy-to-shadow reconciler. The 30-minute `product-shadow-reconcile-2838` cron job ID 47 ran successfully; a manual call returned `status=ok` for both generations and hot data.
- H5/H6 replaced all private cache `TRUNCATE` operations with guarded row-level MERGE/DELETE on 39 small tables, including formerly omitted `retention_cells`. This prevents table-wide read locks during later reader cutover. Incremental and full manual reconciliation calls passed.
- H7 schedules a separate daily full event reconciliation at 03:08 UTC to capture property edits older than seven days. Its first scheduled execution is not yet independently confirmed.
- Post-reconciliation, **all 53 small tables matched row-for-row, both directions**, including non-key column content. The remaining 5 large tables had matching row counts and full primary-key sets. This is not yet a full byte-for-byte payload comparison for all five.
- 12 rollback SQL files preserve the precise original definitions of all 105 public Product reader RPCs; separate rollback files preserve original Usage/Lifecycle analytics RPCs and all 8 existing Product cron commands.
- All target functions remain inaccessible to `anon`, `authenticated`, and `service_role`; no permissions were extended to teammate-owned schemas.

### Production cutover is NOT complete

The original Supabase Edge function `sync-incremental` still writes via public RPCs, and `companies-dashboard` still directly reads `public` tables through the Data API. Model reporting also joins `public.company_directory`. The new shadow reflects legacy ingestion on a schedule, rather than being the canonical writer.

Before switching any public RPCs:
1. Confirm the post-upgrade cron job independently after its next scheduled run and record the function's actual `status`, not just `cron.job_run_details.status`.
2. Complete populated-data edge-case parity on Companies, Retention, historical and Product Analytics drilldowns and validate the payload of large generations.
3. Decide the final ingestion ownership and direct-Data-API client routing, including the `companies-dashboard` Edge function. Do not leave any untracked dependency on legacy public Product data.
4. Dry-run the public proxy migration with the captured restore files and check all function signatures and EXECUTE grants.
5. Only then perform a guarded production cutover, smoke-test Vercel/dashboard routes and actual scheduled ingestion, and retain legacy tables for rollback.

Do not mark Product migration complete or merge this draft PR until these gates pass.
