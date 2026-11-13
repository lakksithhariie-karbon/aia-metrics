-- Read-only reconstruction of Module Mix company cards from frozen events.
-- Historical name/integration/actor metadata is deliberately not copied from
-- old snapshots. Compare event facts exactly, and document mutable differences.
CREATE OR REPLACE FUNCTION "01_product_schema".build_overview_module_mix_cards_v1(
 p_as_of_at timestamptz,p_source_watermark_at timestamptz
) RETURNS TABLE(drill_key text,tab text,member_id text,sort_position integer,card jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog'
SET statement_timeout TO '115s'
SET extra_float_digits TO '3'
AS $fn$
WITH p AS MATERIALIZED (
 SELECT p_as_of_at asof,p_source_watermark_at wm
 WHERE p_as_of_at IS NOT NULL AND p_source_watermark_at IS NOT NULL
 AND p_as_of_at>=p_source_watermark_at
),
classified AS MATERIALIZED (
 SELECT e.company_id,e.email,e.distinct_id,e.event_time,e.insert_id,
 CASE WHEN e.event_time>=p.asof-interval '28 days'
 THEN 'current' ELSE 'previous' END period,
 CASE
 WHEN e.event_name='Upload' AND lower(btrim(coalesce(e.properties->>'type','')))='bill' THEN 'bill_upload'
 WHEN e.event_name='Entity Created' AND lower(btrim(coalesce(e.properties->>'entityType','')))='bill' THEN 'bill_entity'
 WHEN e.event_name='Invoice Bulk Edited' THEN 'invoice_bulk_edited'
 WHEN e.event_name='Vendor Mismatch Resolved' THEN 'vendor_mismatch'
 WHEN e.event_name='Upload' AND lower(btrim(coalesce(e.properties->>'type','')))='invoice' THEN 'invoice_upload'
 WHEN e.event_name='Entity Created' AND lower(btrim(coalesce(e.properties->>'entityType','')))='invoice' THEN 'invoice_entity'
 WHEN e.event_name='Upload' AND lower(btrim(coalesce(e.properties->>'type','')))='statement' THEN 'statement_upload'
 WHEN e.event_name='Transaction Type Updated' THEN 'type_updated'
 WHEN e.event_name='Transaction Ledger Updated' THEN 'ledger_updated'
 WHEN e.event_name='Transaction Status' THEN 'transaction_status'
 WHEN e.event_name='Transaction Configuration Edited' THEN 'config_edited'
 WHEN e.event_name='Accounting Sync' THEN 'accounting_sync'
 END feature,
 lower(btrim(coalesce(e.properties->>'status',''))) status
 FROM "01_product_schema".events e
 JOIN "01_product_schema".client_company cc ON cc.company_id=e.company_id
 CROSS JOIN p
 WHERE e.event_time>=p.asof-interval '56 days' AND e.event_time<p.asof
 AND e.ingested_at<=p.wm
 AND "01_product_schema".is_core_activity(e.event_name,e.properties)
),
counts AS MATERIALIZED (
 SELECT period,company_id,max(event_time) last_core_at,
 count(*) FILTER(WHERE feature='bill_upload')::integer bill_upload,
 count(*) FILTER(WHERE feature='bill_entity')::integer bill_entity,
 count(*) FILTER(WHERE feature='invoice_bulk_edited')::integer invoice_bulk_edited,
 count(*) FILTER(WHERE feature='vendor_mismatch')::integer vendor_mismatch,
 count(*) FILTER(WHERE feature='invoice_upload')::integer invoice_upload,
 count(*) FILTER(WHERE feature='invoice_entity')::integer invoice_entity,
 count(*) FILTER(WHERE feature='statement_upload')::integer statement_upload,
 count(*) FILTER(WHERE feature='type_updated')::integer type_updated,
 count(*) FILTER(WHERE feature='ledger_updated')::integer ledger_updated,
 count(*) FILTER(WHERE feature='transaction_status')::integer transaction_status,
 count(*) FILTER(WHERE feature='transaction_status' AND status='accounting ready')::integer accounting_ready,
 count(*) FILTER(WHERE feature='config_edited')::integer config_edited,
 count(*) FILTER(WHERE feature='accounting_sync')::integer sync,
 (CASE WHEN bool_or(feature IN('bill_upload','bill_entity','invoice_bulk_edited','vendor_mismatch')) THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(feature IN('invoice_upload','invoice_entity')) THEN '1' ELSE '0' END)||
 (CASE WHEN bool_or(feature IN('statement_upload','type_updated','ledger_updated','transaction_status','config_edited')) THEN '1' ELSE '0' END) mask
 FROM classified GROUP BY period,company_id
),
last_actor AS MATERIALIZED (
 SELECT DISTINCT ON(period,company_id) period,company_id,email,distinct_id
 FROM classified ORDER BY period,company_id,event_time DESC,insert_id DESC
),
definitions AS (
 SELECT * FROM (VALUES
 ('001'::text,'transactions_only'::text,'Transactions only'::text),
 ('100','ap_only','AP only'),('101','ap_transactions','AP + Transactions'),
 ('110','ap_ar','AP + AR'),('111','ap_ar_transactions','AP + AR + Transactions'),
 ('010','ar_only','AR only'),('011','ar_transactions','AR + Transactions'),
 ('000','other_core','Other core only')) k(mask,report_key,title)
),
details AS MATERIALIZED (
 SELECT c.*,a.email,a.distinct_id,k.report_key,k.title,
 d.company_name,
 CASE WHEN ri.integration IS NULL OR ri.integration IN ('','Unknown') THEN NULL
 WHEN ri.integration='Zoho Books' THEN 'Zoho'
 ELSE ri.integration END integration_type
 FROM counts c JOIN last_actor a USING(period,company_id)
 JOIN definitions k ON k.mask=c.mask
 LEFT JOIN "01_product_schema".company_directory d ON d.company_uuid::text=c.company_id
 LEFT JOIN "01_product_schema".company_reporting_identity ri ON ri.company_id=c.company_id
),
rendered AS (
 SELECT d.*, d.report_key||':'||d.period key,
 CASE WHEN d.period='current' THEN 'last 28 days' ELSE 'previous 28 days' END evidence_window,
 (d.bill_upload+d.bill_entity+d.invoice_bulk_edited+d.vendor_mismatch) bills,
 (d.invoice_upload+d.invoice_entity) invoices,
 (d.type_updated+d.ledger_updated+d.transaction_status+d.config_edited) transactions
 FROM details d
)
SELECT r.key AS drill_key,'all'::text AS tab,r.company_id member_id,
 (row_number() OVER(PARTITION BY r.key ORDER BY lower(coalesce(r.company_name,'')),r.company_id)-1)::integer sort_position,
 jsonb_build_object(
  'company_id',r.company_id,'company_name',r.company_name,
  'integration_type',r.integration_type,
  'actor',jsonb_build_object('email',r.email,'distinct_id',r.distinct_id),
  'reached_at',to_char(r.last_core_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  'last_core_activity_at',to_char(r.last_core_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
  'timestamps','[]'::jsonb,'status_badge',NULL::text,'next_milestone_at',NULL::text,
  'evidence',jsonb_build_object(
   'chips',jsonb_build_array(r.title),
   'label','Activity in '||r.evidence_window,
   'items',(
    SELECT jsonb_agg(jsonb_build_object(
      'key',x.k,'label',x.label,'muted',x.n=0,
      'value',CASE WHEN x.n=0 THEN '—' ELSE to_char(x.n,'FM999,999,999,999,990') END
    ) ORDER BY x.pos)
    FROM (VALUES
     (1,'bills'::text,'Bills'::text,r.bills),
     (2,'invoices','Invoices',r.invoices),
     (3,'statements','Statements',r.statement_upload),
     (4,'transactions','Transactions',r.transactions),
     (5,'sync','Sync',r.sync)
    ) x(pos,k,label,n)
   )
  ),
  'event_counts',jsonb_build_array(
   jsonb_build_object('key','bill_upload','count',r.bill_upload,'label','Bill Upload'),
   jsonb_build_object('key','bill_entity','count',r.bill_entity,'label','Bill Entity Created'),
   jsonb_build_object('key','invoice_bulk_edited','count',r.invoice_bulk_edited,'label','Invoice Bulk Edited'),
   jsonb_build_object('key','vendor_mismatch','count',r.vendor_mismatch,'label','Vendor Mismatch Resolved'),
   jsonb_build_object('key','invoice_upload','count',r.invoice_upload,'label','Invoice Upload'),
   jsonb_build_object('key','invoice_entity','count',r.invoice_entity,'label','Invoice Entity Created'),
   jsonb_build_object('key','statement_upload','count',r.statement_upload,'label','Statement Upload'),
   jsonb_build_object('key','type_updated','count',r.type_updated,'label','Type Updated'),
   jsonb_build_object('key','ledger_updated','count',r.ledger_updated,'label','Ledger Updated'),
   jsonb_build_object('key','transaction_status','count',r.transaction_status,'label','Transaction Status'),
   jsonb_build_object('key','accounting_ready','count',r.accounting_ready,'label','Accounting Ready')
  )
 ) card
 FROM rendered r;
$fn$;
REVOKE ALL ON FUNCTION "01_product_schema".build_overview_module_mix_cards_v1(timestamptz,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".build_overview_module_mix_cards_v1(timestamptz,timestamptz)
 TO service_role;
