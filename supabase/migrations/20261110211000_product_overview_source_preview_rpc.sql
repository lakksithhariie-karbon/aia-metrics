-- Temporary verified source path for the not-yet-published Overview builder.
-- Runs the five replay-tested private Product calculators on one completed
-- private ingestion generation. No snapshot stage/activation or reader switch.
-- Service-role only; never return identities, raw events or credentials.
CREATE OR REPLACE FUNCTION public.shadow_product_overview_source_preview_v1()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO pg_catalog,pg_temp
SET statement_timeout TO '90s'
AS $function$
DECLARE v_asof timestamptz := now(); v_wm timestamptz;
 v_status text; v_shadow_count bigint; v_legacy_count bigint;
 v_activity jsonb; v_charts jsonb; v_workflow jsonb;
 v_friction jsonb; v_adoption jsonb;
BEGIN
 SELECT status,last_success_at INTO v_status,v_wm
 FROM "01_product_schema".export_watermarks
 WHERE job_name='incremental';
 IF v_status IS DISTINCT FROM 'ok' OR v_wm IS NULL
  OR v_wm<now()-interval '24 hours' OR v_wm>now()
 THEN RAISE EXCEPTION 'overview_preview_source_not_fresh'; END IF;
 SELECT count(*) INTO v_shadow_count FROM "01_product_schema".events;
 SELECT count(*) INTO v_legacy_count FROM public.events;
 IF v_shadow_count<>v_legacy_count OR v_shadow_count<1
 THEN RAISE EXCEPTION 'overview_preview_source_parity_failed'; END IF;
 v_activity:="01_product_schema".build_overview_activity_source_v1(v_asof,v_wm);
 v_charts:="01_product_schema".build_overview_active_charts_source_v1(v_asof,v_wm);
 v_workflow:="01_product_schema".build_overview_workflow_source_v1(v_asof,v_wm);
 v_friction:="01_product_schema".build_overview_friction_source_v1(v_asof,v_wm);
 v_adoption:="01_product_schema".build_overview_adoption_source_v1(v_asof,v_wm);
 IF v_activity IS NULL OR v_charts IS NULL OR v_workflow IS NULL
    OR v_friction IS NULL OR v_adoption IS NULL OR
    v_activity->>'source_watermark_at' IS DISTINCT FROM v_charts->>'source_watermark_at' OR
    v_activity->>'source_watermark_at' IS DISTINCT FROM v_workflow->>'source_watermark_at' OR
    v_activity->>'source_watermark_at' IS DISTINCT FROM v_friction->>'source_watermark_at' OR
    v_activity->>'source_watermark_at' IS DISTINCT FROM v_adoption->>'source_watermark_at'
 THEN RAISE EXCEPTION 'overview_preview_mixed_or_missing_generation'; END IF;
 RETURN jsonb_build_object(
   'contract','shadow_overview_source_preview_v1',
   'source_schema','01_product_schema',
   'as_of',v_asof,'source_watermark_at',v_wm,
   'event_count',v_shadow_count,'snapshot_published',false,
   'activity',v_activity,'charts',v_charts,
   'workflow',v_workflow,'friction',v_friction,'adoption',v_adoption
 );
END;
$function$;
REVOKE ALL ON FUNCTION public.shadow_product_overview_source_preview_v1()
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.shadow_product_overview_source_preview_v1()
 TO service_role;
