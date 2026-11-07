-- Product Stage E6: private copies of remaining immutable metric helpers,
-- and rebind existing shadow readers to these private helpers.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='240s';
SET LOCAL check_function_bodies=off;
DO $rebind$
DECLARE r record; a record; d text; old text; n integer:=0; updated integer:=0;
BEGIN
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
        WHERE ns.nspname='01_product_schema')<>127 THEN RAISE EXCEPTION 'Expected 127 target functions';END IF;
 FOR r IN SELECT p.oid,p.proname,p.provolatile,p.prosecdef FROM pg_proc p
     JOIN pg_namespace ns ON ns.oid=p.pronamespace
     WHERE ns.nspname='public' AND p.proname IN
        ('is_core_activity','is_qualifying_sync','is_successful_integration','is_internal_email')
     ORDER BY p.proname
 LOOP
   IF r.provolatile<>'i' OR r.prosecdef THEN
      RAISE EXCEPTION 'Unexpected mutable metric helper %',r.proname;END IF;
   d:=pg_get_functiondef(r.oid);
   IF d NOT LIKE 'CREATE OR REPLACE FUNCTION public.%'
      OR d LIKE '%feature_olap.%' OR d LIKE '%product_source.%'
   THEN RAISE EXCEPTION 'Invalid metric helper source';END IF;
   d:=replace(d,'CREATE OR REPLACE FUNCTION public.','CREATE OR REPLACE FUNCTION "01_product_schema".');
   EXECUTE d;
   n:=n+1;
 END LOOP;
 IF n<>4 THEN RAISE EXCEPTION 'Four helpers required';END IF;
 FOR r IN SELECT p.oid,p.proname FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='01_product_schema' ORDER BY p.proname
 LOOP
   d:=pg_get_functiondef(r.oid);old:=d;
   FOR a IN SELECT proname FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
         WHERE ns.nspname='01_product_schema' AND
          (p.proname LIKE 'company_%' OR
           p.proname IN ('is_core_activity','is_qualifying_sync','is_successful_integration','is_internal_email'))
   LOOP
      d:=replace(d,'public.'||a.proname||'(',
                   '"01_product_schema".'||quote_ident(a.proname)||'(');
   END LOOP;
   IF d<>old THEN EXECUTE d;updated:=updated+1;END IF;
 END LOOP;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
       WHERE ns.nspname='01_product_schema')<>131 THEN
      RAISE EXCEPTION 'Unexpected target helper count';END IF;
 EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "01_product_schema" FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher';
 IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
    WHERE ns.nspname='01_product_schema' AND
      (has_function_privilege('anon',p.oid,'EXECUTE') OR
       has_function_privilege('authenticated',p.oid,'EXECUTE') OR
       has_function_privilege('service_role',p.oid,'EXECUTE'))) THEN
     RAISE EXCEPTION 'Shadow Product helper exposure';END IF;
 RAISE NOTICE 'Rebound % private reporting helpers',updated;
END $rebind$;
