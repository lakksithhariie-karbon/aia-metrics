-- Snapshot-pinned aggregate for three adoption cards and the shared
-- mature-integration journey. All counts come from the canonical company facts.
CREATE OR REPLACE FUNCTION public.read_overview_adoption_journey_v1()
RETURNS jsonb
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
SET statement_timeout TO '35s'
AS $function$
WITH published AS MATERIALIZED (
  SELECT s.id,
         (s.payload#>>'{value,active_users,as_of}')::timestamptz AS as_of_at,
         s.source_watermark_at
  FROM public.product_snapshot_current c
  JOIN public.product_snapshot s ON s.id=c.snapshot_id
  WHERE c.kind='overview' AND c.scope_key='' AND s.source_status='ok'
  LIMIT 1
),
facts AS MATERIALIZED (
  SELECT f.* FROM published p CROSS JOIN LATERAL
  public.overview_adoption_company_facts_v1(p.id) AS f
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
  'contract','mature_independent_adoption_v1',
  'snapshot_id',p.id,
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

REVOKE ALL ON FUNCTION public.read_overview_adoption_journey_v1()
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_overview_adoption_journey_v1()
 TO service_role;
