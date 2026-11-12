-- Deterministic, read-only Feature Usage drill headers from the same frozen
-- source membership population as the verified payload generator.
-- No legacy/public writes, staging, publication, pointers or crons.
CREATE OR REPLACE FUNCTION "01_product_schema".build_overview_feature_usage_headers_v1(
 p_as_of_at timestamptz,p_source_watermark_at timestamptz
) RETURNS TABLE(drill_key text,tab text,header jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog'
SET statement_timeout TO '110s'
AS $fn$
WITH params AS (
 SELECT date_trunc('week',p_as_of_at AT TIME ZONE 'Asia/Kolkata')::date current_week
 WHERE p_as_of_at IS NOT NULL AND p_source_watermark_at IS NOT NULL
   AND p_as_of_at >= p_source_watermark_at
),
weeks AS (
 SELECT (p.current_week - n*7)::date ws FROM params p CROSS JOIN generate_series(1,12) n
),
modules AS (
 SELECT * FROM (VALUES
 ('ap'::text,'AP / Bills'::text),
 ('ar','AR / Invoices'),
 ('transactions','Transactions')) m(module_key,title)
),
tabs AS (
 SELECT * FROM (VALUES
 ('ap'::text,'all'::text,'All'::text,1),
 ('ap','bill_upload','Bill Upload',2),('ap','bill_entity','Bill Entity Created',3),
 ('ap','review_correction','Review / Correction',4),
 ('ar','all','All',1),('ar','invoice_upload','Invoice Upload',2),
 ('ar','invoice_entity','Invoice Entity Created',3),
 ('transactions','all','All',1),('transactions','statement_upload','Statement Upload',2),
 ('transactions','type_updated','Type Updated',3),('transactions','ledger_updated','Ledger Updated',4),
 ('transactions','accounting_ready','Accounting Ready',5),
 ('transactions','config_edited','Configuration Edited',6)
 ) t(module_key,tab_key,tab_label,position)
),
population AS MATERIALIZED(
 SELECT p.drill_key,p.tab,p.member_id
 FROM "01_product_schema".build_overview_feature_usage_population_v1(
   p_as_of_at,p_source_watermark_at
 ) p
),
counts AS MATERIALIZED(
 SELECT p.drill_key,p.tab,count(*)::integer n
 FROM population p GROUP BY p.drill_key,p.tab
),
slots AS (
 SELECT m.module_key,m.title,w.ws,
 m.module_key||':'||to_char(w.ws,'YYYY-MM-DD') AS drill_key,
 t.tab_key,t.tab_label
 FROM weeks w CROSS JOIN modules m JOIN tabs t ON t.module_key=m.module_key
)
SELECT s.drill_key,s.tab_key AS tab,
 jsonb_build_object(
 'kind','coverage',
 'tabs',(
   SELECT jsonb_agg(jsonb_build_object(
      'key',t.tab_key,'count',coalesce(c2.n,0),'label',t.tab_label
     ) ORDER BY t.position)
   FROM tabs t LEFT JOIN counts c2
     ON c2.drill_key=s.drill_key AND c2.tab=t.tab_key
   WHERE t.module_key=s.module_key
 ),
 'title',s.title,
 'detail',NULL::text,
 'row_key','companies',
 'headline',coalesce(c.n,0)::text||
   CASE WHEN coalesce(c.n,0)=1 THEN ' active company' ELSE ' active companies' END,
 'node_key',s.drill_key,
 'active_tab',s.tab_key,
 'population',coalesce(c.n,0),
 'default_tab','all',
 'window_label','Week of '||to_char(s.ws,'FMDD Mon'),
 'source_context','From Feature Usage · '||s.title||
   ' · Week of '||to_char(s.ws,'FMDD Mon')||
   CASE WHEN s.tab_key='all' THEN '' ELSE ' · '||s.tab_label END,
 'search_placeholder','Search company…'
 ) AS header
FROM slots s LEFT JOIN counts c ON c.drill_key=s.drill_key AND c.tab=s.tab_key;
$fn$;
REVOKE ALL ON FUNCTION "01_product_schema".build_overview_feature_usage_headers_v1(timestamptz,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".build_overview_feature_usage_headers_v1(timestamptz,timestamptz)
 TO service_role;
