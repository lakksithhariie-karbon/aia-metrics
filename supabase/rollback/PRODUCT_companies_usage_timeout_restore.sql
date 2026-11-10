-- Run to restore the two reader RPCs' former inherited timeout behavior.
-- This is a function-settings-only rollback, no data or routing changes.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER FUNCTION public.read_companies_usage(date,date)
  RESET statement_timeout;
ALTER FUNCTION "01_product_schema".read_companies_usage(date,date)
  RESET statement_timeout;
COMMIT;
