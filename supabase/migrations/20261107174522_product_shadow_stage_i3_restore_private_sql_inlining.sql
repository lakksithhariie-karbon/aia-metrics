-- Product I3: restore inlining of private immutable SQL helpers.
-- Immutable SQL with a per-function SET search_path cannot be inlined, causing
-- the 550k-event shadow retention refresh to exceed its 145s deadline.
-- These 10 helpers are SECURITY INVOKER, ungranted, and have no unqualified
-- user-schema references; their SECURITY DEFINER callers have fixed search paths.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='90s';
DO $restore$
DECLARE r record; n integer:=0;
BEGIN
 FOR r IN SELECT p.proname,pg_get_function_identity_arguments(p.oid) args,
                  pg_get_functiondef(p.oid) ddl,
                  p.provolatile,p.prosecdef,l.lanname
 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
 JOIN pg_language l ON l.oid=p.prolang
 WHERE ns.nspname='01_product_schema' AND p.proname IN
 ('company_items_for','company_module_for','company_subtype_for',
 'company_usable_name','company_work_module_v2','core_activity_kind',
 'is_core_activity','is_qualifying_sync','is_successful_integration','merge_event_properties')
 ORDER BY p.proname
 LOOP
 IF r.provolatile<>'i' OR r.prosecdef OR r.lanname<>'sql'
    OR r.ddl LIKE '%public.%' OR r.ddl LIKE '%metrics_private.%'
 THEN RAISE EXCEPTION 'Unsafe immutable helper %',r.proname;END IF;
 EXECUTE format('ALTER FUNCTION %I.%I(%s) RESET search_path',
    '01_product_schema',r.proname,r.args);
 n:=n+1;
 END LOOP;
 IF n<>10 THEN RAISE EXCEPTION 'Expected exactly ten immutable SQL helpers';END IF;
 IF EXISTS(
  SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='01_product_schema' AND p.proname IN
  ('company_items_for','company_module_for','company_subtype_for',
   'company_usable_name','company_work_module_v2','core_activity_kind',
   'is_core_activity','is_qualifying_sync','is_successful_integration','merge_event_properties')
 AND p.proconfig IS NOT NULL
 ) THEN RAISE EXCEPTION 'Function inlining configuration still present';END IF;
END $restore$;
