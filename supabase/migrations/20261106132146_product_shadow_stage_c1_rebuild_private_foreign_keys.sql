-- Product Stage C1: recreate the source's 18 foreign-key relationships
-- ONLY between shadow tables, initially NOT VALID for controlled verification.
SET LOCAL lock_timeout='6s';
SET LOCAL statement_timeout='240s';
DO $fk$
DECLARE rec record; v_def text; v_original text; n integer:=0;
BEGIN
 IF (SELECT count(*) FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid
     JOIN pg_namespace ns ON ns.oid=c.relnamespace
     WHERE co.contype='f' AND ns.nspname IN('public','metrics_private'))<>18
 THEN RAISE EXCEPTION 'Source Product FK inventory changed'; END IF;
 IF EXISTS (SELECT 1 FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid
     JOIN pg_namespace ns ON ns.oid=c.relnamespace
     WHERE co.contype='f' AND ns.nspname='01_product_schema') THEN
     RAISE EXCEPTION 'Product shadow already has foreign keys'; END IF;
 FOR rec IN SELECT co.oid,co.conname,c.relname source_table,ref.relname ref_table,
     ns.nspname source_schema,refns.nspname ref_schema
     FROM pg_constraint co JOIN pg_class c ON co.conrelid=c.oid
     JOIN pg_namespace ns ON ns.oid=c.relnamespace
     JOIN pg_class ref ON ref.oid=co.confrelid
     JOIN pg_namespace refns ON refns.oid=ref.relnamespace
     WHERE co.contype='f' AND ns.nspname IN('public','metrics_private')
     ORDER BY ns.nspname,c.relname,co.conname
 LOOP
   IF rec.ref_schema NOT IN ('public','metrics_private') THEN
     RAISE EXCEPTION 'Unexpected cross-domain FK reference %.%',rec.ref_schema,rec.ref_table;
   END IF;
   v_original:=pg_get_constraintdef(rec.oid,true);
   v_def:=replace(v_original,
    'REFERENCES '||rec.ref_schema||'.'||rec.ref_table||'(',
    'REFERENCES "01_product_schema".'||quote_ident(rec.ref_table)||'(');
   v_def:=replace(v_def,
    'REFERENCES '||rec.ref_table||'(',
    'REFERENCES "01_product_schema".'||quote_ident(rec.ref_table)||'(');
   IF position('REFERENCES "01_product_schema".' IN v_def)=0 THEN
     RAISE EXCEPTION 'Unable to safely rewrite FK %: %',rec.conname,v_original;
   END IF;
   EXECUTE format('ALTER TABLE %I.%I ADD CONSTRAINT %I %s NOT VALID',
      '01_product_schema',rec.source_table,rec.conname,v_def);
   n:=n+1;
 END LOOP;
 IF n<>18 OR (SELECT count(*) FROM pg_constraint co
     JOIN pg_class c ON c.oid=co.conrelid JOIN pg_namespace ns ON ns.oid=c.relnamespace
     JOIN pg_class ref ON ref.oid=co.confrelid JOIN pg_namespace refns ON refns.oid=ref.relnamespace
     WHERE ns.nspname='01_product_schema' AND refns.nspname='01_product_schema'
         AND co.contype='f')<>18 THEN
    RAISE EXCEPTION 'Target foreign key inventory or referenced schema incorrect';
 END IF;
END $fk$;
