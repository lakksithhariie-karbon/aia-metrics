/** A build gate to catch accidental divergence from audited Companies usage.
 * Live event-count parity is separately validated in Supabase for each release.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = path => readFileSync(new URL("../" + path, import.meta.url), "utf8");
const data = read("lib/companies/server.ts");
const ui = read("components/companies/companies-insights-drill.tsx");
const shell = read("components/companies/companies-dashboard.tsx");
const sql = read("supabase/migrations/20261010_companies_drill_insights_v1.sql");

assert.match(data, /read_companies_monthly_breakdown_v2/,
  "The existing audited breakdown must remain the comparison source.");
assert.match(data, /read_companies_monthly_insights_v1/,
  "The new insights RPC must be available.");
assert.match(data, /companies_insights_reconciliation_failed/,
  "Never remove the reconciliation gate.");
for (const dimension of ["insights.total", "insights.item_total", "insights.categories", "insights.slices", "insights.days", "insights.sources"]) {
  assert.ok(data.includes(dimension), "Missing data integrity guard: " + dimension);
}
assert.match(shell, /<CompaniesInsightsDrill/,
  "Companies modal must mount the audited insights component.");
for (const tab of ["overview", "breakdown", "users", "evidence"]) {
  assert.ok(ui.includes('key: "' + tab + '"'), "Missing drill tab: " + tab);
}
for (const module of ["ap", "ar", "transactions", "gst"]) {
  assert.ok(ui.includes('"' + module + '"'), "Module-specific slice display missing: " + module);
}
for (const requirement of [
  "company_work_module_v2", "company_items_for", "company_monthly_meta_v2",
  "source_watermark_at", "integration_at", "is_internal_email",
  "Asia/Kolkata", "p_user_key", "REVOKE ALL", "service_role",
]) {
  assert.ok(sql.includes(requirement), "Missing audited SQL requirement: " + requirement);
}
assert.doesNotMatch(ui, /Technical details and original grouped subtypes|cid-technical/,
  "The approved Companies drill must not show raw technical details.");
console.log("Companies drill contract verified: modules, tabs, source filters and total parity guards.");
