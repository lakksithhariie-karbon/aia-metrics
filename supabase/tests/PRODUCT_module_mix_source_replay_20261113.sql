-- Read-only exact historical Module Mix payload, population and headers.
-- Snapshot #378. Re-run with #373, #367, #360 for further frozen samples.
-- Company card evidence exceptions are reported, NOT fabricated away.
BEGIN READ ONLY;
SET LOCAL statement_timeout='120s';
WITH h AS (
 SELECT id,payload,(payload#>>'{value,window_end}')::timestamptz asof,
 source_watermark_at wm
 FROM public.product_snapshot WHERE id=378 AND kind='overview-module-mix'
), source AS MATERIALIZED(
 SELECT h.id,h.payload,
 "01_product_schema".build_overview_module_mix_payload_v1(h.asof,h.wm) rebuilt
 FROM h
), saved_population AS MATERIALIZED(
 SELECT drill_key,tab,member_id FROM public.product_overview_member
 WHERE snapshot_id=378 AND kind='overview-module-mix'
), rebuilt_population AS MATERIALIZED(
 SELECT r.drill_key,r.tab,r.member_id FROM h CROSS JOIN LATERAL
 "01_product_schema".build_overview_module_mix_population_v1(h.asof,h.wm) r
), saved_headers AS MATERIALIZED(
 SELECT drill_key,tab,header FROM public.product_overview_drill
 WHERE snapshot_id=378 AND kind='overview-module-mix'
), rebuilt_headers AS MATERIALIZED(
 SELECT r.drill_key,r.tab,r.header FROM h CROSS JOIN LATERAL
 "01_product_schema".build_overview_module_mix_headers_v1(h.asof,h.wm) r
), saved_cards AS MATERIALIZED(
 SELECT drill_key,tab,member_id,card FROM public.product_overview_member
 WHERE snapshot_id=378 AND kind='overview-module-mix'
), rebuilt_cards AS MATERIALIZED(
 SELECT r.drill_key,r.tab,r.member_id,r.card FROM h CROSS JOIN LATERAL
 "01_product_schema".build_overview_module_mix_cards_v1(h.asof,h.wm) r
)
SELECT (SELECT id FROM h) snapshot_id,
 (SELECT payload=rebuilt FROM source) full_payload_exact,
 (SELECT count(*) FROM saved_population) saved_members,
 (SELECT count(*) FROM rebuilt_population) rebuilt_members,
 (SELECT count(*) FROM (
 SELECT * FROM saved_population EXCEPT ALL SELECT * FROM rebuilt_population) t) missing_members,
 (SELECT count(*) FROM (
 SELECT * FROM rebuilt_population EXCEPT ALL SELECT * FROM saved_population) t) extra_members,
 (SELECT count(*) FROM saved_headers) saved_headers,
 (SELECT count(*) FROM rebuilt_headers) rebuilt_headers,
 (SELECT count(*) FROM (
 SELECT * FROM saved_headers EXCEPT ALL SELECT * FROM rebuilt_headers) t) missing_headers,
 (SELECT count(*) FROM (
 SELECT * FROM rebuilt_headers EXCEPT ALL SELECT * FROM saved_headers) t) extra_headers,
 (SELECT count(*) FROM saved_cards s JOIN rebuilt_cards r USING(drill_key,tab,member_id)
 WHERE s.card->'event_counts'=r.card->'event_counts') exact_event_count_cards,
 (SELECT count(*) FROM saved_cards s JOIN rebuilt_cards r USING(drill_key,tab,member_id)
 WHERE s.card->'evidence'=r.card->'evidence') exact_evidence_cards,
 NOT has_function_privilege('anon',
 '"01_product_schema".build_overview_module_mix_payload_v1(timestamptz,timestamptz)','EXECUTE')
 AND NOT has_function_privilege('authenticated',
 '"01_product_schema".build_overview_module_mix_cards_v1(timestamptz,timestamptz)','EXECUTE')
 AS private_access_ok;
ROLLBACK;
