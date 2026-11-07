-- Product Stage E2: six read-only Companies canaries in the private target.
-- Rebind product table names to shadow copies. Original pure public helpers
-- remain callable as needed until all helper dependencies are cloned.
SET LOCAL lock_timeout='6s';
SET LOCAL statement_timeout='120s';
SET LOCAL check_function_bodies=on;
DO $clone$
DECLARE r record; tab record; d text; n integer:=0;
BEGIN
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
     WHERE s.nspname='01_product_schema')<>14 THEN
   RAISE EXCEPTION 'Unexpected preexisting Product shadow function count';
 END IF;
 FOR r IN SELECT p.oid,p.proname FROM pg_proc p
    JOIN pg_namespace s ON s.oid=p.pronamespace
    WHERE s.nspname='public' AND p.proname=ANY(ARRAY[
      'read_companies_breakdown','read_companies_context','read_companies_snapshot',
      'read_companies_usage','read_company_names','read_company_users'
    ]) ORDER BY p.proname
 LOOP
   d:=pg_get_functiondef(r.oid);
   IF d NOT LIKE 'CREATE OR REPLACE FUNCTION public.%'
      OR d NOT LIKE '%LANGUAGE sql%' OR d NOT LIKE '%STABLE SECURITY DEFINER%'
      OR d NOT LIKE '%SET search_path TO ''public''%'
      OR d LIKE '%metrics_private.%' OR d LIKE '%product_source.%'
      OR d LIKE '%feature_olap.%' THEN
     RAISE EXCEPTION 'Unexpected Companies read-only source function %',r.proname;
   END IF;
   d:=replace(d,'CREATE OR REPLACE FUNCTION public.',
                'CREATE OR REPLACE FUNCTION "01_product_schema".');
   FOR tab IN SELECT c.relname FROM pg_class c JOIN pg_namespace s ON c.relnamespace=s.oid
      WHERE s.nspname='public' AND c.relkind='r'
      ORDER BY length(c.relname) DESC,c.relname
   LOOP
     d:=replace(d,'public.'||tab.relname,
                 '"01_product_schema".'||quote_ident(tab.relname));
   END LOOP;
   d:=replace(d,'SET search_path TO ''public''',
       'SET search_path TO "01_product_schema", public, pg_catalog, pg_temp');
   EXECUTE d;
   n:=n+1;
 END LOOP;
 IF n<>6 THEN RAISE EXCEPTION 'Expected six Companies readers, found %',n;END IF;
 EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "01_product_schema" FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher';
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
     WHERE s.nspname='01_product_schema' AND p.prosecdef)<>20
 THEN RAISE EXCEPTION 'Expected 20 private, SECURITY DEFINER, read-only shadows';END IF;
 IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
    WHERE s.nspname='01_product_schema' AND
     (has_function_privilege('anon',p.oid,'EXECUTE') OR
      has_function_privilege('authenticated',p.oid,'EXECUTE') OR
      has_function_privilege('service_role',p.oid,'EXECUTE')))
 THEN RAISE EXCEPTION 'Unexpected Product shadow RPC access'; END IF;
END $clone$;
