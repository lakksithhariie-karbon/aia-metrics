-- Product H6: make the scheduled hot reconciliation non-blocking for readers.
-- Source remains read-only; the 39 target cache tables are synchronized with
-- MERGE/DELETE instead of TRUNCATE. No cron command or public function changed.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='90s';
DO $guard$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='01_product_schema' AND p.proname='reconcile_product_hot_delta_v2') THEN
   RAISE EXCEPTION 'Missing verified Product delta reconciliation';END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='01_product_schema' AND p.proname='reconcile_hot_product_shadow_v1'
      AND pg_get_functiondef(p.oid) LIKE '%TRUNCATE TABLE%') THEN
   RAISE EXCEPTION 'Expected old mirror definition not found';END IF;
END $guard$;

CREATE OR REPLACE FUNCTION "01_product_schema".reconcile_hot_product_shadow_v1(p_full boolean DEFAULT false)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
SET statement_timeout TO '180s'
AS $body$
DECLARE changed_events bigint;src bigint;dst bigint;hot_result jsonb;
BEGIN
 IF NOT pg_try_advisory_xact_lock(7242852,20261107) THEN
   RETURN jsonb_build_object('status','busy');
 END IF;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='01_product_schema' AND c.relkind='r' AND c.relrowsecurity)<>58
 THEN RAISE EXCEPTION 'Product shadow inventory or privacy mismatch';END IF;
 IF EXISTS(SELECT 1 FROM pg_trigger tg JOIN pg_class c ON c.oid=tg.tgrelid
     JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='01_product_schema' AND c.relname='events' AND NOT tg.tgisinternal)
 THEN RAISE EXCEPTION 'Unexpected shadow event trigger';END IF;
 IF (SELECT max(id) FROM public.product_snapshot) IS DISTINCT FROM
    (SELECT max(id) FROM "01_product_schema".product_snapshot)
 THEN RAISE EXCEPTION 'Snapshot generation parity required first';END IF;
 MERGE INTO "01_product_schema".events AS d
 USING (SELECT * FROM public.events
        WHERE COALESCE(p_full,false) OR ingested_at >= clock_timestamp()-interval '7 days') AS s
 ON d.insert_id=s.insert_id
 WHEN MATCHED AND to_jsonb(d) IS DISTINCT FROM to_jsonb(s)
 THEN UPDATE SET
    event_name=s.event_name,event_time=s.event_time,distinct_id=s.distinct_id,
    user_id=s.user_id,uc_uuid=s.uc_uuid,email=s.email,company_id=s.company_id,
    company=s.company,properties=s.properties,ingested_at=s.ingested_at,
    properties_contract=s.properties_contract
 WHEN NOT MATCHED THEN INSERT
    (insert_id,event_name,event_time,distinct_id,user_id,uc_uuid,email,
     company_id,company,properties,ingested_at,properties_contract)
 VALUES
    (s.insert_id,s.event_name,s.event_time,s.distinct_id,s.user_id,s.uc_uuid,s.email,
     s.company_id,s.company,s.properties,s.ingested_at,s.properties_contract);
 GET DIAGNOSTICS changed_events=ROW_COUNT;

 hot_result:="01_product_schema".reconcile_product_hot_delta_v2();
 IF hot_result->>'status' IS DISTINCT FROM 'ok' OR
    (hot_result->>'hot_tables')::int<>39 THEN
    RAISE EXCEPTION 'Product 39-table non-blocking reconciliation failed: %',hot_result;
 END IF;
 SELECT count(*) INTO src FROM public.events;
 SELECT count(*) INTO dst FROM "01_product_schema".events;
 IF src<>dst THEN RAISE EXCEPTION 'Product event snapshot row count mismatch: % vs %',src,dst;END IF;
 RETURN jsonb_build_object('status','ok','event_rows',dst,
   'event_rows_updated_or_inserted',changed_events,
   'hot_tables_refreshed',39,'hot_details',hot_result);
END $body$;

REVOKE ALL ON FUNCTION "01_product_schema".reconcile_hot_product_shadow_v1(boolean)
FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher;
