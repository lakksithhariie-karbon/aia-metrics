-- Remove only the guarded publication coordinator. No live pointer is changed.
DROP FUNCTION IF EXISTS "01_product_schema".try_publish_verified_overview_v1();
