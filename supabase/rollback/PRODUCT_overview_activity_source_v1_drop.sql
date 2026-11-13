-- Remove isolated source-only replay function. Never changes published rows.
DROP FUNCTION IF EXISTS "01_product_schema".build_overview_activity_source_v1(timestamptz,timestamptz);
