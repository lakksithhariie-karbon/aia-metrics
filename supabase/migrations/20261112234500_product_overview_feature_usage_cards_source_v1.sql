-- Reconstruct source-backed Feature Usage company cards, without touching pointers.
-- Current names/integration details are explicitly *current* metadata: historical
-- labels may have changed; frozen event-time facts never use the legacy archive.
-- This is a candidate, not an authorization to stage/publish. Require replay review.
CREATE OR REPLACE FUNCTION "01_product_schema".build_overview_feature_usage_cards_source_v1(
 p_as_of_at timestamptz,p_source_watermark_at timestamptz
) RETURNS TABLE(drill_key text,tab text,member_id text,sort_position integer,card jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog'
SET statement_timeout TO '115s'
AS $fn$
WITH params AS MATERIALIZED (
 SELECT p_source_watermark_at wm,
 date_trunc('week',p_as_of_at AT TIME ZONE 'Asia/Kolkata')::date today_week
 WHERE p_as_of_at IS NOT NULL AND p_source_watermark_at IS NOT NULL
 AND p_as_of_at>=p_source_watermark_at
),
ev AS MATERIALIZED (
 SELECT date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date ws,
 e.company_id,e.event_name,e.event_time,e.insert_id,e.email,e.distinct_id,
 lower(btrim(coalesce(e.properties->>'type',''))) ty,
 lower(btrim(coalesce(e.properties->>'entityType',''))) et,
 lower(btrim(coalesce(e.properties->>'status',''))) st
 FROM "01_product_schema".events e
 JOIN "01_product_schema".client_company cc ON cc.company_id=e.company_id
 CROSS JOIN params p
 WHERE e.event_time>=((p.today_week-84)::timestamp AT TIME ZONE 'Asia/Kolkata')
 AND e.event_time<(p.today_week::timestamp AT TIME ZONE 'Asia/Kolkata')
 AND e.ingested_at<=p.wm
),
tagged AS MATERIALIZED(
 SELECT *,
 CASE WHEN (event_name='Upload' AND ty='bill')
 OR(event_name='Entity Created' AND et='bill')
 OR event_name IN('Vendor Mismatch Resolved','Invoice Bulk Edited') THEN 'ap'
 WHEN (event_name='Upload' AND ty='invoice')
 OR(event_name='Entity Created' AND et='invoice') THEN 'ar'
 WHEN (event_name='Upload' AND ty='statement')
 OR event_name IN('Transaction Type Updated','Transaction Ledger Updated','Transaction Status','Transaction Configuration Edited') THEN 'transactions'
 ELSE NULL END module,
 CASE WHEN event_name='Upload' AND ty='bill' THEN 'bill_upload'
 WHEN event_name='Entity Created' AND et='bill' THEN 'bill_entity'
 WHEN event_name='Vendor Mismatch Resolved' THEN 'vendor_mismatch'
 WHEN event_name='Invoice Bulk Edited' THEN 'invoice_bulk_edited'
 WHEN event_name='Upload' AND ty='invoice' THEN 'invoice_upload'
 WHEN event_name='Entity Created' AND et='invoice' THEN 'invoice_entity'
 WHEN event_name='Upload' AND ty='statement' THEN 'statement_upload'
 WHEN event_name='Transaction Type Updated' THEN 'type_updated'
 WHEN event_name='Transaction Ledger Updated' THEN 'ledger_updated'
 WHEN event_name='Transaction Status' AND st='accounting ready' THEN 'accounting_ready'
 WHEN event_name='Transaction Configuration Edited' THEN 'config_edited'
 ELSE NULL END feature
 FROM ev
),
counts AS MATERIALIZED (
 SELECT ws,company_id,module,
 max(event_time) as last_at,
 count(*) FILTER (WHERE feature='bill_upload')::integer bill_upload,
 count(*) FILTER (WHERE feature='bill_entity')::integer bill_entity,
 count(*) FILTER (WHERE feature='vendor_mismatch')::integer vendor_mismatch,
 count(*) FILTER (WHERE feature='invoice_bulk_edited')::integer invoice_bulk_edited,
 count(*) FILTER (WHERE feature='invoice_upload')::integer invoice_upload,
 count(*) FILTER (WHERE feature='invoice_entity')::integer invoice_entity,
 count(*) FILTER (WHERE feature='statement_upload')::integer statement_upload,
 count(*) FILTER (WHERE feature='type_updated')::integer type_updated,
 count(*) FILTER (WHERE feature='ledger_updated')::integer ledger_updated,
 count(*) FILTER (WHERE feature='accounting_ready')::integer accounting_ready,
 count(*) FILTER (WHERE feature='config_edited')::integer config_edited
 FROM tagged WHERE module IS NOT NULL GROUP BY 1,2,3
),
actors AS MATERIALIZED (
 SELECT DISTINCT ON (ws,company_id,module) ws,company_id,module,email,distinct_id
 FROM tagged WHERE module IS NOT NULL
 ORDER BY ws,company_id,module,event_time DESC,insert_id DESC
),
values_by_module AS MATERIALIZED (
 SELECT c.*,
 CASE c.module WHEN 'ap' THEN 'AP / Bills'
 WHEN 'ar' THEN 'AR / Invoices' ELSE 'Transactions' END module_title,
 CASE c.module WHEN 'ap' THEN 'Latest AP activity'
 WHEN 'ar' THEN 'Latest AR activity' ELSE 'Latest transaction work' END recency_label,
 CASE c.module WHEN 'ap' THEN ARRAY['bill_upload','bill_entity','vendor_mismatch','invoice_bulk_edited']
 WHEN 'ar' THEN ARRAY['invoice_upload','invoice_entity']
 ELSE ARRAY['statement_upload','type_updated','ledger_updated','accounting_ready','config_edited']
 END all_feature_keys,
 CASE c.module WHEN 'ap' THEN ARRAY['bill_upload','bill_entity','review_correction']
 WHEN 'ar' THEN ARRAY['invoice_upload','invoice_entity']
 ELSE ARRAY['statement_upload','type_updated','ledger_updated','accounting_ready','config_edited']
 END evidence_feature_keys
 FROM counts c
),
slots AS MATERIALIZED (
 SELECT p.drill_key,p.tab,p.member_id,
 split_part(p.drill_key,':',1) module,
 split_part(p.drill_key,':',2)::date ws
 FROM "01_product_schema".build_overview_feature_usage_population_v1(p_as_of_at,p_source_watermark_at) p
),
details AS MATERIALIZED(
 SELECT s.drill_key,s.tab,s.member_id,c.module,c.module_title,c.recency_label,
 c.last_at,
 a.email,a.distinct_id,dir.company_name,
 CASE WHEN ri.integration IS NULL OR ri.integration='Unknown' OR ri.integration='' THEN NULL
 WHEN ri.integration='Zoho Books' THEN 'Zoho'
 ELSE ri.integration END integration_type,
 c.bill_upload,c.bill_entity,c.vendor_mismatch,c.invoice_bulk_edited,
 c.invoice_upload,c.invoice_entity,c.statement_upload,c.type_updated,
 c.ledger_updated,c.accounting_ready,c.config_edited,
 c.all_feature_keys,c.evidence_feature_keys
 FROM slots s JOIN values_by_module c ON c.ws=s.ws AND c.company_id=s.member_id AND c.module=s.module
 JOIN actors a ON a.ws=s.ws AND a.company_id=s.member_id AND a.module=s.module
 LEFT JOIN "01_product_schema".company_directory dir ON dir.company_uuid::text=s.member_id
 LEFT JOIN "01_product_schema".company_reporting_identity ri ON ri.company_id=s.member_id
),
with_json AS (
SELECT d.*,
(SELECT jsonb_agg(jsonb_build_object('key',v.feature,'count',v.count,'label',v.label)
 ORDER BY v.pos) FROM (
 SELECT k AS feature, ord AS pos,
 CASE k
 WHEN 'bill_upload' THEN d.bill_upload WHEN 'bill_entity' THEN d.bill_entity
 WHEN 'vendor_mismatch' THEN d.vendor_mismatch
 WHEN 'invoice_bulk_edited' THEN d.invoice_bulk_edited
 WHEN 'invoice_upload' THEN d.invoice_upload WHEN 'invoice_entity' THEN d.invoice_entity
 WHEN 'statement_upload' THEN d.statement_upload
 WHEN 'type_updated' THEN d.type_updated WHEN 'ledger_updated' THEN d.ledger_updated
 WHEN 'accounting_ready' THEN d.accounting_ready WHEN 'config_edited' THEN d.config_edited END AS count,
 CASE k WHEN 'bill_upload' THEN 'Bill Upload' WHEN 'bill_entity' THEN 'Bill Entity Created'
 WHEN 'vendor_mismatch' THEN 'Vendor Mismatch Resolved'
 WHEN 'invoice_bulk_edited' THEN 'Invoice Bulk Edited'
 WHEN 'invoice_upload' THEN 'Invoice Upload' WHEN 'invoice_entity' THEN 'Invoice Entity Created'
 WHEN 'statement_upload' THEN 'Statement Upload'
 WHEN 'type_updated' THEN 'Type Updated' WHEN 'ledger_updated' THEN 'Ledger Updated'
 WHEN 'accounting_ready' THEN 'Accounting Ready' WHEN 'config_edited' THEN 'Configuration Edited' END label
 FROM unnest(d.all_feature_keys) WITH ORDINALITY AS t(k,ord)
 ) v WHERE v.count>0) AS event_counts_base,
(SELECT jsonb_agg(
 jsonb_build_object('key',v.feature,'label',v.label,
 'value', CASE WHEN v.count=0 THEN '—' ELSE v.count::text END)
 || CASE WHEN v.count=0 THEN jsonb_build_object('muted',true) ELSE '{}'::jsonb END
 || CASE WHEN d.tab=v.feature THEN jsonb_build_object('selected',true) ELSE '{}'::jsonb END
 ORDER BY v.pos) FROM (
 SELECT k feature,ord pos,
 CASE k
 WHEN 'bill_upload' THEN d.bill_upload WHEN 'bill_entity' THEN d.bill_entity
 WHEN 'review_correction' THEN d.vendor_mismatch+d.invoice_bulk_edited
 WHEN 'invoice_upload' THEN d.invoice_upload WHEN 'invoice_entity' THEN d.invoice_entity
 WHEN 'statement_upload' THEN d.statement_upload
 WHEN 'type_updated' THEN d.type_updated WHEN 'ledger_updated' THEN d.ledger_updated
 WHEN 'accounting_ready' THEN d.accounting_ready WHEN 'config_edited' THEN d.config_edited
 END AS count,
 CASE k WHEN 'bill_upload' THEN 'Bill Upload' WHEN 'bill_entity' THEN 'Bill Entity Created'
 WHEN 'review_correction' THEN 'Review / Correction'
 WHEN 'invoice_upload' THEN 'Invoice Upload' WHEN 'invoice_entity' THEN 'Invoice Entity Created'
 WHEN 'statement_upload' THEN 'Statement Upload'
 WHEN 'type_updated' THEN 'Type Updated' WHEN 'ledger_updated' THEN 'Ledger Updated'
 WHEN 'accounting_ready' THEN 'Accounting Ready' WHEN 'config_edited' THEN 'Configuration Edited' END label
 FROM unnest(d.evidence_feature_keys) WITH ORDINALITY AS t(k,ord)
 ) v) AS evidence_items
FROM details d
)
SELECT j.drill_key,j.tab,j.member_id,
(row_number() OVER (
 PARTITION BY j.drill_key,j.tab
 ORDER BY lower(coalesce(j.company_name,'')),j.member_id
)-1)::integer sort_position,
jsonb_build_object(
 'actor',jsonb_build_object('email',j.email,'distinct_id',j.distinct_id),
 'company_id',j.member_id,'company_name',j.company_name,
 'integration_type',j.integration_type,
 'reached_at',to_char(j.last_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
 'event_counts',coalesce(j.event_counts_base,'[]'::jsonb)
 || jsonb_build_array(jsonb_build_object('key','latest_activity','count',0,
 'label',j.recency_label,'display',to_char(j.last_at AT TIME ZONE 'Asia/Kolkata','FMDD Mon'))),
 'evidence',jsonb_build_object(
 'chips',jsonb_build_array(j.module_title),
 'items',j.evidence_items,
 'label','Activity in selected week',
 'recency',jsonb_build_object('label',j.recency_label,
 'value',to_char(j.last_at AT TIME ZONE 'Asia/Kolkata','FMDD Mon'))
 ),
 'last_core_activity_at',NULL::text,'next_milestone_at',NULL::text,
 'status_badge',NULL::text,'timestamps','[]'::jsonb
) AS card
FROM with_json j;
$fn$;
REVOKE ALL ON FUNCTION "01_product_schema".build_overview_feature_usage_cards_source_v1(timestamptz,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".build_overview_feature_usage_cards_source_v1(timestamptz,timestamptz)
 TO service_role;
