-- Read-only full Feature Usage payload regression against five frozen sealed generations.
-- All payload_exact and security guards must pass. No publication is performed.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '120s';
WITH replay AS MATERIALIZED (
 SELECT s.id,s.source_watermark_at,
   s.payload AS saved,
   "01_product_schema".build_overview_feature_usage_source_v1(
     (s.payload#>>'{value,as_of}')::timestamptz,s.source_watermark_at
   ) AS computed
 FROM public.product_snapshot s
 WHERE s.kind='overview-feature-usage' AND s.id IN(353,358,364,370,376)
)
SELECT id,source_watermark_at,
 saved=computed->'payload' AS full_payload_exact_ok,
 jsonb_array_length(saved#>'{value,weeks}')=12 AS twelve_weeks_saved_ok,
 jsonb_array_length(computed#>'{payload,value,weeks}')=12 AS twelve_weeks_replayed_ok,
 NOT has_schema_privilege('anon','01_product_schema','USAGE') AS private_schema_anon_denied_ok,
 NOT has_schema_privilege('authenticated','01_product_schema','USAGE') AS private_schema_auth_denied_ok,
 NOT has_function_privilege('anon',
   '"01_product_schema".build_overview_feature_usage_source_v1(timestamptz,timestamptz)',
   'EXECUTE') AS function_anon_denied_ok,
 NOT has_function_privilege('authenticated',
   '"01_product_schema".build_overview_feature_usage_source_v1(timestamptz,timestamptz)',
   'EXECUTE') AS function_auth_denied_ok
FROM replay ORDER BY id DESC;
ROLLBACK;
