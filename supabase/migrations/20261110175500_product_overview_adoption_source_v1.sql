-- Replays the live, mature independent adoption summary from numbered Product
-- events with a frozen watermark. Uses the historical first integration cohort,
-- excludes currently flagged test companies like existing v3 readers.
-- Does not stage snapshots or switch existing readers.
CREATE OR REPLACE FUNCTION "01_product_schema".build_overview_adoption_source_v1(
 p_as_of_at timestamptz,p_source_watermark_at timestamptz)
 RETURNS jsonb
 LANGUAGE sql STABLE SECURITY INVOKER
 SET search_path TO 'pg_catalog'
 SET statement_timeout TO '60s'
AS $function$
WITH published AS MATERIALIZED (
 SELECT p_as_of_at AS as_of_at,p_source_watermark_at AS source_watermark_at
 WHERE p_as_of_at IS NOT NULL AND p_source_watermark_at IS NOT NULL
 AND p_as_of_at >= p_source_watermark_at
),
first_integration AS MATERIALIZED(
 SELECT DISTINCT ON(e.company_id) e.company_id,e.event_time AS integrated_at
 FROM "01_product_schema".events e
 JOIN "01_product_schema".client_company cc ON cc.company_id=e.company_id
 CROSS JOIN published p
 WHERE e.event_time<p.as_of_at-interval '28 days'
 AND e.ingested_at<=p.source_watermark_at
 AND "01_product_schema".is_successful_integration(e.event_name,e.properties)
 ORDER BY e.company_id,e.event_time,e.insert_id
),
base AS MATERIALIZED(
 SELECT f.company_id,f.integrated_at
 FROM first_integration f CROSS JOIN published p
 WHERE f.integrated_at>=p.as_of_at-interval '56 days'
 AND NOT EXISTS(SELECT 1 FROM "01_product_schema".company_directory d
   WHERE d.company_uuid::text=f.company_id AND d.is_test)
),
qualified AS MATERIALIZED (
  SELECT b.company_id,b.integrated_at,e.event_time,e.event_name,e.properties,
    floor(extract(epoch FROM (e.event_time-b.integrated_at))/604800)::int AS rel_week,
    (e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS local_day,
    "01_product_schema".is_qualifying_sync(e.event_name,e.properties) AS is_sync,
    (e.event_name<>'Accounting Sync' AND "01_product_schema".is_core_activity(e.event_name,e.properties))
      AS is_work,
    CASE
      WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill')
        OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill')
        OR e.event_name='Vendor Mismatch Resolved' THEN 'ap'
      WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice')
        OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice')
        OR e.event_name='Invoice Bulk Edited' THEN 'ar'
      ELSE 'transactions'
    END AS module
  FROM base b JOIN "01_product_schema".events e ON e.company_id=b.company_id
  CROSS JOIN published p
  WHERE e.event_time>=b.integrated_at
    AND e.event_time<b.integrated_at+interval '28 days'
    AND e.event_time<p.as_of_at
    AND e.ingested_at<=p.source_watermark_at
    AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
    AND NOT "01_product_schema".is_retention_internal_email_v2(e.email)
    AND (
      (e.event_name<>'Accounting Sync' AND "01_product_schema".is_core_activity(e.event_name,e.properties))
      OR "01_product_schema".is_qualifying_sync(e.event_name,e.properties)
    )
),
activity AS (
  SELECT q.company_id,
    min(q.event_time) FILTER(WHERE q.is_work AND q.rel_week=0) AS first_7,
    min(q.event_time) FILTER(WHERE q.is_work) AS first_28,
    min(q.event_time) FILTER(WHERE q.is_sync) AS first_training,
    count(DISTINCT q.rel_week) FILTER(WHERE q.is_work)::int AS active_weeks,
    count(*) FILTER(WHERE q.is_work)::int AS core_actions,
    count(*) FILTER(WHERE q.is_work AND q.module='ap')::int AS ap_actions,
    count(*) FILTER(WHERE q.is_work AND q.module='ar')::int AS ar_actions,
    count(*) FILTER(WHERE q.is_work AND q.module='transactions')::int AS transaction_actions,
    count(*) FILTER(WHERE q.is_sync)::int AS sync_events,
    max(q.event_time) FILTER(WHERE q.is_work) AS last_core_at,
    jsonb_build_object(
      'bill_upload',count(*) FILTER(WHERE q.is_work AND q.event_name='Upload'
                        AND lower(btrim(q.properties->>'type'))='bill')>0,
      'bill_entity',count(*) FILTER(WHERE q.is_work AND q.event_name='Entity Created'
                        AND lower(btrim(q.properties->>'entityType'))='bill')>0,
      'vendor_mismatch',count(*) FILTER(WHERE q.is_work AND q.event_name='Vendor Mismatch Resolved')>0,
      'invoice_upload',count(*) FILTER(WHERE q.is_work AND q.event_name='Upload'
                        AND lower(btrim(q.properties->>'type'))='invoice')>0,
      'invoice_entity',count(*) FILTER(WHERE q.is_work AND q.event_name='Entity Created'
                        AND lower(btrim(q.properties->>'entityType'))='invoice')>0,
      'invoice_bulk',count(*) FILTER(WHERE q.is_work AND q.event_name='Invoice Bulk Edited')>0,
      'statement_upload',count(*) FILTER(WHERE q.is_work AND q.event_name='Upload'
                        AND lower(btrim(q.properties->>'type'))='statement')>0,
      'transaction_ledger',count(*) FILTER(WHERE q.is_work AND q.event_name='Transaction Ledger Updated')>0,
      'transaction_status',count(*) FILTER(WHERE q.is_work AND q.event_name='Transaction Status')>0,
      'transaction_type',count(*) FILTER(WHERE q.is_work AND q.event_name='Transaction Type Updated')>0
    ) AS step_flags
  FROM qualified q
  GROUP BY q.company_id
),
post_core_sync AS (
  SELECT q.company_id,min(q.event_time) AS sync_at
  FROM qualified q JOIN activity a ON a.company_id=q.company_id
  WHERE a.first_7 IS NOT NULL AND q.is_sync AND q.event_time>a.first_7
  GROUP BY q.company_id
),
post_training_core AS (
  SELECT q.company_id,min(q.event_time) AS post_core_at
  FROM qualified q JOIN activity a ON a.company_id=q.company_id
  WHERE q.is_work AND a.first_training IS NOT NULL
    AND q.local_day > (a.first_training AT TIME ZONE 'Asia/Kolkata')::date
  GROUP BY q.company_id
),
value_completion AS (
  SELECT q.company_id,min(q.event_time) AS value_at
  FROM qualified q JOIN post_training_core t ON t.company_id=q.company_id
  WHERE q.is_sync AND q.event_time>t.post_core_at
  GROUP BY q.company_id
),
facts AS MATERIALIZED(
 SELECT b.company_id,
  a.first_7 AS first_core_7d_at,
  a.first_28 AS first_core_28d_at,
  s.sync_at AS first_sync_after_core_at,
  a.first_training AS training_sync_at,
  t.post_core_at AS post_training_core_at,
  v.value_at,
  coalesce(a.active_weeks,0) AS active_weeks,
  coalesce(a.core_actions,0) AS core_actions,
  coalesce(a.ap_actions,0) AS ap_actions,
  coalesce(a.ar_actions,0) AS ar_actions,
  coalesce(a.transaction_actions,0) AS transaction_actions,
  coalesce(a.sync_events,0) AS sync_events,
  coalesce(a.step_flags,'{}'::jsonb) AS step_flags
 FROM base b
 LEFT JOIN activity a USING(company_id)
 LEFT JOIN post_core_sync s USING(company_id)
 LEFT JOIN post_training_core t USING(company_id)
 LEFT JOIN value_completion v USING(company_id)
),
counts AS (
  SELECT count(*)::integer AS integrated,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL)::integer AS core_7d,
    count(*) FILTER(WHERE first_sync_after_core_at IS NOT NULL)::integer AS sync_after_core,
    count(*) FILTER(WHERE value_at IS NOT NULL)::integer AS value_28d,
    count(*) FILTER(WHERE active_weeks>=2)::integer AS sustained_28d,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL AND ap_actions>0)::integer AS ap_companies,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL AND ar_actions>0)::integer AS ar_companies,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL AND transaction_actions>0)::integer AS txn_companies,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'bill_upload'='true')::integer AS bill_upload,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'bill_entity'='true')::integer AS bill_entity,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'vendor_mismatch'='true')::integer AS vendor_mismatch,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'invoice_upload'='true')::integer AS invoice_upload,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'invoice_entity'='true')::integer AS invoice_entity,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'invoice_bulk'='true')::integer AS invoice_bulk,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'statement_upload'='true')::integer AS statement_upload,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'transaction_ledger'='true')::integer AS transaction_ledger,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'transaction_status'='true')::integer AS transaction_status,
    count(*) FILTER(WHERE first_core_7d_at IS NOT NULL
      AND step_flags->>'transaction_type'='true')::integer AS transaction_type
  FROM facts
)
SELECT jsonb_build_object(
  'contract','overview_adoption_source_v1',
  'as_of',p.as_of_at,
  'source_watermark_at',p.source_watermark_at,
  'cohort_start',p.as_of_at-interval '56 days',
  'cohort_end',p.as_of_at-interval '28 days',
  'total',c.integrated,
  'outcomes',jsonb_build_object(
    'core_7d',c.core_7d,
    'value_28d',c.value_28d,
    'sustained_28d',c.sustained_28d
  ),
  'stages',jsonb_build_object(
    'integration',c.integrated,
    'started_work',c.core_7d,
    'qualifying_sync',c.sync_after_core
  ),
  'modules',jsonb_build_object(
    'ap',c.ap_companies,'ar',c.ar_companies,'transactions',c.txn_companies
  ),
  'steps',jsonb_build_object(
    'bill_upload',c.bill_upload,'bill_entity',c.bill_entity,
    'vendor_mismatch',c.vendor_mismatch,
    'invoice_upload',c.invoice_upload,'invoice_entity',c.invoice_entity,
    'invoice_bulk',c.invoice_bulk,
    'statement_upload',c.statement_upload,
    'transaction_ledger',c.transaction_ledger,
    'transaction_status',c.transaction_status,
    'transaction_type',c.transaction_type
  ),
  'basis',jsonb_build_object(
    'integration','Successful recorded Tally/Zoho integration; mature 28-day cohort',
    'core_7d','Independent qualifying core work within 7 days',
    'qualifying_sync','Qualifying accounting sync after first 7-day core work, within 28 days',
    'value_28d','Integration, training sync, independent core on later IST day, and closing sync, in 28 days',
    'sustained_28d','Independent core work in at least 2 of the first 4 seven-day periods',
    'modules','Overlapping usage in first 28 days among companies that started within 7 days'
  )
)
FROM published p CROSS JOIN counts c;
$function$;
REVOKE ALL ON FUNCTION "01_product_schema".build_overview_adoption_source_v1(timestamptz,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".build_overview_adoption_source_v1(timestamptz,timestamptz) TO service_role;
