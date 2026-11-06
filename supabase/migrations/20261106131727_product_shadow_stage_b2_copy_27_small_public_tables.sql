-- Product Stage B2: snapshot-copy 27 small public Product tables.
-- Leave five large tables for chunked copy. Source rows never modified.
SET LOCAL lock_timeout='6s';
SET LOCAL statement_timeout='240s';
DO $copy$
DECLARE r record; idcol record; copied bigint; actual bigint; maxid bigint; n int:=0;
BEGIN
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
     WHERE ns.nspname='public' AND c.relkind='r')<>32 THEN
     RAISE EXCEPTION 'Unexpected public Product table count'; END IF;
 FOR r IN SELECT c.relname tab, pg_total_relation_size(c.oid) bytes
          FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
          WHERE ns.nspname='public' AND c.relkind='r'
            AND pg_total_relation_size(c.oid)<12*1024*1024
          ORDER BY c.relname
 LOOP
   EXECUTE format('SELECT count(*) FROM %I.%I','01_product_schema',r.tab) INTO actual;
   IF actual<>0 THEN RAISE EXCEPTION 'Shadow table % is not empty',r.tab; END IF;
   EXECUTE format('INSERT INTO %I.%I OVERRIDING SYSTEM VALUE SELECT * FROM %I.%I',
            '01_product_schema',r.tab,'public',r.tab);
   GET DIAGNOSTICS copied=ROW_COUNT;
   EXECUTE format('SELECT count(*) FROM %I.%I','01_product_schema',r.tab) INTO actual;
   IF copied<>actual THEN RAISE EXCEPTION 'Copy validation failed for %',r.tab; END IF;
   FOR idcol IN SELECT a.attname col FROM pg_attribute a
                JOIN pg_class t ON t.oid=a.attrelid
                JOIN pg_namespace n ON n.oid=t.relnamespace
                WHERE n.nspname='01_product_schema' AND t.relname=r.tab
                  AND a.attnum>0 AND a.attidentity<>''
   LOOP
     EXECUTE format('SELECT max(%I) FROM %I.%I',idcol.col,'01_product_schema',r.tab) INTO maxid;
     IF maxid IS NOT NULL THEN
       PERFORM setval(pg_get_serial_sequence(format('%I.%I','01_product_schema',r.tab),
                                             idcol.col),maxid,true);
     END IF;
   END LOOP;
   n:=n+1;
 END LOOP;
 IF n<>27 THEN RAISE EXCEPTION 'Expected 27 small public tables, found %',n; END IF;
END $copy$;
