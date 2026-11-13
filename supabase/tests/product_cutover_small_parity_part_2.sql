-- Product pre-cutover parity, small tables, part 2/3.
-- READ ONLY. Exactly compare row content both directions; all counts should be zero.
-- Run the three small-table parts and the large-table test immediately before cutover.
SELECT 'metrics_private.retention_activation_v4' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."retention_activation_v4" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."retention_activation_v4" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."retention_activation_v4" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."retention_activation_v4" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.retention_core_day_v3' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."retention_core_day_v3" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."retention_core_day_v3" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."retention_core_day_v3" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."retention_core_day_v3" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.retention_core_day_v4' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."retention_core_day_v4" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."retention_core_day_v4" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."retention_core_day_v4" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."retention_core_day_v4" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.retention_dashboard_meta_v3' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."retention_dashboard_meta_v3" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."retention_dashboard_meta_v3" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."retention_dashboard_meta_v3" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."retention_dashboard_meta_v3" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.retention_dashboard_meta_v4' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."retention_dashboard_meta_v4" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."retention_dashboard_meta_v4" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."retention_dashboard_meta_v4" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."retention_dashboard_meta_v4" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.retention_kpi_meta_v2' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."retention_kpi_meta_v2" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."retention_kpi_meta_v2" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."retention_kpi_meta_v2" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."retention_kpi_meta_v2" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.retention_month_core_v2' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."retention_month_core_v2" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."retention_month_core_v2" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."retention_month_core_v2" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."retention_month_core_v2" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'metrics_private.retention_week_core_v2' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "metrics_private"."retention_week_core_v2" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."retention_week_core_v2" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."retention_week_core_v2" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "metrics_private"."retention_week_core_v2" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.client_company' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."client_company" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."client_company" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."client_company" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."client_company" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.company_activation' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."company_activation" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_activation" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_activation" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."company_activation" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.company_core_activity' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."company_core_activity" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_core_activity" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_core_activity" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."company_core_activity" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.company_day_action' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."company_day_action" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_day_action" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_day_action" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."company_day_action" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.company_directory' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."company_directory" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_directory" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_directory" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."company_directory" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.company_month_core' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."company_month_core" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_month_core" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_month_core" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."company_month_core" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.company_profile' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."company_profile" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_profile" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_profile" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."company_profile" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.company_week_action' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."company_week_action" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_week_action" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_week_action" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."company_week_action" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.company_week_product' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."company_week_product" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_week_product" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_week_product" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."company_week_product" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.company_week_value' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."company_week_value" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."company_week_value" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."company_week_value" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."company_week_value" s) extra) AS extra_or_mismatched
ORDER BY source_table;
