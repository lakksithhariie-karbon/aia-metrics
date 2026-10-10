/** Shared, validated compact Jira dashboard contract. Raw issue lists never ship
 * in the initial page payload; evidence is paginated on demand. */
export type DeliveryFilters = {
  sprint: number | null;
  module: string | null;
  sub_module: string | null;
  severity: string | null;
  assignee: string | null;
};
export type SprintRow = {
  sprint_id: number;
  sprint_name: string;
  state: string;
  start_date: string;
  end_date: string;
  scope_now: number;
  committed: number;
  committed_done: number;
  commitment_completion_pct: number | null;
  added_mid_sprint: number;
  mid_sprint_add_pct: number | null;
  done_now: number;
  scope_completion_pct: number | null;
  carried_to_next: number;
};
export type ThroughputRow = {
  sprint_id: number;
  sprint_name: string;
  throughput: number;
  first_done_after_start: number;
  sprint_start: string;
  sprint_complete: string;
};
export type CohortSummary = {
  n: number | null;
  value: number | null;
  denominator: number | null;
  rows_shown: number;
  unit: string | null;
  title?: string;
  source_note?: string;
  scope_note?: string;
};
export type FlowStageRow = {
  sprint_id: number;
  sprint_name: string;
  sprint_state: string;
  stage: string;
  issues_in_stage: number;
  median_hours: number | null;
  avg_hours: number | null;
  p90_hours: number | null;
};
export type WorkflowStat = { n: number | null; value: number | null; denominator: number | null; unit: string | null };
export type DeliveryDashboard = {
  contract: "jira_delivery_dashboard_v1";
  snapshot_id: number;
  latest_clean_sync_id: number;
  refreshed_at: string;
  synced_at: string;
  selected_sprint_id: number | null;
  filters: Record<string, unknown>;
  options: {
    sprints: Array<{ sprint_id: number; sprint_name: string; state: string; start_date: string; end_date: string }>;
    modules: string[];
    sub_modules: string[];
    severities: string[];
    assignees: string[];
  };
  core: {
    hero: { value: number | null; status: string };
    sprint_discipline: SprintRow[];
    sprint_throughput: ThroughputRow[];
    sprint_summary: Array<Record<string, unknown>>;
    cycle_time_org: { median_days: number | null; n: number };
    cycle_time_by_sprint: Array<{ sprint_id: number; median_days: number | null; n: number }>;
    metric_cohorts: Record<string, CohortSummary>;
  };
  flow: {
    flow_counts: { open_total: number; stale_all: number; stale_blocked: number; blocked_all: number; qa_queue_count: number };
    wip_by_status: Array<{ status_name: string; issue_count: number; pct: number }>;
    stage_summary: FlowStageRow[];
    bug_health: {
      open_bugs: number; median_age_days: number | null;
      age_histogram: Array<{ bucket: string; count: number; pct: number }>;
      open_by_module: Array<{ module: string | null; count: number }>;
      open_by_severity: Array<{ severity: string | null; count: number }>;
    };
    metric_updates: Record<string, WorkflowStat>;
    backlog_trend: Array<{
      week_start: string; open_eod: number; net_movement: number; created: number; resolved: number;
    }>;
  };
  quality: {
    metric_updates: Record<string, WorkflowStat>;
    qa_rejection_org: { denominator: number; rejected_cycles: number; rejection_pct: number };
    resolution_medians: Array<{ metric: string; median_value: number | null; rows_used: number; unit: string }>;
    org_reopen: Array<{ month: string; closed_issues: number; reopened_issues: number; reopen_pct: number }>;
  };
  issue_types: Array<{ sprint_id: number; sprint_name: string; issue_type: string; count: number }>;
};
export type DeliveryEvidenceItem = {
  issue_key: string;
  summary: string | null;
  status: string | null;
  issue_type: string | null;
  priority: string | null;
  severity: string | null;
  module: string | null;
  sub_module: string | null;
  assignee: string | null;
  created_at: string | null;
  resolved_at: string | null;
  stage_hours?: number | null;
};
export type DeliveryEvidence = {
  contract: "jira_delivery_evidence_v1";
  key: string;
  label: string;
  snapshot_id: number;
  total: number;
  source_count: number;
  offset: number;
  limit: number;
  rows: DeliveryEvidenceItem[];
};
