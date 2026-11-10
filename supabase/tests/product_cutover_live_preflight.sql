-- READ-ONLY, repeatable Product pre-cutover environment gate.
-- All *_ok columns must be TRUE, but success here does NOT authorize cutover.
-- Run payload parity SQL suites, signed Edge canary, and application smoke
-- tests separately. This gate checks DB security, raw ingestion, published
-- snapshot freshness (24h maximum lag), and cron status. Page manifests
-- are reported separately because consumers may still use per-kind pointers.
-- Overview live freshness and Retention v5 live cache freshness are reported
-- separately from the stricter nine-kind archive/snapshot-completeness gate.
-- This query does not replace app/HTTP smoke tests or publication builder.
WITH data_counts AS (
 SELECT (SELECT count(*) FROM public.events) source_events,
        (SELECT count(*) FROM "01_product_schema".events) shadow_events,
        (SELECT max(ingested_at) FROM public.events) source_latest,
        (SELECT max(ingested_at) FROM "01_product_schema".events) shadow_latest
), inventory AS (
 SELECT (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
         WHERE n.nspname='01_product_schema' AND c.relkind='r') shadow_tables,
        (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
         WHERE n.nspname='01_product_schema' AND c.relkind='r' AND c.relrowsecurity) shadow_rls,
        (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='01_product_schema' AND p.proname LIKE 'read_%') private_readers,
        (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
         WHERE n.nspname='public' AND p.proname LIKE 'read_%'
           AND p.proname NOT LIKE 'read_jira_%' AND p.proname NOT LIKE 'read_ai_%'
           AND p.proname NOT LIKE 'read_infra_%' AND p.proname NOT LIKE 'read_product_shadow_%') legacy_readers
), bridges AS (
 SELECT count(*) count,
        bool_and(has_function_privilege('service_role',p.oid,'EXECUTE')
           AND NOT has_function_privilege('anon',p.oid,'EXECUTE')
           AND NOT has_function_privilege('authenticated',p.oid,'EXECUTE')) least_privilege_ok
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public'
    AND (p.proname LIKE 'shadow_product_%' OR p.proname LIKE 'read_product_shadow_%')
), jobs AS (
 SELECT j.jobid,j.active,r.status,r.start_time
 FROM cron.job j LEFT JOIN LATERAL (
   SELECT status,start_time FROM cron.job_run_details x
   WHERE x.jobid=j.jobid ORDER BY start_time DESC LIMIT 1
 ) r ON true
 WHERE j.jobid IN(7,47,48)
), reporting AS (
  SELECT count(*) AS required_kinds,
         count(s.id) AS current_kinds,
         count(*)=9 AND count(s.id)=9 AND
           coalesce(bool_and(s.source_status='ok'
             AND w.status='ok'
             AND s.source_watermark_at >= w.last_success_at - interval '24 hours'
             AND s.source_watermark_at <= w.last_success_at),false)
             AS report_snapshot_fresh_24h_ok
  FROM (VALUES ('overview'),('overview-funnel'),('overview-feature-usage'),
        ('overview-module-mix'),('overview-friction'),('retention-summary'),
        ('retention-heatmap'),('retention-monthly'),('churn-trend')) required(kind)
  LEFT JOIN public.product_snapshot_current c ON c.kind=required.kind AND c.scope_key=''
  LEFT JOIN public.product_snapshot s ON s.id=c.snapshot_id
  LEFT JOIN public.export_watermarks w ON w.job_name='incremental'
)
SELECT now() checked_at,
 data_counts.source_events,data_counts.shadow_events,
 (source_events=shadow_events AND source_latest IS NOT DISTINCT FROM shadow_latest) events_parity_ok,
 (inventory.shadow_tables=58 AND inventory.shadow_rls=58) private_rls_ok,
 (inventory.private_readers=106 AND inventory.legacy_readers=105) reader_inventory_ok,
 (bridges.count=11 AND bridges.least_privilege_ok) bridge_permissions_ok,
 (SELECT active AND status='succeeded' AND start_time > now()-interval '90 minutes'
  FROM jobs WHERE jobid=7) production_hourly_ok,
 (SELECT active AND status='succeeded' AND start_time > now()-interval '45 minutes'
  FROM jobs WHERE jobid=47) shadow_halfhourly_ok,
 (SELECT active AND status='succeeded' AND start_time > now()-interval '36 hours'
  FROM jobs WHERE jobid=48) shadow_daily_full_ok,
 reporting.required_kinds, reporting.current_kinds,
 reporting.report_snapshot_fresh_24h_ok,
 (SELECT count(*)=5 AND count(s.id)=5 AND
     coalesce(bool_and(s.source_status='ok' AND w.status='ok'
       AND s.source_watermark_at >= w.last_success_at - interval '24 hours'
       AND s.source_watermark_at <= w.last_success_at),false)
  FROM (VALUES ('overview'),('overview-funnel'),('overview-feature-usage'),
    ('overview-module-mix'),('overview-friction')) live(kind)
  LEFT JOIN public.product_snapshot_current c ON c.kind=live.kind AND c.scope_key=''
  LEFT JOIN public.product_snapshot s ON s.id=c.snapshot_id
  LEFT JOIN public.export_watermarks w ON w.job_name='incremental')
    AS overview_live_fresh_24h_ok,
 (SELECT w.status='ok' AND m.source_watermark_at IS NOT NULL
    AND m.source_watermark_at >= w.last_success_at - interval '24 hours'
    AND m.source_watermark_at <= w.last_success_at
    AND m.refreshed_at >= now()-interval '24 hours'
  FROM metrics_private.retention_dashboard_meta_v4 m
  JOIN public.export_watermarks w ON w.job_name='incremental'
  WHERE m.singleton) AS retention_v5_live_fresh_24h_ok,
 (SELECT count(*) FROM public.product_publication_current) AS page_manifests_present
FROM data_counts CROSS JOIN inventory CROSS JOIN bridges CROSS JOIN reporting;
