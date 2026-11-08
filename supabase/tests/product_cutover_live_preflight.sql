-- READ-ONLY, repeatable Product pre-cutover environment gate.
-- All *_ok columns must be TRUE, but success here does NOT authorize cutover.
-- Run payload parity SQL suites, signed Edge canary, and application smoke
-- tests separately. This gate checks DB security, freshness and cron status.
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
  FROM jobs WHERE jobid=48) shadow_daily_full_ok
FROM data_counts CROSS JOIN inventory CROSS JOIN bridges;
