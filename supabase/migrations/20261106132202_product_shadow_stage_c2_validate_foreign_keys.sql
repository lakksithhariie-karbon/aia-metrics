-- Product Stage C2: validate every newly created shadow-only FK.
SET LOCAL lock_timeout='6s';
SET LOCAL statement_timeout='900s';
DO $validate$
DECLARE r record; n integer:=0;
BEGIN
 IF (SELECT count(*) FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid
     JOIN pg_namespace ns ON ns.oid=c.relnamespace
     WHERE ns.nspname='01_product_schema' AND co.contype='f')<>18 THEN
     RAISE EXCEPTION 'Expected 18 target foreign keys';
 END IF;
 FOR r IN SELECT c.relname table_name, co.conname fk_name FROM pg_constraint co
   JOIN pg_class c ON c.oid=co.conrelid
   JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='01_product_schema' AND co.contype='f'
   ORDER BY c.relname,co.conname
 LOOP
   EXECUTE format('ALTER TABLE %I.%I VALIDATE CONSTRAINT %I',
                  '01_product_schema',r.table_name,r.fk_name);
   n:=n+1;
 END LOOP;
 IF n<>18 OR EXISTS(SELECT 1 FROM pg_constraint co
         JOIN pg_class c ON c.oid=co.conrelid
         JOIN pg_namespace ns ON ns.oid=c.relnamespace
         WHERE ns.nspname='01_product_schema' AND co.contype='f' AND NOT co.convalidated)
 THEN RAISE EXCEPTION 'Not all target Product foreign keys validated';
 END IF;
END $validate$;
