-- READ ONLY deterministic replay. All *_ok fields MUST be true.
-- Snapshot ids 377 and 371 were known-good Nov 5 and Nov 2 generations
-- before restoration. The source functions read frozen numbered events,
-- not existing snapshot payloads, and never publish anything.
BEGIN READ ONLY;
SET LOCAL statement_timeout='90s';

WITH baseline AS MATERIALIZED (
 SELECT s.id,s.payload#>'{value}' AS saved,s.source_watermark_at AS wm,
   "01_product_schema".build_overview_activity_source_v1(
     (s.payload#>>'{value,active_users,as_of}')::timestamptz,
     s.source_watermark_at
   ) AS replay_usage,
   "01_product_schema".build_overview_active_charts_source_v1(
     (s.payload#>>'{value,active_users,as_of}')::timestamptz,
     s.source_watermark_at
   ) AS replay_charts,
   public.read_overview_active_charts_v3(s.id) AS recorded_charts
 FROM "01_product_schema".product_snapshot s
 WHERE s.id IN (377,371) AND s.kind='overview' AND s.scope_key=''
)
SELECT id,wm,
 saved->>'dau'=replay_usage->>'dau' AS dau_ok,
 saved->>'wau'=replay_usage->>'wau_current' AS wau_ok,
 saved#>>'{active_users,wau,previous}'=replay_usage->>'wau_previous' AS previous_wau_ok,
 saved->>'mau'=replay_usage->>'mau_current' AS mau_ok,
 saved#>>'{active_users,mau,previous}'=replay_usage->>'mau_previous' AS previous_mau_ok,
 saved->>'wau_companies'=replay_usage->>'wau_companies' AS wau_companies_ok,
 saved->>'mau_companies'=replay_usage->>'mau_companies' AS mau_companies_ok,
 (replay_charts-'contract')=(recorded_charts-'contract'-'snapshot_id') AS full_charts_ok,
 jsonb_array_length(replay_charts#>'{weekly,rows}')=12 AS chart_shape_ok,
 NOT has_function_privilege('anon',
   '"01_product_schema".build_overview_activity_source_v1(timestamptz,timestamptz)',
   'EXECUTE') AS anonymous_denied_ok,
 NOT has_function_privilege('authenticated',
   '"01_product_schema".build_overview_active_charts_source_v1(timestamptz,timestamptz)',
   'EXECUTE') AS authenticated_denied_ok
FROM baseline
ORDER BY id DESC;

ROLLBACK;
