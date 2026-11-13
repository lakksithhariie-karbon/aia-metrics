-- Product Stage E5b: clone remaining 78 private reporting readers.
-- Public production functions and teammate schemas remain unmodified.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='240s';
SET LOCAL check_function_bodies=off;
DO $clone$
DECLARE rec record; t record; f record; d text; n integer:=0; expected integer;
BEGIN
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
       WHERE ns.nspname='01_product_schema')<>49 THEN
      RAISE EXCEPTION 'Unexpected Product E5a prerequisite function inventory';END IF;
 SELECT count(*) INTO expected FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
 WHERE ns.nspname='public' AND p.proname LIKE 'read_%'
   AND p.proname NOT LIKE 'read_jira_%'
   AND p.proname NOT LIKE 'read_ai_%'
   AND p.proname NOT LIKE 'read_infra_%';
 IF expected<>105 THEN RAISE EXCEPTION 'Unexpected Product read source inventory %',expected;END IF;
 FOR rec IN SELECT p.oid,p.proname,p.prosecdef,p.provolatile
   FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public' AND p.proname LIKE 'read_%'
     AND p.proname NOT LIKE 'read_jira_%'
     AND p.proname NOT LIKE 'read_ai_%'
     AND p.proname NOT LIKE 'read_infra_%'
     AND NOT EXISTS (SELECT 1 FROM pg_proc x JOIN pg_namespace sn ON sn.oid=x.pronamespace
                  WHERE sn.nspname='01_product_schema' AND x.proname=p.proname)
   ORDER BY p.proname
 LOOP
   IF NOT rec.prosecdef OR rec.provolatile<>'s' THEN
      RAISE EXCEPTION 'Non-STABLE or non-private Product reader %',rec.proname;END IF;
   d:=pg_get_functiondef(rec.oid);
   IF d NOT LIKE 'CREATE OR REPLACE FUNCTION public.%'
     OR d LIKE '%feature_olap.%' OR d LIKE '%product_source.%' THEN
      RAISE EXCEPTION 'Unsupported definition of Product reader %',rec.proname;END IF;
   d:=replace(d,'CREATE OR REPLACE FUNCTION public.',
            'CREATE OR REPLACE FUNCTION "01_product_schema".');
   FOR t IN SELECT sn.nspname sc,c.relname nm FROM pg_class c JOIN pg_namespace sn ON sn.oid=c.relnamespace
     WHERE sn.nspname IN('public','metrics_private') AND c.relkind IN('r','v')
     ORDER BY length(c.relname) DESC,c.relname
   LOOP
     d:=replace(d,t.sc||'.'||t.nm,
         '"01_product_schema".'||quote_ident(t.nm));
   END LOOP;
   FOR f IN SELECT p.proname nm, ns.nspname sc FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
     WHERE (ns.nspname='public' AND
              ((p.proname LIKE 'read_%' AND p.proname NOT LIKE 'read_jira_%'
                      AND p.proname NOT LIKE 'read_ai_%' AND p.proname NOT LIKE 'read_infra_%')
                OR p.proname LIKE 'company_%' OR p.proname LIKE 'overview_%'))
         OR (ns.nspname='metrics_private' AND
                p.proname IN ('company_work_module_v2','is_retention_internal_email_v2','read_overview_chart_summary_cached_v1'))
      ORDER BY length(p.proname) DESC
   LOOP
     d:=replace(d,f.sc||'.'||f.nm||'(',
            '"01_product_schema".'||quote_ident(f.nm)||'(');
   END LOOP;
   d:=replace(d,'SET search_path TO ''public'', ''metrics_private'', ''pg_temp''',
       'SET search_path TO "01_product_schema", public, pg_catalog, pg_temp');
   d:=replace(d,'SET search_path TO ''public''',
       'SET search_path TO "01_product_schema", public, pg_catalog, pg_temp');
   IF d LIKE '%metrics_private.%' OR d LIKE '%public.read_%'
      OR d LIKE '%public.overview_%' OR d LIKE '%public.company_%' THEN
      RAISE EXCEPTION 'Unrebound Product source dependency in %',rec.proname;
   END IF;
   EXECUTE d;
   n:=n+1;
 END LOOP;
 IF n<>78 THEN RAISE EXCEPTION 'Expected 78 reporting clones, obtained %',n; END IF;
 EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "01_product_schema" FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher';
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
       WHERE ns.nspname='01_product_schema')<>127
 THEN RAISE EXCEPTION 'Unexpected Product reader count after E5b';END IF;
 IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
    WHERE ns.nspname='01_product_schema' AND
      (has_function_privilege('anon',p.oid,'EXECUTE')
      OR has_function_privilege('authenticated',p.oid,'EXECUTE')
      OR has_function_privilege('service_role',p.oid,'EXECUTE')))
 THEN RAISE EXCEPTION 'Product shadow function access violation';END IF;
END $clone$;
