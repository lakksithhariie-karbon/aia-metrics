-- Exact 30 Friction drill headers: 5 issues x 2 windows x 3 tabs.
-- Derived from frozen event-backed payload, not saved legacy drill rows.
CREATE OR REPLACE FUNCTION "01_product_schema".build_overview_friction_headers_v1(
 p_as_of_at timestamptz,p_source_watermark_at timestamptz
) RETURNS TABLE(drill_key text,tab text,header jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog'
SET statement_timeout TO '100s'
AS $fn$
WITH payload AS MATERIALIZED(
 SELECT "01_product_schema".build_overview_friction_payload_v1(
 p_as_of_at,p_source_watermark_at)#>'{value}' v
), issues AS(
 SELECT x.value issue FROM payload p,
 jsonb_array_elements(p.v->'issues') x
), rows AS(
 SELECT i.issue->>'key' issue_key,i.issue->>'label' label,
 CASE i.issue->>'key'
 WHEN 'txn_reverted' THEN 'Transaction reverted to Needs Review'
 WHEN 'txn_ledger_failed' THEN 'Transaction Ledger Updated failed'
 WHEN 'txn_type_failed' THEN 'Transaction Type Updated failed'
 WHEN 'bill_upload_failed' THEN 'Bill Upload failed'
 ELSE 'Invoice Upload failed' END title,
 z.period,z.window_label,
 (i.issue#>>(ARRAY[z.period,'impacted']))::integer impacted,
 (i.issue#>>(ARRAY[z.period,'recovered']))::integer recovered,
 (i.issue#>>(ARRAY[z.period,'unresolved']))::integer unresolved
 FROM issues i
 CROSS JOIN (VALUES('current'::text,'Last 28 days'::text),
 ('previous','Previous 28 days')) z(period,window_label)
), slots AS(
 SELECT r.*,t.tab_key,t.tab_label,
 CASE t.tab_key WHEN 'all' THEN r.impacted WHEN 'recovered' THEN r.recovered ELSE r.unresolved END population
 FROM rows r CROSS JOIN (VALUES
 ('all'::text,'All impacted'::text,1),
 ('recovered','Recovered',2),
 ('unresolved','Unresolved',3)) t(tab_key,tab_label,pos)
)
SELECT s.issue_key||':'||s.period AS drill_key,
 s.tab_key AS tab,
 jsonb_build_object(
 'kind','optional',
 'tabs',jsonb_build_array(
  jsonb_build_object('key','all','count',s.impacted,'label','All impacted'),
  jsonb_build_object('key','recovered','count',s.recovered,'label','Recovered'),
  jsonb_build_object('key','unresolved','count',s.unresolved,'label','Unresolved')
 ),
 'title',s.title,'detail',s.recovered::text||' recovered · '||s.unresolved::text||' unresolved',
 'row_key','companies',
 'headline',s.impacted::text||CASE WHEN s.impacted=1 THEN ' company impacted' ELSE ' companies impacted' END,
 'node_key',s.issue_key,'active_tab',s.tab_key,'population',s.population,
 'default_tab','unresolved',
 'window_label',s.window_label,
 'source_context','From Friction & Recovery · '||
 (CASE WHEN s.issue_key='txn_reverted' THEN 'Transaction reverted' ELSE s.label END)||
 ' · '||s.tab_label||' · '||s.window_label,
 'search_placeholder','Search company…'
 ) AS header
FROM slots s;
$fn$;
REVOKE ALL ON FUNCTION "01_product_schema".build_overview_friction_headers_v1(timestamptz,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".build_overview_friction_headers_v1(timestamptz,timestamptz)
 TO service_role;
