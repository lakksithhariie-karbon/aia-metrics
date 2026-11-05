-- EMERGENCY MODEL READER ROLLBACK ONLY. Do NOT apply during normal migration.
-- Switch existing two service-role RPCs back to legacy aia_infra view.
-- Source tables remain canonical for external INSERT ... ON CONFLICT ingestion.
-- No table copies, mirror triggers, privileges or data are removed.
DO $rollback$
DECLARE rec record; definition text; checked integer:=0;
BEGIN
  IF to_regclass('aia_infra.bill_extraction_reporting_v1') IS NULL
  THEN RAISE EXCEPTION 'Old Model reporting view absent'; END IF;
  FOR rec IN
    SELECT p.oid,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN
      ('read_ai_bill_extraction_v1','read_ai_bill_analytics_v1')
  LOOP
    SELECT pg_get_functiondef(rec.oid) INTO definition;
    IF position('"04_model_schema".bill_extraction_reporting_v1' IN definition)=0
    THEN RAISE EXCEPTION 'Unexpected function definition for %',rec.proname; END IF;
    EXECUTE replace(definition,
      '"04_model_schema".bill_extraction_reporting_v1',
      'aia_infra.bill_extraction_reporting_v1');
    checked:=checked+1;
  END LOOP;
  IF checked<>2 THEN RAISE EXCEPTION 'Expected exactly 2 Model reporting functions'; END IF;
  IF public.read_ai_bill_extraction_v1('dashboard','2026-09-01'::date,'2026-11-01'::date)->>'contract'
    <> 'ai_bill_extraction_live_v1'
     OR public.read_ai_bill_analytics_v1('dashboard','2026-09-01'::date,'2026-11-01'::date)->>'contract'
    <> 'ai_bill_analytics_v1'
  THEN RAISE EXCEPTION 'Rollback RPC contract failed'; END IF;
END;
$rollback$;
-- Important: DO NOT DROP "04_model_schema" mirror or source-table triggers.
-- Restore new routing with migration 20261105135316 only after assessing live state.