-- Product Stage G1: PRIVATE ingestion function canaries, never route live traffic.
-- Only creates functions in numbered Product schema, no trigger or job changes.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='180s';
SET LOCAL check_function_bodies=off;
DO $writer$
DECLARE rec record; tab record; fn record; d text; n integer:=0;
BEGIN
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
        WHERE ns.nspname='01_product_schema')<>131 THEN
    RAISE EXCEPTION 'Product helper prerequisite inventory mismatch'; END IF;
 FOR rec IN SELECT p.oid,p.proname FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
  WHERE ns.nspname='public' AND p.proname IN
   ('normalize_event_properties','merge_event_properties','try_begin_incremental',
    'finish_incremental','upsert_mixpanel_events_detail','upsert_mixpanel_events',
    'record_activity_day_fact','core_activity_kind')
  ORDER BY CASE p.proname
    WHEN 'normalize_event_properties' THEN 1
    WHEN 'merge_event_properties' THEN 2
    WHEN 'core_activity_kind' THEN 3
    WHEN 'upsert_mixpanel_events_detail' THEN 5
    ELSE 4 END,p.proname
 LOOP
   d:=pg_get_functiondef(rec.oid);
   IF d NOT LIKE 'CREATE OR REPLACE FUNCTION public.%'
     OR d LIKE '%feature_olap.%' OR d LIKE '%product_source.%' THEN
      RAISE EXCEPTION 'Unexpected Product private writer source %',rec.proname;END IF;
   d:=replace(d,'CREATE OR REPLACE FUNCTION public.',
                 'CREATE OR REPLACE FUNCTION "01_product_schema".');
   FOR tab IN SELECT s.nspname sc,c.relname nm FROM pg_class c
        JOIN pg_namespace s ON s.oid=c.relnamespace
        WHERE s.nspname IN('public','metrics_private') AND c.relkind IN('r','v')
        ORDER BY length(c.relname) DESC,c.relname
   LOOP
      d:=replace(d,tab.sc||'.'||tab.nm,'"01_product_schema".'||quote_ident(tab.nm));
   END LOOP;
   FOR fn IN SELECT p.proname nm, s.nspname sc FROM pg_proc p
         JOIN pg_namespace s ON s.oid=p.pronamespace
         WHERE (s.nspname='public' AND p.proname IN
          ('normalize_event_properties','merge_event_properties','try_begin_incremental',
           'finish_incremental','upsert_mixpanel_events_detail','upsert_mixpanel_events',
           'record_activity_day_fact','core_activity_kind'))
           OR (s.nspname='public' AND p.proname IN
            ('is_core_activity','is_qualifying_sync','is_successful_integration','is_internal_email'))
      ORDER BY length(p.proname) DESC
   LOOP
      d:=replace(d,fn.sc||'.'||fn.nm||'(',
                   '"01_product_schema".'||quote_ident(fn.nm)||'(');
   END LOOP;
   d:=replace(d,'SET search_path TO ''public'', ''pg_temp''',
                 'SET search_path TO "01_product_schema", pg_catalog, pg_temp');
   d:=replace(d,'SET search_path TO ''public''',
                 'SET search_path TO "01_product_schema", pg_catalog, pg_temp');
   IF d LIKE '%public.events%' OR d LIKE '%public.export_watermarks%'
      OR d LIKE '%public.normalize_event_properties%'
      OR d LIKE '%public.merge_event_properties%' OR d LIKE '%metrics_private.%'
   THEN RAISE EXCEPTION 'Unrewritten ingestion source reference %',rec.proname; END IF;
   EXECUTE d;
   n:=n+1;
 END LOOP;
 IF n<>8 OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
        WHERE ns.nspname='01_product_schema')<>139
 THEN RAISE EXCEPTION 'Unexpected Product G1 function count %',n;END IF;
 EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "01_product_schema" FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher';
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='01_product_schema' AND
     (has_function_privilege('anon',p.oid,'EXECUTE') OR
      has_function_privilege('authenticated',p.oid,'EXECUTE') OR
      has_function_privilege('service_role',p.oid,'EXECUTE')))
 THEN RAISE EXCEPTION 'Shadow writer security failure';END IF;
END $writer$;
