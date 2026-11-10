-- READ ONLY. Historical Overview member replay: Nov 5 frozen generation.
-- Returns counts only, never identifiers or emails. The mismatch is a
-- real publication blocker, not permission to invent nine source rows.
BEGIN READ ONLY;
SET LOCAL statement_timeout='90s';
WITH baseline AS (
 SELECT (payload#>>'{value,active_users,as_of}')::timestamptz as asof,
 source_watermark_at wm,
 date_trunc('week',(payload#>>'{value,active_users,as_of}')::timestamptz
  AT TIME ZONE 'Asia/Kolkata')::date AS week_start
 FROM public.product_snapshot WHERE id=377
),
qualified AS MATERIALIZED (
 SELECT DISTINCT e.distinct_id AS member_id,
  date_trunc('week',e.event_time AT TIME ZONE 'Asia/Kolkata')::date AS event_week,
  e.event_time
 FROM public.events e
 JOIN public.client_company c ON c.company_id=e.company_id
 CROSS JOIN baseline b
 WHERE e.event_time<b.asof AND e.ingested_at<=b.wm
   AND NULLIF(e.distinct_id,'') IS NOT NULL
   AND public.is_core_activity(e.event_name,e.properties)
   AND NOT metrics_private.is_retention_internal_email_v2(e.email)
),
expected_usage AS (
 SELECT DISTINCT CASE WHEN q.event_time>=b.asof-interval '7 days'
   THEN 'wau' ELSE 'mau' END AS kind, q.member_id
 FROM qualified q CROSS JOIN baseline b
 WHERE q.event_time>=b.asof-interval '30 days'
 UNION
 SELECT DISTINCT 'mau',member_id FROM qualified q CROSS JOIN baseline b
 WHERE q.event_time>=b.asof-interval '30 days'
),
recorded_usage AS (
 SELECT drill_key AS kind, member_id
 FROM public.product_overview_member
 WHERE snapshot_id=377 AND tab='all' AND drill_key IN ('wau','mau')
),
expected_week AS (
 SELECT DISTINCT q.member_id,q.event_week AS week_start
 FROM qualified q CROSS JOIN baseline b
 WHERE q.event_week>=b.week_start-84 AND q.event_week<b.week_start
),
recorded_week AS (
 SELECT member_id,substring(drill_key from 15)::date AS week_start
 FROM public.product_overview_member
 WHERE snapshot_id=377 AND tab='all' AND drill_key LIKE 'weekly_active:%'
),
usage_missing AS (SELECT * FROM recorded_usage EXCEPT SELECT * FROM expected_usage),
usage_extra AS (SELECT * FROM expected_usage EXCEPT SELECT * FROM recorded_usage),
week_recorded_only AS (SELECT * FROM recorded_week EXCEPT SELECT * FROM expected_week),
week_source_only AS (SELECT * FROM expected_week EXCEPT SELECT * FROM recorded_week)
SELECT
 (SELECT count(*) FROM usage_missing) AS usage_recorded_only,
 (SELECT count(*) FROM usage_extra) AS usage_source_only,
 (SELECT count(*) FROM week_recorded_only) AS weekly_recorded_only,
 (SELECT count(*) FROM week_source_only) AS weekly_source_only,
 (SELECT count(DISTINCT member_id) FROM week_recorded_only) AS distinct_unmatched_legacy_members,
 (SELECT count(*) FROM public.events e
  WHERE e.distinct_id=(SELECT member_id FROM week_recorded_only LIMIT 1))
  AS any_raw_events_for_unmatched_member,
 (SELECT count(*) FROM usage_missing)=0 AND
 (SELECT count(*) FROM usage_extra)=0 AS wau_mau_exact_ok,
 (SELECT count(*) FROM week_recorded_only)=0 AND
 (SELECT count(*) FROM week_source_only)=0 AS full_weekly_members_exact_ok;
ROLLBACK;
