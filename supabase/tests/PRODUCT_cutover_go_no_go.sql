-- Read-only, repeatable production routing gate.
-- This is DB readiness only, not operator approval, HTTP test, dependency
-- owner sign-off or completed 48-72h observation. Never execute switch SQL
-- merely because this query returns true.
BEGIN READ ONLY;
SET LOCAL statement_timeout='60s';
WITH
w AS (SELECT status,last_success_at AS source_at FROM public.export_watermarks WHERE job_name='incremental'),
events AS (SELECT (SELECT count(*) FROM public.events) old_n,
 (SELECT count(*) FROM "01_product_schema".events) new_n),
kinds AS (SELECT unnest(ARRAY['overview','overview-funnel','overview-feature-usage','overview-module-mix','overview-friction']) kind),
current AS (
 SELECT k.kind,a.id old_id,b.id new_id,
 a.source_status old_status,b.source_status new_status,
 a.source_watermark_at old_wm,b.source_watermark_at new_wm,
 a.n_events old_n,b.n_events new_n,
 CASE WHEN k.kind='overview-funnel'
 THEN EXISTS(SELECT 1 FROM public.product_funnel_seal z WHERE z.snapshot_id=a.id)
 ELSE EXISTS(SELECT 1 FROM public.product_overview_seal z WHERE z.snapshot_id=a.id)
 END old_sealed,
 CASE WHEN k.kind='overview-funnel'
 THEN EXISTS(SELECT 1 FROM "01_product_schema".product_funnel_seal z WHERE z.snapshot_id=b.id)
 ELSE EXISTS(SELECT 1 FROM "01_product_schema".product_overview_seal z WHERE z.snapshot_id=b.id)
 END new_sealed
 FROM kinds k
 LEFT JOIN public.product_snapshot_current x ON x.kind=k.kind AND x.scope_key=''
 LEFT JOIN public.product_snapshot a ON a.id=x.snapshot_id
 LEFT JOIN "01_product_schema".product_snapshot_current y ON y.kind=k.kind AND y.scope_key=''
 LEFT JOIN "01_product_schema".product_snapshot b ON b.id=y.snapshot_id
), overview AS (
 SELECT count(old_id)=5 AS public_complete,count(new_id)=5 AS private_complete,
 coalesce(bool_and(old_sealed AND new_sealed),false) AS all_sealed,
 coalesce(bool_and(old_status='ok' AND new_status='ok' AND old_wm=new_wm AND old_n=new_n),false) AS source_matches,
 count(DISTINCT old_wm)=1 AND count(DISTINCT new_wm)=1 AND
 count(DISTINCT old_n)=1 AND count(DISTINCT new_n)=1 AS uniform_source,
 coalesce(bool_and(old_wm>=w.source_at-interval '24 hours' AND
 new_wm>=w.source_at-interval '24 hours' AND
 old_wm<=w.source_at AND new_wm<=w.source_at),false) AS fresh_24h
 FROM current CROSS JOIN w
), legacy_manifest AS (
 SELECT count(DISTINCT m.kind)=5 AS ok
 FROM public.product_publication_current pc
 JOIN public.product_publication p ON p.publication_id=pc.publication_id AND p.page='overview'
 JOIN public.product_publication_member m ON m.publication_id=p.publication_id
 JOIN current c ON c.kind=m.kind AND c.old_id=m.snapshot_id
 CROSS JOIN w,events
 WHERE pc.page='overview' AND p.source_watermark_at=w.source_at
 AND p.n_events=events.old_n AND m.scope_key=''
), private_manifest AS (
 SELECT count(DISTINCT m.kind)=5 AS ok
 FROM "01_product_schema".product_publication_current pc
 JOIN "01_product_schema".product_publication p ON p.publication_id=pc.publication_id AND p.page='overview'
 JOIN "01_product_schema".product_publication_member m ON m.publication_id=p.publication_id
 JOIN current c ON c.kind=m.kind AND c.new_id=m.snapshot_id
 CROSS JOIN w,events
 WHERE pc.page='overview' AND p.source_watermark_at=w.source_at
 AND p.n_events=events.new_n AND m.scope_key=''
), inventory AS (
 SELECT (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='01_product_schema' AND p.proname LIKE 'read_%')=106 AS private_readers_ok,
 (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname='01_product_schema' AND c.relkind='r' AND c.relrowsecurity)=58 AS private_rls_ok,
 (SELECT count(*) FROM cron.job j WHERE j.jobid IN (7,29,39,40,41,42,45,46,47,48)
 AND j.active AND (SELECT status FROM cron.job_run_details d
 WHERE d.jobid=j.jobid ORDER BY start_time DESC LIMIT 1)='succeeded')=10 AS current_jobs_ok
)
SELECT now() checked_at,w.source_at ingested_at,events.old_n public_events,events.new_n private_events,
 (w.status='ok') AS source_ingestion_ok,(events.old_n=events.new_n) AS events_count_match,
 overview.public_complete,overview.private_complete,overview.all_sealed,
 overview.source_matches,overview.uniform_source,overview.fresh_24h AS overview_fresh_24h,
 legacy_manifest.ok AS public_page_manifest_ok,private_manifest.ok AS private_page_manifest_ok,
 (SELECT m.source_watermark_at>=w.source_at-interval '24 hours'
   AND m.source_watermark_at<=w.source_at AND m.refreshed_at>=now()-interval '24 hours'
 FROM metrics_private.retention_dashboard_meta_v4 m WHERE m.singleton) AS retention_v5_fresh,
 inventory.private_readers_ok,inventory.private_rls_ok,inventory.current_jobs_ok,
 (w.status='ok' AND events.old_n=events.new_n AND overview.public_complete AND
 overview.private_complete AND overview.all_sealed AND overview.source_matches AND
 overview.uniform_source AND overview.fresh_24h AND legacy_manifest.ok AND private_manifest.ok AND
 inventory.private_readers_ok AND inventory.private_rls_ok AND inventory.current_jobs_ok AND
 (SELECT m.source_watermark_at>=w.source_at-interval '24 hours'
   AND m.refreshed_at>=now()-interval '24 hours'
 FROM metrics_private.retention_dashboard_meta_v4 m WHERE m.singleton)
 ) AS automated_database_go
FROM w CROSS JOIN events CROSS JOIN overview CROSS JOIN legacy_manifest CROSS JOIN private_manifest CROSS JOIN inventory;
ROLLBACK;
