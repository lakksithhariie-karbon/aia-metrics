-- Product Stage E3: independent Retention and Companies read-only shadow functions.
-- All DDL is in "01_product_schema". Original Product reports and jobs stay untouched.
SET LOCAL lock_timeout='6s';
SET LOCAL statement_timeout='160s';
SET LOCAL check_function_bodies=on;
DO $clone$
DECLARE r record; tab record; d text; n integer:=0;
BEGIN
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
     WHERE s.nspname='01_product_schema')<>20 THEN
   RAISE EXCEPTION 'Unexpected Product shadow helper inventory';
 END IF;
 FOR r IN SELECT p.oid,p.proname FROM pg_proc p
    JOIN pg_namespace s ON s.oid=p.pronamespace
    WHERE s.nspname='public' AND p.proname=ANY(ARRAY[
      'read_companies_page_fast',
      'read_retention_dashboard_v3',
      'read_retention_dashboard_v4',
      'read_retention_dashboard_v5_base',
      'read_retention_dashboard_v5',
      'read_retention_heatmap_v2',
      'read_retention_kpis_v2'
    ])
    ORDER BY CASE p.proname
      WHEN 'read_retention_dashboard_v3' THEN 1
      WHEN 'read_retention_dashboard_v4' THEN 2
      WHEN 'read_retention_dashboard_v5_base' THEN 3
      WHEN 'read_retention_dashboard_v5' THEN 4
      ELSE 5 END,p.proname
 LOOP
   d:=pg_get_functiondef(r.oid);
   IF d NOT LIKE 'CREATE OR REPLACE FUNCTION public.%'
     OR d NOT LIKE '%LANGUAGE sql%' OR d NOT LIKE '%STABLE SECURITY DEFINER%'
     OR d NOT LIKE '%SET search_path TO ''public'', ''metrics_private'', ''pg_temp''%'
     OR d LIKE '%feature_olap.%' OR d LIKE '%product_source.%' THEN
     RAISE EXCEPTION 'Unexpected read-only source contract %',r.proname;
   END IF;
   d:=replace(d,'CREATE OR REPLACE FUNCTION public.',
                'CREATE OR REPLACE FUNCTION "01_product_schema".');
   FOR tab IN SELECT s.nspname schema_name,c.relname table_name FROM pg_class c
      JOIN pg_namespace s ON s.oid=c.relnamespace
      WHERE s.nspname IN ('public','metrics_private') AND c.relkind='r'
      ORDER BY length(c.relname) DESC,c.relname
   LOOP
     d:=replace(d,tab.schema_name||'.'||tab.table_name,
                   '"01_product_schema".'||quote_ident(tab.table_name));
   END LOOP;
   IF r.proname='read_retention_dashboard_v4' THEN
      d:=replace(d,'public.read_retention_dashboard_v3(',
                    '"01_product_schema".read_retention_dashboard_v3(');
   ELSIF r.proname='read_retention_dashboard_v5' THEN
      d:=replace(d,'public.read_retention_dashboard_v5_base(',
                    '"01_product_schema".read_retention_dashboard_v5_base(');
   END IF;
   d:=replace(d,
     'SET search_path TO ''public'', ''metrics_private'', ''pg_temp''',
     'SET search_path TO "01_product_schema", public, metrics_private, pg_catalog, pg_temp');
   EXECUTE d;
   n:=n+1;
 END LOOP;
 IF n<>7 OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
     WHERE ns.nspname='01_product_schema')<>27 THEN
     RAISE EXCEPTION 'Unexpected Product stage E3 function inventory %',n; END IF;
 EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "01_product_schema" FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher';
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
    WHERE s.nspname='01_product_schema' AND
       (NOT p.prosecdef OR
        has_function_privilege('anon',p.oid,'EXECUTE') OR
        has_function_privilege('authenticated',p.oid,'EXECUTE') OR
        has_function_privilege('service_role',p.oid,'EXECUTE')))
 THEN RAISE EXCEPTION 'Shadow security violation'; END IF;
END $clone$;
