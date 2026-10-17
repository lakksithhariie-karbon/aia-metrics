-- Jira Engineering Flow: one published reporting clock, without changing
-- snapshots, raw Jira rows, ingestion, dashboard facade or evidence readers.
--
-- 2026-10-17, published sync 107: Core stale_7d=260 / stale_blocked=13,
-- dynamic Flow stale_all=581 / stale_blocked=38. This differs because issues
-- cross a seven-day age boundary after a cohort snapshot has been published.
--
-- The replacement preserves the exact signature, STABLE SECURITY DEFINER,
-- search_path and statement timeout of the previously deployed function.
-- All existing permissions are preserved by CREATE OR REPLACE FUNCTION.
-- Published-cutoff membership was checked read-only in eight filter scopes,
-- comparing issue-key SETS for both stale and stale+blocked.
-- This migration is deliberately limited to ONE Flow reader.
--
-- Review rollback: supabase/rollbacks/20261017_jira_flow_published_cutoff_v1.sql
CREATE OR REPLACE FUNCTION jira.get_filtered_dashboard_flow_submodule(p_sprint_id bigint DEFAULT NULL::bigint, p_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[], p_sub_modules text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '8s'
AS $function$
with
published_cutoff as materialized (
  -- Core's stored metric cohorts were computed at this published cutoff.
  -- Flow must not advance stale membership between validated Jira syncs.
  select refreshed_at as as_of
  from jira.dashboard_snapshot_refresh_state
  where singleton
),
window_sprints as (
  select ds.id::bigint as sprint_id, ds.name as sprint_name,
         ds.state as sprint_state, ds.start_date, ds.end_date,
         coalesce(s.complete_date, ds.end_date) as sprint_complete
  from v_dashboard_sprints ds
  join sprints s on s.id = ds.id
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
target_sprint as (
  select ws.*
  from window_sprints ws
  where (p_sprint_id is not null and ws.sprint_id = p_sprint_id)
     or (p_sprint_id is null and ws.sprint_state = 'active')
  order by ws.start_date desc, ws.sprint_id desc
  limit 1
),
status_events as materialized (
  select h.issue_id, h.to_display as raw_stage, h.changed_at,
         lead(h.changed_at) over (
           partition by h.issue_id order by h.changed_at, h.itemordinal
         ) as next_change
  from issue_field_history h
  join filtered_issues i on i.issue_id = h.issue_id
  where h.field = 'status'
),
stage_per_issue as materialized (
  select issue_id,
         initcap(raw_stage) as stage,
         sum(extract(epoch from (coalesce(next_change, now()) - changed_at))) / 3600.0 as hours
  from status_events
  where lower(raw_stage) not in ('done', 'issue resolved', 'spendlytics')
  group by issue_id, initcap(raw_stage)
),
stage_rows as materialized (
  select distinct
    d.sprint_id, d.sprint_name, d.sprint_state,
    d.sprint_start, d.sprint_end,
    sp.stage, sp.hours
  from (
    select sd.sprint_id, sd.sprint_name, sd.sprint_state,
           sd.sprint_start, sd.sprint_end,
           sd.issue_id, sd.is_direct_member, sd.is_subtask,
           sd.module, sd.sub_module, sd.severity, sd.assignee_name
    from v_sprint_drilldown sd
    join window_sprints ws on ws.sprint_id = sd.sprint_id
  ) d
  join stage_per_issue sp on sp.issue_id = d.issue_id
  where d.is_direct_member and not d.is_subtask
    and (p_sprint_id is null or d.sprint_id = p_sprint_id)
    and _dashboard_filter_matches_submodule(
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
stage_summary as (
  select sprint_id, sprint_name, sprint_state, sprint_start, sprint_end, stage,
         count(*)::int as issues_in_stage,
         round(avg(hours)::numeric, 1) as avg_hours,
         round(percentile_cont(0.5) within group (order by hours)::numeric, 1) as median_hours,
         round(percentile_cont(0.9) within group (order by hours)::numeric, 1) as p90_hours
  from stage_rows
  group by sprint_id, sprint_name, sprint_state, sprint_start, sprint_end, stage
),
target_code_review as (
  select ss.*
  from stage_summary ss
  join target_sprint ts on ts.sprint_id = ss.sprint_id
  where ss.stage = 'Code Review'
),
flow_rows as materialized (
  select fs.issue_id, fs.issue_key, fs.summary, fs.severity, fs.status_name,
         extract(epoch from (cutoff.as_of - i.updated_at)) / 86400.0 as stale_calc_days,
         case when fs.is_blocked and fs.moved_to_blocked_at is not null
           then extract(epoch from (cutoff.as_of - fs.moved_to_blocked_at)) / 86400.0
           else null::numeric end as blocked_days,
         (fs.is_open and fs.is_blocked and
           cutoff.as_of - i.updated_at > interval '7 days') as is_stale_blocked,
         fs.is_open,
         (cutoff.as_of - i.updated_at > interval '7 days') as is_stale,
         fs.is_blocked,
         i.issue_type, i.priority, i.assignee_name, i.created_at,
         i.resolved_at, i.module
  from v_issue_flow_state fs
  join filtered_issues i on i.issue_id = fs.issue_id
  cross join published_cutoff cutoff
),
flow_counts as (
  select
    count(*) filter (where is_open and is_stale)::int as stale_all,
    count(*) filter (where is_open and is_blocked)::int as blocked_all,
    count(*) filter (where is_open and is_stale_blocked)::int as stale_blocked,
    count(*) filter (where is_open)::int as open_total
  from flow_rows
),
wip_counts as (
  select status_name, count(*)::int as issue_count
  from flow_rows
  where is_open
  group by status_name
),
wip_total as (
  select coalesce(sum(issue_count), 0)::numeric as total from wip_counts
),
wip_json as (
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'status_name', w.status_name,
      'issue_count', w.issue_count,
      'pct', round(100.0 * w.issue_count / nullif(t.total, 0), 1)
    ) order by w.issue_count desc, w.status_name
  ), '[]'::jsonb) as value
  from wip_counts w cross join wip_total t
),
bugs as materialized (
  select i.*,
         case when i.is_done then coalesce(ct.done_at, i.resolved_at) end as done_eff
  from filtered_issues i
  left join v_issue_cycle_times ct on ct.issue_id = i.issue_id
  where i.issue_type = 'Bug'
),
open_bugs as materialized (
  select b.*, extract(epoch from (now() - b.created_at)) / 86400.0 as age_days
  from bugs b
  where not b.is_done
),
bug_total as (
  select count(*)::int as open_bugs,
         percentile_cont(0.5) within group (order by age_days) as median_age_days
  from open_bugs
),
bug_severity_json as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'severity', severity, 'count', count
  ) order by count desc, severity nulls last), '[]'::jsonb) as value
  from (
    select severity, count(*)::int as count from open_bugs group by severity
  ) x
),
bug_age_counts as (
  select bucket, count(*)::int as count
  from (
    select case
      when age_days < 7 then '<7d'
      when age_days < 31 then '7–30d'
      when age_days < 91 then '31–90d'
      else '>90d'
    end as bucket
    from open_bugs
  ) b
  group by bucket
),
bug_age_json as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'bucket', b.bucket,
    'count', b.count,
    'pct', round(100.0 * b.count / nullif(t.open_bugs, 0), 1)
  ) order by case b.bucket when '<7d' then 1 when '7–30d' then 2 when '31–90d' then 3 else 4 end), '[]'::jsonb) as value
  from bug_age_counts b cross join bug_total t
),
bug_rca_json as (
  select coalesce(jsonb_agg(jsonb_build_object('root_cause', root_cause, 'count', count) order by count desc, root_cause nulls last), '[]'::jsonb) as value
  from (
    select root_cause, count(*)::int as count from open_bugs group by root_cause
  ) x
),
bug_module_json as (
  select coalesce(jsonb_agg(jsonb_build_object('module', module, 'count', count) order by count desc, module nulls last), '[]'::jsonb) as value
  from (
    select module, count(*)::int as count from open_bugs group by module
  ) x
),
trend_weeks as materialized (
  select week_start, week_end
  from v_backlog_trend
  order by week_start
),
trend_agg as (
  select w.week_start, w.week_end,
    count(*) filter (
      where b.created_at < w.week_start + interval '1 week'
        and (b.done_eff is null or b.done_eff >= w.week_start + interval '1 week')
    )::int as open_eod,
    count(*) filter (
      where b.created_at >= w.week_start and b.created_at < w.week_start + interval '1 week'
    )::int as created,
    count(*) filter (
      where b.done_eff is not null
        and b.done_eff >= w.week_start and b.done_eff < w.week_start + interval '1 week'
    )::int as resolved
  from trend_weeks w
  left join bugs b on true
  group by w.week_start, w.week_end
),
trend_with_net as (
  select t.*,
         t.created - t.resolved as net_movement,
         sum(t.created - t.resolved) over (
           order by t.week_start rows between 3 preceding and current row
         ) as trailing_4w_net
  from trend_agg t
),
trend_json as (
  select coalesce(jsonb_agg(to_jsonb(t) order by t.week_start), '[]'::jsonb) as value
  from trend_with_net t
),
qa_queue_json as (
  select coalesce(jsonb_agg(to_jsonb(q) order by q.days_in_queue desc nulls last, q.issue_key), '[]'::jsonb) as value
  from v_qa_queue q
  join filtered_issues i on i.issue_id = q.issue_id
),
flow_state_json as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'issue_key', issue_key,
    'summary', summary,
    'severity', severity,
    'status_name', status_name,
    'stale_calc_days', round(stale_calc_days::numeric, 1),
    'blocked_days', round(blocked_days::numeric, 1),
    'is_stale_blocked', is_stale_blocked,
    'created_at', created_at,
    'resolved_at', resolved_at,
    'module', module,
    'priority', priority,
    'assignee_name', assignee_name
  ) order by stale_calc_days desc nulls last, issue_key), '[]'::jsonb) as value
  from flow_rows
),
stage_json as (
  select coalesce(jsonb_agg(to_jsonb(s) order by s.sprint_start desc, s.sprint_id desc, s.median_hours desc, s.stage), '[]'::jsonb) as value
  from stage_summary s
),
metric_updates as (
  select jsonb_build_object(
    'code_review', jsonb_build_object(
      'value', (select median_hours from target_code_review),
      'unit', 'hours',
      'n', (select issues_in_stage from target_code_review),
      'denominator', (select issues_in_stage from target_code_review)
    ),
    'backlog_trajectory', jsonb_build_object(
      'value', (select trailing_4w_net from trend_with_net order by week_start desc limit 1),
      'unit', 'net',
      'n', (select open_eod from trend_with_net order by week_start desc limit 1),
      'denominator', (select open_eod from trend_with_net order by week_start desc limit 1)
    )
  ) as value
)
select jsonb_build_object(
  'stage_summary', (select value from stage_json),
  'flow_state', (select value from flow_state_json),
  'flow_counts', (select to_jsonb(f) from flow_counts f),
  'wip_by_status', (select value from wip_json),
  'bug_health', jsonb_build_object(
    'open_bugs', (select open_bugs from bug_total),
    'median_age_days', (select median_age_days from bug_total),
    'open_by_severity', (select value from bug_severity_json),
    'age_histogram', (select value from bug_age_json),
    'rca_distribution', (select value from bug_rca_json),
    'open_by_module', (select value from bug_module_json)
  ),
  'backlog_trend', (select value from trend_json),
  'qa_queue', (select value from qa_queue_json),
  'metric_updates', (select value from metric_updates)
);
$function$
