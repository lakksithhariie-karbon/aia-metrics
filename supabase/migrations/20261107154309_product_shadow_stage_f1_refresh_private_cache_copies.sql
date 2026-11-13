-- Product Stage F1: synchronize only 26 small private shadow cache tables.
-- No source tables, source functions, or production cron jobs are changed.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='240s';
DO $sync$
DECLARE r record; copied bigint; count_after bigint; n int:=0;
BEGIN
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
       WHERE s.nspname='01_product_schema' AND c.relkind='r' AND c.relrowsecurity)<>58 THEN
      RAISE EXCEPTION 'Target schema/RLS inventory invalid';END IF;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
       WHERE s.nspname='metrics_private' AND c.relkind='r')<>26 THEN
      RAISE EXCEPTION 'Private source inventory changed';END IF;
 IF (SELECT count(*) FROM pg_constraint c
     JOIN pg_class ref ON ref.oid=c.confrelid
     JOIN pg_namespace ns ON ns.oid=ref.relnamespace
     WHERE ns.nspname='01_product_schema' AND ref.relname IN
      (SELECT relname FROM pg_class x JOIN pg_namespace xn ON xn.oid=x.relnamespace
       WHERE xn.nspname='metrics_private' AND x.relkind='r') AND c.contype='f')<>0 THEN
     RAISE EXCEPTION 'Unexpected foreign key referencing private cache tables'; END IF;
 FOR r IN SELECT c.relname tab FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
   WHERE s.nspname='metrics_private' AND c.relkind='r' ORDER BY c.relname
 LOOP
   EXECUTE format('TRUNCATE TABLE %I.%I', '01_product_schema',r.tab);
   EXECUTE format('INSERT INTO %I.%I SELECT * FROM %I.%I',
     '01_product_schema',r.tab,'metrics_private',r.tab);
   GET DIAGNOSTICS copied=ROW_COUNT;
   EXECUTE format('SELECT count(*) FROM %I.%I','01_product_schema',r.tab) INTO count_after;
   IF copied<>count_after THEN RAISE EXCEPTION 'Shadow refresh mismatch for %',r.tab;END IF;
   n:=n+1;
 END LOOP;
 IF n<>26 THEN RAISE EXCEPTION 'Expected 26 refreshed caches';END IF;
END $sync$;
