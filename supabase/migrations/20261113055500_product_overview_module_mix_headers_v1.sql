-- Exact legacy-compatible Module Mix drill headers from same source payload.
-- 8 buckets x current/previous = 16 headers; no writes to snapshots.
CREATE OR REPLACE FUNCTION "01_product_schema".build_overview_module_mix_headers_v1(
 p_as_of_at timestamptz,p_source_watermark_at timestamptz
) RETURNS TABLE(drill_key text,tab text,header jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog'
SET statement_timeout TO '100s'
SET extra_float_digits TO '3'
AS $fn$
WITH source AS MATERIALIZED (
 SELECT "01_product_schema".build_overview_module_mix_payload_v1(
 p_as_of_at,p_source_watermark_at)#>'{value}' payload
), buckets AS (
 SELECT b.value AS bucket FROM source s,
 jsonb_array_elements(s.payload->'buckets') b
), populated AS(
 SELECT (b.bucket->>'key')||':'||v.period AS drill_key,
 b.bucket->>'key' AS node_key,b.bucket->>'label' AS title,
 v.period,
 CASE WHEN v.period='current' THEN 'Last 28 days' ELSE 'Previous 28 days' END window_label,
 CASE WHEN v.period='current' THEN (b.bucket#>>'{current,companies}')::integer
 ELSE (b.bucket#>>'{previous,companies}')::integer END AS companies,
 CASE WHEN v.period='current' THEN (b.bucket#>>'{current,core_active_companies}')::integer
 ELSE (b.bucket#>>'{previous,core_active_companies}')::integer END AS population
 FROM buckets b CROSS JOIN (VALUES ('current'::text),('previous')) v(period)
)
SELECT p.drill_key,'all'::text AS tab,jsonb_build_object(
 'kind','optional','tabs',NULL::jsonb,
 'title',p.title,'detail',
  (CASE WHEN p.population>0
    THEN to_char(round(p.companies::numeric*100/p.population,1),'FM9990.0')
    ELSE '0.0' END)||'% of core-active companies',
 'row_key','companies',
 'headline',p.companies::text||CASE WHEN p.companies=1 THEN ' company' ELSE ' companies' END,
 'node_key',p.node_key,
 'active_tab',NULL::text,'population',p.companies,
 'default_tab',NULL::text,'window_label',p.window_label,
 'source_context','From Module Mix · '||p.title||' · '||p.window_label,
 'search_placeholder','Search company…'
) AS header FROM populated p;
$fn$;
REVOKE ALL ON FUNCTION "01_product_schema".build_overview_module_mix_headers_v1(timestamptz,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".build_overview_module_mix_headers_v1(timestamptz,timestamptz)
 TO service_role;
