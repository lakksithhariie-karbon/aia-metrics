-- Product I2: harden 14 shadow function search paths and remove final
-- explicit public helper reference. Only shadow schema functions change.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='90s';
DO $harden$
DECLARE rec record; d text; n integer:=0;
BEGIN
 IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
  WHERE ns.nspname='01_product_schema'
  AND NOT EXISTS(SELECT 1 FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) cfg WHERE cfg LIKE 'search_path=%'))<>14
 THEN RAISE EXCEPTION 'Expected 14 shadow functions with unconfigured search_path';END IF;
 SELECT pg_get_functiondef(p.oid) INTO d
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='01_product_schema' AND p.proname='is_core_activity';
 IF d NOT LIKE '%public.core_activity_kind(%'
 THEN RAISE EXCEPTION 'Expected explicit public core helper reference missing';END IF;
 d:=replace(d,'public.core_activity_kind(',
             '"01_product_schema".core_activity_kind(');
 EXECUTE d;
 FOR rec IN SELECT p.proname,pg_get_function_identity_arguments(p.oid) args
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='01_product_schema' AND
       NOT EXISTS(SELECT 1 FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) cfg WHERE cfg LIKE 'search_path=%')
   ORDER BY p.proname
 LOOP
   EXECUTE format('ALTER FUNCTION %I.%I(%s) SET search_path TO %I,pg_catalog,pg_temp',
      '01_product_schema',rec.proname,rec.args,'01_product_schema');
   n:=n+1;
 END LOOP;
 IF n<>14 OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='01_product_schema' AND
    NOT EXISTS(SELECT 1 FROM unnest(coalesce(p.proconfig,ARRAY[]::text[])) cfg WHERE cfg LIKE 'search_path=%'))
 THEN RAISE EXCEPTION 'Shadow function search_path hardening incomplete';END IF;
END $harden$;
