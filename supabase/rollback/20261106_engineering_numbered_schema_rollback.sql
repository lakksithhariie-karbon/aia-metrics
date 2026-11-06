-- EMERGENCY ROLLBACK ONLY: revert object-preserving Engineering schema rename.
-- Do NOT use during normal deployment; assess production status first.
-- All 20 original tables, 39 views, four materializations, 35 routines,
-- 3 sequences and 4 public RPCs retain OIDs and rows. No data copying/deleting.
-- Edge Function dual search path remains valid both before/after rollback.
-- Backup of exact original 39 function definitions:
-- supabase/rollback/20261106_original_jira_function_definitions.sql
-- NEVER touch feature_olap or product_source.
SET LOCAL lock_timeout = '8s';
SET LOCAL statement_timeout = '180s';

DO $rollback$
DECLARE
  v_source oid;
  v_reserved oid;
  v_cron_id bigint;
  v_cmd text;
  v_ddl text;
  v_initial_search_path text;
  v_original_function_check text;
  v_probe boolean;
  v_rows bigint;
  v_count integer := 0;
  v_tables text;
  rec record;
BEGIN
  SELECT oid INTO STRICT v_source FROM pg_namespace WHERE nspname='02_engineering_schema';
  SELECT oid INTO STRICT v_reserved FROM pg_namespace WHERE nspname='02_engineering_schema_reserved_20261106';
  IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='jira')
  THEN RAISE EXCEPTION 'Original Jira namespace already exists; abort rollback'; END IF;
  IF EXISTS (SELECT 1 FROM pg_class WHERE relnamespace=v_reserved)
    OR EXISTS (SELECT 1 FROM pg_proc WHERE pronamespace=v_reserved)
    OR EXISTS (SELECT 1 FROM pg_type WHERE typnamespace=v_reserved)
  THEN RAISE EXCEPTION 'Reserved namespace backup not empty'; END IF;
  IF (SELECT count(*) FROM pg_class WHERE relnamespace=v_source AND relkind='r')<>20
    OR (SELECT count(*) FROM pg_class WHERE relnamespace=v_source AND relkind='v')<>39
    OR (SELECT count(*) FROM pg_class WHERE relnamespace=v_source AND relkind='m')<>4
    OR (SELECT count(*) FROM pg_proc WHERE pronamespace=v_source)<>35
  THEN RAISE EXCEPTION 'Engineering inventory changed; rollback must be adapted'; END IF;
  SELECT string_agg(format('"02_engineering_schema".%I',c.relname),',' ORDER BY c.relname)
  INTO v_tables FROM pg_class c
  WHERE c.relnamespace=v_source AND c.relkind='r';
  EXECUTE 'LOCK TABLE '||v_tables||' IN SHARE MODE';

  CREATE TEMP TABLE engineering_rollback_counts
   (old_oid oid PRIMARY KEY,rel_name text,old_rows bigint) ON COMMIT DROP;
  FOR rec IN SELECT oid,relname FROM pg_class WHERE relnamespace=v_source
    AND relkind='r' ORDER BY relname LOOP
    EXECUTE format('SELECT count(*) FROM "02_engineering_schema".%I',rec.relname)
    INTO v_rows;
    INSERT INTO engineering_rollback_counts VALUES(rec.oid,rec.relname,v_rows);
  END LOOP;

  EXECUTE 'ALTER SCHEMA "02_engineering_schema" RENAME TO jira';
  EXECUTE 'ALTER SCHEMA "02_engineering_schema_reserved_20261106" RENAME TO "02_engineering_schema"';
  v_initial_search_path:=current_setting('search_path');
  PERFORM set_config('search_path','jira,public,pg_catalog',true);
  v_original_function_check:=current_setting('check_function_bodies');
  PERFORM set_config('check_function_bodies','off',true);

  FOR rec IN
    SELECT p.oid,p.proname,n.nspname
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.oid=v_source OR (n.nspname='public' AND p.proname IN
      ('read_jira_delivery_dashboard_v1','read_jira_delivery_evidence_v1',
       'read_jira_delivery_evidence_v2','read_jira_delivery_issue_v1'))
    ORDER BY n.nspname,p.proname
  LOOP
    SELECT pg_get_functiondef(rec.oid) INTO v_ddl;
    v_ddl:=replace(v_ddl,'"02_engineering_schema".','jira.');
    v_ddl:=replace(v_ddl,'SET search_path TO ''"02_engineering_schema"'',',
                   'SET search_path TO ''jira'',');
    EXECUTE v_ddl;
    v_count:=v_count+1;
  END LOOP;
  PERFORM set_config('check_function_bodies',v_original_function_check,true);
  PERFORM set_config('search_path',v_initial_search_path,true);
  EXECUTE $SELECT jira._filter_cohort_row_matches(
    '{"sprint_id":123}'::jsonb,ARRAY[123]::integer[],NULL::text,
    NULL::text[],NULL::text[],true,false,false,false)$ INTO v_probe;
  IF v_probe IS DISTINCT FROM true
  THEN RAISE EXCEPTION 'Restored Jira helper probe failed'; END IF;
  IF v_count<>39 THEN RAISE EXCEPTION 'Expected 39 function definitions, got %',v_count; END IF;

  EXECUTE 'ALTER ROLE jira_sync SET search_path = ''jira, public''';

  SELECT jobid,command INTO STRICT v_cron_id,v_cmd
    FROM cron.job WHERE jobname='jira-dashboard-snapshot-watchdog'
    AND active AND schedule='*/5 * * * *';
  IF position('"02_engineering_schema".refresh_metric_cohorts()' IN v_cmd)=0
  THEN RAISE EXCEPTION 'Cron command no longer as expected'; END IF;
  PERFORM cron.alter_job(job_id:=v_cron_id,
    command:=replace(v_cmd,'"02_engineering_schema".refresh_metric_cohorts()',
                           'jira.refresh_metric_cohorts()'));

  IF (SELECT oid FROM pg_namespace WHERE nspname='jira') IS DISTINCT FROM v_source
    OR (SELECT oid FROM pg_namespace WHERE nspname='02_engineering_schema') IS DISTINCT FROM v_reserved
  THEN RAISE EXCEPTION 'Schema OID mismatch after rollback'; END IF;

  FOR rec IN SELECT old_oid,rel_name,old_rows FROM engineering_rollback_counts
    ORDER BY rel_name LOOP
    IF NOT EXISTS(SELECT 1 FROM pg_class WHERE oid=rec.old_oid AND relnamespace=v_source)
    THEN RAISE EXCEPTION 'Table identity changed for %',rec.rel_name; END IF;
    EXECUTE format('SELECT count(*) FROM jira.%I',rec.rel_name) INTO v_rows;
    IF v_rows<>rec.old_rows
    THEN RAISE EXCEPTION 'Unexpected row count change for %',rec.rel_name; END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE (n.oid=v_source OR (n.nspname='public' AND p.proname IN
       ('read_jira_delivery_dashboard_v1','read_jira_delivery_evidence_v1',
        'read_jira_delivery_evidence_v2','read_jira_delivery_issue_v1')))
    AND (p.prosrc LIKE '%"02_engineering_schema".%'
      OR EXISTS(SELECT 1 FROM unnest(p.proconfig) setting
                WHERE setting LIKE '%02_engineering_schema%')))
  THEN RAISE EXCEPTION 'Stale numbered-schema references after rollback'; END IF;
  IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobid=v_cron_id
    AND command LIKE '%jira.refresh_metric_cohorts()%')
  THEN RAISE EXCEPTION 'Cron rollback invalid'; END IF;
END;
$rollback$;
