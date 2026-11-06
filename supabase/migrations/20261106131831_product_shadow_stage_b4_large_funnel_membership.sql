-- Product Stage B4: copy large funnel membership snapshot, source read-only.
SET LOCAL lock_timeout='6s'; SET LOCAL statement_timeout='600s';
DO $copy$ DECLARE n bigint; existing bigint;
BEGIN
 SELECT count(*) INTO existing FROM "01_product_schema".product_funnel_member;
 IF existing<>0 THEN RAISE EXCEPTION 'Target funnel membership already populated'; END IF;
 INSERT INTO "01_product_schema".product_funnel_member SELECT * FROM public.product_funnel_member;
 GET DIAGNOSTICS n=ROW_COUNT;
 SELECT count(*) INTO existing FROM "01_product_schema".product_funnel_member;
 IF n<>existing THEN RAISE EXCEPTION 'Funnel membership copy count mismatch'; END IF;
END $copy$;
