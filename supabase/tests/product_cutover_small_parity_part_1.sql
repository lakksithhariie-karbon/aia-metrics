-- Product pre-cutover parity, small tables, part 1/3.
-- READ ONLY. Exactly compare row content both directions; all counts should be zero.
-- Run the three small-table parts and the large-table test immediately before cutover.
SELECT 'metrics_private.company_calendar_month_module_usage' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."company_calendar_month_module_usage" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_calendar_month_module_usage" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_calendar_month_module_usage" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."company_calendar_month_module_usage" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.company_calendar_month_module_usage_v2' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."company_calendar_month_module_usage_v2" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_calendar_month_module_usage_v2" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_calendar_month_module_usage_v2" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."company_calendar_month_module_usage_v2" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.company_lifecycle_identity' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."company_lifecycle_identity" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_lifecycle_identity" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_lifecycle_identity" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."company_lifecycle_identity" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.company_lifecycle_meta' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."company_lifecycle_meta" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_lifecycle_meta" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_lifecycle_meta" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."company_lifecycle_meta" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.company_lifecycle_user' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."company_lifecycle_user" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_lifecycle_user" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_lifecycle_user" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."company_lifecycle_user" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.company_lifecycle_week_module_usage' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."company_lifecycle_week_module_usage" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_lifecycle_week_module_usage" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_lifecycle_week_module_usage" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."company_lifecycle_week_module_usage" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.company_month_module_usage' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."company_month_module_usage" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_month_module_usage" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_month_module_usage" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."company_month_module_usage" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.company_monthly_identity' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."company_monthly_identity" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_monthly_identity" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_monthly_identity" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."company_monthly_identity" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.company_monthly_meta' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."company_monthly_meta" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_monthly_meta" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_monthly_meta" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."company_monthly_meta" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.company_monthly_meta_v2' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."company_monthly_meta_v2" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_monthly_meta_v2" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_monthly_meta_v2" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."company_monthly_meta_v2" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.company_monthly_user' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."company_monthly_user" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_monthly_user" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_monthly_user" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."company_monthly_user" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.company_observed_user' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."company_observed_user" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_observed_user" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_observed_user" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."company_observed_user" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.company_reporting_identity' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."company_reporting_identity" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_reporting_identity" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_reporting_identity" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."company_reporting_identity" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.company_reporting_meta' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."company_reporting_meta" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_reporting_meta" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_reporting_meta" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."company_reporting_meta" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.overview_chart_summary_cache_v1' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."overview_chart_summary_cache_v1" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."overview_chart_summary_cache_v1" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."overview_chart_summary_cache_v1" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."overview_chart_summary_cache_v1" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.overview_independent_core_kpi_cache_v1' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."overview_independent_core_kpi_cache_v1" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."overview_independent_core_kpi_cache_v1" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."overview_independent_core_kpi_cache_v1" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."overview_independent_core_kpi_cache_v1" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.retention_activation_v2' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."retention_activation_v2" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."retention_activation_v2" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."retention_activation_v2" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."retention_activation_v2" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.retention_activation_v3' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."retention_activation_v3" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."retention_activation_v3" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."retention_activation_v3" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."retention_activation_v3" s) extra) AS extra_or_mismatched
ORDER BY source_table;
