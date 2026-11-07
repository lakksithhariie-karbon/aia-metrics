-- Product migration Stage A: non-destructive private shadow tables.
-- The 58 existing Product source tables are neither changed nor locked for writes.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='240s';
DO $stage$
DECLARE r record; n integer:=0; v_target_oid oid;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='01_product_schema') THEN
   RAISE EXCEPTION 'Target Product schema is absent';
 END IF;
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname IN('public','metrics_private') AND c.relkind='r')<>58 THEN
   RAISE EXCEPTION 'Unexpected Product source inventory';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='01_product_schema' AND c.relkind IN ('r','v','m','p')) THEN
   RAISE EXCEPTION 'Product shadow schema is not empty';
 END IF;
 FOR r IN
   SELECT n.nspname src,c.relname tab,c.oid
   FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname IN ('public','metrics_private') AND c.relkind='r'
   ORDER BY n.nspname,c.relname
 LOOP
   EXECUTE format('CREATE TABLE %I.%I (LIKE %I.%I INCLUDING ALL)',
                   '01_product_schema',r.tab,r.src,r.tab);
   EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY',
                   '01_product_schema',r.tab);
   EXECUTE format('REVOKE ALL ON TABLE %I.%I FROM PUBLIC, anon, authenticated, service_role, product_metrics_fetcher',
                   '01_product_schema',r.tab);
   EXECUTE format('COMMENT ON TABLE %I.%I IS %L',
     '01_product_schema',r.tab,
     'Product migration shadow table. Source: '||r.src||'.'||r.tab||'; no live writer or public reader routed to this copy.');
   n:=n+1;
 END LOOP;
 IF n<>58 OR
    (SELECT count(*) FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
     WHERE ns.nspname='01_product_schema' AND c.relkind='r' AND c.relrowsecurity)<>58 THEN
    RAISE EXCEPTION 'Product shadow creation count or RLS failed';
 END IF;
END $stage$;
