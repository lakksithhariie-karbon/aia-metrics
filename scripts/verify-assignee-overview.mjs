import assert from "node:assert/strict";
import { resetAssigneeToolbarFilters } from "../lib/delivery/assignee-filter-url.ts";
import { readFileSync } from "node:fs";
const read=(path)=>readFileSync(new URL("../"+path,import.meta.url),"utf8");
const table=read("components/delivery/assignee-overview-table.tsx");
const header=read("components/product-metrics-header.tsx");
const matrix=read("lib/delivery/assignee-matrix.ts");
const server=read("lib/delivery/server.ts");
const types=read("lib/delivery/types.ts");
const issueApi=read("app/api/delivery/issue/route.ts");
const evidenceApi=read("app/api/delivery/evidence/route.ts");
const evidenceModal=read("components/delivery/delivery-evidence-modal.tsx");
const issueModal=read("components/delivery/delivery-issue-detail-modal.tsx");
const prefetch=read("components/delivery/evidence-prefetch.ts");
const page=read("app/delivery/assignees/page.tsx");
const loading=read("app/delivery/assignees/loading.tsx");
const css=read("app/delivery/assignees/assignees.css");
const customerCss=read("app/customer/customer.css");
assert.match(page,/readAssigneeMatrix\(filters\)/);
assert.match(page,/customer\/customer.css/);
assert.match(page,/metrics-page-grid.css/);
assert.match(page,/deliveryView="assignees"/);
assert.match(header,/Engineering Overview/);
assert.match(header,/Assignee Overview/);
assert.match(header,/href:"\/delivery\/assignees"/);
assert.match(header,/DropdownMenuLinkItem/);
assert.match(header,/deliveryView\?:DeliveryView/);
assert.match(table,/className="companies-page assignee-page"/);
assert.match(table,/className="companies-records po-record-layout companies-monthly-records companies-grid-card"/);
assert.match(table,/className="po-record-toolbar companies-command-bar"/);
assert.match(table,/className="po-record-scroll companies-monthly-scroll"/);
assert.match(table,/className="po-user-table companies-table companies-monthly-table assignee-monthly-table"/);
assert.match(table,/className="companies-month-header"/);
assert.match(table,/className="companies-module-header"/);
assert.match(table,/className="companies-frozen-header-spacer"/);
assert.match(table,/className="companies-expander-cell"/);
assert.match(table,/className=\{"companies-module-button"\+/);
assert.match(table,/className="companies-nested-user-row"/);
assert.match(table,/className="companies-total-row"/);
assert.match(table,/setExpanded/);
assert.match(table,/cell\(row,type,"__all__",type.type\)/,
  "Expanded issue type Open cell must drill that issue type only.");
assert.doesNotMatch(table,/\.props\.children/);
assert.match(table,/UNTAGGED_MODULE/);
assert.match(table,/__other__/);
assert.match(table,/featuredKeys/);
assert.match(table,/matrixScope/);
assert.match(table,/expectedCount:n/);
assert.match(table,/DeliveryEvidenceModal target=\{drill\}/);
assert.match(table,/prefetchEvidencePage/);
assert.doesNotMatch(table,/Export CSV|escapeCSV|assignee-export/);
assert.match(matrix,/readDeliveryDashboard\(filters\)/);
assert.match(matrix,/readAssigneeMatrixEvidence\(filters,"wip_open"\)/);
assert.match(matrix,/readAssigneeMatrixEvidence\(filters,"stale_7d"\)/);
assert.match(matrix,/readAssigneeMatrixEvidence\(filters,"blocked"\)/);
assert.match(matrix,/\[dashboard,open,stale,blocked\]=await Promise\.all\(\[/);
assert.match(matrix,/value\.snapshot_id!==snapshot/,
  "Unpinned initial cohorts must reconcile against the validated dashboard snapshot.");
assert.match(server,/snapshotId!==null&&result\.snapshot_id!==snapshotId/,
  "Pinned evidence requests must continue rejecting snapshot mismatches.");
assert.match(server,/readAssigneeMatrixEvidence\(/);
assert.match(server,/p_snapshot_id:snapshotId/);
assert.match(server,/jira_assignee_initial_evidence_incomplete/);
assert.match(matrix,/wip_open","stale_7d","blocked/);
assert.match(matrix,/jira_assignee_matrix_cohort_mismatch_/);
assert.match(matrix,/jira_assignee_matrix_membership_mismatch/);
assert.match(matrix,/jira_assignee_matrix_total_reconciliation_failed/);
assert.match(matrix,/jira_assignee_matrix_assignee_mismatch/);
assert.match(matrix,/UNTAGGED_MODULE="__untagged__"/);
assert.match(server,/matrix:open","matrix:stale","matrix:blocked/);
assert.match(server,/readDeliveryEvidence\(filters,sourceKey,snapshotId,0,7000/);
assert.match(server,/jira_delivery_matrix_evidence_count_mismatch/);
assert.match(server,/scope\.moduleMode==="other"/);
assert.match(server,/scope\.issueType/);
assert.match(server,/scope\.assignee/);
assert.match(server,/matrixScope\?:AssigneeMatrixScope/);
assert.match(types,/AssigneeMatrixScope/);
assert.match(evidenceApi,/matrix_scope/);
assert.match(issueApi,/matrix_scope/);
assert.match(evidenceModal,/loadEvidencePage\(/);
assert.match(evidenceModal,/matrix_scope:target.matrixScope/);
assert.match(evidenceModal,/matrixScope=\{target.matrixScope\}/);
assert.match(issueModal,/matrix_scope:matrixScope/);
assert.match(prefetch,/request.matrix_scope/);
assert.match(loading,/ed-skeleton-line/);
assert.doesNotMatch(loading,/Loading verified Jira reporting data/);
assert.match(css,/inherits Companies' original customer.css/);
assert.match(customerCss,/\.companies-monthly-table \.companies-month-header th/);
assert.match(customerCss,/\.companies-monthly-table tbody td:nth-child\(3\)/);
assert.match(customerCss,/\.companies-monthly-table tfoot td/);
assert.doesNotMatch(matrix,/fixture|mockKpis|Math.random/);
console.log("Assignee Overview verified: exact Companies table primitives, live audited Jira cohorts, scoped drill evidence, and frozen header/identity layout.");

assert.match(css,/\.assignee-page\.companies-page\{/);
assert.match(css,/height:calc\(100dvh - 56px\)/);
assert.match(css,/padding:0 30px!important/);
assert.match(css,/\.assignee-page\.companies-page \.companies-records/);
assert.match(table,/global-control-label/);
assert.match(table,/Reporting scope/);
assert.match(table,/ui-control date-trigger/);
assert.match(table,/metrics-section-description/);
assert.match(table,/MetricsInfoButton/);
assert.match(table,/MetricsInfoDialog/);
assert.match(table,/assignee-scope-wrap/);
assert.match(table,/applySprint/);
assert.match(table,/All sprints/);
assert.match(table,/assignee-sprint-menu/);
assert.match(table,/Filter by module/);
assert.match(table,/Filter by sub-module/);
assert.match(table,/Filter by severity/);
assert.doesNotMatch(table,/assignee-sprint-filter/,
  "Sprint scoping lives in the heading chip, not the toolbar Filters menu.");
assert.doesNotMatch(table,/aria-haspopup="dialog"/,
  "Scope chip opens the sprint popover; metric info stays on the toolbar button.");
assert.match(table,/CompactMenuSelect/,
  "Filter dropdowns must use the app-native CompactMenuSelect control.");
assert.match(table,/assignee-filter-select/);
assert.doesNotMatch(table,/<select[\s>]/,
  "No browser-native select dropdowns on the assignees page.");
assert.doesNotMatch(table,/ui-select-host/);
assert.match(table,/maxWidth:tableMaxWidth/,
  "Filtered sparse views cap the fixed-layout stretch instead of ballooning cells.");
assert.match(table,/tableMaxWidth=462\+numericColumns\.length\*190/);
assert.match(table,/aria-label="Assignee workload matrix"/);
assert.match(table,/maxWidth:tableMaxWidth\+2/,
  "The records card hugs the capped table width so no empty space shows inside it.");
assert.match(table,/flex:"0 0 auto",height:content/,
  "Short filtered tables hug vertically; tall tables keep viewport-fill internal scroll.");
assert.match(css,/\.assignee-shell \.ed-investigation-foot\.rd-modal-foot\{border-top:0\}/,
  "Drill pagination footer drops the full-width divider on this page only.");
assert.match(css,/\.assignee-shell \.ed-issue-dialog\{width:min\(1080px,calc\(100vw - 64px\)\)/,
  "Issue-detail dialog matches the first drill's frame size on this page.");
assert.match(css,/\.assignee-shell \.ed-issue-dialog\{width:calc\(100vw - 18px\)/,
  "Small screens keep the shared near-fullscreen dialog fit.");
assert.match(table,/scrollRef/);
assert.match(table,/window\.addEventListener\("resize",measure\)/);
assert.doesNotMatch(css,/assignee-monthly-table\{margin:0 auto\}/,
  "The card cap replaced table centering.");
assert.match(css,/\.assignee-page \.assignee-scope-wrap\{position:relative\}/);
assert.match(css,/\.assignee-page \.assignee-sprint-menu\{width:280px/);
assert.match(matrix,/sub_modules:dashboard\.options\.sub_modules/);

/* Executable URL regression tests for the toolbar reset. */
const originalParams = new URLSearchParams("sprint=1268&module=AP&sub_module=Payments&severity=L1");
assert.equal(resetAssigneeToolbarFilters(originalParams), "/delivery/assignees?sprint=1268");
assert.equal(originalParams.get("module"), "AP", "Reset helper must not mutate URL parameters.");
assert.equal(
  resetAssigneeToolbarFilters(new URLSearchParams("sprint=1238&module=AR&assignee=owner%40123&search=backlog")),
  "/delivery/assignees?sprint=1238&assignee=owner%40123&search=backlog",
  "Preserve selected sprint, assignee, and any unrelated URL context.",
);
assert.equal(
  resetAssigneeToolbarFilters(new URLSearchParams("module=AP&sub_module=Payments&severity=L1")),
  "/delivery/assignees",
  "Reset only toolbar filters and return the default view when no scope is active.",
);
assert.equal(
  resetAssigneeToolbarFilters(new URLSearchParams("sprint=1268")),
  "/delivery/assignees?sprint=1268",
  "Reset must not change reporting sprint when no toolbar filter is active.",
);
assert.ok(table.includes('onClick={resetFilters}>Reset</button>'),
  "Reset button must use the scoped reset action.");
assert.ok(table.includes('resetAssigneeToolbarFilters(new URLSearchParams(window.location.search))'),
  "Reset must use current URL query parameters to preserve reporting scope.");
assert.ok(!table.includes('onClick={()=>router.replace("/delivery/assignees",{scroll:false})}>Reset'),
  "Reset must never clear the reporting scope by navigating to the bare route.");
const infoDefinitions=read("components/ui/metrics-info.tsx");
const assigneeInfo=infoDefinitions.split("assignee_workload: {")[1]?.split("\n  },")[0];
assert.ok(assigneeInfo, "Assignee metric info definition must exist.");
assert.doesNotMatch(assigneeInfo, /\b\d[\d,]* (?:assignees|open issues)\b/,
  "Assignee metric example must not hardcode a moving global workload count.");
console.log("Assignee toolbar reset and timeless metric info verified.");
