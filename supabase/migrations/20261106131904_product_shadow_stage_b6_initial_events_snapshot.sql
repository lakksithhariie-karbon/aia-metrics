-- Product Stage B6: initial consistent statement-snapshot of events into private shadow.
-- NEVER mutate source public.events. Original ingestion and trigger remain live.
SET LOCAL lock_timeout='6s'; SET LOCAL statement_timeout='1200s';
DO $copy$ DECLARE copied bigint; actual bigint;
BEGIN
 SELECT count(*) INTO actual FROM "01_product_schema".events;
 IF actual<>0 THEN RAISE EXCEPTION 'Product shadow events unexpectedly populated'; END IF;
 IF EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
            JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='01_product_schema' AND c.relname='events' AND NOT t.tgisinternal)
 THEN RAISE EXCEPTION 'Product shadow events has a side-effect trigger'; END IF;
 INSERT INTO "01_product_schema".events SELECT * FROM public.events;
 GET DIAGNOSTICS copied=ROW_COUNT;
 SELECT count(*) INTO actual FROM "01_product_schema".events;
 IF copied<>actual OR copied<500000 THEN RAISE EXCEPTION 'Product event snapshot count mismatch'; END IF;
END $copy$;
