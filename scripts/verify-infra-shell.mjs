import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { infraPreviewData as data } from "../lib/infra/preview-snapshot.ts";

const read=path=>readFileSync(new URL("../"+path,import.meta.url),"utf8");
const drawer=read("components/main-navigation-drawer.tsx");
const header=read("components/product-metrics-header.tsx");
const page=read("app/infra/page.tsx");
const loading=read("app/infra/loading.tsx");
const shell=read("components/infra/infra-overview.tsx");
const charts=read("components/infra/infra-charts.tsx");
const css=read("app/infra/infra.css");
const types=read("lib/infra/types.ts");
const source=read("lib/infra/preview-snapshot.ts");
const layout=read("app/metrics-page-grid.css");
const baseCss=read("app/delivery/delivery.css");
const info=read("components/ui/metrics-info.tsx");

assert.match(drawer,/href="\/infra"/);
assert.match(drawer,/onInfra \? " is-current" : ""/);
assert.match(header,/current === "infra"/);
assert.match(header,/Infrastructure Overview/);
assert.match(header,/href:"\/infra"/);
assert.match(page,/<ProductMetricsHeader current="infra"/);
assert.match(page,/<InfraOverview data=\{infraPreviewData\}/);
for(const token of ["retention/retention.css","metrics-page-grid.css","delivery/delivery.css"]) {
  assert.ok(page.includes(token),"Missing shared styles: "+token);
}
for(const token of [
  "rd-page ed-page infra-page","rd-page-head ed-page-head",
  "metrics-grid-section ed-section","metrics-section-kicker ed-section-heading",
  "ed-sprint-kpis ed-kpi-grid po-kpis","metric-card ed-metric",
  "report-card ed-report","report-header ed-report-heading","ed-collection",
  "CompactMenuSelect","MetricsInfoButton","MetricsInfoDialog",
  "ed-evidence-dialog","ed-evidence-table-shell","ed-report-table",
])assert.ok(shell.includes(token),"Infra must reuse approved Product primitive: "+token);
assert.match(layout,/--metrics-page-max:1560px/);
assert.match(layout,/--metrics-page-gap:24px/);
assert.match(baseCss,/\.ed-kpi-grid\.po-kpis/);
for(const token of [
  ".metric-card{",".report-card{",".rd-page{",".ed-kpi-grid.po-kpis{",
  ".app-header{",".app-dashboard-trigger{",
])assert.ok(!css.includes(token),"Infra must not redefine shared styles: "+token);
for(const component of ["AwsSpendTrend","ServiceDrivers","AccountDistribution"]) {
  assert.ok(charts.includes("function "+component),"Missing AWS chart: "+component);
}
assert.match(shell,/onSelect=\{setMonth\}/);
assert.match(shell,/onSelect=\{key=>openDrill/);
assert.match(info,/sectionLabel = "Product Metrics"/);
assert.match(shell,/Frozen audited AWS cost preview · Not live/,
  "Captured Infra data must never be presented as live.");
assert.match(shell,/data\.awsMonths\.slice\(\)\.reverse\(\)/,
  "Every displayed AWS chart point must be selectable.");
assert.match(charts,/Service breakdowns in this preview begin in May 2026/);
assert.match(charts,/Account breakdowns in this preview begin in May 2026/);
assert.match(shell,/Only the month total is captured before May 2026/);
assert.equal(data.mode,"audited-preview-snapshot");
assert.equal(data.awsMonths.length,10);
assert.equal(data.awsServices.length,66);
assert.equal(data.awsAccounts.length,54);
assert.equal(data.awsMonths.find(x=>x.month==="2026-09")?.usd,4016.56);
assert.equal(data.awsMonths.find(x=>x.month==="2026-10")?.estimated,true);
assert.equal(data.awsRun.rows,11966);
assert.ok(Math.abs(data.awsRun.referenceUsd-data.awsRun.storedDetailUsd)<.05);
assert.ok(data.awsAccounts.every(x=>/^Account \d{2}$/.test(x.label)));
assert.ok(data.awsServices.every(x=>Number.isFinite(x.usd)));
for(const month of data.awsMonths){
  assert.ok(month.usd>=0&&month.accounts>0&&month.services>0);
  const top=data.awsServices.filter(x=>x.month===month.month);
  assert.ok(top.reduce((sum,row)=>sum+row.usd,0)<=month.usd+.06);
}
// Bill Processing Economics is a separate module. No related code or data
// may ship in the Infra source, even hidden inside its preview snapshot.
const forbidden=/bill.?processing|bill.?cost|billMonths|billAsOf|billDays|docTypes|BillVolumeEconomics|CostComposition|DocumentTypes|DailyBillVolume|enrichment_cost|extraction_cost/i;
for(const [name,content] of Object.entries({page,loading,shell,charts,css,types,source})){
  assert.doesNotMatch(content,forbidden,
    "Removed Bill Processing module leaked into Infra: "+name);
}
assert.ok(!("billMonths" in data)&&!("billAsOf" in data)&&
  !("docTypes" in data)&&!("billDays" in data),
  "Infra preview payload must carry AWS-only data.");
assert.doesNotMatch(source,/AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|SUPABASE_SERVICE_ROLE_KEY|company_uuid|prediction_uuid|\b[0-9]{12}\b/);
assert.doesNotMatch(page,/read_jira_delivery|readPublishedOverview|fetch\(|postgres\(|service_role/);

console.log("Infra AWS-only preview verified: shared Product design, monthly source parity, interactive AWS drills; Bill Processing removed.");
