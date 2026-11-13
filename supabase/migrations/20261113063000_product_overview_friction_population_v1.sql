-- Source-derived Friction impact/recovery membership, including three tabs.
-- Eligibility is the same as the legacy-compatible Friction payload; immutable
-- event facts come from numbered Product events, not archived drill rows.
CREATE OR REPLACE FUNCTION "01_product_schema".build_overview_friction_population_v1(
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
normalized AS MATERIALIZED(
 SELECT e.company_id,e.event_time,
 CASE WHEN e.event_time>=p.asof-interval '28 days' THEN 'current' ELSE 'previous' END period,
 e.event_name,
 lower(btrim(coalesce(e.properties->>'status',''))) status,
 lower(btrim(coalesce(e.properties->>'type',''))) activity_type,
 lower(btrim(coalesce(e.properties->>'action',''))) action
 FROM "01_product_schema".events e
 JOIN "01_product_schema".client_company cc ON cc.company_id=e.company_id
 CROSS JOIN p
 WHERE e.event_time>=p.asof-interval '56 days' AND e.event_time<p.asof
 AND e.ingested_at<=p.wm
 AND e.event_name IN('Transaction Status','Upload',
                     'Transaction Type Updated','Transaction Ledger Updated')
),
classified AS(
 SELECT n.*,
 CASE WHEN event_name='Transaction Status' AND
 (status='accounting ready' OR (status='pending' AND action='revert to needs review'))
 THEN 'txn_reverted'
 WHEN event_name='Upload' AND activity_type='bill' AND status IN('failed','success')
 THEN 'bill_upload_failed'
 WHEN event_name='Upload' AND activity_type='invoice' AND status IN('failed','success')
 THEN 'invoice_upload_failed'
 WHEN event_name='Transaction Type Updated' AND status IN('failed','success')
 THEN 'txn_type_failed'
 WHEN event_name='Transaction Ledger Updated' AND status IN('failed','success')
 THEN 'txn_ledger_failed'
 ELSE NULL END issue_key FROM normalized n
),
events AS MATERIALIZED(
 SELECT n.*,
 CASE WHEN n.issue_key='txn_reverted' THEN n.status='pending'
 ELSE n.status='failed' END is_failure,
 CASE WHEN n.issue_key='txn_reverted' THEN n.status='accounting ready'
 ELSE n.status='success' END is_success
 FROM classified n WHERE n.issue_key IS NOT NULL
),
failed AS MATERIALIZED(
 SELECT issue_key,period,company_id,
 max(event_time) AS last_failure_at
 FROM events WHERE is_failure GROUP BY 1,2,3
),
resolved AS (
 SELECT f.*,
 EXISTS(SELECT 1 FROM events e WHERE e.issue_key=f.issue_key
  AND e.period=f.period AND e.company_id=f.company_id
  AND e.is_success AND e.event_time>f.last_failure_at) recovered
 FROM failed f
)
SELECT r.issue_key||':'||r.period AS drill_key,
 t.tab,r.company_id member_id
FROM resolved r
CROSS JOIN LATERAL (VALUES ('all'::text),
 (CASE WHEN r.recovered THEN 'recovered'::text ELSE 'unresolved'::text END)) t(tab);
$fn$;
REVOKE ALL ON FUNCTION "01_product_schema".build_overview_friction_population_v1(timestamptz,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".build_overview_friction_population_v1(timestamptz,timestamptz)
 TO service_role;
