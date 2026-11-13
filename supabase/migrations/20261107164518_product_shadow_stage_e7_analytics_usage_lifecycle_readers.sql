-- Product E7: stage two Product analytics endpoints that do not touch teammate schemas.
-- Both source functions are stable, security-invoker and read-only.
-- Product Analytics Features/OLAP depend on teammate-owned source schemas and remain excluded.
SET LOCAL lock_timeout='7s'; SET LOCAL statement_timeout='90s';
DO $copy$
DECLARE r record;d text;n integer:=0;
BEGIN
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
   WHERE s.nspname='01_product_schema')<>176 THEN
   RAISE EXCEPTION 'Unexpected Product shadow function count';END IF;
 FOR r IN SELECT p.oid,p.proname,p.prosecdef,p.provolatile
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN ('product_analytics_usage','product_analytics_lifecycle')
   ORDER BY p.proname
 LOOP
   IF r.prosecdef OR r.provolatile<>'s' THEN RAISE EXCEPTION 'Unexpected Product reader contract';END IF;
   d:=pg_get_functiondef(r.oid);
   IF d NOT LIKE 'CREATE OR REPLACE FUNCTION public.%'
      OR d NOT LIKE '%SET search_path TO ''public'', ''pg_temp''%'
      OR d LIKE '%feature_olap.%' OR d LIKE '%product_source.%'
   THEN RAISE EXCEPTION 'Unsupported Product analytics definition %',r.proname;END IF;
   d:=replace(d,'CREATE OR REPLACE FUNCTION public.','CREATE OR REPLACE FUNCTION "01_product_schema".');
   d:=replace(d,'public.company_directory','"01_product_schema".company_directory');
   d:=replace(d,'public.events','"01_product_schema".events');
   d:=replace(d,'SET search_path TO ''public'', ''pg_temp''',
       'SET search_path TO "01_product_schema", pg_catalog, pg_temp');
   IF d LIKE '%public.%' THEN RAISE EXCEPTION 'Legacy reference remains in %',r.proname;END IF;
   EXECUTE d;
   n:=n+1;
 END LOOP;
 IF n<>2 OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
    WHERE s.nspname='01_product_schema')<>178 THEN
    RAISE EXCEPTION 'Expected two analytics reader clones';END IF;
 EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "01_product_schema" FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher';
END $copy$;
