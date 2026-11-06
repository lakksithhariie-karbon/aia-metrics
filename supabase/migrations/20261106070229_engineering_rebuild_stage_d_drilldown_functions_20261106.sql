-- Engineering rebuild stage D: finalize two view-rowtype drilldown routines.
-- The target v_sprint_drilldown now exists after Stage C.
-- No public RPC/cron/source change; no access to teammate-owned objects.
SET LOCAL lock_timeout = '8s';
SET LOCAL statement_timeout = '60s';

DO $drilldown$
DECLARE
 rec record;
 ddl text;
 n integer:=0;
 oldns oid;
 newns oid;
BEGIN
 SELECT oid INTO STRICT oldns FROM pg_namespace WHERE nspname='jira';
 SELECT oid INTO STRICT newns FROM pg_namespace WHERE nspname='02_engineering_schema';
 IF to_regclass('"02_engineering_schema".v_sprint_drilldown') IS NULL
   OR (SELECT count(*) FROM pg_proc WHERE pronamespace=newns)<>33
   OR (SELECT count(*) FROM pg_class WHERE relnamespace=newns AND relkind='v')<>39
 THEN RAISE EXCEPTION 'View and 33 cloned functions required first'; END IF;

 FOR rec IN SELECT oid,proname FROM pg_proc
   WHERE pronamespace=oldns
     AND proname IN ('get_filtered_drilldown','get_filtered_drilldown_submodule')
   ORDER BY proname
 LOOP
   ddl:=pg_get_functiondef(rec.oid);
   IF position('RETURNS SETOF jira.v_sprint_drilldown' IN ddl)=0
   THEN RAISE EXCEPTION 'Unexpected drilldown return type: %',rec.proname; END IF;
   ddl:=replace(ddl,'jira.','"02_engineering_schema".');
   -- In a function definition, a bare double-quoted schema identifier is
   -- required; a SQL single-quoted string creates a triple-quoted bad path.
   ddl:=replace(ddl,'SET search_path TO ''jira'',',
                    'SET search_path TO "02_engineering_schema",');
   EXECUTE ddl;
   n:=n+1;
 END LOOP;
 IF n<>2 OR (SELECT count(*) FROM pg_proc WHERE pronamespace=newns)<>35
 THEN RAISE EXCEPTION 'Two extra functions not installed'; END IF;

 REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "02_engineering_schema"
 FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher,jira_sync;
 IF EXISTS(SELECT 1 FROM pg_proc p WHERE p.pronamespace=newns
   AND (position('jira.' IN p.prosrc)>0
     OR has_function_privilege('anon',p.oid,'EXECUTE')
     OR has_function_privilege('authenticated',p.oid,'EXECUTE')
     OR has_function_privilege('service_role',p.oid,'EXECUTE')))
 THEN RAISE EXCEPTION 'Private function security or reference mismatch'; END IF;
END;
$drilldown$;
