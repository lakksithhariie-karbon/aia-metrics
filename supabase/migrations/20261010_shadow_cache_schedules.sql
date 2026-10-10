-- Keep vetted shadow caches ready for validation.
-- Each schedule runs after the existing production cache refresh; production
-- RPC names and current dashboard pointers are not modified.
SELECT cron.schedule(
 'companies-monthly-core-v2-hourly',
 '22 * * * *',
 'SELECT public.refresh_companies_monthly_core_v2();'
);
SELECT cron.schedule(
 'retention-independent-core-v5-watch',
 '7,17,27,37,47,57 * * * *',
 'SELECT public.refresh_retention_dashboard_v4(false);'
);
SELECT cron.schedule(
 'overview-verified-history-daily',
 '0 5 * * *',
 'SELECT public.refresh_overview_history_v1();'
);
