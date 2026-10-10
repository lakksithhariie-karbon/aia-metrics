/** Build-time guard: prevent reopening the legacy test-inclusive drill bug.
 * Does not access the database or credentials. Database parity is tested separately.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

function readRepo(path) {
  return readFileSync(new URL("../" + path, import.meta.url), "utf8");
}

const adapter = readRepo("lib/overview/drill.ts");
const expected = [
  "read_overview_core_users_v3",
  "read_overview_core_company_v3",
  "read_overview_active_chart_users_v3",
  "read_overview_active_chart_company_v3",
];

for (const name of expected) {
  assert.equal(
    adapter.split('"' + name + '"').length - 1,
    1,
    "Expected exactly one audited drill RPC reference: " + name,
  );
}

for (const name of [
  "read_overview_core_users",
  "read_overview_core_company",
  "read_overview_active_chart_users",
  "read_overview_active_chart_company",
]) {
  assert.doesNotMatch(
    adapter,
    new RegExp('"' + name + '_v[12]"'),
    "Legacy, test-inclusive or nonhistorical Overview drill was reintroduced",
  );
}

const kpis = readRepo("lib/overview/kpis.ts");
assert.match(
  kpis,
  /\/rpc\/read_overview_independent_core_kpis_v4/,
  "Overview KPI reader must use audited snapshot-keyed v4",
);
const usageModal = readRepo("components/overview/overview-usage-modals.tsx");
assert.match(
  usageModal,
  /result\.segment_total\s*!==\s*expectedTotal\(snapshot,\s*segment\)/,
  "Do not remove KPI/drill total consistency validation",
);

console.log("Overview drill contract verified: 4 audited RPCs, KPI parity guard retained.");
