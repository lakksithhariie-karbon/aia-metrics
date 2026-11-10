-- Product shadow-only runtime fix. Production ingestion and legacy readers are unchanged.
-- PostgREST applies its request-level statement_timeout to RPC calls unless the
-- exposed wrapper explicitly hoists a function-level setting.
-- Private refresh_retention already uses a 145-second statement timeout, but
-- the public bridge had no statement_timeout and shadow Edge timed out at ~35s.
-- This affects only public.shadow_product_refresh_retention(text), an existing
-- service_role-only RPC. Do not alter global/service_role/authenticator settings.
DO $guard$
BEGIN
  IF to_regprocedure('public.shadow_product_refresh_retention(text)') IS NULL
     OR to_regprocedure('"01_product_schema".refresh_retention(text)') IS NULL
  THEN RAISE EXCEPTION 'Expected isolated shadow retention RPCs are absent'; END IF;
  IF has_function_privilege('anon', 'public.shadow_product_refresh_retention(text)', 'EXECUTE')
    OR has_function_privilege('authenticated', 'public.shadow_product_refresh_retention(text)', 'EXECUTE')
  THEN RAISE EXCEPTION 'Shadow refresh RPC access is unexpectedly public'; END IF;
END $guard$;
ALTER FUNCTION public.shadow_product_refresh_retention(text) SET statement_timeout TO '150s';
