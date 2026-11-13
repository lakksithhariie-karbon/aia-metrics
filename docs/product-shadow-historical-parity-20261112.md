# Product shadow parity and historical cleanup (November 12, 2026)

## Current result: 58/58 exact table parity, but Overview publisher still blocked

At 16:24 UTC on November 12, the original **58-table bidirectional row-content parity suite passed** across all 58 Product tables: zero missing, altered, or additional rows in either direction. The legacy and new schemas each contained **560,817 events**, identical ingestion watermarks and current snapshot pointers. This is a point-in-time check, not evidence of perpetual zero drift or approval to retire legacy.

## Diagnosis and transition

Earlier on November 12, the sealed-snapshot mirror retained three **October 26 shadow-only** historical generations. Its reconciliation intentionally copies source data without deleting extra historic shadow rows, explaining four raw symmetric parity differences at the earlier checkpoint.

| Shadow-only snapshot ID | Kind | Extra members | Extra drills | Extra seals |
|---|---|---:|---:|---:|
| 348 | `overview-module-mix` | 883 | 16 | 1 |
| 351 | `overview-friction` | 622 | 30 | 1 |
| 354 | `overview` | 8,638 | 63 | 1 |
| **Total** | | **10,143** | **109** | **3** |

All three had zero active snapshot pointer references and zero publication-member references. None existed in the source legacy schema.

**Later on November 12:** an authorized, authenticated GitHub Actions canary ran `sync-incremental-product-shadow` successfully ([run](https://github.com/lakksithhariie-karbon/aia-metrics/actions/runs/43257467674)). The Edge Function includes best-effort calls to `shadow_product_prune_product_snapshots` and related membership pruning functions with `p_keep_per_scope=5`. Immediately after this canary, the three old shadow-only generations and all associated extra rows were no longer present. This is consistent with its built-in retention cleanup. It was **not** a manual copy/delete or production data edit.

The legacy source still has all of its own records, and active pointers remain identical. These non-current shadow-only historical copies are **no longer available** for replay. Do not describe them as preserved.

## Safeguard and tests

The committed read-only `supabase/tests/PRODUCT_shadow_approved_history_audit_20261112.sql` now accepts **exactly two safe outcomes**:

1. `pass_exact_parity`: source and shadow rows/current pointers match with **no extra archival rows**, which is the present state.
2. `pass_source_fidelity_with_approved_historical_extras`: only IDs 348, 351, and 354 exist as extra sealed, unreferenced historical generations, with the exact previously verified kinds, source watermark, and member/drill/seal counts.

Any unexplained missing source row, new extra, altered pointer, or mismatched approved count fails. Do not weaken the original four strict parity SQL suites or change them to ignore extras.

At 16:25 UTC, the audit reported `pass_exact_parity`. The original three small-table scripts (18 + 18 + 17) plus large-table script (5) had all passed with zero bidirectional differences shortly before.

## Faster but still temporary reconciliation

Legacy hourly ingestion cron #7 remains at minute 05. Shadow reconciliation cron #47 now runs at **12, 28, 58** after a guarded, versioned migration `20261112162500_product_shadow_post_ingest_reconcile_schedule.sql`, reducing the lag after source ingestion. The original cadence can be restored using `supabase/rollback/PRODUCT_shadow_post_ingest_reconcile_schedule_restore.sql`. This is shadow-only scheduling, **not** a canonical writer switch.

## Remaining blockers

- The five current Overview snapshots have mixed November 5 and November 11 watermarks.
- Neither schema has an active five-member Overview publication manifest.
- Full complete source payload, Funnel memberships, and Overview member-card regeneration logic must be recovered or rebuilt and source-verified, including the known nine historical identity discrepancies. Do not manufacture absent history or publish incomplete snapshots.
- The authenticated Edge canary returned HTTP 200 with valid refresh and no identity mismatches, but **zero inserts and zero updates**; it proved HTTP authentication, source processing, and unchanged legacy watermark, **not** a real new-event write.
- Complete authenticated reader cutover testing, owner-dependent job transition, rollback, and 48–72-hour post-cutover monitoring are still pending.

`PRODUCT_cutover_go_no_go.sql` correctly returns `automated_database_go=false`. Keep PR #39 in draft and issue #40 open. No production reader/writer cutover has been performed.
