-- GitHub-owned compatibility alignment for the original filtered dashboard RPCs.
-- The existing snapshot materialized view remains unchanged. Only the source
-- from which open-work cohort rows and counts are read is swapped for the
-- validated, point-in-time tombstone-excluding view.
-- Both variants preserve their SQL signature, return shape and filters.
-- Auth grants, SECURITY DEFINER settings and source history are unchanged.

-- Aligned get_filtered_dashboard_core_025_base
CREATE OR REPLACE FUNCTION jira.get_filtered_dashboard_core_025_base(p_sprint_id bigint DEFAULT NULL::bigint, p_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '20s'
AS $function$
with
window_sprints as (
  select
    ds.id::bigint as sprint_id,
    ds.name as sprint_name,
    ds.state,
    ds.start_date,
    ds.end_date,
    coalesce(s.complete_date, ds.end_date) as sprint_complete,
    coalesce(s.goal, '') as goal
  from v_dashboard_sprints ds
  join sprints s on s.id = ds.id
),
target_sprint as (
  select ws.*
  from window_sprints ws
  where
    (p_sprint_id is not null and ws.sprint_id = p_sprint_id)
    or (
      p_sprint_id is null
      and ws.sprint_id = coalesce(
        (select a.sprint_id from window_sprints a where a.state = 'active'
         order by a.start_date desc, a.sprint_id desc limit 1),
        (select n.sprint_id from window_sprints n
         order by n.start_date desc, n.sprint_id desc limit 1)
      )
    )
),
report_sprints as (
  select ws.*
  from window_sprints ws
  where p_sprint_id is null
     or ws.sprint_id = (select t.sprint_id from target_sprint t limit 1)
),
filtered_issues as materialized (
  select i.*
  from v_issue_normalized i
  where i.project_key = 'SPEND'
    and _dashboard_filter_matches(
      i.module, i.severity, i.assignee_name,
      p_modules, p_severities, p_assignees
    )
    and (
      p_sprint_id is null
      or exists (
        select 1
        from sprint_issues si
        join window_sprints ws on ws.sprint_id = si.sprint_id
        where si.issue_id = i.issue_id
          and si.removed_at is null
          and si.sprint_id = p_sprint_id
      )
    )
),
option_drilldown as materialized (
  select d.*
  from v_sprint_drilldown d
  join window_sprints ws on ws.sprint_id = d.sprint_id
),
window_drilldown as materialized (
  select d.*
  from v_sprint_drilldown d
  join window_sprints ws on ws.sprint_id = d.sprint_id
  where _dashboard_filter_matches(
    d.module, d.severity, d.assignee_name,
    p_modules, p_severities, p_assignees
  )
),
report_drilldown as materialized (
  select d.*
  from window_drilldown d
  join report_sprints rs on rs.sprint_id = d.sprint_id
),
sprint_removals as materialized (
  select h.issue_id, h.from_display, min(h.changed_at) as removed_at
  from issue_field_history h
  where h.field = 'Sprint'
  group by h.issue_id, h.from_display
),
discipline_base as materialized (
  select
    d.sprint_id,
    d.sprint_name,
    d.sprint_state as state,
    d.sprint_start as start_date,
    d.sprint_end as end_date,
    d.issue_id,
    d.issue_key,
    d.summary,
    d.issue_type,
    d.status_name,
    d.status_category,
    d.is_done,
    d.priority,
    d.severity,
    d.module,
    d.assignee_name,
    d.created_at,
    d.resolved_at,
    d.created_at <= d.sprint_start + interval '2 days' as was_committed
  from window_drilldown d
  where d.is_direct_member and not d.is_subtask
),
discipline_live as materialized (
  select b.*
  from discipline_base b
  left join sprint_removals r
    on r.issue_id = b.issue_id
   and r.from_display = b.sprint_name
  where r.removed_at is null
     or r.removed_at > b.start_date + interval '2 days'
),
report_discipline_live as materialized (
  select d.*
  from discipline_live d
  join report_sprints rs on rs.sprint_id = d.sprint_id
),
carried_rows as materialized (
  select d.*
  from discipline_live d
  where not d.is_done
    and exists (
      select 1
      from sprint_issues ns
      join sprints nxt on nxt.id = ns.sprint_id
      where ns.issue_id = d.issue_id
        and ns.removed_at is null
        and nxt.name like 'SPEND%'
        and nxt.start_date > d.start_date
    )
),
discipline_agg as (
  select
    sprint_id,
    sprint_name,
    state,
    start_date,
    end_date,
    count(*)::int as scope_now,
    count(*) filter (where was_committed)::int as committed,
    count(*) filter (where was_committed and is_done)::int as committed_done,
    round(100.0 * count(*) filter (where was_committed and is_done)::numeric
      / nullif(count(*) filter (where was_committed), 0), 1) as commitment_completion_pct,
    count(*) filter (where not was_committed)::int as added_mid_sprint,
    round(100.0 * count(*) filter (where not was_committed)::numeric
      / nullif(count(*), 0), 1) as mid_sprint_add_pct,
    count(*) filter (where is_done)::int as done_now,
    round(100.0 * count(*) filter (where is_done)::numeric
      / nullif(count(*), 0), 1) as scope_completion_pct,
    (select count(*)::int from carried_rows c where c.sprint_id = d.sprint_id)
      as carried_to_next
  from report_discipline_live d
  group by sprint_id, sprint_name, state, start_date, end_date
),
first_done as materialized (
  select h.issue_id, min(h.changed_at) as first_done_at
  from issue_field_history h
  join filtered_issues i on i.issue_id = h.issue_id
  where h.field = 'status'
    and i.status_category = 'Done'
    and h.to_display in ('Done', 'Closed', 'Completed', 'Issue Resolved')
  group by h.issue_id
),
throughput_all as materialized (
  select d.*, fd.first_done_at, ws.sprint_complete
  from window_drilldown d
  join window_sprints ws on ws.sprint_id = d.sprint_id
  join first_done fd on fd.issue_id = d.issue_id
  where d.is_direct_member
    and not d.is_subtask
    and d.status_category = 'Done'
    and fd.first_done_at >= ws.start_date
    and fd.first_done_at < ws.sprint_complete + interval '2 days'
),
throughput_rows as materialized (
  select t.*
  from throughput_all t
  join report_sprints rs on rs.sprint_id = t.sprint_id
),
published_throughput as materialized (
  select t.sprint_id, t.throughput, t.first_done_after_start
  from v_sprint_throughput t
  join report_sprints rs on rs.sprint_id = t.sprint_id
),
throughput_agg as (
  select
    t.sprint_id,
    t.sprint_name,
    min(t.sprint_start) as sprint_start,
    max(t.sprint_complete) as sprint_complete,
    case when cardinality(coalesce(p_modules, '{}'::text[])) = 0
           and cardinality(coalesce(p_severities, '{}'::text[])) = 0
           and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
         then max(pt.throughput)::int
         else count(*)::int
    end as throughput,
    case when cardinality(coalesce(p_modules, '{}'::text[])) = 0
           and cardinality(coalesce(p_severities, '{}'::text[])) = 0
           and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
         then max(pt.first_done_after_start)::int
         else count(*) filter (where t.created_at > t.sprint_start + interval '2 days')::int
    end as first_done_after_start
  from throughput_rows t
  left join published_throughput pt on pt.sprint_id = t.sprint_id
  group by t.sprint_id, t.sprint_name
),
summary_agg as (
  select
    d.sprint_id,
    d.sprint_name,
    d.sprint_state as state,
    d.sprint_start as start_date,
    d.sprint_end as end_date,
    count(*) filter (where d.is_direct_member)::int as direct_issues,
    count(*)::int as all_issues,
    count(*) filter (where d.is_done)::int as done_issues,
    round(100.0 * count(*) filter (where d.is_done)::numeric
      / nullif(count(*), 0), 1) as completion_pct,
    count(*) filter (where d.issue_type = 'Bug' and not d.is_done)::int as open_bugs,
    count(*) filter (where d.issue_type = 'Bug' and d.is_done)::int as done_bugs,
    count(*) filter (where not d.is_done and d.priority = 'Highest')::int as open_highest,
    count(distinct d.assignee_id)::int as contributors,
    count(*) filter (where d.severity = 'L1' and not d.is_done)::int as open_l1,
    coalesce(sum(d.story_points) filter (where d.is_done), 0)::numeric as done_points,
    coalesce(sum(d.story_points), 0)::numeric as total_points,
    count(*) filter (where d.created_at > d.sprint_start)::int as added_after_start,
    max(coalesce(rs.goal, '')) as goal
  from report_drilldown d
  join report_sprints rs on rs.sprint_id = d.sprint_id
  group by d.sprint_id, d.sprint_name, d.sprint_state, d.sprint_start, d.sprint_end
),
cycle_rows as materialized (
  select
    ct.issue_id,
    i.issue_key,
    i.summary,
    i.issue_type,
    i.status_name,
    i.severity,
    i.priority,
    i.assignee_name,
    i.created_at,
    i.resolved_at,
    i.module,
    ct.done_at,
    extract(epoch from (ct.done_at - ct.first_in_progress_at)) / 86400.0 as cycle_days
  from v_issue_cycle_times ct
  join filtered_issues i on i.issue_id = ct.issue_id
  where ct.done_at is not null and ct.first_in_progress_at is not null
),
cycle_sprint_rows as materialized (
  select cr.*, ws.sprint_id, ws.sprint_name, ws.start_date as sprint_start
  from cycle_rows cr
  join sprint_issues si on si.issue_id = cr.issue_id and si.removed_at is null
  join report_sprints ws on ws.sprint_id = si.sprint_id
  where cr.done_at >= ws.start_date
    and cr.done_at < ws.sprint_complete + interval '2 days'
),
cycle_by_sprint_agg as (
  select
    sprint_id,
    sprint_name,
    count(*)::int as n,
    round(percentile_cont(0.5) within group (order by cycle_days)::numeric, 2) as median_days,
    round(percentile_cont(0.75) within group (order by cycle_days)::numeric, 2) as p75_days,
    round(percentile_cont(0.90) within group (order by cycle_days)::numeric, 2) as p90_days,
    max(sprint_start) as sprint_start
  from cycle_sprint_rows
  group by sprint_id, sprint_name
),
cycle_org_agg as (
  select
    count(*)::int as n,
    round(percentile_cont(0.5) within group (order by cycle_days)::numeric, 2) as median_days,
    round(percentile_cont(0.75) within group (order by cycle_days)::numeric, 2) as p75_days,
    round(percentile_cont(0.90) within group (order by cycle_days)::numeric, 2) as p90_days
  from cycle_rows
),
cohort_meta as materialized (
  select
    mc.key,
    mc.title,
    mc.value,
    mc.unit,
    mc.n,
    mc.denominator,
    mc.source,
    mc.definition,
    mc.definition_ref,
    mc.row_type,
    mc.source_note
  from jira.v_metric_cohorts_active_v1 mc
),
cohort_expanded as materialized (
  select
    m.key,
    e.payload,
    e.ord
  from cohort_meta m
  join jira.v_metric_cohorts_active_v1 mc on mc.key = m.key
  left join lateral jsonb_array_elements(
    case when jsonb_typeof(coalesce(mc.rows, '[]'::jsonb)) = 'array'
      then coalesce(mc.rows, '[]'::jsonb)
      else '[]'::jsonb end
  ) with ordinality e(payload, ord) on true
),
filtered_cohort_rows as materialized (
  select e.key, e.payload, e.ord
  from cohort_expanded e
  join cohort_meta m on m.key = e.key
  left join filtered_issues i on i.issue_key = e.payload ->> 'issue_key'
  where m.n is null
     or (
       (p_sprint_id is null or (
         i.issue_id is not null and exists (
           select 1 from sprint_issues si
           where si.issue_id = i.issue_id
             and si.sprint_id = p_sprint_id
             and si.removed_at is null
         )
       ))
       and _dashboard_filter_matches(
         case when e.payload ? 'module' then e.payload ->> 'module' else i.module end,
         case when e.payload ? 'severity' then e.payload ->> 'severity' else i.severity end,
         case when e.payload ? 'assignee_name' then e.payload ->> 'assignee_name' else i.assignee_name end,
         p_modules, p_severities, p_assignees
       )
     )
),
dynamic_cohort_rows as materialized (
  select
    'commit_s45'::text as key,
    row_number() over (order by d.resolved_at desc nulls last, d.issue_key) as ord,
    jsonb_build_object(
      'issue_key', d.issue_key, 'summary', d.summary, 'issue_type', d.issue_type,
      'severity', d.severity, 'status_name', d.status_name, 'priority', d.priority,
      'assignee_name', d.assignee_name, 'created_at', d.created_at,
      'resolved_at', d.resolved_at, 'module', d.module, 'sprint_id', d.sprint_id
    ) as payload
  from discipline_live d
  join target_sprint t on t.sprint_id = d.sprint_id
  where d.was_committed and d.is_done
  union all
  select
    'commit_s44',
    row_number() over (order by d.resolved_at desc nulls last, d.issue_key),
    jsonb_build_object(
      'issue_key', d.issue_key, 'summary', d.summary, 'issue_type', d.issue_type,
      'severity', d.severity, 'status_name', d.status_name, 'priority', d.priority,
      'assignee_name', d.assignee_name, 'created_at', d.created_at,
      'resolved_at', d.resolved_at, 'module', d.module, 'sprint_id', d.sprint_id
    )
  from discipline_live d
  where d.was_committed and d.is_done
    and d.sprint_id = (
      select p.sprint_id from window_sprints p
      join target_sprint t on p.start_date < t.start_date
      order by p.start_date desc, p.sprint_id desc limit 1
    )
  union all
  select
    'adds_s45',
    row_number() over (order by d.created_at desc, d.issue_key),
    jsonb_build_object(
      'issue_key', d.issue_key, 'summary', d.summary, 'issue_type', d.issue_type,
      'severity', d.severity, 'status_name', d.status_name, 'priority', d.priority,
      'assignee_name', d.assignee_name, 'created_at', d.created_at,
      'resolved_at', d.resolved_at, 'module', d.module, 'sprint_id', d.sprint_id
    )
  from discipline_live d
  join target_sprint t on t.sprint_id = d.sprint_id
  where not d.was_committed
  union all
  select
    'carried_s45',
    row_number() over (order by d.created_at desc, d.issue_key),
    jsonb_build_object(
      'issue_key', d.issue_key, 'summary', d.summary, 'issue_type', d.issue_type,
      'severity', d.severity, 'status_name', d.status_name, 'priority', d.priority,
      'assignee_name', d.assignee_name, 'created_at', d.created_at,
      'resolved_at', d.resolved_at, 'module', d.module, 'sprint_id', d.sprint_id
    )
  from carried_rows d
  join target_sprint t on t.sprint_id = d.sprint_id
  union all
  select
    'throughput_s45',
    row_number() over (order by d.first_done_at desc, d.issue_key),
    jsonb_build_object(
      'issue_key', d.issue_key, 'summary', d.summary, 'issue_type', d.issue_type,
      'severity', d.severity, 'status_name', d.status_name, 'priority', d.priority,
      'assignee_name', d.assignee_name, 'created_at', d.created_at,
      'resolved_at', d.resolved_at, 'module', d.module, 'sprint_id', d.sprint_id
    )
  from throughput_all d
  join target_sprint t on t.sprint_id = d.sprint_id
  union all
  select
    'cycle_s45',
    row_number() over (order by d.cycle_days desc nulls last, d.issue_key),
    jsonb_build_object(
      'issue_key', d.issue_key, 'summary', d.summary, 'issue_type', d.issue_type,
      'severity', d.severity, 'status_name', d.status_name, 'priority', d.priority,
      'assignee_name', d.assignee_name, 'created_at', d.created_at,
      'resolved_at', d.resolved_at, 'module', d.module, 'sprint_id', d.sprint_id,
      'cycle_days', round(d.cycle_days::numeric, 1)
    )
  from cycle_sprint_rows d
  join target_sprint t on t.sprint_id = d.sprint_id
),
all_cohort_rows as materialized (
  select key, ord, payload
  from filtered_cohort_rows
  where key not in ('commit_s45', 'commit_s44', 'adds_s45', 'carried_s45', 'throughput_s45', 'cycle_s45')
  union all
  select key, ord, payload from dynamic_cohort_rows
),
cohort_agg as (
  select
    key,
    count(*)::int as row_count,
    jsonb_agg(payload order by ord) as rows,
    jsonb_agg(payload ->> 'issue_key' order by ord) as issue_keys
  from all_cohort_rows
  group by key
),
cohort_stats as (
  select
    'commit_s45'::text as key,
    coalesce((select committed_done::double precision from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0) as value,
    'issues'::text as unit,
    coalesce((select committed_done::bigint from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0) as n,
    coalesce((select committed::bigint from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0) as denominator
  union all
  select 'commit_s44',
    coalesce((select count(*)::double precision from discipline_live d where d.was_committed and d.is_done and d.sprint_id = (select p.sprint_id from window_sprints p join target_sprint t on p.start_date < t.start_date order by p.start_date desc, p.sprint_id desc limit 1)), 0),
    'issues',
    coalesce((select count(*)::bigint from discipline_live d where d.was_committed and d.is_done and d.sprint_id = (select p.sprint_id from window_sprints p join target_sprint t on p.start_date < t.start_date order by p.start_date desc, p.sprint_id desc limit 1)), 0),
    coalesce((select count(*)::bigint from discipline_live d where d.was_committed and d.sprint_id = (select p.sprint_id from window_sprints p join target_sprint t on p.start_date < t.start_date order by p.start_date desc, p.sprint_id desc limit 1)), 0)
  union all
  select 'adds_s45',
    coalesce((select added_mid_sprint::double precision from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0),
    'issues',
    coalesce((select added_mid_sprint::bigint from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0),
    coalesce((select scope_now::bigint from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0)
  union all
  select 'carried_s45',
    coalesce((select carried_to_next::double precision from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0),
    'issues',
    coalesce((select carried_to_next::bigint from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0),
    coalesce((select scope_now::bigint from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0)
  union all
  select 'throughput_s45',
    coalesce((select throughput::double precision from throughput_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0),
    'issues',
    coalesce((select throughput::bigint from throughput_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0),
    coalesce((select throughput::bigint from throughput_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0)
  union all
  select 'cycle_s45',
    (select median_days::double precision from cycle_by_sprint_agg d join target_sprint t on t.sprint_id = d.sprint_id),
    'days',
    coalesce((select n::bigint from cycle_by_sprint_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0),
    coalesce((select n::bigint from cycle_by_sprint_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0)
  union all
  select 'cycle_org', median_days::double precision, 'days', n::bigint, n::bigint from cycle_org_agg
  union all
  select
    m.key,
    case when m.key in ('open_bugs', 'bug_age_over90', 'open_l1_s45', 'stale_7d', 'blocked', 'stale_blocked', 'wip_open', 'qa_queue')
      then coalesce(a.row_count, 0)::double precision else m.value end,
    m.unit,
    case when m.key in ('open_bugs', 'bug_age_over90', 'open_l1_s45', 'stale_7d', 'blocked', 'stale_blocked', 'wip_open', 'qa_queue')
      then coalesce(a.row_count, 0)::bigint else m.n::bigint end,
    case when m.key in ('open_bugs', 'bug_age_over90', 'open_l1_s45', 'stale_7d', 'blocked', 'stale_blocked', 'wip_open', 'qa_queue')
      then coalesce(a.row_count, 0)::bigint else m.denominator::bigint end
  from cohort_meta m
  left join cohort_agg a on a.key = m.key
  where m.key not in ('commit_s45', 'commit_s44', 'adds_s45', 'carried_s45', 'throughput_s45', 'cycle_s45', 'cycle_org')
),
cohort_json as (
  select jsonb_object_agg(
    m.key,
    jsonb_build_object(
      'title', case m.key
        when 'commit_s45' then coalesce('Delivered from commitment — ' || (select sprint_name from target_sprint), m.title)
        when 'commit_s44' then coalesce('Delivered from commitment — ' || (select p.sprint_name from window_sprints p join target_sprint t on p.start_date < t.start_date order by p.start_date desc, p.sprint_id desc limit 1), m.title)
        when 'adds_s45' then coalesce('Added after start — ' || (select sprint_name from target_sprint), m.title)
        when 'carried_s45' then coalesce('Carried to next — ' || (select sprint_name from target_sprint), m.title)
        when 'throughput_s45' then coalesce('Delivered this sprint — ' || (select sprint_name from target_sprint), m.title)
        when 'cycle_s45' then coalesce('Cycle time — ' || (select sprint_name from target_sprint), m.title)
        else m.title end,
      'value', coalesce(s.value, m.value),
      'unit', coalesce(s.unit, m.unit),
      'n', case when m.n is null then null else coalesce(s.n, m.n::bigint) end,
      'denominator', case when m.n is null then null else coalesce(s.denominator, m.denominator::bigint) end,
      'source', m.source,
      'definition', m.definition,
      'definition_ref', m.definition_ref,
      'row_type', m.row_type,
      'rows_shown', case when m.n is null then 0 else coalesce(a.row_count, 0) end,
      'rows', coalesce(a.rows, '[]'::jsonb),
      'issue_keys', coalesce(a.issue_keys, '[]'::jsonb),
      'source_note', m.source_note,
      'is_filtered', case when m.n is null then false else (
        p_sprint_id is not null
        or cardinality(coalesce(p_modules, '{}'::text[])) > 0
        or cardinality(coalesce(p_severities, '{}'::text[])) > 0
        or cardinality(coalesce(p_assignees, '{}'::text[])) > 0
      ) end,
      'scope_note', case
        when m.n is null then 'reserved (n null) — not published; renders ⧗'
        when p_sprint_id is null
          and cardinality(coalesce(p_modules, '{}'::text[])) = 0
          and cardinality(coalesce(p_severities, '{}'::text[])) = 0
          and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
          then 'unfiltered — server-published dashboard scope'
        when coalesce(a.row_count, 0) = 0 then 'filtered — zero rows match selection (honest empty)'
        else 'filtered — metric and row set published for the selected scope'
      end,
      'scope', jsonb_build_object(
        'filtered', case when m.n is null then false else (
          p_sprint_id is not null
          or cardinality(coalesce(p_modules, '{}'::text[])) > 0
          or cardinality(coalesce(p_severities, '{}'::text[])) > 0
          or cardinality(coalesce(p_assignees, '{}'::text[])) > 0
        ) end,
        'sprint_applies', m.n is not null,
        'attribute_filters_apply', m.n is not null,
        'note', case when m.n is null then 'reserved' else 'server-filtered' end
      )
    )
  ) as value
  from cohort_meta m
  left join cohort_stats s on s.key = m.key
  left join cohort_agg a on a.key = m.key
),
cohort_issue_keys as (
  select distinct payload ->> 'issue_key' as issue_key
  from all_cohort_rows
  where payload ->> 'issue_key' is not null
  union
  select distinct d.issue_key
  from report_drilldown d
  where d.issue_key is not null
),
issue_meta_json as (
  select coalesce(jsonb_object_agg(
    i.issue_key,
    jsonb_build_object(
      'module', i.module,
      'sprint_id', (
        select si.sprint_id from sprint_issues si
        where si.issue_id = i.issue_id and si.removed_at is null
        order by si.added_at desc nulls last, si.sprint_id desc limit 1
      ),
      'issue_type', i.issue_type
    )
  ), '{}'::jsonb) as value
  from filtered_issues i
  join cohort_issue_keys k on k.issue_key = i.issue_key
),
issue_keys_json as (
  select coalesce(jsonb_agg(issue_key order by issue_key), '[]'::jsonb) as value
  from cohort_issue_keys
),
assignee_options_json as (
  select coalesce(jsonb_agg(jsonb_build_object('assignee_name', assignee_name, 'issue_count', issue_count) order by assignee_name), '[]'::jsonb) as value
  from (
    select d.assignee_name, count(*)::int as issue_count
    from option_drilldown d
    where d.assignee_name is not null
    group by d.assignee_name
  ) a
),
module_options_json as (
  select coalesce(jsonb_agg(jsonb_build_object('module', module, 'issue_count', issue_count) order by issue_count desc, module asc nulls last), '[]'::jsonb) as value
  from v_module_counts
)
select jsonb_build_object(
  'generated_at', now(),
  'filters', jsonb_build_object(
    'sprintId', p_sprint_id,
    'modules', case when p_modules is null or cardinality(p_modules) = 0 then null else to_jsonb(p_modules) end,
    'severities', case when p_severities is null or cardinality(p_severities) = 0 then null else to_jsonb(p_severities) end,
    'assignees', case when p_assignees is null or cardinality(p_assignees) = 0 then null else to_jsonb(p_assignees) end
  ),
  'sprints', coalesce((
    select jsonb_agg(to_jsonb(d) order by d.start_date desc, d.sprint_id desc)
    from discipline_agg d
  ), '[]'::jsonb),
  'assignee_options', (select value from assignee_options_json),
  'issue_meta', (select value from issue_meta_json),
  'issue_keys', (select value from issue_keys_json),
  'hero', jsonb_build_object(
    'status', 'decision_required',
    'active_sprint_id', (select sprint_id from target_sprint),
    'value', (select commitment_completion_pct from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id),
    'scope_note', case when p_sprint_id is null then 'active sprint' else 'selected sprint' end
  ),
  'sprint_discipline', coalesce((select jsonb_agg(to_jsonb(d) order by d.start_date desc, d.sprint_id desc) from discipline_agg d), '[]'::jsonb),
  'sprint_summary', coalesce((select jsonb_agg(to_jsonb(s) order by s.start_date desc, s.sprint_id desc) from summary_agg s), '[]'::jsonb),
  'sprint_throughput', coalesce((select jsonb_agg(to_jsonb(t) order by t.sprint_start desc, t.sprint_id desc) from throughput_agg t), '[]'::jsonb),
  'stage_summary', '[]'::jsonb,
  'cycle_time_by_sprint', coalesce((select jsonb_agg(to_jsonb(c) order by c.sprint_start desc, c.sprint_id desc) from cycle_by_sprint_agg c), '[]'::jsonb),
  'cycle_time_org', (select jsonb_build_object('sprint_id', null, 'sprint_name', '(all time)', 'n', c.n, 'median_days', c.median_days, 'p75_days', c.p75_days, 'p90_days', c.p90_days, 'sprint_start', null) from cycle_org_agg c),
  'drilldown', coalesce((select jsonb_agg(to_jsonb(d) order by d.sprint_id, d.issue_id) from report_drilldown d), '[]'::jsonb),
  'metric_cohorts', (select value from cohort_json),
  'module_options', (select value from module_options_json),
  'scope', jsonb_build_object(
    'dashboard', jsonb_build_object(
      'filtered', p_sprint_id is not null
        or cardinality(coalesce(p_modules, '{}'::text[])) > 0
        or cardinality(coalesce(p_severities, '{}'::text[])) > 0
        or cardinality(coalesce(p_assignees, '{}'::text[])) > 0,
      'sprint_applies', true,
      'attribute_filters_apply', true,
      'note', 'server-published filtered dashboard core'
    )
  )
);
$function$;

-- Aligned get_filtered_dashboard_core_025_base_submodule
CREATE OR REPLACE FUNCTION jira.get_filtered_dashboard_core_025_base_submodule(p_sprint_id bigint DEFAULT NULL::bigint, p_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[], p_sub_modules text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '20s'
AS $function$
with
window_sprints as (
  select
    ds.id::bigint as sprint_id,
    ds.name as sprint_name,
    ds.state,
    ds.start_date,
    ds.end_date,
    coalesce(s.complete_date, ds.end_date) as sprint_complete,
    coalesce(s.goal, '') as goal
  from v_dashboard_sprints ds
  join sprints s on s.id = ds.id
),
target_sprint as (
  select ws.*
  from window_sprints ws
  where
    (p_sprint_id is not null and ws.sprint_id = p_sprint_id)
    or (
      p_sprint_id is null
      and ws.sprint_id = coalesce(
        (select a.sprint_id from window_sprints a where a.state = 'active'
         order by a.start_date desc, a.sprint_id desc limit 1),
        (select n.sprint_id from window_sprints n
         order by n.start_date desc, n.sprint_id desc limit 1)
      )
    )
),
report_sprints as (
  select ws.*
  from window_sprints ws
  where p_sprint_id is null
     or ws.sprint_id = (select t.sprint_id from target_sprint t limit 1)
),
filtered_issues as materialized (
  select i.*
  from v_issue_normalized i
  where i.project_key = 'SPEND'
    and _dashboard_filter_matches_submodule(
      i.module,
      i.sub_module,
      i.severity,
      i.assignee_name,
      p_modules,
      p_sub_modules,
      p_severities,
      p_assignees
    )
    and (
      p_sprint_id is null
      or exists (
        select 1
        from sprint_issues si
        join window_sprints ws on ws.sprint_id = si.sprint_id
        where si.issue_id = i.issue_id
          and si.removed_at is null
          and si.sprint_id = p_sprint_id
      )
    )
),
option_drilldown as materialized (
  select d.*
  from v_sprint_drilldown d
  join window_sprints ws on ws.sprint_id = d.sprint_id
),
window_drilldown as materialized (
  select d.*
  from v_sprint_drilldown d
  join window_sprints ws on ws.sprint_id = d.sprint_id
  where _dashboard_filter_matches_submodule(
    d.module,
    d.sub_module,
    d.severity,
    d.assignee_name,
    p_modules,
    p_sub_modules,
    p_severities,
    p_assignees
  )
),
report_drilldown as materialized (
  select d.*
  from window_drilldown d
  join report_sprints rs on rs.sprint_id = d.sprint_id
),
sprint_removals as materialized (
  select h.issue_id, h.from_display, min(h.changed_at) as removed_at
  from issue_field_history h
  where h.field = 'Sprint'
  group by h.issue_id, h.from_display
),
discipline_base as materialized (
  select
    d.sprint_id,
    d.sprint_name,
    d.sprint_state as state,
    d.sprint_start as start_date,
    d.sprint_end as end_date,
    d.issue_id,
    d.issue_key,
    d.summary,
    d.issue_type,
    d.status_name,
    d.status_category,
    d.is_done,
    d.priority,
    d.severity,
    d.module,
    d.sub_module,
    d.assignee_name,
    d.created_at,
    d.resolved_at,
    d.created_at <= d.sprint_start + interval '2 days' as was_committed
  from window_drilldown d
  where d.is_direct_member and not d.is_subtask
),
discipline_live as materialized (
  select b.*
  from discipline_base b
  left join sprint_removals r
    on r.issue_id = b.issue_id
   and r.from_display = b.sprint_name
  where r.removed_at is null
     or r.removed_at > b.start_date + interval '2 days'
),
report_discipline_live as materialized (
  select d.*
  from discipline_live d
  join report_sprints rs on rs.sprint_id = d.sprint_id
),
carried_rows as materialized (
  select d.*
  from discipline_live d
  where not d.is_done
    and exists (
      select 1
      from sprint_issues ns
      join sprints nxt on nxt.id = ns.sprint_id
      where ns.issue_id = d.issue_id
        and ns.removed_at is null
        and nxt.name like 'SPEND%'
        and nxt.start_date > d.start_date
    )
),
discipline_agg as (
  select
    sprint_id,
    sprint_name,
    state,
    start_date,
    end_date,
    count(*)::int as scope_now,
    count(*) filter (where was_committed)::int as committed,
    count(*) filter (where was_committed and is_done)::int as committed_done,
    round(100.0 * count(*) filter (where was_committed and is_done)::numeric
      / nullif(count(*) filter (where was_committed), 0), 1) as commitment_completion_pct,
    count(*) filter (where not was_committed)::int as added_mid_sprint,
    round(100.0 * count(*) filter (where not was_committed)::numeric
      / nullif(count(*), 0), 1) as mid_sprint_add_pct,
    count(*) filter (where is_done)::int as done_now,
    round(100.0 * count(*) filter (where is_done)::numeric
      / nullif(count(*), 0), 1) as scope_completion_pct,
    (select count(*)::int from carried_rows c where c.sprint_id = d.sprint_id)
      as carried_to_next
  from report_discipline_live d
  group by sprint_id, sprint_name, state, start_date, end_date
),
first_done as materialized (
  select h.issue_id, min(h.changed_at) as first_done_at
  from issue_field_history h
  join filtered_issues i on i.issue_id = h.issue_id
  where h.field = 'status'
    and i.status_category = 'Done'
    and h.to_display in ('Done', 'Closed', 'Completed', 'Issue Resolved')
  group by h.issue_id
),
throughput_all as materialized (
  select d.*, fd.first_done_at, ws.sprint_complete
  from window_drilldown d
  join window_sprints ws on ws.sprint_id = d.sprint_id
  join first_done fd on fd.issue_id = d.issue_id
  where d.is_direct_member
    and not d.is_subtask
    and d.status_category = 'Done'
    and fd.first_done_at >= ws.start_date
    and fd.first_done_at < ws.sprint_complete + interval '2 days'
),
throughput_rows as materialized (
  select t.*
  from throughput_all t
  join report_sprints rs on rs.sprint_id = t.sprint_id
),
published_throughput as materialized (
  select t.sprint_id, t.throughput, t.first_done_after_start
  from v_sprint_throughput t
  join report_sprints rs on rs.sprint_id = t.sprint_id
),
throughput_agg as (
  select
    t.sprint_id,
    t.sprint_name,
    min(t.sprint_start) as sprint_start,
    max(t.sprint_complete) as sprint_complete,
    case when cardinality(coalesce(p_modules, '{}'::text[])) = 0
           and cardinality(coalesce(p_severities, '{}'::text[])) = 0
           and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
           and cardinality(coalesce(p_sub_modules, '{}'::text[])) = 0
         then max(pt.throughput)::int
         else count(*)::int
    end as throughput,
    case when cardinality(coalesce(p_modules, '{}'::text[])) = 0
           and cardinality(coalesce(p_severities, '{}'::text[])) = 0
           and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
           and cardinality(coalesce(p_sub_modules, '{}'::text[])) = 0
         then max(pt.first_done_after_start)::int
         else count(*) filter (where t.created_at > t.sprint_start + interval '2 days')::int
    end as first_done_after_start
  from throughput_rows t
  left join published_throughput pt on pt.sprint_id = t.sprint_id
  group by t.sprint_id, t.sprint_name
),
summary_agg as (
  select
    d.sprint_id,
    d.sprint_name,
    d.sprint_state as state,
    d.sprint_start as start_date,
    d.sprint_end as end_date,
    count(*) filter (where d.is_direct_member)::int as direct_issues,
    count(*)::int as all_issues,
    count(*) filter (where d.is_done)::int as done_issues,
    round(100.0 * count(*) filter (where d.is_done)::numeric
      / nullif(count(*), 0), 1) as completion_pct,
    count(*) filter (where d.issue_type = 'Bug' and not d.is_done)::int as open_bugs,
    count(*) filter (where d.issue_type = 'Bug' and d.is_done)::int as done_bugs,
    count(*) filter (where not d.is_done and d.priority = 'Highest')::int as open_highest,
    count(distinct d.assignee_id)::int as contributors,
    count(*) filter (where d.severity = 'L1' and not d.is_done)::int as open_l1,
    coalesce(sum(d.story_points) filter (where d.is_done), 0)::numeric as done_points,
    coalesce(sum(d.story_points), 0)::numeric as total_points,
    count(*) filter (where d.created_at > d.sprint_start)::int as added_after_start,
    max(coalesce(rs.goal, '')) as goal
  from report_drilldown d
  join report_sprints rs on rs.sprint_id = d.sprint_id
  group by d.sprint_id, d.sprint_name, d.sprint_state, d.sprint_start, d.sprint_end
),
cycle_rows as materialized (
  select
    ct.issue_id,
    i.issue_key,
    i.summary,
    i.issue_type,
    i.status_name,
    i.severity,
    i.priority,
    i.assignee_name,
    i.created_at,
    i.resolved_at,
    i.module,
    i.sub_module,
    ct.done_at,
    extract(epoch from (ct.done_at - ct.first_in_progress_at)) / 86400.0 as cycle_days
  from v_issue_cycle_times ct
  join filtered_issues i on i.issue_id = ct.issue_id
  where ct.done_at is not null and ct.first_in_progress_at is not null
),
cycle_sprint_rows as materialized (
  select cr.*, ws.sprint_id, ws.sprint_name, ws.start_date as sprint_start
  from cycle_rows cr
  join sprint_issues si on si.issue_id = cr.issue_id and si.removed_at is null
  join report_sprints ws on ws.sprint_id = si.sprint_id
  where cr.done_at >= ws.start_date
    and cr.done_at < ws.sprint_complete + interval '2 days'
),
cycle_by_sprint_agg as (
  select
    sprint_id,
    sprint_name,
    count(*)::int as n,
    round(percentile_cont(0.5) within group (order by cycle_days)::numeric, 2) as median_days,
    round(percentile_cont(0.75) within group (order by cycle_days)::numeric, 2) as p75_days,
    round(percentile_cont(0.90) within group (order by cycle_days)::numeric, 2) as p90_days,
    max(sprint_start) as sprint_start
  from cycle_sprint_rows
  group by sprint_id, sprint_name
),
cycle_org_agg as (
  select
    count(*)::int as n,
    round(percentile_cont(0.5) within group (order by cycle_days)::numeric, 2) as median_days,
    round(percentile_cont(0.75) within group (order by cycle_days)::numeric, 2) as p75_days,
    round(percentile_cont(0.90) within group (order by cycle_days)::numeric, 2) as p90_days
  from cycle_rows
),
cohort_meta as materialized (
  select
    mc.key,
    mc.title,
    mc.value,
    mc.unit,
    mc.n,
    mc.denominator,
    mc.source,
    mc.definition,
    mc.definition_ref,
    mc.row_type,
    mc.source_note
  from jira.v_metric_cohorts_active_v1 mc
),
cohort_expanded as materialized (
  select
    m.key,
    e.payload,
    e.ord
  from cohort_meta m
  join jira.v_metric_cohorts_active_v1 mc on mc.key = m.key
  left join lateral jsonb_array_elements(
    case when jsonb_typeof(coalesce(mc.rows, '[]'::jsonb)) = 'array'
      then coalesce(mc.rows, '[]'::jsonb)
      else '[]'::jsonb end
  ) with ordinality e(payload, ord) on true
),
filtered_cohort_rows as materialized (
  select e.key, e.payload, e.ord
  from cohort_expanded e
  join cohort_meta m on m.key = e.key
  left join filtered_issues i on i.issue_key = e.payload ->> 'issue_key'
  where m.n is null
     or (
       (p_sprint_id is null or (
         i.issue_id is not null and exists (
           select 1 from sprint_issues si
           where si.issue_id = i.issue_id
             and si.sprint_id = p_sprint_id
             and si.removed_at is null
         )
       ))
       and _dashboard_filter_matches_submodule(
         case when e.payload ? 'module' then e.payload ->> 'module' else i.module end,
         case when e.payload ? 'sub_module' then e.payload ->> 'sub_module' else i.sub_module end,
         case when e.payload ? 'severity' then e.payload ->> 'severity' else i.severity end,
         case when e.payload ? 'assignee_name' then e.payload ->> 'assignee_name' else i.assignee_name end,
         p_modules,
         p_sub_modules,
         p_severities,
         p_assignees
       )
       and (coalesce(array_length(p_sub_modules, 1), 0) = 0 or i.issue_id is not null)
     )
),
dynamic_cohort_rows as materialized (
  select
    'commit_s45'::text as key,
    row_number() over (order by d.resolved_at desc nulls last, d.issue_key) as ord,
    jsonb_build_object(
      'issue_key', d.issue_key, 'summary', d.summary, 'issue_type', d.issue_type,
      'severity', d.severity, 'status_name', d.status_name, 'priority', d.priority,
      'assignee_name', d.assignee_name, 'created_at', d.created_at,
      'resolved_at', d.resolved_at, 'module', d.module, 'sub_module', d.sub_module, 'sprint_id', d.sprint_id
    ) as payload
  from discipline_live d
  join target_sprint t on t.sprint_id = d.sprint_id
  where d.was_committed and d.is_done
  union all
  select
    'commit_s44',
    row_number() over (order by d.resolved_at desc nulls last, d.issue_key),
    jsonb_build_object(
      'issue_key', d.issue_key, 'summary', d.summary, 'issue_type', d.issue_type,
      'severity', d.severity, 'status_name', d.status_name, 'priority', d.priority,
      'assignee_name', d.assignee_name, 'created_at', d.created_at,
      'resolved_at', d.resolved_at, 'module', d.module, 'sub_module', d.sub_module, 'sprint_id', d.sprint_id
    )
  from discipline_live d
  where d.was_committed and d.is_done
    and d.sprint_id = (
      select p.sprint_id from window_sprints p
      join target_sprint t on p.start_date < t.start_date
      order by p.start_date desc, p.sprint_id desc limit 1
    )
  union all
  select
    'adds_s45',
    row_number() over (order by d.created_at desc, d.issue_key),
    jsonb_build_object(
      'issue_key', d.issue_key, 'summary', d.summary, 'issue_type', d.issue_type,
      'severity', d.severity, 'status_name', d.status_name, 'priority', d.priority,
      'assignee_name', d.assignee_name, 'created_at', d.created_at,
      'resolved_at', d.resolved_at, 'module', d.module, 'sub_module', d.sub_module, 'sprint_id', d.sprint_id
    )
  from discipline_live d
  join target_sprint t on t.sprint_id = d.sprint_id
  where not d.was_committed
  union all
  select
    'carried_s45',
    row_number() over (order by d.created_at desc, d.issue_key),
    jsonb_build_object(
      'issue_key', d.issue_key, 'summary', d.summary, 'issue_type', d.issue_type,
      'severity', d.severity, 'status_name', d.status_name, 'priority', d.priority,
      'assignee_name', d.assignee_name, 'created_at', d.created_at,
      'resolved_at', d.resolved_at, 'module', d.module, 'sub_module', d.sub_module, 'sprint_id', d.sprint_id
    )
  from carried_rows d
  join target_sprint t on t.sprint_id = d.sprint_id
  union all
  select
    'throughput_s45',
    row_number() over (order by d.first_done_at desc, d.issue_key),
    jsonb_build_object(
      'issue_key', d.issue_key, 'summary', d.summary, 'issue_type', d.issue_type,
      'severity', d.severity, 'status_name', d.status_name, 'priority', d.priority,
      'assignee_name', d.assignee_name, 'created_at', d.created_at,
      'resolved_at', d.resolved_at, 'module', d.module, 'sub_module', d.sub_module, 'sprint_id', d.sprint_id
    )
  from throughput_all d
  join target_sprint t on t.sprint_id = d.sprint_id
  union all
  select
    'cycle_s45',
    row_number() over (order by d.cycle_days desc nulls last, d.issue_key),
    jsonb_build_object(
      'issue_key', d.issue_key, 'summary', d.summary, 'issue_type', d.issue_type,
      'severity', d.severity, 'status_name', d.status_name, 'priority', d.priority,
      'assignee_name', d.assignee_name, 'created_at', d.created_at,
      'resolved_at', d.resolved_at, 'module', d.module, 'sub_module', d.sub_module, 'sprint_id', d.sprint_id,
      'cycle_days', round(d.cycle_days::numeric, 1)
    )
  from cycle_sprint_rows d
  join target_sprint t on t.sprint_id = d.sprint_id
),
all_cohort_rows as materialized (
  select key, ord, payload
  from filtered_cohort_rows
  where key not in ('commit_s45', 'commit_s44', 'adds_s45', 'carried_s45', 'throughput_s45', 'cycle_s45')
  union all
  select key, ord, payload from dynamic_cohort_rows
),
cohort_agg as (
  select
    key,
    count(*)::int as row_count,
    jsonb_agg(payload order by ord) as rows,
    jsonb_agg(payload ->> 'issue_key' order by ord) as issue_keys
  from all_cohort_rows
  group by key
),
cohort_stats as (
  select
    'commit_s45'::text as key,
    coalesce((select committed_done::double precision from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0) as value,
    'issues'::text as unit,
    coalesce((select committed_done::bigint from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0) as n,
    coalesce((select committed::bigint from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0) as denominator
  union all
  select 'commit_s44',
    coalesce((select count(*)::double precision from discipline_live d where d.was_committed and d.is_done and d.sprint_id = (select p.sprint_id from window_sprints p join target_sprint t on p.start_date < t.start_date order by p.start_date desc, p.sprint_id desc limit 1)), 0),
    'issues',
    coalesce((select count(*)::bigint from discipline_live d where d.was_committed and d.is_done and d.sprint_id = (select p.sprint_id from window_sprints p join target_sprint t on p.start_date < t.start_date order by p.start_date desc, p.sprint_id desc limit 1)), 0),
    coalesce((select count(*)::bigint from discipline_live d where d.was_committed and d.sprint_id = (select p.sprint_id from window_sprints p join target_sprint t on p.start_date < t.start_date order by p.start_date desc, p.sprint_id desc limit 1)), 0)
  union all
  select 'adds_s45',
    coalesce((select added_mid_sprint::double precision from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0),
    'issues',
    coalesce((select added_mid_sprint::bigint from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0),
    coalesce((select scope_now::bigint from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0)
  union all
  select 'carried_s45',
    coalesce((select carried_to_next::double precision from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0),
    'issues',
    coalesce((select carried_to_next::bigint from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0),
    coalesce((select scope_now::bigint from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0)
  union all
  select 'throughput_s45',
    coalesce((select throughput::double precision from throughput_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0),
    'issues',
    coalesce((select throughput::bigint from throughput_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0),
    coalesce((select throughput::bigint from throughput_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0)
  union all
  select 'cycle_s45',
    (select median_days::double precision from cycle_by_sprint_agg d join target_sprint t on t.sprint_id = d.sprint_id),
    'days',
    coalesce((select n::bigint from cycle_by_sprint_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0),
    coalesce((select n::bigint from cycle_by_sprint_agg d join target_sprint t on t.sprint_id = d.sprint_id), 0)
  union all
  select 'cycle_org', median_days::double precision, 'days', n::bigint, n::bigint from cycle_org_agg
  union all
  select
    m.key,
    case when m.key in ('open_bugs', 'bug_age_over90', 'open_l1_s45', 'stale_7d', 'blocked', 'stale_blocked', 'wip_open', 'qa_queue')
      then coalesce(a.row_count, 0)::double precision else m.value end,
    m.unit,
    case when m.key in ('open_bugs', 'bug_age_over90', 'open_l1_s45', 'stale_7d', 'blocked', 'stale_blocked', 'wip_open', 'qa_queue')
      then coalesce(a.row_count, 0)::bigint else m.n::bigint end,
    case when m.key in ('open_bugs', 'bug_age_over90', 'open_l1_s45', 'stale_7d', 'blocked', 'stale_blocked', 'wip_open', 'qa_queue')
      then coalesce(a.row_count, 0)::bigint else m.denominator::bigint end
  from cohort_meta m
  left join cohort_agg a on a.key = m.key
  where m.key not in ('commit_s45', 'commit_s44', 'adds_s45', 'carried_s45', 'throughput_s45', 'cycle_s45', 'cycle_org')
),
cohort_json as (
  select jsonb_object_agg(
    m.key,
    jsonb_build_object(
      'title', case m.key
        when 'commit_s45' then coalesce('Delivered from commitment — ' || (select sprint_name from target_sprint), m.title)
        when 'commit_s44' then coalesce('Delivered from commitment — ' || (select p.sprint_name from window_sprints p join target_sprint t on p.start_date < t.start_date order by p.start_date desc, p.sprint_id desc limit 1), m.title)
        when 'adds_s45' then coalesce('Added after start — ' || (select sprint_name from target_sprint), m.title)
        when 'carried_s45' then coalesce('Carried to next — ' || (select sprint_name from target_sprint), m.title)
        when 'throughput_s45' then coalesce('Delivered this sprint — ' || (select sprint_name from target_sprint), m.title)
        when 'cycle_s45' then coalesce('Cycle time — ' || (select sprint_name from target_sprint), m.title)
        else m.title end,
      'value', coalesce(s.value, m.value),
      'unit', coalesce(s.unit, m.unit),
      'n', case when m.n is null then null else coalesce(s.n, m.n::bigint) end,
      'denominator', case when m.n is null then null else coalesce(s.denominator, m.denominator::bigint) end,
      'source', m.source,
      'definition', m.definition,
      'definition_ref', m.definition_ref,
      'row_type', m.row_type,
      'rows_shown', case when m.n is null then 0 else coalesce(a.row_count, 0) end,
      'rows', coalesce(a.rows, '[]'::jsonb),
      'issue_keys', coalesce(a.issue_keys, '[]'::jsonb),
      'source_note', m.source_note,
      'is_filtered', case when m.n is null then false else (
        p_sprint_id is not null
        or cardinality(coalesce(p_modules, '{}'::text[])) > 0
        or cardinality(coalesce(p_severities, '{}'::text[])) > 0
        or cardinality(coalesce(p_assignees, '{}'::text[])) > 0
          or cardinality(coalesce(p_sub_modules, '{}'::text[])) > 0
      ) end,
      'scope_note', case
        when m.n is null then 'reserved (n null) — not published; renders ⧗'
        when p_sprint_id is null
          and cardinality(coalesce(p_modules, '{}'::text[])) = 0
          and cardinality(coalesce(p_severities, '{}'::text[])) = 0
          and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
           and cardinality(coalesce(p_sub_modules, '{}'::text[])) = 0
          then 'unfiltered — server-published dashboard scope'
        when coalesce(a.row_count, 0) = 0 then 'filtered — zero rows match selection (honest empty)'
        else 'filtered — metric and row set published for the selected scope'
      end,
      'scope', jsonb_build_object(
        'filtered', case when m.n is null then false else (
          p_sprint_id is not null
          or cardinality(coalesce(p_modules, '{}'::text[])) > 0
          or cardinality(coalesce(p_severities, '{}'::text[])) > 0
          or cardinality(coalesce(p_assignees, '{}'::text[])) > 0
          or cardinality(coalesce(p_sub_modules, '{}'::text[])) > 0
        ) end,
        'sprint_applies', m.n is not null,
        'attribute_filters_apply', m.n is not null,
        'note', case when m.n is null then 'reserved' else 'server-filtered' end
      )
    )
  ) as value
  from cohort_meta m
  left join cohort_stats s on s.key = m.key
  left join cohort_agg a on a.key = m.key
),
cohort_issue_keys as (
  select distinct payload ->> 'issue_key' as issue_key
  from all_cohort_rows
  where payload ->> 'issue_key' is not null
  union
  select distinct d.issue_key
  from report_drilldown d
  where d.issue_key is not null
),
issue_meta_json as (
  select coalesce(jsonb_object_agg(
    i.issue_key,
    jsonb_build_object(
      'module', i.module,
      'sub_module', i.sub_module,
      'sprint_id', (
        select si.sprint_id from sprint_issues si
        where si.issue_id = i.issue_id and si.removed_at is null
        order by si.added_at desc nulls last, si.sprint_id desc limit 1
      ),
      'issue_type', i.issue_type
    )
  ), '{}'::jsonb) as value
  from filtered_issues i
  join cohort_issue_keys k on k.issue_key = i.issue_key
),
issue_keys_json as (
  select coalesce(jsonb_agg(issue_key order by issue_key), '[]'::jsonb) as value
  from cohort_issue_keys
),
assignee_options_json as (
  select coalesce(jsonb_agg(jsonb_build_object('assignee_name', assignee_name, 'issue_count', issue_count) order by assignee_name), '[]'::jsonb) as value
  from (
    select d.assignee_name, count(*)::int as issue_count
    from option_drilldown d
    where d.assignee_name is not null
    group by d.assignee_name
  ) a
),
module_options_json as (
  select coalesce(jsonb_agg(jsonb_build_object('module', module, 'issue_count', issue_count) order by issue_count desc, module asc nulls last), '[]'::jsonb) as value
  from v_module_counts
)
select jsonb_build_object(
  'generated_at', now(),
  'filters', jsonb_build_object(
    'sprintId', p_sprint_id,
    'modules', case when p_modules is null or cardinality(p_modules) = 0 then null else to_jsonb(p_modules) end,
    'subModules', case when p_sub_modules is null or cardinality(p_sub_modules) = 0 then null else to_jsonb(p_sub_modules) end,
    'severities', case when p_severities is null or cardinality(p_severities) = 0 then null else to_jsonb(p_severities) end,
    'assignees', case when p_assignees is null or cardinality(p_assignees) = 0 then null else to_jsonb(p_assignees) end
  ),
  'sprints', coalesce((
    select jsonb_agg(to_jsonb(d) order by d.start_date desc, d.sprint_id desc)
    from discipline_agg d
  ), '[]'::jsonb),
  'assignee_options', (select value from assignee_options_json),
  'issue_meta', (select value from issue_meta_json),
  'issue_keys', (select value from issue_keys_json),
  'hero', jsonb_build_object(
    'status', 'decision_required',
    'active_sprint_id', (select sprint_id from target_sprint),
    'value', (select commitment_completion_pct from discipline_agg d join target_sprint t on t.sprint_id = d.sprint_id),
    'scope_note', case when p_sprint_id is null then 'active sprint' else 'selected sprint' end
  ),
  'sprint_discipline', coalesce((select jsonb_agg(to_jsonb(d) order by d.start_date desc, d.sprint_id desc) from discipline_agg d), '[]'::jsonb),
  'sprint_summary', coalesce((select jsonb_agg(to_jsonb(s) order by s.start_date desc, s.sprint_id desc) from summary_agg s), '[]'::jsonb),
  'sprint_throughput', coalesce((select jsonb_agg(to_jsonb(t) order by t.sprint_start desc, t.sprint_id desc) from throughput_agg t), '[]'::jsonb),
  'stage_summary', '[]'::jsonb,
  'cycle_time_by_sprint', coalesce((select jsonb_agg(to_jsonb(c) order by c.sprint_start desc, c.sprint_id desc) from cycle_by_sprint_agg c), '[]'::jsonb),
  'cycle_time_org', (select jsonb_build_object('sprint_id', null, 'sprint_name', '(all time)', 'n', c.n, 'median_days', c.median_days, 'p75_days', c.p75_days, 'p90_days', c.p90_days, 'sprint_start', null) from cycle_org_agg c),
  'drilldown', coalesce((select jsonb_agg(to_jsonb(d) order by d.sprint_id, d.issue_id) from report_drilldown d), '[]'::jsonb),
  'metric_cohorts', (select value from cohort_json),
  'module_options', (select value from module_options_json),
  'scope', jsonb_build_object(
    'dashboard', jsonb_build_object(
      'filtered', p_sprint_id is not null
        or cardinality(coalesce(p_modules, '{}'::text[])) > 0
        or cardinality(coalesce(p_severities, '{}'::text[])) > 0
        or cardinality(coalesce(p_assignees, '{}'::text[])) > 0
          or cardinality(coalesce(p_sub_modules, '{}'::text[])) > 0,
      'sprint_applies', true,
      'attribute_filters_apply', true,
      'note', 'server-published filtered dashboard core'
    )
  )
);
$function$;
