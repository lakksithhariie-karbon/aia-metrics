-- Private Product cache rebuild canaries. No live jobs routed.
SET LOCAL lock_timeout='7s'; SET LOCAL statement_timeout='240s'; SET LOCAL check_function_bodies=off;
DO $do$
DECLARE r record;tab record;fn record;d text;n int:=0;
BEGIN
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace WHERE ns.nspname='01_product_schema')<>139
 THEN RAISE EXCEPTION 'Expected G1 private writer functions';END IF;
 FOR r IN SELECT p.oid,p.proname,ns.nspname sc,p.provolatile,p.prosecdef
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
    WHERE (ns.nspname='public' AND p.proname=ANY(ARRAY[
      'refresh_retention','refresh_company_week_product','refresh_retention_dashboard_v3',
      'refresh_retention_dashboard_v4','refresh_retention_kpis_v2','refresh_retention_heatmap_v2',
      'refresh_companies_monthly_cache','refresh_companies_monthly_core_v2',
      'refresh_companies_fast_cache','refresh_companies_lifecycle_cache','refresh_overview_history_v1'
    ])) OR (ns.nspname='metrics_private' AND p.proname IN
      ('refresh_overview_chart_summary_cache_v1','refresh_overview_independent_core_kpi_cache_v1'))
    ORDER BY ns.nspname,p.proname
 LOOP
    IF r.provolatile<>'v' OR NOT r.prosecdef THEN RAISE EXCEPTION 'Unexpected writer properties %',r.proname; END IF;
    d:=pg_get_functiondef(r.oid);
    IF d NOT LIKE 'CREATE OR REPLACE FUNCTION '||r.sc||'.%' OR
        d LIKE '%feature_olap.%' OR d LIKE '%product_source.%' THEN
        RAISE EXCEPTION 'Unexpected writer definition %',r.proname; END IF;
    d:=replace(d,'CREATE OR REPLACE FUNCTION '||r.sc||'.',
      'CREATE OR REPLACE FUNCTION "01_product_schema".');
    FOR tab IN SELECT sn.nspname sc,c.relname nm FROM pg_class c JOIN pg_namespace sn ON sn.oid=c.relnamespace
       WHERE sn.nspname IN('public','metrics_private') AND c.relkind IN('r','v')
       ORDER BY length(c.relname) DESC,c.relname
    LOOP
       d:=replace(d,tab.sc||'.'||tab.nm,'"01_product_schema".'||quote_ident(tab.nm));
    END LOOP;
    FOR fn IN SELECT p.proname nm,ns.nspname sc FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
       WHERE ns.nspname IN('public','metrics_private')
       AND (EXISTS(SELECT 1 FROM pg_proc dest JOIN pg_namespace dns ON dns.oid=dest.pronamespace
                     WHERE dns.nspname='01_product_schema' AND dest.proname=p.proname)
          OR p.proname LIKE 'refresh_%')
       ORDER BY length(p.proname) DESC
    LOOP
       d:=replace(d,fn.sc||'.'||fn.nm||'(','"01_product_schema".'||quote_ident(fn.nm)||'(');
    END LOOP;
    d:=replace(d,'SET search_path TO ''public'', ''metrics_private'', ''pg_temp''',
      'SET search_path TO "01_product_schema", pg_catalog, pg_temp');
    d:=replace(d,'SET search_path TO ''public''',
      'SET search_path TO "01_product_schema", pg_catalog, pg_temp');
    d:=replace(d,'pg_try_advisory_xact_lock(20261010','pg_try_advisory_xact_lock(20261107');
    d:=replace(d,'pg_try_advisory_xact_lock(7242851','pg_try_advisory_xact_lock(7242852');
    IF r.proname='refresh_retention' THEN
       d:=replace(d,'''metrics_scratch.events''','''"01_product_schema".events''');
    END IF;
    IF d LIKE '%public.%' OR d LIKE '%metrics_private.%' OR d LIKE '%feature_olap.%'
    THEN RAISE EXCEPTION 'Legacy source reference still in %',r.proname;END IF;
    EXECUTE d;n:=n+1;
 END LOOP;
 IF n<>13 OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
      WHERE ns.nspname='01_product_schema')<>152
 THEN RAISE EXCEPTION 'Expected 13 private refresh functions';END IF;
 EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "01_product_schema" FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher';
END $do$;
