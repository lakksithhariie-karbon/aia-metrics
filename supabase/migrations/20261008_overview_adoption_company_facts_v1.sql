-- Canonical company-level adoption facts, pinned to the same published
-- Overview snapshot and ingestion watermark as WAU / MAU.
-- All 403 mature integrations enter once. Events are limited to the first 28d.
CREATE OR REPLACE FUNCTION public.overview_adoption_company_facts_v1(
  p_snapshot_id bigint
)
RETURNS TABLE (
  company_id text,
  company_name text,
  integration_type text,
  is_test boolean,
  integrated_at timestamptz,
  first_core_7d_at timestamptz,
  first_core_28d_at timestamptz,
  first_sync_after_core_at timestamptz,
  training_sync_at timestamptz,
  post_training_core_at timestamptz,
  value_at timestamptz,
  active_weeks integer,
  core_actions integer,
  ap_actions integer,
  ar_actions integer,
  transaction_actions integer,
  sync_events integer,
  last_core_at timestamptz,
  step_flags jsonb
)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'metrics_private', 'pg_temp'
SET statement_timeout TO '35s'
AS $function$
WITH published AS MATERIALIZED (
  SELECT s.id, s.source_watermark_at,
    (s.payload #>> '{value,active_users,as_of}')::timestamptz AS as_of_at
  FROM public.product_snapshot_current c
  JOIN public.product_snapshot s ON s.id=c.snapshot_id
  WHERE c.kind='overview' AND c.scope_key=''
    AND s.source_status='ok' AND c.snapshot_id=p_snapshot_id
  LIMIT 1
),
base AS MATERIALIZED (
  SELECT m.member_id AS company_id,
    coalesce(nullif(m.card->>'company_name',''),m.member_id) AS company_name,
    coalesce(nullif(m.card->>'integration_type',''),'Unknown') AS integration_type,
    coalesce((m.card->>'is_test')::boolean,false) AS is_test,
    (m.card->>'integrated_at')::timestamptz AS integrated_at
  FROM public.product_overview_member m
  JOIN published p ON p.id=m.snapshot_id
  WHERE m.kind='overview' AND m.drill_key='core_adoption_7d'
    AND m.tab='all'
    AND (m.card->>'integrated_at')::timestamptz + interval '28 days'<=p.as_of_at
),
qualified AS MATERIALIZED (
  SELECT b.company_id,b.integrated_at,e.event_time,e.event_name,e.properties,
    floor(extract(epoch FROM (e.event_time-b.integrated_at))/604800)::int AS rel_week,
    (e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS local_day,
    public.is_qualifying_sync(e.event_name,e.properties) AS is_sync,
    (e.event_name<>'Accounting Sync' AND public.is_core_activity(e.event_name,e.properties))
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
  FROM base b JOIN public.events e ON e.company_id=b.company_id
  CROSS JOIN published p
  WHERE e.event_time>=b.integrated_at
    AND e.event_time<b.integrated_at+interval '28 days'
    AND e.event_time<p.as_of_at
    AND e.ingested_at<=p.source_watermark_at
    AND lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
    AND NOT metrics_private.is_retention_internal_email_v2(e.email)
    AND (
      (e.event_name<>'Accounting Sync' AND public.is_core_activity(e.event_name,e.properties))
      OR public.is_qualifying_sync(e.event_name,e.properties)
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
)
SELECT
  b.company_id,b.company_name,b.integration_type,b.is_test,b.integrated_at,
  a.first_7,a.first_28,s.sync_at,
  a.first_training,t.post_core_at,v.value_at,
  coalesce(a.active_weeks,0),coalesce(a.core_actions,0),
  coalesce(a.ap_actions,0),coalesce(a.ar_actions,0),
  coalesce(a.transaction_actions,0),coalesce(a.sync_events,0),
  a.last_core_at,
  coalesce(a.step_flags,'{}'::jsonb)
FROM base b
LEFT JOIN activity a USING(company_id)
LEFT JOIN post_core_sync s USING(company_id)
LEFT JOIN post_training_core t USING(company_id)
LEFT JOIN value_completion v USING(company_id);
$function$;

REVOKE ALL ON FUNCTION public.overview_adoption_company_facts_v1(bigint)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.overview_adoption_company_facts_v1(bigint)
  TO service_role;
