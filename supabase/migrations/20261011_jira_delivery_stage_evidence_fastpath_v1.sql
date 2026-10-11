-- Performance-only update for the existing service-role-only stage evidence RPC.
-- Stage dwell cohorts are restricted to selected-sprint members before history
-- aggregation; unfiltered parity uses the published stage view, while filtered
-- parity retains the existing filtered Flow reader. Source count and median
-- must reconcile before rows are returned. No Jira data or definitions change.
-- GitHub-owned Jira investigation reader v2. Non-destructive extension of
-- deployed evidence v1: same cohort membership and snapshot guards, with
-- searchable/sortable/paginated evidence and one bounded full export.
-- service_role only. Existing v1 readers and dashboards remain untouched.
CREATE OR REPLACE FUNCTION public.read_jira_delivery_evidence_v2(p_key text, p_sprint_id bigint DEFAULT NULL::bigint, p_modules text[] DEFAULT NULL::text[], p_sub_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[], p_limit integer DEFAULT 10, p_offset integer DEFAULT 0, p_snapshot_id bigint DEFAULT NULL::bigint, p_query text DEFAULT ''::text, p_sort text DEFAULT 'created'::text, p_direction text DEFAULT 'desc'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_temp'
 SET statement_timeout TO '30s'
AS $function$
DECLARE
 v_core jsonb;
 v_flow jsonb;
 v_stage jsonb;
 v_requested_stage text;
 v_median numeric;
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
 IF p_key IS NULL OR length(p_key)>90 OR p_limit IS NULL OR p_limit<1 OR p_limit>7000
    OR p_offset IS NULL OR p_offset<0 OR p_offset>50000
    OR length(coalesce(p_query,''))>140
    OR p_sort NOT IN ('key','created','resolved','severity','status','priority','assignee')
    OR p_direction NOT IN ('asc','desc')
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
 IF p_key<>'commitment_gap' AND left(p_key,6)<>'stage:' AND left(p_key,7)<>'status:' AND left(p_key,5)<>'type:' THEN
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
 ELSIF left(p_key,6)='stage:' THEN
    v_requested_stage := substring(p_key FROM 7);
    IF length(v_requested_stage)<1 OR length(v_requested_stage)>80 THEN
      RAISE EXCEPTION 'jira_delivery_invalid_stage';
    END IF;
   -- Same per-issue stage intervals and direct sprint membership as
   -- jira.v_sprint_stage_summary and the filtered Flow dashboard.
   -- One issue may have multiple transitions; total hours are summed per
   -- issue/stage before computing the median. The reported sample is issues,
   -- not individual status events.
   v_selected := coalesce(p_sprint_id,
     (SELECT id FROM jira.v_dashboard_sprints
      ORDER BY (state='active') DESC,start_date DESC,id DESC LIMIT 1));
   IF v_selected IS NULL THEN RAISE EXCEPTION 'jira_delivery_missing_sprint'; END IF;
   -- Unfiltered sprint source is independently reconciled to the dashboard.
   -- Its stage view avoids calculating the full filtered Flow dashboard again.
   IF coalesce(cardinality(p_modules),0)=0
      AND coalesce(cardinality(p_sub_modules),0)=0
      AND coalesce(cardinality(p_severities),0)=0
      AND coalesce(cardinality(p_assignees),0)=0 THEN
     SELECT to_jsonb(s) INTO v_stage
     FROM jira.v_sprint_stage_summary s
     WHERE s.sprint_id=v_selected AND s.stage=v_requested_stage
     LIMIT 1;
   ELSE
     v_flow := jira.get_filtered_dashboard_flow_submodule(
       p_sprint_id,p_modules,p_severities,p_assignees,p_sub_modules);
     SELECT item INTO v_stage
     FROM jsonb_array_elements(coalesce(v_flow->'stage_summary','[]'::jsonb)) item
     WHERE (item->>'sprint_id')::bigint=v_selected
       AND item->>'stage'=v_requested_stage
     LIMIT 1;
   END IF;
   IF v_stage IS NULL THEN
     RAISE EXCEPTION 'jira_delivery_unknown_stage';
   END IF;
   -- Only scan status history for members of the selected sprint and
   -- current filter scope; retain the exact stage dwell definition and median.
   WITH members AS MATERIALIZED (
     SELECT DISTINCT d.issue_id,d.issue_key,d.summary,d.issue_type,
       d.status_name,d.priority,d.severity,d.module,d.sub_module,
       d.assignee_name,d.created_at,d.resolved_at,d.sprint_id
     FROM jira.v_sprint_drilldown d
     WHERE d.sprint_id=v_selected AND d.is_direct_member AND NOT d.is_subtask
       AND jira._dashboard_filter_matches_submodule(
         d.module,d.sub_module,d.severity,d.assignee_name,
         p_modules,p_sub_modules,p_severities,p_assignees)
   ), ev AS (
     SELECT h.issue_id,h.to_display raw_stage,h.changed_at,
       lead(h.changed_at) OVER(
         PARTITION BY h.issue_id ORDER BY h.changed_at,h.itemordinal
       ) next_change
     FROM jira.issue_field_history h
     JOIN members m ON m.issue_id=h.issue_id
     WHERE h.field='status'
   ), stage_secs AS (
     SELECT e.issue_id,initcap(e.raw_stage) stage,
       sum(extract(epoch from coalesce(e.next_change,now())-e.changed_at))/3600.0 AS hours
     FROM ev e
     WHERE lower(e.raw_stage) NOT IN ('done','issue resolved','spendlytics')
     GROUP BY e.issue_id,initcap(e.raw_stage)
   ), stage_issues AS (
     SELECT m.issue_key,m.summary,m.issue_type,m.status_name,
       m.priority,m.severity,m.module,m.sub_module,m.assignee_name,
       m.created_at,m.resolved_at,m.sprint_id,ss.hours
     FROM members m
     JOIN stage_secs ss ON ss.issue_id=m.issue_id
     WHERE ss.stage=v_requested_stage
   )
   SELECT count(*)::int,
     round((percentile_cont(0.5) WITHIN GROUP(ORDER BY hours::double precision))::numeric,1),
     coalesce(jsonb_agg(jsonb_build_object(
       'issue_key',issue_key,'summary',summary,'issue_type',issue_type,
       'status_name',status_name,'priority',priority,'severity',severity,
       'module',module,'sub_module',sub_module,'assignee_name',assignee_name,
       'created_at',created_at,'resolved_at',resolved_at,
       'stage_hours',round(hours::numeric,2))
       ORDER BY hours DESC,issue_key),'[]'::jsonb)
   INTO v_count,v_median,v_rows
   FROM stage_issues;
   IF v_count IS DISTINCT FROM coalesce((v_stage->>'issues_in_stage')::int,0)
      OR (v_count>0 AND (
         v_stage IS NULL
         OR v_median IS DISTINCT FROM (v_stage->>'median_hours')::numeric))
   THEN
     RAISE EXCEPTION 'jira_delivery_stage_evidence_parity_mismatch';
   END IF;
   SELECT coalesce(name,'Selected sprint')||' · '||v_requested_stage INTO v_label
   FROM jira.sprints WHERE id=v_selected;
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

 -- Preserve the validated full cohort, then search and sort BEFORE paging.
 -- SQL sorts only whitelisted fields; no dynamic SQL or per-page truncation.
 WITH normalized AS (
   SELECT e.row AS original,e.ord,i.issue_key,
     coalesce(nullif(e.row->>'summary',''),i.summary) AS summary,
     coalesce(nullif(e.row->>'status_name',''),i.status_name) AS status_name,
     coalesce(nullif(e.row->>'issue_type',''),i.issue_type) AS issue_type,
     coalesce(nullif(e.row->>'priority',''),i.priority) AS priority,
     coalesce(nullif(e.row->>'severity',''),i.severity) AS severity,
     coalesce(nullif(e.row->>'module',''),i.module) AS module,
     coalesce(nullif(e.row->>'sub_module',''),i.sub_module) AS sub_module,
     coalesce(nullif(e.row->>'assignee_name',''),i.assignee_name) AS assignee_name,
     coalesce((e.row->>'created_at')::timestamptz,i.created_at) AS created_at,
     coalesce((e.row->>'resolved_at')::timestamptz,i.resolved_at) AS resolved_at,
     (e.row->>'stage_hours')::numeric AS stage_hours
   FROM jsonb_array_elements(v_rows) WITH ORDINALITY e(row,ord)
   JOIN jira.issues i ON i.issue_key=e.row->>'issue_key'
   JOIN jira.raw_issues raw ON raw.issue_id=i.issue_id AND raw.deleted_at IS NULL
 ), searched AS (
   SELECT n.* FROM normalized n WHERE trim(coalesce(p_query,''))=''
    OR position(lower(trim(p_query)) IN lower(concat_ws(' ',n.issue_key,n.summary,
       n.assignee_name,n.issue_type,n.status_name,n.module,n.priority)))>0
 ), sorted AS (
   SELECT s.*,row_number() OVER (ORDER BY
     CASE WHEN p_sort='key' AND p_direction='asc' THEN substring(s.issue_key FROM '[0-9]+$')::bigint END ASC NULLS LAST,
     CASE WHEN p_sort='key' AND p_direction='desc' THEN substring(s.issue_key FROM '[0-9]+$')::bigint END DESC NULLS LAST,
     CASE WHEN p_sort='created' AND p_direction='asc' THEN s.created_at END ASC NULLS LAST,
     CASE WHEN p_sort='created' AND p_direction='desc' THEN s.created_at END DESC NULLS LAST,
     CASE WHEN p_sort='resolved' AND p_direction='asc' THEN s.resolved_at END ASC NULLS LAST,
     CASE WHEN p_sort='resolved' AND p_direction='desc' THEN s.resolved_at END DESC NULLS LAST,
     CASE WHEN p_sort='severity' AND p_direction='asc' THEN lower(s.severity) END ASC NULLS LAST,
     CASE WHEN p_sort='severity' AND p_direction='desc' THEN lower(s.severity) END DESC NULLS LAST,
     CASE WHEN p_sort='status' AND p_direction='asc' THEN lower(s.status_name) END ASC NULLS LAST,
     CASE WHEN p_sort='status' AND p_direction='desc' THEN lower(s.status_name) END DESC NULLS LAST,
     CASE WHEN p_sort='priority' AND p_direction='asc' THEN lower(s.priority) END ASC NULLS LAST,
     CASE WHEN p_sort='priority' AND p_direction='desc' THEN lower(s.priority) END DESC NULLS LAST,
     CASE WHEN p_sort='assignee' AND p_direction='asc' THEN lower(s.assignee_name) END ASC NULLS LAST,
     CASE WHEN p_sort='assignee' AND p_direction='desc' THEN lower(s.assignee_name) END DESC NULLS LAST,
     s.issue_key DESC,s.ord
   ) AS ranking FROM searched s
 )
 SELECT (SELECT count(*)::int FROM searched),
   (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'issue_key',p.issue_key,'summary',p.summary,
      'status',p.status_name,'issue_type',p.issue_type,'priority',p.priority,
      'severity',p.severity,'module',p.module,'sub_module',p.sub_module,
      'assignee',p.assignee_name,'created_at',p.created_at,
      'resolved_at',p.resolved_at,'stage_hours',p.stage_hours
   ) ORDER BY p.ranking),'[]'::jsonb)
    FROM sorted p WHERE p.ranking>p_offset AND p.ranking<=p_offset+p_limit)
 INTO v_total,v_page;

 RETURN jsonb_build_object(
  'contract','jira_delivery_evidence_v2',
  'key',p_key,'label',v_label,
  'snapshot_id',v_published,'source_count',v_count,
  'total',v_total,'offset',p_offset,'limit',p_limit,
  'query',coalesce(p_query,''),'sort',p_sort,'direction',p_direction,'rows',v_page);
END;
$function$;

REVOKE ALL ON FUNCTION public.read_jira_delivery_evidence_v2(text,bigint,text[],text[],text[],text[],integer,integer,bigint,text,text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_jira_delivery_evidence_v2(text,bigint,text[],text[],text[],text[],integer,integer,bigint,text,text,text)
 TO service_role;
