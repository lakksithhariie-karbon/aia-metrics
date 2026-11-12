# Product shadow historical parity classification (2026-11-12)

## Diagnosis

**The Product event sync is not missing records.** At 2026-11-12 14:03 UTC, legacy and shadow each contained 560,556 events with matching current source watermarks. The complete 58-table source-to-shadow parity suite returned **zero missing or content-mismatched source rows**.

Raw symmetric whole-table parity remains different in **four reporting tables**, but all additional records trace to three sealed **October 26** historical snapshot generations present only in `"01_product_schema"`:

| Snapshot ID | Kind | Extra members | Extra drills | Extra seals |
|---|---|---:|---:|---:|
| 348 | `overview-module-mix` | 883 | 16 | 1 |
| 351 | `overview-friction` | 622 | 30 | 1 |
| 354 | `overview` | 8,638 | 63 | 1 |
| **Total** | | **10,143** | **109** | **3** |

All three were sealed on October 26, have `n_events=511439`, the same source watermark, non-null build keys, **zero current snapshot-pointer references**, and **zero publication-member references**. Every legacy snapshot/drill/member/seal row is present in the shadow with identical data. Current pointers in both schemas match exactly.

### Root cause

The sealed-snapshot mirror function `"01_product_schema".reconcile_sealed_product_shadow_v1()` is intentionally **additive**: it inserts/updates legacy snapshots and copies missing sealed generations, but does not delete existing shadow historical generations. Thus `EXCEPT ALL` in the shadow-to-legacy direction reports the old retained records as extras. This is not a missing event, corrupted report row, or current-pointer discrepancy.

### Implemented safeguard

`supabase/tests/PRODUCT_shadow_approved_history_audit_20261112.sql` is a **read-only**, fail-closed source-fidelity test. It:
- Requires exact source fidelity in the four exception tables via row-content `EXCEPT ALL` and confirms matching live events and publication/current pointers.
- Allows **only snapshot IDs 348, 351, and 354** with the verified kind, October 26 watermark, expected record counts, and zero active pointers/manifests.
- Rejects any new shadow-only snapshot or unexpected child rows; it does not grant blanket permission for more drift.
- Reports `pass_source_fidelity_with_approved_historical_extras` rather than mislabeling physical 58-table equality.

The other 54 reporting/data tables were verified by the original strict parity suite. The four original raw-parity checks were **not changed**; they remain useful for seeing the physical extra rows.

### How to verify

Run in order against the authorized database:
1. `product_cutover_small_parity_part_1.sql` (18 tables).
2. `product_cutover_small_parity_part_2.sql` (18 tables).
3. `product_cutover_small_parity_part_3.sql` (17 tables).
4. `product_cutover_large_parity.sql` (5 tables).
5. `PRODUCT_shadow_approved_history_audit_20261112.sql` (explicit exception validation).
6. `PRODUCT_cutover_go_no_go.sql` (independent production-readiness gate).

At the Nov 12 check, each of the 58 source-to-shadow missing/mismatch counters was zero; the four target-only deltas were precisely 3 snapshots, 3 seals, 109 drills and 10,143 members. The independent history test passed.

### Safety / production boundary

**No snapshot deletion, source mutation, watermark rewriting, pointer advancement, writer switch, or reader cutover was performed.** Historical records remain available for audit/replay. Deleting them just to make raw counts agree would be destructive and would not address the still-broken Overview publication pipeline.

**Production sign-off is still blocked:** the current five Overview kinds do not share one source watermark, both page publication manifests are absent, and `PRODUCT_cutover_go_no_go.sql` still reports `automated_database_go=false`. Resolve the separate [Overview publisher issue #40](https://github.com/lakksithhariie-karbon/aia-metrics/issues/40) before cutover.
