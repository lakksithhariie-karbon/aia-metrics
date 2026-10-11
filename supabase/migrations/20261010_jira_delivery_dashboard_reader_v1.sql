-- Jira Engineering & Delivery read facade v1.
-- GitHub-owned, additive, server-only. Existing audited Jira views, snapshots,
-- sync function and Product Metrics endpoints are untouched.
--
-- A single database transaction reads the three established filtered readers,
-- validates overlapping populations, and emits a compact dashboard payload.
-- No raw per-issue rows in the dashboard response; evidence is lazy.
CREATE OR REPLACE FUNCTION public.read_jira_delivery_dashboard_v1(
  p_sprint_id bigint DEFAULT NULL,
  p_modules text[] DEFAULT NULL,
  p_sub_modules text[] DEFAULT NULL,
  p_severities text[] DEFAULT NULL,
  p_assignees text[] DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = jira, public, pg_temp
SET statement_timeout = '30s'
AS $function$
DECLARE
  v_core jsonb;
  v_flow jsonb;
  v_quality jsonb;
  v_cohorts jsonb;
  v_sprint bigint;
  v_latest bigint;
  v_published bigint;
  v_refreshed_at timestamptz;
  v_synced_at timestamptz;
  v_types jsonb;
  v_module_options jsonb;
  v_submodule_options jsonb;
  v_severity_options jsonb;
  v_assignee_options jsonb;
  v_sprint_options jsonb;
  v_issue_type_row record;
  v_cohort_wip int;
  v_flow_wip int;
  v_cohort_bugs int;
  v_flow_bugs int;
  v_cohort_qa int;
  v_flow_qa int;
  v_cohort_stale int;
  v_flow_stale int;
  v_cohort_blocked int;
  v_flow_blocked int;
BEGIN
  IF cardinality(coalesce(p_modules, '{}'::text[])) > 12
     OR cardinality(coalesce(p_sub_modules, '{}'::text[])) > 12
     OR cardinality(coalesce(p_severities, '{}'::text[])) > 12
     OR cardinality(coalesce(p_assignees, '{}'::text[])) > 12
     OR EXISTS (SELECT 1 FROM unnest(
       coalesce(p_modules, '{}'::text[]) ||
       coalesce(p_sub_modules, '{}'::text[]) ||
       coalesce(p_severities, '{}'::text[]) ||
       coalesce(p_assignees, '{}'::text[])) s(v)
       WHERE length(s.v)>160 OR s.v IS NULL) THEN
    RAISE EXCEPTION 'jira_delivery_invalid_filters';
  END IF;

  SELECT refreshed_sync_id, refreshed_at INTO v_published, v_refreshed_at
  FROM jira.dashboard_snapshot_refresh_state WHERE singleton;
  SELECT max(id) INTO v_latest
  FROM jira.sync_log WHERE finished_at IS NOT NULL AND errors_count = 0;
  SELECT finished_at INTO v_synced_at FROM jira.sync_log WHERE id = v_published;

  IF v_published IS NULL OR v_latest IS NULL OR v_published <> v_latest
     OR v_synced_at IS NULL THEN
    RAISE EXCEPTION 'jira_delivery_unpublished_sync';
  END IF;
  IF p_sprint_id IS NOT NULL
    AND NOT EXISTS(SELECT 1 FROM jira.v_dashboard_sprints WHERE id = p_sprint_id)
  THEN
    RAISE EXCEPTION 'jira_delivery_sprint_outside_window';
  END IF;

  -- One coherent read transaction; all filters go to all three existing
  -- audited filtered readers, not independent UI calculations.
  v_core := jira.get_filtered_dashboard_core_submodule(
    p_sprint_id,p_modules,p_severities,p_assignees,p_sub_modules);
  v_flow := jira.get_filtered_dashboard_flow_submodule(
    p_sprint_id,p_modules,p_severities,p_assignees,p_sub_modules);
  v_quality := jira.get_filtered_dashboard_quality_submodule(
    p_sprint_id,p_modules,p_severities,p_assignees,p_sub_modules);
  v_cohorts := coalesce(v_core->'metric_cohorts','{}'::jsonb);

  v_cohort_wip := (v_cohorts->'wip_open'->>'n')::int;
  v_flow_wip := (v_flow->'flow_counts'->>'open_total')::int;
  v_cohort_bugs := (v_cohorts->'open_bugs'->>'n')::int;
  v_flow_bugs := (v_flow->'bug_health'->>'open_bugs')::int;
  v_cohort_stale := (v_cohorts->'stale_7d'->>'n')::int;
  v_flow_stale := (v_flow->'flow_counts'->>'stale_all')::int;
  v_cohort_blocked := (v_cohorts->'blocked'->>'n')::int;
  v_flow_blocked := (v_flow->'flow_counts'->>'blocked_all')::int;
  v_cohort_qa := (v_cohorts->'qa_queue'->>'n')::int;
  v_flow_qa := jsonb_array_length(coalesce(v_flow->'qa_queue','[]'::jsonb));

  IF v_cohort_wip IS NULL OR v_cohort_wip IS DISTINCT FROM v_flow_wip
     OR v_cohort_bugs IS NULL OR v_cohort_bugs IS DISTINCT FROM v_flow_bugs
     OR v_cohort_stale IS NULL OR v_cohort_stale IS DISTINCT FROM v_flow_stale
     OR v_cohort_blocked IS NULL OR v_cohort_blocked IS DISTINCT FROM v_flow_blocked
     OR v_cohort_qa IS NULL OR v_cohort_qa IS DISTINCT FROM v_flow_qa
     OR coalesce((v_cohorts->'stale_blocked'->>'n')::int,-1)
         IS DISTINCT FROM (v_flow->'flow_counts'->>'stale_blocked')::int
  THEN
    RAISE EXCEPTION 'jira_delivery_population_reconciliation_failed';
  END IF;

  -- The four published sprint windows; selected historical sprint gets an
  -- explicit current-state qualifier from React rather than simulated history.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'sprint_id',id,'sprint_name',name,'state',state,
      'start_date',start_date,'end_date',end_date
    ) ORDER BY start_date DESC,id DESC),'[]'::jsonb)
    INTO v_sprint_options FROM jira.v_dashboard_sprints;

  -- Group the same direct, non-subtask, qualified sprint members that feed
  -- jira.v_sprint_discipline, including the exact historical removal cutoff.
  WITH removals AS (
    SELECT issue_id,from_display,min(changed_at) removed_at
    FROM jira.issue_field_history
    WHERE field='Sprint'
    GROUP BY issue_id,from_display
  ), groups AS (
    SELECT d.sprint_id,d.sprint_name,
      coalesce(nullif(btrim(d.issue_type),''),'Unspecified') issue_type,
      count(*)::int issue_count
    FROM jira.v_sprint_drilldown d
    JOIN jira.v_dashboard_sprints w ON w.id=d.sprint_id
    LEFT JOIN removals r ON r.issue_id=d.issue_id AND r.from_display=d.sprint_name
    WHERE d.is_direct_member AND NOT d.is_subtask
      AND (p_sprint_id IS NULL OR d.sprint_id=p_sprint_id)
      AND (r.removed_at IS NULL OR r.removed_at>d.sprint_start+interval '2 days')
      AND jira._dashboard_filter_matches_submodule(
        d.module,d.sub_module,d.severity,d.assignee_name,
        p_modules,p_sub_modules,p_severities,p_assignees)
    GROUP BY d.sprint_id,d.sprint_name,d.issue_type
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
     'sprint_id',sprint_id,'sprint_name',sprint_name,
     'issue_type',issue_type,'count',issue_count)
     ORDER BY sprint_id DESC,issue_type),'[]'::jsonb)
    INTO v_types FROM groups;

  -- Reject silent comparison-table divergence from the core sprint cohort.
  FOR v_issue_type_row IN
    SELECT (s->>'sprint_id')::bigint AS id,
           (s->>'scope_now')::int AS expected
    FROM jsonb_array_elements(coalesce(v_core->'sprint_discipline','[]'::jsonb)) s
  LOOP
    IF (SELECT coalesce(sum((t->>'count')::int),0)
        FROM jsonb_array_elements(v_types) t
        WHERE (t->>'sprint_id')::bigint = v_issue_type_row.id)
        <> v_issue_type_row.expected THEN
      RAISE EXCEPTION 'jira_delivery_issue_type_scope_mismatch';
    END IF;
  END LOOP;

  -- Catalogs intentionally ignore the active filters. A selected filter
  -- must not disappear from its own dropdown.
  SELECT coalesce(jsonb_agg(val ORDER BY val),'[]'::jsonb)
    INTO v_module_options
  FROM (SELECT DISTINCT module AS val FROM jira.v_issue_normalized
        WHERE module IS NOT NULL AND nullif(btrim(module),'') IS NOT NULL) x;
  SELECT coalesce(jsonb_agg(val ORDER BY val),'[]'::jsonb)
    INTO v_submodule_options
  FROM (SELECT DISTINCT sub_module AS val FROM jira.v_issue_normalized
        WHERE sub_module IS NOT NULL AND nullif(btrim(sub_module),'') IS NOT NULL) x;
  SELECT coalesce(jsonb_agg(val ORDER BY val),'[]'::jsonb)
    INTO v_severity_options
  FROM (SELECT DISTINCT severity AS val FROM jira.v_issue_normalized
        WHERE severity IS NOT NULL AND nullif(btrim(severity),'') IS NOT NULL) x;
  SELECT coalesce(jsonb_agg(val ORDER BY val),'[]'::jsonb)
    INTO v_assignee_options
  FROM (SELECT DISTINCT i.assignee_name AS val
    FROM jira.v_issue_normalized i
    WHERE i.assignee_name IS NOT NULL AND nullif(btrim(i.assignee_name),'') IS NOT NULL
      AND EXISTS (SELECT 1 FROM jira.sprint_issues si
        JOIN jira.v_dashboard_sprints s ON s.id=si.sprint_id
        WHERE si.issue_id=i.issue_id AND si.removed_at IS NULL)) x;

  RETURN jsonb_build_object(
    'contract','jira_delivery_dashboard_v1',
    'snapshot_id',v_published,
    'latest_clean_sync_id',v_latest,
    'refreshed_at',v_refreshed_at,
    'synced_at',v_synced_at,
    'selected_sprint_id',p_sprint_id,
    'filters',jsonb_build_object(
      'sprint',p_sprint_id,'modules',p_modules,'sub_modules',p_sub_modules,
      'severities',p_severities,'assignees',p_assignees),
    'options',jsonb_build_object(
      'sprints',v_sprint_options,'modules',v_module_options,
      'sub_modules',v_submodule_options,'severities',v_severity_options,
      'assignees',v_assignee_options),
    'core',jsonb_build_object(
      'hero',v_core->'hero',
      'sprint_discipline',v_core->'sprint_discipline',
      'sprint_throughput',v_core->'sprint_throughput',
      'sprint_summary',v_core->'sprint_summary',
      'cycle_time_org',v_core->'cycle_time_org',
      'cycle_time_by_sprint',v_core->'cycle_time_by_sprint',
      'metric_cohorts',(
        SELECT coalesce(jsonb_object_agg(k,v-'rows'-'issue_keys'),'{}'::jsonb)
        FROM jsonb_each(v_cohorts) c(k,v))),
    'flow',jsonb_build_object(
      'flow_counts',v_flow->'flow_counts',
      'wip_by_status',v_flow->'wip_by_status',
      'stage_summary',v_flow->'stage_summary',
      'bug_health',v_flow->'bug_health',
      'metric_updates',v_flow->'metric_updates',
      'backlog_trend',v_flow->'backlog_trend'),
    'quality',jsonb_build_object(
      'metric_updates',v_quality->'metric_updates',
      'qa_rejection_org',v_quality->'qa_rejection_org',
      'resolution_medians',v_quality->'resolution_medians',
      'org_reopen',v_quality->'org_reopen'),
    'issue_types',v_types);
END;
$function$;

REVOKE ALL ON FUNCTION public.read_jira_delivery_dashboard_v1(bigint,text[],text[],text[],text[]) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_jira_delivery_dashboard_v1(bigint,text[],text[],text[],text[]) TO service_role;
