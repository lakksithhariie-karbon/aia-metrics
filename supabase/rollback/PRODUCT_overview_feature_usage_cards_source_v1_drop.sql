-- Drop only the private event-backed Feature Usage card calculator.
-- No active or archived snapshots, crons, source tables or pointers are affected.
DROP FUNCTION IF EXISTS "01_product_schema".build_overview_feature_usage_cards_source_v1(timestamptz,timestamptz);
