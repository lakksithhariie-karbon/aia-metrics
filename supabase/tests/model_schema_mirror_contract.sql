-- Read-only validation. Every Boolean returned should be true.
-- This checks physical mirrored rows, generated columns, reporting projection,
-- least-privilege ACLs and the two live RPC sources. It does not modify any data.
SELECT
  (SELECT count(*) FROM aia_infra.companies)
  = (SELECT count(*) FROM "04_model_schema".companies) AS company_rows_match,
  (SELECT count(*) FROM aia_infra.bill_costs)
  = (SELECT count(*) FROM "04_model_schema".bill_costs) AS bill_rows_match,
  (SELECT count(*) FROM aia_infra.bill_extraction_reporting_v1)
  = (SELECT count(*) FROM "04_model_schema".bill_extraction_reporting_v1) AS reporting_rows_match,
  (SELECT max(loaded_at) FROM aia_infra.bill_costs)
  IS NOT DISTINCT FROM
  (SELECT max(loaded_at) FROM "04_model_schema".bill_costs) AS last_ingestion_matches,
  NOT EXISTS (
    SELECT 1 FROM aia_infra.bill_costs old
    FULL JOIN "04_model_schema".bill_costs newer USING(prediction_uuid)
    WHERE to_jsonb(old) IS DISTINCT FROM to_jsonb(newer)
  ) AS bill_values_match,
  NOT EXISTS (
    SELECT 1 FROM aia_infra.companies old
    FULL JOIN "04_model_schema".companies newer USING(company_uuid)
    WHERE to_jsonb(old) IS DISTINCT FROM to_jsonb(newer)
  ) AS company_values_match,
  NOT EXISTS (
    SELECT 1 FROM aia_infra.bill_extraction_reporting_v1 old
    FULL JOIN "04_model_schema".bill_extraction_reporting_v1 newer USING(prediction_uuid)
    WHERE to_jsonb(old) IS DISTINCT FROM to_jsonb(newer)
  ) AS reporting_values_match,
  (SELECT bool_and(c.relrowsecurity)
   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='04_model_schema' AND c.relkind='r') AS all_target_tables_rls_enabled,
  NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='04_model_schema' AND c.relkind IN ('r','v')
      AND (has_table_privilege('anon',c.oid,'SELECT')
       OR has_table_privilege('authenticated',c.oid,'SELECT')
       OR has_table_privilege('service_role',c.oid,'SELECT'))
  ) AS no_public_or_service_direct_reads,
  (SELECT count(*)=2 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public'
    AND p.proname IN ('read_ai_bill_extraction_v1','read_ai_bill_analytics_v1')
    AND p.prosrc LIKE '%"04_model_schema".bill_extraction_reporting_v1%'
    AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
    AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')
    AND has_function_privilege('service_role',p.oid,'EXECUTE')) AS rpc_cutover_secure;