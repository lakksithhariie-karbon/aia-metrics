-- Additive read-only analytics over the private, verified reporting view.
-- Data currency and latency units remain unverified. Deleted is a status snapshot,
-- not proof of a failed model operation or a sunk-cost accounting classification.
CREATE OR REPLACE FUNCTION public.read_ai_bill_analytics_v1(
  p_action text,
  p_from date,
  p_to date,
  p_scopes text[] DEFAULT ARRAY['verified_customer'],
  p_doc text DEFAULT 'all',
  p_status text DEFAULT 'all',
  p_search text DEFAULT '',
  p_drill text DEFAULT 'page_band',
  p_value text DEFAULT '',
  p_sort text DEFAULT 'createdAt',
  p_direction text DEFAULT 'desc',
  p_offset integer DEFAULT 0,
  p_limit integer DEFAULT 10
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = '' AS $function$
DECLARE result jsonb;
BEGIN
  IF p_action NOT IN ('dashboard','records') OR p_from IS NULL OR p_to IS NULL
    OR p_from > p_to OR p_from < DATE '2020-01-01'
    OR p_to > (CURRENT_DATE + INTERVAL '1 month')::date
    OR COALESCE(array_length(p_scopes,1),0) NOT BETWEEN 1 AND 3
    OR (p_scopes <@ ARRAY['verified_customer','test_company','unverified_company']::text[]) IS NOT TRUE
    OR p_doc NOT IN ('all','scanned','digital','handwritten','unknown')
    OR p_status NOT IN ('all','reviewed','needs_review','deleted','unknown')
    OR length(COALESCE(p_search,'')) > 100
    OR p_drill NOT IN ('page_band','day')
    OR length(COALESCE(p_value,'')) > 20
    OR p_sort NOT IN ('createdAt','knownTotalCost','knownTotalLatency')
    OR p_direction NOT IN ('asc','desc') OR p_offset < 0 OR p_offset > 100000
    OR p_limit NOT BETWEEN 1 AND 50
    OR (p_action='records' AND (
      (p_drill='page_band' AND p_value NOT IN ('1','2-5','6-10','11+','unknown'))
      OR (p_drill='day' AND (p_value !~ '^20[0-9]{2}-(0[1-9]|1[0-2])-([0-2][0-9]|3[01])$'
        OR TO_CHAR(TO_DATE(p_value,'YYYY-MM-DD'),'YYYY-MM-DD')<>p_value))
    ))
  THEN RAISE EXCEPTION 'invalid_ai_bill_analytics_scope' USING ERRCODE='22023'; END IF;

  IF p_action = 'dashboard' THEN
    WITH source AS MATERIALIZED (
      SELECT b.* FROM aia_infra.bill_extraction_reporting_v1 b
      WHERE b.created_at >= p_from::timestamptz
        AND b.created_at < (p_to+INTERVAL '1 month')::timestamptz
        AND b.company_scope=ANY(p_scopes)
        AND (p_doc='all' OR COALESCE(b.doc_type,'unknown')=p_doc)
        AND (p_status='all' OR COALESCE(b.review_status,'unknown')=p_status)
        AND (p_search='' OR b.company_name ILIKE '%'||p_search||'%'
             OR b.prediction_uuid::text ILIKE '%'||p_search||'%')
    ), current_month AS MATERIALIZED (
      SELECT b.known_total_cost FROM aia_infra.bill_extraction_reporting_v1 b
      WHERE b.created_at >= date_trunc('month',now() AT TIME ZONE 'UTC')::timestamptz
        AND b.created_at <= now()
        AND b.company_scope=ANY(p_scopes)
        AND (p_doc='all' OR COALESCE(b.doc_type,'unknown')=p_doc)
        AND (p_status='all' OR COALESCE(b.review_status,'unknown')=p_status)
        AND (p_search='' OR b.company_name ILIKE '%'||p_search||'%'
             OR b.prediction_uuid::text ILIKE '%'||p_search||'%')
    ), docs AS (
      SELECT COALESCE(doc_type,'unknown') AS name,COUNT(*) AS n,
        COUNT(known_total_cost) AS cost_n,COALESCE(SUM(known_total_cost),0) AS total_cost,
        COUNT(known_total_latency) AS latency_n,
        percentile_disc(0.5) WITHIN GROUP(ORDER BY known_total_latency) AS p50,
        percentile_disc(0.95) WITHIN GROUP(ORDER BY known_total_latency) AS p95
      FROM source GROUP BY 1
    ), page_groups AS (
      SELECT CASE WHEN total_pages IS NULL OR total_pages<=0 THEN 'unknown'
         WHEN total_pages=1 THEN '1'
         WHEN total_pages<=5 THEN '2-5'
         WHEN total_pages<=10 THEN '6-10'
         ELSE '11+' END AS name,
        COUNT(*) AS n,COUNT(known_total_cost) AS cost_n,
        COALESCE(SUM(known_total_cost),0) AS total_cost,
        COUNT(known_total_latency) AS latency_n,
        percentile_disc(0.5) WITHIN GROUP(ORDER BY known_total_latency) AS p50,
        percentile_disc(0.95) WITHIN GROUP(ORDER BY known_total_latency) AS p95
      FROM source GROUP BY 1
    ), days AS (
      SELECT TO_CHAR(created_at AT TIME ZONE 'UTC','YYYY-MM-DD') AS name,COUNT(*) AS n
      FROM source WHERE created_at >= GREATEST(p_from::timestamptz,(p_to+INTERVAL '1 month')::timestamptz-INTERVAL '30 days')
      GROUP BY 1 ORDER BY 1
    )
    SELECT jsonb_build_object(
      'contract','ai_bill_analytics_v1',
      'currency','unverified',
      'periodDays',((p_to+INTERVAL '1 month')::date-p_from)::int,
      'selected',(SELECT jsonb_build_object(
         'predictions',COUNT(*),
         'dailyAverage',CASE WHEN ((p_to+INTERVAL '1 month')::date-p_from)>0
            THEN COUNT(*)::numeric/((p_to+INTERVAL '1 month')::date-p_from) ELSE NULL END,
         'reviewedCount',COUNT(*) FILTER(WHERE review_status='reviewed'),
         'reviewedCost',COALESCE(SUM(known_total_cost) FILTER(WHERE review_status='reviewed'),0),
         'reviewedKnown',COUNT(known_total_cost) FILTER(WHERE review_status='reviewed'),
         'reviewedUnknown',COUNT(*) FILTER(WHERE review_status='reviewed' AND known_total_cost IS NULL),
         'nonDeletedCost',COALESCE(SUM(known_total_cost) FILTER(WHERE review_status IS DISTINCT FROM 'deleted'),0),
         'nonDeletedKnown',COUNT(known_total_cost) FILTER(WHERE review_status IS DISTINCT FROM 'deleted'),
         'nonDeletedUnknown',COUNT(*) FILTER(WHERE review_status IS DISTINCT FROM 'deleted' AND known_total_cost IS NULL),
         'deletedCount',COUNT(*) FILTER(WHERE review_status='deleted'),
         'deletedCost',COALESCE(SUM(known_total_cost) FILTER(WHERE review_status='deleted'),0),
         'deletedKnown',COUNT(known_total_cost) FILTER(WHERE review_status='deleted'),
         'deletedUnknown',COUNT(*) FILTER(WHERE review_status='deleted' AND known_total_cost IS NULL)
       ) FROM source),
      'mtd',(SELECT jsonb_build_object(
         'month',TO_CHAR(now() AT TIME ZONE 'UTC','YYYY-MM'),
         'predictions',COUNT(*),'knownCost',COALESCE(SUM(known_total_cost),0),
         'knownCount',COUNT(known_total_cost),
         'unknownCount',COUNT(*) FILTER(WHERE known_total_cost IS NULL)
       ) FROM current_month),
      'daily',COALESCE((SELECT jsonb_agg(jsonb_build_object('day',name,'predictions',n) ORDER BY name) FROM days),'[]'::jsonb),
      'docAnalytics',COALESCE((SELECT jsonb_agg(jsonb_build_object('label',name,'predictions',n,
         'knownCost',total_cost,'knownCostCount',cost_n,'unknownCostCount',n-cost_n,
         'medianLatency',p50,'p95Latency',p95,'knownLatencyCount',latency_n) ORDER BY name) FROM docs),'[]'::jsonb),
      'pageAnalytics',COALESCE((SELECT jsonb_agg(jsonb_build_object('label',name,'predictions',n,
         'knownCost',total_cost,'knownCostCount',cost_n,'unknownCostCount',n-cost_n,
         'medianLatency',p50,'p95Latency',p95,'knownLatencyCount',latency_n) ORDER BY CASE name WHEN '1' THEN 1 WHEN '2-5' THEN 2 WHEN '6-10' THEN 3 WHEN '11+' THEN 4 ELSE 5 END) FROM page_groups),'[]'::jsonb)
    ) INTO result;
  ELSE
    WITH source AS MATERIALIZED (
      SELECT b.* FROM aia_infra.bill_extraction_reporting_v1 b
      WHERE b.created_at >= p_from::timestamptz
        AND b.created_at < (p_to+INTERVAL '1 month')::timestamptz
        AND b.company_scope=ANY(p_scopes)
        AND (p_doc='all' OR COALESCE(b.doc_type,'unknown')=p_doc)
        AND (p_status='all' OR COALESCE(b.review_status,'unknown')=p_status)
        AND (p_search='' OR b.company_name ILIKE '%'||p_search||'%'
             OR b.prediction_uuid::text ILIKE '%'||p_search||'%')
    ), chosen AS MATERIALIZED (
      SELECT * FROM source
      WHERE (p_drill='page_band' AND (CASE WHEN total_pages IS NULL OR total_pages<=0 THEN 'unknown'
         WHEN total_pages=1 THEN '1' WHEN total_pages<=5 THEN '2-5' WHEN total_pages<=10 THEN '6-10' ELSE '11+' END)=p_value)
         OR (p_drill='day' AND TO_CHAR(created_at AT TIME ZONE 'UTC','YYYY-MM-DD')=p_value)
    ), selected AS (
      SELECT * FROM chosen ORDER BY
        CASE WHEN p_sort='createdAt' AND p_direction='asc' THEN created_at END ASC NULLS LAST,
        CASE WHEN p_sort='createdAt' AND p_direction='desc' THEN created_at END DESC NULLS LAST,
        CASE WHEN p_sort='knownTotalCost' AND p_direction='asc' THEN known_total_cost END ASC NULLS LAST,
        CASE WHEN p_sort='knownTotalCost' AND p_direction='desc' THEN known_total_cost END DESC NULLS LAST,
        CASE WHEN p_sort='knownTotalLatency' AND p_direction='asc' THEN known_total_latency END ASC NULLS LAST,
        CASE WHEN p_sort='knownTotalLatency' AND p_direction='desc' THEN known_total_latency END DESC NULLS LAST,
        prediction_uuid DESC LIMIT p_limit OFFSET p_offset
    )
    SELECT jsonb_build_object('contract','ai_bill_extraction_records_v1',
      'total',(SELECT COUNT(*) FROM chosen),
      'knownCostCount',(SELECT COUNT(known_total_cost) FROM chosen),
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
    ) INTO result;
  END IF;
  RETURN result;
END;
$function$;

REVOKE ALL ON FUNCTION public.read_ai_bill_analytics_v1(text,date,date,text[],text,text,text,text,text,text,text,integer,integer) FROM PUBLIC, anon, authenticated, product_metrics_fetcher;
GRANT EXECUTE ON FUNCTION public.read_ai_bill_analytics_v1(text,date,date,text[],text,text,text,text,text,text,text,integer,integer) TO service_role;
COMMENT ON FUNCTION public.read_ai_bill_analytics_v1(text,date,date,text[],text,text,text,text,text,text,text,integer,integer)
 IS 'Read-only, service_role-only extended bill analytics and paginated day/page-band evidence. Currency unknown; deleted status is a snapshot, not a proven sunk cost.';