import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const sql = readFileSync(new URL("../supabase/migrations/20261010_jira_reporting_definition_integrity_v1.sql", import.meta.url), "utf8");
const names = ["v_issue_normalized","v_sprint_drilldown","v_issue_flow_state","v_wip_by_status","v_bug_health","v_qa_queue","v_flow_counts","v_sprint_discipline","v_metric_cohorts_active_v1"];
for (const name of names) assert.ok(sql.includes("CREATE OR REPLACE VIEW jira."+name+" AS"),"Missing audited Jira reader "+name);
assert.match(sql,/count\(\*\) FILTER \(WHERE is_done\) AS done_now/);
assert.match(sql,/tomb\.deleted_at <= \(SELECT cutoff_at FROM publication\)/);
assert.match(sql,/from jira\.v_metric_cohorts_active_v1 mc/i);
assert.match(sql,/jira_open_work_parity_failed/);
assert.match(sql,/jira_done_now_parity_failed/);
assert.match(sql,/jira_open_cohort_parity_failed/);
assert.doesNotMatch(sql, /\bTRUNCATE\b|\bDROP\s+(?:TABLE|VIEW|MATERIALIZED\s+VIEW)\b|\bDELETE\s+FROM\s+jira\.(?:raw_issues|issues)\b/i);
const alignedCore = readFileSync(new URL("../supabase/migrations/20261010_jira_filtered_core_reader_alignment_v1.sql", import.meta.url), "utf8");
for (const fn of ["get_filtered_dashboard_core_025_base", "get_filtered_dashboard_core_025_base_submodule"]) {
  assert.ok(alignedCore.includes("CREATE OR REPLACE FUNCTION jira."+fn+"("), "Missing "+fn);
}
assert.equal((alignedCore.match(/from jira\.v_metric_cohorts_active_v1 mc/g) || []).length, 2,
  "Both core variants must read verified cohort metadata");
assert.equal((alignedCore.match(/join jira\.v_metric_cohorts_active_v1 mc/g) || []).length, 2,
  "Both core variants must read verified cohort rows");
assert.doesNotMatch(alignedCore, /from metric_cohorts mc|join metric_cohorts mc/i);
assert.doesNotMatch(alignedCore, /DROP\s+(?:MATERIALIZED VIEW|TABLE)|TRUNCATE\s+jira/i);
console.log("Jira reporting source guards verified: deleted-exclusion parity, exact done_now, frozen cohort adapter.");
