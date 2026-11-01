/**
 * AI Services — pure demo aggregators over BillExtractionRecord arrays.
 *
 * The future server reader will expose these same shapes from
 * `aia_infra.bill_extraction_reporting_v1`; the demo UI consumes only these
 * shapes, never raw source tables.
 */
import type { BillExtractionRecord, BillScope } from "./types";

export interface KpiResult {
  bills: number;
  companies: number;
  knownCostTotal: number;
  knownCostCount: number;
  unknownCostCount: number;
  avgKnownCost: number | null;
  p50Latency: number | null;
  p95Latency: number | null;
  knownLatencyCount: number;
  unknownLatencyCount: number;
  needsReviewCount: number;
  needsReviewRate: number | null;
}

export interface MonthPoint {
  month: string;
  bills: number;
  knownCost: number;
  unknownCostCount: number;
  p50Latency: number | null;
  p95Latency: number | null;
}

export interface DocMixSlice {
  docType: string;
  bills: number;
  knownCost: number;
}

export interface ReviewSlice {
  status: string;
  bills: number;
}

export interface LegibilityBucket {
  bucket: string;
  bills: number;
  needsReview: number;
}

export interface CompanyRow {
  companyUuid: string;
  companyName: string;
  scope: BillScope;
  bills: number;
  knownCost: number;
  unknownCostCount: number;
}

export interface ExceptionCounts {
  missingCost: number;
  missingLatency: number;
  missingPages: number;
  missingDocType: number;
  missingLegibility: number;
  partialBreakdown: number;
  testScope: number;
  unverifiedScope: number;
}

/** Nearest-rank percentile over a sorted ascending array. */
export function percentile(sorted: number[], p: number): number | null {
  if (!sorted.length) return null;
  const rank = Math.ceil((p / 100) * sorted.length) - 1;
  return sorted[Math.min(Math.max(rank, 0), sorted.length - 1)];
}

export function summarize(records: BillExtractionRecord[]): KpiResult {
  const companies = new Set<string>();
  let knownCostTotal = 0;
  let knownCostCount = 0;
  let unknownCostCount = 0;
  const latencies: number[] = [];
  let unknownLatencyCount = 0;
  let needsReviewCount = 0;
  for (const r of records) {
    companies.add(r.companyUuid);
    if (r.knownTotalCost === null) unknownCostCount += 1;
    else {
      knownCostTotal += r.knownTotalCost;
      knownCostCount += 1;
    }
    if (r.knownTotalLatency === null) unknownLatencyCount += 1;
    else latencies.push(r.knownTotalLatency);
    if (r.reviewStatus === "needs_review") needsReviewCount += 1;
  }
  latencies.sort((a, b) => a - b);
  return {
    bills: records.length,
    companies: companies.size,
    knownCostTotal,
    knownCostCount,
    unknownCostCount,
    avgKnownCost: knownCostCount ? knownCostTotal / knownCostCount : null,
    p50Latency: percentile(latencies, 50),
    p95Latency: percentile(latencies, 95),
    knownLatencyCount: latencies.length,
    unknownLatencyCount,
    needsReviewCount,
    needsReviewRate: records.length ? needsReviewCount / records.length : null,
  };
}

export function monthlySeries(records: BillExtractionRecord[]): MonthPoint[] {
  const byMonth = new Map<string, BillExtractionRecord[]>();
  for (const r of records) {
    const month = r.createdAt.slice(0, 7);
    const list = byMonth.get(month);
    if (list) list.push(r);
    else byMonth.set(month, [r]);
  }
  return Array.from(byMonth.entries())
    .sort(([a], [b]) => (a < b ? -1 : 1))
    .map(([month, rows]) => {
      const lats = rows
        .map(r => r.knownTotalLatency)
        .filter((v): v is number => v !== null)
        .sort((a, b) => a - b);
      return {
        month,
        bills: rows.length,
        knownCost: rows.reduce((s, r) => s + (r.knownTotalCost ?? 0), 0),
        unknownCostCount: rows.filter(r => r.knownTotalCost === null).length,
        p50Latency: percentile(lats, 50),
        p95Latency: percentile(lats, 95),
      };
    });
}

export function docMix(records: BillExtractionRecord[]): DocMixSlice[] {
  const order = ["scanned", "digital", "handwritten", "unknown"];
  const map = new Map<string, { bills: number; knownCost: number }>();
  for (const r of records) {
    const key = r.docType ?? "unknown";
    const slot = map.get(key) ?? { bills: 0, knownCost: 0 };
    slot.bills += 1;
    slot.knownCost += r.knownTotalCost ?? 0;
    map.set(key, slot);
  }
  return order
    .filter(k => map.has(k))
    .map(k => ({ docType: k, bills: map.get(k)!.bills, knownCost: map.get(k)!.knownCost }));
}

export function reviewMix(records: BillExtractionRecord[]): ReviewSlice[] {
  const order = ["reviewed", "needs_review", "deleted", "unknown"];
  const map = new Map<string, number>();
  for (const r of records) {
    const key = r.reviewStatus ?? "unknown";
    map.set(key, (map.get(key) ?? 0) + 1);
  }
  return order
    .filter(k => map.has(k))
    .map(k => ({ status: k, bills: map.get(k)! }));
}

export function legibilityBuckets(records: BillExtractionRecord[]): LegibilityBucket[] {
  const labels = ["0–0.2", "0.2–0.4", "0.4–0.6", "0.6–0.8", "0.8–1.0", "unknown"];
  const buckets = labels.map(bucket => ({ bucket, bills: 0, needsReview: 0 }));
  for (const r of records) {
    const idx =
      r.legibilityScore === null
        ? 5
        : r.legibilityScore < 0.2
          ? 0
          : r.legibilityScore < 0.4
            ? 1
            : r.legibilityScore < 0.6
              ? 2
              : r.legibilityScore < 0.8
                ? 3
                : 4;
    buckets[idx].bills += 1;
    if (r.reviewStatus === "needs_review") buckets[idx].needsReview += 1;
  }
  return buckets;
}

export function companyTable(records: BillExtractionRecord[]): CompanyRow[] {
  const map = new Map<string, CompanyRow & { name: string }>();
  for (const r of records) {
    const row =
      map.get(r.companyUuid) ??
      { companyUuid: r.companyUuid, companyName: r.companyName, scope: r.companyScope, bills: 0, knownCost: 0, unknownCostCount: 0, name: r.companyName };
    row.bills += 1;
    row.knownCost += r.knownTotalCost ?? 0;
    if (r.knownTotalCost === null) row.unknownCostCount += 1;
    map.set(r.companyUuid, row);
  }
  return Array.from(map.values()).sort((a, b) => b.bills - a.bills);
}

export function exceptionCounts(records: BillExtractionRecord[]): ExceptionCounts {
  return {
    missingCost: records.filter(r => r.knownTotalCost === null).length,
    missingLatency: records.filter(r => r.knownTotalLatency === null).length,
    missingPages: records.filter(r => r.totalPages === null).length,
    missingDocType: records.filter(r => r.docType === null).length,
    missingLegibility: records.filter(r => r.legibilityScore === null).length,
    partialBreakdown: records.filter(
      r =>
        (r.extractionCost === null) !== (r.enrichmentCost === null),
    ).length,
    testScope: records.filter(r => r.companyScope === "test_company").length,
    unverifiedScope: records.filter(r => r.companyScope === "unverified_company").length,
  };
}
