-- Non-writing compile check for all 105 numbered Product RPC targets.
-- Construct typed NULL arguments from the actual pg_proc signatures and
-- EXPLAIN the exact SQL expression shape used in the public reader proxies.
-- This validates parser/name/argument compatibility without executing the
-- function or changing any production public reader.
DO $parse$
DECLARE r record; a text; statement text; checked int:=0;
BEGIN
 FOR r IN
   SELECT p.proname,p.pronargs,p.proargtypes,p.proretset
   FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname LIKE 'read_%'
     AND p.proname NOT LIKE 'read_jira_%'
     AND p.proname NOT LIKE 'read_ai_%'
     AND p.proname NOT LIKE 'read_infra_%'
     AND p.proname NOT LIKE 'read_product_shadow_%'
 LOOP
   SELECT COALESCE(string_agg('NULL::'||format_type(r.proargtypes[i],NULL),',' ORDER BY i),'')
   INTO a FROM generate_series(0,r.pronargs-1) g(i);
   statement:=format('EXPLAIN SELECT %s "01_product_schema".%I(%s)',
     CASE WHEN r.proretset THEN '* FROM' ELSE '' END,r.proname,a);
   EXECUTE statement;
   checked:=checked+1;
 END LOOP;
 IF checked<>105 THEN RAISE EXCEPTION 'Expected 105 public Product RPCs, got %',checked;END IF;
END $parse$;
