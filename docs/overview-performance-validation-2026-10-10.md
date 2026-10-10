# Overview performance validation, 10 October 2026

Scope: preview branch `fix/data-integrity-history-v2`. Production application branch `main` is unchanged.

## What changed

- New private tables `metrics_private.overview_independent_core_kpi_cache_v1` and `metrics_private.overview_chart_summary_cache_v1` hold precomputed **existing v3 JSON responses**, keyed by Overview snapshot ID, source ingestion watermark and as-of timestamp.
- Public service-role-only v4 readers cover WAU/MAU, Active Usage, Adoption, Workflow Usage and Friction. All preserve the original v3 output contracts and fall back to v3 on a missing, stale or invalid cache entry.
- New staggered pg_cron jobs recompute only missing or invalidated cache entries every five minutes. Jobs are additive; they do not replace snapshot publication or existing reporting jobs.
- Application preview readers switch to the v4 summaries. Workflow weekly-user drills now use the scoped v4 reader, and Friction company-list drills the single-scan v5 reader. Their original v3 implementations remain intact. Other drills, Retention, Companies, date selection and event classification remain unchanged.
- Historical Overview snapshots are updated **in place** by the existing daily job, so cache validation checks both snapshot timestamp fields on **every read**.

## Validation against Supabase project hdgbmcerogqfocyxdnpw

- WAU/MAU v3 and v4 returned **exactly equal JSON** for all eight supported snapshots: March through September and current October (8/8).
- The other four v3/v4 chart summary pairs returned **exactly equal JSON** for current October, August and September (12/12). Total tested payload comparisons: **20/20**.
- Metadata checks passed for **8/8 KPI cache rows** and **32/32 chart summary cache rows**.
- Cold-cache fallback verified with uncached older snapshot 271: both KPI and Active Usage matched v3.
- Workflow scoped drill and Friction single-scan drill each matched their original v3 JSON across four representative cases (8/8), including current/previous periods, search and pagination.
- New functions permit `service_role` and deny `anon`/`authenticated`. Supabase security and performance advisors reported **no new cache-specific findings**.
- Background cron job histories showed successful executions.

### Sample PostgreSQL execution times, milliseconds

| Data source | Original v3 | Cached v4 |
|---|---:|---:|
| WAU/MAU | 2,176 | 4.5 |
| Active Usage | 4,228 | 3.7 |
| Adoption | 962 | 3.5 |
| Workflow Usage | 4,085 | 3.6 |
| Friction | 2,718 | 4.6 |

All five cached readers in **one** SQL query: 6.2 ms (current), 7.2 ms (August), 7.1 ms (September).

Scoped drill samples: Workflow weekly users 3,259 ms (v3) to 406 ms (v4); Friction affected companies 4,725 ms (v3) to 964 ms (single-scan v5). These are database execution times, **not** end-to-end page, network or browser render times. Values are sample measurements, not latency SLAs.

## Operational and correctness guarantees

- No raw event, company, retention, integration or snapshot rows were modified.
- No existing v3 RPC or refresh job was replaced. On cache misses, the v3 computation is still authoritative.
- Cache entries are invalid when the snapshot ID, source watermark, as-of time or JSON contract disagrees. Rewarm jobs handle new published generations and in-place historical snapshot refreshes.
- Database SQL functions and cache tables are accessible only with existing privileged server-side access; service keys never move to the browser.
- Cache generation preserves **recorded** historical values. May–July 2026 upstream event capture gaps are **not** corrected by faster reads.
- A future change to the v3 metric definitions requires an explicit cache version/invalidation review. Do not silently reuse cached data across definition changes.

## Rollback

Repoint the five preview server adapters in `lib/overview/` from their v4 summary RPCs to the original v3 names; additionally repoint Workflow weekly-user drills and Friction company-list drills to their original v3 readers. Redeploy the fix branch. The v3 functions and existing data remain available. The additive cache tables may remain unused or the two new pg_cron jobs can be unscheduled after rollback. Do not delete original SQL functions or historical snapshots.

## Pre-production gate

Vercel compiled and type-checked the preview successfully. Direct database parity, fallback, security and refresh checks passed. However, the protected preview was not exercised end-to-end in an authenticated browser in this audit. Before merging: verify initial render, August/September/October date choices, chart/table switchers and representative drill-downs on the Vercel preview. Only merge/deploy to production after explicit approval.
