-- Read-only Engineering & Delivery dashboard release guards.
-- Does not modify source data. Snapshot ID and all numbers are derived live.

WITH dashboard AS (
 SELECT public.read_jira_delivery_dashboard_v1() AS j
), canonical AS (
 SELECT
   (j->'core'->'metric_cohorts'->'wip_open'->>'n')::int AS core_wip,
   (j->'flow'->'flow_counts'->>'open_total')::int AS flow_wip,
   (j->'core'->'metric_cohorts'->'open_bugs'->>'n')::int AS core_bugs,
   (j->'flow'->'bug_health'->>'open_bugs')::int AS flow_bugs,
   (j->'core'->'metric_cohorts'->'stale_7d'->>'n')::int AS core_stale,
   (j->'flow'->'flow_counts'->>'stale_all')::int AS flow_stale,
   (j->'core'->'metric_cohorts'->'blocked'->>'n')::int AS core_blocked,
   (j->'flow'->'flow_counts'->>'blocked_all')::int AS flow_blocked,
   (j->'core'->'metric_cohorts'->'qa_queue'->>'n')::int AS core_qa,
   (j->'flow'->'flow_counts'->>'qa_queue_count')::int AS independent_qa,
   (j->>'snapshot_id')::bigint AS published_id,
   (j->>'latest_clean_sync_id')::bigint AS clean_id,
   j->'core'->'sprint_discipline' AS sprints,
   j->'issue_types' AS issue_types,
   j->'flow'->'bug_health'->'age_histogram' AS age_hist
 FROM dashboard
), results AS (
 SELECT 'snapshot_clean_sync_matches' AS check_name,published_id=clean_id AS passed FROM canonical
 UNION ALL SELECT 'snapshot_newest_ingest_matches',
   published_id=(SELECT max(id) FROM jira.sync_log) FROM canonical
 UNION ALL SELECT 'wip_core_flow_parity',core_wip=flow_wip FROM canonical
 UNION ALL SELECT 'bug_core_flow_parity',core_bugs=flow_bugs FROM canonical
 UNION ALL SELECT 'stale_core_flow_parity',core_stale=flow_stale FROM canonical
 UNION ALL SELECT 'blocked_core_flow_parity',core_blocked=flow_blocked FROM canonical
 UNION ALL SELECT 'QA_independent_parity',core_qa=independent_qa FROM canonical
 UNION ALL SELECT 'sprint_scope_equals_type_matrix',
   NOT EXISTS (
     SELECT 1 FROM canonical c,jsonb_array_elements(c.sprints) sprint
     WHERE (sprint->>'scope_now')::int <>
       (SELECT coalesce(sum((t->>'count')::int),0)
          FROM jsonb_array_elements(c.issue_types) t
          WHERE t->>'sprint_id'=sprint->>'sprint_id')
   ) FROM canonical
 UNION ALL SELECT 'sprint_done_not_greater_than_scope',
   NOT EXISTS (SELECT 1 FROM canonical c,jsonb_array_elements(c.sprints) sprint
     WHERE (sprint->>'done_now')::int>(sprint->>'scope_now')::int) FROM canonical
 UNION ALL SELECT 'bug_age_buckets_equal_open_bugs',
   (SELECT coalesce(sum((item->>'count')::int),0)
     FROM jsonb_array_elements(age_hist) item)=flow_bugs FROM canonical
 UNION ALL SELECT 'source_history_preserved',
   (SELECT count(*) FROM jira.issues)=(SELECT count(*) FROM jira.raw_issues)
     AND (SELECT count(*) FROM jira.issue_field_history)>0 FROM canonical
)
SELECT check_name,passed FROM results ORDER BY check_name;
