export const MODULES = [
  { key: "ap", label: "Bills / AP" },
  { key: "ar", label: "Invoices / AR" },
  { key: "transactions", label: "Transactions" },
  { key: "gst", label: "GST" },
  { key: "sync", label: "Sync" },
] as const;

export type ModuleKey = (typeof MODULES)[number]["key"];
export type Totals = Record<ModuleKey, number>;

export type SortKey = "name" | ModuleKey;
export type SortDirection = "asc" | "desc";
export type UsageFilter = "all" | "active" | "inactive";

export interface CompanyUsageUser {
  id: string;
  email: string;
  totals: Totals;
}

export interface CompanyUsageRow {
  id: string;
  name: string;
  integration: string;
  is_test: boolean;
  totals: Totals;
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
  /** False when the requested range does not overlap warehouse history. */
  available: boolean;
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
  module: ModuleKey;
  total: number;
  item_total: number | null;
  rows: ModuleBreakdownRow[];
}
