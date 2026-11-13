-- Transactional dry-run of complete Feature Usage staging + seal + publishability.
-- Source-backed, private only, NEVER activates any pointer or publishes a page.
-- Entire candidate/member/header write is rolled back after assertions.
BEGIN;
SET LOCAL statement_timeout='120s';
WITH params AS MATERIALIZED (
 SELECT now() asof,w.last_success_at wm,w.status,(SELECT count(*) FROM "01_product_schema".events) n_events
 FROM "01_product_schema".export_watermarks w WHERE w.job_name='incremental'
),
source AS MATERIALIZED (
 SELECT p.asof,p.wm,p.n_events,
 "01_product_schema".build_overview_feature_usage_source_v1(p.asof,p.wm) AS j FROM params p
),
members AS MATERIALIZED (
 SELECT jsonb_agg(jsonb_build_object(
 'kind','overview-feature-usage','drill_key',c.drill_key,'tab',c.tab,
 'member_id',c.member_id,'position',c.sort_position,'card',c.card
 )) AS rows,count(*) n
 FROM params p CROSS JOIN LATERAL
 "01_product_schema".build_overview_feature_usage_cards_source_v1(p.asof,p.wm) c
),
headers AS MATERIALIZED (
 SELECT jsonb_agg(jsonb_build_object(
 'kind','overview-feature-usage','drill_key',h.drill_key,'tab',h.tab,'header',h.header
 )) rows,count(*) n
 FROM params p CROSS JOIN LATERAL
 "01_product_schema".build_overview_feature_usage_headers_v1(p.asof,p.wm) h
),
candidate AS MATERIALIZED (
 SELECT "01_product_schema".stage_product_snapshot_v2(
 'overview-feature-usage','',s.j->'payload',s.wm::text,s.n_events,
 'replay-test-only-feature-usage|'||s.wm::text||'|'||s.n_events,
 NULL::timestamptz,NULL::timestamptz,s.asof
 ) id FROM source s
 WHERE (s.j#>>'{payload,schema}')='1'
 AND jsonb_array_length(s.j#>'{payload,value,weeks}')=12
),
load AS MATERIALIZED (
 SELECT c.id,"01_product_schema".stage_overview_members(c.id,m.rows,h.rows) loaded,
 m.n members,h.n headers
 FROM candidate c CROSS JOIN members m CROSS JOIN headers h
 WHERE m.n>0 AND h.n=156
),
validate AS MATERIALIZED (
 SELECT l.id,l.loaded,l.members,l.headers,
 "01_product_schema".assert_product_snapshot_publishable(l.id,1) verified
 FROM load l
)
SELECT v.id,v.loaded,v.members,v.headers,
 EXISTS(SELECT 1 FROM "01_product_schema".product_overview_seal z WHERE z.snapshot_id=v.id) sealed,
 EXISTS(SELECT 1 FROM "01_product_schema".product_snapshot_current c WHERE c.snapshot_id=v.id) active
FROM validate v;
ROLLBACK;
-- Must return zero. Existing published pages and old tables were never changed.
SELECT (SELECT count(*) FROM "01_product_schema".product_snapshot
        WHERE build_key LIKE 'replay-test-only-feature-usage|%') AS left_staged_candidates,
       (SELECT count(*) FROM "01_product_schema".product_snapshot_current WHERE kind='overview-feature-usage' AND scope_key='') AS current_pointers_kept,
       (SELECT count(*) FROM public.product_snapshot_current WHERE kind='overview-feature-usage' AND scope_key='') AS legacy_pointers_kept;
