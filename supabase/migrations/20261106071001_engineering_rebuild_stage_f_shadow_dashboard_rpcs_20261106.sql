-- Engineering rebuild Stage F: four PRIVATE SHADOW DASHBOARD RPCs.
-- Original public.read_jira_delivery_* functions remain unchanged, with the
-- live dashboard still reading Jira. Shadow RPCs are DB-only parity probes.
SET LOCAL lock_timeout = '8s';
SET LOCAL statement_timeout = '90s';
SET LOCAL check_function_bodies = off;

DO $shadow$
DECLARE
 rec record;
 ddl text;
 n integer:=0;
 newns oid;
BEGIN
 SELECT oid INTO STRICT newns FROM pg_namespace WHERE nspname='02_engineering_schema';
 IF (SELECT count(*) FROM pg_proc WHERE pronamespace=newns)<>35
 OR (SELECT count(*) FROM pg_class WHERE relnamespace=newns AND relkind='m' AND relispopulated)<>4
 THEN RAISE EXCEPTION 'Private functions or materializations not ready'; END IF;
 FOR rec IN
   SELECT p.oid,p.proname FROM pg_proc p
   JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public' AND p.proname IN
     ('read_jira_delivery_dashboard_v1',
      'read_jira_delivery_evidence_v1',
      'read_jira_delivery_evidence_v2',
      'read_jira_delivery_issue_v1')
   ORDER BY p.proname
 LOOP
   ddl:=pg_get_functiondef(rec.oid);
   IF position('CREATE OR REPLACE FUNCTION public.' IN ddl)<>1
   THEN RAISE EXCEPTION 'Unexpected public RPC definition: %',rec.proname; END IF;
   ddl:=replace(ddl,'CREATE OR REPLACE FUNCTION public.',
                    'CREATE OR REPLACE FUNCTION "02_engineering_schema".');
   ddl:=replace(ddl,'jira.','"02_engineering_schema".');
   ddl:=replace(ddl,'SET search_path TO ''jira'',',
                    'SET search_path TO "02_engineering_schema",');
   EXECUTE ddl;
   n:=n+1;
 END LOOP;
 IF n<>4 OR (SELECT count(*) FROM pg_proc WHERE pronamespace=newns)<>39
 THEN RAISE EXCEPTION 'Expected four shadow RPCs, found %',n; END IF;
 REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "02_engineering_schema"
   FROM PUBLIC,anon,authenticated,service_role,jira_sync,product_metrics_fetcher;
 IF EXISTS(SELECT 1 FROM pg_proc p WHERE p.pronamespace=newns
   AND (position('jira.' IN p.prosrc)>0
     OR has_function_privilege('anon',p.oid,'EXECUTE')
     OR has_function_privilege('authenticated',p.oid,'EXECUTE')
     OR has_function_privilege('service_role',p.oid,'EXECUTE')))
 THEN RAISE EXCEPTION 'Shadow RPC reference or permission mismatch'; END IF;
END;
$shadow$;
