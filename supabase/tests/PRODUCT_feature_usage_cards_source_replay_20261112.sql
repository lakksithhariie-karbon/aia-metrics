-- Read-only, fail-visible audit of full Feature Usage card event evidence.
-- Immutable event facts MUST replay exactly. Mutable company identity/integration,
-- actor and sort-position are reported separately, never misclassified as exact.
-- A pass does NOT authorize staging/publishing or cutover of other Overview kinds.
BEGIN READ ONLY;
SET LOCAL statement_timeout='120s';
WITH b AS (
 SELECT (payload#>>'{value,as_of}')::timestamptz asof,source_watermark_at wm
 FROM public.product_snapshot WHERE id=376 AND kind='overview-feature-usage'
), rebuilt AS MATERIALIZED (
 SELECT * FROM b CROSS JOIN LATERAL
 "01_product_schema".build_overview_feature_usage_cards_source_v1(b.asof,b.wm) x
), source AS MATERIALIZED (
 SELECT drill_key,tab,member_id,sort_position,card FROM public.product_overview_member
 WHERE snapshot_id=376 AND kind='overview-feature-usage'
),
missing AS (
 SELECT drill_key,tab,member_id FROM source
 EXCEPT ALL SELECT drill_key,tab,member_id FROM rebuilt
), extra AS (
 SELECT drill_key,tab,member_id FROM rebuilt
 EXCEPT ALL SELECT drill_key,tab,member_id FROM source
), comparison AS (
 SELECT count(*) checked,
 count(*) FILTER(WHERE s.card->>'reached_at' IS NOT DISTINCT FROM r.card->>'reached_at') exact_reached,
 count(*) FILTER(WHERE s.card->'event_counts'=r.card->'event_counts') exact_event_counts,
 count(*) FILTER(WHERE s.card->'evidence'=r.card->'evidence') exact_evidence,
 count(*) FILTER(WHERE s.card->'actor'=r.card->'actor') exact_actor,
 count(*) FILTER(WHERE s.card->>'company_name' IS NOT DISTINCT FROM r.card->>'company_name') exact_name,
 count(*) FILTER(WHERE s.card->>'integration_type' IS NOT DISTINCT FROM r.card->>'integration_type') exact_integration,
 count(*) FILTER(WHERE s.sort_position=r.sort_position) exact_sort,
 count(*) FILTER(WHERE s.card=r.card) exact_full_card
 FROM source s JOIN rebuilt r USING (drill_key,tab,member_id)
)
SELECT (SELECT count(*) FROM source) saved_members,
 (SELECT count(*) FROM rebuilt) rebuilt_members,
 (SELECT count(*) FROM missing) missing_members,
 (SELECT count(*) FROM extra) unexpected_members,
 c.*,
 (SELECT count(*) FROM missing)=0 AND (SELECT count(*) FROM extra)=0 AND
 c.checked=(SELECT count(*) FROM source) AND
 c.exact_reached=c.checked AND c.exact_event_counts=c.checked AND
 c.exact_evidence=c.checked AS immutable_event_evidence_exact_ok,
 NOT has_function_privilege('anon',
 '"01_product_schema".build_overview_feature_usage_cards_source_v1(timestamptz,timestamptz)','EXECUTE')
 AND NOT has_function_privilege('authenticated',
 '"01_product_schema".build_overview_feature_usage_cards_source_v1(timestamptz,timestamptz)','EXECUTE')
 AS protected_private_function_ok
FROM comparison c;
ROLLBACK;
