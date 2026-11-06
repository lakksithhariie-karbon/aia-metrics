-- Engineering schema cutover, 2026-11-06.
-- OBJECT-PRESERVING: neither source tables nor their rows are copied or dropped.
-- Source schema OID, all relation OIDs, indexes, FKs, sequences and ACLs are retained.
-- Empty reserved destination namespace is renamed to backup (not dropped).
-- Requires jira-sync Edge Function with dual search_path before applying.
-- Strictly exclude teammate-owned feature_olap and product_source.
SET LOCAL lock_timeout = '8s';
SET LOCAL statement_timeout = '180s';

DO $migrate$
DECLARE
  v_old oid;
  v_dest oid;
  v_cron_id bigint;
  v_cron_cmd text;
  v_ddl text;
  v_initial_search_path text;
  v_initial_function_check text;
  v_probe boolean;
  rec record;
  v_table_names text;
  v_count bigint;
  v_rewritten integer := 0;
BEGIN
  SELECT oid INTO STRICT v_old FROM pg_namespace WHERE nspname = 'jira';
  SELECT oid INTO STRICT v_dest FROM pg_namespace WHERE nspname = '02_engineering_schema';

  IF EXISTS (SELECT 1 FROM pg_class WHERE relnamespace=v_dest)
     OR EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace=v_dest)
     OR EXISTS (SELECT 1 FROM pg_type WHERE typnamespace=v_dest)
  THEN RAISE EXCEPTION 'Destination schema is not empty; refusing cutover'; END IF;
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='02_engineering_schema_reserved_20261106')
  THEN RAISE EXCEPTION 'Reserved schema backup already exists'; END IF;
  IF (SELECT count(*) FROM pg_class WHERE relnamespace=v_old AND relkind='r') <> 20
    OR (SELECT count(*) FROM pg_class WHERE relnamespace=v_old AND relkind='v') <> 39
    OR (SELECT count(*) FROM pg_class WHERE relnamespace=v_old AND relkind='m') <> 4
    OR (SELECT count(*) FROM pg_class WHERE relnamespace=v_old AND relkind='S') <> 3
    OR (SELECT count(*) FROM pg_proc WHERE pronamespace=v_old) <> 35
  THEN RAISE EXCEPTION 'Jira object inventory differs; refusing cutover'; END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public'
      AND p.proname IN('read_jira_delivery_dashboard_v1','read_jira_delivery_evidence_v1',
                      'read_jira_delivery_evidence_v2','read_jira_delivery_issue_v1')) <> 4
  THEN RAISE EXCEPTION 'Public Jira RPC inventory differs'; END IF;
  IF NOT EXISTS (SELECT 1 FROM jira.sync_log WHERE id=(SELECT max(id) FROM jira.sync_log)
    AND finished_at > now()-interval '2 days' AND errors_count=0)
  THEN RAISE EXCEPTION 'Latest Jira sync is not recent and clean'; END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname='jira-dashboard-snapshot-watchdog'
      AND active AND schedule='*/5 * * * *'
      AND command LIKE '%jira.refresh_metric_cohorts()%')
    OR (SELECT count(*) FROM cron.job WHERE active AND jobname IN
      ('jira-sync-0230utc','jira-sync-1230utc'))<>2
  THEN RAISE EXCEPTION 'Jira schedules differ from audited baseline'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_db_role_setting s JOIN pg_roles r ON r.oid=s.setrole
    WHERE r.rolname='jira_sync' AND s.setdatabase=0
    AND 'search_path=jira, public'=ANY(s.setconfig))
  THEN RAISE EXCEPTION 'Jira writer role search_path changed'; END IF;

  -- Prevent source writes while capturing and rechecking every existing row.
  SELECT string_agg(format('jira.%I',c.relname),',' ORDER BY c.relname)
    INTO v_table_names FROM pg_class c
    WHERE c.relnamespace=v_old AND c.relkind='r';
  EXECUTE 'LOCK TABLE '||v_table_names||' IN SHARE MODE';

  CREATE TEMP TABLE engineering_cutover_counts
   (old_oid oid PRIMARY KEY,rel_name text NOT NULL,old_rows bigint NOT NULL)
   ON COMMIT DROP;
  FOR rec IN SELECT oid,relname FROM pg_class
             WHERE relnamespace=v_old AND relkind='r' ORDER BY relname
  LOOP
    EXECUTE format('SELECT count(*) FROM jira.%I',rec.relname) INTO v_count;
    INSERT INTO engineering_cutover_counts VALUES(rec.oid,rec.relname,v_count);
  END LOOP;

  -- The original Jira schema is renamed, not reconstructed. All data objects
  -- retain their original OIDs and foreign key / view dependency graph.
  EXECUTE 'ALTER SCHEMA "02_engineering_schema" RENAME TO "02_engineering_schema_reserved_20261106"';
  EXECUTE 'ALTER SCHEMA jira RENAME TO "02_engineering_schema"';
  v_initial_search_path:=current_setting('search_path');
  PERFORM set_config('search_path','"02_engineering_schema",public,pg_catalog',true);
  v_initial_function_check:=current_setting('check_function_bodies');
  -- PostgreSQL validates interdependent SQL functions before other definitions
  -- have been rewritten; pg_dump uses this same session-scoped mechanism.
  -- Re-enable validation and run live helper/view checks before committing.
  PERFORM set_config('check_function_bodies','off',true);

  -- Function bodies are stored SQL text. Only their explicit jira qualifier
  -- and SET search_path clause need to change after the schema rename.
  FOR rec IN
    SELECT p.oid,p.proname,n.nspname
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.oid=v_old
       OR (n.nspname='public' AND p.proname IN
         ('read_jira_delivery_dashboard_v1','read_jira_delivery_evidence_v1',
          'read_jira_delivery_evidence_v2','read_jira_delivery_issue_v1'))
    ORDER BY n.nspname,p.proname
  LOOP
    SELECT pg_get_functiondef(rec.oid) INTO v_ddl;
    IF position('jira.' IN v_ddl)>0 THEN
      v_ddl:=replace(v_ddl,'jira.','"02_engineering_schema".');
    END IF;
    v_ddl:=replace(v_ddl,'SET search_path TO ''jira'',',
                   'SET search_path TO ''"02_engineering_schema"'',');
    EXECUTE v_ddl;
    v_rewritten:=v_rewritten+1;
  END LOOP;
  PERFORM set_config('check_function_bodies',v_initial_function_check,true);
  PERFORM set_config('search_path',v_initial_search_path,true);
  IF v_rewritten<>39 THEN
    RAISE EXCEPTION 'Expected 39 rewritten functions; got %',v_rewritten;
  END IF;

  -- Runtime probes after re-enabling body validation. They compile new SQL
  -- bodies, traverse an actual moved helper and a live reporting view.
  EXECUTE 'SELECT "02_engineering_schema"._filter_cohort_row_matches(
     ''{"sprint_id":123}''::jsonb,ARRAY[123]::integer[],NULL::text,
     NULL::text[],NULL::text[],true,false,false,false)' INTO v_probe;
  IF v_probe IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'Numbered-schema nested helper probe failed'; END IF;
  EXECUTE 'SELECT EXISTS (SELECT 1 FROM "02_engineering_schema".v_dashboard_sprints LIMIT 1)'
    INTO v_probe;
  IF v_probe IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'Numbered-schema sprint reporting view failed'; END IF;

  -- External Postgres writer role, independent of Edge Function connection
  -- defaults, receives the new fully quoted numbered schema path.
  EXECUTE 'ALTER ROLE jira_sync SET search_path = ''"02_engineering_schema", public''';

  SELECT jobid,command INTO STRICT v_cron_id,v_cron_cmd
    FROM cron.job WHERE jobname='jira-dashboard-snapshot-watchdog'
    AND active AND schedule='*/5 * * * *';
  IF position('jira.refresh_metric_cohorts()' IN v_cron_cmd)=0
  THEN RAISE EXCEPTION 'Watchdog cron unexpectedly changed'; END IF;
  PERFORM cron.alter_job(job_id:=v_cron_id,command:=replace(v_cron_cmd,
    'jira.refresh_metric_cohorts()',
    '"02_engineering_schema".refresh_metric_cohorts()'));

  -- Verify source and destination object identities; no DML was executed.
  IF (SELECT oid FROM pg_namespace WHERE nspname='02_engineering_schema')
     IS DISTINCT FROM v_old
    OR (SELECT oid FROM pg_namespace WHERE nspname='02_engineering_schema_reserved_20261106')
     IS DISTINCT FROM v_dest
    OR to_regnamespace('jira') IS NOT NULL
  THEN RAISE EXCEPTION 'Engineering schema identity invalid'; END IF;
  IF (SELECT count(*) FROM pg_class WHERE relnamespace=v_old AND relkind='r')<>20
    OR (SELECT count(*) FROM pg_class WHERE relnamespace=v_old AND relkind='v')<>39
    OR (SELECT count(*) FROM pg_class WHERE relnamespace=v_old AND relkind='m')<>4
    OR (SELECT count(*) FROM pg_class WHERE relnamespace=v_old AND relkind='S')<>3
    OR (SELECT count(*) FROM pg_proc WHERE pronamespace=v_old)<>35
  THEN RAISE EXCEPTION 'Relation/function counts changed, rolling back'; END IF;

  FOR rec IN SELECT old_oid,rel_name,old_rows FROM engineering_cutover_counts
             ORDER BY rel_name LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_class c WHERE c.oid=rec.old_oid AND c.relnamespace=v_old)
    THEN RAISE EXCEPTION 'Table OID changed: %',rec.rel_name; END IF;
    EXECUTE format('SELECT count(*) FROM "02_engineering_schema".%I',rec.rel_name)
       INTO v_count;
    IF v_count<>rec.old_rows
    THEN RAISE EXCEPTION 'Table row count changed: %, % to %',
      rec.rel_name,rec.old_rows,v_count;
    END IF;
  END LOOP;

  IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE (n.oid=v_old OR (n.nspname='public' AND p.proname IN
      ('read_jira_delivery_dashboard_v1','read_jira_delivery_evidence_v1',
       'read_jira_delivery_evidence_v2','read_jira_delivery_issue_v1')))
    AND (position('jira.' IN p.prosrc)>0 OR EXISTS(
      SELECT 1 FROM unnest(p.proconfig) AS setting
      WHERE setting LIKE 'search_path=jira,%')))
  THEN RAISE EXCEPTION 'Stale Jira references remain in rewritten functions'; END IF;

  IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobid=v_cron_id
    AND command LIKE '%"02_engineering_schema".refresh_metric_cohorts()%')
  THEN RAISE EXCEPTION 'Cron refresh target did not change'; END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_db_role_setting s JOIN pg_roles r ON r.oid=s.setrole
    WHERE r.rolname='jira_sync'
    AND EXISTS(SELECT 1 FROM unnest(s.setconfig) item
      WHERE item LIKE '%02_engineering_schema%'))
  THEN RAISE EXCEPTION 'Writer role search path update missing'; END IF;

  -- Preserve public RPC permissions and original function identity.
  IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN
      ('read_jira_delivery_dashboard_v1','read_jira_delivery_evidence_v1',
       'read_jira_delivery_evidence_v2','read_jira_delivery_issue_v1')
    AND (has_function_privilege('anon',p.oid,'EXECUTE')
      OR has_function_privilege('authenticated',p.oid,'EXECUTE')
      OR NOT has_function_privilege('service_role',p.oid,'EXECUTE')))
  THEN RAISE EXCEPTION 'Public Jira RPC ACL regression'; END IF;
END;
$migrate$;
