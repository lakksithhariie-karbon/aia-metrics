-- READ-ONLY Overview source replay. Every *_ok must be TRUE for both
-- known-good Nov 2/Nov 5 generations. These source functions evaluate raw
-- numbered Product events at each sealed historical ingestion watermark.
-- Existing data/pointers are never modified; full legacy snapshot rebuild,
-- member-card regeneration and publication are NOT implemented here.
BEGIN READ ONLY;
SET LOCAL statement_timeout='120s';

WITH replay AS MATERIALIZED (
 SELECT s.id,s.source_watermark_at AS wm,s.payload#>'{value}' AS saved,
  (s.payload#>>'{value,active_users,as_of}')::timestamptz AS asof,
  "01_product_schema".build_overview_activity_source_v1(
    (s.payload#>>'{value,active_users,as_of}')::timestamptz,s.source_watermark_at) AS activity,
  "01_product_schema".build_overview_active_charts_source_v1(
    (s.payload#>>'{value,active_users,as_of}')::timestamptz,s.source_watermark_at) AS charts,
  "01_product_schema".build_overview_workflow_source_v1(
    (s.payload#>>'{value,active_users,as_of}')::timestamptz,s.source_watermark_at) AS workflow,
  "01_product_schema".build_overview_friction_source_v1(
    (s.payload#>>'{value,active_users,as_of}')::timestamptz,s.source_watermark_at) AS friction,
  "01_product_schema".build_overview_adoption_source_v1(
    (s.payload#>>'{value,active_users,as_of}')::timestamptz,s.source_watermark_at) AS adoption,
  public.read_overview_active_charts_v3(s.id) AS prior_charts,
  public.read_overview_workflow_charts_v3(s.id) AS prior_workflow,
  public.read_overview_friction_v3(s.id) AS prior_friction,
  public.read_overview_adoption_journey_v3(s.id) AS prior_adoption
 FROM "01_product_schema".product_snapshot s
 WHERE s.id IN (377,371) AND s.kind='overview' AND s.scope_key=''
)
SELECT id,
 saved->>'dau'=activity->>'dau' AS dau_ok,
 saved->>'wau'=activity->>'wau_current' AS wau_ok,
 saved#>>'{active_users,wau,previous}'=activity->>'wau_previous' AS previous_wau_ok,
 saved->>'mau'=activity->>'mau_current' AS mau_ok,
 saved#>>'{active_users,mau,previous}'=activity->>'mau_previous' AS previous_mau_ok,
 saved->>'wau_companies'=activity->>'wau_companies' AS wau_companies_ok,
 saved->>'mau_companies'=activity->>'mau_companies' AS mau_companies_ok,
 (charts-'contract')=(prior_charts-'contract'-'snapshot_id') AS full_active_charts_ok,
 (workflow-'contract')=(prior_workflow-'contract'-'snapshot_id') AS full_workflow_ok,
 (friction-'contract')=(prior_friction-'contract'-'snapshot_id') AS full_friction_ok,
 (adoption-'contract')=(prior_adoption-'contract'-'snapshot_id') AS full_adoption_ok,
 jsonb_array_length(charts#>'{weekly,rows}')=12 AS chart_shape_ok,
 NOT has_schema_privilege('anon','01_product_schema','USAGE') AS schema_hidden_from_anon_ok,
 NOT has_schema_privilege('authenticated','01_product_schema','USAGE') AS schema_hidden_from_auth_ok,
 NOT has_function_privilege('anon',
  '"01_product_schema".build_overview_activity_source_v1(timestamptz,timestamptz)',
  'EXECUTE') AS activity_anon_denied_ok,
 NOT has_function_privilege('anon',
  '"01_product_schema".build_overview_active_charts_source_v1(timestamptz,timestamptz)',
  'EXECUTE') AS charts_anon_denied_ok,
 NOT has_function_privilege('anon',
  '"01_product_schema".build_overview_workflow_source_v1(timestamptz,timestamptz)',
  'EXECUTE') AS workflow_anon_denied_ok,
 NOT has_function_privilege('anon',
  '"01_product_schema".build_overview_friction_source_v1(timestamptz,timestamptz)',
  'EXECUTE') AS friction_anon_denied_ok,
 NOT has_function_privilege('anon',
  '"01_product_schema".build_overview_adoption_source_v1(timestamptz,timestamptz)',
  'EXECUTE') AS adoption_anon_denied_ok
FROM replay ORDER BY id DESC;

ROLLBACK;
