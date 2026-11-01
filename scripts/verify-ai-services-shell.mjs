#!/usr/bin/env node
/**
 * Static contract for the AI Services Bill Extraction mock shell.
 * Demo UI only: asserts synthetic-data guards, nav wiring, and shared
 * grid/table/modal primitives. No Supabase, API, or AWS changes allowed.
 */
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";

const read = path => readFileSync(new URL("../" + path, import.meta.url), "utf8");
const has = path => existsSync(new URL("../" + path, import.meta.url));

// New route + shell files exist.
for (const path of [
  "app/ai-services/page.tsx",
  "app/ai-services/loading.tsx",
  "app/ai-services/ai-services.css",
  "components/ai-services/ai-services-overview.tsx",
  "components/ai-services/bill-drills.tsx",
  "lib/ai-services/types.ts",
  "lib/ai-services/summary.ts",
  "lib/ai-services/fixtures.ts",
  "scripts/generate-ai-bill-demo.mjs",
  "testdata/ai-bill-extraction-demo.json",
]) {
  assert.ok(has(path), "missing " + path);
}

// Demo fixture is synthetic and view-shaped.
const demo = JSON.parse(read("testdata/ai-bill-extraction-demo.json"));
assert.equal(demo.meta.mode, "synthetic-demo", "demo meta.mode");
assert.ok(Array.isArray(demo.records) && demo.records.length > 100, "demo records");
assert.ok(
  demo.records.every(r => typeof r.predictionUuid === "string" && "knownTotalCost" in r && "companyScope" in r),
  "demo records mirror bill_extraction_reporting_v1 columns",
);
assert.ok(
  demo.records.some(r => r.knownTotalCost === null) && demo.records.some(r => r.knownTotalLatency === null),
  "demo preserves unknown cost/latency (never zero-filled)",
);

// No live data access from the mock slice.
for (const path of [
  "lib/ai-services/types.ts",
  "lib/ai-services/summary.ts",
  "lib/ai-services/fixtures.ts",
  "scripts/generate-ai-bill-demo.mjs",
  "components/ai-services/ai-services-overview.tsx",
  "components/ai-services/bill-drills.tsx",
  "app/ai-services/page.tsx",
]) {
  const src = read(path);
  assert.doesNotMatch(src, /SUPABASE_|service_role|from ["']@supabase|fetch\(/, path + ": no live data access");
  assert.doesNotMatch(src, /aia_infra\.(aws_costs|bill_costs|companies)/, path + ": no direct source table reads");
}

// Missing-is-unknown semantics live in the aggregator, not the UI.
const summary = read("lib/ai-services/summary.ts");
assert.match(summary, /knownTotalCost === null/, "unknown cost guard");
assert.match(summary, /knownTotalLatency === null/, "unknown latency guard");
assert.match(summary, /Math\.ceil\(\(p \/ 100\)/, "nearest-rank percentile");

// Nav wiring: header dropdown + drawer link, additive only.
const header = read("components/product-metrics-header.tsx");
assert.match(header, /"ai-services"/, "header DashboardKey");
assert.match(header, /AI_SERVICES_PAGES/, "header AI section pages");
assert.match(header, /\/ai-services/, "header ai-services href");
const drawer = read("components/main-navigation-drawer.tsx");
assert.match(drawer, /href="\/ai-services"/, "drawer ai-services link");
assert.match(drawer, /onAiServices/, "drawer active-state match");
assert.doesNotMatch(drawer, /"AI Services" as const|futureSections = \["AI Services"\]/, "drawer placeholder retired");

// Page reuses shared grid + investigation primitives and its own scope file.
const page = read("app/ai-services/page.tsx");
for (const css of ["metrics-page-grid.css", "delivery.css", "delivery-investigation.css", "ai-services.css"]) {
  assert.ok(page.includes(css), "page imports " + css);
}
const overview = read("components/ai-services/ai-services-overview.tsx");
assert.match(overview, /ed-kpi-grid po-kpis/, "KPI grid primitive");
assert.match(overview, /ai-kpi-section/, "KPI section spans the outer page grid");
assert.match(overview, /search,\s*\n\s*\}\)/, "global search scopes every KPI and chart, not only drills");
assert.match(overview, /<DistributionRows/, "document and review comparison charts remain visual");
assert.match(overview, /<LatencyComparison/, "latency compares P50 and P95 visually");
const aiCss = read("app/ai-services/ai-services.css");
assert.match(aiCss, /\.ai-shell \.ai-kpi-section[\s\S]*?grid-column: 1 \/ -1/, "KPI section spans all 12 columns");
assert.match(summary, /\(r\.extractionCost === null\) !== \(r\.enrichmentCost === null\)/, "partial cost component guard");
assert.match(overview, /MetricsInvestigationTable/, "investigation table primitive");
assert.match(overview, /ProductMonthRangePicker/, "shared date control");
assert.match(overview, /CompactMenuSelect/, "shared filter control");
assert.match(overview, /BillRecordsModal/, "drill modal wiring");
assert.match(overview, /ed-preview-note/, "freshness/caveat footer");
const drills = read("components/ai-services/bill-drills.tsx");
assert.match(drills, /role="dialog"/, "drill modal semantics");
assert.match(drills, /aria-modal/, "drill modal semantics");
assert.match(drills, /createPortal/, "investigations portal outside dashboard grid");
assert.match(drills, /DrillSummary/, "Product-style evidence summary");
assert.match(drills, /rd-table-summary/, "Product-style pagination summary");
assert.match(drills, /BillCompaniesModal/, "active companies open a company population before prediction detail");
assert.match(aiCss, /\.ai-records-table\.ed-investigation-table th:first-child/, "prediction ID column does not inherit 38px expander width");
assert.match(overview, /className="ed-screenreader-only"/, "live announcement uses the shared visually-hidden class");
assert.doesNotMatch(overview, /ed-screen-reader-only/, "do not leak announcements below the footer");

console.log("AI Services bill-extraction mock shell verified: synthetic demo, shared primitives, no live wiring.");
