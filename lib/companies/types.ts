export const MODULES = [
  { key: "ap", label: "Bills / AP" },
  { key: "ar", label: "Invoices / AR" },
  { key: "transactions", label: "Transactions" },
  { key: "gst", label: "GST" },
  { key: "sync", label: "Sync" },
] as const;

export const MONTH_MODULES = [
  { key: "ap", label: "AP" },
  { key: "ar", label: "AR" },
  { key: "transactions", label: "Transaction" },
  { key: "gst", label: "GST" },
] as const;

export type ModuleKey = (typeof MODULES)[number]["key"];
export type MonthModuleKey = (typeof MONTH_MODULES)[number]["key"];
export type Totals = Record<ModuleKey, number>;
export type MonthTotals = Record<MonthModuleKey, number>;

export type SortKey = "integration_month" | "name";
export type SortDirection = "asc" | "desc";
export type UsageFilter = "all" | "active" | "inactive";

export interface CalendarMonthUsage {
  month: string;
  available: boolean;
  totals: MonthTotals;
}

export interface CompanyUsageUser {
  id: string;
  email: string;
  months: CalendarMonthUsage[];
}

export interface CompanyUsageRow {
  id: string;
  name: string;
  integration: string;
  integration_at: string;
  integration_month: string;
  is_test: boolean;
  months: CalendarMonthUsage[];
  users: CompanyUsageUser[];
}

export interface CompanyListRequest {
  action: "list";
  query: string;
  integration: string;
  usage: UsageFilter;
  sort: SortKey;
  direction: SortDirection;
  from: string;
  to: string;
}

export interface CompanyUsageResponse {
  rows: CompanyUsageRow[];
  months: string[];
  total: number;
  data_start: string | null;
  data_end: string | null;
  source_watermark_at: string | null;
}

export interface ModuleBreakdownRow {
  event: string;
  subtype: string | null;
  status: string | null;
  count: number;
  /** Null when no instrumented event in the group reported item volume. */
  items: number | null;
  latest_at: string | null;
}

export interface ModuleBreakdownResponse {
  company_id: string;
  company_name: string;
  user_id: string | null;
  user_label: string | null;
  module: MonthModuleKey;
  month: string;
  window_start: string | null;
  window_end: string | null;
  total: number;
  item_total: number | null;
  rows: ModuleBreakdownRow[];
  insights: CompaniesMonthlyInsights;
}

/** Additional facets for the Companies drill. Every count reconciles to v2. */
export type CompanyInsightCategory =
  | "status" | "ledger" | "type_change" | "upload" | "entity"
  | "vendor_mismatch" | "reconciliation" | "configuration" | "invoice_edit" | "other";

export interface CompanyInsightSlice {
  category: CompanyInsightCategory;
  event: string;
  type: string | null;
  subtype: string | null;
  entity_type: string | null;
  transaction_type: string | null;
  action: string | null;
  status: string | null;
  source: string | null;
  file_type: string | null;
  resolution_type: string | null;
  events: number;
  items: number | null;
  instrumented: number;
  latest_at: string | null;
}

export interface CompanyInsightUser {
  id: string;
  label: string;
  events: number;
  active_days: number;
  first_at: string | null;
  last_at: string | null;
  counts: Record<CompanyInsightCategory, number> | Record<string, number>;
}

export interface CompaniesMonthlyInsights {
  contract: "companies_monthly_drill_insights_v1";
  company_id: string;
  company_name: string;
  module: MonthModuleKey;
  month: string;
  user_key: string | null;
  window_start: string;
  window_end: string;
  source_watermark_at: string;
  total: number;
  item_total: number | null;
  instrumented_events: number;
  active_users: number;
  active_days: number;
  unattributed_events: number;
  first_at: string | null;
  last_at: string | null;
  user_groups_total: number;
  categories: Array<{ key: CompanyInsightCategory; events: number; items: number | null; instrumented: number }>;
  slices: CompanyInsightSlice[];
  users: CompanyInsightUser[];
  days: Array<{ date: string; events: number; users: number }>;
  sources: Array<{ source: string; events: number }>;
}
