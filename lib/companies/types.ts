export const MODULES = [
  { key: "ap", label: "Bills / AP" },
  { key: "ar", label: "Invoices / AR" },
  { key: "transactions", label: "Transactions" },
  { key: "gst", label: "GST" },
  { key: "sync", label: "Sync" },
] as const;

export const WEEK_MODULES = [
  { key: "ap", label: "AP" },
  { key: "ar", label: "AR" },
  { key: "transactions", label: "TXN" },
  { key: "gst", label: "GST" },
] as const;

export type ModuleKey = (typeof MODULES)[number]["key"];
export type WeekModuleKey = (typeof WEEK_MODULES)[number]["key"];
export type Totals = Record<ModuleKey, number>;
export type WeekTotals = Record<WeekModuleKey, number>;
export type UsageWeek = 1 | 2 | 3 | 4;

export type SortKey = "integration_date" | "name";
export type SortDirection = "asc" | "desc";
export type UsageFilter = "all" | "active" | "inactive";

export interface LifecycleWeekUsage {
  week: UsageWeek;
  reached: boolean;
  totals: WeekTotals;
}

export interface CompanyUsageUser {
  id: string;
  email: string;
  weeks: LifecycleWeekUsage[];
}

export interface CompanyUsageRow {
  id: string;
  name: string;
  integration: string;
  integration_at: string;
  is_test: boolean;
  weeks: LifecycleWeekUsage[];
  users: CompanyUsageUser[];
}

export interface CompanyListRequest {
  action: "list";
  page: number;
  query: string;
  integration: string;
  usage: UsageFilter;
  sort: SortKey;
  direction: SortDirection;
  from: string | null;
  to: string | null;
}

export interface CompanyUsageResponse {
  rows: CompanyUsageRow[];
  total: number;
  page: number;
  page_size: number;
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
  module: WeekModuleKey;
  week: UsageWeek;
  window_start: string | null;
  window_end: string | null;
  total: number;
  item_total: number | null;
  rows: ModuleBreakdownRow[];
}
