-- Remove isolated Friction read-only builders only. No data/pointers touched.
DROP FUNCTION IF EXISTS "01_product_schema".build_overview_friction_cards_v1(timestamptz,timestamptz);
DROP FUNCTION IF EXISTS "01_product_schema".build_overview_friction_headers_v1(timestamptz,timestamptz);
DROP FUNCTION IF EXISTS "01_product_schema".build_overview_friction_population_v1(timestamptz,timestamptz);
DROP FUNCTION IF EXISTS "01_product_schema".build_overview_friction_payload_v1(timestamptz,timestamptz);
