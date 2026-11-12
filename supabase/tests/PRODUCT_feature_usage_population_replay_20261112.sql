-- Read-only proof: all five sealed historical Feature Usage member populations
-- reproduce EXACT identity sets. Any missing/extra/duplicate member row is a failure.
-- Never infer card/header parity or permission to publish from this test.
BEGIN READ ONLY;
SET LOCAL statement_timeout='120s';
WITH baseline AS (
 SELECT s.id,(s.payload#>>'{value,as_of}')::timestamptz asof,s.source_watermark_at wm
 FROM public.product_snapshot s
 WHERE s.kind='overview-feature-usage' AND s.id IN(353,358,364,370,376)
),
rebuilt AS MATERIALIZED (
 SELECT b.id,p.drill_key,p.tab,p.member_id
 FROM baseline b
 CROSS JOIN LATERAL "01_product_schema".build_overview_feature_usage_population_v1(b.asof,b.wm) p
),
recorded AS MATERIALIZED (
 SELECT snapshot_id id,drill_key,tab,member_id
 FROM public.product_overview_member
 WHERE kind='overview-feature-usage' AND snapshot_id IN(353,358,364,370,376)
),
missing AS (SELECT * FROM recorded EXCEPT ALL SELECT * FROM rebuilt),
unexpected AS (SELECT * FROM rebuilt EXCEPT ALL SELECT * FROM recorded)
SELECT b.id,
 (SELECT count(*) FROM recorded r WHERE r.id=b.id) recorded_members,
 (SELECT count(*) FROM rebuilt r WHERE r.id=b.id) rebuilt_members,
 (SELECT count(*) FROM missing m WHERE m.id=b.id) missing_members,
 (SELECT count(*) FROM unexpected u WHERE u.id=b.id) unexpected_members,
 (SELECT count(*) FROM missing m WHERE m.id=b.id)=0
 AND (SELECT count(*) FROM unexpected u WHERE u.id=b.id)=0 AS full_membership_exact_ok,
 NOT has_function_privilege('anon',
 '"01_product_schema".build_overview_feature_usage_population_v1(timestamptz,timestamptz)',
 'EXECUTE') AS anon_denied_ok,
 NOT has_function_privilege('authenticated',
 '"01_product_schema".build_overview_feature_usage_population_v1(timestamptz,timestamptz)',
 'EXECUTE') AS authenticated_denied_ok
FROM baseline b ORDER BY b.id DESC;
ROLLBACK;
