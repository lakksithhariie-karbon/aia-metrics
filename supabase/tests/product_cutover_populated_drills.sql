-- Read-only parity using POPULATED production members, not NULL-only canaries.
-- Run after shadow reconciliation; counts must be positive and missing_from_shadow = 0.
-- Uses real snapshot, company and month values discovered from existing rows.

-- overview_populated_header
WITH sample AS MATERIALIZED (
 SELECT d.snapshot_id,d.kind,d.drill_key,d.tab FROM public.product_overview_drill d
 JOIN public.product_overview_member m USING(snapshot_id,kind,drill_key,tab)
 ORDER BY d.snapshot_id DESC LIMIT 1
)
SELECT 'overview_populated_header' AS test_name, source_rows.cnt AS source_rows,
 shadow_rows.cnt AS shadow_rows, delta.cnt AS missing_from_shadow,
 (source_rows.cnt > 0 AND source_rows.cnt=shadow_rows.cnt AND delta.cnt=0) AS pass
FROM sample s
CROSS JOIN LATERAL (SELECT count(*) cnt FROM public.read_overview_drill_header(s.snapshot_id,s.kind,s.drill_key,s.tab) t) source_rows
CROSS JOIN LATERAL (SELECT count(*) cnt FROM "01_product_schema".read_overview_drill_header(s.snapshot_id,s.kind,s.drill_key,s.tab) t) shadow_rows
CROSS JOIN LATERAL (SELECT count(*) cnt FROM (
 SELECT to_jsonb(t) val FROM public.read_overview_drill_header(s.snapshot_id,s.kind,s.drill_key,s.tab) t
 EXCEPT ALL SELECT to_jsonb(t) FROM "01_product_schema".read_overview_drill_header(s.snapshot_id,s.kind,s.drill_key,s.tab) t
 ) differences) delta;

-- overview_populated_members
WITH sample AS MATERIALIZED (
 SELECT d.snapshot_id,d.kind,d.drill_key,d.tab FROM public.product_overview_drill d
 JOIN public.product_overview_member m USING(snapshot_id,kind,drill_key,tab)
 ORDER BY d.snapshot_id DESC LIMIT 1
)
SELECT 'overview_populated_members' AS test_name, source_rows.cnt AS source_rows,
 shadow_rows.cnt AS shadow_rows, delta.cnt AS missing_from_shadow,
 (source_rows.cnt > 0 AND source_rows.cnt=shadow_rows.cnt AND delta.cnt=0) AS pass
FROM sample s
CROSS JOIN LATERAL (SELECT count(*) cnt FROM public.read_overview_members(s.snapshot_id,s.kind,s.drill_key,s.tab,12,0) t) source_rows
CROSS JOIN LATERAL (SELECT count(*) cnt FROM "01_product_schema".read_overview_members(s.snapshot_id,s.kind,s.drill_key,s.tab,12,0) t) shadow_rows
CROSS JOIN LATERAL (SELECT count(*) cnt FROM (
 SELECT to_jsonb(t) val FROM public.read_overview_members(s.snapshot_id,s.kind,s.drill_key,s.tab,12,0) t
 EXCEPT ALL SELECT to_jsonb(t) FROM "01_product_schema".read_overview_members(s.snapshot_id,s.kind,s.drill_key,s.tab,12,0) t
 ) differences) delta;

-- funnel_populated_header
WITH sample AS MATERIALIZED (
 SELECT d.snapshot_id,d.node_key,d.tab FROM public.product_funnel_drill d
 JOIN public.product_funnel_member m USING(snapshot_id,node_key,tab)
 ORDER BY d.snapshot_id DESC LIMIT 1
)
SELECT 'funnel_populated_header' AS test_name, source_rows.cnt AS source_rows,
 shadow_rows.cnt AS shadow_rows, delta.cnt AS missing_from_shadow,
 (source_rows.cnt > 0 AND source_rows.cnt=shadow_rows.cnt AND delta.cnt=0) AS pass
FROM sample s
CROSS JOIN LATERAL (SELECT count(*) cnt FROM public.read_funnel_drill_header(s.snapshot_id,s.node_key,s.tab) t) source_rows
CROSS JOIN LATERAL (SELECT count(*) cnt FROM "01_product_schema".read_funnel_drill_header(s.snapshot_id,s.node_key,s.tab) t) shadow_rows
CROSS JOIN LATERAL (SELECT count(*) cnt FROM (
 SELECT to_jsonb(t) val FROM public.read_funnel_drill_header(s.snapshot_id,s.node_key,s.tab) t
 EXCEPT ALL SELECT to_jsonb(t) FROM "01_product_schema".read_funnel_drill_header(s.snapshot_id,s.node_key,s.tab) t
 ) differences) delta;

-- funnel_populated_members
WITH sample AS MATERIALIZED (
 SELECT d.snapshot_id,d.node_key,d.tab FROM public.product_funnel_drill d
 JOIN public.product_funnel_member m USING(snapshot_id,node_key,tab)
 ORDER BY d.snapshot_id DESC LIMIT 1
)
SELECT 'funnel_populated_members' AS test_name, source_rows.cnt AS source_rows,
 shadow_rows.cnt AS shadow_rows, delta.cnt AS missing_from_shadow,
 (source_rows.cnt > 0 AND source_rows.cnt=shadow_rows.cnt AND delta.cnt=0) AS pass
FROM sample s
CROSS JOIN LATERAL (SELECT count(*) cnt FROM public.read_funnel_members(s.snapshot_id,s.node_key,s.tab,12,0) t) source_rows
CROSS JOIN LATERAL (SELECT count(*) cnt FROM "01_product_schema".read_funnel_members(s.snapshot_id,s.node_key,s.tab,12,0) t) shadow_rows
CROSS JOIN LATERAL (SELECT count(*) cnt FROM (
 SELECT to_jsonb(t) val FROM public.read_funnel_members(s.snapshot_id,s.node_key,s.tab,12,0) t
 EXCEPT ALL SELECT to_jsonb(t) FROM "01_product_schema".read_funnel_members(s.snapshot_id,s.node_key,s.tab,12,0) t
 ) differences) delta;

-- companies_monthly_populated_breakdown
WITH sample AS MATERIALIZED (
 SELECT company_id,module,month_start FROM metrics_private.company_month_module_usage
 WHERE events > 0 ORDER BY month_start DESC,events DESC LIMIT 1
)
SELECT 'companies_monthly_populated_breakdown' AS test_name, source_rows.cnt AS source_rows,
 shadow_rows.cnt AS shadow_rows, delta.cnt AS missing_from_shadow,
 (source_rows.cnt > 0 AND source_rows.cnt=shadow_rows.cnt AND delta.cnt=0) AS pass
FROM sample s
CROSS JOIN LATERAL (SELECT count(*) cnt FROM public.read_companies_monthly_breakdown_v2(s.company_id,s.module,NULL::text,s.month_start) t) source_rows
CROSS JOIN LATERAL (SELECT count(*) cnt FROM "01_product_schema".read_companies_monthly_breakdown_v2(s.company_id,s.module,NULL::text,s.month_start) t) shadow_rows
CROSS JOIN LATERAL (SELECT count(*) cnt FROM (
 SELECT to_jsonb(t) val FROM public.read_companies_monthly_breakdown_v2(s.company_id,s.module,NULL::text,s.month_start) t
 EXCEPT ALL SELECT to_jsonb(t) FROM "01_product_schema".read_companies_monthly_breakdown_v2(s.company_id,s.module,NULL::text,s.month_start) t
 ) differences) delta;
