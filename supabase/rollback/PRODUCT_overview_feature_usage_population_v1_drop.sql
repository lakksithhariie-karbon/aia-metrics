-- Drop only the read-only source membership generator; preserve all existing data.
DROP FUNCTION IF EXISTS "01_product_schema".build_overview_feature_usage_population_v1(timestamptz,timestamptz);
