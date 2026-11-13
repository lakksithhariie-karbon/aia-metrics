-- READ ONLY source-level live Overview preview. This is NOT a
-- publication or a substitute for the 5 legacy snapshot kinds and drill
-- memberships. All five source reports use the SAME completed watermark and
-- as-of timestamp, and expose only aggregate facts in this test.
BEGIN READ ONLY;
SET LOCAL statement_timeout='150s';
WITH generation AS MATERIALIZED (
 SELECT w.last_success_at AS wm,now() AS asof
 FROM "01_product_schema".export_watermarks w
 WHERE w.job_name='incremental' AND w.status='ok' LIMIT 1
), reports AS MATERIALIZED (
 SELECT g.wm,g.asof,
 "01_product_schema".build_overview_activity_source_v1(g.asof,g.wm) AS activity,
 "01_product_schema".build_overview_active_charts_source_v1(g.asof,g.wm) AS charts,
 "01_product_schema".build_overview_workflow_source_v1(g.asof,g.wm) AS workflow,
 "01_product_schema".build_overview_friction_source_v1(g.asof,g.wm) AS friction,
 "01_product_schema".build_overview_adoption_source_v1(g.asof,g.wm) AS adoption
 FROM generation g
)
SELECT wm,asof,
 activity->>'dau' AS dau,activity->>'wau_current' AS wau,activity->>'mau_current' AS mau,
 jsonb_array_length(charts#>'{weekly,rows}') AS active_week_count,
 charts#>>'{frequency,total_users}' AS independent_4week_users,
 jsonb_array_length(workflow->'weekly') AS workflow_week_count,
 workflow#>>'{mix,current_total}' AS workflow_active_companies,
 jsonb_array_length(friction->'rows') AS friction_issue_count,
 adoption->>'total' AS adoption_eligible_companies,
 adoption#>>'{outcomes,core_7d}' AS adoption_started_work,
 adoption#>>'{outcomes,value_28d}' AS adoption_reached_value,
 (
 activity->>'source_watermark_at'=charts->>'source_watermark_at'
 AND activity->>'source_watermark_at'=workflow->>'source_watermark_at'
 AND activity->>'source_watermark_at'=friction->>'source_watermark_at'
 AND activity->>'source_watermark_at'=adoption->>'source_watermark_at'
 ) AS five_reports_same_watermark_ok,
 (SELECT count(*) FROM public.events) AS legacy_event_rows,
 (SELECT count(*) FROM "01_product_schema".events) AS shadow_event_rows,
 (
 wm>=asof-interval '24 hours'
 AND (SELECT count(*) FROM public.events)=(SELECT count(*) FROM "01_product_schema".events)
 ) AS fresh_source_and_event_counts_ok
FROM reports;
ROLLBACK;
