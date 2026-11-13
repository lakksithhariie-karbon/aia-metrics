-- Force full floating-point text precision to match JavaScript snapshot ratios.
-- Rebuild the legacy-compatible Module Mix snapshot from raw numbered-schema events.
-- Critical legacy semantics: count all is_core_activity events for client companies,
-- including test/internal-email records and failed actions. Do not borrow the
-- independent workflow/chart source, which has narrower eligibility rules.
-- Does not stage, publish, or touch public/metrics_private.
CREATE OR REPLACE FUNCTION "01_product_schema".build_overview_module_mix_payload_v1(
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
qualified AS MATERIALIZED(
 SELECT e.company_id,
 CASE WHEN e.event_time>=p.asof-interval '28 days' THEN 'current' ELSE 'previous' END period,
 CASE
  WHEN (e.event_name='Upload' AND lower(btrim(coalesce(e.properties->>'type','')))='bill')
    OR (e.event_name='Entity Created' AND lower(btrim(coalesce(e.properties->>'entityType','')))='bill')
    OR e.event_name IN ('Vendor Mismatch Resolved','Invoice Bulk Edited') THEN 'ap'
  WHEN (e.event_name='Upload' AND lower(btrim(coalesce(e.properties->>'type','')))='invoice')
    OR (e.event_name='Entity Created' AND lower(btrim(coalesce(e.properties->>'entityType','')))='invoice') THEN 'ar'
  WHEN (e.event_name='Upload' AND lower(btrim(coalesce(e.properties->>'type','')))='statement')
    OR e.event_name IN('Transaction Type Updated','Transaction Ledger Updated','Transaction Status','Transaction Configuration Edited')
    THEN 'transactions'
  ELSE 'other' END module
 FROM "01_product_schema".events e
 JOIN "01_product_schema".client_company cc ON cc.company_id=e.company_id
 CROSS JOIN p
 WHERE e.event_time>=p.asof-interval '56 days' AND e.event_time<p.asof
 AND e.ingested_at<=p.wm
 AND "01_product_schema".is_core_activity(e.event_name,e.properties)
),
masks AS MATERIALIZED (
 SELECT q.period,q.company_id,
 (CASE WHEN bool_or(q.module='ap') THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(q.module='ar') THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(q.module='transactions') THEN '1' ELSE '0' END) mask
 FROM qualified q GROUP BY 1,2
),
definitions AS (
 SELECT * FROM (VALUES
  ('001'::text,'transactions_only'::text,'Transactions only'::text,1),
  ('100','ap_only','AP only',2),
  ('101','ap_transactions','AP + Transactions',3),
  ('110','ap_ar','AP + AR',4),
  ('111','ap_ar_transactions','AP + AR + Transactions',5),
  ('010','ar_only','AR only',6),
  ('011','ar_transactions','AR + Transactions',7),
  ('000','other_core','Other core only',8)
 ) k(mask,report_key,label,pos)
),
counts AS MATERIALIZED (
 SELECT d.mask,d.report_key,d.label,d.pos,period.period_name,
 count(m.company_id)::integer n
 FROM definitions d
 CROSS JOIN (VALUES ('current'::text),('previous')) period(period_name)
 LEFT JOIN masks m ON m.mask=d.mask AND m.period=period.period_name
 GROUP BY 1,2,3,4,5
),
totals AS MATERIALIZED(
 SELECT period_name,sum(n)::integer total,
 coalesce(sum(n) FILTER(WHERE mask IN ('101','110','111','011')),0)::integer multi
 FROM counts GROUP BY period_name
),
slots AS MATERIALIZED(
 SELECT d.*,
 coalesce(c.n,0) curr,coalesce(prev.n,0) previous,
 (SELECT total FROM totals WHERE period_name='current') total_current,
 (SELECT total FROM totals WHERE period_name='previous') total_previous,
 (SELECT multi FROM totals WHERE period_name='current') multi_current,
 (SELECT multi FROM totals WHERE period_name='previous') multi_previous
 FROM definitions d
 LEFT JOIN counts c ON c.mask=d.mask AND c.period_name='current'
 LEFT JOIN counts prev ON prev.mask=d.mask AND prev.period_name='previous'
)
SELECT jsonb_build_object('schema',1,'value',jsonb_build_object(
 'buckets',(
 SELECT jsonb_agg(jsonb_build_object(
  'key',s.report_key,'label',s.label,
  'current',jsonb_build_object(
   'companies',s.curr,'core_active_companies',s.total_current,
   'share',CASE WHEN s.total_current>0 THEN s.curr::float8/s.total_current ELSE 0::float8 END),
  'previous',jsonb_build_object(
   'companies',s.previous,'core_active_companies',s.total_previous,
   'share',CASE WHEN s.total_previous>0 THEN s.previous::float8/s.total_previous ELSE 0::float8 END),
  'share_change_pp',CASE WHEN s.total_current>0 AND s.total_previous>0
   THEN round((s.curr::numeric/s.total_current-s.previous::numeric/s.total_previous)*100,1)::float8
   ELSE NULL::float8 END
 ) ORDER BY s.pos) FROM slots s),
 'core_active_companies',(SELECT total FROM totals WHERE period_name='current'),
 'previous_core_active_companies',(SELECT total FROM totals WHERE period_name='previous'),
 'multi_module',jsonb_build_object(
  'label','Multi-module adoption',
  'companies',(SELECT multi FROM totals WHERE period_name='current'),
  'previous_companies',(SELECT multi FROM totals WHERE period_name='previous'),
  'share',(SELECT CASE WHEN total>0 THEN multi::float8/total ELSE 0::float8 END FROM totals WHERE period_name='current'),
  'previous_share',(SELECT CASE WHEN total>0 THEN multi::float8/total ELSE 0::float8 END FROM totals WHERE period_name='previous'),
  'share_change_pp',(SELECT
    CASE WHEN c.total>0 AND v.total>0 THEN round(
    (c.multi::numeric/c.total-v.multi::numeric/v.total)*100,1)::float8
    ELSE NULL::float8 END
    FROM totals c CROSS JOIN totals v
    WHERE c.period_name='current' AND v.period_name='previous')
 ),
 'window_days',28,
 'window_label','Last 28 days',
 'previous_window_label','Previous 28 days',
 'window_start',to_char((p.asof-interval '28 days') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
 'window_end',to_char(p.asof AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
 'previous_start',to_char((p.asof-interval '56 days') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
 'previous_end',to_char((p.asof-interval '28 days') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
))
FROM p;
$fn$;
REVOKE ALL ON FUNCTION "01_product_schema".build_overview_module_mix_payload_v1(timestamptz,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".build_overview_module_mix_payload_v1(timestamptz,timestamptz)
 TO service_role;
