/**
 * AI Services — Bill Extraction demo contract (synthetic data only).
 *
 * Mirrors the live private reporting view
 * `aia_infra.bill_extraction_reporting_v1` column-for-column so the future
 * server reader can replace the demo adapter without component changes.
 * Units are deliberately unlabeled: cost currency and latency units are not
 * confirmed by the data contract. NULL means unknown, never zero.
 */

export type BillScope = "verified_customer" | "test_company" | "unverified_company";

export type ReviewStatus = "reviewed" | "needs_review" | "deleted";

export type DocType = "scanned" | "digital" | "handwritten";

export interface BillExtractionRecord {
  predictionUuid: string;
  fileUuid: string | null;
  companyUuid: string;
  aiCompanyName: string;
  /** Product-directory label for matched companies, else the AI-side name. */
  companyName: string;
  companyScope: BillScope;
  createdAt: string;
  loadedAt: string;
  reviewStatus: ReviewStatus | null;
  docType: DocType | null;
  legibilityScore: number | null;
  totalPages: number | null;
  hasRaw: boolean;
  extractionCost: number | null;
  enrichmentCost: number | null;
  /** Source total unless BOTH components are missing (then NULL = unknown). */
  knownTotalCost: number | null;
  completeCostBreakdown: boolean;
  extractionLatency: number | null;
  enrichmentLatency: number | null;
  /** Source total unless BOTH components are missing (then NULL = unknown). */
  knownTotalLatency: number | null;
  completeLatencyBreakdown: boolean;
}

export interface BillDemoMeta {
  mode: "synthetic-demo";
  demoAsOf: string;
  generatedAt: string;
  seed: number;
  recordCount: number;
}

export interface BillDemoDataset {
  meta: BillDemoMeta;
  records: BillExtractionRecord[];
}

export type ScopeFilter = "verified" | "verified_test" | "verified_unverified" | "all";

export const SCOPE_FILTER_LABELS: Record<ScopeFilter, string> = {
  verified: "Verified customers",
  verified_test: "Verified + test",
  verified_unverified: "Verified + unverified",
  all: "All scopes",
};

export function scopesForFilter(filter: ScopeFilter): BillScope[] {
  switch (filter) {
    case "verified":
      return ["verified_customer"];
    case "verified_test":
      return ["verified_customer", "test_company"];
    case "verified_unverified":
      return ["verified_customer", "unverified_company"];
    case "all":
      return ["verified_customer", "test_company", "unverified_company"];
  }
}
