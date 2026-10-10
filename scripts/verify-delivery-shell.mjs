/** Engineering & Delivery design reference preview guard.
 *
 * The Product Metrics page geometry must remain shared and the reference
 * screenshot figures must NEVER be mislabeled as live, verified Jira values.
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

assert.ok(page.includes('metrics-page-grid.css'), "Delivery must import the exact shared Product page grid");
assert.ok(page.includes('retention/retention.css'), "Delivery must reuse Product Metrics card styling");
assert.ok(page.includes('current="delivery"'), "Delivery must reuse the existing app header");
assert.ok(shell.includes('className="rd-page ed-page"'), "Page must inherit the shared Product 12-column shell");
assert.ok(shell.includes('className="metrics-grid-section ed-section"'), "Sections must reuse Product section wrappers");
for (const token of [
  "--metrics-page-max:1560px",
  "--metrics-page-gutter:28px",
  "--metrics-page-gap:24px",
  "grid-template-columns:repeat(12,minmax(0,1fr))",
]) {
  assert.ok(productGrid.includes(token), "Shared Product geometry changed: " + token);
}
assert.ok(css.includes("grid-template-columns:repeat(12,minmax(0,1fr))"),
  "Full-width report collection must retain a nested 12-column grid");
assert.ok(css.includes(".ed-sprint-kpis{grid-template-columns:repeat(3,minmax(0,1fr))}"),
  "The Sprint reference must show 3 cards across on desktop");
assert.ok(css.includes(".ed-five-kpis{grid-template-columns:repeat(5,minmax(0,1fr))}"),
  "Attention and Quality need the five-across reference layout");
for (const section of [
  "Sprint delivery", "Attention", "Delivery", "Flow", "Quality",
]) {
  assert.ok(shell.includes('title="' + section + '"'), "Missing GitLab reference section: " + section);
}
for (const required of [
  'label: "Active sprint · SPEND Sprint 50"',
  'label: "Committed work not delivered"',
  'label: "Mid-sprint additions"',
  'label: "Throughput"',
  'label: "Stale work"',
  'label: "Stale and blocked"',
  'label: "Open L1 bugs"',
  'label: "QA queue"',
  'label: "Blocked"',
  'label: "Open bug backlog"',
  'label: "Reopen rate"',
  'label: "QA rejection"',
  'label: "Bug resolution"',
  'label: "QA turnaround"',
  'label: "Code review"',
]) {
  assert.ok(shell.includes(required), "Missing insight card: " + required);
}
for (const insight of [
  'title="Work in flight"',
  'title="Planned versus done"',
  'title="Issue types by sprint"',
  'title="Flow health"',
  'Blocked / On hold', 'Code Review', 'Staging',
  'Sprint commitment', 'Committed work finished', 'Late-added completions',
]) {
  assert.ok(shell.includes(insight), "Missing reference report or row: " + insight);
}
assert.match(header, /isDelivery \? "Engineering Metrics" : "Product Metrics"/,
  "Existing Product dashboard header must remain intact");
assert.ok(drawer.includes('href="/delivery"'),
  "The existing 40% navigation drawer must link to the Engineering page");
assert.ok(shell.includes("Visual reference only."), "Never present supplied screenshot values as live Jira data");
assert.ok(shell.includes("not live data"), "Each headline number needs to be identifiable as reference-only");
assert.doesNotMatch(shell, /\bMath\.random\b|mockKpis|fixtureData|sampleMetrics/i,
  "No generated or fabricated Jira metrics in the reference preview");

console.log("Engineering & Delivery preview verified: 15 reference KPI cards, 4 detailed reports, 5 sections, shared 1560px / 12-col grid; not live.");
