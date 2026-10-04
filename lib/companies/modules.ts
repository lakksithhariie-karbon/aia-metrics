/**
 * Canonical Companies product-logic specification.
 *
 * The RUNTIME implementation lives in `supabase/companies-live.sql`
 * (single canonical mapping, executed server-side inside the OIDC-gated Edge
 * Function). This module is its tested TypeScript twin: unit tests and the
 * conformance script `scripts/verify-companies-bridge.cjs` replay the shared
 * vectors in `testdata/companies-module-vectors.json` against both sides, so
 * any drift between SQL and this file is caught. Change all three together.
 *
 * Counts are EVENT OCCURRENCES, never unique documents. Affected-item volume
 * is carried separately and must never be mixed into event counts.
 */
import type { ModuleKey, SortDirection, SortKey, Totals } from "./types";

export const UNATTRIBUTED_ID = "__unattributed__";
export const UNATTRIBUTED_LABEL = "Unattributed activity";

export interface RawEvent {
  event_name: string;
  properties?: Record<string, unknown> | null;
  event_time?: string;
  company_id?: string | null;
  distinct_id?: string | null;
  email?: string | null;
}

const text = (value: unknown): string =>
  typeof value === "string" ? value.trim() : "";

/**
 * TypeScript twin of public.is_internal_email: staff domains are never
 * attributed to companies. Keep the domain list identical to the SQL.
 */
const INTERNAL_DOMAINS = ["karboncard.com", "korefi.ai", "aiaccountant.com", "korefi.com"];
export function isInternalEmail(email: string | null | undefined): boolean {
  let raw = text(email).toLowerCase();
  if (!raw) return false;
  const open = raw.lastIndexOf("<");
  const close = raw.lastIndexOf(">");
  if (open >= 0 && close > open) raw = raw.slice(open + 1, close).trim();
  const at = raw.lastIndexOf("@");
  if (at < 0) return false;
  const domain = raw.slice(at + 1);
  return INTERNAL_DOMAINS.some(
    internal => domain === internal || domain.endsWith(`.${internal}`),
  );
}

export function moduleFor(
  eventName: string,
  properties: Record<string, unknown> | null | undefined,
): ModuleKey | null {
  const props = properties ?? {};
  const type = text(props.type).toLowerCase();
  const entity = text(props.entityType).toLowerCase();
  if (
    (["Upload", "Delete", "Download"].includes(eventName) && type === "bill") ||
    (eventName === "Entity Created" && entity === "bill") ||
    ["Invoice Bulk Edited", "Vendor Mismatch Resolved"].includes(eventName)
  )
    return "ap";
  if (
    (["Upload", "Download"].includes(eventName) && type === "invoice") ||
    (eventName === "Entity Created" && entity === "invoice") ||
    ["Invoice Created", "Download-Inv", "Preview"].includes(eventName)
  )
    return "ar";
  if (
    (["Upload", "Download"].includes(eventName) && type === "statement") ||
    [
      "Transaction Ledger Updated",
      "Transaction Status",
      "Transaction Type Updated",
      "Transaction Configuration Edited",
    ].includes(eventName)
  )
    return "transactions";
  if (
    (eventName === "Upload" && ["gstr2b", "purchase_register"].includes(type)) ||
    eventName === "Recon Processed" ||
    (eventName === "Download" && type === "reconciled_excel") ||
    (eventName === "Export" && type === "gst_reconciliation")
  )
    return "gst";
  if (eventName === "Accounting Sync") return "sync";
  return null;
}

export function subtypeFor(
  eventName: string,
  properties: Record<string, unknown> | null | undefined,
): string | null {
  const props = properties ?? {};
  if (
    ["Upload", "Delete", "Download", "Download-Inv", "Export", "Preview"].includes(
      eventName,
    )
  )
    return text(props.type) || null;
  if (eventName === "Entity Created") return text(props.entityType) || null;
  if (["Transaction Ledger Updated", "Transaction Type Updated"].includes(eventName)) {
    const from = text(props.from);
    const to = text(props.to);
    return [from, to].filter(Boolean).join(" → ") || null;
  }
  if (eventName === "Transaction Configuration Edited")
    return text(props.configField) || null;
  if (eventName === "Vendor Mismatch Resolved")
    return text(props.resolutionType) || null;
  if (eventName === "Accounting Sync" && Array.isArray(props.sync_items)) {
    return (props.sync_items as unknown[]).map(text).filter(Boolean).join(", ") || null;
  }
  return null;
}

/** Instrumented affected-item volume for one event; null = not instrumented. */
export function itemsFor(
  eventName: string,
  properties: Record<string, unknown> | null | undefined,
): number | null {
  const props = properties ?? {};
  const key =
    eventName === "Accounting Sync"
      ? "items_count"
      : eventName === "Transaction Status"
        ? "itemsCount"
        : ["Transaction Ledger Updated", "Transaction Type Updated"].includes(eventName)
          ? "transactionCount"
          : "";
  const value = key ? props[key] : null;
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

export const emptyTotals = (): Totals => ({
  ap: 0,
  ar: 0,
  transactions: 0,
  gst: 0,
  sync: 0,
});

export interface AggregatedUser {
  id: string;
  email: string;
  totals: Totals;
}

export interface AggregatedCompany {
  id: string;
  users: AggregatedUser[];
  totals: Totals;
}

/**
 * In-memory mirror of the read_companies_usage + read_company_users merge:
 * membership comes from ALL observed non-internal events (so users with zero
 * mapped module activity still appear with zero totals), while counts come
 * from the SAME classified mapped events only. Per-company totals therefore
 * equal attributed user totals plus unattributed activity. Used by tests and
 * the conformance script.
 */
export function aggregateEvents(events: readonly RawEvent[]): AggregatedCompany[] {
  const companies = new Map<string, AggregatedCompany>();
  const companyFor = (id: string): AggregatedCompany => {
    let company = companies.get(id);
    if (!company) {
      company = { id, users: [], totals: emptyTotals() };
      companies.set(id, company);
    }
    return company;
  };
  const userFor = (company: AggregatedCompany, userId: string, email: string): AggregatedUser => {
    let user = company.users.find(candidate => candidate.id === userId);
    if (!user) {
      user = {
        id: userId,
        email: userId === UNATTRIBUTED_ID ? UNATTRIBUTED_LABEL : email || userId,
        totals: emptyTotals(),
      };
      company.users.push(user);
    } else if (email) {
      // Latest non-empty email wins (callers pass events in time order).
      user.email = email;
    }
    return user;
  };
  for (const event of events) {
    const companyId = text(event.company_id);
    if (!companyId) continue;
    // Staff activity is excluded consistently with the SQL readers.
    if (isInternalEmail(event.email)) continue;
    const userId = text(event.distinct_id) || UNATTRIBUTED_ID;
    const module = moduleFor(text(event.event_name), event.properties ?? {});
    // The unattributed bucket exists only to preserve mapped activity that
    // has no usable identity; without mapped activity there is nothing to
    // preserve, while identified users always establish membership.
    if (!module && userId === UNATTRIBUTED_ID) continue;
    // Membership: every observed non-internal identity appears, even with no
    // mapped module activity in the period.
    const company = companyFor(companyId);
    const user = userFor(company, userId, text(event.email));
    if (!module) continue;
    company.totals[module] += 1;
    user.totals[module] += 1;
  }
  return [...companies.values()];
}

export function companyTotal(totals: Totals): number {
  return totals.ap + totals.ar + totals.transactions + totals.gst + totals.sync;
}

/**
 * TypeScript twin of public.company_usable_name: free-text event company
 * names mix real names with placeholders; only non-denied values are usable.
 * Keep the denied list identical to supabase/companies-live.sql.
 */
const DENIED_NAMES = new Set(
  ["abc", "dummy", "na", "n/a", "test", "testing", "demo", "xyz", "delete company"],
);
export function usableCompanyName(raw: string | null | undefined): string | null {
  const value = text(raw);
  if (!value || DENIED_NAMES.has(value.toLowerCase())) return null;
  return value;
}

/**
 * Display-name priority: directory name → latest usable event company name →
 * raw company id. Never merges companies sharing a display name.
 */
export function resolveCompanyName(
  directoryName: string | null | undefined,
  latestEventName: string | null | undefined,
  companyId: string,
): string {
  return text(directoryName) || usableCompanyName(latestEventName) || companyId;
}

/** Asia/Kolkata calendar-day window check for an ISO date range. */
export function inRangeIST(eventTime: string, from: string | null, to: string | null): boolean {
  const at = Date.parse(`${eventTime}`);
  if (Number.isNaN(at)) return false;
  if (from && at < Date.parse(`${from}T00:00:00+05:30`)) return false;
  if (to && at >= Date.parse(`${to}T00:00:00+05:30`) + 86_400_000) return false;
  return true;
}

export interface NamedRow {
  id: string;
  name: string;
  users: { email: string }[];
  totals: Totals;
}

export function matchesSearch(
  row: NamedRow,
  query: string,
): boolean {
  const needle = query.trim().toLowerCase();
  if (!needle) return true;
  return (
    row.name.toLowerCase().includes(needle) ||
    row.users.some(user => user.email.toLowerCase().includes(needle))
  );
}

export function sortRows<T extends NamedRow>(
  rows: readonly T[],
  key: SortKey,
  direction: SortDirection,
): T[] {
  const sign = direction === "asc" ? 1 : -1;
  return [...rows].sort((a, b) => {
    const left = key === "name" ? a.name : a.totals[key];
    const right = key === "name" ? b.name : b.totals[key];
    const diff =
      typeof left === "number" && typeof right === "number"
        ? left - right
        : String(left).localeCompare(String(right));
    if (diff !== 0) return sign * (diff < 0 ? -1 : 1);
    // Stable tie-breaks: name, then the stable company ID (never the name).
    return a.name.localeCompare(b.name) || a.id.localeCompare(b.id);
  });
}
