import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
const read = path => readFileSync(new URL("../"+path,import.meta.url),"utf8");
const drawer = read("components/main-navigation-drawer.tsx");
const topMenu = read("components/product-metrics-header.tsx");
const product = read("app/product/page.tsx");
const overview = read("app/overview/page.tsx");
const prototype = read("components/prototype-surface.tsx");
const runtime = read("public/prototype/runtime-v2-1.js");
const root = read("app/page.tsx");

// Overview is an intentionally empty, independent section, with only the
// global header/drawer to keep the rest of the application reachable.
assert.match(overview, /<MainNavigationDrawer\s*\/>/);
assert.match(overview, /<main aria-label="Overview"/);
assert.doesNotMatch(overview,
  /PrototypeSurface|readPublishedOverviewUsage|readPublishedOverviewActiveCharts|readPublishedAdoptionSummary|readPublishedWorkflowSummary|readPublishedFrictionSummary|RetentionDashboard|CompaniesDashboard/,
  "Overview must not render Product data or load Product snapshots.");

// The complete audited Product Overview and its historical semantics move
// under /product. No data-reader or denominator should be rewritten.
for(const required of [
  "readPublishedOverviewUsage(selected)",
  "readPublishedOverviewActiveCharts(selected)",
  "readPublishedAdoptionSummary(selected)",
  "readPublishedWorkflowSummary(selected)",
  "readPublishedFrictionSummary(selected)",
  "resolveOverviewRange(readOverviewRange(params))",
  "Promise.allSettled",
  "historicalStatus={resolved.historical",
  "<PrototypeSurface"
]) {
  assert.ok(product.includes(required), "Product reader or historical parity missing: "+required);
}
assert.match(product, /\.\.\/overview\/overview-info\.css/);

// The drawer owns three distinct top-level sections. Retention and Companies
// keep their established deep links but belong to the Product section.
assert.match(drawer, /href="\/overview"/);
assert.match(drawer, /href="\/product"/);
assert.match(drawer, /href="\/delivery"/);
assert.match(drawer, /pathname === "\/retention"/);
assert.match(drawer, /pathname === "\/customer"/);
assert.match(drawer, /isOverview \? " is-current" : ""/);
assert.match(drawer, /onProduct \? " is-current" : ""/);
assert.match(drawer, /onDelivery \? " is-current" : ""/);
assert.doesNotMatch(drawer, /"Product",\s*"AI Services"/);

// Product Overview is linked to /product in its dashboard switcher, while
// the existing Retention, Companies and Engineering routes stay intact.
assert.match(topMenu, /name: "Product Overview"[\s\S]*?href: "\/product"/);
assert.match(topMenu, /href: "\/retention"/);
assert.match(topMenu, /href: "\/customer"/);
assert.match(topMenu, /href:"\/delivery\/assignees"/);
assert.doesNotMatch(topMenu, /href: "\/overview"/);
assert.match(prototype, /<ProductMetricsHeader current="product"\s*\/>/);

// Legacy date-range picker must navigate within /product so that historical
// queries still reach the same server-side snapshot-selection logic.
assert.match(runtime, /window\.location\.pathname==='\/product'/);
assert.match(runtime, /return '\/product\?'\+q\.toString\(\)/);
assert.match(runtime, /window\.location\.assign\('\/product'\)/);
assert.doesNotMatch(runtime, /\/overview/);
assert.match(root, /redirect\("\/overview"\)/,
  "App root opens the independent Overview section.");

console.log("Section routing verified: Overview empty, Product Overview live at /product, historical picker and secondary page links preserved.");
