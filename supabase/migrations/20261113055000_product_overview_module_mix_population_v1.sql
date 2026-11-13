-- Source-derived identities for Module Mix in both 28-day periods.
-- Same event and eligibility classification as the byte-exact payload source.
-- Read-only: no snapshot copying, staging, publication or legacy access.
CREATE OR REPLACE FUNCTION "01_product_schema".build_overview_module_mix_population_v1(
 p_as_of_at timestamptz,p_source_watermark_at timestamptz
) RETURNS TABLE(drill_key text,tab text,member_id text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog'
SET statement_timeout TO '100s'
AS $fn$
WITH p AS MATERIALIZED(
 SELECT p_as_of_at asof,p_source_watermark_at wm
 WHERE p_as_of_at IS NOT NULL AND p_source_watermark_at IS NOT NULL
 AND p_as_of_at>=p_source_watermark_at
),
events AS MATERIALIZED(
 SELECT e.company_id,
 CASE WHEN e.event_time>=p.asof-interval '28 days' THEN 'current' ELSE 'previous' END period,
 CASE
  WHEN(e.event_name='Upload' AND lower(btrim(coalesce(e.properties->>'type','')))='bill')
   OR(e.event_name='Entity Created' AND lower(btrim(coalesce(e.properties->>'entityType','')))='bill')
   OR e.event_name IN('Vendor Mismatch Resolved','Invoice Bulk Edited') THEN 'ap'
  WHEN(e.event_name='Upload' AND lower(btrim(coalesce(e.properties->>'type','')))='invoice')
   OR(e.event_name='Entity Created' AND lower(btrim(coalesce(e.properties->>'entityType','')))='invoice') THEN 'ar'
  WHEN(e.event_name='Upload' AND lower(btrim(coalesce(e.properties->>'type','')))='statement')
   OR e.event_name IN('Transaction Type Updated','Transaction Ledger Updated',
     'Transaction Status','Transaction Configuration Edited') THEN 'transactions'
  ELSE 'other' END module
 FROM "01_product_schema".events e
 JOIN "01_product_schema".client_company cc ON cc.company_id=e.company_id
 CROSS JOIN p
 WHERE e.event_time>=p.asof-interval '56 days' AND e.event_time<p.asof
 AND e.ingested_at<=p.wm
 AND "01_product_schema".is_core_activity(e.event_name,e.properties)
),
masked AS (
 SELECT period,company_id,
 (CASE WHEN bool_or(module='ap') THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(module='ar') THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(module='transactions') THEN '1' ELSE '0' END) mask
 FROM events GROUP BY 1,2
),
keys AS (
 SELECT * FROM (VALUES
  ('001'::text,'transactions_only'::text),
  ('100','ap_only'),('101','ap_transactions'),('110','ap_ar'),
  ('111','ap_ar_transactions'),('010','ar_only'),('011','ar_transactions'),
  ('000','other_core')) k(mask,report_key)
)
SELECT k.report_key||':'||m.period AS drill_key,'all'::text AS tab,
 m.company_id AS member_id
FROM masked m JOIN keys k USING(mask);
$fn$;
REVOKE ALL ON FUNCTION "01_product_schema".build_overview_module_mix_population_v1(timestamptz,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".build_overview_module_mix_population_v1(timestamptz,timestamptz)
 TO service_role;
