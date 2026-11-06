-- Engineering rebuild stage C: create the 39 reporting views and 4
-- materialized-view definitions in catalog-derived dependency order.
-- Read only from original Jira definitions, no original data/DDL modified.
-- Materialized views are intentionally unpopulated until stage E.
SET LOCAL lock_timeout = '8s';
SET LOCAL statement_timeout = '120s';

DO $views$
DECLARE
 oldns oid;
 newns oid;
 rec record;
 idx record;
 view_sql text;
 index_sql text;
 n_v integer:=0;
 n_m integer:=0;
 n_i integer:=0;
 old_columns text;
 new_columns text;
BEGIN
 SELECT oid INTO STRICT oldns FROM pg_namespace WHERE nspname='jira';
 SELECT oid INTO STRICT newns FROM pg_namespace WHERE nspname='02_engineering_schema';
 IF (SELECT count(*) FROM pg_class WHERE relnamespace=newns AND relkind='r')<>20
    OR (SELECT count(*) FROM pg_proc WHERE pronamespace=newns)<>33
    OR EXISTS(SELECT 1 FROM pg_class WHERE relnamespace=newns AND relkind IN('v','m'))
 THEN RAISE EXCEPTION 'Engineering view staging prerequisite missing or destination nonempty'; END IF;
 IF (SELECT count(*) FROM pg_class WHERE relnamespace=oldns AND relkind='v')<>39
    OR (SELECT count(*) FROM pg_class WHERE relnamespace=oldns AND relkind='m')<>4
 THEN RAISE EXCEPTION 'Legacy Jira view inventory changed'; END IF;

 -- PostgreSQL's own dependency graph is used rather than a manually
 -- maintained view ordering. This includes dependencies via matviews.
 FOR rec IN
   WITH RECURSIVE targets AS (
      SELECT oid,relname,relkind FROM pg_class
      WHERE relnamespace=oldns AND relkind IN('v','m')
   ), edges AS (
      SELECT DISTINCT t.oid dependent, d.refobjid upstream
      FROM targets t
      JOIN pg_rewrite rw ON rw.ev_class=t.oid
      JOIN pg_depend d ON d.objid=rw.oid
         AND d.refclassid='pg_class'::regclass
      JOIN pg_class r ON r.oid=d.refobjid
      WHERE r.relnamespace=oldns AND d.refobjid<>t.oid
   ), paths AS (
      SELECT t.oid root,t.oid node,0 depth,ARRAY[t.oid]::oid[] visited FROM targets t
      UNION ALL
      SELECT p.root,e.upstream,p.depth+1,p.visited||e.upstream
      FROM paths p JOIN edges e ON e.dependent=p.node
      WHERE NOT e.upstream=ANY(p.visited) AND p.depth<30
   )
   SELECT t.oid,t.relname,t.relkind,max(p.depth) AS depth
   FROM targets t JOIN paths p ON p.root=t.oid
   GROUP BY t.oid,t.relname,t.relkind
   ORDER BY depth,t.relname
 LOOP
   view_sql:=pg_get_viewdef(rec.oid,true);
   IF position('jira.' IN view_sql)=0
   THEN RAISE EXCEPTION 'Unexpected view SQL missing original schema: %',rec.relname; END IF;
   view_sql:=replace(view_sql,'jira.','"02_engineering_schema".');
   -- pg_get_viewdef sometimes contains a trailing SELECT terminator.
   view_sql:=regexp_replace(view_sql,';[[:space:]]*$','');
   IF rec.relkind='v' THEN
     EXECUTE format('CREATE VIEW "02_engineering_schema".%I AS %s',
                     rec.relname,view_sql);
     n_v:=n_v+1;
   ELSE
     EXECUTE format('CREATE MATERIALIZED VIEW "02_engineering_schema".%I AS %s WITH NO DATA',
                     rec.relname,view_sql);
     n_m:=n_m+1;
   END IF;

   EXECUTE format('REVOKE ALL ON TABLE "02_engineering_schema".%I FROM PUBLIC,anon,authenticated,service_role,jira_sync,product_metrics_fetcher',
                  rec.relname);
   EXECUTE format('GRANT SELECT ON TABLE "02_engineering_schema".%I TO product_metrics_fetcher',
                  rec.relname);

   SELECT string_agg(attname||':'||format_type(atttypid,atttypmod),'|' ORDER BY attnum)
     INTO old_columns FROM pg_attribute WHERE attrelid=rec.oid AND attnum>0 AND NOT attisdropped;
   SELECT string_agg(a.attname||':'||format_type(a.atttypid,a.atttypmod),'|' ORDER BY a.attnum)
     INTO new_columns FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
     WHERE c.relnamespace=newns AND c.relname=rec.relname
       AND a.attnum>0 AND NOT a.attisdropped;
   IF old_columns IS DISTINCT FROM new_columns
   THEN RAISE EXCEPTION 'Reporting projection mismatch for %',rec.relname; END IF;
 END LOOP;
 IF n_v<>39 OR n_m<>4 THEN
    RAISE EXCEPTION 'Unexpected view materialization counts: %, %',n_v,n_m; END IF;

 -- Rebuild source materialization indexes, including unique indexes needed
 -- for future CONCURRENTLY refresh. Definitions are rewritten only in copy.
 FOR idx IN SELECT i.indexrelid, pg_get_indexdef(i.indexrelid) AS definition
   FROM pg_index i JOIN pg_class mv ON mv.oid=i.indrelid
   WHERE mv.relnamespace=oldns AND mv.relkind='m'
   ORDER BY mv.relname,i.indexrelid
 LOOP
   index_sql:=replace(idx.definition,' ON jira.',' ON "02_engineering_schema".');
   IF index_sql=idx.definition THEN
     RAISE EXCEPTION 'Matview index does not target Jira schema: %',idx.definition; END IF;
   EXECUTE index_sql;
   n_i:=n_i+1;
 END LOOP;
 IF n_i<>5 THEN RAISE EXCEPTION 'Unexpected materialized index count: %',n_i; END IF;
 IF (SELECT count(*) FROM pg_class WHERE relnamespace=newns AND relkind='v')<>39
   OR (SELECT count(*) FROM pg_class WHERE relnamespace=newns AND relkind='m')<>4
 THEN RAISE EXCEPTION 'Incomplete new reporting view inventory'; END IF;
END;
$views$;
