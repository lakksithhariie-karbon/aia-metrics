-- Product Stage D: four view clones private to new Product schema.
SET LOCAL lock_timeout='6s';
SET LOCAL statement_timeout='180s';
SET LOCAL search_path=public,metrics_private,pg_catalog;
DO $views$
DECLARE rec record; definition text; n integer:=0; referenced_bad integer;
BEGIN
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
     WHERE ns.nspname='01_product_schema' AND c.relkind='r')<>58 THEN
     RAISE EXCEPTION 'Expected all Product shadow tables'; END IF;
 IF EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
       WHERE ns.nspname='01_product_schema' AND c.relkind='v') THEN
     RAISE EXCEPTION 'Product shadow views already exist'; END IF;
 FOR rec IN SELECT c.oid,c.relname viewname FROM pg_class c
             JOIN pg_namespace ns ON ns.oid=c.relnamespace
             WHERE ns.nspname IN('public','metrics_private') AND c.relkind='v'
             ORDER BY ns.nspname,c.relname
 LOOP
   definition:=pg_get_viewdef(rec.oid,true);
   IF definition LIKE '%public.%' OR definition LIKE '%metrics_private.%'
     OR definition LIKE '%feature_olap.%' OR definition LIKE '%product_source.%'
   THEN RAISE EXCEPTION 'Source-qualified Product view %',rec.viewname;END IF;
   PERFORM set_config('search_path','"01_product_schema",pg_catalog',true);
   EXECUTE format('CREATE VIEW %I.%I AS %s','01_product_schema',rec.viewname,definition);
   EXECUTE format('REVOKE ALL ON %I.%I FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher',
                  '01_product_schema',rec.viewname);
   PERFORM set_config('search_path','public,metrics_private,pg_catalog',true);
   n:=n+1;
 END LOOP;
 IF n<>4 THEN RAISE EXCEPTION 'Expected four private Product views';END IF;
 SELECT count(*) INTO referenced_bad
 FROM pg_rewrite rw JOIN pg_class vc ON vc.oid=rw.ev_class
 JOIN pg_namespace vn ON vn.oid=vc.relnamespace
 JOIN pg_depend dep ON dep.objid=rw.oid AND dep.classid='pg_rewrite'::regclass
                   AND dep.refclassid='pg_class'::regclass
 JOIN pg_class src ON src.oid=dep.refobjid
 JOIN pg_namespace sn ON sn.oid=src.relnamespace
 WHERE vn.nspname='01_product_schema' AND vc.relkind='v'
 AND src.relkind IN('r','v','m') AND sn.nspname<>'01_product_schema';
 IF referenced_bad<>0 THEN RAISE EXCEPTION 'Shadow views unexpectedly refer to source tables';END IF;
END $views$;
