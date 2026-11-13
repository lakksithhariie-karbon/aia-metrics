SET LOCAL lock_timeout='7s'; SET LOCAL statement_timeout='90s';
DO $fix$
DECLARE d text; original text; oid_value oid;
BEGIN
 SELECT p.oid INTO oid_value FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='01_product_schema' AND p.proname='reconcile_sealed_product_shadow_v1';
 IF oid_value IS NULL THEN RAISE EXCEPTION 'Shadow snapshot reconciliation not found';END IF;
 d:=pg_get_functiondef(oid_value);original:=d;
 IF position(E'DECLARE\n  s record;' in d)=0 OR position('FOR s IN SELECT' in d)=0
 THEN RAISE EXCEPTION 'Expected shadow variable collision markers missing';END IF;
 d:=replace(d,E'DECLARE\n  s record;',E'DECLARE\n  generation record;');
 d:=replace(d,'FOR s IN SELECT','FOR generation IN SELECT');
 d:=replace(d,'s.snapshot_id','generation.snapshot_id');
 IF d=original OR d LIKE '%FOR s IN SELECT%' OR d LIKE '%snapshot_id=s.snapshot_id%' THEN
   RAISE EXCEPTION 'Snapshot alias correction incomplete'; END IF;
 EXECUTE d;
END $fix$;
