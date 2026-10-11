-- Read-only Jira reporting integrity audit.
-- Expect every "passed" value to be true. Do not hardcode absolute counts:
-- source syncs change the actual Jira population over time.

WITH expected AS (
 SELECT
  (SELECT count(*) FROM jira.issues i
    WHERE NOT i.is_done AND i.status_category <> 'Done'
      AND NOT EXISTS (SELECT 1 FROM jira.raw_issues r
        WHERE r.issue_id=i.issue_id AND r.deleted_at IS NOT NULL)) AS open_work,
  (SELECT count(*) FROM jira.issues i
    WHERE i.issue_type='Bug' AND NOT i.is_done
      AND NOT EXISTS (SELECT 1 FROM jira.raw_issues r
        WHERE r.issue_id=i.issue_id AND r.deleted_at IS NOT NULL)) AS open_bugs
), checks AS (
 SELECT 'open_work_view_parity' AS check_name,
  (SELECT coalesce(sum(issue_count),0) FROM jira.v_wip_by_status)=(SELECT open_work FROM expected) AS passed
 UNION ALL SELECT 'open_work_flow_parity',
  (SELECT open_total FROM jira.v_flow_counts)=(SELECT open_work FROM expected)
 UNION ALL SELECT 'open_work_cohort_parity',
  (SELECT n FROM jira.v_metric_cohorts_active_v1 WHERE key='wip_open')=(SELECT open_work FROM expected)
 UNION ALL SELECT 'bug_health_parity',
  (SELECT open_bugs FROM jira.v_bug_health)=(SELECT open_bugs FROM expected)
 UNION ALL SELECT 'bug_cohort_parity',
  (SELECT n FROM jira.v_metric_cohorts_active_v1 WHERE key='open_bugs')=(SELECT open_bugs FROM expected)
 UNION ALL SELECT 'QA_cohort_parity',
  (SELECT n FROM jira.v_metric_cohorts_active_v1 WHERE key='qa_queue')=(SELECT count(*) FROM jira.v_qa_queue)
 UNION ALL SELECT 'done_now_percentage_consistency',
  NOT EXISTS(SELECT 1 FROM jira.v_sprint_discipline d WHERE d.scope_now>0
    AND (abs(100.0*d.done_now::numeric/d.scope_now::numeric-d.scope_completion_pct) > 0.051
      OR d.done_now>d.scope_now))
 UNION ALL SELECT 'normalized_no_deleted',
  NOT EXISTS(SELECT 1 FROM jira.v_issue_normalized i JOIN jira.raw_issues r USING(issue_id)
    WHERE r.deleted_at IS NOT NULL)
 UNION ALL SELECT 'flow_no_deleted',
  NOT EXISTS(SELECT 1 FROM jira.v_issue_flow_state i JOIN jira.raw_issues r USING(issue_id)
    WHERE r.deleted_at IS NOT NULL)
 UNION ALL SELECT 'sprint_no_deleted',
  NOT EXISTS(SELECT 1 FROM jira.v_sprint_drilldown i JOIN jira.raw_issues r USING(issue_id)
    WHERE r.deleted_at IS NOT NULL)
 UNION ALL SELECT 'open_cohort_count_rows_keys_agree',
  NOT EXISTS(SELECT 1 FROM jira.v_metric_cohorts_active_v1 c
   WHERE c.key IN ('wip_open','open_bugs','bug_age_over90','open_l1_s45',
     'stale_7d','blocked','stale_blocked','qa_queue')
     AND (c.n<>c.value OR c.n<>c.rows_shown OR c.n<>jsonb_array_length(c.rows)
      OR c.n<>jsonb_array_length(c.issue_keys)))
 UNION ALL SELECT 'raw_derived_issue_id_parity',
  NOT EXISTS (SELECT issue_id FROM jira.raw_issues EXCEPT SELECT issue_id FROM jira.issues)
  AND NOT EXISTS (SELECT issue_id FROM jira.issues EXCEPT SELECT issue_id FROM jira.raw_issues)
 UNION ALL SELECT 'sprint_links_no_orphans',
  NOT EXISTS (SELECT 1 FROM jira.sprint_issues si
   LEFT JOIN jira.issues i ON i.issue_id=si.issue_id
   LEFT JOIN jira.sprints s ON s.id=si.sprint_id
   WHERE i.issue_id IS NULL OR s.id IS NULL)
)
SELECT check_name, passed FROM checks ORDER BY check_name;
