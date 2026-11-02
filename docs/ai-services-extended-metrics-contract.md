# AI Services: operating metrics and reporting coverage (2026-11-02)

## Data source
The production Bill Extraction dashboard calls a **server-only** Supabase RPC, not mock records.
Base metric source: `aia_infra.bill_extraction_reporting_v1`; extended analytics:
`public.read_ai_bill_analytics_v1`, restricted to `service_role`, migration
`20261102030122_aia_bill_analytics_read_v1_20261102.sql`.

Default scope: verified customer companies only. Additional scopes deliberately include
test or unmatched companies; the header help dialog explains all four choices.

## Metrics and precise meaning

| Requested | UI location | Computation and caveat |
| --- | --- | --- |
| AI Spend MTD | Operational economics | Current UTC month through now, **independent of historical date picker**, same company/doc/status/search filters. Sum known cost, unknown explicitly reported |
| Cost per Prediction | At a glance | Average recorded cost among known-cost predictions only, not total cost divided by missing-cost predictions |
| Predictions per Day | Operational economics + daily chart | Selected date range predictions divided by all calendar days including zeros; chart final 30 UTC days of selected range |
| Median Latency | Operational economics | Median `known_total_latency` (nearest-rank/discrete P50); unknown excluded |
| Cost × Latency by Document Type | Cost and throughput diagnostics | Per doc type, known recorded cost and median latency shown **separately** with individual coverage; not mathematical multiplication |
| Cost and Latency by Page Band | Cost and throughput diagnostics | Per band 1, 2–5, 6–10, 11+, unknown; known recorded cost and median latency plus coverage, drill into paginated predictions |
| Documents Processed | At a glance | Number of extraction predictions, **not** verified unique documents |
| Spend on Processed Work | Operational economics | Proxy = known cost on non-deleted review statuses (reviewed + needs_review); **not proof of successful processing** |
| Sunk Cost on Deleted Documents | Operational economics | UI intentionally calls it **Recorded cost on deleted**; unknown cost excluded. No evidence it is unrecoverable/sunk |
| Documents Deleted | Operational economics + Review outcomes | Number of predictions whose **current** review status is `deleted`; not a deletion event history |

All metrics use the same date, scope, document, review and global-search filters, except
MTD is the current month regardless of historical date selection. Every chart/group
offers supporting prediction evidence where applicable; page-band and day evidence
are paginated server-side (10 per page). Query execution is read-only.

## Critical money and unit caveat

**The product owner requested USD ($) display on 2026-11-02.** The preview now
formats all recorded cost numbers in USD using the shared `Intl.NumberFormat` formatter
through KPI cards, cost charts, company tables, investigation evidence and detail modals.
**No conversion is performed.** The upstream numeric source has no currency column,
comment, or authoritative exporter specification, so the display denomination remains
a product-direction assumption, **not independently verified source metadata**.
A visible dashboard footer and modal explanations retain this limitation.
Please obtain an explicit producer confirmation before interpreting reported amounts as
reconciled financial USD spend or promoting this change to production.

Latency values also have unverified units and must not be labeled milliseconds or
seconds without producer confirmation.

## Live evidence checks

For verified customers and Aug–Oct 2026, the service returns **34,364** predictions
and **4,338** unknown-cost predictions. Extended analytics reconcile to the same
34,364 and group them into four document types and five page bands. At the audit
point, deleted-status count was **4,369**, recorded known deleted cost **149.64033849
unverified cost units**, and November MTD contained **31** known-cost predictions.

Database grants: `service_role` EXECUTE true; `anon` and `authenticated`
EXECUTE false. Existing production Vercel Authentication + kill switch remain
unchanged. Source ingestion/fields were not modified.
