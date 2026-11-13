-- Product Stage E4: private helper functions required by reporting readers.
-- Only new Product-schema functions created. No source schema objects modified.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='180s';
SET LOCAL check_function_bodies=off;
DO $clone$
DECLARE r record; tab record; fn record; d text; n integer:=0;
BEGIN
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace x ON x.oid=p.pronamespace
     WHERE x.nspname='01_product_schema')<>27 THEN
   RAISE EXCEPTION 'Product reader stage E3 prerequisite count failed';
 END IF;
 FOR r IN
   SELECT p.oid,p.proname,ns.nspname src,p.provolatile,p.prosecdef,l.lanname
   FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   JOIN pg_language l ON l.oid=p.prolang
   WHERE (ns.nspname='public' AND
          (p.proname LIKE 'company_%' OR p.proname LIKE 'overview_%'))
      OR (ns.nspname='metrics_private' AND p.proname IN
           ('company_work_module_v2','is_retention_internal_email_v2'))
   ORDER BY CASE WHEN p.proname LIKE 'company_%' THEN 1 WHEN ns.nspname='metrics_private' THEN 2 ELSE 3 END,p.proname
 LOOP
   IF r.src='public' AND r.proname LIKE 'overview_%' AND
     (r.lanname<>'sql' OR r.provolatile<>'s' OR NOT r.prosecdef) THEN
     RAISE EXCEPTION 'Unexpected overview helper definition %',r.proname;
   ELSIF (r.proname LIKE 'company_%' OR r.src='metrics_private') AND r.provolatile<>'i' THEN
     RAISE EXCEPTION 'Unexpected non-immutable helper %',r.proname;
   END IF;
   d:=pg_get_functiondef(r.oid);
   IF d LIKE '%feature_olap.%' OR d LIKE '%product_source.%' THEN
       RAISE EXCEPTION 'Cross-team function dependency not allowed %',r.proname;
   END IF;
   d:=replace(d,'CREATE OR REPLACE FUNCTION '||r.src||'.',
       'CREATE OR REPLACE FUNCTION "01_product_schema".');
   FOR tab IN SELECT s.nspname sc,c.relname nm FROM pg_class c
      JOIN pg_namespace s ON s.oid=c.relnamespace
      WHERE s.nspname IN ('public','metrics_private') AND c.relkind IN ('r','v')
      ORDER BY length(c.relname) DESC,c.relname
   LOOP
     d:=replace(d,tab.sc||'.'||tab.nm,
                   '"01_product_schema".'||quote_ident(tab.nm));
   END LOOP;
   FOR fn IN SELECT p.proname nm,s.nspname sc FROM pg_proc p
        JOIN pg_namespace s ON s.oid=p.pronamespace
        WHERE (s.nspname='public' AND (p.proname LIKE 'company_%' OR p.proname LIKE 'overview_%'))
           OR (s.nspname='metrics_private' AND p.proname IN
               ('company_work_module_v2','is_retention_internal_email_v2'))
       ORDER BY length(p.proname) DESC
   LOOP
     d:=replace(d,fn.sc||'.'||fn.nm||'(',
                '"01_product_schema".'||quote_ident(fn.nm)||'(');
   END LOOP;
   d:=replace(d,'SET search_path TO ''public'', ''metrics_private'', ''pg_temp''',
                 'SET search_path TO "01_product_schema", public, pg_catalog, pg_temp');
   EXECUTE d;
   n:=n+1;
 END LOOP;
 IF n<>21 THEN RAISE EXCEPTION 'Expected 21 helpers, found %',n;END IF;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
        WHERE ns.nspname='01_product_schema')<>48 THEN
      RAISE EXCEPTION 'Unexpected shadow helper count'; END IF;
 EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "01_product_schema" FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher';
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
     WHERE ns.nspname='01_product_schema' AND
       (has_function_privilege('anon',p.oid,'EXECUTE') OR
        has_function_privilege('authenticated',p.oid,'EXECUTE') OR
        has_function_privilege('service_role',p.oid,'EXECUTE'))) THEN
      RAISE EXCEPTION 'Shadow helper privacy check failed';END IF;
END $clone$;
