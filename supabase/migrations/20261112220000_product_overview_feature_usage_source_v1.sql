-- Reconstruct complete legacy-compatible Feature Usage summary from frozen Product events.
-- Historical replay: 5 snapshots (353, 358, 364, 370, 376) x 12 weeks x 13
-- core/module/feature company-count metrics = 780 exact count comparisons.
-- Source-only, does not stage/publish, change pointers, read private identities,
-- or create a cron. Never imply this alone satisfies five-kind Overview cutover.
CREATE OR REPLACE FUNCTION "01_product_schema".build_overview_feature_usage_source_v1(
  p_as_of_at timestamptz, p_source_watermark_at timestamptz
)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog'
SET statement_timeout TO '110s'
SET extra_float_digits TO '3'
AS $fn$
WITH params AS MATERIALIZED (
  SELECT p_as_of_at AS asof, p_source_watermark_at AS wm,
   date_trunc('week', p_as_of_at AT TIME ZONE 'Asia/Kolkata')::date AS current_week
  WHERE p_as_of_at IS NOT NULL
    AND p_source_watermark_at IS NOT NULL
    AND p_as_of_at >= p_source_watermark_at
),
weeks AS MATERIALIZED (
 SELECT (p.current_week - (n.week_back * 7))::date AS week_start
 FROM params p CROSS JOIN generate_series(12,1,-1) AS n(week_back)
),
classified AS MATERIALIZED (
 SELECT w.week_start, e.company_id,
   "01_product_schema".is_core_activity(e.event_name,e.properties) AS core,
   CASE
     WHEN e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill'
       THEN 'bill_upload'
     WHEN e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill'
       THEN 'bill_entity'
     WHEN e.event_name IN ('Vendor Mismatch Resolved','Invoice Bulk Edited')
       THEN 'review_correction'
     WHEN e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice'
       THEN 'invoice_upload'
     WHEN e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice'
       THEN 'invoice_entity'
     WHEN e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='statement'
       THEN 'statement_upload'
     WHEN e.event_name='Transaction Type Updated' THEN 'type_updated'
     WHEN e.event_name='Transaction Ledger Updated' THEN 'ledger_updated'
     WHEN e.event_name='Transaction Status' AND lower(btrim(e.properties->>'status'))='accounting ready'
       THEN 'accounting_ready'
     ELSE NULL END AS feature,
   CASE
     WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='bill')
       OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='bill')
       OR e.event_name IN ('Vendor Mismatch Resolved','Invoice Bulk Edited')
       THEN 'ap'
     WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='invoice')
       OR (e.event_name='Entity Created' AND lower(btrim(e.properties->>'entityType'))='invoice')
       THEN 'ar'
     WHEN (e.event_name='Upload' AND lower(btrim(e.properties->>'type'))='statement')
       OR e.event_name IN ('Transaction Type Updated','Transaction Ledger Updated',
                            'Transaction Status','Transaction Configuration Edited')
       THEN 'transactions'
     ELSE NULL END AS module
 FROM weeks w
 JOIN "01_product_schema".events e
   ON e.event_time >= (w.week_start::timestamp AT TIME ZONE 'Asia/Kolkata')
  AND e.event_time < ((w.week_start+7)::timestamp AT TIME ZONE 'Asia/Kolkata')
 JOIN "01_product_schema".client_company c ON c.company_id=e.company_id
 CROSS JOIN params p
 WHERE e.ingested_at <= p.wm
),
week_counts AS (
 SELECT week_start, count(DISTINCT company_id)::integer AS companies
 FROM classified WHERE core GROUP BY 1
),
module_counts AS (
 SELECT week_start,module,count(DISTINCT company_id)::integer companies
 FROM classified WHERE module IS NOT NULL GROUP BY 1,2
),
feature_counts AS (
 SELECT week_start,feature,count(DISTINCT company_id)::integer companies
 FROM classified WHERE feature IS NOT NULL GROUP BY 1,2
),
modules AS (
 SELECT * FROM (VALUES
   ('ap'::text, 'AP / Bills'::text,1),
   ('ar','AR / Invoices',2),
   ('transactions','Transactions',3)
 ) m(module_key,module_label,position)
),
features AS (
 SELECT * FROM (VALUES
   ('ap'::text,'bill_upload'::text,'Bill Upload'::text,1),
   ('ap','bill_entity','Bill Entity Created',2),
   ('ap','review_correction','Review / Correction',3),
   ('ar','invoice_upload','Invoice Upload',1),
   ('ar','invoice_entity','Invoice Entity Created',2),
   ('transactions','statement_upload','Statement Upload',1),
   ('transactions','type_updated','Transaction Type Updated',2),
   ('transactions','ledger_updated','Transaction Ledger Updated',3),
   ('transactions','accounting_ready','Accounting Ready',4)
 ) f(module_key,feature_key,feature_label,position)
),
rows AS (
 SELECT w.week_start,
 jsonb_build_object(
   'week_start',to_char(w.week_start,'YYYY-MM-DD'),
   'week_label',to_char(w.week_start,'FMDD Mon'),
   'core_active_companies',coalesce(wc.companies,0),
   'modules',(
     SELECT jsonb_agg(jsonb_build_object(
       'key',m.module_key,
       'label',m.module_label,
       'companies',coalesce(mc.companies,0),
       'share_of_core_active',CASE WHEN coalesce(wc.companies,0)>0
          THEN coalesce(mc.companies,0)::double precision / wc.companies::double precision
          ELSE 0::double precision END,
       'features',(
         SELECT jsonb_agg(jsonb_build_object(
           'key',f.feature_key,'label',f.feature_label,
           'companies',coalesce(fc.companies,0),
           'share_of_module',CASE WHEN coalesce(mc.companies,0)>0
             THEN coalesce(fc.companies,0)::double precision / mc.companies::double precision
             ELSE 0::double precision END
         ) ORDER BY f.position)
         FROM features f LEFT JOIN feature_counts fc
           ON fc.week_start=w.week_start AND fc.feature=f.feature_key
         WHERE f.module_key=m.module_key
       )
     ) ORDER BY m.position)
     FROM modules m
     LEFT JOIN module_counts mc
       ON mc.week_start=w.week_start AND mc.module=m.module_key
   )
 ) AS data
 FROM weeks w LEFT JOIN week_counts wc USING(week_start)
)
SELECT jsonb_build_object(
  'contract','overview_feature_usage_source_v1',
  'as_of',p.asof,'source_watermark_at',p.wm,
  'payload',jsonb_build_object(
    'schema',1,
    'value',jsonb_build_object(
      'as_of',to_char(p.asof AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'subtitle','Module usage · last 12 completed weeks',
      'weeks',(SELECT jsonb_agg(data ORDER BY week_start) FROM rows)
    )
  )
) FROM params p;
$fn$;
REVOKE ALL ON FUNCTION "01_product_schema".build_overview_feature_usage_source_v1(timestamptz,timestamptz)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".build_overview_feature_usage_source_v1(timestamptz,timestamptz)
  TO service_role;
