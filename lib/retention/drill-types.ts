export type ActivationStatus =
  | "activated"
  | "awaiting_sync"
  | "no_core"
  | "no_training";

export interface ActivationModuleTotals {
  ap: number;
  ar: number;
  transactions: number;
  gst: number;
}

export interface ActivationUserRow {
  id: string;
  email: string;
  totals: ActivationModuleTotals;
}

export interface ActivationCompanyRow {
  id: string;
  name: string;
  is_test: boolean;
  integration: string;
  integration_at: string;
  training_sync_at: string | null;
  post_training_core_at: string | null;
  activated_at: string | null;
  status: ActivationStatus;
  ttv_hours: number | null;
  totals: ActivationModuleTotals;
  users: ActivationUserRow[];
}

export interface ActivationListResponse {
  rows: ActivationCompanyRow[];
  total: number;
  page: number;
  page_size: number;
}

export interface ActivationEvidenceRow {
  at: string;
  event: string;
  module: "AP" | "AR" | "Transaction" | "GST" | "Sync";
  user: string | null;
}

export interface ActivationDetailUser {
  id: string;
  email: string;
  first_seen_at: string;
  last_seen_at: string;
  activation_role: "core_job" | "closing_sync" | "both" | null;
  recent_totals: ActivationModuleTotals & { sync: number };
}

export interface ActivationWeekRow {
  week_start: string;
  week_end: string;
  totals: ActivationModuleTotals & { sync: number };
}

export interface ActivationCompanyDetail {
  id: string;
  name: string;
  is_test: boolean;
  integration: string;
  signup_at: string;
  signup_kind: "Company Created" | "First seen";
  integration_at: string;
  training_sync_at: string | null;
  post_training_core_at: string | null;
  activated_at: string | null;
  ttv_hours: number | null;
  last_core_activity_at: string | null;
  observed_users: number;
  active_weeks_8: number;
  module_events_8: number;
  evidence: ActivationEvidenceRow[];
  users: ActivationDetailUser[];
  weeks: ActivationWeekRow[];
}

export type RetentionCellSegment = "all" | "retained" | "churned";

export interface RetentionCellUserRow {
  id: string;
  email: string;
  first_seen_at: string;
  last_seen_at: string;
  active: boolean;
  core_events: number;
  totals: {
    ap: number;
    ar: number;
    transactions: number;
    sync: number;
  };
}

export interface RetentionCellCompanyRow {
  id: string;
  name: string;
  is_test: boolean;
  integration: string;
  integration_at: string;
  activated_at: string;
  retained: boolean;
  cohort_start: string;
  target_start: string;
  target_end: string;
  core_events: number;
  active_users: number;
  observed_users: number;
  totals: {
    ap: number;
    ar: number;
    transactions: number;
    sync: number;
  };
  users: RetentionCellUserRow[];
}

export interface RetentionCellCounts {
  all: number;
  retained: number;
  churned: number;
}

export interface RetentionCellDrillResponse {
  interval: "weekly" | "monthly";
  relative_period: number;
  cohort_start: string | null;
  counts: RetentionCellCounts;
  rows: RetentionCellCompanyRow[];
  total: number;
  page: number;
  page_size: number;
  source_watermark_at: string | null;
}

export interface RetentionPeriodContext {
  interval: "weekly" | "monthly";
  relative_period: number;
  cohort_start: string | null;
  target_start: string;
  target_end: string;
  retained: boolean;
  core_events: number;
  active_users: number;
  observed_users: number;
  totals: {
    ap: number;
    ar: number;
    transactions: number;
    sync: number;
  };
}
