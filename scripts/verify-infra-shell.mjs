import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { infraPreviewData as data } from "../lib/infra/preview-snapshot.ts";
import { completedPreset, resolveRange, validMonthRange, shiftMonth } from "../lib/infra/date-range.ts";
const read = path => readFileSync(new URL("../" + path, import.meta.url), "utf8");
const drawer = read("components/main-navigation-drawer.tsx");
const header = read("components/product-metrics-header.tsx");
const page = read("app/infra/page.tsx");
const loading = read("app/infra/loading.tsx");
const shell = read("components/infra/infra-overview.tsx");
const charts = read("components/infra/infra-charts.tsx");
const css = read("app/infra/infra.css");
const types = read("lib/infra/types.ts");
const source = read("lib/infra/preview-snapshot.ts");
const layout = read("app/metrics-page-grid.css");
const baseCss = read("app/delivery/delivery.css");
const picker = read("components/ui/product-month-range-picker.tsx");
const investigationTable = read("components/ui/metrics-investigation-table.tsx");
const engineeringEvidence = read("components/delivery/delivery-evidence-modal.tsx");
const engineeringCSS = read("app/delivery/delivery-investigation.css");
const productCss = read("app/prototype.css");

assert.match(drawer, /href="\/infra"/);
assert.match(header, /current === "infra"/);
assert.match(page, /<ProductMetricsHeader current="infra"/);
assert.match(page, /<InfraOverview data=\{infraPreviewData\}/);
for (const token of ["retention/retention.css", "metrics-page-grid.css", "delivery/delivery.css"]) assert.ok(page.includes(token));
for (const token of [
  "rd-page ed-page infra-page", "rd-page-head ed-page-head", "metrics-grid-section ed-section",
  "metrics-section-kicker ed-section-heading", "ed-sprint-kpis ed-kpi-grid po-kpis", "metric-card ed-metric",
  "report-card ed-report", "report-header ed-report-heading", "ed-collection", "MetricsInfoButton", "MetricsInfoDialog",
  "rd-modal rd-activation-modal ed-investigation-modal", "MetricsInvestigationTable", "ProductMonthRangePicker",
]) assert.ok(shell.includes(token), "Missing shared Product primitive: " + token);
assert.match(layout, /--metrics-page-max:1560px/);
assert.match(layout, /--metrics-page-gap:24px/);
assert.match(baseCss, /\.ed-kpi-grid\.po-kpis/);
for (const token of [".metric-card{", ".report-card{", ".rd-page{", ".app-header{", ".app-dashboard-trigger{", ".date-popover{"]) {
  assert.ok(!css.includes(token), "Infra must not redefine a shared component: " + token);
}

// The Product month-picker structure inherits the unchanged global design.
for (const token of ["date-popover", "date-popover-heading", "date-picker-body", "date-presets", "date-preset", "month-picker", "range-fields", "range-field", "month-grid", "month-button", "date-scope-note", "date-picker-footer", "date-trigger"]) {
  assert.ok(picker.includes(token) && productCss.includes("." + token), "Picker must reuse Product styles: " + token);
}
assert.match(picker, /id="date-range-popover"/);
assert.match(picker, /Point-in-time reporting/);
assert.match(picker, />Cancel<\/button>/);
assert.match(picker, />Apply<\/button>/);
assert.match(picker, /onApply\(draft\)/);
assert.match(picker, /setDraft\(value\)/, "Reopening resets uncommitted draft selections.");
assert.match(picker, /Presets use completed calendar months/);
assert.doesNotMatch(shell, /CompactMenuSelect|infra-preview-caption|Frozen audited|Source integrity|Data confidence|kind:\s*"health"/);
assert.doesNotMatch(loading, /Source integrity|Data confidence|Frozen audited/);
assert.match(shell, /previewDisclosure/);
assert.match(shell, /This preview is not a live billing feed/);
assert.match(shell, /note: previewDisclosure/, "Keep captured-data disclosure in metric information.");

const asOf = "2026-10-08T04:17:14Z";
assert.deepEqual(completedPreset("3", asOf), { preset: "3", start: "2026-07", end: "2026-09" });
assert.deepEqual(completedPreset("6", asOf), { preset: "6", start: "2026-04", end: "2026-09" });
assert.deepEqual(completedPreset("12", asOf), { preset: "12", start: "2025-10", end: "2026-09" });
assert.equal(shiftMonth("2026-01", -1), "2025-12");
const months = data.awsMonths.map(m => m.month);
assert.deepEqual(resolveRange(completedPreset("lifetime", asOf), months), { start: "2026-01", end: "2026-10" });
assert.deepEqual(resolveRange({ preset: "custom", start: "2026-07", end: "2026-08" }, months), { start: "2026-07", end: "2026-08" });
assert.deepEqual(resolveRange({ preset: "custom", start: "2026-09", end: "2026-09" }, months), { start: "2026-09", end: "2026-09" });
assert.equal(validMonthRange({ preset: "custom", start: "2026-09", end: "2026-08" }, "2026-10"), false);
assert.equal(validMonthRange({ preset: "custom", start: "2026-09", end: "2026-11" }, "2026-10"), false);
assert.equal(validMonthRange({ preset: "custom", start: null, end: "2026-09" }, "2026-10"), false);
assert.match(shell, /const month = scope.end/);
assert.match(shell, /m.month >= scope.start && m.month <= scope.end/);
assert.match(shell, /setDrill\(null\); setInfo\(null\); setRange\(next\)/);
assert.match(shell, /month: selectedMonth/, "Chart drill must stay tied to the selected point, not a different global month.");

// Both breakdowns use one component, matching row count and dimensions.
assert.equal((charts.match(/<CostBreakdownTable /g) || []).length, 2);
assert.match(charts, /slice\(0, 7\)/);
assert.match(charts, /total - shown.reduce/);
assert.match(charts, /amount \/ total \* 100/);
assert.match(charts, /<tfoot>/);
assert.match(css, /tbody tr\{height:44px\}/);
assert.match(charts, /ResizeObserver/);
assert.match(charts, /getBoundingClientRect\(\).width/);
assert.match(css, /height:270px;max-height:none/);
assert.doesNotMatch(charts + shell, /↗/);
for (const component of ["AwsSpendTrend", "ServiceDrivers", "AccountDistribution"]) assert.ok(charts.includes("function " + component));
assert.match(charts, /Service breakdowns in this preview begin in May 2026/);
assert.match(charts, /Account breakdowns in this preview begin in May 2026/);
assert.match(shell, /Only the month total is captured before May 2026/);

// Existing AWS capture and arithmetic are unchanged.
assert.equal(data.mode, "audited-preview-snapshot");
assert.equal(data.awsMonths.length, 10);
assert.equal(data.awsServices.length, 66);
assert.equal(data.awsAccounts.length, 54);
assert.equal(data.awsMonths.find(x => x.month === "2026-09")?.usd, 4016.56);
assert.equal(data.awsMonths.find(x => x.month === "2026-10")?.estimated, true);
assert.equal(data.awsRun.rows, 11966);
assert.ok(Math.abs(data.awsRun.referenceUsd - data.awsRun.storedDetailUsd) < .05);
assert.ok(data.awsAccounts.every(x => /^Account \d{2}$/.test(x.label)));
for (const month of data.awsMonths) {
  assert.ok(month.usd >= 0 && month.accounts > 0 && month.services > 0);
  for (const rows of [data.awsServices, data.awsAccounts]) {
    const shown = rows.filter(x => x.month === month.month).sort((a, b) => b.usd - a.usd).slice(0, 7);
    const sum = shown.reduce((s, r) => s + r.usd, 0);
    assert.ok(sum <= month.usd + .06);
    assert.ok(Math.abs(sum + Math.max(0, month.usd - sum) - month.usd) < .06);
  }
}
const forbidden = /bill.?processing|bill.?cost|billMonths|billAsOf|billDays|docTypes|BillVolumeEconomics|CostComposition|DocumentTypes|DailyBillVolume|enrichment_cost|extraction_cost/i;
for (const [name, content] of Object.entries({ page, loading, shell, charts, css, types, source })) assert.doesNotMatch(content, forbidden, "Separate module leaked into Infra: " + name);
assert.doesNotMatch(charts, /InfraBillMonth|InfraDocType|InfraBillDay/);
assert.ok(!("billMonths" in data) && !("billAsOf" in data) && !("docTypes" in data) && !("billDays" in data));
assert.doesNotMatch(source, /AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|SUPABASE_SERVICE_ROLE_KEY|company_uuid|prediction_uuid|\b[0-9]{12}\b/);
assert.doesNotMatch(page, /read_jira_delivery|readPublishedOverview|fetch\(|postgres\(|service_role/);
// Every AWS spend, category, account, service-history and account-history
// drill calls this one reusable component. Its markup and sizing inherit the
// exact Product / Engineering table style classes, not the former Jira
// evidence-table widths.
assert.match(page,/delivery\/delivery-investigation\.css/);
assert.match(engineeringEvidence,/className="rd-modal rd-activation-modal ed-investigation-modal"/);
assert.match(engineeringEvidence,/className="rd-table-wrap ed-investigation-table-wrap"/);
assert.match(engineeringEvidence,/className="rd-activation-table ed-investigation-table"/);
for(const cssName of [".ed-investigation-table.rd-activation-table",".ed-investigation-table-wrap.rd-table-wrap"]) {
  assert.ok(engineeringCSS.includes(cssName),"Missing approved Engineering table CSS "+cssName);
}
for(const token of [
  "rd-table-wrap ed-investigation-table-wrap","rd-activation-table ed-investigation-table",
  "ed-investigation-row","ed-investigation-key","infra-drill-align-right",
  "Full month total","rd-drill-toolbar ed-investigation-toolbar",
  "ed-investigation-caption"
]) {
  assert.ok((shell+investigationTable).includes(token),"Missing Product / Engineering modal primitive "+token);
}
assert.match(shell,/type DrillKind = "aws-month" \| "services" \| "service" \| "accounts" \| "account"/);
assert.match(shell,/target.kind === "aws-month" \|\| target.kind === "services"/);
assert.match(shell,/target.kind === "accounts"/);
assert.match(shell,/target.kind === "service"/);
assert.match(shell,/isMonthlyBreakdown && rows.length && aws/);
assert.match(shell,/query\.trim\(\)\.toLocaleLowerCase/);
assert.match(shell,/setQuery\("+"\)/);
assert.match(shell,/fullTotal=\{monthlyTotal\}/);
assert.match(investigationTable,/role="region" tabIndex=\{0\}/);
assert.match(investigationTable,/aria-label=\{ariaLabel\}/);
assert.match(investigationTable,/onClick=\{row\.onOpen\}/);
assert.match(css,/infra-drill-table thead th:first-child\{width:55%/);
assert.match(css,/infra-drill-table \.ed-investigation-row>td\.infra-drill-align-right/);
assert.doesNotMatch(shell,/ed-evidence-table-shell|ed-report-table ed-evidence-table/);
assert.doesNotMatch(css,/infra-drill-dialog \.ed-evidence-table/);
// The Product table's th:first-child has zero padding / 38px width. Infra's
// total label must explicitly override both, including on the bottom row.
assert.match(css,/\.infra-drill-table\.rd-activation-table tfoot th:first-child\{/);
assert.match(css,/width:55%;padding:0 18px 0 16px!important;text-align:left!important/);
assert.doesNotMatch(css,/\.infra-drill-foot/);
assert.doesNotMatch(shell,/rd-modal-foot|rd-table-summary|infra-drill-foot/);
assert.doesNotMatch(shell,/displayed ·|source rows/);
assert.doesNotMatch(shell,/The preview itemizes the eleven largest categories/);
assert.doesNotMatch(shell,/A dash indicates detail outside the captured monthly top categories/);
assert.doesNotMatch(shell,/<footer\b/);
assert.match(investigationTable,/<tfoot>/);
assert.match(investigationTable,/fullTotal\.label/);
console.log("Infra modal cleanup verified: no footer notes; aligned first-column monthly totals.");
console.log("Infra drill modal table verified: Product / Engineering shared primitives, five targets, search, cost alignment and totals.");
console.log("Infra validated: Product date picker, completed-month presets, exact scope, shared breakdown table, responsive chart width, removed source panel and banner, unchanged AWS data.");
