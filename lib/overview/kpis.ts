/** The published Overview snapshot anchors the event cutoff and source watermark.
 * The actual counts are recomputed from independent accounting-work events.
 * No KPI value falls back to the prototype fixture or sync-inclusive summary.
 */
export interface OverviewUsageSnapshot {
  snapshotId: number;
  asOf: string;
  asOfDate: string;
  sourceWatermarkAt: string;
  wau: { current: number; previous: number };
  mau: { current: number; previous: number };
}

type JsonObject = Record<string, unknown>;

function object(value: unknown): JsonObject | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as JsonObject)
    : null;
}

function count(value: unknown): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0
    ? value
    : null;
}

function usageCount(value: unknown): { current: number; previous: number } | null {
  const data = object(value);
  if (!data) return null;
  const current = count(data.current);
  const previous = count(data.previous);
  return current === null || previous === null ? null : { current, previous };
}

export async function readPublishedOverviewUsage(snapshotId?:number): Promise<OverviewUsageSnapshot | null> {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;

  const response = await fetch(
    url + "/rest/v1/rpc/read_overview_independent_core_kpis_v3",
    {
      method: "POST",
      cache: "no-store",
      signal: AbortSignal.timeout(25_000),
      headers: {
        apikey: key,
        Authorization: "Bearer " + key,
        "Content-Type": "application/json",
        "Cache-Control": "no-cache",
      },
      body: JSON.stringify(snapshotId == null ? {} : {p_snapshot_id:snapshotId}),
    },
  );
  if (!response.ok) {
    throw new Error("overview_independent_core_http_" + response.status);
  }

  const data: unknown = await response.json();
  const snapshot = object(data);
  const wau = usageCount(snapshot?.wau);
  const mau = usageCount(snapshot?.mau);
  const asOf = snapshot?.as_of;
  const watermark = snapshot?.source_watermark_at;
  const snapshotId = count(snapshot?.snapshot_id);

  if (
    snapshot?.contract !== "independent_core_v1" ||
    !wau ||
    !mau ||
    wau.current > mau.current ||
    typeof asOf !== "string" ||
    Number.isNaN(Date.parse(asOf)) ||
    typeof watermark !== "string" ||
    Number.isNaN(Date.parse(watermark)) ||
    snapshotId === null
  ) {
    return null;
  }

  return {
    snapshotId,
    asOf,
    asOfDate: new Intl.DateTimeFormat("sv-SE", {
      timeZone: "Asia/Kolkata",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(new Date(asOf)),
    sourceWatermarkAt: watermark,
    wau,
    mau,
  };
}
