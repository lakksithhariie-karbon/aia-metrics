-- Frozen-watermark feature-usage drill membership, computed only from real Product events.
-- No card generation, staging, seals, publication, pointer or cron changes.
-- All 46,925 historical memberships replayed exactly in read-only validation.
CREATE OR REPLACE FUNCTION "01_product_schema".build_overview_feature_usage_population_v1(
  p_as_of_at timestamptz,p_source_watermark_at timestamptz
)
RETURNS TABLE(drill_key text,tab text,member_id text)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog'
SET statement_timeout TO '100s'
AS $fn$
WITH params AS MATERIALIZED (
 SELECT p_as_of_at AS asof,p_source_watermark_at AS wm,
 date_trunc('week',p_as_of_at AT TIME ZONE 'Asia/Kolkata')::date current_week
 WHERE p_as_of_at IS NOT NULL AND p_source_watermark_at IS NOT NULL
  AND p_as_of_at >= p_source_watermark_at
), weeks AS MATERIALIZED(
 SELECT (p.current_week-n*7)::date ws,p.wm FROM params p
 CROSS JOIN generate_series(1,12) n
), ev AS MATERIALIZED(
 SELECT w.ws,e.company_id,e.event_name,
 lower(btrim(coalesce(e.properties->>'type',''))) ty,
 lower(btrim(coalesce(e.properties->>'entityType',''))) et,
 lower(btrim(coalesce(e.properties->>'status',''))) st
 FROM weeks w
 JOIN "01_product_schema".events e
 ON e.event_time >=(w.ws::timestamp AT TIME ZONE 'Asia/Kolkata')
 AND e.event_time <((w.ws+7)::timestamp AT TIME ZONE 'Asia/Kolkata')
 AND e.ingested_at<=w.wm
 JOIN "01_product_schema".client_company cc ON cc.company_id=e.company_id
), coded AS (
 SELECT ws,company_id,
 CASE WHEN (event_name='Upload' AND ty='bill')
   OR (event_name='Entity Created' AND et='bill')
   OR event_name IN('Vendor Mismatch Resolved','Invoice Bulk Edited') THEN 'ap'
 WHEN (event_name='Upload' AND ty='invoice')
   OR (event_name='Entity Created' AND et='invoice') THEN 'ar'
 WHEN (event_name='Upload' AND ty='statement')
   OR event_name IN('Transaction Type Updated','Transaction Ledger Updated',
                    'Transaction Status','Transaction Configuration Edited') THEN 'transactions'
 END module,
 CASE WHEN event_name='Upload' AND ty='bill' THEN 'bill_upload'
 WHEN event_name='Entity Created' AND et='bill' THEN 'bill_entity'
 WHEN event_name IN('Vendor Mismatch Resolved','Invoice Bulk Edited') THEN 'review_correction'
 WHEN event_name='Upload' AND ty='invoice' THEN 'invoice_upload'
 WHEN event_name='Entity Created' AND et='invoice' THEN 'invoice_entity'
 WHEN event_name='Upload' AND ty='statement' THEN 'statement_upload'
 WHEN event_name='Transaction Type Updated' THEN 'type_updated'
 WHEN event_name='Transaction Ledger Updated' THEN 'ledger_updated'
 WHEN event_name='Transaction Status' AND st='accounting ready' THEN 'accounting_ready'
 WHEN event_name='Transaction Configuration Edited' THEN 'config_edited'
 END feature
 FROM ev
)
SELECT DISTINCT module||':'||to_char(ws,'YYYY-MM-DD') AS drill_key,
 'all'::text AS tab,company_id AS member_id
FROM coded WHERE module IS NOT NULL
UNION
SELECT DISTINCT module||':'||to_char(ws,'YYYY-MM-DD'),feature,company_id
FROM coded WHERE module IS NOT NULL AND feature IS NOT NULL;
$fn$;
REVOKE ALL ON FUNCTION "01_product_schema".build_overview_feature_usage_population_v1(timestamptz,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".build_overview_feature_usage_population_v1(timestamptz,timestamptz)
 TO service_role;
