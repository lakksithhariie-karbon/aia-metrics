#!/usr/bin/env node
/**
 * Static contract for the AI Services Bill Extraction live reader and shell.
 * Live UI with private server reader: asserts security, nav wiring, and shared
 * grid/table/modal primitives; no source-table changes.
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
  "lib/ai-services/live.ts",
  "app/api/ai-services/report/route.ts",
  "supabase/migrations/20261101185848_ai_bill_extraction_live_read_v1_20261102.sql",
  "supabase/migrations/20261102030122_aia_bill_analytics_read_v1_20261102.sql",
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

// Client code never imports secrets or Supabase source data. Only the server
// reader may use the service-role key, and production access fails closed.
const overviewClient = read("components/ai-services/ai-services-overview.tsx");
const evidenceClient = read("components/ai-services/bill-drills.tsx");
assert.doesNotMatch(overviewClient + evidenceClient, /SUPABASE_SERVICE_ROLE_KEY|aia_infra\./);
assert.doesNotMatch(overviewClient, /queryDemo|Synthetic preview|records={filtered}/);
const live = read("lib/ai-services/live.ts");
assert.match(live,/server-only/);
assert.match(live,/VERCEL_ENV === "production"/);
assert.match(live,/AI_BILL_REPORTING_PRODUCTION_ENABLED !== "true"/, "production must fail closed without explicit enable flag");
assert.match(live,/ensureBillReportingAccess\(\)/, "server RPC must enforce production access gate");
assert.doesNotMatch(live,/export function ensurePreviewOnly/, "old blanket production block removed");
assert.match(live,/SUPABASE_SERVICE_ROLE_KEY/);
assert.match(live,/ai_bill_extraction_live_v1/);
assert.match(live,/read_ai_bill_analytics_v1/, "new analytics RPC used server-side");
assert.match(live,/analytics\.selected\?\.predictions !== value\.kpis\.bills/, "extended analytics reconcile with base KPIs");
assert.match(read("components/ai-services/ai-services-overview.tsx"),/Cost × latency by document type/, "document cost and latency diagnostics");
assert.match(read("components/ai-services/ai-services-overview.tsx"),/Cost and latency by page band/, "page band diagnostics");
assert.match(read("components/ai-services/ai-services-overview.tsx"),/AI spend MTD/, "month-to-date KPI");
assert.match(read("components/ai-services/ai-services-overview.tsx"),/Documents deleted/, "deleted status KPI");
assert.match(live,/knownCostCount \+ value.kpis.unknownCostCount/);
const rpc=read("supabase/migrations/20261101185848_ai_bill_extraction_live_read_v1_20261102.sql");
assert.match(rpc,/SECURITY DEFINER/);
assert.match(rpc,/SET search_path = ''/);
assert.match(rpc,/TO service_role/);
assert.match(rpc,/REVOKE ALL/);
assert.doesNotMatch(rpc,/UPDATE aia_infra\.|DELETE FROM aia_infra\.|INSERT INTO aia_infra\./);
assert.match(read("app/api/ai-services/report/route.ts"),/ensureBillReportingAccess/);

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
assert.match(overview,/debouncedSearch/,"global search scopes dashboard and evidence");
assert.match(overview, /<DistributionRows/, "document and review comparison charts remain visual");
assert.match(overview, /<LatencyComparison/, "latency compares P50 and P95 visually");
const aiCss = read("app/ai-services/ai-services.css");
assert.match(aiCss, /\.ai-shell \.ai-kpi-section[\s\S]*?grid-column: 1 \/ -1/, "KPI section spans all 12 columns");
assert.match(summary, /\(r\.extractionCost === null\) !== \(r\.enrichmentCost === null\)/, "partial cost component guard");
assert.match(overview, /MetricsInvestigationTable/, "investigation table primitive");
assert.match(overview, /const currency: "USD" = "USD"/, "USD money display policy is consistent throughout the UI");
assert.match(read("app/ai-services/ai-services.css"), /\.ai-shell \.ed-collection > \.ed-report\.report-card \{[\s\S]*?align-self: start;/, "paired chart cards do not stretch to tallest sibling");
assert.match(read("components/ai-services/bill-drills.tsx"), /fmtCost\(r\.knownTotalCost,currency\)/, "evidence table formats money via shared currency setting");
assert.match(overview, /formatRecordedCost\(total,currency,1\)/, "component chart headline formats money consistently");
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

console.log("AI Services live contract verified: protected production reader with explicit kill switch, source scope, paginated evidence and shared primitives.");
