-- Additive, read-only reporting contract for AI bill extraction.
-- Source tables, ingestion jobs, AWS cost tables, and existing readers remain unchanged.
-- This reporting view is PRIVATE: aia_infra is not a public client API.
-- Explicit owner-privileged view is required solely for cross-checking
-- public.company_directory (RLS restricts product_metrics_fetcher there).
-- Only the existing read-only product_metrics_fetcher role is granted SELECT.

CREATE VIEW aia_infra.bill_extraction_reporting_v1
WITH (security_barrier = true)
AS
SELECT
  b.prediction_uuid,
  b.file_uuid,
  b.company_uuid,
  a.company_name AS ai_company_name,
  COALESCE(NULLIF(BTRIM(d.company_name), ''), a.company_name) AS company_name,
  CASE
    WHEN d.company_uuid IS NULL THEN 'unverified_company'
    WHEN a.is_test OR COALESCE(d.is_test, false) THEN 'test_company'
    ELSE 'verified_customer'
  END AS company_scope,
  b.created_at,
  b.loaded_at,
  b.review_status,
  b.doc_type,
  b.legibility_score,
  b.total_pages,
  b.has_raw,
  b.extraction_cost,
  b.enrichment_cost,
  CASE
    WHEN b.extraction_cost IS NULL AND b.enrichment_cost IS NULL THEN NULL::numeric
    ELSE b.total_cost
  END AS known_total_cost,
  b.extraction_cost IS NOT NULL AND b.enrichment_cost IS NOT NULL AS complete_cost_breakdown,
  b.extraction_latency,
  b.enrichment_latency,
  CASE
    WHEN b.extraction_latency IS NULL AND b.enrichment_latency IS NULL THEN NULL::numeric
    ELSE b.total_latency
  END AS known_total_latency,
  b.extraction_latency IS NOT NULL AND b.enrichment_latency IS NOT NULL AS complete_latency_breakdown
FROM aia_infra.bill_costs AS b
INNER JOIN aia_infra.companies AS a ON a.company_uuid = b.company_uuid
LEFT JOIN public.company_directory AS d ON d.company_uuid = b.company_uuid;

-- The owner-privileged join above must never grant access through anon,
-- authenticated or the normal Supabase API service_role. Only an already
-- approved, server-side Postgres connection using this existing reader may query.
REVOKE ALL ON aia_infra.bill_extraction_reporting_v1
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON aia_infra.bill_extraction_reporting_v1 TO product_metrics_fetcher;

COMMENT ON VIEW aia_infra.bill_extraction_reporting_v1 IS
  'Private AI bill extraction reporting v1. Missing component pairs are reported as NULL totals rather than zero; company_scope reconciles public.company_directory test flags and explicitly quarantines unmatched companies. Do not infer cost currency, latency units, extraction accuracy or review transitions from this view.';

COMMENT ON COLUMN aia_infra.bill_extraction_reporting_v1.known_total_cost IS
  'Source total_cost unless BOTH component costs are missing; NULL means unknown, not free. Currency is not verified.';
COMMENT ON COLUMN aia_infra.bill_extraction_reporting_v1.known_total_latency IS
  'Source total_latency unless BOTH component latencies are missing; NULL means unknown. Units are not verified.';
COMMENT ON COLUMN aia_infra.bill_extraction_reporting_v1.company_scope IS
  'verified_customer, test_company, or unverified_company. Production customer dashboards should default to verified_customer only.';

-- Rollback (review before use):
-- DROP VIEW IF EXISTS aia_infra.bill_extraction_reporting_v1;
