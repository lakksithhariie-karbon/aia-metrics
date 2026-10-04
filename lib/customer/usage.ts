/** Customer usage is activity count, not unique documents. No production data. */
export const SNAPSHOT_DATE = "2026-10-04";
export const SOURCE_START = "2026-07-06";
export const MODULES = [
  { key: "ap", label: "Bills / AP" },
  { key: "ar", label: "Invoices / AR" },
  { key: "transactions", label: "Transactions" },
  { key: "gst", label: "GST" },
  { key: "sync", label: "Sync" },
] as const;
export type ModuleKey = (typeof MODULES)[number]["key"];
export type Totals = Record<ModuleKey, number | null>;
export type Flow = "bills" | "invoices" | "statements" | "transactions" | "sync";
export interface Activity { date: string; flow: Flow; count: number }
export interface CustomerUser { id: string; email: string; events: readonly Activity[] }
export interface Customer { id: string; name: string; integration: string; users: readonly CustomerUser[] }
export interface UsageUser { id: string; email: string; totals: Totals }
export interface UsageRow { id: string; name: string; integration: string; users: UsageUser[]; totals: Totals }
export interface DateRange { preset: "lifetime" | "3" | "6" | "12" | "custom"; start: string | null; end: string | null }
export type SortKey = "name" | ModuleKey;
export interface Filters { query: string; usage: "all" | "active" | "inactive"; integration: string }
export const LIFETIME: DateRange = { preset: "lifetime", start: null, end: null };
export const EMPTY_FILTERS: Filters = { query: "", usage: "all", integration: "all" };
export const number = new Intl.NumberFormat("en-US");
export function shiftMonth(month: string, offset: number): string {
  const [year, m] = month.split("-").map(Number);
  return new Date(Date.UTC(year, m - 1 + offset, 1)).toISOString().slice(0, 7);
}
export function lastDay(month: string): string {
  return new Date(Date.parse(shiftMonth(month, 1) + "-01T12:00:00Z") - 86400000).toISOString().slice(0, 10);
}
export function shortMonth(month: string): string {
  return new Date(month + "-01T12:00:00Z").toLocaleDateString("en-GB", { month: "short", year: "numeric", timeZone: "UTC" }).replace("Sept", "Sep");
}
export function rangeLabel(range: DateRange): string {
  if (range.preset === "lifetime") return "Lifetime";
  if (!range.start || !range.end) return "Choose months";
  return range.start === range.end ? shortMonth(range.start) : `${shortMonth(range.start)} – ${shortMonth(range.end)}`;
}
export function presetRange(preset: DateRange["preset"]): DateRange {
  if (preset === "lifetime" || preset === "custom") return { ...LIFETIME, preset };
  const end = shiftMonth(SNAPSHOT_DATE.slice(0, 7), -1);
  return { preset, start: shiftMonth(end, 1 - Number(preset)), end };
}
export function windowFor(range: DateRange): { start: string; end: string } {
  if (range.preset === "lifetime") return { start: SOURCE_START, end: SNAPSHOT_DATE };
  if (!range.start || !range.end || range.start > range.end) throw new Error("Select a valid month range.");
  return { start: range.start + "-01", end: [lastDay(range.end), SNAPSHOT_DATE].sort()[0] };
}
function emptyTotals(available: boolean): Totals {
  const zero = available ? 0 : null;
  return { ap: zero, ar: zero, transactions: zero, gst: null, sync: zero };
}
function activityTotals(events: readonly Activity[], start: string, end: string, available: boolean): Totals {
  const totals = emptyTotals(available);
  if (!available) return totals;
  for (const event of events) {
    if (event.date < start || event.date > end) continue;
    const key = event.flow === "bills" ? "ap" : event.flow === "invoices" ? "ar" : event.flow === "sync" ? "sync" : "transactions";
    totals[key] = (totals[key] ?? 0) + event.count;
  }
  return totals;
}
/** Stable customer IDs, never display names, define the grouping boundary. */
export function aggregateCustomers(customers: readonly Customer[], range: DateRange): UsageRow[] {
  const { start, end } = windowFor(range);
  const available = end >= SOURCE_START && start <= SNAPSHOT_DATE;
  return customers.map(customer => {
    const users = customer.users.map(user => ({ id: user.id, email: user.email, totals: activityTotals(user.events, start, end, available) }));
    const totals = emptyTotals(available);
    for (const user of users) for (const { key } of MODULES) {
      if (totals[key] !== null && user.totals[key] !== null) totals[key]! += user.totals[key]!;
    }
    return { id: customer.id, name: customer.name, integration: customer.integration, users, totals };
  });
}
export function filterAndSort(rows: readonly UsageRow[], filters: Filters, key: SortKey, direction: "asc" | "desc"): UsageRow[] {
  const query = filters.query.trim().toLowerCase();
  return rows.filter(row => {
    const matches = !query || row.name.toLowerCase().includes(query) || row.users.some(user => user.email.toLowerCase().includes(query));
    const total = MODULES.reduce((sum, module) => sum + (row.totals[module.key] ?? 0), 0);
    const available = row.totals.ap !== null;
    return matches && (filters.integration === "all" || row.integration === filters.integration)
      && (filters.usage === "all" || available && (filters.usage === "active" ? total > 0 : total === 0));
  }).sort((a, b) => {
    const av = key === "name" ? a.name : a.totals[key], bv = key === "name" ? b.name : b.totals[key];
    if (av === null && bv !== null) return 1;
    if (av !== null && bv === null) return -1;
    const diff = av === null || bv === null ? 0 : typeof av === "number" && typeof bv === "number" ? av - bv : String(av).localeCompare(String(bv));
    return (direction === "asc" ? diff : -diff) || a.name.localeCompare(b.name) || a.id.localeCompare(b.id);
  });
}
export function pageNumbers(page: number, pages: number): number[] {
  const result: number[] = [];
  for (let i = 1; i <= pages; i++) if (i === 1 || i === pages || Math.abs(i - page) <= 1) result.push(i);
  return result;
}
