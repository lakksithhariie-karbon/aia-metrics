-- Isolated rollback of the source-only private header generator.
-- No data or published snapshots are affected.
DROP FUNCTION IF EXISTS "01_product_schema".build_overview_feature_usage_headers_v1(timestamptz,timestamptz);
