-- Read-only production safety preflight for the five-kind Overview publisher.
-- This test MUST NOT stage or activate any snapshot. Fail-closed conditions
-- are observable and leave canonical public + metrics_private untouched.
BEGIN READ ONLY;
SET LOCAL statement_timeout='120s';
WITH current_source AS (
 SELECT w.status,w.last_success_at wm,
 (SELECT count(*) FROM "01_product_schema".events) events
 FROM "01_product_schema".export_watermarks w WHERE job_name='incremental'
), candidates AS (
 SELECT s.kind,s.id,s.source_watermark_at,s.n_events,s.payload,
  EXISTS(SELECT 1 FROM "01_product_schema".product_overview_seal z
         WHERE z.snapshot_id=s.id)
   OR EXISTS(SELECT 1 FROM "01_product_schema".product_funnel_seal z
             WHERE z.snapshot_id=s.id) AS has_seal
 FROM "01_product_schema".product_snapshot s
 WHERE s.kind IN('overview','overview-funnel','overview-feature-usage',
 'overview-module-mix','overview-friction') AND s.scope_key=''
), current AS (
 SELECT kind,snapshot_id FROM "01_product_schema".product_snapshot_current
 WHERE kind IN('overview','overview-funnel','overview-feature-usage',
 'overview-module-mix','overview-friction') AND scope_key=''
)
SELECT src.status AS source_status,src.wm AS source_watermark_at,
 src.events AS events,
 (SELECT count(*) FROM candidates c WHERE c.source_watermark_at=src.wm
 AND c.n_events=src.events AND c.has_seal) AS sealed_same_generation_candidates,
 (SELECT count(*) FROM "01_product_schema".product_publication_current
 WHERE page='overview') AS new_page_manifest,
 (SELECT count(*) FROM public.product_publication_current
 WHERE page='overview') AS legacy_page_manifest,
 (SELECT count(*) FROM current) AS existing_shadow_current_kinds,
 NOT has_function_privilege('anon',
  '"01_product_schema".try_publish_verified_overview_v1()','EXECUTE')
 AND NOT has_function_privilege('authenticated',
  '"01_product_schema".try_publish_verified_overview_v1()','EXECUTE')
 AS publisher_private_ok,
 NOT has_function_privilege('anon',
  '"01_product_schema".stage_feature_usage_generation_v1(timestamptz)','EXECUTE')
 AND NOT has_function_privilege('authenticated',
  '"01_product_schema".stage_feature_usage_generation_v1(timestamptz)','EXECUTE')
 AS stage_private_ok
FROM current_source src;
ROLLBACK;
