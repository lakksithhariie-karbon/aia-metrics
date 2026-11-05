# Domain schema mapping, Phase 0 inventory (2026-11-05)

**Status as of 2026-11-05:** `"03_infra_schema"` is now the canonical AWS cost source. The AWS Edge Function (v6), daily cron and public read-only RPC reference its two physical tables. Pre-cutover copies remain in `aia_infra` for rollback. Other numbered schemas remain empty; no other domains have been migrated.

**Strict exclusions:** `feature_olap` and `product_source` are teammate-owned. Do not rename, move, migrate, restructure, grant/revoke privileges, modify or drop any objects in either schema. Preserve functions that depend on them.

## Destination ownership

| Target schema | Scope | Planned tables | Regular views | Materialized views |
| --- | --- | ---: | ---: | ---: |
| `"01_product_schema"` | Customer, product usage, retention, product reporting/caches | 58 (excludes 7 teammate-owned source tables) | 4 | 0 |
| `"02_engineering_schema"` | Jira ingestion, engineering metrics, sprint dashboards | 20 | 39 | 4 |
| `"03_infra_schema"` | AWS costs, sync run lineage | 2 | 0 | 0 |
| `"04_model_schema"` | AI bill extraction costs, customer mapping, inference reporting | 2 | 1 | 0 |
| **Total in scope** | | **82** | **44** | **4** |

Note: `public.company_directory` remains the shared customer directory, planned under Product. `aia_infra.companies` is the separate AI extraction/model company mapping and belongs under Model.

Exact numbered schema identifiers begin with digits, so quote them in PostgreSQL SQL: `SELECT * FROM "03_infra_schema".aws_costs`.

Keep `public` as a minimal, backwards-compatible Data API/RPC entrypoint, even after domain storage moves. Do not expose the new schemas in the Supabase Data API or grant `anon`/ `authenticated` access without a separate security review. Supabase-managed schemas remain unchanged.

## Complete existing-table to future-schema map

Source paths are current for the in-scope objects. Infra is already canonical in the new schema; other targets are **future intended locations**. The seven excluded teammate-owned tables appear for reference only and must not be changed.

| Current table | Target schema | Planned action |
| --- | --- | --- |
| `public.client_company` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.company_activation` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.company_core_activity` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.company_day_action` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.company_directory` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.company_month_core` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.company_profile` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.company_week_action` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.company_week_product` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.company_week_value` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.events` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.export_watermarks` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.person_day_action` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_funnel_drill` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_funnel_member` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_funnel_seal` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_overview_drill` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_overview_member` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_overview_seal` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_publication` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_publication_current` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_publication_member` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_refresh_run` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_retention_build_lease` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_retention_period_drill` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_retention_period_seal` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_retention_summary_header` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_retention_summary_member` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_retention_summary_seal` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_snapshot` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.product_snapshot_current` | `01_product_schema` | Phase 4, compatibility APIs first |
| `public.retention_cells` | `01_product_schema` | Phase 4, compatibility APIs first |
| `metrics_private.company_calendar_month_module_usage` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.company_calendar_month_module_usage_v2` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.company_lifecycle_identity` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.company_lifecycle_meta` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.company_lifecycle_user` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.company_lifecycle_week_module_usage` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.company_month_module_usage` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.company_monthly_identity` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.company_monthly_meta` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.company_monthly_meta_v2` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.company_monthly_user` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.company_observed_user` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.company_reporting_identity` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.company_reporting_meta` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.overview_chart_summary_cache_v1` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.overview_independent_core_kpi_cache_v1` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.retention_activation_v2` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.retention_activation_v3` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.retention_activation_v4` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.retention_core_day_v3` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.retention_core_day_v4` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.retention_dashboard_meta_v3` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.retention_dashboard_meta_v4` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.retention_kpi_meta_v2` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.retention_month_core_v2` | `01_product_schema` | Phase 4, retain private data access |
| `metrics_private.retention_week_core_v2` | `01_product_schema` | Phase 4, retain private data access |
| `product_source.companies` | EXCLUDED | Teammate-owned. Do not move or alter |
| `product_source.membership_history` | EXCLUDED | Teammate-owned. Do not move or alter |
| `product_source.memberships` | EXCLUDED | Teammate-owned. Do not move or alter |
| `product_source.sync_runs` | EXCLUDED | Teammate-owned. Do not move or alter |
| `product_source.user_emails` | EXCLUDED | Teammate-owned. Do not move or alter |
| `product_source.users` | EXCLUDED | Teammate-owned. Do not move or alter |
| `product_source.voucher_feature_usage` | EXCLUDED | Teammate-owned. Do not move or alter |
| `jira.attachments_meta` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.comments` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.dashboard_snapshot_refresh_state` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.dim_canonical_values` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.field_value_map` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.issue_field_history` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.issue_field_values` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.issue_links` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.issue_types` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.issues` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.priorities` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.projects` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.raw_issues` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.sprint_issues` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.sprints` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.statuses` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.sync_errors` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.sync_log` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.users` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `jira.worklogs` | `02_engineering_schema` | Phase 3, migrate together with Jira logic |
| `"03_infra_schema".aws_cost_sync_runs` | `03_infra_schema` | DONE: canonical; original `aia_infra` backup retained |
| `"03_infra_schema".aws_costs` | `03_infra_schema` | DONE: canonical; original `aia_infra` backup retained |
| `aia_infra.bill_costs` | `04_model_schema` | Phase 2, bill extraction reporting compatibility |
| `aia_infra.companies` | `04_model_schema` | Phase 2, bill extraction reporting compatibility |

## Regular views (44)

| Existing view | Planned target |
| --- | --- |
| `public.company_week_product_qa` | `01_product_schema` |
| `public.retention_kpis` | `01_product_schema` |
| `public.upload_type_coverage_qa` | `01_product_schema` |
| `metrics_private.events_no_test_v2` | `01_product_schema` |
| `jira.issue_status_history` | `02_engineering_schema` |
| `jira.v_active_window_sprints` | `02_engineering_schema` |
| `jira.v_backlog_trend` | `02_engineering_schema` |
| `jira.v_backlog_trend_4w` | `02_engineering_schema` |
| `jira.v_backlog_trend_base` | `02_engineering_schema` |
| `jira.v_backlog_trend_latest` | `02_engineering_schema` |
| `jira.v_bug_health` | `02_engineering_schema` |
| `jira.v_bug_sla` | `02_engineering_schema` |
| `jira.v_cycle_time_distribution` | `02_engineering_schema` |
| `jira.v_dashboard_sprints` | `02_engineering_schema` |
| `jira.v_engineer_quality` | `02_engineering_schema` |
| `jira.v_field_hygiene` | `02_engineering_schema` |
| `jira.v_flow_counts` | `02_engineering_schema` |
| `jira.v_issue_current` | `02_engineering_schema` |
| `jira.v_issue_cycle_times` | `02_engineering_schema` |
| `jira.v_issue_detail` | `02_engineering_schema` |
| `jira.v_issue_flow_state` | `02_engineering_schema` |
| `jira.v_issue_normalized` | `02_engineering_schema` |
| `jira.v_issue_status_trail` | `02_engineering_schema` |
| `jira.v_label_counts` | `02_engineering_schema` |
| `jira.v_metric_cohorts_active_v1` | `02_engineering_schema` |
| `jira.v_org_reopen_rate` | `02_engineering_schema` |
| `jira.v_qa_queue` | `02_engineering_schema` |
| `jira.v_qa_rejection` | `02_engineering_schema` |
| `jira.v_qa_rejection_org` | `02_engineering_schema` |
| `jira.v_resolution_medians` | `02_engineering_schema` |
| `jira.v_sprint_commitment_pending` | `02_engineering_schema` |
| `jira.v_sprint_commitment_pending_summary` | `02_engineering_schema` |
| `jira.v_sprint_completion` | `02_engineering_schema` |
| `jira.v_sprint_discipline` | `02_engineering_schema` |
| `jira.v_sprint_drilldown` | `02_engineering_schema` |
| `jira.v_sprint_stage_summary` | `02_engineering_schema` |
| `jira.v_sprint_summary` | `02_engineering_schema` |
| `jira.v_sprint_throughput` | `02_engineering_schema` |
| `jira.v_stage_time` | `02_engineering_schema` |
| `jira.v_status_categories` | `02_engineering_schema` |
| `jira.v_sub_module_counts` | `02_engineering_schema` |
| `jira.v_sync_status` | `02_engineering_schema` |
| `jira.v_wip_by_status` | `02_engineering_schema` |
| `aia_infra.bill_extraction_reporting_v1` | `04_model_schema` |

## Materialized views (4)

| Existing materialized view | Planned target |
| --- | --- |
| `jira.metric_cohorts` | `02_engineering_schema` |
| `jira.mv_sprint_commitment_pending` | `02_engineering_schema` |
| `jira.mv_sprint_commitment_scope` | `02_engineering_schema` |
| `jira.v_module_counts` | `02_engineering_schema` |

## Dependency-safe migration sequence (future work)

1. **Infra (cutover complete 2026-11-05):** AWS Edge Function v6, cron guard, RPC and RLS-protected tables now use `"03_infra_schema"`. Original `aia_infra` tables remain as rollback copies. Dashboard and writer connection smoke checks passed; **confirm next scheduled daily run before retiring backups**.
2. **Model:** Update extraction reporting view and all private service-role RPCs, including references to `public.company_directory`, before moving `aia_infra.bill_costs` / `aia_infra.companies`.
3. **Engineering:** Inventory Jira synchronization jobs, stored routines, regular/materialized view dependencies and all external consumers. Change objects in dependency order; rename legacy `jira.v_module_counts` to a truthful `mv_` name only after callers are updated.
4. **Product:** Inventory stored functions, server requests, retention refreshes, RLS policies and publication generations. Source `public` (32 tables) + `metrics_private` (26) are the main move set. The 7 zero-row `product_source` tables are **explicitly excluded and teammate-owned**. Preserve their pipeline and any references to them; no migration or cleanup is authorized for that schema.

**Existing dependencies:** Live inspection identified 161 `public` functions containing explicitly qualified references to current schemas. PostgreSQL SQL routines, application fetches, Edge Functions and cron SQL may not be safely rewritten by simple `ALTER TABLE ... SET SCHEMA`. Update and regression-test these consumers first. Preserve previous RLS and least-privilege role grants on all migrated tables.

**Naming:** Keep descriptive snake_case names. Prefix regular views with `v_`, materialized views with `mv_` where practical. Consolidate old `retention_*_v2/v3/v4` objects only after verifying active callers. Do not remove empty `product_publication*` tables, since they are referenced by functions. Never delete production structures purely because their current row count is zero.

**Rollout gate:** Each phase requires source-to-target row/count checks, view/RPC checks, full-page production smoke tests, sync/cron checks, and a documented rollback. Complete one domain before the next.
