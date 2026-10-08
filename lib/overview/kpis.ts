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

/**
 * The canonical WAU/MAU contract is the current published Overview generation.
 * Never fall back to the legacy demo fixture if the publication is unavailable.
 */
export async function readPublishedOverviewUsage(): Promise<OverviewUsageSnapshot | null> {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) return null;

  const response = await fetch(url + "/rest/v1/rpc/read_product_snapshot", {
    method: "POST",
    cache: "no-store",
    headers: {
      apikey: key,
      Authorization: "Bearer " + key,
      "Content-Type": "application/json",
      "Cache-Control": "no-cache",
    },
    body: JSON.stringify({ p_kind: "overview", p_scope_key: "" }),
  });
  if (!response.ok) {
    throw new Error("overview_kpis_snapshot_http_" + response.status);
  }

  const rows: unknown = await response.json();
  if (!Array.isArray(rows) || rows.length !== 1) return null;

  const row = object(rows[0]);
  const payload = object(row?.payload);
  const value = object(payload?.value);
  const active = object(value?.active_users);
  const wau = usageCount(active?.wau);
  const mau = usageCount(active?.mau);
  const asOf = active?.as_of;
  const watermark = row?.source_watermark_at;
  const snapshotId = count(row?.snapshot_id);

  if (
    row?.source_status !== "ok" ||
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
