-- Private read-only facade for the AI Services dashboard. This code does not
-- change, backfill, or expose the underlying data. Only service_role can call
-- it via PostgREST; all filtering/aggregation runs in Postgres.
CREATE OR REPLACE FUNCTION public.read_ai_bill_extraction_v1(
  p_action text,
  p_from date,
  p_to date,
  p_scopes text[] DEFAULT ARRAY['verified_customer'],
  p_doc text DEFAULT 'all',
  p_status text DEFAULT 'all',
  p_search text DEFAULT '',
  p_drill text DEFAULT 'all',
  p_value text DEFAULT '',
  p_sort text DEFAULT 'createdAt',
  p_direction text DEFAULT 'desc',
  p_offset integer DEFAULT 0,
  p_limit integer DEFAULT 10
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = '' AS $function$
DECLARE output jsonb;
BEGIN
  IF p_action NOT IN ('dashboard','records') OR p_from IS NULL OR p_to IS NULL
    OR p_from > p_to OR p_from < DATE '2020-01-01'
    OR p_to > (CURRENT_DATE + INTERVAL '1 month')::date
    OR COALESCE(array_length(p_scopes, 1), 0) NOT BETWEEN 1 AND 3
    OR p_scopes <@ ARRAY['verified_customer','test_company','unverified_company']::text[] IS NOT TRUE
    OR p_doc NOT IN ('all','scanned','digital','handwritten','unknown')
    OR p_status NOT IN ('all','reviewed','needs_review','deleted','unknown')
    OR length(p_search) > 100 OR length(p_value) > 90
    OR p_sort NOT IN ('createdAt','knownTotalCost','knownTotalLatency')
    OR p_direction NOT IN ('asc','desc')
    OR p_offset < 0 OR p_offset > 100000 OR p_limit < 1 OR p_limit > 50
    OR p_drill NOT IN ('all','known_cost','known_latency','needs_review','month','month_cost','month_latency','components','doc_type','review_status','legibility','company','missing_cost','missing_latency','missing_pages','missing_doc','missing_legibility','partial_breakdown')
  THEN RAISE EXCEPTION 'invalid_bill_reporting_scope' USING ERRCODE='22023'; END IF;
  IF p_action = 'records' AND (
    (p_drill IN ('month','month_cost','month_latency') AND p_value !~ '^20[0-9]{2}-(0[1-9]|1[0-2])$') OR
    (p_drill = 'company' AND p_value !~ '^[0-9a-f-]{36}$') OR
    (p_drill = 'doc_type' AND p_value NOT IN ('scanned','digital','handwritten','unknown')) OR
    (p_drill = 'review_status' AND p_value NOT IN ('reviewed','needs_review','deleted','unknown')) OR
    (p_drill = 'legibility' AND p_value NOT IN ('0–0.2','0.2–0.4','0.4–0.6','0.6–0.8','0.8–1.0','unknown'))
  ) THEN RAISE EXCEPTION 'invalid_bill_drill_scope' USING ERRCODE='22023'; END IF;

  IF p_action = 'dashboard' THEN
    WITH source AS MATERIALIZED (
      SELECT * FROM aia_infra.bill_extraction_reporting_v1 b
      WHERE b.created_at >= p_from::timestamptz AND b.created_at < (p_to + INTERVAL '1 month')::timestamptz
      AND b.company_scope = ANY(p_scopes)
      AND (p_doc='all' OR COALESCE(b.doc_type,'unknown')=p_doc)
      AND (p_status='all' OR COALESCE(b.review_status,'unknown')=p_status)
      AND (p_search='' OR b.company_name ILIKE '%'||p_search||'%' OR b.prediction_uuid::text ILIKE '%'||p_search||'%')
    ),
    months AS (
      SELECT TO_CHAR(created_at AT TIME ZONE 'UTC','YYYY-MM') AS period_month,
        COUNT(*) bills, COALESCE(SUM(known_total_cost),0) known_cost,
        COUNT(*) FILTER (WHERE known_total_cost IS NULL) unknown_cost_count,
        percentile_disc(0.5) WITHIN GROUP (ORDER BY known_total_latency) p50,
        percentile_disc(0.95) WITHIN GROUP (ORDER BY known_total_latency) p95
      FROM source GROUP BY 1 ORDER BY 1
    ),
    docs AS (SELECT COALESCE(doc_type,'unknown') doc_type, COUNT(*) bills,
      COALESCE(SUM(known_total_cost),0) known_cost FROM source GROUP BY 1),
    reviews AS (SELECT COALESCE(review_status,'unknown') review_status,COUNT(*) bills FROM source GROUP BY 1),
    legibility AS (SELECT CASE
      WHEN legibility_score IS NULL THEN 'unknown'
      WHEN legibility_score < 0.2 THEN '0–0.2'
      WHEN legibility_score < 0.4 THEN '0.2–0.4'
      WHEN legibility_score < 0.6 THEN '0.4–0.6'
      WHEN legibility_score < 0.8 THEN '0.6–0.8'
      ELSE '0.8–1.0' END bucket,
      COUNT(*) bills,COUNT(*) FILTER(WHERE review_status='needs_review') needs_review
      FROM source GROUP BY 1),
    companies AS (SELECT company_uuid, MIN(company_name) company_name,
      MIN(company_scope) company_scope, COUNT(*) bills,
      COALESCE(SUM(known_total_cost),0) known_cost,
      COUNT(*) FILTER (WHERE known_total_cost IS NULL) unknown_cost_count,
      COUNT(*) FILTER (WHERE review_status='needs_review') needs_review
      FROM source GROUP BY company_uuid ORDER BY COUNT(*) DESC,MIN(company_name))
    SELECT jsonb_build_object(
      'contract','ai_bill_extraction_live_v1',
      'asOf',(SELECT MAX(loaded_at) FROM aia_infra.bill_extraction_reporting_v1),
      'firstMonth',(SELECT TO_CHAR(MIN(created_at) AT TIME ZONE 'UTC','YYYY-MM') FROM aia_infra.bill_extraction_reporting_v1),
      'kpis',(SELECT jsonb_build_object(
        'bills',COUNT(*),'companies',COUNT(DISTINCT company_uuid),
        'knownCostTotal',COALESCE(SUM(known_total_cost),0),
        'knownCostCount',COUNT(*) FILTER(WHERE known_total_cost IS NOT NULL),
        'unknownCostCount',COUNT(*) FILTER(WHERE known_total_cost IS NULL),
        'avgKnownCost',AVG(known_total_cost),
        'p50Latency',percentile_disc(0.5) WITHIN GROUP (ORDER BY known_total_latency),
        'p95Latency',percentile_disc(0.95) WITHIN GROUP (ORDER BY known_total_latency),
        'knownLatencyCount',COUNT(*) FILTER(WHERE known_total_latency IS NOT NULL),
        'unknownLatencyCount',COUNT(*) FILTER(WHERE known_total_latency IS NULL),
        'needsReviewCount',COUNT(*) FILTER(WHERE review_status='needs_review'),
        'needsReviewRate',CASE WHEN COUNT(*)=0 THEN NULL ELSE COUNT(*) FILTER(WHERE review_status='needs_review')::numeric/COUNT(*) END
      ) FROM source),
      'months',COALESCE((SELECT jsonb_agg(jsonb_build_object('month',period_month,'bills',bills,'knownCost',known_cost,'unknownCostCount',unknown_cost_count,'p50Latency',p50,'p95Latency',p95) ORDER BY period_month) FROM months),'[]'::jsonb),
      'docs',COALESCE((SELECT jsonb_agg(jsonb_build_object('docType',doc_type,'bills',bills,'knownCost',known_cost) ORDER BY doc_type) FROM docs),'[]'::jsonb),
      'reviews',COALESCE((SELECT jsonb_agg(jsonb_build_object('status',review_status,'bills',bills) ORDER BY review_status) FROM reviews),'[]'::jsonb),
      'buckets',COALESCE((SELECT jsonb_agg(jsonb_build_object('bucket',bucket,'bills',bills,'needsReview',needs_review) ORDER BY bucket) FROM legibility),'[]'::jsonb),
      'companies',COALESCE((SELECT jsonb_agg(jsonb_build_object('companyUuid',company_uuid,'companyName',company_name,'scope',company_scope,'bills',bills,'knownCost',known_cost,'unknownCostCount',unknown_cost_count,'needsReview',needs_review) ORDER BY bills DESC,company_name) FROM companies),'[]'::jsonb),
      'components',(SELECT jsonb_build_object('count',COUNT(*),'extraction',COALESCE(SUM(extraction_cost),0),'enrichment',COALESCE(SUM(enrichment_cost),0)) FROM source WHERE complete_cost_breakdown),
      'exceptions',(SELECT jsonb_build_object(
        'missingCost',COUNT(*) FILTER(WHERE known_total_cost IS NULL),
        'missingLatency',COUNT(*) FILTER(WHERE known_total_latency IS NULL),
        'missingPages',COUNT(*) FILTER(WHERE total_pages IS NULL),
        'missingDocType',COUNT(*) FILTER(WHERE doc_type IS NULL),
        'missingLegibility',COUNT(*) FILTER(WHERE legibility_score IS NULL),
        'partialBreakdown',COUNT(*) FILTER(WHERE (extraction_cost IS NULL)<>(enrichment_cost IS NULL)),
        'testScope',COUNT(*) FILTER(WHERE company_scope='test_company'),
        'unverifiedScope',COUNT(*) FILTER(WHERE company_scope='unverified_company')
      ) FROM source)
    ) INTO output;
  ELSE
    WITH source AS MATERIALIZED (
      SELECT * FROM aia_infra.bill_extraction_reporting_v1 b
      WHERE b.created_at >= p_from::timestamptz AND b.created_at < (p_to + INTERVAL '1 month')::timestamptz
      AND b.company_scope=ANY(p_scopes)
      AND (p_doc='all' OR COALESCE(b.doc_type,'unknown')=p_doc)
      AND (p_status='all' OR COALESCE(b.review_status,'unknown')=p_status)
      AND (p_search='' OR b.company_name ILIKE '%'||p_search||'%' OR b.prediction_uuid::text ILIKE '%'||p_search||'%')
    ),
    chosen AS MATERIALIZED (
      SELECT * FROM source b WHERE
        p_drill='all'
        OR (p_drill='known_cost' AND known_total_cost IS NOT NULL)
        OR (p_drill='known_latency' AND known_total_latency IS NOT NULL)
        OR (p_drill='needs_review' AND review_status='needs_review')
        OR (p_drill='month' AND TO_CHAR(created_at AT TIME ZONE 'UTC','YYYY-MM')=p_value)
        OR (p_drill='month_cost' AND TO_CHAR(created_at AT TIME ZONE 'UTC','YYYY-MM')=p_value AND known_total_cost IS NOT NULL)
        OR (p_drill='month_latency' AND TO_CHAR(created_at AT TIME ZONE 'UTC','YYYY-MM')=p_value AND known_total_latency IS NOT NULL)
        OR (p_drill='components' AND complete_cost_breakdown)
        OR (p_drill='doc_type' AND COALESCE(doc_type,'unknown')=p_value)
        OR (p_drill='review_status' AND COALESCE(review_status,'unknown')=p_value)
        OR (p_drill='company' AND company_uuid::text=p_value)
        OR (p_drill='missing_cost' AND known_total_cost IS NULL)
        OR (p_drill='missing_latency' AND known_total_latency IS NULL)
        OR (p_drill='missing_pages' AND total_pages IS NULL)
        OR (p_drill='missing_doc' AND doc_type IS NULL)
        OR (p_drill='missing_legibility' AND legibility_score IS NULL)
        OR (p_drill='partial_breakdown' AND (extraction_cost IS NULL)<>(enrichment_cost IS NULL))
        OR (p_drill='legibility' AND (CASE
          WHEN legibility_score IS NULL THEN 'unknown'
          WHEN legibility_score < 0.2 THEN '0–0.2'
          WHEN legibility_score < 0.4 THEN '0.2–0.4'
          WHEN legibility_score < 0.6 THEN '0.4–0.6'
          WHEN legibility_score < 0.8 THEN '0.6–0.8'
          ELSE '0.8–1.0' END)=p_value)
    ),
    filtered AS MATERIALIZED (
      SELECT * FROM chosen b WHERE p_value IS NOT NULL
      AND (p_action='records')
    ),
    selected AS (
      SELECT * FROM filtered ORDER BY
        CASE WHEN p_sort='createdAt' AND p_direction='asc' THEN created_at END ASC NULLS LAST,
        CASE WHEN p_sort='createdAt' AND p_direction='desc' THEN created_at END DESC NULLS LAST,
        CASE WHEN p_sort='knownTotalCost' AND p_direction='asc' THEN known_total_cost END ASC NULLS LAST,
        CASE WHEN p_sort='knownTotalCost' AND p_direction='desc' THEN known_total_cost END DESC NULLS LAST,
        CASE WHEN p_sort='knownTotalLatency' AND p_direction='asc' THEN known_total_latency END ASC NULLS LAST,
        CASE WHEN p_sort='knownTotalLatency' AND p_direction='desc' THEN known_total_latency END DESC NULLS LAST,
        prediction_uuid DESC LIMIT p_limit OFFSET p_offset
    )
    SELECT jsonb_build_object(
      'contract','ai_bill_extraction_records_v1',
      'total',(SELECT COUNT(*) FROM filtered),
      'knownCostCount',(SELECT COUNT(*) FROM filtered WHERE known_total_cost IS NOT NULL),
      'rows',COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'predictionUuid',prediction_uuid,'fileUuid',file_uuid,'companyUuid',company_uuid,
        'aiCompanyName',ai_company_name,'companyName',company_name,'companyScope',company_scope,
        'createdAt',created_at,'loadedAt',loaded_at,'reviewStatus',review_status,'docType',doc_type,
        'legibilityScore',legibility_score,'totalPages',total_pages,'hasRaw',has_raw,
        'extractionCost',extraction_cost,'enrichmentCost',enrichment_cost,
        'knownTotalCost',known_total_cost,'completeCostBreakdown',complete_cost_breakdown,
        'extractionLatency',extraction_latency,'enrichmentLatency',enrichment_latency,
        'knownTotalLatency',known_total_latency,'completeLatencyBreakdown',complete_latency_breakdown
      )) FROM selected),'[]'::jsonb)
    ) INTO output;
  END IF;
  RETURN output;
END;
$function$;

REVOKE ALL ON FUNCTION public.read_ai_bill_extraction_v1(text,date,date,text[],text,text,text,text,text,text,text,integer,integer) FROM PUBLIC, anon, authenticated, product_metrics_fetcher;
GRANT EXECUTE ON FUNCTION public.read_ai_bill_extraction_v1(text,date,date,text[],text,text,text,text,text,text,text,integer,integer) TO service_role;
COMMENT ON FUNCTION public.read_ai_bill_extraction_v1(text,date,date,text[],text,text,text,text,text,text,text,integer,integer)
IS 'Read-only, service-role-only Bill Extraction dashboard + paginated evidence over the private verified reporting view. Never backfills unknown values.';
