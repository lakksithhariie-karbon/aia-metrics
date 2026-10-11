import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { infraPreviewData as data } from "../lib/infra/preview-snapshot.ts";
const read=path=>readFileSync(new URL("../"+path,import.meta.url),"utf8");
const drawer=read("components/main-navigation-drawer.tsx");
const header=read("components/product-metrics-header.tsx");
const page=read("app/infra/page.tsx");
const shell=read("components/infra/infra-overview.tsx");
const charts=read("components/infra/infra-charts.tsx");
const css=read("app/infra/infra.css");
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
for (const token of ["retention/retention.css","metrics-page-grid.css","delivery/delivery.css"]) {
  assert.ok(page.includes(token),"Missing unchanged shared Product / Engineering styles: "+token);
}
for (const token of [
  "rd-page ed-page infra-page","rd-page-head ed-page-head",
  "metrics-grid-section ed-section","metrics-section-kicker ed-section-heading",
  "ed-sprint-kpis ed-kpi-grid po-kpis","metric-card ed-metric",
  "report-card ed-report","report-header ed-report-heading","ed-collection",
  "CompactMenuSelect","MetricsInfoButton","MetricsInfoDialog",
  "ed-evidence-dialog","ed-evidence-table-shell","ed-report-table",
])assert.ok(shell.includes(token),"Infra must reuse shared UI primitive: "+token);
assert.match(layout,/--metrics-page-max:1560px/);
assert.match(layout,/--metrics-page-gap:24px/);
assert.match(baseCss,/\.ed-kpi-grid\.po-kpis/);
for(const text of [
  ".metric-card{",".report-card{",".rd-page{",".ed-kpi-grid.po-kpis{",
  ".app-header{",".app-dashboard-trigger{",
])assert.ok(!css.includes(text),"Infra must not redefine global component styles: "+text);
for(const component of [
  "AwsSpendTrend","ServiceDrivers","AccountDistribution",
  "BillVolumeEconomics","CostComposition","DocumentTypes","DailyBillVolume",
])assert.ok(charts.includes("function "+component),"Missing interactive audited chart: "+component);
assert.match(shell,/onSelect=\{setMonth\}/);
assert.match(shell,/onSelect=\{key=>openDrill/);
assert.match(info,/sectionLabel = "Product Metrics"/);
assert.equal(data.mode,"audited-preview-snapshot");
assert.equal(data.awsMonths.find(x=>x.month==="2026-09")?.usd,4016.56);
assert.equal(data.awsMonths.find(x=>x.month==="2026-10")?.estimated,true);
assert.equal(data.billMonths.find(x=>x.month==="2026-09")?.docs,14201);
assert.equal(data.billMonths.find(x=>x.month==="2026-09")?.incomplete,20);
assert.equal(data.awsRun.rows,11966);
assert.ok(Math.abs(data.awsRun.referenceUsd-data.awsRun.storedDetailUsd)<.05);
assert.equal(data.awsAccounts.length,54);
assert.ok(data.awsAccounts.every(x=>/^Account \d{2}$/.test(x.label)));
assert.ok(data.awsServices.every(x=>Number.isFinite(x.usd)));
for(const m of data.billMonths){
 assert.equal(m.measured+m.incomplete,m.docs);
 const byType=data.docTypes.filter(x=>x.month===m.month);
 assert.equal(byType.reduce((sum,r)=>sum+r.docs,0),m.docs);
 assert.ok(Math.abs(byType.reduce((sum,r)=>sum+r.total,0)-m.total)<.02);
 assert.ok(Math.abs(m.extraction+m.enrichment-m.total)<.02);
}
for(const m of data.awsMonths){
 assert.ok(m.usd>=0&&m.accounts>=1&&m.services>=1);
 const top=data.awsServices.filter(x=>x.month===m.month);
 assert.ok(top.reduce((sum,row)=>sum+row.usd,0)<=m.usd+.06);
}
const dataSource=read("lib/infra/preview-snapshot.ts");
assert.doesNotMatch(dataSource,/AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|SUPABASE_SERVICE_ROLE_KEY|company_uuid|prediction_uuid|\b[0-9]{12}\b/);
assert.doesNotMatch(page,/read_jira_delivery|readPublishedOverview|fetch\(|postgres\(|service_role/);
console.log("Infra preview verified: exact shared Product/Engineering design primitives, anonymized audit data, monthly reconciliation and interactive cost drills.");
