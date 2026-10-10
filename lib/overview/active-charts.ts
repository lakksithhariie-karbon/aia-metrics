/** Server-only, read-only adapter for the two Active Usage charts.
 * Returns published-generation-aligned results. No fixture fallback.
 */
export interface ActiveWeeklyRow {
  week_start: string;
  users: number;
  first_observed: number;
  returning: number;
  limited_tracking: boolean;
}
export interface ActiveFrequencyRow {
  active_weeks: number;
  users: number;
  share_pct: number;
}
export interface OverviewActiveCharts {
  snapshotId: number;
  asOf: string;
  sourceWatermarkAt: string;
  currentIncompleteWeek: string;
  qualityNotice: string;
  weekly: { rows: ActiveWeeklyRow[] };
  frequency: {
    window_start: string;
    window_end: string;
    total_users: number;
    rows: ActiveFrequencyRow[];
  };
}
function obj(v: unknown): Record<string, unknown> | null {
  return v !== null && typeof v === "object" && !Array.isArray(v)
    ? v as Record<string, unknown> : null;
}
function natural(v: unknown): v is number {
  return typeof v === "number" && Number.isSafeInteger(v) && v >= 0;
}
function dateOnly(v: unknown): v is string {
  return typeof v === "string" && /^\d{4}-\d{2}-\d{2}$/.test(v);
}

export async function readPublishedOverviewActiveCharts(snapshotId?:number): Promise<OverviewActiveCharts | null> {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;
  const response = await fetch(url + "/rest/v1/rpc/read_overview_active_charts_v4", {
    method: "POST", cache: "no-store", signal: AbortSignal.timeout(25_000),
    headers: {
      apikey: key, Authorization: "Bearer " + key,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
    body: JSON.stringify(snapshotId == null ? {} : {p_snapshot_id:snapshotId}),
  });
  if (!response.ok) throw new Error("overview_charts_http_" + response.status);
  const result = obj(await response.json());
  const weekly = obj(result?.weekly);
  const frequency = obj(result?.frequency);
  const weeklyRows = weekly?.rows;
  const frequencyRows = frequency?.rows;
  if (!result || !frequency || result.contract !== "independent_core_active_charts_v1"
    || !natural(result.snapshot_id)
    || typeof result.as_of !== "string" || Number.isNaN(Date.parse(result.as_of))
    || typeof result.source_watermark_at !== "string"
    || !dateOnly(result.current_incomplete_week)
    || !Array.isArray(weeklyRows) || weeklyRows.length !== 12
    || !Array.isArray(frequencyRows) || frequencyRows.length !== 4
    || !natural(frequency.total_users)
    || !dateOnly(frequency.window_start) || !dateOnly(frequency.window_end)) return null;

  const weeks: ActiveWeeklyRow[] = [];
  const buckets: ActiveFrequencyRow[] = [];
  for (const entry of weeklyRows) {
    const r = obj(entry);
    if (!r || !dateOnly(r.week_start)
      || !natural(r.users) || !natural(r.returning) || !natural(r.first_observed)
      || r.users !== r.returning + r.first_observed
      || typeof r.limited_tracking !== "boolean") return null;
    weeks.push({
      week_start: r.week_start, users: r.users,
      returning: r.returning, first_observed: r.first_observed,
      limited_tracking: r.limited_tracking,
    });
  }
  for (let index = 0; index < frequencyRows.length; index++) {
    const r = obj(frequencyRows[index]);
    if (!r || r.active_weeks !== index + 1 || !natural(r.users)
      || typeof r.share_pct !== "number") return null;
    buckets.push({ active_weeks: r.active_weeks, users: r.users, share_pct: r.share_pct });
  }
  if (buckets.reduce((n, b) => n + b.users, 0) !== frequency.total_users) return null;

  return {
    snapshotId: result.snapshot_id,
    asOf: result.as_of,
    sourceWatermarkAt: result.source_watermark_at,
    currentIncompleteWeek: result.current_incomplete_week,
    qualityNotice: typeof result.quality_notice === "string" ? result.quality_notice : "",
    weekly: { rows: weeks },
    frequency: {
      window_start: frequency.window_start,
      window_end: frequency.window_end,
      total_users: frequency.total_users,
      rows: buckets,
    },
  };
}
