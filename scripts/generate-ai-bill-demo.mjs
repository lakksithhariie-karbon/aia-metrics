#!/usr/bin/env node
/**
 * Generate the synthetic AI bill-extraction demo fixture.
 *
 * Seeded PRNG (mulberry32, seed 42) so output is deterministic. Distributions
 * mirror the live audit rates from docs/ai-services-bill-extraction-data-readiness.md:
 * ~13% unknown cost, ~6.5% unknown latency, doc mix with NULLs, all 3 scopes.
 * No real company names, UUIDs, or costs. DEMO ONLY.
 */
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SEED = 42;
const DEMO_AS_OF = "2026-10-27T06:59:08.124+00:00";
const MONTHS = ["2026-03", "2026-04", "2026-05", "2026-06", "2026-07", "2026-08", "2026-09", "2026-10"];
const MONTH_WEIGHTS = [0.06, 0.09, 0.1, 0.12, 0.13, 0.16, 0.2, 0.14];

function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const rand = mulberry32(SEED);
const pick = arr => arr[Math.floor(rand() * arr.length)];
const pickWeighted = (values, weights) => {
  let x = rand();
  for (let i = 0; i < values.length; i += 1) {
    x -= weights[i];
    if (x <= 0) return values[i];
  }
  return values[values.length - 1];
};

const COMPANIES = [
  { uuid: "11111111-1111-4111-8111-111111111111", name: "Demo Laundry Co", scope: "verified_customer" },
  { uuid: "22222222-2222-4222-8222-222222222222", name: "Demo Textiles Ltd", scope: "verified_customer" },
  { uuid: "33333333-3333-4333-8333-333333333333", name: "Demo Garments Inc", scope: "verified_customer" },
  { uuid: "44444444-4444-4444-8444-444444444444", name: "Demo Retail Group", scope: "verified_customer" },
  { uuid: "55555555-5555-4555-8555-555555555555", name: "Demo Foods Pvt", scope: "verified_customer" },
  { uuid: "66666666-6666-4666-8666-666666666666", name: "Demo Logistics", scope: "verified_customer" },
  { uuid: "77777777-7777-4777-8777-777777777777", name: "Demo Electronics", scope: "verified_customer" },
  { uuid: "88888888-8888-4888-8888-888888888888", name: "Demo Pharma Labs", scope: "verified_customer" },
  { uuid: "99999999-9999-4999-8999-999999999999", name: "Demo Auto Parts", scope: "verified_customer" },
  { uuid: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", name: "Demo QA Fixture", scope: "test_company" },
  { uuid: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", name: "Demo Sandbox Org", scope: "test_company" },
  { uuid: "cccccccc-cccc-4ccc-8ccc-cccccccccccc", name: "Unmatched Demo Co", scope: "unverified_company" },
];

const DOC_TYPES = ["scanned", "scanned", "digital", "digital", "digital", "handwritten", null];
const REVIEW = ["reviewed", "reviewed", "reviewed", "reviewed", "reviewed", "reviewed", "reviewed", "reviewed", "needs_review", "needs_review", "deleted"];

const hex = n => Array.from({ length: n }, () => "0123456789abcdef"[Math.floor(rand() * 16)]).join("");
const uuid = () => `${hex(8)}-${hex(4)}-4${hex(3)}-8${hex(3)}-${hex(12)}`;

function lognormal(median, sigma) {
  const u1 = Math.max(rand(), 1e-9);
  const u2 = rand();
  const z = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
  return median * Math.exp(sigma * z);
}

const records = [];
let n = 0;
for (const month of MONTHS) {
  const daysInMonth = month === "2026-10" ? 27 : 28;
  const rows = Math.round((month === "2026-10" ? 60 : 62) * (MONTH_WEIGHTS[MONTHS.indexOf(month)] / 0.125));
  for (let i = 0; i < rows; i += 1) {
    n += 1;
    const company = pickWeighted(COMPANIES, [0.14, 0.13, 0.12, 0.11, 0.1, 0.09, 0.08, 0.07, 0.06, 0.05, 0.03, 0.02]);
    const day = 1 + Math.floor(rand() * daysInMonth);
    const createdAt = `${month}-${String(day).padStart(2, "0")}T${String(Math.floor(rand() * 24)).padStart(2, "0")}:${String(Math.floor(rand() * 60)).padStart(2, "0")}:00+05:30`;
    const costKnown = rand() > 0.13;
    const latKnown = rand() > 0.065;
    const extractionCost = costKnown && rand() > 0.06 ? +lognormal(1.6, 0.7).toFixed(3) : null;
    const enrichmentCost = costKnown && rand() > 0.06 ? +lognormal(0.9, 0.8).toFixed(3) : null;
    const extractionLatency = latKnown && rand() > 0.04 ? Math.round(lognormal(42, 0.9)) : null;
    const enrichmentLatency = latKnown && rand() > 0.04 ? Math.round(lognormal(18, 0.9)) : null;
    const docType = month < "2026-05" && rand() < 0.3 ? pick(["scanned", null]) : pick(DOC_TYPES);
    records.push({
      predictionUuid: uuid(),
      fileUuid: rand() > 0.1 ? uuid() : null,
      companyUuid: company.uuid,
      aiCompanyName: company.name,
      companyName: company.scope === "unverified_company" ? company.name + " (unmatched)" : company.name,
      companyScope: company.scope,
      createdAt,
      loadedAt: createdAt,
      reviewStatus: pick(REVIEW),
      docType,
      legibilityScore: rand() > 0.12 ? +Math.min(1, Math.max(0, 0.55 + rand() * 0.5)).toFixed(2) : null,
      totalPages: rand() > 0.25 ? 1 + Math.floor(rand() * 14) : null,
      hasRaw: rand() > 0.15,
      extractionCost,
      enrichmentCost,
      knownTotalCost:
        extractionCost === null && enrichmentCost === null
          ? null
          : +(((extractionCost ?? 0) + (enrichmentCost ?? 0)) * (1 + (rand() - 0.5) * 0.04)).toFixed(3),
      completeCostBreakdown: extractionCost !== null && enrichmentCost !== null,
      extractionLatency,
      enrichmentLatency,
      knownTotalLatency:
        extractionLatency === null && enrichmentLatency === null
          ? null
          : (extractionLatency ?? 0) + (enrichmentLatency ?? 0) + Math.floor(rand() * 4),
      completeLatencyBreakdown: extractionLatency !== null && enrichmentLatency !== null,
    });
  }
}

const outDir = join(dirname(fileURLToPath(import.meta.url)), "..", "testdata");
writeFileSync(
  join(outDir, "ai-bill-extraction-demo.json"),
  JSON.stringify(
    { meta: { mode: "synthetic-demo", demoAsOf: DEMO_AS_OF, generatedAt: new Date().toISOString(), seed: SEED, recordCount: records.length }, records },
    null,
    2,
  ) + "\n",
);
console.log(`wrote ai-bill-extraction-demo.json: ${records.length} records`);
