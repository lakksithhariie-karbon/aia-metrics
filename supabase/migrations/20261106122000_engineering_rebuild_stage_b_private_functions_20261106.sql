-- Engineering rebuild stage B: independent private SQL functions.
-- Never modify existing jira, public RPCs, teammate-owned schemas or jobs.
-- Copy the first 33 audited functions (two return a view rowtype, recreated
-- after Stage C creates the view). Replace only the owning
-- schema and qualified references. Views may not exist until stage C; therefore
-- defer function body validation while compiling and test in a NEW transaction.
SET LOCAL lock_timeout = '8s';
SET LOCAL statement_timeout = '120s';
SET LOCAL check_function_bodies = off;

DO $rebuild$
DECLARE
 v_old oid;
 v_target oid;
 rec record;
 ddl text;
 n integer:=0;
BEGIN
 SELECT oid INTO STRICT v_old FROM pg_namespace WHERE nspname='jira';
 SELECT oid INTO STRICT v_target FROM pg_namespace WHERE nspname='02_engineering_schema';
 IF EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace=v_target)
 THEN RAISE EXCEPTION 'New Engineering functions already exist; refusing overwrite'; END IF;
 IF (SELECT count(*) FROM pg_proc WHERE pronamespace=v_old)<>35
 THEN RAISE EXCEPTION 'Jira function inventory changed'; END IF;
 IF (SELECT count(*) FROM pg_class WHERE relnamespace=v_target AND relkind='r')<>20
 THEN RAISE EXCEPTION 'Run verified physical-table stage A first'; END IF;
 FOR rec IN SELECT p.oid,p.proname FROM pg_proc p
            WHERE p.pronamespace=v_old
              AND p.proname NOT IN ('get_filtered_drilldown','get_filtered_drilldown_submodule')
            ORDER BY p.proname,p.oid
 LOOP
   ddl:=pg_get_functiondef(rec.oid);
   IF position('CREATE OR REPLACE FUNCTION jira.' IN ddl)<>1
   THEN RAISE EXCEPTION 'Unexpected function header for %',rec.proname; END IF;
   ddl:=replace(ddl,'jira.','"02_engineering_schema".');
   ddl:=replace(ddl,
     'SET search_path TO ''jira'',',
     'SET search_path TO ''"02_engineering_schema"'',');
   -- Any unresolved helper/view references are validated after stages B/C.
   EXECUTE ddl;
   n:=n+1;
 END LOOP;
 IF n<>33 OR (SELECT count(*) FROM pg_proc WHERE pronamespace=v_target)<>33
 THEN RAISE EXCEPTION 'Engineering function cloning incomplete'; END IF;

 -- The routines remain inaccessible via public/anon/authenticated/service_role.
 -- Do not grant EXECUTE to reader or writer roles until cutover is validated.
 REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "02_engineering_schema"
 FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher,jira_sync;

 IF EXISTS (
  SELECT 1 FROM pg_proc p WHERE p.pronamespace=v_target
    AND (has_function_privilege('anon',p.oid,'EXECUTE')
      OR has_function_privilege('authenticated',p.oid,'EXECUTE')
      OR has_function_privilege('service_role',p.oid,'EXECUTE'))
 ) THEN RAISE EXCEPTION 'New Engineering SQL routine privilege leak'; END IF;
 IF EXISTS (
   SELECT 1 FROM pg_proc p WHERE p.pronamespace=v_target
     AND (position('jira.' IN p.prosrc)>0
       OR EXISTS(SELECT 1 FROM unnest(p.proconfig) setting
                 WHERE setting LIKE 'search_path=jira,%'))
 ) THEN RAISE EXCEPTION 'Old schema references remain in cloned routines'; END IF;
END;
$rebuild$;