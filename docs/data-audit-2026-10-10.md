# Product Metrics: data audit

**Audited:** 10 October 2026 (IST)  
**Scope:** Product Overview, Retention & Churn, Companies  
**Decision:** Arithmetic verified. **Not approved as issue-free customer analytics** until the policy and instrumentation issues below are resolved.  
**Method:** Read-only queries against Supabase, independent raw-event recomputations, drill population checks, Mixpanel telemetry comparison. No data or production metrics were changed.

## Source freshness

| Current chart family | Source | Watermark (UTC) |
| --- | --- | --- |
| Product Overview | Published overview snapshot 276 | 2026-10-10 02:05:18 |
| Companies | Monthly Companies cache | 2026-10-10 04:05:19 |
| Retention / Churn | Live retention v4/v3 materialization | 2026-10-10 05:05:20 |

Older retention-summary/heatmap snapshot records last updated 8 Oct are not used by the **live Retention v4 page**. The page reads fresh retention_v3 materializations. Cross-page panels do not share one single global ingestion watermark.

## Calculations independently reconciled

| Chart or card | Audited value | Checks |
| --- | --- | --- |
| WAU | 150 current, 154 prior | Both matched independent distinct-user computation |
| MAU | 439 current, 313 prior | Both matched independent distinct-user computation |
| Weekly activity | 12 completed weeks | Each weekly count and First Observed/Returning split matched |
| Usage frequency | 285 + 61 + 24 + 44 = 414 | All 4 buckets matched |
| Module combinations | 434 current companies, 146 multi-module; 421 prior, 118 multi-module | Every module-combination cell matched raw event classification |
| Adoption | 387 integrations in the mature rolling 28-day cohort (integrated 28–56 days before cutoff); 250 first-week adopters; 79 value-converted; 60 sustained | All cohort outcome counts matched |
| Integration journey | 387 → 250 → 205 | Each stage matched its company fact population |
| Issues that need attention | Five issue types, current and previous windows | 10/10 company-population counts matched |
| Retention heatmap | 40 September–October cells | 0 mismatches, including 34 properly incomplete cells; 549 September core-active company-days exactly match raw events |
| September churn | 97 churned / 144 eligible = 67.4% | Eligible and churned company counts matched |
| Companies Oct integration cohort | 108 companies; AP 859, AR 19, Transactions 1,494, GST 23 | All four module totals matched raw events; zero company/user rollup differences |
| Sample drill populations | AP users 103, AP+Transactions companies 109, adoption companies 250, issue companies 2 | Drill denominators matched parent charts |

Matching calculations is **not** proof that upstream events were fully captured or categorized correctly.

## Issues preventing full data sign-off

### 1. May–July tracking gap

Recorded successful integrations: May **88**, June **11**, July **11**, August **327**, September **435**. Accounting Sync volumes: June **3,103**, July **5,185**. Mixpanel and Supabase agree on monthly raw event counts, showing that the missing June/July events are already absent from source analytics. The PM confirmed product stabilization disrupted event collection.

Integration-based customer cohorts can be understated. The warehouse begins **1 March 2026**, while earlier events exist in Mixpanel.

**Needed:** Backfill confirmed integrations using authoritative product state, not inferred Accounting Sync alone. Historical cohort trends remain incomplete until then.

The Overview mature integration cohort is a **rolling 28-day intake window, ending 28 days before as-of**, not all historical mature integrations. In that exact window, raw strictly eligible integration events identify **386 companies**, while the published cohort has **387**: one customer has a successful integration event recorded only by an internal staff email. This is a cross-page eligibility-rule difference, not a 324-company materialization loss.

### 2. Marked test companies enter customer metrics

The directory's **is_test** attribute is not applied consistently:

- WAU **150 → 147** after excluding marked-test-company events
- MAU **439 → 430**
- Current core-active company population **434**, including **9** marked tests
- September churn **97/144 = 67.4%** → **94/141 = 66.7%** after excluding marked tests
- Mature adoption cohort **387**, with no marked tests at this cutoff

**Needed:** Confirm reliable test labeling and decide whether customer analytics exclude test companies, then use the same policy everywhere.

Companies also admits **9** companies whose first successful integration was observed only through internal-staff activity (1 May, 6 August, 1 September, 1 October). Retention uses a stricter non-internal integration rule. Decide whether staff-assisted customer integrations count; apply one documented policy across pages.

### 3. Companies treats failed attempts as usage

Companies displays **mapped event occurrences**, not just successful work: failures, downloads and deletions count.

In the September first-integration company cohort, **615 of 9,668 AP events (6.4%)** were failed. **444** failed Invoice Bulk Edited events contributed to that AP count. Across all September events, Invoice Bulk Edited had **660 records, all marked Failed**.

The Companies classifier maps Invoice Bulk Edited to AP. Product Overview's hypothetical mapping puts it under AR, but all of these recent failed events are excluded from Overview's independent core work. The immediate problem is counting failed attempts as completed usage, not two successful counters disagreeing.

The Issues widget also omits Invoice Bulk Edited failures because the product does not consistently record the matching successful attempt needed for its incident denominator.

**Needed:** Define whether Companies means events attempted or successful work. If the latter, exclude failed attempts and align module classification. Instrument bulk-edit successes before calculating incident rates.

### 4. Retention counts Accounting Sync as core activity

Retention core-active days include Accounting Sync (with no manual/automatic attribution). Product Overview's independent core metrics exclude Accounting Sync.

For the **14 September activated cohort, Week 1**, Retention reports **11/19 = 57.9%**; excluding sync-only activity yields **9/19 = 47.4%**. September churn happens to remain **97/144** under both rules.

**Needed:** Align on one intended definition (any workflow activity vs independent core work). If standardizing, rebuild Retention activity; do not call current Retention percentages independent-human-work percentages.

### 5. Different data cutoffs and access model

Overview, Companies and Retention use distinct, recently published watermarks. Date differences must be visible when comparing panels.

Several raw warehouse tables lack Postgres row-level security, although direct anonymous/authenticated SELECT grants on the audited raw tables are absent. The audited summary RPCs also reject those roles. Review defense in depth separately; no unauthenticated public read was established.

## Info dialog work on this preview

All **18** info explanations (12 Overview, 5 Retention, 1 Companies) now give one direct calculation rule, one brief example and only essential caveats. They explicitly disclose included sync activity, marked tests, failed Companies events and historical gaps. No SQL or business metric changes were made.

## Release recommendation

**Arithmetic: PASS. Historical completeness and cross-page semantic consistency: NOT YET CLEARED.**

Use recent metrics cautiously with their explicit definitions. Obtain decisions for the issues above, make data-source or instrumentation changes, rebuild affected outputs and rerun reconciliation before promising issue-free customer analytics.
