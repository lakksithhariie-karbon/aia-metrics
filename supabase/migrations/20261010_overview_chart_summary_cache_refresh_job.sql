-- Stagger chart-summary warming two minutes after the KPI cache refresh.
-- Only mismatched snapshot IDs/watermarks are recomputed, in small batches.
SELECT cron.schedule(
  'overview-chart-summary-cache-watch',
  '2,7,12,17,22,27,32,37,42,47,52,57 * * * *',
  'SELECT metrics_private.refresh_overview_chart_summary_cache_v1(4);'
);
