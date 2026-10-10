-- GitHub-owned Jira reporting definitions. The raw source tables, history,
-- sync protocol, cron jobs, and materialized snapshot storage stay untouched.
-- Fixes (1) done_now using the same is_done population as scope_completion_pct,
-- and (2) deleted-in-Jira issue exclusion for current/open-work projections.
-- Existing output column signatures, grants and dependent views are preserved.
-- Generated from the live audited view definitions on 2026-10-10.

-- Correct jira.v_issue_normalized
CREATE OR REPLACE VIEW jira.v_issue_normalized AS
 SELECT issue_id,
    issue_key,
    project_key,
    summary,
    issue_type,
    status_name,
    status_category,
    is_done,
    priority,
    severity,
    module,
    sub_module,
    source,
    root_cause,
    added_to_backlog,
    team_id,
    team_name,
    story_points,
    assignee_id,
    assignee_name,
    reporter_id,
    creator_id,
    sprint_count,
    parent_id,
    labels,
    created_at,
    updated_at,
    start_date,
    due_date,
    resolved_at,
    extra,
    first_seen_at,
    synced_at,
    module AS module_raw,
    sub_module AS sub_module_raw,
    source AS source_raw,
    root_cause AS root_cause_raw,
    jira.canonical_value('Module'::text, module) AS module_canonical,
    jira.canonical_value('Sub Module'::text, sub_module) AS sub_module_canonical,
    jira.canonical_value('Source'::text, source) AS source_canonical,
    jira.canonical_value('Root Cause'::text, root_cause) AS root_cause_canonical
   FROM jira.issues i
 WHERE NOT EXISTS (SELECT 1 FROM jira.raw_issues raw WHERE raw.issue_id = i.issue_id AND raw.deleted_at IS NOT NULL);

-- Correct jira.v_sprint_drilldown
CREATE OR REPLACE VIEW jira.v_sprint_drilldown AS
 WITH sprint_members AS (
         SELECT si.issue_id,
            si.sprint_id,
            true AS direct
           FROM jira.sprint_issues si
          WHERE si.removed_at IS NULL
        ), sprint_children AS (
         SELECT si2.issue_id,
            si2.sprint_id,
            false AS direct
           FROM jira.sprint_issues si2
             JOIN jira.issues child ON child.issue_id = si2.issue_id AND child.issue_type = 'Subtask'::text
             JOIN jira.issues parent ON parent.issue_id = child.parent_id
             JOIN jira.sprint_issues si ON si.issue_id = parent.issue_id AND si.removed_at IS NULL
          WHERE NOT (EXISTS ( SELECT 1
                   FROM jira.sprint_issues own
                  WHERE own.issue_id = child.issue_id AND own.sprint_id = si2.sprint_id AND own.removed_at IS NULL))
        ), members AS (
         SELECT u.issue_id,
            u.sprint_id,
            COALESCE(bool_or(u.direct), false) AS direct
           FROM ( SELECT sprint_members.issue_id,
                    sprint_members.sprint_id,
                    sprint_members.direct
                   FROM sprint_members
                UNION ALL
                 SELECT sprint_children.issue_id,
                    sprint_children.sprint_id,
                    sprint_children.direct
                   FROM sprint_children) u
          GROUP BY u.issue_id, u.sprint_id
        )
 SELECT s.id AS sprint_id,
    s.name AS sprint_name,
    s.state AS sprint_state,
    s.start_date AS sprint_start,
    s.end_date AS sprint_end,
    m.direct AS is_direct_member,
    i.issue_id,
    i.issue_key,
    i.summary,
    i.issue_type,
    i.issue_type = 'Subtask'::text AS is_subtask,
    i.status_name,
    i.status_category,
    i.is_done,
    i.priority,
    i.severity,
    i.module,
    i.sub_module,
    i.source,
    i.root_cause,
    i.assignee_id,
    i.assignee_name,
    i.team_name,
    i.created_at,
    i.resolved_at,
    i.parent_id,
    p.issue_key AS parent_key,
    p.issue_type AS parent_type,
    p.assignee_name AS parent_assignee,
    i.story_points,
    ( SELECT count(*) AS count
           FROM jira.comments c
          WHERE c.issue_id = i.issue_id) AS comment_count,
    ( SELECT count(*) AS count
           FROM jira.attachments_meta a
          WHERE a.issue_id = i.issue_id) AS attachment_count,
    ( SELECT COALESCE(sum(w.time_spent_seconds), 0::bigint) AS "coalesce"
           FROM jira.worklogs w
          WHERE w.issue_id = i.issue_id) AS worklog_seconds,
    ( SELECT count(*) AS count
           FROM jira.issue_links l
          WHERE l.issue_id = i.issue_id) AS link_count,
    ( SELECT count(*) AS count
           FROM jira.issues sc
          WHERE sc.parent_id = i.issue_id) AS subtask_count,
    EXTRACT(epoch FROM now() - i.created_at) / 86400::numeric AS age_days,
    EXTRACT(epoch FROM i.resolved_at - i.created_at) / 86400::numeric AS lead_time_days
   FROM jira.issues i
     JOIN members m ON m.issue_id = i.issue_id
     JOIN jira.sprints s ON s.id = m.sprint_id
     LEFT JOIN jira.issues p ON p.issue_id = i.parent_id
 WHERE NOT EXISTS (SELECT 1 FROM jira.raw_issues raw WHERE raw.issue_id = i.issue_id AND raw.deleted_at IS NOT NULL);

-- Correct jira.v_issue_flow_state
CREATE OR REPLACE VIEW jira.v_issue_flow_state AS
 WITH last_touch AS (
         SELECT issue_field_history.issue_id,
            max(issue_field_history.changed_at) AS last_status_change_at
           FROM jira.issue_field_history
          WHERE issue_field_history.field = 'status'::text
          GROUP BY issue_field_history.issue_id
        ), blocked_entry AS (
         SELECT h.issue_id,
            h.changed_at AS moved_to_blocked_at
           FROM jira.issue_field_history h
          WHERE h.field = 'status'::text AND h.to_display = 'Blocked/Onhold'::text AND NOT (EXISTS ( SELECT 1
                   FROM jira.issue_field_history later
                  WHERE later.issue_id = h.issue_id AND later.field = 'status'::text AND later.changed_at > h.changed_at))
        )
 SELECT i.issue_id,
    i.issue_key,
    i.summary,
    i.issue_type,
    i.status_name,
    i.status_category,
    i.is_done,
    i.severity,
    i.priority,
    i.assignee_id,
    i.assignee_name,
    i.created_at,
    i.due_date,
    i.updated_at,
    NOT i.is_done AS is_open,
    lt.last_status_change_at,
    GREATEST(i.updated_at, COALESCE(lt.last_status_change_at, i.updated_at)) AS last_touch_at,
    (now() - i.updated_at) / 86400.0::double precision AS stale_calc_days,
    (now() - i.updated_at) > '7 days'::interval AS is_stale,
    i.status_name = 'Blocked/Onhold'::text AS is_blocked,
    be.moved_to_blocked_at,
        CASE
            WHEN i.status_name = 'Blocked/Onhold'::text AND be.moved_to_blocked_at IS NOT NULL THEN (now() - be.moved_to_blocked_at) / 86400.0::double precision
            ELSE NULL::interval
        END AS blocked_days,
    i.status_name = 'Blocked/Onhold'::text AND i.is_done = false AND (now() - i.updated_at) > '7 days'::interval AS is_stale_blocked
   FROM jira.issues i
     LEFT JOIN last_touch lt ON lt.issue_id = i.issue_id
     LEFT JOIN blocked_entry be ON be.issue_id = i.issue_id
 WHERE NOT EXISTS (SELECT 1 FROM jira.raw_issues raw WHERE raw.issue_id = i.issue_id AND raw.deleted_at IS NOT NULL);

-- Correct jira.v_wip_by_status
CREATE OR REPLACE VIEW jira.v_wip_by_status AS
 SELECT status_name,
    count(*) AS issue_count,
    round(100.0 * count(*)::numeric / sum(count(*)) OVER (), 1) AS pct
   FROM jira.issues
  WHERE is_done = false AND status_category <> 'Done'::text
    AND NOT EXISTS (SELECT 1 FROM jira.raw_issues raw WHERE raw.issue_id = issues.issue_id AND raw.deleted_at IS NOT NULL)
  GROUP BY status_name
  ORDER BY (count(*)) DESC;

-- Correct jira.v_bug_health
CREATE OR REPLACE VIEW jira.v_bug_health AS
 WITH ob AS (
         SELECT issues.issue_id,
            issues.severity,
            issues.module,
            issues.root_cause,
            issues.created_at
           FROM jira.issues
          WHERE issues.issue_type = 'Bug'::text AND issues.is_done = false
            AND NOT EXISTS (SELECT 1 FROM jira.raw_issues raw WHERE raw.issue_id = issues.issue_id AND raw.deleted_at IS NOT NULL)
        )
 SELECT ( SELECT count(*) AS count
           FROM ob) AS open_bugs,
    ( SELECT round(EXTRACT(epoch FROM percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY (now() - ob.created_at))) / 86400.0, 1) AS round
           FROM ob) AS median_age_days,
    ( SELECT count(*) AS count
           FROM ob
          WHERE (now() - ob.created_at) < '7 days'::interval) AS age_lt_7d,
    ( SELECT count(*) AS count
           FROM ob
          WHERE (now() - ob.created_at) >= '7 days'::interval AND (now() - ob.created_at) < '30 days'::interval) AS age_7_30d,
    ( SELECT count(*) AS count
           FROM ob
          WHERE (now() - ob.created_at) >= '30 days'::interval AND (now() - ob.created_at) < '90 days'::interval) AS age_31_90d,
    ( SELECT count(*) AS count
           FROM ob
          WHERE (now() - ob.created_at) >= '90 days'::interval) AS age_over_90d,
    ( SELECT COALESCE(jsonb_agg(jsonb_build_object('severity', s.severity, 'count', s.cnt) ORDER BY s.cnt DESC), '[]'::jsonb) AS "coalesce"
           FROM ( SELECT
                        CASE
                            WHEN ob.severity IS NULL THEN 'Untagged'::text
                            ELSE ob.severity
                        END AS severity,
                    count(*) AS cnt
                   FROM ob
                  GROUP BY (
                        CASE
                            WHEN ob.severity IS NULL THEN 'Untagged'::text
                            ELSE ob.severity
                        END)) s) AS open_by_severity,
    ( SELECT COALESCE(jsonb_agg(jsonb_build_object('bucket', w.bucket, 'count', b.cnt, 'pct',
                CASE
                    WHEN (( SELECT count(*) AS count
                       FROM ob)) = 0 THEN NULL::numeric
                    ELSE round(100.0 * b.cnt::numeric / (( SELECT count(*) AS count
                       FROM ob))::numeric, 1)
                END) ORDER BY w.ord), '[]'::jsonb) AS "coalesce"
           FROM ( VALUES ('<7d'::text,1), ('7-30d'::text,2), ('31-90d'::text,3), ('>90d'::text,4)) w(bucket, ord)
             JOIN LATERAL ( SELECT
                        CASE w.bucket
                            WHEN '<7d'::text THEN ( SELECT count(*) AS count
                               FROM ob
                              WHERE (now() - ob.created_at) < '7 days'::interval)
                            WHEN '7-30d'::text THEN ( SELECT count(*) AS count
                               FROM ob
                              WHERE (now() - ob.created_at) >= '7 days'::interval AND (now() - ob.created_at) < '30 days'::interval)
                            WHEN '31-90d'::text THEN ( SELECT count(*) AS count
                               FROM ob
                              WHERE (now() - ob.created_at) >= '30 days'::interval AND (now() - ob.created_at) < '90 days'::interval)
                            ELSE ( SELECT count(*) AS count
                               FROM ob
                              WHERE (now() - ob.created_at) >= '90 days'::interval)
                        END AS cnt) b ON true) AS age_histogram,
    ( SELECT COALESCE(jsonb_agg(jsonb_build_object('root_cause', s.root_cause, 'count', s.cnt) ORDER BY s.cnt DESC), '[]'::jsonb) AS "coalesce"
           FROM ( SELECT ob.root_cause,
                    count(*) AS cnt
                   FROM ob
                  GROUP BY ob.root_cause) s) AS rca_distribution,
    ( SELECT COALESCE(jsonb_agg(jsonb_build_object('module', s.module, 'count', s.cnt) ORDER BY s.cnt DESC), '[]'::jsonb) AS "coalesce"
           FROM ( SELECT ob.module,
                    count(*) AS cnt
                   FROM ob
                  GROUP BY ob.module) s) AS open_by_module;

-- Correct jira.v_qa_queue
CREATE OR REPLACE VIEW jira.v_qa_queue AS
 SELECT i.issue_id,
    i.issue_key,
    i.summary,
    i.severity,
    i.priority,
    i.status_name,
    i.assignee_name,
    i.updated_at,
    q.last_uat_enter,
    round(EXTRACT(epoch FROM now() - q.last_uat_enter) / 86400.0, 1) AS days_in_queue
   FROM jira.issues i
     LEFT JOIN LATERAL ( SELECT max(h.changed_at) AS last_uat_enter
           FROM jira.issue_field_history h
          WHERE h.issue_id = i.issue_id AND h.field = 'status'::text AND h.to_display ~~* 'uat%'::text) q ON true
  WHERE i.is_done = false AND (i.status_name = ANY (ARRAY['UAT'::text, 'Testing'::text, 'Staging'::text]))
    AND NOT EXISTS (SELECT 1 FROM jira.raw_issues raw WHERE raw.issue_id = i.issue_id AND raw.deleted_at IS NOT NULL);

-- Correct jira.v_flow_counts
CREATE OR REPLACE VIEW jira.v_flow_counts AS
 SELECT count(*) FILTER (WHERE is_open AND is_stale) AS stale_all,
    count(*) FILTER (WHERE is_open AND is_blocked) AS blocked_all,
    count(*) FILTER (WHERE is_stale_blocked) AS stale_blocked,
    ( SELECT count(*) AS count
           FROM jira.issues
          WHERE issues.is_done = false AND issues.status_category <> 'Done'::text
            AND NOT EXISTS (SELECT 1 FROM jira.raw_issues raw WHERE raw.issue_id = issues.issue_id AND raw.deleted_at IS NOT NULL)) AS open_total
   FROM jira.v_issue_flow_state;

-- Correct jira.v_sprint_discipline
CREATE OR REPLACE VIEW jira.v_sprint_discipline AS
 WITH sprint_removals AS (
         SELECT h.issue_id,
            h.from_display,
            min(h.changed_at) AS removed_at
           FROM jira.issue_field_history h
          WHERE h.field = 'Sprint'::text
          GROUP BY h.issue_id, h.from_display
        ), base AS (
         SELECT s.id AS sprint_id,
            s.name AS sprint_name,
            s.state,
            s.start_date,
            s.end_date,
            d.issue_id,
            d.is_done,
            d.created_at <= (s.start_date + '2 days'::interval) AS was_committed
           FROM jira.sprints s
             JOIN jira.v_sprint_drilldown d ON d.sprint_id = s.id AND d.is_direct_member
             JOIN jira.v_dashboard_sprints w ON w.id = s.id
          WHERE NOT d.is_subtask
        ), live AS (
         SELECT b_1.sprint_id,
            b_1.sprint_name,
            b_1.state,
            b_1.start_date,
            b_1.end_date,
            b_1.issue_id,
            b_1.is_done,
            b_1.was_committed
           FROM base b_1
             LEFT JOIN sprint_removals r ON r.issue_id = b_1.issue_id AND r.from_display = b_1.sprint_name
          WHERE r.removed_at IS NULL OR r.removed_at > (b_1.start_date + '2 days'::interval)
        ), carried AS (
         SELECT b_1.sprint_id,
            b_1.issue_id
           FROM live b_1
          WHERE NOT b_1.is_done AND (EXISTS ( SELECT 1
                   FROM jira.sprint_issues ns
                     JOIN jira.sprints nxt ON nxt.id = ns.sprint_id
                  WHERE ns.issue_id = b_1.issue_id AND ns.removed_at IS NULL AND nxt.name ~~ 'SPEND%'::text AND nxt.start_date > b_1.start_date))
        )
 SELECT sprint_id,
    sprint_name,
    state,
    start_date,
    end_date,
    count(*) AS scope_now,
    count(*) FILTER (WHERE was_committed) AS committed,
    count(*) FILTER (WHERE was_committed AND is_done) AS committed_done,
    round(100.0 * count(*) FILTER (WHERE was_committed AND is_done)::numeric / NULLIF(count(*) FILTER (WHERE was_committed), 0)::numeric, 1) AS commitment_completion_pct,
    count(*) FILTER (WHERE NOT was_committed) AS added_mid_sprint,
    round(100.0 * count(*) FILTER (WHERE NOT was_committed)::numeric / NULLIF(count(*), 0)::numeric, 1) AS mid_sprint_add_pct,
    count(*) FILTER (WHERE is_done) AS done_now,
    round(100.0 * count(*) FILTER (WHERE is_done)::numeric / NULLIF(count(*), 0)::numeric, 1) AS scope_completion_pct,
    ( SELECT count(*) AS count
           FROM carried c
          WHERE c.sprint_id = b.sprint_id) AS carried_to_next
   FROM live b
  GROUP BY sprint_id, sprint_name, state, start_date, end_date
  ORDER BY start_date DESC, sprint_id DESC;

-- Minimal adapter for count-based cohorts. The historical materialized snapshot
-- is retained (no drop/recreate or extra refresh job). Only tombstoned issue
-- evidence that was deleted BEFORE the published clean sync is excluded.
-- Rate/median metrics and all other cohorts retain their published values.
CREATE OR REPLACE VIEW jira.v_metric_cohorts_active_v1 AS
WITH publication AS (
  SELECT s.finished_at AS cutoff_at
  FROM jira.dashboard_snapshot_refresh_state meta
  JOIN jira.sync_log s ON s.id = meta.refreshed_sync_id
  WHERE meta.singleton AND s.errors_count = 0 AND s.finished_at IS NOT NULL
),
filtered AS (
  SELECT mc.key,
         count(e.payload) FILTER (WHERE tomb.issue_id IS NULL) AS visible_count,
         coalesce(jsonb_agg(e.payload ORDER BY e.ordinal) FILTER
           (WHERE e.payload IS NOT NULL AND tomb.issue_id IS NULL), '[]'::jsonb) AS visible_rows,
         coalesce(jsonb_agg(e.payload->'issue_key' ORDER BY e.ordinal) FILTER
           (WHERE e.payload IS NOT NULL AND tomb.issue_id IS NULL), '[]'::jsonb) AS visible_keys
  FROM jira.metric_cohorts mc
  LEFT JOIN LATERAL jsonb_array_elements(
    CASE WHEN jsonb_typeof(coalesce(mc.rows, '[]'::jsonb)) = 'array'
      THEN coalesce(mc.rows, '[]'::jsonb) ELSE '[]'::jsonb END
  ) WITH ORDINALITY AS e(payload, ordinal) ON TRUE
  LEFT JOIN jira.raw_issues tomb ON tomb.issue_key = e.payload->>'issue_key'
    AND tomb.deleted_at IS NOT NULL
    AND tomb.deleted_at <= (SELECT cutoff_at FROM publication)
  WHERE mc.key IN ('wip_open', 'open_bugs', 'bug_age_over90', 'open_l1_s45', 'stale_7d', 'blocked', 'stale_blocked', 'qa_queue')
  GROUP BY mc.key
)
SELECT mc.key, mc.title,
       CASE WHEN f.key IS NOT NULL THEN f.visible_count::numeric ELSE mc.value END AS value,
       mc.unit,
       CASE WHEN f.key IS NOT NULL THEN f.visible_count::numeric ELSE mc.n END AS n,
       mc.denominator, mc.source, mc.definition, mc.definition_ref, mc.row_type,
       CASE WHEN f.key IS NOT NULL THEN f.visible_count ELSE mc.rows_shown END AS rows_shown,
       CASE WHEN f.key IS NOT NULL THEN f.visible_rows ELSE mc.rows END AS rows,
       CASE WHEN f.key IS NOT NULL THEN f.visible_keys ELSE mc.issue_keys END AS issue_keys,
       mc.source_note
FROM jira.metric_cohorts mc
LEFT JOIN filtered f USING(key);

-- Return the corrected, snapshot-bounded open count rows without altering the
-- historical materialized snapshot's 23-row contract or scheduled refresh.
CREATE OR REPLACE FUNCTION jira.get_filtered_metric_cohorts(p_sprint_ids integer[] DEFAULT NULL::integer[], p_module text DEFAULT NULL::text, p_severity text[] DEFAULT NULL::text[], p_assignee text[] DEFAULT NULL::text[])
 RETURNS TABLE(key text, title text, value double precision, unit text, n integer, denominator integer, source text, definition text, definition_ref text, row_type text, rows_shown integer, rows jsonb, issue_keys jsonb, source_note text, is_filtered boolean, scope_note text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '5s'
AS $function$
declare
  valid_sprints int[];
  has_sprint_filter boolean;
  has_module_filter boolean;
  has_severity_filter boolean;
  has_assignee_filter boolean;
begin
  -- A supplied sprint list is restricted to the active + prior-three window.
  -- An invalid supplied list remains an explicit empty match for sprint-grain
  -- cohorts. No supplied list means this RPC is reading the already-windowed
  -- metric_cohorts snapshot, so there is no sprint filter to apply.
  if p_sprint_ids is not null and cardinality(p_sprint_ids) > 0 then
    select coalesce(array_agg(id::int order by start_date desc, id desc), '{}'::int[])
      into valid_sprints
    from v_dashboard_sprints
    where id = any(p_sprint_ids);
    if cardinality(valid_sprints) = 0 then
      valid_sprints := array[-1];
    end if;
    has_sprint_filter := true;
  else
    valid_sprints := null;
    has_sprint_filter := false;
  end if;

  has_module_filter := p_module is not null;
  has_severity_filter := p_severity is not null and cardinality(p_severity) > 0;
  has_assignee_filter := p_assignee is not null and cardinality(p_assignee) > 0;

  return query
  with base as (
    select
      mc.*,
      _filter_cohort_field_present(mc.rows, 'sprint_id') as has_sprint_field,
      _filter_cohort_field_present(mc.rows, 'module') as has_module_field,
      _filter_cohort_field_present(mc.rows, 'severity') as has_severity_field,
      _filter_cohort_field_present(mc.rows, 'assignee_name') as has_assignee_field
    from jira.v_metric_cohorts_active_v1 mc
  ),
  expanded as (
    select
      b.key,
      b.title,
      b.value,
      b.unit,
      b.n,
      b.denominator,
      b.source,
      b.definition,
      b.definition_ref,
      b.row_type,
      b.source_note,
      b.has_sprint_field,
      b.has_module_field,
      b.has_severity_field,
      b.has_assignee_field,
      elem.payload,
      elem.ord
    from base b
    left join lateral jsonb_array_elements(
      case
        when jsonb_typeof(coalesce(b.rows, '[]'::jsonb)) = 'array'
          then coalesce(b.rows, '[]'::jsonb)
        else '[]'::jsonb
      end
    ) with ordinality as elem(payload, ord) on true
  ),
  filtered as (
    select
      e.key,
      e.payload,
      e.ord
    from expanded e
    where e.n is null
       or _filter_cohort_row_matches(
            e.payload,
            valid_sprints,
            p_module,
            p_severity,
            p_assignee,
            has_sprint_filter and e.has_sprint_field,
            has_module_filter and e.has_module_field,
            has_severity_filter and e.has_severity_field,
            has_assignee_filter and e.has_assignee_field
          )
  ),
  agg as (
    select
      f.key,
      jsonb_agg(f.payload order by f.ord) filter (where f.payload is not null) as filtered_rows,
      jsonb_agg(f.payload->>'issue_key' order by f.ord) filter (where f.payload is not null) as filtered_keys,
      count(*) filter (where f.payload is not null)::int as filtered_count
    from filtered f
    group by f.key
  )
  select
    b.key,
    b.title,
    -- Frozen contract: filtering changes row sets, never published metrics.
    case when b.n is null then null else b.value::double precision end,
    b.unit,
    b.n::integer,
    b.denominator::integer,
    b.source,
    b.definition,
    b.definition_ref,
    b.row_type,
    case when b.n is null then 0 else coalesce(a.filtered_count, 0) end,
    coalesce(a.filtered_rows, '[]'::jsonb),
    coalesce(a.filtered_keys, '[]'::jsonb),
    b.source_note,
    case
      when b.n is null then false
      else (
        (has_sprint_filter and b.has_sprint_field)
        or (has_module_filter and b.has_module_field)
        or (has_severity_filter and b.has_severity_field)
        or (has_assignee_filter and b.has_assignee_field)
      )
    end,
    case
      when b.n is null then 'reserved (n null) — not filtered; renders ⧗'
      when not (has_sprint_filter or has_module_filter or has_severity_filter or has_assignee_filter)
        then 'unfiltered — no filter supplied'
      when not (
        (has_sprint_filter and b.has_sprint_field)
        or (has_module_filter and b.has_module_field)
        or (has_severity_filter and b.has_severity_field)
        or (has_assignee_filter and b.has_assignee_field)
      ) then 'unfiltered — selected filter is not published for this cohort'
      when coalesce(a.filtered_count, 0) = 0
        then 'filtered — zero rows match selection (honest empty)'
      else 'filtered — published metric remains at its defined scope; row set narrowed'
    end
  from base b
  left join agg a on a.key = b.key
  order by b.key;
end;
$function$

-- Fail closed if any current-state view still contains deleted issue evidence.
DO $jira_checks$
BEGIN
  IF EXISTS (SELECT 1 FROM jira.v_issue_normalized i JOIN jira.raw_issues r USING(issue_id) WHERE r.deleted_at IS NOT NULL LIMIT 1) THEN
    RAISE EXCEPTION 'jira_deleted_issues_in_normalized_population';
  END IF;
  IF EXISTS (SELECT 1 FROM jira.v_sprint_drilldown d JOIN jira.raw_issues r USING(issue_id) WHERE r.deleted_at IS NOT NULL LIMIT 1) THEN
    RAISE EXCEPTION 'jira_deleted_issues_in_sprint_population';
  END IF;
  IF EXISTS (SELECT 1 FROM jira.v_issue_flow_state f JOIN jira.raw_issues r USING(issue_id) WHERE r.deleted_at IS NOT NULL LIMIT 1) THEN
    RAISE EXCEPTION 'jira_deleted_issues_in_flow_population';
  END IF;
  IF (SELECT coalesce(sum(issue_count),0) FROM jira.v_wip_by_status) <>
     (SELECT count(*) FROM jira.issues i WHERE NOT i.is_done AND i.status_category <> 'Done'
        AND NOT EXISTS(SELECT 1 FROM jira.raw_issues r WHERE r.issue_id=i.issue_id AND r.deleted_at IS NOT NULL)) THEN
    RAISE EXCEPTION 'jira_open_work_parity_failed';
  END IF;
  IF EXISTS (SELECT 1 FROM jira.v_sprint_discipline d WHERE d.scope_now>0
    AND abs(100.0 * d.done_now::numeric / d.scope_now::numeric - d.scope_completion_pct) > 0.051) THEN
    RAISE EXCEPTION 'jira_done_now_parity_failed';
  END IF;
  IF EXISTS (SELECT 1 FROM jira.v_metric_cohorts_active_v1 c
    WHERE c.key IN ('wip_open', 'open_bugs', 'bug_age_over90', 'open_l1_s45', 'stale_7d', 'blocked', 'stale_blocked', 'qa_queue')
      AND (c.n <> c.rows_shown OR c.n <> jsonb_array_length(c.rows)
        OR c.n <> jsonb_array_length(c.issue_keys) OR c.value <> c.n)) THEN
    RAISE EXCEPTION 'jira_open_cohort_parity_failed';
  END IF;
END
$jira_checks$;
