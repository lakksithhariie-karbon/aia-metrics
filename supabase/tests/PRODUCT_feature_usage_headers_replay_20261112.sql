-- Exact replay of all Feature Usage drill headers from frozen event history.
-- 5 generations x 12 weeks x 13 module/tabs = 780 headers.
-- Read-only; does not stage, seal, advance current pointers or alter cron.
BEGIN READ ONLY;
SET LOCAL statement_timeout='120s';
WITH baseline AS (
 SELECT s.id,(s.payload#>>'{value,as_of}')::timestamptz asof,s.source_watermark_at wm
 FROM public.product_snapshot s WHERE s.kind='overview-feature-usage'
 AND s.id IN(353,358,364,370,376)
), replay AS MATERIALIZED (
 SELECT b.id,h.drill_key,h.tab,h.header
 FROM baseline b CROSS JOIN LATERAL
 "01_product_schema".build_overview_feature_usage_headers_v1(b.asof,b.wm) h
), recorded AS MATERIALIZED (
 SELECT snapshot_id id,drill_key,tab,header
 FROM public.product_overview_drill WHERE kind='overview-feature-usage'
 AND snapshot_id IN(353,358,364,370,376)
), missing AS (SELECT * FROM recorded EXCEPT ALL SELECT * FROM replay),
 extra AS (SELECT * FROM replay EXCEPT ALL SELECT * FROM recorded)
SELECT b.id,
 (SELECT count(*) FROM recorded r WHERE r.id=b.id) recorded_headers,
 (SELECT count(*) FROM replay r WHERE r.id=b.id) replayed_headers,
 (SELECT count(*) FROM missing m WHERE m.id=b.id) recorded_not_rebuilt,
 (SELECT count(*) FROM extra e WHERE e.id=b.id) rebuilt_not_recorded,
 (SELECT count(*) FROM recorded r WHERE r.id=b.id)=156
 AND (SELECT count(*) FROM replay r WHERE r.id=b.id)=156
 AND (SELECT count(*) FROM missing m WHERE m.id=b.id)=0
 AND (SELECT count(*) FROM extra e WHERE e.id=b.id)=0
 AS exact_headers_ok,
 NOT has_function_privilege('anon',
 '"01_product_schema".build_overview_feature_usage_headers_v1(timestamptz,timestamptz)','EXECUTE')
 AS anon_denied,
 NOT has_function_privilege('authenticated',
 '"01_product_schema".build_overview_feature_usage_headers_v1(timestamptz,timestamptz)','EXECUTE')
 AS authenticated_denied
FROM baseline b ORDER BY b.id DESC;
ROLLBACK;
