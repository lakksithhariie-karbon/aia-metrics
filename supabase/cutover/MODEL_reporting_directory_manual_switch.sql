-- MANUAL CROSS-SCHEMA VIEW CUTOVER, NOT DEPLOYED.
-- Existing view grants, owner and security_barrier=true are preserved.
-- Owner approval and Product canonical-writer verification are prerequisites.
-- The SELECT content was verified to yield 38,063 identical rows in both directions.
-- Run only after setting both manual preflight session GUCs to yes.
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '120s';
DO $guard$
BEGIN
 IF current_setting('aia_product_cutover.writer_ready', true) IS DISTINCT FROM 'yes'
   OR current_setting('aia_model_directory_cutover.owner_approved', true) IS DISTINCT FROM 'yes'
 THEN RAISE EXCEPTION 'Model reporting cutover requires canonical Product writer plus explicit Model owner approval';
 END IF;
 IF (SELECT count(*) FROM public.company_directory) <>
    (SELECT count(*) FROM "01_product_schema".company_directory)
 THEN RAISE EXCEPTION 'Product company_directory parity count failed'; END IF;
 IF EXISTS (SELECT to_jsonb(x) v FROM public.company_directory x
            EXCEPT ALL SELECT to_jsonb(y) FROM "01_product_schema".company_directory y)
   OR EXISTS (SELECT to_jsonb(y) v FROM "01_product_schema".company_directory y
              EXCEPT ALL SELECT to_jsonb(x) FROM public.company_directory x)
 THEN RAISE EXCEPTION 'Product company_directory parity contents failed'; END IF;
END $guard$;

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
     LEFT JOIN "01_product_schema".company_directory d ON d.company_uuid = b.company_uuid;
COMMIT;
