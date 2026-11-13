# Product Overview publication implementation status, 13 November 2026 (IST)

## Scope and production safety

New-schema-only work on draft PR #39. **No public/metrics_private writer or dashboard routing change**, no legacy snapshots or membership records removed. The existing production dashboard still reads the old reporting functions. Do not present Overview publishing as complete.

## Implemented and tested

- `build_overview_feature_usage_source_v1`: five historic complete JSON payloads replay exactly.
- `build_overview_feature_usage_population_v1`: 46,925 historic membership identities replay exactly.
- `build_overview_feature_usage_headers_v1`: 780 historic headers replay exactly.
- `build_overview_feature_usage_cards_source_v1`: 9,439/9,439 historic event counts, evidence and reached_at values replay exactly. Historical mutable presentation metadata does NOT: 8,513 actors, 9,379 names, 8,124 integration values, 7,230 sort positions, 7,220 full cards match. This is explicitly not full card byte equality.
- `stage_feature_usage_generation_v1`: successfully produced an otherwise complete candidate at watermark 2026-11-12 18:05:34 UTC with 9,377 cards, 156 drill headers and a seal. A repeated call reused its ID, proving deterministic idempotence. Snapshot had no active pointer or publication-member references.
- `try_publish_verified_overview_v1`: refuses publication unless **all five complete kinds** share a current completed event watermark, valid payload schema and positive sealed drill/header membership; calls the existing atomic page publisher only on success. Verified it returns `status=blocked` for missing four kinds.
- Hardened `publish_product_publication` in `01_product_schema` to enforce nonempty sealed Overview member/header data even when called directly. Retention publishing remains unchanged.
- Regression tests and rollback scripts committed.

## Critical operational finding and correction

The persisted **unpublished Feature Usage candidate #381** was an extra physical generation compared with the mirrored legacy schema. Product shadow cron #47 at 18:58 UTC failed **correctly** with `Snapshot generation parity required first`. This was a staging-integration conflict, not an ingestion failure.

Candidate #381 was verified to have **zero current pointer and publication references**, with exactly 9,377 members, 156 drill headers and one seal. These private-only rows and snapshot were safely removed by a guarded transaction; canonical `public` rows were untouched. Manual `assert_product_shadow_sync_v1(false)` then succeeded, bringing both sides to **560,828 events** at the 19:05 UTC source watermark. All original **58 bidirectional Product table parity checks** passed again with no differences.

Added `20261113002500_product_stage_requires_mirror_parked_v1.sql` to **block durable candidate staging while strict shadow mirror cron #47/#48 is enabled**. Its fail-closed regression passed. A transactional rollback-only staging test remains available for development. Do not deactivate legacy ingestion to stage partial reports.

## Four real report blockers

1. **overview:** Current source calculators cover aggregate KPIs, active charts, workflow and adoption, but no full-fidelity unified payload and drill/card generator. Historical Overview member replay has nine unsupported weekly identities, which must not be fabricated.
2. **overview-funnel:** Complete cohort/root tree and stage membership/card/header generation are absent; the historical snapshot is Nov 5.
3. **overview-module-mix:** Source `build_overview_workflow_source_v1` has a different population/definition from the legacy module-mix payload, so copying its counts or modifying old JSON timestamps would silently change metrics. A definition-verified builder and drill populations are required.
4. **overview-friction:** Source `build_overview_friction_source_v1` uses different eligibility/count definitions than the saved legacy friction payload. For a Nov 11 checkpoint, its current reverted-to-review affected count was 56 versus 59 recorded in legacy; this is a real discrepancy, not a rounding issue. Verify and reconcile meaning before publication.

All four need source-backed complete payloads, exact or explained historical replay, populated drill headers and member cards, and seals. Then test the **complete five-kind candidate in an isolated rollback-only transaction** while strict mirroring remains active. For a durable publication, coordinate pausing strict mirror reconciliation and switching to the new canonical writer, then atomically publish after passing all validation gates. Never make up missing event identities or relabel old reports as current.

## Remaining go/no-go

`PRODUCT_cutover_go_no_go.sql` remains **false**: `uniform_source=false`, `overview_fresh_24h=false`, and both page-manifest flags false. `current_jobs_ok` observed false immediately after cron #47's intentional parity failure; manual reconciliation succeeded after guarded cleanup and the next scheduled execution must independently show success. Keep legacy active and PR #39 draft.
