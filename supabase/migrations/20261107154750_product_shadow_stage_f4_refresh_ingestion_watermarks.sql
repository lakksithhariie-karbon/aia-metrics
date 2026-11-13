-- Product Stage F4: synchronize shadow export watermark metadata.
-- Does not mutate source ingestion state.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='60s';
DO $sync$
DECLARE n bigint;
BEGIN
 IF EXISTS(SELECT 1 FROM pg_constraint co JOIN pg_class c ON c.oid=co.confrelid
      JOIN pg_namespace ns ON ns.oid=c.relnamespace
      WHERE ns.nspname='01_product_schema' AND c.relname='export_watermarks' AND co.contype='f')
 THEN RAISE EXCEPTION 'Unexpected inbound shadow FK';END IF;
 TRUNCATE TABLE "01_product_schema".export_watermarks;
 INSERT INTO "01_product_schema".export_watermarks SELECT * FROM public.export_watermarks;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>2 OR (SELECT count(*) FROM "01_product_schema".export_watermarks)<>n
 THEN RAISE EXCEPTION 'Shadow watermark source discrepancy';END IF;
END $sync$;
