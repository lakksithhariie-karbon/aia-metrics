-- Product J1: scoped, service-role-only public bridge RPCs for isolated shadow ingestion canary.
-- No legacy public function altered. No cron or Edge function changed.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='90s';
DO $guard$ BEGIN
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public' AND p.proname LIKE 'shadow_product_%') THEN
   RAISE EXCEPTION 'Product shadow bridge names already exist';END IF;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='01_product_schema' AND p.proname IN
   ('try_begin_incremental','upsert_mixpanel_events_detail','finish_incremental',
    'refresh_retention','prune_product_snapshots','prune_funnel_members','prune_overview_members'))<>7
 THEN RAISE EXCEPTION 'Product private target writer inventory unexpected';END IF;
END $guard$;
CREATE FUNCTION public.shadow_product_try_begin_incremental(p_lease interval DEFAULT '15 minutes') RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog,pg_temp AS $fn$ SELECT "01_product_schema".try_begin_incremental(p_lease); $fn$;
CREATE FUNCTION public.shadow_product_upsert_mixpanel_events_detail(p_rows jsonb) RETURNS TABLE(inserted integer,updated integer,identity_mismatches integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog,pg_temp AS $fn$ SELECT * FROM "01_product_schema".upsert_mixpanel_events_detail(p_rows); $fn$;
CREATE FUNCTION public.shadow_product_finish_incremental(p_ok boolean,p_day date,p_detail text) RETURNS void LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog,pg_temp AS $fn$ SELECT "01_product_schema".finish_incremental(p_ok,p_day,p_detail); $fn$;
CREATE FUNCTION public.shadow_product_refresh_retention(p_source text) RETURNS TABLE(n_activation integer,n_week integer,n_cells integer,n_client integer,n_profile integer,n_week_action integer) LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog,pg_temp AS $fn$ SELECT * FROM "01_product_schema".refresh_retention(p_source); $fn$;
CREATE FUNCTION public.shadow_product_prune_product_snapshots(p_keep_per_scope integer DEFAULT 5) RETURNS integer LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog,pg_temp AS $fn$ SELECT "01_product_schema".prune_product_snapshots(p_keep_per_scope); $fn$;
CREATE FUNCTION public.shadow_product_prune_funnel_members(p_keep_per_scope integer DEFAULT 5) RETURNS integer LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog,pg_temp AS $fn$ SELECT "01_product_schema".prune_funnel_members(p_keep_per_scope); $fn$;
CREATE FUNCTION public.shadow_product_prune_overview_members(p_keep_per_scope integer DEFAULT 5) RETURNS integer LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path TO pg_catalog,pg_temp AS $fn$ SELECT "01_product_schema".prune_overview_members(p_keep_per_scope); $fn$;
CREATE FUNCTION public.shadow_product_watermark() RETURNS TABLE(last_success_date date) LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO pg_catalog,pg_temp AS $fn$ SELECT last_success_date FROM "01_product_schema".export_watermarks WHERE job_name='incremental' LIMIT 1; $fn$;
REVOKE ALL ON FUNCTION public.shadow_product_try_begin_incremental(interval) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shadow_product_try_begin_incremental(interval) TO service_role;
REVOKE ALL ON FUNCTION public.shadow_product_upsert_mixpanel_events_detail(jsonb) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shadow_product_upsert_mixpanel_events_detail(jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.shadow_product_finish_incremental(boolean,date,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shadow_product_finish_incremental(boolean,date,text) TO service_role;
REVOKE ALL ON FUNCTION public.shadow_product_refresh_retention(text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shadow_product_refresh_retention(text) TO service_role;
REVOKE ALL ON FUNCTION public.shadow_product_prune_product_snapshots(integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shadow_product_prune_product_snapshots(integer) TO service_role;
REVOKE ALL ON FUNCTION public.shadow_product_prune_funnel_members(integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shadow_product_prune_funnel_members(integer) TO service_role;
REVOKE ALL ON FUNCTION public.shadow_product_prune_overview_members(integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shadow_product_prune_overview_members(integer) TO service_role;
REVOKE ALL ON FUNCTION public.shadow_product_watermark() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.shadow_product_watermark() TO service_role;
DO $verify$ BEGIN
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname LIKE 'shadow_product_%'
 AND p.prosecdef AND has_function_privilege('service_role',p.oid,'EXECUTE')
 AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
 AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE'))<>8
 THEN RAISE EXCEPTION 'Shadow writer bridge ACL verification failed';END IF;
END $verify$;
