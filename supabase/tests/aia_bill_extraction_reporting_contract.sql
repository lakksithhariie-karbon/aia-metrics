-- Read-only contract checks for the live reporting view.
-- Every check below must be TRUE. Never print source PII or credentials.
SELECT
  (SELECT COUNT(*) FROM aia_infra.bill_extraction_reporting_v1)
    = (SELECT COUNT(*) FROM aia_infra.bill_costs) AS preserves_row_count,

  (SELECT COUNT(DISTINCT prediction_uuid) FROM aia_infra.bill_extraction_reporting_v1)
    = (SELECT COUNT(*) FROM aia_infra.bill_costs) AS predictions_still_unique,

  NOT EXISTS (
    SELECT 1 FROM aia_infra.bill_costs AS b
    JOIN aia_infra.bill_extraction_reporting_v1 AS v USING (prediction_uuid)
    WHERE b.extraction_cost IS NULL AND b.enrichment_cost IS NULL
      AND v.known_total_cost IS NOT NULL
  ) AS missing_cost_is_not_zero,

  NOT EXISTS (
    SELECT 1 FROM aia_infra.bill_costs AS b
    JOIN aia_infra.bill_extraction_reporting_v1 AS v USING (prediction_uuid)
    WHERE b.extraction_latency IS NULL AND b.enrichment_latency IS NULL
      AND v.known_total_latency IS NOT NULL
  ) AS missing_latency_is_not_zero,

  (SELECT COALESCE(SUM(known_total_cost), 0)
     FROM aia_infra.bill_extraction_reporting_v1)
    = (SELECT COALESCE(SUM(total_cost), 0) FROM aia_infra.bill_costs
       WHERE extraction_cost IS NOT NULL OR enrichment_cost IS NOT NULL)
    AS known_cost_total_reconciles,

  NOT EXISTS (
    SELECT 1 FROM aia_infra.bill_extraction_reporting_v1 AS v
    LEFT JOIN public.company_directory AS d USING (company_uuid)
    WHERE (d.company_uuid IS NULL AND v.company_scope <> 'unverified_company')
      OR (d.company_uuid IS NOT NULL AND d.is_test IS TRUE
          AND v.company_scope <> 'test_company')
  ) AS company_classification_reconciles,

  has_table_privilege('product_metrics_fetcher',
    'aia_infra.bill_extraction_reporting_v1','SELECT') AS designated_reader_has_select,
  NOT has_table_privilege('anon',
    'aia_infra.bill_extraction_reporting_v1','SELECT') AS anon_denied,
  NOT has_table_privilege('authenticated',
    'aia_infra.bill_extraction_reporting_v1','SELECT') AS authenticated_denied,
  NOT has_table_privilege('service_role',
    'aia_infra.bill_extraction_reporting_v1','SELECT') AS unrelated_service_role_denied;
