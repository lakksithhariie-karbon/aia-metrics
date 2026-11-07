-- Product pre-cutover exact large table verification. READ ONLY.
-- These five tables exceed the size threshold used by small-table SQL checks.
-- All values must be zero. Compare full JSONB payload with source and detect extra target PKs.
SELECT 'events' AS table_name,
 (SELECT count(*) FROM public."events" s LEFT JOIN "01_product_schema"."events" d ON s."insert_id"=d."insert_id"
 WHERE d."insert_id" IS NULL OR to_jsonb(s) IS DISTINCT FROM to_jsonb(d)) AS source_missing_or_mismatched,
 (SELECT count(*) FROM "01_product_schema"."events" d LEFT JOIN public."events" s ON s."insert_id"=d."insert_id"
 WHERE s."insert_id" IS NULL) AS shadow_extras
UNION ALL
SELECT 'product_funnel_member' AS table_name,
 (SELECT count(*) FROM public."product_funnel_member" s LEFT JOIN "01_product_schema"."product_funnel_member" d ON s."snapshot_id"=d."snapshot_id" AND s."node_key"=d."node_key" AND s."tab"=d."tab" AND s."company_id"=d."company_id"
 WHERE d."snapshot_id" IS NULL OR to_jsonb(s) IS DISTINCT FROM to_jsonb(d)) AS source_missing_or_mismatched,
 (SELECT count(*) FROM "01_product_schema"."product_funnel_member" d LEFT JOIN public."product_funnel_member" s ON s."snapshot_id"=d."snapshot_id" AND s."node_key"=d."node_key" AND s."tab"=d."tab" AND s."company_id"=d."company_id"
 WHERE s."snapshot_id" IS NULL) AS shadow_extras
UNION ALL
SELECT 'product_overview_member' AS table_name,
 (SELECT count(*) FROM public."product_overview_member" s LEFT JOIN "01_product_schema"."product_overview_member" d ON s."snapshot_id"=d."snapshot_id" AND s."kind"=d."kind" AND s."drill_key"=d."drill_key" AND s."tab"=d."tab" AND s."member_id"=d."member_id"
 WHERE d."snapshot_id" IS NULL OR to_jsonb(s) IS DISTINCT FROM to_jsonb(d)) AS source_missing_or_mismatched,
 (SELECT count(*) FROM "01_product_schema"."product_overview_member" d LEFT JOIN public."product_overview_member" s ON s."snapshot_id"=d."snapshot_id" AND s."kind"=d."kind" AND s."drill_key"=d."drill_key" AND s."tab"=d."tab" AND s."member_id"=d."member_id"
 WHERE s."snapshot_id" IS NULL) AS shadow_extras
UNION ALL
SELECT 'product_retention_period_drill' AS table_name,
 (SELECT count(*) FROM public."product_retention_period_drill" s LEFT JOIN "01_product_schema"."product_retention_period_drill" d ON s."snapshot_id"=d."snapshot_id" AND s."drill_key"=d."drill_key"
 WHERE d."snapshot_id" IS NULL OR to_jsonb(s) IS DISTINCT FROM to_jsonb(d)) AS source_missing_or_mismatched,
 (SELECT count(*) FROM "01_product_schema"."product_retention_period_drill" d LEFT JOIN public."product_retention_period_drill" s ON s."snapshot_id"=d."snapshot_id" AND s."drill_key"=d."drill_key"
 WHERE s."snapshot_id" IS NULL) AS shadow_extras
UNION ALL
SELECT 'product_retention_summary_member' AS table_name,
 (SELECT count(*) FROM public."product_retention_summary_member" s LEFT JOIN "01_product_schema"."product_retention_summary_member" d ON s."snapshot_id"=d."snapshot_id" AND s."drill"=d."drill" AND s."position"=d."position"
 WHERE d."snapshot_id" IS NULL OR to_jsonb(s) IS DISTINCT FROM to_jsonb(d)) AS source_missing_or_mismatched,
 (SELECT count(*) FROM "01_product_schema"."product_retention_summary_member" d LEFT JOIN public."product_retention_summary_member" s ON s."snapshot_id"=d."snapshot_id" AND s."drill"=d."drill" AND s."position"=d."position"
 WHERE s."snapshot_id" IS NULL) AS shadow_extras
ORDER BY table_name;
