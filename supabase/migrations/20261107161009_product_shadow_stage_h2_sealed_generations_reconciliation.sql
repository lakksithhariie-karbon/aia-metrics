-- Product H2: reconcile sealed snapshot generations into private shadow only.
-- Reads production, writes numbered Product schema, never mutates legacy or teammate data.
SET LOCAL lock_timeout='7s';
SET LOCAL statement_timeout='180s';
CREATE OR REPLACE FUNCTION "01_product_schema".reconcile_sealed_product_shadow_v1()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO pg_catalog, pg_temp
SET statement_timeout TO '160s'
AS $f$
DECLARE
  s record; n_snapshot bigint:=0; n_overview int:=0; n_funnel int:=0;
  n_period int:=0; n_summary int:=0; n_publication bigint:=0;
  seq text;
BEGIN
  IF NOT pg_try_advisory_xact_lock(7242852,20261108) THEN
    RETURN jsonb_build_object('status','busy');
  END IF;
  IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='01_product_schema' AND c.relkind='r' AND c.relrowsecurity)<>58 OR
     (SELECT count(*) FROM pg_constraint co JOIN pg_class c ON c.oid=co.conrelid
      JOIN pg_namespace n ON n.oid=c.relnamespace
      WHERE n.nspname='01_product_schema' AND co.contype='f' AND co.convalidated)<>18
  THEN RAISE EXCEPTION 'Product shadow prerequisites invalid';END IF;
  UPDATE "01_product_schema".product_snapshot AS d SET
    kind=s.kind,scope_key=s.scope_key,payload=s.payload,source_status=s.source_status,
    source_watermark_at=s.source_watermark_at,source_watermark_date=s.source_watermark_date,
    n_events=s.n_events,n_client=s.n_client,n_activation=s.n_activation,created_at=s.created_at,
    bounds_from=s.bounds_from,bounds_to=s.bounds_to,as_of_at=s.as_of_at,build_key=s.build_key
  FROM public.product_snapshot s WHERE d.id=s.id AND to_jsonb(d) IS DISTINCT FROM to_jsonb(s);
  INSERT INTO "01_product_schema".product_snapshot OVERRIDING SYSTEM VALUE
  SELECT s.* FROM public.product_snapshot s
  WHERE NOT EXISTS(SELECT 1 FROM "01_product_schema".product_snapshot t WHERE t.id=s.id)
  ON CONFLICT (id) DO NOTHING;
  GET DIAGNOSTICS n_snapshot=ROW_COUNT;
  seq:=pg_get_serial_sequence('"01_product_schema".product_snapshot','id');
  IF seq IS NOT NULL AND EXISTS(SELECT 1 FROM "01_product_schema".product_snapshot) THEN
     PERFORM setval(seq,(SELECT MAX(id) FROM "01_product_schema".product_snapshot),true);
  END IF;

  FOR s IN SELECT src.snapshot_id FROM public.product_overview_seal src
    WHERE NOT EXISTS (SELECT 1 FROM "01_product_schema".product_overview_seal t
                     WHERE t.snapshot_id=src.snapshot_id)
  LOOP
    INSERT INTO "01_product_schema".product_overview_drill
    SELECT * FROM public.product_overview_drill WHERE snapshot_id=s.snapshot_id ON CONFLICT DO NOTHING;
    INSERT INTO "01_product_schema".product_overview_member
    SELECT * FROM public.product_overview_member WHERE snapshot_id=s.snapshot_id ON CONFLICT DO NOTHING;
    INSERT INTO "01_product_schema".product_overview_seal
    SELECT * FROM public.product_overview_seal WHERE snapshot_id=s.snapshot_id ON CONFLICT DO NOTHING;
    n_overview:=n_overview+1;
  END LOOP;
  FOR s IN SELECT src.snapshot_id FROM public.product_funnel_seal src
    WHERE NOT EXISTS(SELECT 1 FROM "01_product_schema".product_funnel_seal t
                     WHERE t.snapshot_id=src.snapshot_id)
  LOOP
    INSERT INTO "01_product_schema".product_funnel_drill
    SELECT * FROM public.product_funnel_drill WHERE snapshot_id=s.snapshot_id ON CONFLICT DO NOTHING;
    INSERT INTO "01_product_schema".product_funnel_member
    SELECT * FROM public.product_funnel_member WHERE snapshot_id=s.snapshot_id ON CONFLICT DO NOTHING;
    INSERT INTO "01_product_schema".product_funnel_seal
    SELECT * FROM public.product_funnel_seal WHERE snapshot_id=s.snapshot_id ON CONFLICT DO NOTHING;
    n_funnel:=n_funnel+1;
  END LOOP;
  FOR s IN SELECT src.snapshot_id FROM public.product_retention_period_seal src
    WHERE NOT EXISTS(SELECT 1 FROM "01_product_schema".product_retention_period_seal t
                     WHERE t.snapshot_id=src.snapshot_id)
  LOOP
    INSERT INTO "01_product_schema".product_retention_period_drill
    SELECT * FROM public.product_retention_period_drill WHERE snapshot_id=s.snapshot_id ON CONFLICT DO NOTHING;
    INSERT INTO "01_product_schema".product_retention_period_seal
    SELECT * FROM public.product_retention_period_seal WHERE snapshot_id=s.snapshot_id ON CONFLICT DO NOTHING;
    n_period:=n_period+1;
  END LOOP;
  FOR s IN SELECT src.snapshot_id FROM public.product_retention_summary_seal src
    WHERE NOT EXISTS(SELECT 1 FROM "01_product_schema".product_retention_summary_seal t
                     WHERE t.snapshot_id=src.snapshot_id)
  LOOP
    INSERT INTO "01_product_schema".product_retention_summary_header
    SELECT * FROM public.product_retention_summary_header WHERE snapshot_id=s.snapshot_id ON CONFLICT DO NOTHING;
    INSERT INTO "01_product_schema".product_retention_summary_member
    SELECT * FROM public.product_retention_summary_member WHERE snapshot_id=s.snapshot_id ON CONFLICT DO NOTHING;
    INSERT INTO "01_product_schema".product_retention_summary_seal
    SELECT * FROM public.product_retention_summary_seal WHERE snapshot_id=s.snapshot_id ON CONFLICT DO NOTHING;
    n_summary:=n_summary+1;
  END LOOP;
  INSERT INTO "01_product_schema".product_publication OVERRIDING SYSTEM VALUE
    SELECT src.* FROM public.product_publication src
    WHERE NOT EXISTS(SELECT 1 FROM "01_product_schema".product_publication t
                     WHERE t.publication_id=src.publication_id)
    ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS n_publication=ROW_COUNT;
  INSERT INTO "01_product_schema".product_publication_member
    SELECT src.* FROM public.product_publication_member src
    WHERE NOT EXISTS (SELECT 1 FROM "01_product_schema".product_publication_member dest
                      WHERE dest.publication_id=src.publication_id AND
                            dest.kind=src.kind AND dest.scope_key=src.scope_key)
    ON CONFLICT DO NOTHING;

  UPDATE "01_product_schema".product_refresh_run AS d SET
    kind=s.kind,scope_key=s.scope_key,build_key=s.build_key,status=s.status,
    source_watermark_at=s.source_watermark_at,n_events=s.n_events,
    staged_snapshot_id=s.staged_snapshot_id,error_code=s.error_code,detail=s.detail,
    created_at=s.created_at,updated_at=s.updated_at
  FROM public.product_refresh_run s WHERE d.id=s.id AND to_jsonb(d) IS DISTINCT FROM to_jsonb(s);
  INSERT INTO "01_product_schema".product_refresh_run OVERRIDING SYSTEM VALUE
    SELECT s.* FROM public.product_refresh_run s
    WHERE NOT EXISTS (SELECT 1 FROM "01_product_schema".product_refresh_run t WHERE t.id=s.id)
    ON CONFLICT DO NOTHING;

  INSERT INTO "01_product_schema".product_snapshot_current(kind,scope_key,snapshot_id,published_at)
  SELECT kind,scope_key,snapshot_id,published_at FROM public.product_snapshot_current WHERE TRUE
  ON CONFLICT(kind,scope_key) DO UPDATE
    SET snapshot_id=EXCLUDED.snapshot_id,published_at=EXCLUDED.published_at;
  INSERT INTO "01_product_schema".product_publication_current(page,publication_id,swapped_at)
  SELECT page,publication_id,swapped_at FROM public.product_publication_current WHERE TRUE
  ON CONFLICT(page) DO UPDATE
    SET publication_id=EXCLUDED.publication_id,swapped_at=EXCLUDED.swapped_at;

  IF EXISTS (SELECT 1 FROM public.product_snapshot_current live
      WHERE NOT EXISTS(SELECT 1 FROM "01_product_schema".product_snapshot_current dest
        WHERE dest.kind=live.kind AND dest.scope_key=live.scope_key AND dest.snapshot_id=live.snapshot_id))
  THEN RAISE EXCEPTION 'Shadow current snapshot pointer mismatch'; END IF;
  RETURN jsonb_build_object('status','ok','new_snapshot_rows',n_snapshot,
     'new_overview_generations',n_overview,'new_funnel_generations',n_funnel,
     'new_retention_period_generations',n_period,'new_retention_summary_generations',n_summary,
     'new_publications',n_publication);
END $f$;
REVOKE ALL ON FUNCTION "01_product_schema".reconcile_sealed_product_shadow_v1()
 FROM PUBLIC,anon,authenticated,service_role,product_metrics_fetcher;
