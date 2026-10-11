-- Jira dashboard v1: fail closed whenever source ingestion has advanced past
-- the last fully verified/published snapshot, including a failed/partial sync
-- or an in-progress sync. This avoids stale snapshot labels on current-state
-- Jira issues and prevents mismatched live evidence.
--
-- Add the QA queue's independently measured issue-count in the compact
-- dashboard payload so the Next.js server can verify a real second source.
--
-- No raw or derived issues are modified; neither Edge Function nor cron
-- scheduling is changed. Signature, permissions and filter logic preserved.

-- read_jira_delivery_dashboard_v1
CREATE OR REPLACE FUNCTION public.read_jira_delivery_dashboard_v1(p_sprint_id bigint DEFAULT NULL::bigint, p_modules text[] DEFAULT NULL::text[], p_sub_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_temp'
 SET statement_timeout TO '30s'
AS $function$
DECLARE
  v_core jsonb;
  v_flow jsonb;
  v_quality jsonb;
  v_cohorts jsonb;
  v_sprint bigint;
  v_latest bigint;
  v_last_run bigint;
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
  -- A partially successful or currently running ingest can alter live issues
  -- before a verified snapshot is published. Do not advertise mixed data.
  SELECT max(id) INTO v_last_run FROM jira.sync_log;
  SELECT finished_at INTO v_synced_at FROM jira.sync_log WHERE id = v_published;

  IF v_published IS NULL OR v_latest IS NULL OR v_published <> v_latest
     OR v_last_run IS DISTINCT FROM v_published
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
      'flow_counts',(v_flow->'flow_counts' || jsonb_build_object('qa_queue_count',v_flow_qa)),
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

-- read_jira_delivery_evidence_v1
CREATE OR REPLACE FUNCTION public.read_jira_delivery_evidence_v1(p_key text, p_sprint_id bigint DEFAULT NULL::bigint, p_modules text[] DEFAULT NULL::text[], p_sub_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[], p_limit integer DEFAULT 40, p_offset integer DEFAULT 0, p_snapshot_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_temp'
 SET statement_timeout TO '30s'
AS $function$
DECLARE
 v_core jsonb;
 v_cohort jsonb;
 v_rows jsonb := '[]'::jsonb;
 v_page jsonb := '[]'::jsonb;
 v_count int;
 v_total int;
 v_selected bigint;
 v_published bigint;
 v_latest bigint;
  v_last_run bigint;
 v_label text;
BEGIN
 IF p_key IS NULL OR length(p_key)>90 OR p_limit IS NULL OR p_limit<1 OR p_limit>50
    OR p_offset IS NULL OR p_offset<0 OR p_offset>25000
    OR cardinality(coalesce(p_modules,'{}'::text[]))>12
    OR cardinality(coalesce(p_sub_modules,'{}'::text[]))>12
    OR cardinality(coalesce(p_severities,'{}'::text[]))>12
    OR cardinality(coalesce(p_assignees,'{}'::text[]))>12
 THEN RAISE EXCEPTION 'jira_delivery_invalid_evidence_request'; END IF;

 SELECT refreshed_sync_id INTO v_published FROM jira.dashboard_snapshot_refresh_state WHERE singleton;
 SELECT max(id) INTO v_latest FROM jira.sync_log WHERE finished_at IS NOT NULL AND errors_count=0;
 SELECT max(id) INTO v_last_run FROM jira.sync_log;
 IF v_published IS NULL OR v_latest IS DISTINCT FROM v_published
    OR v_last_run IS DISTINCT FROM v_published
    OR (p_snapshot_id IS NOT NULL AND p_snapshot_id <> v_published) THEN
   RAISE EXCEPTION 'jira_delivery_evidence_snapshot_mismatch';
 END IF;
 IF p_sprint_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM jira.v_dashboard_sprints WHERE id=p_sprint_id)
 THEN RAISE EXCEPTION 'jira_delivery_evidence_unknown_sprint'; END IF;

 -- Reuse exactly the filtered cohort produced for the dashboard. The
 -- "source_count" may be a number of QA cycles, while "total" is issues.
 IF p_key NOT IN ('commitment_gap') AND left(p_key,7)<>'status:' AND left(p_key,5)<>'type:' THEN
   v_core := jira.get_filtered_dashboard_core_submodule(
     p_sprint_id,p_modules,p_severities,p_assignees,p_sub_modules);
   v_cohort := v_core->'metric_cohorts'->p_key;
   IF v_cohort IS NULL OR v_cohort->>'n' IS NULL THEN
     RAISE EXCEPTION 'jira_delivery_evidence_unknown_cohort';
   END IF;
   v_rows := CASE WHEN jsonb_typeof(v_cohort->'rows')='array'
     THEN v_cohort->'rows' ELSE '[]'::jsonb END;
   v_count := (v_cohort->>'n')::int;
   v_label := coalesce(v_cohort->>'title',p_key);
 ELSIF p_key='commitment_gap' THEN
   v_core := jira.get_filtered_dashboard_core_submodule(
     p_sprint_id,p_modules,p_severities,p_assignees,p_sub_modules);
   v_selected := coalesce(p_sprint_id,(v_core->'sprint_discipline'->0->>'sprint_id')::bigint);
   IF v_selected IS NULL THEN RAISE EXCEPTION 'jira_delivery_missing_sprint'; END IF;
   WITH removals AS (
     SELECT issue_id,from_display,min(changed_at) removed_at
     FROM jira.issue_field_history WHERE field='Sprint'
     GROUP BY issue_id,from_display
   ), current_gap AS (
     SELECT d.issue_key,d.summary,d.issue_type,d.status_name,
       d.priority,d.severity,d.module,d.sub_module,d.assignee_name,
       d.created_at,d.resolved_at,d.sprint_id
     FROM jira.v_sprint_drilldown d
     LEFT JOIN removals r ON r.issue_id=d.issue_id AND r.from_display=d.sprint_name
     WHERE d.sprint_id=v_selected AND d.is_direct_member AND NOT d.is_subtask
       AND NOT d.is_done AND d.created_at<=d.sprint_start+interval '2 days'
       AND (r.removed_at IS NULL OR r.removed_at>d.sprint_start+interval '2 days')
       AND jira._dashboard_filter_matches_submodule(
         d.module,d.sub_module,d.severity,d.assignee_name,
         p_modules,p_sub_modules,p_severities,p_assignees)
   )
   SELECT coalesce(jsonb_agg(to_jsonb(g) ORDER BY g.created_at DESC,g.issue_key),'[]'::jsonb)
     INTO v_rows FROM current_gap g;
   v_count := jsonb_array_length(v_rows);
   IF v_count IS DISTINCT FROM
     ((v_core->'sprint_discipline'->0->>'committed')::int -
      (v_core->'sprint_discipline'->0->>'committed_done')::int) THEN
     RAISE EXCEPTION 'jira_delivery_commitment_gap_evidence_mismatch';
   END IF;
   v_label := 'Committed work not delivered';
 ELSIF left(p_key,7)='status:' THEN
   v_label := substring(p_key FROM 8);
   IF v_label='' THEN RAISE EXCEPTION 'jira_delivery_empty_status'; END IF;
   SELECT coalesce(jsonb_agg(jsonb_build_object(
      'issue_key',i.issue_key,'summary',i.summary,'issue_type',i.issue_type,
      'status_name',i.status_name,'priority',i.priority,'severity',i.severity,
      'module',i.module,'sub_module',i.sub_module,'assignee_name',i.assignee_name,
      'created_at',i.created_at,'resolved_at',i.resolved_at)
      ORDER BY i.updated_at DESC,i.issue_key),'[]'::jsonb)
    INTO v_rows
   FROM jira.v_issue_normalized i
   WHERE i.project_key='SPEND' AND NOT i.is_done AND i.status_category<>'Done'
     AND i.status_name=v_label
     AND jira._dashboard_filter_matches_submodule(i.module,i.sub_module,i.severity,
       i.assignee_name,p_modules,p_sub_modules,p_severities,p_assignees)
     AND (p_sprint_id IS NULL OR EXISTS(
       SELECT 1 FROM jira.sprint_issues si
       WHERE si.issue_id=i.issue_id AND si.sprint_id=p_sprint_id AND si.removed_at IS NULL));
   v_count := jsonb_array_length(v_rows);
 ELSIF left(p_key,5)='type:' THEN
   v_label := substring(p_key FROM 6);
   v_selected := coalesce(p_sprint_id,(SELECT id FROM jira.v_dashboard_sprints
       ORDER BY (state='active') DESC,start_date DESC LIMIT 1));
   IF v_label='' OR v_selected IS NULL THEN
     RAISE EXCEPTION 'jira_delivery_empty_issue_type';
   END IF;
   WITH removals AS (
     SELECT issue_id,from_display,min(changed_at) removed_at
     FROM jira.issue_field_history WHERE field='Sprint'
     GROUP BY issue_id,from_display
   ), typed AS (
     SELECT d.issue_key,d.summary,d.issue_type,d.status_name,
       d.priority,d.severity,d.module,d.sub_module,d.assignee_name,
       d.created_at,d.resolved_at,d.sprint_id
     FROM jira.v_sprint_drilldown d
     LEFT JOIN removals r ON r.issue_id=d.issue_id AND r.from_display=d.sprint_name
     WHERE d.sprint_id=v_selected AND d.is_direct_member AND NOT d.is_subtask
       AND coalesce(nullif(btrim(d.issue_type),''),'Unspecified')=v_label
       AND (r.removed_at IS NULL OR r.removed_at>d.sprint_start+interval '2 days')
       AND jira._dashboard_filter_matches_submodule(
         d.module,d.sub_module,d.severity,d.assignee_name,
         p_modules,p_sub_modules,p_severities,p_assignees)
   )
   SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC,t.issue_key),'[]'::jsonb)
     INTO v_rows FROM typed t;
   v_count := jsonb_array_length(v_rows);
 END IF;

 v_total := jsonb_array_length(v_rows);
 SELECT coalesce(jsonb_agg(jsonb_build_object(
    'issue_key',e.row->>'issue_key',
    'summary',e.row->>'summary',
    'status',e.row->>'status_name',
    'issue_type',e.row->>'issue_type',
    'priority',e.row->>'priority',
    'severity',e.row->>'severity',
    'module',e.row->>'module',
    'sub_module',e.row->>'sub_module',
    'assignee',e.row->>'assignee_name',
    'created_at',e.row->>'created_at',
    'resolved_at',e.row->>'resolved_at'
   ) ORDER BY e.ord),'[]'::jsonb)
   INTO v_page
 FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS e(row,ord)
 WHERE e.ord>p_offset AND e.ord<=p_offset+p_limit;
 RETURN jsonb_build_object(
  'contract','jira_delivery_evidence_v1',
  'key',p_key,'label',v_label,
  'snapshot_id',v_published,
  'source_count',v_count,
  'total',v_total,'offset',p_offset,'limit',p_limit,'rows',v_page);
END;
$function$;
