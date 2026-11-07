-- Product Stage B1: snapshot-copy 26 small metrics_private tables.
-- Never write to source tables, public reports, jobs, teammate-owned schemas.
SET LOCAL lock_timeout='6s';
SET LOCAL statement_timeout='240s';
DO $copy$
DECLARE r record; copied bigint; actual bigint; n int:=0;
BEGIN
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON c.relnamespace=n.oid
     WHERE n.nspname='metrics_private' AND c.relkind='r')<>26
    OR (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON c.relnamespace=n.oid
     WHERE n.nspname='01_product_schema' AND c.relkind='r' AND c.relrowsecurity)<>58 THEN
   RAISE EXCEPTION 'Unexpected Product inventory or privacy configuration';
 END IF;
 FOR r IN SELECT c.relname AS tab FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
           WHERE ns.nspname='metrics_private' AND c.relkind='r' ORDER BY c.relname
 LOOP
   EXECUTE format('SELECT count(*) FROM %I.%I','01_product_schema',r.tab) INTO actual;
   IF actual<>0 THEN RAISE EXCEPTION 'Target % already non-empty',r.tab; END IF;
   EXECUTE format('INSERT INTO %I.%I OVERRIDING SYSTEM VALUE SELECT * FROM %I.%I',
          '01_product_schema',r.tab,'metrics_private',r.tab);
   GET DIAGNOSTICS copied=ROW_COUNT;
   EXECUTE format('SELECT count(*) FROM %I.%I','01_product_schema',r.tab) INTO actual;
   IF actual<>copied THEN RAISE EXCEPTION 'Copy count mismatch on %',r.tab; END IF;
   n:=n+1;
 END LOOP;
 IF n<>26 THEN RAISE EXCEPTION 'Only % of 26 copied',n; END IF;
END $copy$;
