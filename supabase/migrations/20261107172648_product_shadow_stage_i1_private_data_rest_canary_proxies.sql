-- Product I1: restricted REST canary endpoints backed only by private Product readers.
-- Does not replace any existing production RPC or expose private tables.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='90s';
DO $guard$
BEGIN
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname IN(
    'read_product_shadow_overview_canary','read_product_shadow_retention_canary','read_product_shadow_companies_canary'))
 THEN RAISE EXCEPTION 'Product shadow REST canary already exists';END IF;
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='01_product_schema' AND p.proname IN(
   'read_overview_independent_core_kpis_v4','read_retention_dashboard_v5','read_companies_monthly_grid_v2'))<>3
 THEN RAISE EXCEPTION 'Missing private Product read functions';END IF;
END $guard$;

CREATE FUNCTION public.read_product_shadow_overview_canary(p_snapshot_id bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,pg_temp
AS $fn$
 SELECT "01_product_schema".read_overview_independent_core_kpis_v4(p_snapshot_id);
$fn$;

CREATE FUNCTION public.read_product_shadow_retention_canary(p_from date,p_to date)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,pg_temp
AS $fn$
 SELECT "01_product_schema".read_retention_dashboard_v5(p_from,p_to);
$fn$;

CREATE FUNCTION public.read_product_shadow_companies_canary(p_from date,p_to date)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,pg_temp
AS $fn$
 SELECT "01_product_schema".read_companies_monthly_grid_v2(
   p_from,p_to,NULL,NULL,NULL,NULL,NULL,1,20);
$fn$;

REVOKE ALL ON FUNCTION public.read_product_shadow_overview_canary(bigint)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.read_product_shadow_retention_canary(date,date)
 FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.read_product_shadow_companies_canary(date,date)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_product_shadow_overview_canary(bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_product_shadow_retention_canary(date,date) TO service_role;
GRANT EXECUTE ON FUNCTION public.read_product_shadow_companies_canary(date,date) TO service_role;

DO $verify$
BEGIN
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public' AND p.proname LIKE 'read_product_shadow_%_canary'
 AND p.prosecdef
 AND has_function_privilege('service_role',p.oid,'EXECUTE')
 AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
 AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE'))<>3
 THEN RAISE EXCEPTION 'Canary access or security audit failed';END IF;
END $verify$;
