-- Engineering rebuild stage A: independent physical copies, 2026-11-06.
-- Non-destructive: never rename, drop, truncate, update, or delete jira sources.
-- No changes to feature_olap, product_source, Infra, Model, or Product.
-- This is an INITIAL CONSISTENT SNAPSHOT. New inserts after the snapshot are
-- intentionally NOT live until a separately verified ingestion cutover.
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET LOCAL lock_timeout = '8s';
SET LOCAL statement_timeout = '240s';

DO $stage$
DECLARE
 v_target oid;
 v_source oid;
 v_r record;
 v_fk record;
 v_a record;
 v_seq text;
 v_max bigint;
 v_old_count bigint;
 v_new_count bigint;
 v_n integer:=0;
 v_fk_n integer:=0;
BEGIN
 SELECT oid INTO STRICT v_target FROM pg_namespace
 WHERE nspname='02_engineering_schema';
 SELECT oid INTO STRICT v_source FROM pg_namespace
 WHERE nspname='jira';
 IF EXISTS(SELECT 1 FROM pg_class WHERE relnamespace=v_target)
   OR EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace=v_target)
   OR EXISTS(SELECT 1 FROM pg_type WHERE typnamespace=v_target)
 THEN RAISE EXCEPTION 'Engineering destination is not empty, refusing to overwrite'; END IF;
 IF (SELECT count(*) FROM pg_class WHERE relnamespace=v_source AND relkind='r')<>20
 THEN RAISE EXCEPTION 'Source Jira table inventory differs from audit'; END IF;
 -- Preserve the source's 20-table state under one repeatable-read snapshot.
 -- No source table locks, Jira sync and dashboard remain fully operational.
 FOR v_r IN SELECT c.oid,c.relname
    FROM pg_class c WHERE c.relnamespace=v_source AND c.relkind='r'
    ORDER BY c.relname
 LOOP
   EXECUTE format(
     'CREATE TABLE "02_engineering_schema".%I (LIKE jira.%I INCLUDING ALL)',
     v_r.relname,v_r.relname);
   EXECUTE format(
     'INSERT INTO "02_engineering_schema".%I OVERRIDING SYSTEM VALUE SELECT * FROM jira.%I',
     v_r.relname,v_r.relname);
   EXECUTE format('SELECT count(*) FROM jira.%I',v_r.relname)
     INTO v_old_count;
   EXECUTE format('SELECT count(*) FROM "02_engineering_schema".%I',v_r.relname)
     INTO v_new_count;
   IF v_new_count<>v_old_count THEN
     RAISE EXCEPTION 'Snapshot count mismatch on %: old %, new %',
       v_r.relname,v_old_count,v_new_count;
   END IF;
   -- New copies default to private RLS-protected read-only access.
   EXECUTE format('ALTER TABLE "02_engineering_schema".%I ENABLE ROW LEVEL SECURITY',
     v_r.relname);
   EXECUTE format('REVOKE ALL ON TABLE "02_engineering_schema".%I FROM PUBLIC, anon, authenticated, service_role, product_metrics_fetcher, jira_sync',
     v_r.relname);
   EXECUTE format('GRANT SELECT ON TABLE "02_engineering_schema".%I TO product_metrics_fetcher',
     v_r.relname);
   EXECUTE format('CREATE POLICY engineering_snapshot_reader ON "02_engineering_schema".%I FOR SELECT TO product_metrics_fetcher USING (true)',
     v_r.relname);
   v_n:=v_n+1;
 END LOOP;
 IF v_n<>20 THEN RAISE EXCEPTION 'Expected 20 Engineering tables, got %',v_n; END IF;

 -- LIKE INCLUDING ALL copies PKs, UNIQUE, CHECKs, indexes and identity
 -- sequences. It does NOT copy FKs, so recreate them within the new schema.
 FOR v_fk IN
   SELECT c.relname,co.conname,pg_get_constraintdef(co.oid) AS definition
   FROM pg_constraint co
   JOIN pg_class c ON c.oid=co.conrelid
   WHERE c.relnamespace=v_source AND co.contype='f'
   ORDER BY c.relname,co.conname
 LOOP
   IF position('REFERENCES jira.' IN v_fk.definition)=0 THEN
      RAISE EXCEPTION 'FK references unexpected schema: %',v_fk.conname; END IF;
   EXECUTE format(
      'ALTER TABLE "02_engineering_schema".%I ADD CONSTRAINT %I %s',
      v_fk.relname,v_fk.conname,
      replace(v_fk.definition,'REFERENCES jira.','REFERENCES "02_engineering_schema".'));
   v_fk_n:=v_fk_n+1;
 END LOOP;
 IF v_fk_n<>10 THEN RAISE EXCEPTION 'FK count mismatch: %',v_fk_n; END IF;

 -- Reset independent IDENTITY sequences after explicit identity-value copies.
 FOR v_a IN
  SELECT c.relname,a.attname
  FROM pg_class c
  JOIN pg_attribute a ON a.attrelid=c.oid
  WHERE c.relnamespace=v_source AND c.relkind='r'
    AND a.attnum>0 AND a.attidentity<>''
 LOOP
   v_seq:=pg_get_serial_sequence(format('"02_engineering_schema".%I',v_a.relname),
                                v_a.attname);
   IF v_seq IS NULL THEN RAISE EXCEPTION 'Missing new identity sequence %.%',v_a.relname,v_a.attname; END IF;
   EXECUTE format('SELECT max(%I) FROM "02_engineering_schema".%I',
                  v_a.attname,v_a.relname) INTO v_max;
   PERFORM setval(v_seq::regclass,greatest(coalesce(v_max,0),1),
                  coalesce(v_max,0)>0);
 END LOOP;

 GRANT USAGE ON SCHEMA "02_engineering_schema" TO product_metrics_fetcher;
 -- No anonymous, authenticated or service-role schema access.
 IF has_schema_privilege('anon','02_engineering_schema','USAGE')
    OR has_schema_privilege('authenticated','02_engineering_schema','USAGE')
    OR has_schema_privilege('service_role','02_engineering_schema','USAGE')
 THEN RAISE EXCEPTION 'Engineering schema exposure detected'; END IF;

 IF (SELECT count(*) FROM pg_class WHERE relnamespace=v_target AND relkind='r')<>20
 OR (SELECT count(*) FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid
    WHERE c.relnamespace=v_target AND co.contype='f')<>10
 OR (SELECT count(*) FROM pg_class WHERE relnamespace=v_target AND relkind='S')<>3
 THEN RAISE EXCEPTION 'New Engineering physical table structure incomplete'; END IF;
END;
$stage$;
