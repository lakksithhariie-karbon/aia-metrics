-- Read-only contract and response canaries, execute after Product reconciliation.
WITH source_readers AS (
 SELECT p.proname,p.proargtypes,p.provolatile,p.prosecdef,
        pg_get_function_identity_arguments(p.oid) args,
        pg_get_function_arguments(p.oid) args_and_defaults,
        pg_get_function_result(p.oid) returns
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname LIKE 'read_%'
   AND p.proname NOT LIKE 'read_jira_%' AND p.proname NOT LIKE 'read_ai_%'
   AND p.proname NOT LIKE 'read_infra_%' AND p.proname NOT LIKE 'read_product_shadow_%'
), shadow_readers AS (
 SELECT p.proname,p.proargtypes,p.provolatile,p.prosecdef,
        pg_get_function_identity_arguments(p.oid) args,
        pg_get_function_arguments(p.oid) args_and_defaults,
        pg_get_function_result(p.oid) returns
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='01_product_schema'
)
SELECT count(*) public_reader_contracts,
 count(*) FILTER(WHERE s.proname IS NULL OR l.proargtypes IS DISTINCT FROM s.proargtypes
 OR l.provolatile IS DISTINCT FROM s.provolatile
 OR l.prosecdef IS DISTINCT FROM s.prosecdef
 OR l.args IS DISTINCT FROM s.args OR l.args_and_defaults IS DISTINCT FROM s.args_and_defaults
 OR l.returns IS DISTINCT FROM s.returns) bad_shadow_contracts
FROM source_readers l LEFT JOIN shadow_readers s ON l.proname=s.proname;

SELECT
 public.read_product_shadow_overview_canary((SELECT max(id) FROM public.product_snapshot))
   IS NOT DISTINCT FROM
 public.read_overview_independent_core_kpis_v4((SELECT max(id) FROM public.product_snapshot))
   AS overview_parity,
 public.read_product_shadow_retention_canary(DATE '2026-09-01',DATE '2026-10-31')
   IS NOT DISTINCT FROM
 public.read_retention_dashboard_v5(DATE '2026-09-01',DATE '2026-10-31')
   AS retention_parity,
 public.read_product_shadow_companies_canary(DATE '2026-09-01',DATE '2026-10-31')
   IS NOT DISTINCT FROM
 public.read_companies_monthly_grid_v2(DATE '2026-09-01',DATE '2026-10-31',NULL,NULL,NULL,NULL,NULL,1,20)
   AS companies_parity;

SELECT
  (public.product_analytics_usage('2026-09','2026-10','month','all')->'pairs')
    IS NOT DISTINCT FROM
  ("01_product_schema".product_analytics_usage('2026-09','2026-10','month','all')->'pairs') AS usage_pairs_parity,
  (public.product_analytics_usage('2026-09','2026-10','month','all')->'rows')
    IS NOT DISTINCT FROM
  ("01_product_schema".product_analytics_usage('2026-09','2026-10','month','all')->'rows') AS usage_rows_parity,
  public.product_analytics_lifecycle()
    IS NOT DISTINCT FROM "01_product_schema".product_analytics_lifecycle() AS lifecycle_parity;
