-- Remove only the new read-only Feature Usage source calculator.
-- No source events, snapshots, pointers, members, manifests or crons are touched.
DROP FUNCTION IF EXISTS "01_product_schema".build_overview_feature_usage_source_v1(
  timestamptz,timestamptz);
