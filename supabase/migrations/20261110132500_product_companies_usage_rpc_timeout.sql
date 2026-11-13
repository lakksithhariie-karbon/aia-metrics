-- Reversible bounded timeout for Companies usage reader; measured 6.6s full scan
-- on 554k+ events. This only changes RPC execution limits, not reader routing
-- or ingestion. Authenticated Companies Edge returned SQLSTATE 57014 at 8s.
BEGIN;
SET LOCAL lock_timeout='5s';
ALTER FUNCTION public.read_companies_usage(date,date)
  SET statement_timeout='20s';
ALTER FUNCTION "01_product_schema".read_companies_usage(date,date)
  SET statement_timeout='20s';
COMMIT;
