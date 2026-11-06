SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='180s';
DO $switch$
DECLARE
  r record;
  v_ddl text;
  v_cmd text;
  v_n int:=0;
  v_latest bigint;
  v_published bigint;
  v_sprint bigint;
  v_issue text;
  v_result jsonb;
BEGIN
  IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='02_engineering_schema' AND c.relkind='r') <> 20
     OR (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='02_engineering_schema' AND c.relkind='v') <>39
     OR (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='02_engineering_schema' AND c.relkind='m') <>4
  THEN RAISE EXCEPTION 'Engineering target inventory drift'; END IF;
  IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='02_engineering_schema' AND c.relkind='r'
              AND NOT c.relrowsecurity)
  THEN RAISE EXCEPTION 'Shadow RLS missing'; END IF;
  IF NOT has_schema_privilege('jira_sync','02_engineering_schema','USAGE')
  THEN RAISE EXCEPTION 'Trusted Jira writer cannot access shadow schema'; END IF;
  SELECT max(id) INTO v_latest FROM "02_engineering_schema".sync_log;
  SELECT refreshed_sync_id INTO v_published
    FROM "02_engineering_schema".dashboard_snapshot_refresh_state WHERE singleton;
  IF v_latest IS NULL OR v_latest IS DISTINCT FROM v_published
      OR NOT EXISTS(SELECT 1 FROM "02_engineering_schema".sync_log
                    WHERE id=v_latest AND finished_at IS NOT NULL AND errors_count=0)
  THEN RAISE EXCEPTION 'Shadow fresh ingestion/snapshot not healthy'; END IF;
  IF EXISTS(SELECT issue_id FROM jira.issues EXCEPT SELECT issue_id FROM "02_engineering_schema".issues)
     OR EXISTS(SELECT issue_id,change_id,itemordinal FROM jira.issue_field_history
               EXCEPT SELECT issue_id,change_id,itemordinal FROM "02_engineering_schema".issue_field_history)
  THEN RAISE EXCEPTION 'Original Jira issue/history keys missing'; END IF;
  IF (SELECT count(*) FROM cron.job
      WHERE jobid IN(8,9,15) AND active AND username='postgres') <>3
  THEN RAISE EXCEPTION 'Jira cron job inventory drift'; END IF;
  SELECT id INTO v_sprint FROM "02_engineering_schema".v_dashboard_sprints
    ORDER BY (state='active') DESC,start_date DESC,id DESC LIMIT 1;
  SELECT issue_key INTO v_issue FROM "02_engineering_schema".issues
    WHERE issue_key LIKE 'SPEND-%' ORDER BY issue_id DESC LIMIT 1;
  IF v_sprint IS NULL OR v_issue IS NULL THEN RAISE EXCEPTION 'Missing Jira smoke test data'; END IF;

  FOR r IN SELECT p.oid,p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
           WHERE n.nspname='02_engineering_schema'
             AND p.proname IN ('read_jira_delivery_dashboard_v1','read_jira_delivery_evidence_v1',
                               'read_jira_delivery_evidence_v2','read_jira_delivery_issue_v1')
           ORDER BY p.proname LOOP
    v_ddl:=pg_get_functiondef(r.oid);
    IF position('CREATE OR REPLACE FUNCTION "02_engineering_schema".' IN v_ddl)<>1
    THEN RAISE EXCEPTION 'Unexpected shadow RPC definition: %',r.proname; END IF;
    EXECUTE replace(v_ddl,'CREATE OR REPLACE FUNCTION "02_engineering_schema".',
                           'CREATE OR REPLACE FUNCTION public.');
    v_n:=v_n+1;
  END LOOP;
  IF v_n<>4 THEN RAISE EXCEPTION 'Missing shadow RPC definitions'; END IF;

  FOR r IN SELECT jobid,command,schedule FROM cron.job WHERE jobid IN (8,9) ORDER BY jobid LOOP
    IF (r.jobid=8 AND r.schedule<>'30 2 * * *')
       OR (r.jobid=9 AND r.schedule<>'30 12 * * *')
       OR position(E'url := (\n          select decrypted_secret' IN r.command)=0
    THEN RAISE EXCEPTION 'Jira sync cron command drift: %',r.jobid; END IF;
    v_cmd:=replace(r.command,
      E'url := (\n          select decrypted_secret',
      E'url := (\n          select regexp_replace(decrypted_secret, ''/jira-sync$'', ''/jira-sync-engineering'')');
    PERFORM cron.alter_job(r.jobid,command:=v_cmd);
  END LOOP;
  SELECT command INTO v_cmd FROM cron.job WHERE jobid=15 AND schedule='*/5 * * * *';
  IF v_cmd IS NULL OR position('select jira.refresh_metric_cohorts();' IN v_cmd)=0
  THEN RAISE EXCEPTION 'Jira watchdog command drift'; END IF;
  PERFORM cron.alter_job(15,command:=replace(v_cmd,
    'select jira.refresh_metric_cohorts();',
    'select "02_engineering_schema".refresh_metric_cohorts();'));
  IF (SELECT count(*) FROM cron.job WHERE jobid IN (8,9) AND command LIKE '%jira-sync-engineering%')<>2
     OR (SELECT count(*) FROM cron.job WHERE jobid=15
         AND command LIKE '%"02_engineering_schema".refresh_metric_cohorts()%')<>1
  THEN RAISE EXCEPTION 'Cron writer/watchdog switch not verified'; END IF;
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public'
        AND p.proname IN ('read_jira_delivery_dashboard_v1','read_jira_delivery_evidence_v1',
                         'read_jira_delivery_evidence_v2','read_jira_delivery_issue_v1')
        AND has_function_privilege('service_role',p.oid,'EXECUTE')
        AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
        AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE'))<>4
  THEN RAISE EXCEPTION 'Public RPC permission changed'; END IF;

  EXECUTE 'SELECT public.read_jira_delivery_dashboard_v1()' INTO v_result;
  IF jsonb_typeof(v_result)<>'object' OR (v_result->>'snapshot_id')::bigint IS DISTINCT FROM v_published
  THEN RAISE EXCEPTION 'Default dashboard smoke failed'; END IF;
  EXECUTE 'SELECT public.read_jira_delivery_dashboard_v1($1)' INTO v_result USING v_sprint;
  IF jsonb_typeof(v_result)<>'object' THEN RAISE EXCEPTION 'Active sprint smoke failed'; END IF;
  EXECUTE 'SELECT public.read_jira_delivery_evidence_v1($1,$2)' INTO v_result USING 'open_bugs',v_sprint;
  IF jsonb_typeof(v_result)<>'object' THEN RAISE EXCEPTION 'Evidence v1 smoke failed'; END IF;
  EXECUTE 'SELECT public.read_jira_delivery_evidence_v2($1,$2)' INTO v_result USING 'qa_queue',v_sprint;
  IF jsonb_typeof(v_result)<>'object' THEN RAISE EXCEPTION 'Evidence v2 smoke failed'; END IF;
  EXECUTE 'SELECT public.read_jira_delivery_issue_v1($1,$2)' INTO v_result USING v_issue,v_published;
  IF jsonb_typeof(v_result)<>'object' THEN RAISE EXCEPTION 'Issue detail smoke failed'; END IF;
END $switch$;
