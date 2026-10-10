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
const overviewCards = read("components/overview/overview-kpi-strip.tsx");
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
assert.match(shell,/className="ed-sprint-kpis ed-kpi-grid po-kpis"/);
assert.match(shell,/className="ed-attention-kpis ed-kpi-grid po-kpis"/);
assert.match(shell,/className="ed-quality-kpis ed-kpi-grid po-kpis"/);
assert.match(css,/\.ed-kpi-grid\.po-kpis\{/);
assert.match(css,/grid-template-columns:repeat\(12,minmax\(0,1fr\)\)/);
assert.match(css,/\.ed-sprint-kpis\.ed-kpi-grid>\.ed-metric-wrap\{grid-column:span 3\}/);
assert.match(css,/\.ed-attention-kpis\.ed-kpi-grid\{grid-template-columns:repeat\(5,minmax\(0,1fr\)\)\}/);
assert.match(css,/\.ed-quality-kpis\.ed-kpi-grid>\.ed-metric-wrap\{grid-column:span 4\}/);
assert.doesNotMatch(shell,/highlighted(?:\?|:)|ed-metric-featured/,
  "No Engineering KPI should ship in a permanently highlighted hover-like state.");
assert.doesNotMatch(css,/ed-metric-featured|background:#f5f7ff/,
  "Product KPI backgrounds must be neutral by default.");
assert.match(css,/height:100%;min-height:136px;padding:15px 19px/,
  "KPI cards should be compact and allow their grid row to grow for wrapped notes.");
assert.match(css,/height:100%;min-height:134px;padding:15px 16px/,
  "Mobile KPI cards should not retain the old 158px minimum.");

for(const shared of [
  'className="po-kpi-divider"',
  'className="metric-label"',
  'className="metric-period"',
  'className="metric-value"',
  'className={"metric-note"',
]) assert.ok(shell.includes(shared),"Missing shared Product Overview KPI primitive "+shared);
assert.doesNotMatch(css,/ed-metric-readout|ed-five-kpis|ed-metric-caption|ed-metric-label/,
  "Do not copy Product card styling into a smaller grey Engineering lookalike.");
assert.match(css,/bottom:12px/,"Metric info icons must match Product's bottom-right position.");
assert.match(css,/\.ed-collection\{/);
assert.match(shell,/function WorkInFlight\(/);
assert.match(shell,/const total=data.flow.flow_counts.open_total/);
assert.match(shell,/const blocked=data.flow.flow_counts.blocked_all/);
assert.match(shell,/const rows=\[\.\.\.data.flow.wip_by_status\]/);
assert.match(shell,/className="ed-wip-list" role="list"/);
assert.match(shell,/key:"status:"\+status/);
assert.match(shell,/row.issue_count\/largest\*100/,
  "Relative volume must be proportional to source counts.");
assert.match(shell,/row.pct/,
  "Shares must come from the audited source, not invented chart values.");
assert.match(css,/\.ed-wip-distribution\{/);
assert.match(css,/\.ed-wip-entry:focus-visible\{/);

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
  "BacklogTrend","BugAging","DefinitionDialog","FilterBar",
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
assert.match(api,/readDeliveryEvidence\(filters,key,snapshot,offset,limit,query/);
const cohortV2 = read("supabase/migrations/20261011_jira_delivery_investigation_v2.sql");
const issueSQL = cohortV2;
const modal = read("components/delivery/delivery-evidence-modal.tsx");
const issueModal = read("components/delivery/delivery-issue-detail-modal.tsx");
const modalCss = read("app/delivery/delivery-investigation.css");
const issueRoute = read("app/api/delivery/issue/route.ts");
assert.match(page,/delivery-investigation.css/);
assert.match(shell,/<DeliveryEvidenceModal target=\{drill\}/);
assert.match(modal,/className="rd-modal rd-activation-modal ed-investigation-modal"/);
assert.match(modal,/className="rd-modal-head ed-investigation-head"/);
assert.match(modal,/className="rd-drill-toolbar ed-investigation-toolbar"/);
assert.match(modal,/className="rd-table-wrap ed-investigation-table-wrap"/);
assert.match(modal,/className="rd-activation-table ed-investigation-table"/);
assert.match(modal,/className="rd-modal-foot rd-modal-foot-paginated ed-investigation-foot"/);
assert.match(modal,/className="rd-pagination"/);
assert.match(modal,/className="rd-expander ed-investigation-expander"/);
assert.match(modal,/className="rd-search ed-investigation-search"/);
assert.match(modal,/className="ed-investigation-row-detail"/);
assert.match(modal,/ed-investigation-field-grid/);
assert.match(modal,/DeliveryIssueDetailModal/);
assert.match(modal,/const size=10/);
assert.match(modal,/Export CSV/);
assert.match(modal,/evidence_request_failed/);
assert.match(server,/read_jira_delivery_evidence_v2/);
assert.match(server,/read_jira_delivery_issue_v1/);
assert.match(issueModal,/Back to issues/);
assert.match(issueModal,/Status trail/);
assert.match(issueModal,/service_levels/);
assert.match(modalCss,/\.ed-investigation-modal/);
assert.match(modalCss,/\.ed-secondary-overlay/);
assert.match(cohortV2,/v_last_run IS DISTINCT FROM v_published/);
assert.match(cohortV2,/jira_delivery_stage_evidence_parity_mismatch/);
assert.match(cohortV2,/row_number\(\) OVER/);
assert.match(server,/jira_delivery_issue_outside_cohort/);
assert.match(issueSQL,/jira_issue_snapshot_mismatch/);
assert.match(issueRoute,/readDeliveryIssue/);
assert.doesNotMatch(modal,/<select\b|Querying the published Jira snapshot/);

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
assert.match(shell,/function BacklogTrend\(/);
assert.match(shell,/id="ed-backlog-area"/);
assert.match(shell,/role="tooltip"/);
assert.match(shell,/aria-label=\{"Weekly open backlog across "/);
assert.match(shell,/event.key==="ArrowLeft"/);
assert.match(shell,/onMouseEnter=\{\(\)=>setActive\(index\)\}/);
assert.match(shell,/data.flow.backlog_trend/);
assert.match(shell,/data.flow.bug_health.age_histogram/);
assert.match(shell,/function BugAging\(/);
assert.match(shell,/ed-aging-tooltip/);
assert.match(css,/\.ed-chart-tooltip\{/);
assert.match(css,/\.ed-trend-plot:focus-visible\{/);
assert.match(css,/\.ed-aging-row:focus-visible\{/);
assert.doesNotMatch(shell,/ed-trend-wrap|ed-status-table|ed-share-track/,
  "The old chart and legacy Work-in-flight table must not return.");
assert.match(page,/export const maxDuration = 45/);
assert.match(overviewCards,/className="metric-card"/,
  "Product Overview remains the reference for full-card drill triggers.");
assert.match(shell,/function MetricTile\(/);
assert.match(shell,/return <div className="ed-metric-wrap">/);
assert.match(modal,/value\?\.label\|\|target.label/,"Cohort title must follow published Jira definition.");
assert.match(modal,/<p>Jira issues<\/p>/,
  "Modal eyebrow is simply Jira issues, without a sync number.");
assert.match(modal,/value&&pageCount>1\?<footer/,
  "Retain numeric pagination for multipage issue lists.");
assert.match(modal,/\{row\.issue_key\}<\/button>/,
  "Plain SPEND ID button must still open the secondary investigation.");
assert.doesNotMatch(modal,/className="ed-investigation-summary"|Cohort issues|Published sync|Published snapshot|Distinct Jira issues/,
  "No redundant cohort/snapshot metadata in the primary modal.");
assert.doesNotMatch(issueModal,/Back to cohort|Verified against Jira snapshot/,
  "No internal metadata in secondary issue detail.");
assert.doesNotMatch(modal,/\{row\.issue_key\} ↗/,
  "No extra diagonal stroke beside Jira issue keys.");
assert.doesNotMatch(shell,/ed-wip-entry-arrow|aria-hidden="true">↗/,
  "No decorative links next to Engineering issue counts.");
assert.doesNotMatch(modalCss,/\.ed-investigation-summary\{/,
  "No stale CSS for the removed three-cell summary panel.");
assert.match(css,/\.ed-aging-chart\{[^}]*flex:1 1 auto;gap:8px;grid-auto-rows:minmax\(44px,1fr\)/,
  "Aging bands must fill the chart card, not leave a blank bottom.");

assert.match(modal,/aria-hidden=\{!!detailKey\}/,"Primary modal must hide from accessibility tree while issue detail is open.");
assert.match(issueModal,/querySelectorAll<HTMLElement>/,"Secondary investigation must contain keyboard focus.");
assert.match(modalCss,/\.ed-investigation-foot\.rd-modal-foot\{[\s\S]*?justify-content:center/,
  "Product-style numbered pagination stays centered without debug metadata.");
assert.match(modalCss,/\.ed-investigation-foot \.rd-pagination\{/);
assert.match(modal,/function EvidenceSkeleton\(/);
assert.match(modal,/loading\?<EvidenceSkeleton review=\{target.key==="stage:Code Review"\}\/>/);
assert.match(issueModal,/ed-issue-loading/);
assert.match(modalCss,/\.ed-investigation-skeleton/);
assert.doesNotMatch(shell,/function EvidenceDialog|function EvidenceTableSkeleton/);
assert.doesNotMatch(modal,/Querying the published Jira snapshot|Loading issue evidence…/);
assert.match(shell,/className="metric-card ed-metric"/);
assert.match(shell,/onClick=\{openCard\}/);
assert.match(shell,/aria-haspopup="dialog"/);
assert.match(shell,/<InfoIcon label=\{metric.label\} onClick=\{\(\)=>onInfo\(metric\)\}\/>/);
assert.match(shell,/import CompactMenuSelect from "..\/ui\/compact-menu-select"/);
assert.equal((shell.match(/<CompactMenuSelect\b/g)||[]).length,5,
  "Every Jira filter must reuse the Product/Retention custom dropdown.");
assert.doesNotMatch(shell,/<select\b|<option\b/,
  "Native browser dropdowns are not accepted in Engineering filters.");
for (const key of ["sprint","module","sub_module","severity","assignee"]) {
  assert.ok(shell.includes('onChange={value=>applyFilter("'+key+'",value)}'),
    "Custom filter must apply immediately and preserve the current URL: " + key);
}
assert.match(css,/\.ed-delivery-filter-select \.compact-menu-select-menu\{/);
assert.match(css,/max-height:min\(295px,calc\(100dvh - 135px\)\)/,
  "Long module and assignee lists must scroll inside the Product dropdown.");
assert.match(shell,/router.replace\("\/delivery"\+/,
  "Selecting a filter must navigate immediately.");
assert.match(shell,/className="ed-reset">Reset<\/a>/);
assert.doesNotMatch(shell,/ed-drill-link|ed-metric-bottom|className="ed-apply"|>Clear<\/a>|ed-reference-badge|ed-historical-warning|Published sync \{data.snapshot_id\}/);
assert.doesNotMatch(css,/\.ed-apply\b|\.ed-clear\b|\.ed-reference-badge\b|\.ed-historical-warning\b|\.ed-drill-link\b/);
assert.match(css,/\.ed-metric\.metric-card:focus-visible/);
assert.match(sql,/REVOKE ALL ON FUNCTION public\.read_jira_delivery_dashboard_v1/);
assert.match(evidence,/jira_delivery_evidence_snapshot_mismatch/);
assert.match(evidence,/REVOKE ALL ON FUNCTION public\.read_jira_delivery_evidence_v1/);
assert.match(header,/isDelivery \? "Engineering Metrics" : "Product Metrics"/);
assert.match(drawer,/href="\/delivery"/);
assert.doesNotMatch(shell,/Visual reference only|Reference snapshot|drill pending|mockKpis|fixtureData|not live data|SPEND Sprint 50.*41\.9%/i,
  "No screenshot figures or placeholder copy allowed in the verified dashboard.");
console.log("Live Engineering & Delivery contract verified: 15 metrics, 6 reports, 5 filters, secured SSR + paginated evidence, shared Product grid.");
