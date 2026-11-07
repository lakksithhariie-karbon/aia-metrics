-- Product H5: non-blocking delta reconciliation of all 39 hot Product tables.
-- Replaces snapshot TRUNCATE strategy for eventual reader cutover.
-- Original public/metrics_private tables are SELECT-only throughout.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='60s';
CREATE OR REPLACE FUNCTION "01_product_schema".reconcile_product_hot_delta_v2()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
SET statement_timeout TO '180s'
AS $body$
DECLARE
  tbl record;
  a record;
  on_clause text;
  cols text;
  src_values text;
  set_clause text;
  sql_command text;
  merged_rows bigint;
  deleted_rows bigint;
  affected bigint:=0;
  purged bigint:=0;
  table_count integer:=0;
  dst_count bigint;
  src_count bigint;
BEGIN
 IF NOT pg_try_advisory_xact_lock(7242852,20261107) THEN
    RETURN jsonb_build_object('status','busy');
 END IF;
 IF (SELECT COUNT(*) FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
     WHERE ns.nspname='01_product_schema' AND c.relkind='r' AND c.relrowsecurity)<>58
 THEN RAISE EXCEPTION 'Target Product schema not safely staged'; END IF;
 FOR tbl IN
   SELECT ns.nspname source_schema,c.relname tab,c.oid source_oid
   FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
   WHERE c.relkind='r' AND
    (ns.nspname='metrics_private' OR (ns.nspname='public' AND c.relname=ANY(ARRAY[
      'client_company','company_activation','company_core_activity','company_day_action',
      'company_directory','company_month_core','company_profile','company_week_action',
      'company_week_product','company_week_value','person_day_action','export_watermarks',
      'retention_cells'])))
   ORDER BY ns.nspname,c.relname
 LOOP
   SELECT string_agg(format('d.%I = s.%I',att.attname,att.attname),' AND ' ORDER BY keypos.ordinality)
     INTO on_clause
   FROM pg_index pk
   CROSS JOIN LATERAL unnest(pk.indkey) WITH ORDINALITY keypos(attnum,ordinality)
   JOIN pg_attribute att ON att.attrelid=pk.indrelid AND att.attnum=keypos.attnum
   WHERE pk.indrelid=tbl.source_oid AND pk.indisprimary;
   IF on_clause IS NULL THEN RAISE EXCEPTION 'Primary key missing for %',tbl.tab;END IF;
   SELECT string_agg(format('%I',att.attname),',' ORDER BY att.attnum),
          string_agg(format('s.%I',att.attname),',' ORDER BY att.attnum),
          string_agg(format('%I=s.%I',att.attname,att.attname),',' ORDER BY att.attnum)
             FILTER (WHERE NOT EXISTS (
               SELECT 1 FROM pg_index pk JOIN LATERAL unnest(pk.indkey) keyatt(attnum) ON true
               WHERE pk.indrelid=tbl.source_oid AND pk.indisprimary AND keyatt.attnum=att.attnum))
   INTO cols,src_values,set_clause
   FROM pg_attribute att WHERE att.attrelid=tbl.source_oid
      AND att.attnum>0 AND NOT att.attisdropped AND att.attidentity='' AND att.attgenerated='';
   IF cols IS NULL THEN RAISE EXCEPTION 'Missing ordinary columns for %',tbl.tab;END IF;
   sql_command:=format(
     'MERGE INTO %I.%I AS d USING %I.%I AS s ON (%s) %s WHEN NOT MATCHED THEN INSERT(%s) VALUES(%s)',
     '01_product_schema',tbl.tab,tbl.source_schema,tbl.tab,on_clause,
     CASE WHEN set_clause IS NULL THEN ''
       ELSE format('WHEN MATCHED AND to_jsonb(d) IS DISTINCT FROM to_jsonb(s) THEN UPDATE SET %s',set_clause)
     END,cols,src_values);
   EXECUTE sql_command;
   GET DIAGNOSTICS merged_rows=ROW_COUNT;
   affected:=affected+merged_rows;
   EXECUTE format('DELETE FROM %I.%I AS d WHERE NOT EXISTS (SELECT 1 FROM %I.%I AS s WHERE %s)',
      '01_product_schema',tbl.tab,tbl.source_schema,tbl.tab,on_clause);
   GET DIAGNOSTICS deleted_rows=ROW_COUNT;
   purged:=purged+deleted_rows;
   EXECUTE format('SELECT count(*) FROM %I.%I','01_product_schema',tbl.tab) INTO dst_count;
   EXECUTE format('SELECT count(*) FROM %I.%I',tbl.source_schema,tbl.tab) INTO src_count;
   IF dst_count<>src_count THEN
     RAISE EXCEPTION 'Source/target count mismatch in %.%: % vs %',
       tbl.source_schema,tbl.tab,src_count,dst_count;
   END IF;
   table_count:=table_count+1;
 END LOOP;
 IF table_count<>39 THEN RAISE EXCEPTION 'Unexpected Product hot table inventory %',table_count;END IF;
 RETURN jsonb_build_object('status','ok','hot_tables',table_count,
   'upserts',affected,'deletions',purged);
END $body$;
REVOKE ALL ON FUNCTION "01_product_schema".reconcile_product_hot_delta_v2()
FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher;
