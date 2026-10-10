-- On-demand Jira issue evidence for Engineering & Delivery v1.
-- Only called from the Next.js server with service_role; browser receives
-- at most 50 rows, never the 3k+ issue payload of the core dashboard RPC.
CREATE OR REPLACE FUNCTION public.read_jira_delivery_evidence_v1(
  p_key text,
  p_sprint_id bigint DEFAULT NULL,
  p_modules text[] DEFAULT NULL,
  p_sub_modules text[] DEFAULT NULL,
  p_severities text[] DEFAULT NULL,
  p_assignees text[] DEFAULT NULL,
  p_limit integer DEFAULT 40,
  p_offset integer DEFAULT 0,
  p_snapshot_id bigint DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = jira, public, pg_temp
SET statement_timeout = '30s'
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
 IF v_published IS NULL OR v_latest IS DISTINCT FROM v_published
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

REVOKE ALL ON FUNCTION public.read_jira_delivery_evidence_v1(text,bigint,text[],text[],text[],text[],integer,integer,bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_jira_delivery_evidence_v1(text,bigint,text[],text[],text[],text[],integer,integer,bigint) TO service_role;
