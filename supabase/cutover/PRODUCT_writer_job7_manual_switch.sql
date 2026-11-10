-- MANUAL, SHADOW-ONLY WRITER ROUTING, NOT APPLIED.
-- Changes only the Vault URL *name* referenced by hourly job #7; keeps all
-- service_role/cron headers in Vault, and leaves original Vault URL unchanged.
-- The isolated shadow Edge has passed an authenticated one-shot canary.
-- RUN ONLY in the coordinated maintenance window with reader and cron cutover,
-- after evidence of fresh snapshot publication and rollback rehearsal.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='90s';
DO $writer$
DECLARE original_cmd text;
BEGIN
 IF current_setting('aia_product_cutover.approved',true) IS DISTINCT FROM 'yes'
 OR current_setting('aia_product_cutover.authenticated_canary_passed',true) IS DISTINCT FROM 'yes'
 OR current_setting('aia_product_cutover.dashboard_http_passed',true) IS DISTINCT FROM 'yes'
 OR current_setting('aia_product_cutover.rollback_rehearsed',true) IS DISTINCT FROM 'yes'
 THEN RAISE EXCEPTION 'Product writer switch requires authenticated canary, dashboard HTTP check, rollback and operator approval'; END IF;
 -- Fail closed on the actual source generation used by the live Overview
 -- dashboard. The five selected snapshots must be complete, agree on one
 -- generation, and be no more than 24 hours behind the healthy source.
 -- This is independent of the legacy Retention snapshot archive; the live
 -- Retention v5 path uses metrics_private.retention_dashboard_meta_v4.
 IF NOT EXISTS (
  SELECT 1 FROM public.export_watermarks w
  CROSS JOIN LATERAL (
   SELECT count(s.id) AS matched,
          count(DISTINCT s.source_watermark_at) AS watermark_versions,
          count(DISTINCT s.n_events) AS event_count_versions,
          coalesce(bool_and(s.source_status='ok'
             AND s.source_watermark_at>=w.last_success_at-interval '24 hours'
             AND s.source_watermark_at<=w.last_success_at),false) AS fresh
   FROM (VALUES ('overview'),('overview-funnel'),('overview-feature-usage'),
                ('overview-module-mix'),('overview-friction')) required(kind)
   LEFT JOIN public.product_snapshot_current c
     ON c.kind=required.kind AND c.scope_key=''
   LEFT JOIN public.product_snapshot s ON s.id=c.snapshot_id
  ) snapshots
  WHERE w.job_name='incremental' AND w.status='ok'
    AND snapshots.matched=5
    AND snapshots.watermark_versions=1
    AND snapshots.event_count_versions=1
    AND snapshots.fresh
 ) THEN
  RAISE EXCEPTION 'Product writer cutover blocked: current Overview snapshots are missing, stale, or mixed-generation';
 END IF;
  -- Canonical readership must never switch onto a stale/unpublished Product
  -- generation. This page manifest must list all five CURRENT sealed kinds
  -- at the exact completed private-ingestion generation. Unlike a simple
  -- row-count check, it rejects mixed or missing snapshots and memberships.
  IF NOT EXISTS (
    SELECT 1
    FROM "01_product_schema".product_publication_current pc
    JOIN "01_product_schema".product_publication pub
      ON pub.publication_id=pc.publication_id
    JOIN "01_product_schema".product_publication_member m
      ON m.publication_id=pc.publication_id
    JOIN "01_product_schema".product_snapshot_current c
      ON c.kind=m.kind AND c.scope_key=m.scope_key
         AND c.snapshot_id=m.snapshot_id
    JOIN "01_product_schema".product_snapshot s
      ON s.id=m.snapshot_id
    JOIN "01_product_schema".export_watermarks w
      ON w.job_name='incremental' AND w.status='ok'
    WHERE pc.page='overview' AND pub.page='overview'
      AND pub.source_watermark_at=w.last_success_at
      AND pub.n_events=(SELECT count(*) FROM "01_product_schema".events)
      AND w.last_success_at>=now()-interval '24 hours'
    GROUP BY pc.publication_id,pub.source_watermark_at
    HAVING count(*)=5 AND count(DISTINCT m.kind)=5
      AND bool_and(
        m.scope_key='' AND
        m.kind=ANY(ARRAY['overview','overview-funnel',
          'overview-feature-usage','overview-module-mix','overview-friction'])
        AND s.source_status='ok'
        AND s.source_watermark_at=pub.source_watermark_at
        AND s.n_events=pub.n_events
        AND CASE WHEN m.kind='overview-funnel'
          THEN EXISTS(SELECT 1 FROM "01_product_schema".product_funnel_seal z
             WHERE z.snapshot_id=m.snapshot_id)
          ELSE EXISTS(SELECT 1 FROM "01_product_schema".product_overview_seal z
             WHERE z.snapshot_id=m.snapshot_id)
        END
      )
  ) THEN
    RAISE EXCEPTION 'Product cutover blocked: canonical Overview page manifest is stale, missing, unsealed or mixed-generation';
  END IF;

 SELECT command INTO original_cmd FROM cron.job
 WHERE jobid=7 AND jobname='sync-incremental-hourly' AND active FOR UPDATE;
 IF original_cmd IS NULL OR
 length(original_cmd)-length(replace(original_cmd,'''sync_incremental_function_url''',''))<>length('''sync_incremental_function_url''')
 OR original_cmd NOT LIKE '%sync_incremental_service_role%'
 OR original_cmd NOT LIKE '%sync_incremental_cron%'
 THEN RAISE EXCEPTION 'Unexpected original cron job command, refuse to reroute';END IF;
 IF (SELECT status FROM "01_product_schema".export_watermarks
     WHERE job_name='incremental') IS DISTINCT FROM 'ok'
 THEN RAISE EXCEPTION 'Shadow writer watermark is not healthy';END IF;
 IF EXISTS(SELECT 1 FROM public.events p WHERE NOT EXISTS(
    SELECT 1 FROM "01_product_schema".events s WHERE s.insert_id=p.insert_id))
 THEN RAISE EXCEPTION 'New Product schema missing legacy events';END IF;
 IF EXISTS(SELECT 1 FROM vault.secrets WHERE name='product_shadow_canonical_function_url_v1')
 THEN RAISE EXCEPTION 'Target Vault URL name already exists, operator must audit before rerun';END IF;
 PERFORM vault.create_secret(
  'https://hdgbmcerogqfocyxdnpw.supabase.co/functions/v1/sync-incremental-product-shadow',
  'product_shadow_canonical_function_url_v1',
  'Isolated Product writer canonical URL; created only at guarded cutover');
 PERFORM cron.alter_job(7, command := replace(original_cmd,
   '''sync_incremental_function_url''',
   '''product_shadow_canonical_function_url_v1'''));
END $writer$;
COMMIT;
