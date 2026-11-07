-- Product Stage B5: copy large overview member snapshot, no source writes.
SET LOCAL lock_timeout='6s'; SET LOCAL statement_timeout='600s';
DO $copy$ DECLARE n bigint; existing bigint;
BEGIN
 SELECT count(*) INTO existing FROM "01_product_schema".product_overview_member;
 IF existing<>0 THEN RAISE EXCEPTION 'Target overview membership already populated'; END IF;
 INSERT INTO "01_product_schema".product_overview_member SELECT * FROM public.product_overview_member;
 GET DIAGNOSTICS n=ROW_COUNT;
 SELECT count(*) INTO existing FROM "01_product_schema".product_overview_member;
 IF n<>existing THEN RAISE EXCEPTION 'Overview membership copy count mismatch'; END IF;
END $copy$;
