-- Product Stage F2: refresh 11 small shadow public reporting tables only.
-- Source public tables remain untouched and online. No new grants or cron jobs.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='240s';
DO $refresh$
DECLARE r text; n integer:=0; copied bigint; existing bigint;
BEGIN
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace s ON s.oid=c.relnamespace
     WHERE s.nspname='01_product_schema' AND c.relkind='r' AND c.relrowsecurity)<>58
 THEN RAISE EXCEPTION 'Product shadow not in expected state';END IF;
 FOREACH r IN ARRAY ARRAY[
    'client_company','company_activation','company_core_activity','company_day_action',
    'company_directory','company_month_core','company_profile','company_week_action',
    'company_week_product','company_week_value','person_day_action'
 ] LOOP
   IF EXISTS(SELECT 1 FROM pg_constraint co JOIN pg_class c ON c.oid=co.confrelid
       JOIN pg_namespace s ON s.oid=c.relnamespace
       WHERE co.contype='f' AND s.nspname='01_product_schema' AND c.relname=r)
   THEN RAISE EXCEPTION 'Unexpected inbound FK to %',r;END IF;
   EXECUTE format('TRUNCATE TABLE %I.%I','01_product_schema',r);
   EXECUTE format('INSERT INTO %I.%I SELECT * FROM %I.%I','01_product_schema',r,'public',r);
   GET DIAGNOSTICS copied=ROW_COUNT;
   EXECUTE format('SELECT count(*) FROM %I.%I','01_product_schema',r) INTO existing;
   IF existing<>copied THEN RAISE EXCEPTION 'Product mirror row-count check failed for %',r; END IF;
   n:=n+1;
 END LOOP;
 IF n<>11 THEN RAISE EXCEPTION 'Expected 11 reporting mirrors';END IF;
END $refresh$;
