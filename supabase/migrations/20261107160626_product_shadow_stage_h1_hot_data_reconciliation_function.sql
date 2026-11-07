-- Product H1: guarded manual-only hot-table reconciliation.
-- Source tables are READ ONLY. Shadow writer is NOT scheduled or exposed.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='240s';
CREATE OR REPLACE FUNCTION "01_product_schema".reconcile_hot_product_shadow_v1(p_full boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
SET statement_timeout TO '180s'
AS $f$
DECLARE tab text; n int:=0; copied bigint; changed_events bigint; src bigint; dst bigint;
BEGIN
 IF NOT pg_try_advisory_xact_lock(7242852,20261107) THEN
    RETURN jsonb_build_object('status','busy');
 END IF;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
   WHERE s.nspname='01_product_schema' AND c.relkind='r' AND c.relrowsecurity)<>58
 THEN RAISE EXCEPTION 'Shadow Product inventory not safe'; END IF;
 IF EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
   JOIN pg_namespace s ON s.oid=c.relnamespace
   WHERE s.nspname='01_product_schema' AND c.relname='events' AND NOT t.tgisinternal)
 THEN RAISE EXCEPTION 'Unexpected shadow event side-effect trigger'; END IF;
 IF (SELECT max(id) FROM public.product_snapshot) IS DISTINCT FROM
    (SELECT max(id) FROM "01_product_schema".product_snapshot)
 THEN RAISE EXCEPTION 'New Product snapshots require staged seal and member reconciliation'; END IF;
 MERGE INTO "01_product_schema".events d
 USING (SELECT * FROM public.events
        WHERE coalesce(p_full,false) OR ingested_at >= clock_timestamp()-interval '7 days') s
 ON d.insert_id=s.insert_id
 WHEN MATCHED AND to_jsonb(d) IS DISTINCT FROM to_jsonb(s) THEN
   UPDATE SET
     event_name=s.event_name,event_time=s.event_time,distinct_id=s.distinct_id,
     user_id=s.user_id,uc_uuid=s.uc_uuid,email=s.email,company_id=s.company_id,
     company=s.company,properties=s.properties,ingested_at=s.ingested_at,
     properties_contract=s.properties_contract
 WHEN NOT MATCHED THEN
   INSERT (insert_id,event_name,event_time,distinct_id,user_id,uc_uuid,email,
           company_id,company,properties,ingested_at,properties_contract)
   VALUES (s.insert_id,s.event_name,s.event_time,s.distinct_id,s.user_id,s.uc_uuid,
           s.email,s.company_id,s.company,s.properties,s.ingested_at,s.properties_contract);
 GET DIAGNOSTICS changed_events=ROW_COUNT;
 FOR tab IN SELECT c.relname FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
        WHERE ns.nspname='metrics_private' AND c.relkind='r' ORDER BY c.relname
 LOOP
   EXECUTE format('TRUNCATE TABLE %I.%I','01_product_schema',tab);
   EXECUTE format('INSERT INTO %I.%I SELECT * FROM %I.%I','01_product_schema',tab,'metrics_private',tab);
   GET DIAGNOSTICS copied=ROW_COUNT;
   EXECUTE format('SELECT COUNT(*) FROM %I.%I','01_product_schema',tab) INTO dst;
   IF dst<>copied THEN RAISE EXCEPTION 'Shadow cache count failure %',tab;END IF;
   n:=n+1;
 END LOOP;
 FOREACH tab IN ARRAY ARRAY[
 'client_company','company_activation','company_core_activity','company_day_action',
 'company_directory','company_month_core','company_profile','company_week_action',
 'company_week_product','company_week_value','person_day_action','export_watermarks'
 ] LOOP
   EXECUTE format('TRUNCATE TABLE %I.%I','01_product_schema',tab);
   EXECUTE format('INSERT INTO %I.%I SELECT * FROM public.%I','01_product_schema',tab,tab);
   GET DIAGNOSTICS copied=ROW_COUNT;
   EXECUTE format('SELECT COUNT(*) FROM %I.%I','01_product_schema',tab) INTO dst;
   IF dst<>copied THEN RAISE EXCEPTION 'Shadow hot table count failure %',tab;END IF;
   n:=n+1;
 END LOOP;
 IF n<>38 THEN RAISE EXCEPTION 'Expected 38 hot tables';END IF;
 SELECT count(*) INTO src FROM public.events;
 SELECT count(*) INTO dst FROM "01_product_schema".events;
 IF src<>dst THEN RAISE EXCEPTION 'Shadow event row count differs after reconciliation';END IF;
 RETURN jsonb_build_object('status','ok','hot_tables_refreshed',n,
    'event_rows_updated_or_inserted',changed_events,'event_rows',dst);
END $f$;
REVOKE ALL ON FUNCTION "01_product_schema".reconcile_hot_product_shadow_v1(boolean)
 FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher;
