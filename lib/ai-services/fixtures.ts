/**
 * AI Services — demo adapter (synthetic data only).
 *
 * Loads `testdata/ai-bill-extraction-demo.json` and filters it with the same
 * semantics the future server reader will apply to
 * `aia_infra.bill_extraction_reporting_v1`. Demo UI code calls `queryDemo`;
 * swapping in the RPC reader later keeps every component unchanged.
 */
import dataset from "../../testdata/ai-bill-extraction-demo.json";
import type { BillExtractionRecord, BillScope, ScopeFilter } from "./types";
import { scopesForFilter } from "./types";

export const DEMO_AS_OF = (dataset as { meta: { demoAsOf: string } }).meta.demoAsOf;
export const DEMO_RECORDS = (dataset as { records: BillExtractionRecord[] }).records;

export interface DemoQuery {
  scopes: ScopeFilter;
  from: string;
  to: string;
  docTypes: string[];
  statuses: string[];
  companyUuids: string[];
  search: string;
}

export function queryDemo(query: DemoQuery): BillExtractionRecord[] {
  const allowed = new Set<BillScope>(scopesForFilter(query.scopes));
  const search = query.search.trim().toLowerCase();
  return DEMO_RECORDS.filter(r => {
    if (!allowed.has(r.companyScope)) return false;
    const month = r.createdAt.slice(0, 7);
    if (month < query.from || month > query.to) return false;
    if (query.docTypes.length && !query.docTypes.includes(r.docType ?? "unknown")) return false;
    if (query.statuses.length && !query.statuses.includes(r.reviewStatus ?? "unknown")) return false;
    if (query.companyUuids.length && !query.companyUuids.includes(r.companyUuid)) return false;
    if (
      search &&
      !(
        r.predictionUuid.toLowerCase().includes(search) ||
        r.companyName.toLowerCase().includes(search) ||
        (r.docType ?? "").includes(search)
      )
    )
      return false;
    return true;
  });
}

export function demoCompanies(): { uuid: string; name: string; scope: BillScope }[] {
  const map = new Map<string, { uuid: string; name: string; scope: BillScope }>();
  for (const r of DEMO_RECORDS) {
    if (!map.has(r.companyUuid)) map.set(r.companyUuid, { uuid: r.companyUuid, name: r.companyName, scope: r.companyScope });
  }
  return Array.from(map.values()).sort((a, b) => a.name.localeCompare(b.name));
}
