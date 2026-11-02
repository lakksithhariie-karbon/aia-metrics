/** Server-only read facade. No secret or raw database table is exposed to the browser. */
import "server-only";
import type { BillScope } from "./types";
import type { KpiResult, MonthPoint, DocMixSlice, ReviewSlice, LegibilityBucket, CompanyRow, ExceptionCounts } from "./summary";
import type { BillExtractionRecord } from "./types";

export type LiveScope = { from: string; to: string; scopes: BillScope[]; doc: string; status: string; search: string };
export type LiveDashboard = {
  contract: "ai_bill_extraction_live_v1";
  asOf: string | null;
  firstMonth: string | null;
  kpis: KpiResult;
  months: MonthPoint[];
  docs: DocMixSlice[];
  reviews: ReviewSlice[];
  buckets: LegibilityBucket[];
  companies: (CompanyRow & { needsReview: number })[];
  components: { count: number; extraction: number; enrichment: number };
  exceptions: ExceptionCounts;
  analytics: LiveAnalytics;
};

export type LiveAnalyticsRow = {
  label: string; predictions: number; knownCost: number;
  knownCostCount: number; unknownCostCount: number;
  medianLatency: number | null; p95Latency: number | null; knownLatencyCount: number;
};
export type LiveAnalytics = {
  contract: "ai_bill_analytics_v1";
  /** The source currently does not verify whether costs are in USD. */
  currency: "unverified" | "USD";
  periodDays: number;
  selected: {
    predictions: number; dailyAverage: number | null;
    reviewedCount: number; reviewedCost: number; reviewedKnown: number; reviewedUnknown: number;
    nonDeletedCost: number; nonDeletedKnown: number; nonDeletedUnknown: number;
    deletedCount: number; deletedCost: number; deletedKnown: number; deletedUnknown: number;
  };
  mtd: { month: string; predictions: number; knownCost: number; knownCount: number; unknownCount: number };
  daily: Array<{ day: string; predictions: number }>;
  docAnalytics: LiveAnalyticsRow[];
  pageAnalytics: LiveAnalyticsRow[];
};
export type LiveEvidence = {
  contract: "ai_bill_extraction_records_v1";
  total: number;
  knownCostCount: number;
  rows: BillExtractionRecord[];
};

const month = (v: unknown): v is string => typeof v === "string" && /^20\d{2}-(0[1-9]|1[0-2])$/.test(v);
const word = (v: unknown, permitted: readonly string[]) => typeof v === "string" && permitted.includes(v);
export function validateScope(input: unknown): LiveScope {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("bill_invalid_scope");
  const q = input as Record<string,unknown>;
  const scopes = q.scopes;
  if (!month(q.from) || !month(q.to) || q.from > q.to ||
      !Array.isArray(scopes) || scopes.length < 1 || scopes.length > 3 ||
      scopes.some(v => !word(v,["verified_customer","test_company","unverified_company"])) ||
      !word(q.doc,["all","scanned","digital","handwritten","unknown"]) ||
      !word(q.status,["all","reviewed","needs_review","deleted","unknown"]) ||
      typeof q.search !== "string" || q.search.length > 100) throw new Error("bill_invalid_scope");
  return q as unknown as LiveScope;
}

export function ensureBillReportingAccess() {
  // Production must be protected by Vercel Authentication with Deployment
  // Protection scope "All Deployments", and explicitly enabled separately.
  // A Vercel project setting change is NOT sufficient to enable the reader.
  // If protection is ever disabled, immediately disable this production flag.
  if (process.env.VERCEL_ENV === "production" &&
      process.env.AI_BILL_REPORTING_PRODUCTION_ENABLED !== "true") {
    throw new Error("bill_reporting_production_disabled");
  }
}

async function rpc<T>(action: "dashboard" | "records", scope: LiveScope, params: Record<string,unknown> = {}, fn = "read_ai_bill_extraction_v1"): Promise<T> {
  ensureBillReportingAccess();
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("bill_reporting_credentials_missing");
  const response = await fetch(url.replace(/\/+$/, "") + "/rest/v1/rpc/" + fn, {
    method: "POST", cache: "no-store", signal: AbortSignal.timeout(27000),
    headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json", "Cache-Control": "no-store" },
    body: JSON.stringify({
      p_action: action, p_from: scope.from + "-01", p_to: scope.to + "-01",
      p_scopes: scope.scopes, p_doc: scope.doc, p_status: scope.status, p_search: scope.search,
      ...params,
    }),
  });
  if (!response.ok) throw new Error("bill_reporting_rpc_http_" + response.status);
  return await response.json() as T;
}
const nonNegativeInt = (v: unknown) => typeof v === "number" && Number.isSafeInteger(v) && v >= 0;

export async function readBillDashboard(scope: LiveScope): Promise<LiveDashboard> {
  const [value, analytics] = await Promise.all([
    rpc<LiveDashboard>("dashboard",scope),
    rpc<LiveAnalytics>("dashboard",scope,{}, "read_ai_bill_analytics_v1"),
  ]);
  if (!value || value.contract !== "ai_bill_extraction_live_v1" ||
    !nonNegativeInt(value.kpis?.bills) || !nonNegativeInt(value.kpis?.knownCostCount) ||
    !nonNegativeInt(value.kpis?.unknownCostCount) ||
    value.kpis.knownCostCount + value.kpis.unknownCostCount !== value.kpis.bills ||
    !Array.isArray(value.months) || !Array.isArray(value.docs) ||
    !Array.isArray(value.reviews) || !Array.isArray(value.companies) ||
    !Array.isArray(value.buckets) ||
    value.months.reduce((s,r)=>s+r.bills,0)!==value.kpis.bills ||
    value.docs.reduce((s,r)=>s+r.bills,0)!==value.kpis.bills ||
    value.reviews.reduce((s,r)=>s+r.bills,0)!==value.kpis.bills ||
    value.companies.reduce((s,r)=>s+r.bills,0)!==value.kpis.bills ||
    !value.exceptions || value.exceptions.missingCost!==value.kpis.unknownCostCount) {
    throw new Error("bill_reporting_dashboard_contract_invalid");
  }
  if (analytics?.contract !== "ai_bill_analytics_v1" ||
      !["unverified","USD"].includes(analytics.currency) ||
      !nonNegativeInt(analytics.periodDays) ||
      analytics.selected?.predictions !== value.kpis.bills ||
      !Array.isArray(analytics.docAnalytics) || !Array.isArray(analytics.pageAnalytics) ||
      !Array.isArray(analytics.daily) || analytics.daily.length > 31 ||
      analytics.docAnalytics.reduce((s,r)=>s+r.predictions,0) !== value.kpis.bills ||
      analytics.pageAnalytics.reduce((s,r)=>s+r.predictions,0) !== value.kpis.bills ||
      analytics.docAnalytics.reduce((s,r)=>s+r.knownCostCount,0) !== value.kpis.knownCostCount ||
      analytics.pageAnalytics.reduce((s,r)=>s+r.knownCostCount,0) !== value.kpis.knownCostCount ||
      !nonNegativeInt(analytics.mtd?.predictions) ||
      analytics.mtd.knownCount + analytics.mtd.unknownCount !== analytics.mtd.predictions) {
    throw new Error("bill_analytics_contract_invalid");
  }
  return {...value, analytics};
}

export async function readBillEvidence(scope: LiveScope, input: Record<string,unknown>): Promise<LiveEvidence> {
  const drill = input.drill, value = input.value, sort = input.sort, direction = input.direction, offset = input.offset;
  const allowed = ["all","known_cost","known_latency","needs_review","month","month_cost","month_latency","components","doc_type","review_status","legibility","company","missing_cost","missing_latency","missing_pages","missing_doc","missing_legibility","partial_breakdown","page_band","day"];
  if (!word(drill,allowed) || typeof value !== "string" || value.length>90 ||
    !word(sort,["createdAt","knownTotalCost","knownTotalLatency"]) ||
    !word(direction,["asc","desc"]) || !nonNegativeInt(offset) || (offset as number)>100000) {
    throw new Error("bill_reporting_invalid_evidence_request");
  }
  const analyticsDrill = drill === "page_band" || drill === "day";
  const result = await rpc<LiveEvidence>("records",scope,{
    p_drill:drill,p_value:value,p_sort:sort,p_direction:direction,p_offset:offset,p_limit:10,
  }, analyticsDrill ? "read_ai_bill_analytics_v1" : "read_ai_bill_extraction_v1");
  if (result?.contract!=="ai_bill_extraction_records_v1" ||
    !nonNegativeInt(result.total) || !nonNegativeInt(result.knownCostCount) ||
    result.knownCostCount>result.total || !Array.isArray(result.rows) || result.rows.length>10 ||
    result.rows.length!==Math.max(0,Math.min(10,result.total-(offset as number))) ||
    result.rows.some(row=>!row.predictionUuid||!row.companyUuid||!row.createdAt)) {
    throw new Error("bill_reporting_evidence_contract_invalid");
  }
  return result;
}
