export type OverviewDrillSegment = "wau" | "mau" | "mau_only";
export type OverviewCoreModule = "all" | "ap" | "ar" | "transactions";
export type OverviewCoreCounts = { ap: number; ar: number; transactions: number };

export interface OverviewDrillCompanyRow {
  id: string;
  name: string;
  is_test: boolean;
  actions: number;
  active_days: number;
  last_active_at: string;
  modules: OverviewCoreCounts;
}

export interface OverviewDrillUserRow {
  id: string;
  email: string;
  actions: number;
  active_days: number;
  last_active_at: string;
  modules: OverviewCoreCounts;
  companies: OverviewDrillCompanyRow[];
}

export interface OverviewDrillUsersResponse {
  snapshot_id: number;
  segment: OverviewDrillSegment;
  as_of: string;
  source_watermark_at: string;
  total: number;
  segment_total: number;
  page: number;
  page_size: number;
  rows: OverviewDrillUserRow[];
}

export interface OverviewDrillMember {
  id: string;
  email: string;
  actions: number;
  active_days: number;
  last_active_at: string;
  modules: OverviewCoreCounts;
}
export interface OverviewDrillCompanyDetail {
  snapshot_id: number;
  scope: "wau" | "mau";
  as_of: string;
  source_watermark_at: string;
  focus_user_id: string;
  company: { id: string; name: string; is_test: boolean };
  window: { start: string; end: string; days: number };
  stats: {
    core_actions: number;
    active_users: number;
    active_days: number;
    first_activity_at: string;
    last_activity_at: string;
    modules: OverviewCoreCounts;
  };
  milestones: {
    company_created_at: string | null;
    integration_at: string | null;
    first_independent_activity_at: string | null;
    first_qualifying_sync_at: string | null;
    last_qualifying_sync_at: string | null;
  };
  users: OverviewDrillMember[];
  weeks: Array<{
    week_start: string;
    actions: number;
    active_users: number;
    modules: OverviewCoreCounts;
  }>;
  recent_events: Array<{
    at: string;
    event: string;
    module: "ap" | "ar" | "transactions";
    user_id: string;
    user_email: string;
  }>;
}

function credentials(): { url: string; key: string } {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("supabase_unavailable");
  return { url, key };
}

async function rpc<T>(
  name: string,
  body: Record<string, string | number>,
  signal?: AbortSignal,
): Promise<T | null> {
  const { url, key } = credentials();
  const response = await fetch(url + "/rest/v1/rpc/" + name, {
    method: "POST",
    signal,
    cache: "no-store",
    headers: {
      apikey: key,
      Authorization: "Bearer " + key,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error("overview_drill_rpc_" + response.status);
  const result: unknown = await response.json();
  return (result as T | null) ?? null;
}

export async function readOverviewCoreUsers(params: {
  snapshotId: number;
  segment: OverviewDrillSegment;
  query: string;
  module: OverviewCoreModule;
  page: number;
  pageSize: number;
  signal?: AbortSignal;
}): Promise<OverviewDrillUsersResponse | null> {
  return rpc<OverviewDrillUsersResponse>(
    "read_overview_core_users_v1",
    {
      p_snapshot_id: params.snapshotId,
      p_segment: params.segment,
      p_query: params.query,
      p_module: params.module,
      p_page: params.page,
      p_page_size: params.pageSize,
    },
    params.signal,
  );
}

export async function readOverviewCoreCompany(params: {
  snapshotId: number;
  scope: "wau" | "mau";
  userId: string;
  companyId: string;
  signal?: AbortSignal;
}): Promise<OverviewDrillCompanyDetail | null> {
  return rpc<OverviewDrillCompanyDetail>(
    "read_overview_core_company_v1",
    {
      p_snapshot_id: params.snapshotId,
      p_scope: params.scope,
      p_user_id: params.userId,
      p_company_id: params.companyId,
    },
    params.signal,
  );
}
