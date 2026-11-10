-- Restore previous canonical Engineering derive_issue definition.
CREATE OR REPLACE FUNCTION "02_engineering_schema".derive_issue(p_issue_ids bigint[])
 RETURNS TABLE(out_issue_id bigint, ok boolean)
 LANGUAGE plpgsql
 SET search_path TO '02_engineering_schema', 'public', 'pg_catalog'
AS $function$
begin
  insert into issues as i (issue_id, issue_key, project_key, summary, issue_type,
      status_name, status_category, is_done, priority, severity, module, sub_module,
      source, root_cause, added_to_backlog, team_id, team_name, story_points,
      assignee_id, assignee_name, reporter_id, creator_id, sprint_count, parent_id,
      labels, created_at, updated_at, start_date, due_date, resolved_at, extra)
  select
      r.issue_id,
      r.issue_key,
      r.payload#>>'{fields,project,key}',
      r.payload#>>'{fields,summary}',
      r.payload#>>'{fields,issuetype,name}',
      r.payload#>>'{fields,status,name}',
      r.payload#>>'{fields,statusCategory,name}',
      coalesce(r.payload#>>'{fields,statusCategory,name}' = 'Done', false),
      r.payload#>>'{fields,priority,name}',
      coalesce(
        case when jsonb_typeof(r.payload#>'{fields,customfield_10794}') = 'array'
             then r.payload#>>'{fields,customfield_10794,0}'
             else r.payload#>>'{fields,customfield_10794}' end,
        null),
      coalesce(
        case when jsonb_typeof(r.payload#>'{fields,customfield_10585}') = 'array'
             then r.payload#>>'{fields,customfield_10585,0}'
             else r.payload#>>'{fields,customfield_10585}' end, null),
      coalesce(
        case when jsonb_typeof(r.payload#>'{fields,customfield_10618}') = 'array'
             then btrim(r.payload#>>'{fields,customfield_10618,0}')
             else btrim(coalesce(r.payload#>>'{fields,customfield_10618}','')) end, null),
      coalesce(
        case when jsonb_typeof(r.payload#>'{fields,customfield_10795}') = 'array'
             then r.payload#>>'{fields,customfield_10795,0}'
             else r.payload#>>'{fields,customfield_10795}' end, null),
      coalesce(
        case when jsonb_typeof(r.payload#>'{fields,customfield_10796}') = 'array'
             then r.payload#>>'{fields,customfield_10796,0}'
             else r.payload#>>'{fields,customfield_10796}' end, null),
      coalesce(
        case when jsonb_typeof(r.payload#>'{fields,customfield_10504}') = 'array'
             then r.payload#>>'{fields,customfield_10504,0,value}'
             else r.payload#>>'{fields,customfield_10504,value}' end, null),
      r.payload#>>'{fields,customfield_10001,id}',
      r.payload#>>'{fields,customfield_10001,name}',
      (r.payload#>>'{fields,customfield_10016}')::numeric,
      r.payload#>>'{fields,assignee,accountId}',
      coalesce(r.payload#>>'{fields,assignee,displayName}', case
          when r.payload#>'{fields,assignee}' is not null then 'Former user' end),
      r.payload#>>'{fields,reporter,accountId}',
      r.payload#>>'{fields,creator,accountId}',
      case when jsonb_typeof(r.payload#>'{fields,customfield_10020}') = 'array'
           then jsonb_array_length(r.payload#>'{fields,customfield_10020}') else 0 end,
      case when (r.payload#>>'{fields,parent,id}') ~ '^\d+$'
           then (r.payload#>>'{fields,parent,id}')::bigint end,
      coalesce((select array_agg(x) from jsonb_array_elements_text(
                  _jsonb_array_or_empty(r.payload#>'{fields,labels}')) t(x)), '{}'),
      (r.payload#>>'{fields,created}')::timestamptz,
      (r.payload#>>'{fields,updated}')::timestamptz,
      nullif(r.payload#>>'{fields,customfield_10015}','')::date,
      nullif(r.payload#>>'{fields,duedate}','')::date,
      (r.payload#>>'{fields,resolutiondate}')::timestamptz,
      r.payload->'fields'
  from raw_issues r
  where r.issue_id = any(p_issue_ids) and r.deleted_at is null
  on conflict (issue_id) do update set
      issue_key = excluded.issue_key,
      summary = excluded.summary,
      issue_type = excluded.issue_type,
      status_name = excluded.status_name,
      status_category = excluded.status_category,
      is_done = excluded.is_done,
      priority = excluded.priority,
      severity = excluded.severity,
      module = excluded.module,
      sub_module = excluded.sub_module,
      source = excluded.source,
      root_cause = excluded.root_cause,
      added_to_backlog = excluded.added_to_backlog,
      team_id = excluded.team_id,
      team_name = excluded.team_name,
      story_points = excluded.story_points,
      assignee_id = excluded.assignee_id,
      assignee_name = excluded.assignee_name,
      reporter_id = excluded.reporter_id,
      creator_id = excluded.creator_id,
      sprint_count = excluded.sprint_count,
      parent_id = excluded.parent_id,
      labels = excluded.labels,
      created_at = excluded.created_at,
      updated_at = excluded.updated_at,
      start_date = excluded.start_date,
      due_date = excluded.due_date,
      resolved_at = excluded.resolved_at,
      extra = excluded.extra,
      synced_at = now();

  insert into sprints as s (id, name, state, start_date, end_date, complete_date, goal)
  select distinct (sp->>'id')::bigint, sp->>'name', sp->>'state',
         (sp->>'startDate')::timestamptz, (sp->>'endDate')::timestamptz,
         (sp->>'completeDate')::timestamptz, sp->>'goal'
  from raw_issues r
  cross join lateral jsonb_array_elements(
    _jsonb_array_or_empty(r.payload#>'{fields,customfield_10020}')
  ) sp
  where r.issue_id = any(p_issue_ids) and sp->>'id' is not null
  on conflict (id) do update set
      name = excluded.name, state = excluded.state,
      start_date = coalesce(excluded.start_date, s.start_date),
      end_date = coalesce(excluded.end_date, s.end_date),
      complete_date = coalesce(excluded.complete_date, s.complete_date),
      goal = coalesce(excluded.goal, s.goal),
      synced_at = now();

  update sprint_issues si set removed_at = now()
  where si.issue_id = any(p_issue_ids) and si.removed_at is null
    and not exists (
      select 1 from raw_issues r
      cross join lateral jsonb_array_elements(
        _jsonb_array_or_empty(r.payload#>'{fields,customfield_10020}')
      ) sp
      where r.issue_id = si.issue_id
        and (sp->>'id')::bigint = si.sprint_id);

  insert into sprint_issues (issue_id, sprint_id, added_at)
  select distinct r.issue_id, (sp->>'id')::bigint, now()
  from raw_issues r
  cross join lateral jsonb_array_elements(
    _jsonb_array_or_empty(r.payload#>'{fields,customfield_10020}')
  ) sp
  where r.issue_id = any(p_issue_ids) and sp->>'id' is not null
  on conflict (issue_id, sprint_id) do update set removed_at = null;

  delete from issue_field_values where issue_id = any(p_issue_ids);

  insert into issue_field_values (issue_id, field_id, value_ordinal, value)
  select r.issue_id, f.fid, t.ord, t.val
  from raw_issues r
  join (values
      ('customfield_10585'),('customfield_10618'),('customfield_10794'),
      ('customfield_10795'),('customfield_10796'),('customfield_10797'),
      ('customfield_10504'),('customfield_10001'),('customfield_10016'),
      ('customfield_10793'),('customfield_10017')
  ) as f(fid) on jsonb_typeof(r.payload #> array['fields', f.fid]) = 'array'
  cross join lateral jsonb_array_elements(
    _jsonb_array_or_empty(r.payload #> array['fields', f.fid])
  ) with ordinality as t(val, ord)
  where r.issue_id = any(p_issue_ids);

  insert into issue_field_values (issue_id, field_id, value_ordinal, value)
  select r.issue_id, f.fid, 0, r.payload #> array['fields', f.fid]
  from raw_issues r
  join (values
      ('customfield_10585'),('customfield_10618'),('customfield_10794'),
      ('customfield_10795'),('customfield_10796'),('customfield_10797'),
      ('customfield_10504'),('customfield_10001'),('customfield_10016'),
      ('customfield_10793'),('customfield_10017')
  ) as f(fid)
    on coalesce(jsonb_typeof(r.payload #> array['fields', f.fid]), 'null')
       not in ('array', 'null')
  where r.issue_id = any(p_issue_ids)
    and r.payload #> array['fields', f.fid] is not null;

  return query select r.issue_id, true from raw_issues r
  where r.issue_id = any(p_issue_ids);
end;
$function$

