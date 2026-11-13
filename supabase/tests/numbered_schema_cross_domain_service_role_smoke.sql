-- Repeatable service-role-only reporting smoke test across all four numbered schemas.
-- READ ONLY. This tests database RPC contracts, not authenticated HTTP routing.
-- All values must be true. Model source bill counts are checked separately by parity.
BEGIN READ ONLY;
SET LOCAL ROLE service_role;
SELECT
  jsonb_typeof(public.read_jira_delivery_dashboard_v1(1271,NULL,NULL,NULL,NULL)) = 'object'
    AS engineering_dashboard_rpc_ok,
  jsonb_typeof(public.read_infra_aws_live_v1()) = 'object'
    AS infra_dashboard_rpc_ok,
  public.read_ai_bill_extraction_v1('dashboard',DATE '2026-09-01',DATE '2026-11-01')->>'contract'
      = 'ai_bill_extraction_live_v1' AS model_extraction_rpc_ok,
  public.read_ai_bill_analytics_v1('dashboard',DATE '2026-09-01',DATE '2026-11-01')->>'contract'
      = 'ai_bill_analytics_v1' AS model_analytics_rpc_ok,
  jsonb_typeof(public.read_product_shadow_overview_canary(NULL::bigint)) = 'object'
    AS product_overview_shadow_rpc_ok,
  jsonb_typeof(public.read_product_shadow_retention_canary(DATE '2026-09-01',DATE '2026-10-31')) = 'object'
    AS product_retention_shadow_rpc_ok,
  jsonb_typeof(public.read_product_shadow_companies_canary(DATE '2026-09-01',DATE '2026-10-31')) = 'object'
    AS product_companies_shadow_rpc_ok;
ROLLBACK;
