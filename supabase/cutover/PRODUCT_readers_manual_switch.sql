-- MANUAL PRODUCT READER CUTOVER, NEVER RUN UNTIL SHADOW WRITER END-TO-END VERIFIED.
-- Not in the migrations folder: intentional, no automatic execution on PR merge.
-- Source: exact introspection of 105 STABLE SECURITY DEFINER public Product readers.
-- Execute in one session with explicit approved/writer_ready GUCs, after automated
-- parity suite passes and production ingestion is canonical in 01_product_schema.
-- Recreates public RPC bodies to point to private functions while preserving
-- names, parameter defaults, return types, volatility and statement timeouts.
-- Existing function ownership and GRANTs persist under CREATE OR REPLACE.
-- Restore original definitions using supabase/rollback/20261107_product_readers_part_*.sql.
-- Keep feature_olap/product_source and Product Analytics Features/OLAP untouched.

BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='300s';
DO $guard$
DECLARE num_readers integer;
BEGIN
  IF current_setting('aia_product_cutover.approved',true) IS DISTINCT FROM 'yes'
     OR current_setting('aia_product_cutover.writer_ready',true) IS DISTINCT FROM 'yes'
  THEN RAISE EXCEPTION 'Product cutover requires explicit operator preflight and verified canonical shadow writer';END IF;
  SELECT count(*) INTO num_readers FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='01_product_schema' AND p.proname LIKE 'read_%';
  IF num_readers<>106 THEN RAISE EXCEPTION 'Expected 105 migrated readers plus one private cache reader, got %',num_readers;END IF;
  IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
       WHERE n.nspname='01_product_schema' AND c.relkind='r' AND c.relrowsecurity)<>58
  THEN RAISE EXCEPTION 'Shadow RLS inventory mismatch';END IF;
  IF (SELECT count(*) FROM public.events)<>(SELECT count(*) FROM "01_product_schema".events)
  THEN RAISE EXCEPTION 'Event row-count parity failed before reader switch';END IF;
  IF (SELECT max(ingested_at) FROM public.events) IS DISTINCT FROM
     (SELECT max(ingested_at) FROM "01_product_schema".events)
  THEN RAISE EXCEPTION 'Event freshness parity failed before reader switch';END IF;
  -- Canonical readership must never switch onto a stale/unpublished Product
  -- generation. This page manifest must list all five CURRENT sealed kinds
  -- at the exact completed private-ingestion generation. Unlike a simple
  -- row-count check, it rejects mixed or missing snapshots and memberships.
  IF NOT EXISTS (
    SELECT 1
    FROM "01_product_schema".product_publication_current pc
    JOIN "01_product_schema".product_publication pub
      ON pub.publication_id=pc.publication_id
    JOIN "01_product_schema".product_publication_member m
      ON m.publication_id=pc.publication_id
    JOIN "01_product_schema".product_snapshot_current c
      ON c.kind=m.kind AND c.scope_key=m.scope_key
         AND c.snapshot_id=m.snapshot_id
    JOIN "01_product_schema".product_snapshot s
      ON s.id=m.snapshot_id
    JOIN "01_product_schema".export_watermarks w
      ON w.job_name='incremental' AND w.status='ok'
    WHERE pc.page='overview' AND pub.page='overview'
      AND pub.source_watermark_at=w.last_success_at
      AND pub.n_events=(SELECT count(*) FROM "01_product_schema".events)
      AND w.last_success_at>=now()-interval '24 hours'
    GROUP BY pc.publication_id,pub.source_watermark_at
    HAVING count(*)=5 AND count(DISTINCT m.kind)=5
      AND bool_and(
        m.scope_key='' AND
        m.kind=ANY(ARRAY['overview','overview-funnel',
          'overview-feature-usage','overview-module-mix','overview-friction'])
        AND s.source_status='ok'
        AND s.source_watermark_at=pub.source_watermark_at
        AND s.n_events=pub.n_events
        AND CASE WHEN m.kind='overview-funnel'
          THEN EXISTS(SELECT 1 FROM "01_product_schema".product_funnel_seal z
             WHERE z.snapshot_id=m.snapshot_id)
          ELSE EXISTS(SELECT 1 FROM "01_product_schema".product_overview_seal z
             WHERE z.snapshot_id=m.snapshot_id)
        END
      )
  ) THEN
    RAISE EXCEPTION 'Product cutover blocked: canonical Overview page manifest is stale, missing, unsealed or mixed-generation';
  END IF;

END $guard$;

CREATE OR REPLACE FUNCTION public."read_companies_breakdown"(p_company_id text, p_module text, p_user_key text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
RETURNS TABLE(event text, subtype text, status text, events bigint, items bigint, instrumented bigint, latest_at timestamp with time zone)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_companies_breakdown"("p_company_id","p_module","p_user_key","p_from","p_to");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_companies_context"()
RETURNS TABLE(clients jsonb, directory jsonb, data_start date, data_end date, watermark timestamp with time zone, integrations jsonb)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_companies_context"();
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_companies_identity_fast"(p_company_id text, p_user_key text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '2s'
AS $product_proxy$
  SELECT "01_product_schema"."read_companies_identity_fast"("p_company_id","p_user_key");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_companies_lifecycle_breakdown"(p_company_id text, p_module text, p_user_key text DEFAULT NULL::text, p_usage_week smallint DEFAULT 1)
RETURNS TABLE(event text, subtype text, status text, events bigint, items bigint, instrumented bigint, latest_at timestamp with time zone, window_start timestamp with time zone, window_end timestamp with time zone)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_companies_lifecycle_breakdown"("p_company_id","p_module","p_user_key","p_usage_week");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_companies_lifecycle_identity"(p_company_id text, p_user_key text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '2s'
AS $product_proxy$
  SELECT "01_product_schema"."read_companies_lifecycle_identity"("p_company_id","p_user_key");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_companies_lifecycle_page"(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_query text DEFAULT ''::text, p_usage text DEFAULT 'all'::text, p_integration text DEFAULT 'all'::text, p_sort text DEFAULT 'integration_date'::text, p_direction text DEFAULT 'desc'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_companies_lifecycle_page"("p_from","p_to","p_query","p_usage","p_integration","p_sort","p_direction","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_companies_monthly_breakdown"(p_company_id text, p_module text, p_user_key text DEFAULT NULL::text, p_usage_month date DEFAULT NULL::date)
RETURNS TABLE(event text, subtype text, status text, events bigint, items bigint, instrumented bigint, latest_at timestamp with time zone, window_start timestamp with time zone, window_end timestamp with time zone)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_companies_monthly_breakdown"("p_company_id","p_module","p_user_key","p_usage_month");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_companies_monthly_breakdown_v2"(p_company_id text, p_module text, p_user_key text DEFAULT NULL::text, p_usage_month date DEFAULT NULL::date)
RETURNS TABLE(event text, subtype text, status text, events bigint, items bigint, instrumented bigint, latest_at timestamp with time zone, window_start timestamp with time zone, window_end timestamp with time zone)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_companies_monthly_breakdown_v2"("p_company_id","p_module","p_user_key","p_usage_month");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_companies_monthly_grid"(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_query text DEFAULT ''::text, p_usage text DEFAULT 'all'::text, p_integration text DEFAULT 'all'::text, p_sort text DEFAULT 'integration_month'::text, p_direction text DEFAULT 'desc'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 5000)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '8s'
AS $product_proxy$
  SELECT "01_product_schema"."read_companies_monthly_grid"("p_from","p_to","p_query","p_usage","p_integration","p_sort","p_direction","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_companies_monthly_grid_v2"(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_query text DEFAULT ''::text, p_usage text DEFAULT 'all'::text, p_integration text DEFAULT 'all'::text, p_sort text DEFAULT 'integration_month'::text, p_direction text DEFAULT 'desc'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 5000)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '8s'
AS $product_proxy$
  SELECT "01_product_schema"."read_companies_monthly_grid_v2"("p_from","p_to","p_query","p_usage","p_integration","p_sort","p_direction","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_companies_monthly_identity"(p_company_id text, p_user_key text DEFAULT NULL::text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '2s'
AS $product_proxy$
  SELECT "01_product_schema"."read_companies_monthly_identity"("p_company_id","p_user_key");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_companies_monthly_insights_v1"(p_company_id text, p_module text, p_user_key text DEFAULT NULL::text, p_usage_month date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '12s'
AS $product_proxy$
  SELECT "01_product_schema"."read_companies_monthly_insights_v1"("p_company_id","p_module","p_user_key","p_usage_month");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_companies_page_fast"(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_query text DEFAULT ''::text, p_usage text DEFAULT 'all'::text, p_integration text DEFAULT 'all'::text, p_sort text DEFAULT 'name'::text, p_direction text DEFAULT 'asc'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_companies_page_fast"("p_from","p_to","p_query","p_usage","p_integration","p_sort","p_direction","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_companies_snapshot"(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '20s'
AS $product_proxy$
  SELECT "01_product_schema"."read_companies_snapshot"("p_from","p_to");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_companies_usage"(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
RETURNS TABLE(company_id text, user_key text, module text, events bigint, items bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '20s'
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_companies_usage"("p_from","p_to");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_company_names"(p_company_id text DEFAULT NULL::text)
RETURNS TABLE(company_id text, event_name text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_company_names"("p_company_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_company_users"()
RETURNS TABLE(company_id text, user_key text, user_email text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_company_users"();
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_current_funnel_snapshot"()
RETURNS TABLE(snapshot_id bigint, published_at timestamp with time zone, source_watermark_at timestamp with time zone, n_events bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_current_funnel_snapshot"();
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_current_overview_snapshot"(p_kind text)
RETURNS TABLE(snapshot_id bigint, published_at timestamp with time zone, source_watermark_at timestamp with time zone, n_events bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_current_overview_snapshot"("p_kind");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_funnel_drill_header"(p_snapshot_id bigint, p_node_key text, p_tab text)
RETURNS TABLE(header jsonb)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_funnel_drill_header"("p_snapshot_id","p_node_key","p_tab");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_funnel_generation"(p_snapshot_id bigint)
RETURNS TABLE(snapshot_id bigint, kind text, scope_key text, published_at timestamp with time zone, source_watermark_at timestamp with time zone, n_events bigint, is_current boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_funnel_generation"("p_snapshot_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_funnel_members"(p_snapshot_id bigint, p_node_key text, p_tab text, p_limit integer, p_offset integer)
RETURNS TABLE(card jsonb, total_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_funnel_members"("p_snapshot_id","p_node_key","p_tab","p_limit","p_offset");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_funnel_tab_counts"(p_snapshot_id bigint, p_node_key text)
RETURNS TABLE(tab text, member_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_funnel_tab_counts"("p_snapshot_id","p_node_key");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_active_chart_company_v1"(p_snapshot_id bigint, p_kind text, p_key text, p_segment text, p_user_id text, p_company_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '30s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_active_chart_company_v1"("p_snapshot_id","p_kind","p_key","p_segment","p_user_id","p_company_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_active_chart_company_v2"(p_snapshot_id bigint, p_kind text, p_key text, p_segment text, p_user_id text, p_company_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '30s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_active_chart_company_v2"("p_snapshot_id","p_kind","p_key","p_segment","p_user_id","p_company_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_active_chart_company_v3"(p_snapshot_id bigint, p_kind text, p_key text, p_segment text, p_user_id text, p_company_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '30s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_active_chart_company_v3"("p_snapshot_id","p_kind","p_key","p_segment","p_user_id","p_company_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_active_chart_users_v1"(p_snapshot_id bigint, p_kind text, p_key text, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_module text DEFAULT 'all'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '30s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_active_chart_users_v1"("p_snapshot_id","p_kind","p_key","p_segment","p_query","p_module","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_active_chart_users_v2"(p_snapshot_id bigint, p_kind text, p_key text, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_module text DEFAULT 'all'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '30s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_active_chart_users_v2"("p_snapshot_id","p_kind","p_key","p_segment","p_query","p_module","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_active_chart_users_v3"(p_snapshot_id bigint, p_kind text, p_key text, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_module text DEFAULT 'all'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '30s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_active_chart_users_v3"("p_snapshot_id","p_kind","p_key","p_segment","p_query","p_module","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_active_charts_v1"()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '30s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_active_charts_v1"();
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_active_charts_v2"()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '30s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_active_charts_v2"();
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_active_charts_v3"(p_snapshot_id bigint DEFAULT NULL::bigint)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '30s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_active_charts_v3"("p_snapshot_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_active_charts_v4"(p_snapshot_id bigint DEFAULT NULL::bigint)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_active_charts_v4"("p_snapshot_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_adoption_companies_v1"(p_snapshot_id bigint, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_adoption_companies_v1"("p_snapshot_id","p_segment","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_adoption_companies_v2"(p_snapshot_id bigint, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_adoption_companies_v2"("p_snapshot_id","p_segment","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_adoption_companies_v3"(p_snapshot_id bigint, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_adoption_companies_v3"("p_snapshot_id","p_segment","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_adoption_company_v1"(p_snapshot_id bigint, p_company_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_adoption_company_v1"("p_snapshot_id","p_company_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_adoption_company_v2"(p_snapshot_id bigint, p_company_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_adoption_company_v2"("p_snapshot_id","p_company_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_adoption_company_v3"(p_snapshot_id bigint, p_company_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_adoption_company_v3"("p_snapshot_id","p_company_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_adoption_journey_v1"()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_adoption_journey_v1"();
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_adoption_journey_v2"()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_adoption_journey_v2"();
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_adoption_journey_v3"(p_snapshot_id bigint DEFAULT NULL::bigint)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_adoption_journey_v3"("p_snapshot_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_adoption_journey_v4"(p_snapshot_id bigint DEFAULT NULL::bigint)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_adoption_journey_v4"("p_snapshot_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_core_company_v1"(p_snapshot_id bigint, p_scope text, p_user_id text, p_company_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '25s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_core_company_v1"("p_snapshot_id","p_scope","p_user_id","p_company_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_core_company_v2"(p_snapshot_id bigint, p_scope text, p_user_id text, p_company_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '25s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_core_company_v2"("p_snapshot_id","p_scope","p_user_id","p_company_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_core_company_v3"(p_snapshot_id bigint, p_scope text, p_user_id text, p_company_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '25s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_core_company_v3"("p_snapshot_id","p_scope","p_user_id","p_company_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_core_users_v1"(p_snapshot_id bigint, p_segment text DEFAULT 'mau'::text, p_query text DEFAULT ''::text, p_module text DEFAULT 'all'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '25s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_core_users_v1"("p_snapshot_id","p_segment","p_query","p_module","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_core_users_v2"(p_snapshot_id bigint, p_segment text DEFAULT 'mau'::text, p_query text DEFAULT ''::text, p_module text DEFAULT 'all'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '25s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_core_users_v2"("p_snapshot_id","p_segment","p_query","p_module","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_core_users_v3"(p_snapshot_id bigint, p_segment text DEFAULT 'mau'::text, p_query text DEFAULT ''::text, p_module text DEFAULT 'all'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '25s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_core_users_v3"("p_snapshot_id","p_segment","p_query","p_module","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_drill_header"(p_snapshot_id bigint, p_kind text, p_drill_key text, p_tab text)
RETURNS TABLE(header jsonb)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_overview_drill_header"("p_snapshot_id","p_kind","p_drill_key","p_tab");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_friction_companies_v1"(p_snapshot_id bigint, p_issue_key text, p_period text DEFAULT 'current'::text, p_segment text DEFAULT 'affected'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_friction_companies_v1"("p_snapshot_id","p_issue_key","p_period","p_segment","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_friction_companies_v2"(p_snapshot_id bigint, p_issue_key text, p_period text DEFAULT 'current'::text, p_segment text DEFAULT 'affected'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_friction_companies_v2"("p_snapshot_id","p_issue_key","p_period","p_segment","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_friction_companies_v3"(p_snapshot_id bigint, p_issue_key text, p_period text DEFAULT 'current'::text, p_segment text DEFAULT 'affected'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_friction_companies_v3"("p_snapshot_id","p_issue_key","p_period","p_segment","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_friction_companies_v4"(p_snapshot_id bigint, p_issue_key text, p_period text DEFAULT 'current'::text, p_segment text DEFAULT 'affected'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_friction_companies_v4"("p_snapshot_id","p_issue_key","p_period","p_segment","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_friction_companies_v5"(p_snapshot_id bigint, p_issue_key text, p_period text DEFAULT 'current'::text, p_segment text DEFAULT 'affected'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_friction_companies_v5"("p_snapshot_id","p_issue_key","p_period","p_segment","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_friction_company_v1"(p_snapshot_id bigint, p_issue_key text, p_period text, p_segment text, p_company_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_friction_company_v1"("p_snapshot_id","p_issue_key","p_period","p_segment","p_company_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_friction_company_v2"(p_snapshot_id bigint, p_issue_key text, p_period text, p_segment text, p_company_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_friction_company_v2"("p_snapshot_id","p_issue_key","p_period","p_segment","p_company_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_friction_company_v3"(p_snapshot_id bigint, p_issue_key text, p_period text, p_segment text, p_company_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_friction_company_v3"("p_snapshot_id","p_issue_key","p_period","p_segment","p_company_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_friction_v1"()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_friction_v1"();
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_friction_v2"()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_friction_v2"();
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_friction_v3"(p_snapshot_id bigint DEFAULT NULL::bigint)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_friction_v3"("p_snapshot_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_friction_v4"(p_snapshot_id bigint DEFAULT NULL::bigint)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_friction_v4"("p_snapshot_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_generation"(p_snapshot_id bigint)
RETURNS TABLE(snapshot_id bigint, kind text, scope_key text, published_at timestamp with time zone, source_watermark_at timestamp with time zone, n_events bigint, is_current boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_overview_generation"("p_snapshot_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_history_id_v1"(p_as_of date)
RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_history_id_v1"("p_as_of");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_independent_core_kpis_v1"()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '30s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_independent_core_kpis_v1"();
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_independent_core_kpis_v2"()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '30s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_independent_core_kpis_v2"();
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_independent_core_kpis_v3"(p_snapshot_id bigint DEFAULT NULL::bigint)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '30s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_independent_core_kpis_v3"("p_snapshot_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_independent_core_kpis_v4"(p_snapshot_id bigint DEFAULT NULL::bigint)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '30s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_independent_core_kpis_v4"("p_snapshot_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_members"(p_snapshot_id bigint, p_kind text, p_drill_key text, p_tab text, p_limit integer, p_offset integer)
RETURNS TABLE(card jsonb, total_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_overview_members"("p_snapshot_id","p_kind","p_drill_key","p_tab","p_limit","p_offset");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_tab_counts"(p_snapshot_id bigint, p_kind text, p_drill_key text)
RETURNS TABLE(tab text, member_count bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_overview_tab_counts"("p_snapshot_id","p_kind","p_drill_key");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_workflow_charts_v1"()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_workflow_charts_v1"();
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_workflow_charts_v2"()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_workflow_charts_v2"();
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_workflow_charts_v3"(p_snapshot_id bigint DEFAULT NULL::bigint)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_workflow_charts_v3"("p_snapshot_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_workflow_charts_v4"(p_snapshot_id bigint DEFAULT NULL::bigint)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_workflow_charts_v4"("p_snapshot_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_workflow_company_v1"(p_snapshot_id bigint, p_scope text, p_company_id text, p_week text DEFAULT ''::text, p_module text DEFAULT ''::text, p_mask text DEFAULT ''::text, p_user_id text DEFAULT ''::text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_workflow_company_v1"("p_snapshot_id","p_scope","p_company_id","p_week","p_module","p_mask","p_user_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_workflow_company_v2"(p_snapshot_id bigint, p_scope text, p_company_id text, p_week text DEFAULT ''::text, p_module text DEFAULT ''::text, p_mask text DEFAULT ''::text, p_user_id text DEFAULT ''::text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_workflow_company_v2"("p_snapshot_id","p_scope","p_company_id","p_week","p_module","p_mask","p_user_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_workflow_company_v3"(p_snapshot_id bigint, p_scope text, p_company_id text, p_week text DEFAULT ''::text, p_module text DEFAULT ''::text, p_mask text DEFAULT ''::text, p_user_id text DEFAULT ''::text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_workflow_company_v3"("p_snapshot_id","p_scope","p_company_id","p_week","p_module","p_mask","p_user_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_workflow_mix_companies_v1"(p_snapshot_id bigint, p_period text, p_mask text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_workflow_mix_companies_v1"("p_snapshot_id","p_period","p_mask","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_workflow_mix_companies_v2"(p_snapshot_id bigint, p_period text, p_mask text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_workflow_mix_companies_v2"("p_snapshot_id","p_period","p_mask","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_workflow_mix_companies_v3"(p_snapshot_id bigint, p_period text, p_mask text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_workflow_mix_companies_v3"("p_snapshot_id","p_period","p_mask","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_workflow_module_users_v1"(p_snapshot_id bigint, p_week text, p_module text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_workflow_module_users_v1"("p_snapshot_id","p_week","p_module","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_workflow_module_users_v2"(p_snapshot_id bigint, p_week text, p_module text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_workflow_module_users_v2"("p_snapshot_id","p_week","p_module","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_workflow_module_users_v3"(p_snapshot_id bigint, p_week text, p_module text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_workflow_module_users_v3"("p_snapshot_id","p_week","p_module","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_overview_workflow_module_users_v4"(p_snapshot_id bigint, p_week text, p_module text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '35s'
AS $product_proxy$
  SELECT "01_product_schema"."read_overview_workflow_module_users_v4"("p_snapshot_id","p_week","p_module","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_product_page"(p_page text)
RETURNS TABLE(publication_id bigint, kind text, scope_key text, snapshot_id bigint, payload jsonb, published_at timestamp with time zone, source_watermark_at timestamp with time zone, n_events bigint)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_product_page"("p_page");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_product_snapshot"(p_kind text, p_scope_key text)
RETURNS TABLE(snapshot_id bigint, payload jsonb, published_at timestamp with time zone, source_status text, source_watermark_at timestamp with time zone, source_watermark_date date, n_events bigint, n_client integer, n_activation integer)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_product_snapshot"("p_kind","p_scope_key");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_product_snapshot_with_generation"(p_kind text, p_scope_key text)
RETURNS TABLE(snapshot_id bigint, payload jsonb, published_at timestamp with time zone, source_status text, source_watermark_at timestamp with time zone, source_watermark_date date, n_events bigint, n_client integer, n_activation integer, build_key text, bounds_from timestamp with time zone, bounds_to timestamp with time zone, as_of_at timestamp with time zone)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT * FROM "01_product_schema"."read_product_snapshot_with_generation"("p_kind","p_scope_key");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_activation_company_detail_v1"(p_company_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_activation_company_detail_v1"("p_company_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_activation_company_detail_v2"(p_company_id text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_activation_company_detail_v2"("p_company_id");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_activation_drill_page_v1"(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_query text DEFAULT ''::text, p_status text DEFAULT 'all'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_activation_drill_page_v1"("p_from","p_to","p_query","p_status","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_activation_drill_page_v2"(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_query text DEFAULT ''::text, p_status text DEFAULT 'all'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_activation_drill_page_v2"("p_from","p_to","p_query","p_status","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_churn_month_drill_preview_v1"(p_month date, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_churn_month_drill_preview_v1"("p_month","p_segment","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_churn_month_drill_v1"(p_month date, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_churn_month_drill_v1"("p_month","p_segment","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_churn_month_drill_v2"(p_month date, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_churn_month_drill_v2"("p_month","p_segment","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_dashboard_preview_v4"(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_dashboard_preview_v4"("p_from","p_to");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_dashboard_v3"(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_dashboard_v3"("p_from","p_to");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_dashboard_v4"(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_dashboard_v4"("p_from","p_to");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_dashboard_v5"(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_dashboard_v5"("p_from","p_to");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_dashboard_v5_base"(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_dashboard_v5_base"("p_from","p_to");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_heatmap_cell_drill_v3"(p_interval text, p_cohort_start date DEFAULT NULL::date, p_rel_period integer DEFAULT 1, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_heatmap_cell_drill_v3"("p_interval","p_cohort_start","p_rel_period","p_from","p_to","p_segment","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_heatmap_cell_drill_v4"(p_interval text, p_cohort_start date DEFAULT NULL::date, p_rel_period integer DEFAULT 1, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_heatmap_cell_drill_v4"("p_interval","p_cohort_start","p_rel_period","p_from","p_to","p_segment","p_query","p_page","p_page_size");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_heatmap_v2"(p_interval text DEFAULT 'weekly'::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_heatmap_v2"("p_interval","p_from","p_to");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_kpis_v2"(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp SET statement_timeout TO '5s'
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_kpis_v2"("p_from","p_to");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_period_drill"(p_snapshot_id bigint, p_kind text, p_drill text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_period_drill"("p_snapshot_id","p_kind","p_drill");
$product_proxy$;

CREATE OR REPLACE FUNCTION public."read_retention_summary_drill"(p_snapshot_id bigint, p_drill text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
AS $product_proxy$
  SELECT "01_product_schema"."read_retention_summary_drill"("p_snapshot_id","p_drill");
$product_proxy$;
COMMIT;
