-- Removing staging orchestrator only, no snapshot/reader writes.
DROP FUNCTION IF EXISTS "01_product_schema".stage_feature_usage_generation_v1(timestamptz);
