-- Product E5a: private shadow of chart cache reader. No source changes.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='120s';
SET LOCAL check_function_bodies=off;
DO $clone$
DECLARE rec record; t record; f record; d text;
BEGIN
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace s ON s.oid=p.pronamespace
     WHERE s.nspname='01_product_schema')<>48 THEN RAISE EXCEPTION 'E4 prerequisite missing';END IF;
 SELECT p.oid,p.proname,p.prosecdef,p.provolatile INTO rec
 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
 WHERE ns.nspname='metrics_private' AND p.proname='read_overview_chart_summary_cached_v1';
 IF rec.oid IS NULL OR NOT rec.prosecdef OR rec.provolatile<>'s'
 THEN RAISE EXCEPTION 'Unexpected chart reader contract';END IF;
 d:=pg_get_functiondef(rec.oid);
 IF d NOT LIKE 'CREATE OR REPLACE FUNCTION metrics_private.%'
 THEN RAISE EXCEPTION 'Unexpected definition prefix';END IF;
 d:=replace(d,'CREATE OR REPLACE FUNCTION metrics_private.','CREATE OR REPLACE FUNCTION "01_product_schema".');
 FOR t IN SELECT s.nspname sc,c.relname nm FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
    WHERE s.nspname IN ('public','metrics_private') AND c.relkind IN ('r','v')
    ORDER BY length(c.relname) DESC,c.relname
 LOOP
   d:=replace(d,t.sc||'.'||t.nm,'"01_product_schema".'||quote_ident(t.nm));
 END LOOP;
 FOR f IN SELECT proname FROM pg_proc x JOIN pg_namespace n ON n.oid=x.pronamespace
   WHERE n.nspname='public' AND proname LIKE 'read_%'
    AND proname NOT LIKE 'read_jira_%' AND proname NOT LIKE 'read_ai_%' AND proname NOT LIKE 'read_infra_%'
 LOOP
   d:=replace(d,'public.'||f.proname||'(','"01_product_schema".'||quote_ident(f.proname)||'(');
 END LOOP;
 d:=replace(d,'SET search_path TO ''public'', ''metrics_private'', ''pg_temp''',
     'SET search_path TO "01_product_schema", public, pg_catalog, pg_temp');
 IF d LIKE '%metrics_private.%' OR d LIKE '%public.product_snapshot%'
 THEN RAISE EXCEPTION 'Unreplaced source reference in chart reader';END IF;
 EXECUTE d;
 EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "01_product_schema" FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher';
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
     WHERE ns.nspname='01_product_schema')<>49 THEN
    RAISE EXCEPTION 'Unexpected target function count';END IF;
END $clone$;
