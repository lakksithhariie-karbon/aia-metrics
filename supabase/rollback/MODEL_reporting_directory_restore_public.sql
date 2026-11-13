-- MANUAL ROLLBACK of Model reporting directory consumer.
-- Restore the existing public Product-directory dependency.
-- Only use in a controlled rollback plan, after confirming public.directory is maintained.
BEGIN;
SET LOCAL lock_timeout='3s';
CREATE OR REPLACE VIEW "04_model_schema".bill_extraction_reporting_v1
WITH (security_barrier=true) AS
SELECT b.prediction_uuid,
    b.file_uuid,
    b.company_uuid,
    a.company_name AS ai_company_name,
    COALESCE(NULLIF(btrim(d.company_name), ''::text), a.company_name) AS company_name,
        CASE
            WHEN d.company_uuid IS NULL THEN 'unverified_company'::text
            WHEN a.is_test OR COALESCE(d.is_test, false) THEN 'test_company'::text
            ELSE 'verified_customer'::text
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
   FROM "04_model_schema".bill_costs b
     JOIN "04_model_schema".companies a ON a.company_uuid = b.company_uuid
     LEFT JOIN public.company_directory d ON d.company_uuid = b.company_uuid;
COMMIT;
