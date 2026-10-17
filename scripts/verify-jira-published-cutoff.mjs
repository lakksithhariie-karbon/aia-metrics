import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const read=(file)=>readFileSync(new URL("../"+file,import.meta.url),"utf8");
const fix=read("supabase/migrations/20261017_jira_flow_published_cutoff_v1.sql");
const previous=read("supabase/rollbacks/20261017_jira_flow_published_cutoff_v1.sql");
const server=read("lib/delivery/server.ts");
const page=read("app/delivery/page.tsx");
const matrix=read("lib/delivery/assignee-matrix.ts");
const active=fix.split("\n").filter(line=>!line.trim().startsWith("--")).join("\n");
assert.match(active,/CREATE OR REPLACE FUNCTION jira\.get_filtered_dashboard_flow_submodule\(/);
assert.match(active,/RETURNS jsonb/);
assert.match(active,/LANGUAGE sql\s+STABLE SECURITY DEFINER/);
assert.match(active,/SET search_path TO 'jira', 'public', 'pg_catalog'/);
assert.match(active,/SET statement_timeout TO '8s'/);
assert.match(active,/published_cutoff as materialized \(\s*select refreshed_at as as_of\s+from jira\.dashboard_snapshot_refresh_state\s+where singleton/);
assert.match(active,/cross join published_cutoff cutoff/);
assert.equal((active.match(/cutoff\.as_of - i\.updated_at > interval '7 days'/g)||[]).length,2,
 "Stale and stale+blocked flags must share the published as-of boundary.");
assert.match(active,/extract\(epoch from \(cutoff\.as_of - i\.updated_at\)\) \/ 86400\.0 as stale_calc_days/);
assert.match(active,/cutoff\.as_of - fs\.moved_to_blocked_at/);
assert.doesNotMatch(active,/fs\.is_stale_blocked\s*,|fs\.is_stale\s*,|extract\(epoch from fs\.stale_calc_days\)/,
 "Flow may not reintroduce independently moving stale flags.");
assert.equal((active.match(/CREATE OR REPLACE FUNCTION/g)||[]).length,1,
 "Do not mutate unrelated SQL functions.");
assert.doesNotMatch(active,/CREATE\s+(?:OR REPLACE\s+)?VIEW|\bGRANT\b|\bREVOKE\b|\bDROP\b|\bDELETE\b|\bTRUNCATE\b|\bALTER TABLE\b/i,
 "No schema/view, raw data, or permission changes.");
assert.match(previous,/extract\(epoch from fs\.stale_calc_days\)/);
assert.match(previous,/fs\.is_stale_blocked, fs\.is_open, fs\.is_stale, fs\.is_blocked/);
assert.doesNotMatch(previous,/published_cutoff/);
assert.match(page,/readDeliveryDashboard\(filters\)/,
 "Engineering Overview must still call the shared validated dashboard reader.");
assert.match(server,/return validate\(await rpc<DeliveryDashboard>/,
 "The service-role facade and response contract must retain validation.");
assert.match(server,/jira_delivery_reconciliation_failed/);
assert.match(page,/Verified Jira metrics are temporarily unavailable/);
assert.match(matrix,/readAssigneeMatrixEvidence\(filters,"stale_7d"\)/);
assert.match(matrix,/value\.snapshot_id!==snapshot/);
console.log("Jira Flow cutoff verified: one audited function, two shared stale predicates, exact rollback and fail-closed reconciliation intact.");
