# AI Services — Bill Extraction mock UI (synthetic demo)

**Status:** UI mock on task branch `feat/ai-services-bill-extraction-mock`. Synthetic demo data only.
No Supabase, API, AWS, or existing-dashboard changes beyond additive nav wiring.

## What was built

- Route `/ai-services` (`app/ai-services/`): server shell + `loading.tsx` skeleton + scoped `ai-services.css`.
- `lib/ai-services/`: `types.ts` (1:1 with `bill_extraction_reporting_v1` columns),
  `summary.ts` (pure KPIs/series/buckets over records), `fixtures.ts` (demo query adapter).
- `testdata/ai-bill-extraction-demo.json`: 494 seeded rows (seed 42) via
  `scripts/generate-ai-bill-demo.mjs`. Distributions mirror the live audit:
  ~14% unknown cost, ~6.5% unknown latency, doc mix with NULLs, all 3 scopes.
- `components/ai-services/`: overview shell (filters, 6 KPI cards, 9 panels),
  `bill-drills.tsx` (records modal + detail modal).
- Nav: header `DashboardKey "ai-services"` + `AI_SERVICES_PAGES`; drawer link
  replaces the `"AI Services"` future placeholder.
- Guard: `scripts/verify-ai-services-shell.mjs`, wired into `prebuild` + `test:ai-services-shell`.

## Defaults chosen for §8 (pending human confirmation)

1. P95 nearest-rank. 2. Neutral "cost/latency units" labels. 3. Default last-6
completed months. 4. Test/unverified behind warning opt-in. 5. `has_raw` shown
in detail only; `file_uuid` hidden. 6. `deleted` included in denominators.
7. Company history within selected range. 8. Directory label with AI-name fallback.

## Verification

`npm run test:ai-services-shell` (static) + `npm run build` (full prebuild + Next build).
No live data path exists in this slice: grep-guarded, no `SUPABASE_*`, no `fetch(`.
