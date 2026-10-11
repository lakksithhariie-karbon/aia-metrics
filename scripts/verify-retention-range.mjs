import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { visibleScopedValue, isScopedRequestPending } from "../lib/retention/range-state.ts";

const read = path => readFileSync(new URL("../" + path, import.meta.url), "utf8");
const dashboard = read("components/retention/retention-dashboard.tsx");

// Simulate successful A, an immediate selection of B before effects run,
// pending B, then an error. A must never appear under B.
const periodA = { key: "2026-08-01|2026-08-31", value: { kpis: { id: "A" } } };
const keyB = "2026-09-01|2026-09-30";
assert.deepEqual(visibleScopedValue(periodA.key, periodA), periodA.value);
assert.equal(visibleScopedValue(keyB, periodA), null);
assert.equal(isScopedRequestPending(keyB, { key: periodA.key, pending: false }), true);
assert.equal(isScopedRequestPending(keyB, { key: keyB, pending: true }), true);
assert.equal(isScopedRequestPending(keyB, { key: keyB, pending: false }), false);
assert.equal(visibleScopedValue(keyB, periodA), null);
assert.equal(visibleScopedValue(keyB, null), null);

// Verified cached results return when their own date range is selected.
const periodB = { key: keyB, value: { kpis: { id: "B" } } };
assert.deepEqual(visibleScopedValue(keyB, periodB), periodB.value);
assert.equal(visibleScopedValue(periodA.key, periodB), null);

// Guard the actual component wiring, cache use, failure handling and cleanup.
assert.match(dashboard, /visibleScopedValue\(rangeKey, scopedDashboard\)/);
assert.match(dashboard, /isScopedRequestPending\(rangeKey, requestStatus\)/);
assert.match(dashboard, /setScopedDashboard\(\{ key, value: cached \}\)/);
assert.match(dashboard, /setScopedDashboard\(\{ key, value: result \}\)/);
assert.match(dashboard, /setScopedDashboard\(previous => previous\?\.key === key \? null : previous\)/);
assert.match(dashboard, /setRequestStatus\(\{ key, pending: true \}\)/);
assert.match(dashboard, /setRequestStatus\(\{ key, pending: false \}\)/);
assert.match(dashboard, /if \(!controller.signal.aborted\)/);
assert.match(dashboard, /onApply=\{onApplyRange\}/);
for(const label of ["setActivationOpen(false)", "setHeatmapTarget(null)",
   "setRetentionCompany(null)", "setChurnMonth(null)", "setChurnCompany(null)"]) {
  assert.ok(dashboard.includes(label), "Close old-range modal: " + label);
}
assert.doesNotMatch(dashboard, /if \(!controller.signal.aborted && !dashboardData\)/);
console.log("Retention scope guard: success, range change, pending, failure, cached range, and modal closure passed.");
