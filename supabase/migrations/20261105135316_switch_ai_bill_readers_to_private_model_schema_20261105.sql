-- Model stage B (2026-11-05): switch ONLY the two service-role-only
-- AI Services RPCs to the private "04_model_schema" reporting view.
-- Existing RPC signatures, grants, response shapes, query validation remain.
-- External writer remains on aia_infra and is mirrored by stage A triggers.
DO $cutover$
DECLARE
  v_fn record;
  v_ddl text;
  old_dashboard jsonb; old_analytics jsonb;
  new_dashboard jsonb; new_analytics jsonb;
BEGIN
  IF to_regclass('"04_model_schema".bill_extraction_reporting_v1') IS NULL
     OR to_regclass('aia_infra.bill_extraction_reporting_v1') IS NULL
  THEN RAISE EXCEPTION 'Expected reporting view missing'; END IF;

  -- Freeze the two source tables during baseline-vs-new results comparison.
  -- The update to each function is rollback-safe within this transaction.
  LOCK TABLE aia_infra.companies,aia_infra.bill_costs IN SHARE ROW EXCLUSIVE MODE;
  IF (SELECT count(*) FROM aia_infra.bill_costs) <>
     (SELECT count(*) FROM "04_model_schema".bill_costs)
     OR (SELECT count(*) FROM aia_infra.companies) <>
        (SELECT count(*) FROM "04_model_schema".companies)
     OR (SELECT count(*) FROM aia_infra.bill_extraction_reporting_v1) <>
        (SELECT count(*) FROM "04_model_schema".bill_extraction_reporting_v1)
  THEN RAISE EXCEPTION 'Source/mirror drift prevents cutover'; END IF;

  old_dashboard:=public.read_ai_bill_extraction_v1('dashboard','2026-09-01'::date,'2026-11-01'::date);
  old_analytics:=public.read_ai_bill_analytics_v1('dashboard','2026-09-01'::date,'2026-11-01'::date);

  FOR v_fn IN
    SELECT p.oid,p.proname
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN
      ('read_ai_bill_extraction_v1','read_ai_bill_analytics_v1')
  LOOP
    SELECT pg_get_functiondef(v_fn.oid) INTO STRICT v_ddl;
    IF position('aia_infra.bill_extraction_reporting_v1' IN v_ddl)=0
      OR position('"04_model_schema".bill_extraction_reporting_v1' IN v_ddl)>0
    THEN RAISE EXCEPTION 'Unexpected RPC dependency for %',v_fn.proname; END IF;
    EXECUTE replace(v_ddl,'aia_infra.bill_extraction_reporting_v1',
       '"04_model_schema".bill_extraction_reporting_v1');
  END LOOP;

  new_dashboard:=public.read_ai_bill_extraction_v1('dashboard','2026-09-01'::date,'2026-11-01'::date);
  new_analytics:=public.read_ai_bill_analytics_v1('dashboard','2026-09-01'::date,'2026-11-01'::date);

  IF new_dashboard->>'contract'<>'ai_bill_extraction_live_v1'
    OR new_analytics->>'contract'<>'ai_bill_analytics_v1'
    OR old_dashboard->'kpis' IS DISTINCT FROM new_dashboard->'kpis'
    OR old_dashboard->'months' IS DISTINCT FROM new_dashboard->'months'
    OR old_dashboard->'docs' IS DISTINCT FROM new_dashboard->'docs'
    OR old_dashboard->'reviews' IS DISTINCT FROM new_dashboard->'reviews'
    OR old_dashboard->'exceptions' IS DISTINCT FROM new_dashboard->'exceptions'
    OR old_analytics->'selected' IS DISTINCT FROM new_analytics->'selected'
    OR old_analytics->'docAnalytics' IS DISTINCT FROM new_analytics->'docAnalytics'
    OR old_analytics->'pageAnalytics' IS DISTINCT FROM new_analytics->'pageAnalytics'
  THEN
    RAISE EXCEPTION 'AI Services RPC response parity failed; aborting cutover';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN
     ('read_ai_bill_extraction_v1','read_ai_bill_analytics_v1')
    AND (has_function_privilege('anon',p.oid,'EXECUTE')
      OR has_function_privilege('authenticated',p.oid,'EXECUTE')
      OR NOT has_function_privilege('service_role',p.oid,'EXECUTE'))
  ) THEN RAISE EXCEPTION 'AI Services function grants differ; abort'; END IF;
END;
$cutover$;