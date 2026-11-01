# AI Services: Bill Extraction reporting contract

**Status:** Live additive reporting view applied 2026-11-01 to Supabase project `hdgbmcerogqfocyxdnpw`. No AI dashboard UI created. No AWS, source-ingestion, production data, or existing reader modifications.

## Source of truth and boundary

- Source: `aia_infra.bill_costs` (prediction-grain rows) joined to `aia_infra.companies`.
- Cross-check for test classification: `public.company_directory` by **company UUID**, never by name.
- Private reader: `aia_infra.bill_extraction_reporting_v1`. Migration recorded in `supabase/migrations/20261101073712_aia_bill_extraction_reporting_v1_20261101.sql` (matches live migration history version).
- Approved Postgres reader: `product_metrics_fetcher`, with SELECT on the view. No SELECT for `anon`, `authenticated`, or regular Supabase `service_role`. Do not grant browser access.
- The view deliberately runs with the owner privileges necessary to inspect `public.company_directory`, whose RLS otherwise prevents the existing reader role from seeing its test flags. It is therefore private and strictly grant-limited. Do not move it to `public`.
- There is no deployed frontend/server adapter yet. Runtime access with an actual `product_metrics_fetcher` connection still needs end-to-end verification; the SQL console cannot assume that role.

## Safe reporting semantics

| Concept | Definition and caveat |
| --- | --- |
| Extraction | One `prediction_uuid`; row grain is one prediction / file in current source |
| Customer inclusion | Default to `company_scope='verified_customer'`. `test_company` and `unverified_company` must be counted separately and excluded from customer-only KPIs |
| Cost | `known_total_cost` is NULL when BOTH components are NULL. Zero is not a substitute for missing costs. Do not use source `total_cost` for charts without this guard |
| Cost per known-cost extraction | `SUM(known_total_cost) / COUNT(known_total_cost)` (within the selected cohort). Disclose the excluded/missing count and coverage. This is NOT total spend per all extractions |
| Cost component breakdown | Only compare extraction vs enrichment cost where `complete_cost_breakdown=true`; 42 observed records are only partially itemized |
| Latency | Use `known_total_latency`; when BOTH latency components are NULL the source zero is not an observed zero. Report coverage |
| Document mix | `doc_type` values: scanned, digital, handwritten, NULL (unknown). Never silently discard unknown |
| Page-based metrics | Use only rows with `total_pages>0` and known cost; show page coverage |
| Review outcomes | Current `review_status` snapshot: reviewed / needs_review / deleted. It is NOT extraction accuracy, a success/failure signal or a review history |
| Legibility | Observed `legibility_score` 0..1 where present. Not a calibrated correctness score |

**Units not confirmed:** neither cost currency nor latency units are defined by schema comments or source documentation. Do not label these USD/seconds until verified from the authoritative exporter.

## Live read-only audit (2026-11-01)

- 36,175 source predictions, 36,175 reporting rows and unique prediction IDs.
- Classification: 34,375 verified-customer rows, 1,541 test-company rows, 259 unverified-company rows (11 unmatched companies).
- 25 companies are marked test in the product directory but not in the AI-specific lookup. This is corrected in **reporting classification**, without overwriting either source.
- 4,688 unknown-cost totals; 2,341 unknown-latency totals; 42 partial cost-component breakdowns.
- 9,036 missing page counts, 408 missing document types, 431 missing legibility scores.
- Summed *known reported* costs reconcile exactly to the supported source subset (1,128.123981 source units). This is **not** a claim of actual total spend.
- All ten checks in `supabase/tests/aia_bill_extraction_reporting_contract.sql` passed.

## Remaining source-level work before claiming full data quality

1. Investigate missing historical cost/latency at the **upstream exporter**. Backfill only verifiable original values, never estimates or imputed zeros. Specifically investigate early August and October 12-22.
2. Verify the meaning, units and aggregation of cost and latency; confirm whether cost means billed vendor amount, estimated model usage or internal accounting.
3. Resolve the 11 unmatched companies and the 430 mismatching company names in AI vs product directory. UUIDs are authoritative and the view uses the product-directory label for matched companies.
4. Address page-count/document-type/legibility missingness in upstream instrumentation.
5. Identify the status machine and revision events before asserting extraction accuracy, model failure, retry rate, or human correction time.
6. Build an authenticated server-side reader using the restricted fetcher role, verify row parity and access in that connection, and reject stale/invalid data. Don't expose raw source tables or credentials to the browser.
7. Add ongoing data completeness/freshness monitoring, not just a one-off audit.

## Verification and rollback

Run the read-only contract in `supabase/tests/aia_bill_extraction_reporting_contract.sql` and confirm every column returns `true`. Verify SQL security advisory results and a real `product_metrics_fetcher` session separately.

Rollback is additive and narrowly scoped: `DROP VIEW IF EXISTS aia_infra.bill_extraction_reporting_v1;`. This does not reverse any data change because none occurred.
