-- Product G3: private snapshot publication, membership and cleanup canaries.
-- Original publication functions and production cron remain unchanged.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='240s';
SET LOCAL check_function_bodies=off;
DO $shadow$
DECLARE r record; t record; f record; d text; n integer:=0;
BEGIN
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
      WHERE ns.nspname='01_product_schema')<>152 THEN RAISE EXCEPTION 'G2 prerequisite not met';END IF;
 FOR r IN SELECT p.oid,p.proname,p.prosecdef FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
    WHERE ns.nspname='public' AND p.proname IN
      ('activate_product_snapshot','assert_product_snapshot_publishable','begin_product_refresh',
       'claim_retention_period_build','complete_product_refresh','fail_product_refresh',
       'prune_product_refresh_runs','prune_product_snapshots','prune_funnel_members',
       'prune_overview_members','publish_product_publication','release_retention_period_build',
       'retention_period_is_sealed','retention_summary_is_sealed','stage_funnel_members',
       'stage_overview_members','stage_product_snapshot','stage_product_snapshot_v2',
       'stage_retention_period_drills','stage_retention_summary_members')
    ORDER BY p.proname
 LOOP
   IF NOT r.prosecdef THEN RAISE EXCEPTION 'Unexpected writer privilege for %',r.proname;END IF;
   d:=pg_get_functiondef(r.oid);
   IF d NOT LIKE 'CREATE OR REPLACE FUNCTION public.%'
    OR d LIKE '%feature_olap.%' OR d LIKE '%product_source.%'
   THEN RAISE EXCEPTION 'Unexpected Product publication source %',r.proname;END IF;
   d:=replace(d,'CREATE OR REPLACE FUNCTION public.',
                'CREATE OR REPLACE FUNCTION "01_product_schema".');
   FOR t IN SELECT ns.nspname sc,c.relname nm FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
     WHERE ns.nspname IN('public','metrics_private') AND c.relkind IN('r','v')
     ORDER BY length(c.relname) DESC,c.relname
   LOOP
      d:=replace(d,t.sc||'.'||t.nm,'"01_product_schema".'||quote_ident(t.nm));
   END LOOP;
   FOR f IN SELECT p.proname nm,ns.nspname sc FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
     WHERE ns.nspname='public' AND
       (EXISTS(SELECT 1 FROM pg_proc dest JOIN pg_namespace dns ON dns.oid=dest.pronamespace
           WHERE dns.nspname='01_product_schema' AND dest.proname=p.proname)
        OR p.proname IN
      ('activate_product_snapshot','assert_product_snapshot_publishable','begin_product_refresh',
       'claim_retention_period_build','complete_product_refresh','fail_product_refresh',
       'prune_product_refresh_runs','prune_product_snapshots','prune_funnel_members',
       'prune_overview_members','publish_product_publication','release_retention_period_build',
       'retention_period_is_sealed','retention_summary_is_sealed','stage_funnel_members',
       'stage_overview_members','stage_product_snapshot','stage_product_snapshot_v2',
       'stage_retention_period_drills','stage_retention_summary_members'))
    ORDER BY length(p.proname) DESC
   LOOP
      d:=replace(d,f.sc||'.'||f.nm||'(','"01_product_schema".'||quote_ident(f.nm)||'(');
   END LOOP;
   d:=replace(d,'SET search_path TO ''public''',
           'SET search_path TO "01_product_schema", pg_catalog, pg_temp');
   d:=replace(d,'pg_advisory_xact_lock(p_snapshot_id)',
           'pg_advisory_xact_lock(7242852, p_snapshot_id::integer)');
   d:=replace(d,'pg_advisory_xact_lock(hashtext(',
           'pg_advisory_xact_lock(hashtext(''01_product_schema|'' || ');
   IF d LIKE '%public.%' OR d LIKE '%metrics_private.%' THEN
        RAISE EXCEPTION 'Unrebound source reference in %',r.proname;END IF;
   EXECUTE d;n:=n+1;
 END LOOP;
 IF n<>20 OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
     WHERE ns.nspname='01_product_schema')<>172 THEN
    RAISE EXCEPTION 'Unexpected Product publication writer count';END IF;
 EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "01_product_schema" FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher';
END $shadow$;
