import type { DeliveryDashboard, DeliveryEvidence, DeliveryFilters } from "./types";

/**
 * The same Vercel server-only environment used by Product Metrics.
 * Jira's schema is not exposed to the browser; only two audited public RPC
 * facades can be called, with EXECUTE restricted to service_role.
 */
const credentials = () => {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("jira_delivery_server_credentials_missing");
  return { url: url.replace(/\/+$/, ""), key };
};

async function rpc<T>(name: string, body: Record<string, unknown>): Promise<T> {
  const { url, key } = credentials();
  const response = await fetch(url + "/rest/v1/rpc/" + name, {
    method: "POST", cache: "no-store", signal: AbortSignal.timeout(29_000),
    headers: {
      apikey: key, Authorization: "Bearer " + key,
      "Content-Type": "application/json", "Cache-Control": "no-store",
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error("jira_delivery_" + name + "_http_" + response.status);
  const value: unknown = await response.json();
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("jira_delivery_bad_rpc_payload");
  }
  return value as T;
}

const scalar = (x: unknown): x is number =>
  typeof x === "number" && Number.isFinite(x) && x >= 0;
const count = (x: unknown): x is number => scalar(x) && Number.isSafeInteger(x);

const same = (x: unknown, y: unknown): boolean => count(x) && count(y) && x === y;

function validate(payload: DeliveryDashboard): DeliveryDashboard {
  if (payload.contract !== "jira_delivery_dashboard_v1" ||
      !count(payload.snapshot_id) ||
      !same(payload.snapshot_id, payload.latest_clean_sync_id) ||
      !Number.isFinite(Date.parse(payload.synced_at)) ||
      !Number.isFinite(Date.parse(payload.refreshed_at)) ||
      !Array.isArray(payload.core?.sprint_discipline) ||
      !Array.isArray(payload.options?.sprints) ||
      !Array.isArray(payload.issue_types) ||
      !Array.isArray(payload.flow?.wip_by_status) ||
      !Array.isArray(payload.flow?.stage_summary) ||
      !Array.isArray(payload.quality?.org_reopen)) {
    throw new Error("jira_delivery_contract_invalid");
  }
  const cohort = payload.core.metric_cohorts;
  const fc = payload.flow.flow_counts;
  const bh = payload.flow.bug_health;
  const check = (key: string, expected: unknown) => same(cohort?.[key]?.n, expected);
  if (!check("wip_open",fc.open_total) ||
      !check("open_bugs",bh.open_bugs) ||
      !check("stale_7d",fc.stale_all) ||
      !check("stale_blocked",fc.stale_blocked) ||
      !check("blocked",fc.blocked_all) ||
      !check("qa_queue",fc.qa_queue_count) ||
      payload.flow.wip_by_status.reduce((s,r)=>s+r.issue_count,0)!==fc.open_total) {
    throw new Error("jira_delivery_reconciliation_failed");
  }
  for (const sprint of payload.core.sprint_discipline) {
    if (!count(sprint.sprint_id)||!count(sprint.scope_now)||
        !count(sprint.done_now)||!count(sprint.committed)||
        !count(sprint.committed_done)||!count(sprint.added_mid_sprint)||
        sprint.done_now>sprint.scope_now ||
        sprint.committed_done>sprint.committed ||
        sprint.committed+sprint.added_mid_sprint!==sprint.scope_now ||
        (sprint.scope_completion_pct!==null &&
          Math.abs(sprint.done_now/Math.max(1,sprint.scope_now)*100-sprint.scope_completion_pct)>0.11)) {
      throw new Error("jira_delivery_sprint_reconciliation_failed");
    }
    const types=payload.issue_types
      .filter(t=>t.sprint_id===sprint.sprint_id)
      .reduce((sum,t)=>sum+t.count,0);
    if(types!==sprint.scope_now)throw new Error("jira_delivery_issue_types_reconciliation_failed");
  }
  if(payload.flow.bug_health.age_histogram
      .reduce((s,row)=>s+row.count,0)!==bh.open_bugs){
    throw new Error("jira_delivery_bug_aging_reconciliation_failed");
  }
  return payload;
}
export function parseDeliveryFilters(
  raw: Record<string, string | string[] | undefined>,
): DeliveryFilters {
  const one = (key: string): string | null => {
    const v = raw[key];
    const s = typeof v === "string" ? v : Array.isArray(v) ? v[0] : null;
    if (!s) return null;
    if (s.length > 160) throw new Error("jira_delivery_invalid_filter");
    return s;
  };
  const sprint = one("sprint");
  if (sprint && !/^[1-9][0-9]{0,11}$/.test(sprint)){
    throw new Error("jira_delivery_invalid_sprint");
  }
  return {
    sprint: sprint ? Number(sprint) : null,
    module: one("module"),
    sub_module: one("sub_module"),
    severity: one("severity"),
    assignee: one("assignee"),
  };
}
function args(filters: DeliveryFilters): Record<string, unknown> {
  return {
    p_sprint_id: filters.sprint,
    p_modules: filters.module ? [filters.module] : null,
    p_sub_modules: filters.sub_module ? [filters.sub_module] : null,
    p_severities: filters.severity ? [filters.severity] : null,
    p_assignees: filters.assignee ? [filters.assignee] : null,
  };
}

export async function readDeliveryDashboard(filters: DeliveryFilters): Promise<DeliveryDashboard> {
  return validate(await rpc<DeliveryDashboard>("read_jira_delivery_dashboard_v1",args(filters)));
}

export async function readDeliveryEvidence(
  filters: DeliveryFilters,
  key: string,
  snapshotId: number,
  offset: number,
  limit=40,
): Promise<DeliveryEvidence> {
  if (!count(snapshotId)||key.length>90 || !key.trim() ||
      !count(offset)||offset>25000||!count(limit)||limit<1||limit>50) {
    throw new Error("jira_delivery_evidence_invalid_request");
  }
  const value=await rpc<DeliveryEvidence>("read_jira_delivery_evidence_v1",{
    ...args(filters), p_key:key, p_snapshot_id:snapshotId,
    p_offset:offset,p_limit:limit,
  });
  if(value.contract!=="jira_delivery_evidence_v1" ||
     value.key!==key || value.snapshot_id!==snapshotId ||
     !count(value.total)||!count(value.source_count)||
     value.offset!==offset||value.limit!==limit ||
     !Array.isArray(value.rows) || value.rows.length>limit ||
     value.rows.some(r=>typeof r.issue_key!=="string"||
       !/^SPEND-[0-9]+$/.test(r.issue_key))) {
    throw new Error("jira_delivery_evidence_contract_invalid");
  }
  return value;
}
