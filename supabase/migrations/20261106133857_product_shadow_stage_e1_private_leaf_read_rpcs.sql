-- Product Stage E1: 14 isolated, read-only shadow snapshot + drilldown RPCs.
-- Public production RPC definitions, grants, ingestion and cron jobs stay unchanged.
SET LOCAL lock_timeout='6s';
SET LOCAL statement_timeout='120s';
SET LOCAL check_function_bodies=on;
DO $shadow$
DECLARE rec record; d text; n integer:=0;
BEGIN
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
     WHERE ns.nspname='01_product_schema' AND c.relkind='r' AND c.relrowsecurity)<>58
     OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
     WHERE ns.nspname='01_product_schema')<>0 THEN
   RAISE EXCEPTION 'Product shadow is not in expected staging state';
 END IF;
 FOR rec IN
   SELECT p.oid,p.proname FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public'
   AND p.proname=ANY(ARRAY[
      'read_current_funnel_snapshot','read_current_overview_snapshot',
      'read_funnel_drill_header','read_funnel_generation','read_funnel_members',
      'read_funnel_tab_counts','read_overview_drill_header','read_overview_generation',
      'read_overview_members','read_product_page','read_product_snapshot',
      'read_product_snapshot_with_generation','read_retention_period_drill',
      'read_retention_summary_drill'
   ])
   ORDER BY p.proname
 LOOP
   d:=pg_get_functiondef(rec.oid);
   IF d NOT LIKE 'CREATE OR REPLACE FUNCTION public.%' OR
      d NOT LIKE '%LANGUAGE sql%' OR d NOT LIKE '%STABLE SECURITY DEFINER%' OR
      d NOT LIKE '%SET search_path TO ''public''%' OR
      d LIKE '%metrics_private.%' OR d LIKE '%product_source.%'
        OR d LIKE '%feature_olap.%' THEN
      RAISE EXCEPTION 'Unexpected Product read function contract: %',rec.proname;
   END IF;
   d:=replace(d,'CREATE OR REPLACE FUNCTION public.',
                 'CREATE OR REPLACE FUNCTION "01_product_schema".');
   d:=replace(d,'public.','"01_product_schema".');
   d:=replace(d,'SET search_path TO ''public''',
                 'SET search_path TO "01_product_schema", pg_catalog, pg_temp');
   EXECUTE d;
   n:=n+1;
 END LOOP;
 IF n<>14 OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
     WHERE ns.nspname='01_product_schema' AND p.prosecdef)<>14 THEN
     RAISE EXCEPTION 'Product leaf read function count mismatch: %',n;
 END IF;
 EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "01_product_schema" FROM PUBLIC, anon, authenticated, service_role, product_metrics_fetcher';
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
    WHERE ns.nspname='01_product_schema' AND
      (has_function_privilege('anon',p.oid,'EXECUTE') OR
       has_function_privilege('authenticated',p.oid,'EXECUTE') OR
       has_function_privilege('service_role',p.oid,'EXECUTE')))
 THEN RAISE EXCEPTION 'Shadow read functions unexpectedly exposed'; END IF;
END $shadow$;
