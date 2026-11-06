-- Product Stage B3: copy large retention member/drill snapshot tables.
SET LOCAL lock_timeout='6s'; SET LOCAL statement_timeout='600s';
DO $copy$
DECLARE tab text; cnt bigint; actual bigint;
BEGIN
 FOREACH tab IN ARRAY ARRAY['product_retention_summary_member','product_retention_period_drill'] LOOP
   EXECUTE format('SELECT count(*) FROM %I.%I','01_product_schema',tab) INTO actual;
   IF actual<>0 THEN RAISE EXCEPTION 'Shadow retention table % was already populated',tab; END IF;
   EXECUTE format('INSERT INTO %I.%I SELECT * FROM public.%I',
             '01_product_schema',tab,tab);
   GET DIAGNOSTICS cnt=ROW_COUNT;
   EXECUTE format('SELECT count(*) FROM %I.%I','01_product_schema',tab) INTO actual;
   IF cnt<>actual THEN RAISE EXCEPTION 'Shadow copy mismatch for %',tab; END IF;
 END LOOP;
END $copy$;
