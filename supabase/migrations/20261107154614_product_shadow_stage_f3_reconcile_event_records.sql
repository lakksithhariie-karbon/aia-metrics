-- Product Stage F3: full one-time reconciliation of event rows into shadow.
-- Reads live public.events; writes ONLY "01_product_schema".events.
-- Captures both newly ingested events and source property/identity corrections.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='600s';
DO $sync$
DECLARE src bigint; target bigint;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
          WHERE ns.nspname='01_product_schema' AND c.relname='events'
            AND c.relkind='r' AND c.relrowsecurity)
 THEN RAISE EXCEPTION 'Private target events table missing or RLS not enabled';END IF;
 IF EXISTS(SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
    JOIN pg_namespace ns ON ns.oid=c.relnamespace
    WHERE ns.nspname='01_product_schema' AND c.relname='events' AND NOT t.tgisinternal)
 THEN RAISE EXCEPTION 'Unexpected side-effect trigger on shadow events';END IF;
 MERGE INTO "01_product_schema".events AS target_events
 USING public.events AS live_events
 ON target_events.insert_id=live_events.insert_id
 WHEN MATCHED AND (
      target_events.event_name IS DISTINCT FROM live_events.event_name OR
      target_events.event_time IS DISTINCT FROM live_events.event_time OR
      target_events.distinct_id IS DISTINCT FROM live_events.distinct_id OR
      target_events.user_id IS DISTINCT FROM live_events.user_id OR
      target_events.uc_uuid IS DISTINCT FROM live_events.uc_uuid OR
      target_events.email IS DISTINCT FROM live_events.email OR
      target_events.company_id IS DISTINCT FROM live_events.company_id OR
      target_events.company IS DISTINCT FROM live_events.company OR
      target_events.properties IS DISTINCT FROM live_events.properties OR
      target_events.ingested_at IS DISTINCT FROM live_events.ingested_at OR
      target_events.properties_contract IS DISTINCT FROM live_events.properties_contract
 ) THEN UPDATE SET
      event_name=live_events.event_name,
      event_time=live_events.event_time,
      distinct_id=live_events.distinct_id,
      user_id=live_events.user_id,
      uc_uuid=live_events.uc_uuid,
      email=live_events.email,
      company_id=live_events.company_id,
      company=live_events.company,
      properties=live_events.properties,
      ingested_at=live_events.ingested_at,
      properties_contract=live_events.properties_contract
 WHEN NOT MATCHED THEN INSERT
     (insert_id,event_name,event_time,distinct_id,user_id,uc_uuid,email,company_id,company,
      properties,ingested_at,properties_contract)
 VALUES
     (live_events.insert_id,live_events.event_name,live_events.event_time,
      live_events.distinct_id,live_events.user_id,live_events.uc_uuid,live_events.email,
      live_events.company_id,live_events.company,live_events.properties,live_events.ingested_at,
      live_events.properties_contract);
 SELECT count(*) INTO src FROM public.events;
 SELECT count(*) INTO target FROM "01_product_schema".events;
 IF target<src THEN RAISE EXCEPTION 'Shadow events missing % source rows',src-target;END IF;
END $sync$;
