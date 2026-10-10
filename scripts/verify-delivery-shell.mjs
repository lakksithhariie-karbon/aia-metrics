/** Engineering & Delivery preview safety net.
 * This is a shell, not a data launch. Preserve the exact common Product page
 * grid and never publish fabricated Jira metrics at this stage.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = path => readFileSync(new URL("../" + path, import.meta.url), "utf8");

const page = read("app/delivery/page.tsx");
const shell = read("components/delivery/engineering-delivery-shell.tsx");
const css = read("app/delivery/delivery.css");
const productGrid = read("app/metrics-page-grid.css");
const header = read("components/product-metrics-header.tsx");
const drawer = read("components/main-navigation-drawer.tsx");

assert.match(page, /metrics-page-grid\.css/, "Delivery must import the same shared Product page grid");
assert.match(page, /retention\/retention\.css/, "Delivery must use the same Product Metrics card vocabulary");
assert.match(page, /current="delivery"/, "Delivery must use the existing app header");
assert.match(shell, /className="rd-page ed-page"/, "Delivery must inherit the actual Product page 12-column grid");
assert.match(shell, /className="kpi-grid po-kpis rd-kpi-grid ed-kpi-grid"/, "Delivery KPI tiles must inherit the existing 3-up Product card grid");
assert.match(shell, /className="metrics-grid-section ed-section"/, "Delivery panels must share Product section shells");
for (const section of [
  "Sprint delivery", "Attention", "Delivery", "Flow", "Quality",
]) {
  assert.match(shell, new RegExp('title="' + section + '"'), "Missing reference section " + section);
}
for (const required of [
  "--metrics-page-max:1560px", "--metrics-page-gutter:28px",
  "--metrics-page-gap:24px", "grid-template-columns:repeat(12,minmax(0,1fr))",
]) {
  assert.ok(productGrid.includes(required), "Shared grid contract changed: " + required);
}
assert.match(css, /grid-template-columns:repeat\(12,minmax\(0,1fr\)\)/, "Internal report cards must follow the same 12-column grid");
assert.match(header, /isDelivery \? "Engineering Metrics" : "Product Metrics"/, "Product section header must not change");
assert.match(drawer, /href="\/delivery"/, "Main drawer must navigate to the combined Engineering page");
assert.match(shell, /Data connection pending/, "Unverified values must be explicitly unpopulated");
assert.doesNotMatch(shell, /\bMath\.random\b|mockKpis|fixtureData|sampleMetrics/i, "Do not fabricate Jira metrics");
console.log("Engineering & Delivery shell verified: shared 1560px / 12-column / 24px grid, five sections, no fabricated data.");
