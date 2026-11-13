-- Legacy-compatible five-issue Friction payload computed only from raw
-- numbered Product events. Legacy eligibility counts all client companies,
-- including internal/test-email rows; no silent population narrowing.
-- Historical source replay required; read-only and service-role-only.
CREATE OR REPLACE FUNCTION "01_product_schema".build_overview_friction_payload_v1(
 p_as_of_at timestamptz,p_source_watermark_at timestamptz
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog'
SET statement_timeout TO '100s'
SET extra_float_digits TO '3'
AS $fn$
WITH p AS MATERIALIZED(
 SELECT p_as_of_at asof,p_source_watermark_at wm
 WHERE p_as_of_at IS NOT NULL AND p_source_watermark_at IS NOT NULL
 AND p_as_of_at>=p_source_watermark_at
),
normalized AS MATERIALIZED (
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
 AND e.event_name IN ('Transaction Status','Upload',
                      'Transaction Type Updated','Transaction Ledger Updated')
),
classified AS (
 SELECT n.*,
 CASE
 WHEN event_name='Transaction Status'
  AND (status='accounting ready'
       OR (status='pending' AND action='revert to needs review')) THEN 'txn_reverted'
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
events AS MATERIALIZED (
 SELECT n.*,
 CASE WHEN n.issue_key='txn_reverted' THEN n.status='pending'
 ELSE n.status='failed' END is_failure,
 CASE WHEN n.issue_key='txn_reverted' THEN n.status='accounting ready'
 ELSE n.status='success' END is_success
 FROM classified n WHERE n.issue_key IS NOT NULL
),
company_period AS MATERIALIZED(
 SELECT issue_key,period,company_id,
 count(*) FILTER(WHERE is_failure)::integer failed_events,
 max(event_time) FILTER(WHERE is_failure) last_failure_at
 FROM events GROUP BY 1,2,3
),
company_facts AS MATERIALIZED(
 SELECT g.issue_key,g.period,g.company_id,g.failed_events,
 EXISTS(SELECT 1 FROM events e WHERE
 e.issue_key=g.issue_key AND e.period=g.period AND e.company_id=g.company_id
 AND e.is_success AND e.event_time>g.last_failure_at
 ) AS recovered
 FROM company_period g
),
counts AS MATERIALIZED(
 SELECT issue_key,period,count(*)::integer exposed,
 count(*) FILTER(WHERE failed_events>0)::integer impacted,
 count(*) FILTER(WHERE failed_events>0 AND recovered)::integer recovered,
 count(*) FILTER(WHERE failed_events>0 AND NOT recovered)::integer unresolved
 FROM company_facts GROUP BY 1,2
),
catalog AS (
 SELECT * FROM (VALUES
 ('txn_reverted'::text,'Txn reverted to review'::text,1),
 ('txn_ledger_failed','Txn ledger update failed',2),
 ('txn_type_failed','Txn type update failed',3),
 ('bill_upload_failed','Bill upload failed',4),
 ('invoice_upload_failed','Invoice upload failed',5)
 ) c(k,label,pos)
),
slots AS (
 SELECT k.k,k.label,k.pos,
 coalesce(c.exposed,0) c_exposed,coalesce(c.impacted,0) c_impacted,
 coalesce(c.recovered,0) c_recovered,coalesce(c.unresolved,0) c_unresolved,
 coalesce(v.exposed,0) v_exposed,coalesce(v.impacted,0) v_impacted,
 coalesce(v.recovered,0) v_recovered,coalesce(v.unresolved,0) v_unresolved
 FROM catalog k LEFT JOIN counts c ON c.issue_key=k.k AND c.period='current'
 LEFT JOIN counts v ON v.issue_key=k.k AND v.period='previous'
)
SELECT jsonb_build_object('schema',1,'value',jsonb_build_object(
 'window_days',28,'window_label','Last 28 days',
 'previous_window_label','Previous 28 days',
 'window_start',to_char((p.asof-interval '28 days') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
 'window_end',to_char(p.asof AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
 'previous_start',to_char((p.asof-interval '56 days') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
 'previous_end',to_char((p.asof-interval '28 days') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
 'issues',(
 SELECT jsonb_agg(jsonb_build_object(
  'key',s.k,'label',s.label,
  'current',jsonb_build_object(
    'exposed',s.c_exposed,'impacted',s.c_impacted,
    'recovered',s.c_recovered,'unresolved',s.c_unresolved,
    'incidence',CASE WHEN s.c_exposed>0 THEN s.c_impacted::float8/s.c_exposed ELSE 0::float8 END,
    'recovery_rate',CASE WHEN s.c_impacted>0 THEN s.c_recovered::float8/s.c_impacted ELSE 0::float8 END),
  'previous',jsonb_build_object(
    'exposed',s.v_exposed,'impacted',s.v_impacted,
    'recovered',s.v_recovered,'unresolved',s.v_unresolved,
    'incidence',CASE WHEN s.v_exposed>0 THEN s.v_impacted::float8/s.v_exposed ELSE 0::float8 END,
    'recovery_rate',CASE WHEN s.v_impacted>0 THEN s.v_recovered::float8/s.v_impacted ELSE 0::float8 END),
  'incidence_change_pp',
    CASE WHEN s.c_exposed>0 AND s.v_exposed>0 THEN
      round((s.c_impacted::numeric/s.c_exposed-
             s.v_impacted::numeric/s.v_exposed)*100,1)::float8
    ELSE NULL::float8 END
 ) ORDER BY s.pos) FROM slots s)
)) FROM p;
$fn$;
REVOKE ALL ON FUNCTION "01_product_schema".build_overview_friction_payload_v1(timestamptz,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".build_overview_friction_payload_v1(timestamptz,timestamptz)
 TO service_role;
