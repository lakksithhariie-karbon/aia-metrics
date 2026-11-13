-- Remove isolated Module Mix read-only builders only. No data/pointers touched.
DROP FUNCTION IF EXISTS "01_product_schema".build_overview_module_mix_cards_v1(timestamptz,timestamptz);
DROP FUNCTION IF EXISTS "01_product_schema".build_overview_module_mix_headers_v1(timestamptz,timestamptz);
DROP FUNCTION IF EXISTS "01_product_schema".build_overview_module_mix_population_v1(timestamptz,timestamptz);
DROP FUNCTION IF EXISTS "01_product_schema".build_overview_module_mix_payload_v1(timestamptz,timestamptz);
