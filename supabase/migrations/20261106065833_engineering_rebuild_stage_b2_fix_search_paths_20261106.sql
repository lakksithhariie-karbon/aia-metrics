-- Stage B2: fix numeric-leading schema search_path quoting in cloned functions.
-- PostgreSQL's CREATE FUNCTION "SET search_path TO '"02_schema"'" wraps the
-- identifier in a second quoting layer. Use a SQL-quoted identifier instead.
-- This changes ONLY the new "02_engineering_schema" routine settings.
SET LOCAL lock_timeout = '8s';
DO $fix$
DECLARE r record; n integer:=0;
BEGIN
 FOR r IN SELECT p.oid FROM pg_proc p
   WHERE p.pronamespace='02_engineering_schema'::regnamespace
     AND EXISTS(SELECT 1 FROM unnest(p.proconfig) s
                WHERE s LIKE 'search_path=%02_engineering_schema%')
 LOOP
   EXECUTE format('ALTER FUNCTION %s SET search_path TO "02_engineering_schema", public, pg_catalog',
                  r.oid::regprocedure);
   n:=n+1;
 END LOOP;
 IF n<20 OR n>33 THEN RAISE EXCEPTION 'Unexpected number of search paths fixed: %',n; END IF;
 IF EXISTS (SELECT 1 FROM pg_proc p
   WHERE p.pronamespace='02_engineering_schema'::regnamespace
     AND EXISTS(SELECT 1 FROM unnest(p.proconfig) s
       WHERE s LIKE 'search_path=%02_engineering_schema%'
         AND s NOT LIKE 'search_path="02_engineering_schema",%'))
 THEN RAISE EXCEPTION 'Invalid nested schema quoting remains'; END IF;
END;
$fix$;
