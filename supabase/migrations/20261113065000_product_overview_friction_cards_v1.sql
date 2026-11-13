-- Source-backed Friction company cards. Full event count evidence is
-- shared with the Module Mix raw-event reconstruction for the same frozen
-- period; issue/recovery facts are recomputed from failure/success events.
-- Does not stage/publish or read a legacy snapshot.
CREATE OR REPLACE FUNCTION "01_product_schema".build_overview_friction_cards_v1(
 p_as_of_at timestamptz,p_source_watermark_at timestamptz
) RETURNS TABLE(drill_key text,tab text,member_id text,sort_position integer,card jsonb)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path TO 'pg_catalog'
SET statement_timeout TO '115s'
SET extra_float_digits TO '3'
AS $fn$
WITH p AS MATERIALIZED(
 SELECT p_as_of_at asof,p_source_watermark_at wm
 WHERE p_as_of_at IS NOT NULL AND p_source_watermark_at IS NOT NULL
 AND p_as_of_at>=p_source_watermark_at
),
core_cards AS MATERIALIZED(
 SELECT split_part(c.drill_key,':',2) AS period,c.member_id,c.card
 FROM "01_product_schema".build_overview_module_mix_cards_v1(
 p_as_of_at,p_source_watermark_at) c
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
issue_events AS MATERIALIZED(
 SELECT n.*,
 CASE WHEN n.issue_key='txn_reverted' THEN n.status='pending'
 ELSE n.status='failed' END is_failure,
 CASE WHEN n.issue_key='txn_reverted' THEN n.status='accounting ready'
 ELSE n.status='success' END is_success
 FROM classified n WHERE n.issue_key IS NOT NULL
),
issue_group AS MATERIALIZED(
 SELECT issue_key,period,company_id,
 count(*)::integer attempts,
 count(*) FILTER(WHERE is_failure)::integer failures,
 max(event_time) FILTER(WHERE is_failure) last_failure_at
 FROM issue_events GROUP BY 1,2,3
),
facts AS MATERIALIZED(
 SELECT g.*,
 (SELECT min(e.event_time) FROM issue_events e
  WHERE e.issue_key=g.issue_key AND e.period=g.period
  AND e.company_id=g.company_id AND e.is_success
  AND e.event_time>g.last_failure_at) recovered_at
 FROM issue_group g WHERE g.failures>0
),
labels AS(
 SELECT * FROM (VALUES
 ('txn_reverted'::text,'Transaction status events'::text,'Times reverted'::text),
 ('txn_ledger_failed','Ledger update attempts','Ledger update failures'),
 ('txn_type_failed','Type update attempts','Type update failures'),
 ('bill_upload_failed','Bill upload attempts','Bill upload failures'),
 ('invoice_upload_failed','Invoice upload attempts','Invoice upload failures')
 ) k(issue_key,exposure_label,issues_label)
),
render AS MATERIALIZED(
 SELECT f.*,lc.card base_card,k.exposure_label,k.issues_label,
 to_char(f.last_failure_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') issue_timestamp,
 to_char(f.recovered_at AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') recovery_timestamp
 FROM facts f JOIN core_cards lc ON lc.period=f.period AND lc.member_id=f.company_id
 JOIN labels k ON k.issue_key=f.issue_key
),
cards AS MATERIALIZED(
 SELECT r.issue_key||':'||r.period AS key,
 r.company_id AS member_id,
 CASE WHEN r.recovered_at IS NOT NULL THEN 'recovered' ELSE 'unresolved' END AS state,
 r.base_card || jsonb_build_object(
   'reached_at',r.issue_timestamp,
   'next_milestone_at',r.recovery_timestamp,
   'status_badge',CASE WHEN r.recovered_at IS NOT NULL THEN 'recovered' ELSE 'unresolved' END,
   'timestamps',jsonb_build_array(
     jsonb_build_object('at',r.issue_timestamp,'label','Issue occurred'),
     jsonb_build_object('at',r.recovery_timestamp,'label','Recovery')
   ),
   'evidence',jsonb_build_object(
    'label','Why this company is impacted',
    'items',jsonb_build_array(
     jsonb_build_object('key','exposure','label',r.exposure_label,
       'value',to_char(r.attempts,'FM999,999,999,999,990')),
     jsonb_build_object('key','issues','label',r.issues_label,
       'value',to_char(r.failures,'FM999,999,999,999,990')),
     jsonb_build_object('key','latest_issue','label','Latest issue',
       'value',to_char(r.last_failure_at AT TIME ZONE 'Asia/Kolkata','FMDD Mon')),
     jsonb_build_object('key','recovery','label','Recovery',
       'value',CASE WHEN r.recovered_at IS NULL THEN '—'
       ELSE to_char(r.recovered_at AT TIME ZONE 'Asia/Kolkata','FMDD Mon') END,
       'muted',r.recovered_at IS NULL)
    )
   )
 ) AS card
 FROM render r
),
slots AS (
 SELECT c.key,c.member_id,c.card,x.tab
 FROM cards c CROSS JOIN LATERAL
 (VALUES('all'::text),(c.state)) x(tab)
)
SELECT s.key AS drill_key,s.tab,s.member_id,
 (row_number() OVER(PARTITION BY s.key,s.tab
 ORDER BY lower(coalesce(s.card->>'company_name','')),s.member_id)-1)::integer sort_position,
 s.card
FROM slots s;
$fn$;
REVOKE ALL ON FUNCTION "01_product_schema".build_overview_friction_cards_v1(timestamptz,timestamptz)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION "01_product_schema".build_overview_friction_cards_v1(timestamptz,timestamptz)
 TO service_role;
