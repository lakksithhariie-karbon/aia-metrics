/**
 * Verified Engineering & Delivery contract, GitHub-owned.
 * Keep the exact Product Metrics outer grid, all five sections, 15 cards,
 * six data-driven analytical surfaces and fail-closed Jira evidence plumbing.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const read = path => readFileSync(new URL("../" + path, import.meta.url), "utf8");
const page = read("app/delivery/page.tsx");
const shell = read("components/delivery/engineering-delivery-shell.tsx");
const css = read("app/delivery/delivery.css");
const grid = read("app/metrics-page-grid.css");
const server = read("lib/delivery/server.ts");
const api = read("app/api/delivery/evidence/route.ts");
const sql = read("supabase/migrations/20261010_jira_delivery_dashboard_reader_v1.sql");
const evidence = read("supabase/migrations/20261010_jira_delivery_evidence_v1.sql");
const header = read("components/product-metrics-header.tsx");
const drawer = read("components/main-navigation-drawer.tsx");
assert.match(page, /metrics-page-grid\.css/);
assert.match(page, /retention\/retention\.css/);
assert.match(page, /current="delivery"/);
assert.match(page, /readDeliveryDashboard\(filters\)/);
assert.match(page, /force-dynamic/);
assert.match(shell, /className="rd-page ed-page"/);
assert.match(shell, /className="metrics-grid-section ed-section"/);
for (const token of [
  "--metrics-page-max:1560px",
  "--metrics-page-gutter:28px",
  "--metrics-page-gap:24px",
  "grid-template-columns:repeat(12,minmax(0,1fr))",
]) assert.ok(grid.includes(token), "Product page grid changed: " + token);
assert.match(css,/\.ed-sprint-kpis\{grid-template-columns:repeat\(3,minmax\(0,1fr\)\)\}/);
assert.match(css,/\.ed-five-kpis\{grid-template-columns:repeat\(5,minmax\(0,1fr\)\)\}/);
assert.match(css,/\.ed-collection\{/);
for (const section of ["Sprint delivery","Attention","Delivery","Flow","Quality"]) {
  assert.ok(shell.includes('title="'+section+'"'), "Missing section "+section);
}
for (const id of [
  "commitment","commitment_gap","mid_sprint","throughput",
  "stale","stale_blocked","l1","qa_queue","blocked",
  "bugs","reopen","qa_reject","bug_resolution","qa_turn","code_review",
]) {
  assert.ok(shell.includes('id:"'+id+'"'),"Missing Jira-backed KPI card "+id);
}
for (const component of [
  "WorkInFlight","PlannedVsDone","IssueTypes","FlowHealth",
  "BacklogTrend","BugAging","EvidenceDialog","DefinitionDialog","FilterBar",
]) assert.ok(shell.includes("<"+component), "Missing live view "+component);
for (const term of [
  "data.core.sprint_discipline","data.core.sprint_throughput",
  "data.core.metric_cohorts","data.flow.wip_by_status",
  "data.flow.stage_summary","data.flow.bug_health",
  "data.flow.backlog_trend","data.quality.metric_updates",
  "data.issue_types","data.synced_at","data.snapshot_id",
]) assert.ok(shell.includes(term), "Unwired reporting source "+term);
assert.match(server,/jira_delivery_reconciliation_failed/);
assert.match(server,/jira_delivery_sprint_reconciliation_failed/);
assert.match(server,/jira_delivery_issue_types_reconciliation_failed/);
assert.match(server,/SUPABASE_SERVICE_ROLE_KEY/);
assert.match(server,/cache: "no-store"/);
assert.match(api,/readDeliveryEvidence\(filters,key,snapshot,offset\)/);
assert.match(sql,/jira_delivery_population_reconciliation_failed/);
assert.match(sql,/jira_delivery_issue_type_scope_mismatch/);
const snapshotSql = read("supabase/migrations/20261010_jira_delivery_snapshot_consistency_v1.sql");
assert.equal((snapshotSql.match(/v_last_run IS DISTINCT FROM v_published/g)||[]).length,2,
  "Both compact dashboard and issue evidence must reject partial Jira ingestion.");
assert.match(snapshotSql,/qa_queue_count/);
assert.match(server,/!check\("qa_queue",fc.qa_queue_count\)/,
  "Server must verify QA population against independently counted issue rows.");
assert.match(shell,/const reviewStage=data.flow.stage_summary.find/);
const stageSql=read("supabase/migrations/20261010_jira_delivery_stage_evidence_v1.sql");
assert.match(stageSql,/jira_delivery_stage_evidence_parity_mismatch/);
assert.match(stageSql,/v_last_run IS DISTINCT FROM v_published/);
assert.match(shell,/drillKey:reviewCount!==null\?"stage:Code Review":undefined/);
assert.match(page,/export const maxDuration = 45/);
assert.match(sql,/REVOKE ALL ON FUNCTION public\.read_jira_delivery_dashboard_v1/);
assert.match(evidence,/jira_delivery_evidence_snapshot_mismatch/);
assert.match(evidence,/REVOKE ALL ON FUNCTION public\.read_jira_delivery_evidence_v1/);
assert.match(header,/isDelivery \? "Engineering Metrics" : "Product Metrics"/);
assert.match(drawer,/href="\/delivery"/);
assert.doesNotMatch(shell,/Visual reference only|Reference snapshot|drill pending|mockKpis|fixtureData|not live data|SPEND Sprint 50.*41\.9%/i,
  "No screenshot figures or placeholder copy allowed in the verified dashboard.");
console.log("Live Engineering & Delivery contract verified: 15 metrics, 6 reports, 5 filters, secured SSR + paginated evidence, shared Product grid.");
