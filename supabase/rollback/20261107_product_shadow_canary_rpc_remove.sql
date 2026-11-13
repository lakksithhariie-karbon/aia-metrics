-- Product I1 reversible canary endpoints only. No production readers changed.
DROP FUNCTION IF EXISTS public.read_product_shadow_companies_canary(date,date);
DROP FUNCTION IF EXISTS public.read_product_shadow_retention_canary(date,date);
DROP FUNCTION IF EXISTS public.read_product_shadow_overview_canary(bigint);
