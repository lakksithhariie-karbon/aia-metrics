-- Product pre-cutover parity, small tables, part 3/3.
-- READ ONLY. Exactly compare row content both directions; all counts should be zero.
-- Run the three small-table parts and the large-table test immediately before cutover.
SELECT 'public.export_watermarks' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."export_watermarks" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."export_watermarks" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."export_watermarks" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."export_watermarks" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.person_day_action' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."person_day_action" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."person_day_action" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."person_day_action" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."person_day_action" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.product_funnel_drill' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."product_funnel_drill" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."product_funnel_drill" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."product_funnel_drill" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."product_funnel_drill" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.product_funnel_seal' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."product_funnel_seal" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."product_funnel_seal" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."product_funnel_seal" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."product_funnel_seal" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.product_overview_drill' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."product_overview_drill" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."product_overview_drill" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."product_overview_drill" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."product_overview_drill" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.product_overview_seal' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."product_overview_seal" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."product_overview_seal" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."product_overview_seal" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."product_overview_seal" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.product_publication' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."product_publication" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."product_publication" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."product_publication" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."product_publication" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.product_publication_current' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."product_publication_current" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."product_publication_current" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."product_publication_current" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."product_publication_current" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.product_publication_member' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."product_publication_member" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."product_publication_member" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."product_publication_member" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."product_publication_member" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.product_refresh_run' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."product_refresh_run" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."product_refresh_run" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."product_refresh_run" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."product_refresh_run" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.product_retention_build_lease' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."product_retention_build_lease" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."product_retention_build_lease" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."product_retention_build_lease" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."product_retention_build_lease" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.product_retention_period_seal' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."product_retention_period_seal" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."product_retention_period_seal" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."product_retention_period_seal" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."product_retention_period_seal" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.product_retention_summary_header' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."product_retention_summary_header" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."product_retention_summary_header" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."product_retention_summary_header" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."product_retention_summary_header" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.product_retention_summary_seal' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."product_retention_summary_seal" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."product_retention_summary_seal" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."product_retention_summary_seal" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."product_retention_summary_seal" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.product_snapshot' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."product_snapshot" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."product_snapshot" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."product_snapshot" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."product_snapshot" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.product_snapshot_current' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."product_snapshot_current" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."product_snapshot_current" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."product_snapshot_current" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."product_snapshot_current" s) extra) AS extra_or_mismatched
UNION ALL
SELECT 'public.retention_cells' AS source_table,
  (SELECT count(*) FROM (SELECT to_jsonb(s) AS rowval FROM "public"."retention_cells" s
   EXCEPT ALL SELECT to_jsonb(d) FROM "01_product_schema"."retention_cells" d) missing) AS missing_or_mismatched,
  (SELECT count(*) FROM (SELECT to_jsonb(d) AS rowval FROM "01_product_schema"."retention_cells" d
   EXCEPT ALL SELECT to_jsonb(s) FROM "public"."retention_cells" s) extra) AS extra_or_mismatched
ORDER BY source_table;
