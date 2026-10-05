/**
 * Server-only Companies lifecycle data plane.
 *
 * The main table reads a private, pre-aggregated post-integration cache.
 * W1-W4 are anchored to each company's FIRST successful integration.
 * Browser code never receives Supabase credentials or raw event access.
 */
import {
  type CompanyUsageResponse,
  type ModuleBreakdownResponse,
  type SortDirection,
  type SortKey,
  type UsageFilter,
  type UsageWeek,
  type WeekModuleKey,
} from "./types";

const UNATTRIBUTED_ID = "__unattributed__";
const UNATTRIBUTED_LABEL = "Unattributed activity";

const text = (value: unknown): string =>
  typeof value === "string" ? value.trim() : "";

function credentials(): { url: string; key: string } {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("supabase_unavailable");
  return { url, key };
}

async function rest<T>(path: string, init?: RequestInit, signal?: AbortSignal): Promise<T> {
  const { url, key } = credentials();
  const response = await fetch(`${url}/rest/v1${path}`, {
    ...init,
    cache: "no-store",
    signal,
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      "Cache-Control": "no-cache",
      Pragma: "no-cache",
      ...(init?.headers ?? {}),
    },
  });
  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    const server = response.headers.get("server") ?? "";
    const ray = response.headers.get("cf-ray") ?? response.headers.get("x-vercel-id") ?? "";
    throw new Error(
      `supabase_${response.status}:${path.slice(0, 70)}:srv=${server}:ray=${ray}:body=${detail.slice(0, 120)}`,
    );
  }
  return (await response.json()) as T;
}

async function rpc<T>(
  fn: string,
  params: Record<string, unknown>,
  signal?: AbortSignal,
  limit = 1000,
): Promise<T> {
  return rest<T>(
    `/rpc/${fn}?limit=${limit}`,
    { method: "POST", body: JSON.stringify(params) },
    signal,
  );
}

function scalar<T>(value: T | T[]): T {
  if (Array.isArray(value)) {
    if (!value.length) throw new Error("supabase_empty_scalar");
    return value[0] as T;
  }
  return value;
}

export interface ListParams {
  signal?: AbortSignal;
  page: number;
  query: string;
  integration: string;
  usage: UsageFilter;
  sort: SortKey;
  direction: SortDirection;
  from: string | null;
  to: string | null;
}

export async function listCompanies(params: ListParams): Promise<CompanyUsageResponse> {
  const payload = await rpc<CompanyUsageResponse | CompanyUsageResponse[]>(
    "read_companies_lifecycle_page",
    {
      p_from: params.from,
      p_to: params.to,
      p_query: params.query,
      p_usage: params.usage,
      p_integration: params.integration,
      p_sort: params.sort,
      p_direction: params.direction,
      p_page: 1,
      p_page_size: 5000,
    },
    params.signal,
  );
  return scalar(payload);
}

export interface BreakdownParams {
  signal?: AbortSignal;
  company_id: string;
  user_id: string | null;
  module: WeekModuleKey;
  week: UsageWeek;
}

export async function companyBreakdown(
  params: BreakdownParams,
): Promise<ModuleBreakdownResponse> {
  const userKey =
    params.user_id == null
      ? null
      : params.user_id === UNATTRIBUTED_ID
        ? ""
        : params.user_id;

  const [grouped, identityPayload] = await Promise.all([
    rpc<
      Array<{
        event: string;
        subtype: string | null;
        status: string | null;
        events: number;
        items: number | null;
        instrumented: number;
        latest_at: string | null;
        window_start: string | null;
        window_end: string | null;
      }>
    >(
      "read_companies_lifecycle_breakdown",
      {
        p_company_id: params.company_id,
        p_module: params.module,
        p_user_key: userKey,
        p_usage_week: params.week,
      },
      params.signal,
    ),
    rpc<
      | {
          company_name: string | null;
          integration_at: string | null;
          user_label: string | null;
        }
      | Array<{
          company_name: string | null;
          integration_at: string | null;
          user_label: string | null;
        }>
    >(
      "read_companies_lifecycle_identity",
      {
        p_company_id: params.company_id,
        p_user_key:
          params.user_id === UNATTRIBUTED_ID ? UNATTRIBUTED_ID : params.user_id,
      },
      params.signal,
    ),
  ]);

  const identity = scalar(identityPayload);
  const rows = grouped
    .map(row => ({
      event: text(row.event),
      subtype: text(row.subtype) || null,
      status: text(row.status) || null,
      count: Number(row.events) || 0,
      items: Number(row.instrumented) > 0 ? Number(row.items) || 0 : null,
      latest_at: row.latest_at ?? null,
    }))
    .sort((a, b) => b.count - a.count || a.event.localeCompare(b.event));

  const total = rows.reduce((sum, row) => sum + row.count, 0);
  const instrumented = rows.filter(row => row.items != null);
  const integrationAt = identity.integration_at ? Date.parse(identity.integration_at) : Number.NaN;
  const fallbackWindowStart = Number.isNaN(integrationAt)
    ? null
    : new Date(integrationAt + (params.week - 1) * 7 * 86_400_000).toISOString();
  const fallbackWindowEnd = Number.isNaN(integrationAt)
    ? null
    : new Date(integrationAt + params.week * 7 * 86_400_000).toISOString();
  const windowStart = grouped[0]?.window_start ?? fallbackWindowStart;
  const windowEnd = grouped[0]?.window_end ?? fallbackWindowEnd;

  return {
    company_id: params.company_id,
    company_name: text(identity.company_name) || params.company_id,
    user_id: params.user_id,
    user_label:
      params.user_id == null
        ? null
        : params.user_id === UNATTRIBUTED_ID
          ? UNATTRIBUTED_LABEL
          : text(identity.user_label) || params.user_id,
    module: params.module,
    week: params.week,
    window_start: windowStart,
    window_end: windowEnd,
    total,
    item_total: instrumented.length
      ? instrumented.reduce((sum, row) => sum + (row.items ?? 0), 0)
      : null,
    rows,
  };
}
