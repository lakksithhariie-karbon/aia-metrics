-- Protect the 12 public company/activity/retention source tables (2026-11-03).
-- Preserve *existing* private product_metrics_fetcher DML; add no grants to public roles.
-- service_role and postgres are established BYPASSRLS roles.
-- Revoke stray anon/authenticated TRUNCATE and maintenance grants: RLS does not protect TRUNCATE.
DO $preflight$
DECLARE found_count integer;
BEGIN
  SELECT count(*) INTO found_count
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind IN ('r','p') AND NOT c.relrowsecurity;
  IF found_count <> 12 THEN
    RAISE EXCEPTION 'Unexpected count of public RLS-disabled tables: %', found_count;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public'
      AND tablename = ANY (ARRAY['client_company','company_activation','company_day_action','company_month_core','company_profile','company_week_action','company_week_product','company_week_value','events','export_watermarks','person_day_action','retention_cells'])
  ) THEN
    RAISE EXCEPTION 'Existing policies found; manual review required';
  END IF;
END;
$preflight$;

REVOKE ALL PRIVILEGES ON TABLE public.client_company FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.company_activation FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.company_day_action FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.company_month_core FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.company_profile FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.company_week_action FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.company_week_product FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.company_week_value FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.events FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.export_watermarks FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.person_day_action FROM PUBLIC, anon, authenticated;
REVOKE ALL PRIVILEGES ON TABLE public.retention_cells FROM PUBLIC, anon, authenticated;

CREATE POLICY client_company_trusted_fetcher_all ON public.client_company
  FOR ALL TO product_metrics_fetcher USING (true) WITH CHECK (true);
CREATE POLICY company_activation_trusted_fetcher_all ON public.company_activation
  FOR ALL TO product_metrics_fetcher USING (true) WITH CHECK (true);
CREATE POLICY company_month_core_trusted_fetcher_all ON public.company_month_core
  FOR ALL TO product_metrics_fetcher USING (true) WITH CHECK (true);
CREATE POLICY company_profile_trusted_fetcher_all ON public.company_profile
  FOR ALL TO product_metrics_fetcher USING (true) WITH CHECK (true);
CREATE POLICY company_week_action_trusted_fetcher_all ON public.company_week_action
  FOR ALL TO product_metrics_fetcher USING (true) WITH CHECK (true);
CREATE POLICY company_week_product_trusted_fetcher_all ON public.company_week_product
  FOR ALL TO product_metrics_fetcher USING (true) WITH CHECK (true);
CREATE POLICY company_week_value_trusted_fetcher_all ON public.company_week_value
  FOR ALL TO product_metrics_fetcher USING (true) WITH CHECK (true);
CREATE POLICY events_trusted_fetcher_all ON public.events
  FOR ALL TO product_metrics_fetcher USING (true) WITH CHECK (true);
CREATE POLICY export_watermarks_trusted_fetcher_all ON public.export_watermarks
  FOR ALL TO product_metrics_fetcher USING (true) WITH CHECK (true);
CREATE POLICY retention_cells_trusted_fetcher_all ON public.retention_cells
  FOR ALL TO product_metrics_fetcher USING (true) WITH CHECK (true);
CREATE POLICY company_day_action_trusted_fetcher_select ON public.company_day_action
  FOR SELECT TO product_metrics_fetcher USING (true);
CREATE POLICY person_day_action_trusted_fetcher_select ON public.person_day_action
  FOR SELECT TO product_metrics_fetcher USING (true);

ALTER TABLE public.client_company ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_activation ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_day_action ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_month_core ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_week_action ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_week_product ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_week_value ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.export_watermarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.person_day_action ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.retention_cells ENABLE ROW LEVEL SECURITY;

-- Verification guard: all twelve protections installed and no untrusted DML rights.
DO $postflight$
DECLARE protected_count integer;
BEGIN
  SELECT count(*) INTO protected_count
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relrowsecurity
    AND c.relname = ANY (ARRAY['client_company','company_activation','company_day_action','company_month_core','company_profile','company_week_action','company_week_product','company_week_value','events','export_watermarks','person_day_action','retention_cells']);
  IF protected_count <> 12 THEN
    RAISE EXCEPTION 'RLS protection count mismatch: %', protected_count;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relname = ANY (ARRAY['client_company','company_activation','company_day_action','company_month_core','company_profile','company_week_action','company_week_product','company_week_value','events','export_watermarks','person_day_action','retention_cells'])
      AND (has_table_privilege('anon',c.oid,'SELECT, INSERT, UPDATE, DELETE, TRUNCATE')
           OR has_table_privilege('authenticated',c.oid,'SELECT, INSERT, UPDATE, DELETE, TRUNCATE'))
  ) THEN
    RAISE EXCEPTION 'Unexpected public role table privilege remains';
  END IF;
END;
$postflight$;
