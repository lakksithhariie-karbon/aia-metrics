/** Server-only reporting range resolver. Historical Overview values are
 * reconstructed from a frozen, date-specific Supabase snapshot, never from
 * prototype fixtures or the latest snapshot under an earlier label.
 */
export interface OverviewMonthRange {
  from: string;
  to: string;
  preset: string;
}
export interface ResolvedOverviewRange {
  selection: OverviewMonthRange | null;
  snapshotId: number | null;
  historical: boolean;
  unsupported: boolean;
  startMonth: string | null;
}
const MONTH = /^\d{4}-(0[1-9]|1[0-2])$/;

function monthEnd(month: string): string {
  const [year, number] = month.split("-").map(Number);
  return new Date(Date.UTC(year, number, 0)).toISOString().slice(0, 10);
}
function monthNowIST(): string {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone: "Asia/Kolkata", year: "numeric", month: "2-digit",
  }).format(new Date());
}
export function readOverviewRange(params: Record<string, string | string[] | undefined>): OverviewMonthRange | null {
  const from = params.from, to = params.to;
  if (typeof from !== "string" || typeof to !== "string" ||
    !MONTH.test(from) || !MONTH.test(to) ||
    from > to || to > monthNowIST()) return null;
  return {
    from, to,
    preset: typeof params.preset === "string" && ["custom","1","3","6","12"].includes(params.preset) ? params.preset : "custom",
  };
}
export async function resolveOverviewRange(
  range: OverviewMonthRange | null,
): Promise<ResolvedOverviewRange> {
  if (!range) return {
    selection: null, snapshotId: null, historical: false,
    unsupported: false, startMonth: null,
  };
  const to = range.to;
  if (to === monthNowIST()) return {
    selection: range, snapshotId: null, historical: false,
    unsupported: false, startMonth: range.from,
  };
  const historical = true;
  if (to < "2026-03") return {
    selection: range, snapshotId: null, historical,
    unsupported: true, startMonth: range.from,
  };
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("overview_history_not_configured");
  const response = await fetch(url + "/rest/v1/rpc/read_overview_history_id_v1", {
    method: "POST", cache: "no-store", signal: AbortSignal.timeout(15_000),
    headers: {
      apikey: key, Authorization: "Bearer " + key,
      "Content-Type": "application/json", "Cache-Control": "no-store",
    },
    body: JSON.stringify({p_as_of: monthEnd(to)}),
  });
  if (!response.ok) throw new Error("overview_history_rpc_" + response.status);
  const raw: unknown = await response.json();
  const snapshotId = typeof raw === "number" && Number.isSafeInteger(raw) && raw > 0 ? raw : null;
  return {selection: range,snapshotId,historical,
    unsupported: snapshotId === null,startMonth:range.from,
  };
}
