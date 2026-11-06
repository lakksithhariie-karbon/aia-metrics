DO $guard$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'jira_sync' AND rolcanlogin) THEN
   RAISE EXCEPTION 'Expected trusted Jira ingestion role is missing';
 END IF;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = '02_engineering_schema' AND c.relkind = 'r') <> 20 THEN
   RAISE EXCEPTION 'Engineering shadow table inventory changed';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = '02_engineering_schema' AND c.relkind = 'r' AND NOT c.relrowsecurity) THEN
   RAISE EXCEPTION 'RLS missing on shadow tables';
 END IF;
END $guard$;
GRANT USAGE ON SCHEMA "02_engineering_schema" TO jira_sync;
GRANT SELECT ON ALL TABLES IN SCHEMA "02_engineering_schema" TO jira_sync;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA "02_engineering_schema" TO jira_sync;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA "02_engineering_schema" TO jira_sync;
DO $policy$
DECLARE r record;
BEGIN
 FOR r IN SELECT c.relname AS tablename
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = '02_engineering_schema' AND c.relkind = 'r'
 LOOP
   EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE %I.%I TO jira_sync',
                  '02_engineering_schema',r.tablename);
   IF NOT EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = '02_engineering_schema'
                  AND p.tablename = r.tablename AND p.policyname = 'engineering_ingest_rw') THEN
     EXECUTE format('CREATE POLICY engineering_ingest_rw ON %I.%I FOR ALL TO jira_sync USING (true) WITH CHECK (true)',
                    '02_engineering_schema',r.tablename);
   END IF;
 END LOOP;
END $policy$;
