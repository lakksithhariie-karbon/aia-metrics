-- Keep independently verified Overview KPI snapshots warm, without changing
-- any existing production refresh job or reader. The function does no event
-- work unless the snapshot ID, source watermark, or as-of cutoff has changed.
-- Historical snapshots are refreshed in place by the 05:00 UTC job.
SELECT cron.schedule(
  'overview-independent-core-cache-watch',
  '*/5 * * * *',
  'SELECT metrics_private.refresh_overview_independent_core_kpi_cache_v1(20);'
);
