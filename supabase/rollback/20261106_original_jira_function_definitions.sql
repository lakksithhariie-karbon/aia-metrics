-- ORIGINAL production Jira functions, captured before migration 2026-11-06.
-- For use ONLY after restoring schema name jira in a controlled rollback.
-- Code backup; no data is present. Do not run in forward migration.

-- jira._dashboard_filter_matches(text,text,text,text[],text[],text[])
CREATE OR REPLACE FUNCTION jira._dashboard_filter_matches(p_module text, p_severity text, p_assignee text, p_modules text[], p_severities text[], p_assignees text[])
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'jira', 'public', 'pg_catalog'
AS $function$
  select
    (p_modules is null or cardinality(p_modules) = 0
      or case
        when p_module is null then '__untagged__' = any(p_modules)
        else p_module = any(p_modules)
      end)
    and
    (p_severities is null or cardinality(p_severities) = 0
      or case
        when p_severity is null then 'Untagged' = any(p_severities)
        else p_severity = any(p_severities)
      end)
    and
    (p_assignees is null or cardinality(p_assignees) = 0
      or (p_assignee is not null and p_assignee = any(p_assignees)));
$function$;

-- jira._dashboard_filter_matches_submodule(text,text,text,text,text[],text[],text[],text[])
CREATE OR REPLACE FUNCTION jira._dashboard_filter_matches_submodule(p_module text, p_sub_module text, p_severity text, p_assignee text, p_modules text[], p_sub_modules text[], p_severities text[], p_assignees text[])
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select
    (p_modules is null or cardinality(p_modules) = 0
      or case
        when p_module is null then '__untagged__' = any(p_modules)
        else p_module = any(p_modules)
      end)
    and
    (p_sub_modules is null or cardinality(p_sub_modules) = 0
      or case
        when nullif(btrim(p_sub_module), '') is null then '__untagged__' = any(p_sub_modules)
        else nullif(btrim(p_sub_module), '') = any(p_sub_modules)
      end)
    and
    (p_severities is null or cardinality(p_severities) = 0
      or case
        when p_severity is null then 'Untagged' = any(p_severities)
        else p_severity = any(p_severities)
      end)
    and
    (p_assignees is null or cardinality(p_assignees) = 0
      or (p_assignee is not null and p_assignee = any(p_assignees)));
$function$;

-- jira._filter_assignee_matches(jsonb,text[])
CREATE OR REPLACE FUNCTION jira._filter_assignee_matches(payload jsonb, p_assignee text[])
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'jira', 'public', 'pg_catalog'
AS $function$
  select case
    when p_assignee is null or cardinality(p_assignee) = 0 then true
    else (payload->>'assignee_name') = any(p_assignee)
  end;
$function$;

-- jira._filter_cohort_field_present(jsonb,text)
CREATE OR REPLACE FUNCTION jira._filter_cohort_field_present(p_rows jsonb, p_field text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog'
AS $function$
  select exists (
    select 1
    from jsonb_array_elements(
      case
        when jsonb_typeof(coalesce(p_rows, '[]'::jsonb)) = 'array'
          then coalesce(p_rows, '[]'::jsonb)
        else '[]'::jsonb
      end
    ) as row_value(payload)
    where payload ? p_field
  );
$function$;

-- jira._filter_cohort_row_matches(jsonb,integer[],text,text[],text[],boolean,boolean,boolean,boolean)
CREATE OR REPLACE FUNCTION jira._filter_cohort_row_matches(p_payload jsonb, p_sprint_ids integer[], p_module text, p_severity text[], p_assignee text[], p_apply_sprint boolean, p_apply_module boolean, p_apply_severity boolean, p_apply_assignee boolean)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'jira', 'public', 'pg_catalog'
AS $function$
  select p_payload is not null
    and (
      not p_apply_sprint
      or (p_payload ? 'sprint_id'
          and _filter_sprint_matches(p_payload, p_sprint_ids))
    )
    and (
      not p_apply_module
      or (p_payload ? 'module'
          and _filter_module_matches(p_payload, p_module))
    )
    and (
      not p_apply_severity
      or (p_payload ? 'severity'
          and _filter_severity_matches(p_payload, p_severity))
    )
    and (
      not p_apply_assignee
      or (p_payload ? 'assignee_name'
          and _filter_assignee_matches(p_payload, p_assignee))
    );
$function$;

-- jira._filter_module_matches(jsonb,text)
CREATE OR REPLACE FUNCTION jira._filter_module_matches(payload jsonb, p_module text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'jira', 'public', 'pg_catalog'
AS $function$
  select case
    when p_module is null then true
    when p_module = '__untagged__' then (payload->>'module') is null
    else (payload->>'module') = p_module
  end;
$function$;

-- jira._filter_severity_matches(jsonb,text[])
CREATE OR REPLACE FUNCTION jira._filter_severity_matches(payload jsonb, p_severity text[])
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'jira', 'public', 'pg_catalog'
AS $function$
  select case
    when p_severity is null or cardinality(p_severity) = 0 then true
    when (payload->>'severity') is null then 'Untagged' = any(p_severity)
    else (payload->>'severity') = any(p_severity)
  end;
$function$;

-- jira._filter_sprint_matches(jsonb,integer[])
CREATE OR REPLACE FUNCTION jira._filter_sprint_matches(payload jsonb, p_sprint_ids integer[])
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'jira', 'public', 'pg_catalog'
AS $function$
  select case
    when p_sprint_ids is null or cardinality(p_sprint_ids) = 0 then true
    when (payload->>'sprint_id') is null then true
    else ((payload->>'sprint_id')::int = any(p_sprint_ids))
  end;
$function$;

-- jira._jsonb_array_or_empty(jsonb)
CREATE OR REPLACE FUNCTION jira._jsonb_array_or_empty(value jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'jira', 'public', 'pg_catalog'
AS $function$
  select case
    when jsonb_typeof(value) = 'array' then value
    else '[]'::jsonb
  end;
$function$;

-- jira.adf_to_text(jsonb)
CREATE OR REPLACE FUNCTION jira.adf_to_text(node jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'jira', 'public', 'pg_catalog'
AS $function$
  with recursive t(n, depth) as (
    select node, 0
    union all
    select c, depth + 1
    from t
    cross join lateral jsonb_array_elements(_jsonb_array_or_empty(t.n->'content')) c
  )
  select coalesce(string_agg(n->>'text', ' ' order by depth), '')
  from t where n ? 'text';
$function$;

-- jira.canonical_value(text,text)
CREATE OR REPLACE FUNCTION jira.canonical_value(p_field text, p_raw text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select case
    when p_field is null then null
    when btrim(coalesce(p_raw,'')) = '' then null
    else coalesce(
      (select canonical
         from jira.field_value_map
        where field_name = p_field
          and lower(raw_value) = lower(btrim(p_raw))
        order by case confidence
                   when 'exact' then 1
                   when 'variant' then 2
                   when 'manual' then 3
                   when 'review' then 4
                   else 4
                 end,
                 raw_value
        limit 1),
      'Other')
  end;
$function$;

-- jira.derive_issue(bigint[])
CREATE OR REPLACE FUNCTION jira.derive_issue(p_issue_ids bigint[])
 RETURNS TABLE(out_issue_id bigint, ok boolean)
 LANGUAGE plpgsql
 SET search_path TO 'jira', 'public', 'pg_catalog'
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
$function$;

-- jira.derive_issue_children(bigint[])
CREATE OR REPLACE FUNCTION jira.derive_issue_children(p_issue_ids bigint[])
 RETURNS TABLE(out_issue_id bigint, ok boolean)
 LANGUAGE plpgsql
 SET search_path TO 'jira', 'public', 'pg_catalog'
AS $function$
begin
  delete from comments where issue_id = any(p_issue_ids);
  insert into comments (id, issue_id, author_id, author_name, body, body_text, created, updated, jsd_public)
  select (c->>'id')::bigint, r.issue_id,
         c#>>'{author,accountId}', c#>>'{author,displayName}',
         c->'body', adf_to_text(c->'body'),
         (c->>'created')::timestamptz, (c->>'updated')::timestamptz,
         (c->>'jsdPublic')::boolean
  from raw_issues r
  cross join lateral jsonb_array_elements(
    _jsonb_array_or_empty(r.payload#>'{fields,comment,comments}')
  ) c
  where r.issue_id = any(p_issue_ids);

  delete from attachments_meta where issue_id = any(p_issue_ids);
  insert into attachments_meta (id, issue_id, filename, size_bytes, mime_type, author_id, author_name, created)
  select (a->>'id')::bigint, r.issue_id,
         a->>'filename', (a->>'size')::bigint, a->>'mimeType',
         a#>>'{author,accountId}', a#>>'{author,displayName}',
         (a->>'created')::timestamptz
  from raw_issues r
  cross join lateral jsonb_array_elements(
    _jsonb_array_or_empty(r.payload#>'{fields,attachment}')
  ) a
  where r.issue_id = any(p_issue_ids) and a->>'id' is not null;

  delete from worklogs where issue_id = any(p_issue_ids);
  insert into worklogs (id, issue_id, author_id, author_name, started, time_spent_seconds, time_spent, created, updated)
  select (w->>'id')::bigint, r.issue_id,
         w#>>'{author,accountId}', w#>>'{author,displayName}',
         (w->>'started')::timestamptz, (w->>'timeSpentSeconds')::int, w->>'timeSpent',
         (w->>'created')::timestamptz, (w->>'updated')::timestamptz
  from raw_issues r
  cross join lateral jsonb_array_elements(
    _jsonb_array_or_empty(r.payload#>'{fields,worklog,worklogs}')
  ) w
  where r.issue_id = any(p_issue_ids);

  delete from issue_links where issue_id = any(p_issue_ids);
  insert into issue_links (issue_id, link_type_id, link_type_name, direction, description, related_issue_id, related_issue_key)
  select r.issue_id,
         t.id, t.name, t.dirn, t.descr,
         (t.rel->>'id')::bigint, t.rel->>'key'
  from raw_issues r
  cross join lateral jsonb_array_elements(
    _jsonb_array_or_empty(r.payload#>'{fields,issuelinks}')
  ) l
  cross join lateral (
    select l#>>'{type,id}' as id, l#>>'{type,name}' as name,
           l#>>'{type,outward}' as descr, 'outward' as dirn,
           l->'outwardIssue' as rel
    where l ? 'outwardIssue'
    union all
    select l#>>'{type,id}', l#>>'{type,name}',
           l#>>'{type,inward}', 'inward', l->'inwardIssue'
    where l ? 'inwardIssue'
  ) t
  where r.issue_id = any(p_issue_ids) and t.rel->>'id' is not null
  on conflict (issue_id, related_issue_id, direction, link_type_id) do nothing;

  return query select r.issue_id, true from raw_issues r where r.issue_id = any(p_issue_ids);
end;
$function$;

-- jira.get_delivered_from_commitment(bigint,text[],text[],text[])
CREATE OR REPLACE FUNCTION jira.get_delivered_from_commitment(p_sprint_id bigint, p_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '20s'
AS $function$
with
target as (
  select ds.id, ds.name, ds.start_date
  from v_dashboard_sprints ds
  where ds.id = p_sprint_id
),
base as (
  select
    d.sprint_id,
    d.sprint_name,
    d.issue_id,
    d.issue_key,
    d.summary,
    d.issue_type,
    d.status_name,
    d.status_category,
    d.priority,
    d.severity,
    d.module,
    d.assignee_name,
    d.created_at,
    d.resolved_at,
    d.is_done,
    d.sprint_start,
    d.created_at <= d.sprint_start + interval '2 days' as was_committed
  from v_sprint_drilldown d
  where d.sprint_id = p_sprint_id
    -- Mirror the view's window join: an out-of-window sprint has no published
    -- comparison-table row, so the cohort must be empty rather than fabricated.
    and exists (select 1 from v_dashboard_sprints w where w.id = p_sprint_id)
    and d.is_direct_member
    and not d.is_subtask
    and _dashboard_filter_matches(
      d.module, d.severity, d.assignee_name,
      p_modules, p_severities, p_assignees
    )
),
live as (
  select b.*
  from base b
  left join (
    select h.issue_id, h.from_display, min(h.changed_at) as removed_at
    from issue_field_history h
    where h.field = 'Sprint'
    group by h.issue_id, h.from_display
  ) r
    on r.issue_id = b.issue_id
   and r.from_display = b.sprint_name
  where b.was_committed
    and (r.removed_at is null or r.removed_at > b.sprint_start + interval '2 days')
),
delivered as (
  select * from live where is_done
),
delivered_ordered as (
  select * from delivered
  order by resolved_at desc nulls last, created_at desc, issue_key
)
select jsonb_build_object(
  'title',
    'Delivered from commitment — ' ||
    coalesce((select name from target), 'Sprint ' || p_sprint_id::text),
  'value', (select count(*)::int from delivered),
  'unit', 'issues',
  'n', (select count(*)::int from delivered),
  'denominator', (select count(*)::int from live),
  'source', 'v_sprint_discipline',
  'definition',
    'commitment_completion_pct = committed_done / committed (proxy: created <= start+2d).',
  'definition_ref', 'docs/metric-definitions.md §Sprint discipline',
  'row_type', 'issue',
  'rows_shown', (select count(*)::int from delivered),
  'rows', coalesce(
    (select jsonb_agg(jsonb_build_object(
        'issue_key', o.issue_key,
        'summary', o.summary,
        'issue_type', o.issue_type,
        'status_name', o.status_name,
        'status_category', o.status_category,
        'priority', o.priority,
        'severity', o.severity,
        'module', o.module,
        'assignee_name', o.assignee_name,
        'created_at', o.created_at,
        'resolved_at', o.resolved_at,
        'sprint_id', o.sprint_id
     ) order by o.resolved_at desc nulls last, o.created_at desc, o.issue_key)
     from delivered_ordered o),
    '[]'::jsonb
  ),
  'issue_keys', coalesce(
    (select jsonb_agg(o.issue_key order by o.resolved_at desc nulls last, o.created_at desc, o.issue_key)
     from delivered_ordered o),
    '[]'::jsonb
  ),
  'source_note', 'Rows behind the comparison table''s committed_done value.'
);
$function$;

-- jira.get_delivered_from_commitment_submodule(bigint,text[],text[],text[],text[])
CREATE OR REPLACE FUNCTION jira.get_delivered_from_commitment_submodule(p_sprint_id bigint, p_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[], p_sub_modules text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '20s'
AS $function$
with
target as (
  select ds.id, ds.name, ds.start_date
  from v_dashboard_sprints ds
  where ds.id = p_sprint_id
),
base as (
  select
    d.sprint_id,
    d.sprint_name,
    d.issue_id,
    d.issue_key,
    d.summary,
    d.issue_type,
    d.status_name,
    d.status_category,
    d.priority,
    d.severity,
    d.module,
    d.sub_module,
    d.assignee_name,
    d.created_at,
    d.resolved_at,
    d.is_done,
    d.sprint_start,
    d.created_at <= d.sprint_start + interval '2 days' as was_committed
  from v_sprint_drilldown d
  where d.sprint_id = p_sprint_id
    -- Mirror the view's window join: an out-of-window sprint has no published
    -- comparison-table row, so the cohort must be empty rather than fabricated.
    and exists (select 1 from v_dashboard_sprints w where w.id = p_sprint_id)
    and d.is_direct_member
    and not d.is_subtask
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
live as (
  select b.*
  from base b
  left join (
    select h.issue_id, h.from_display, min(h.changed_at) as removed_at
    from issue_field_history h
    where h.field = 'Sprint'
    group by h.issue_id, h.from_display
  ) r
    on r.issue_id = b.issue_id
   and r.from_display = b.sprint_name
  where b.was_committed
    and (r.removed_at is null or r.removed_at > b.sprint_start + interval '2 days')
),
delivered as (
  select * from live where is_done
),
delivered_ordered as (
  select * from delivered
  order by resolved_at desc nulls last, created_at desc, issue_key
)
select jsonb_build_object(
  'title',
    'Delivered from commitment — ' ||
    coalesce((select name from target), 'Sprint ' || p_sprint_id::text),
  'value', (select count(*)::int from delivered),
  'unit', 'issues',
  'n', (select count(*)::int from delivered),
  'denominator', (select count(*)::int from live),
  'source', 'v_sprint_discipline',
  'definition',
    'commitment_completion_pct = committed_done / committed (proxy: created <= start+2d).',
  'definition_ref', 'docs/metric-definitions.md §Sprint discipline',
  'row_type', 'issue',
  'rows_shown', (select count(*)::int from delivered),
  'rows', coalesce(
    (select jsonb_agg(jsonb_build_object(
        'issue_key', o.issue_key,
        'summary', o.summary,
        'issue_type', o.issue_type,
        'status_name', o.status_name,
        'status_category', o.status_category,
        'priority', o.priority,
        'severity', o.severity,
        'module', o.module,
        'sub_module', o.sub_module,
        'assignee_name', o.assignee_name,
        'created_at', o.created_at,
        'resolved_at', o.resolved_at,
        'sprint_id', o.sprint_id
     ) order by o.resolved_at desc nulls last, o.created_at desc, o.issue_key)
     from delivered_ordered o),
    '[]'::jsonb
  ),
  'issue_keys', coalesce(
    (select jsonb_agg(o.issue_key order by o.resolved_at desc nulls last, o.created_at desc, o.issue_key)
     from delivered_ordered o),
    '[]'::jsonb
  ),
  'source_note', 'Rows behind the comparison table''s committed_done value.'
);
$function$;

-- jira.get_filtered_commitment_gap(bigint,text[],text[],text[])
CREATE OR REPLACE FUNCTION jira.get_filtered_commitment_gap(p_sprint_id bigint, p_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'jira', 'public', 'pg_catalog'
AS $function$
with target as (
  select id, name
  from jira.v_dashboard_sprints
  where id = p_sprint_id
),
scoped as (
  select s.*
  from jira.mv_sprint_commitment_scope s
  join target t on t.id = s.sprint_id
  where (
    coalesce(array_length(p_modules, 1), 0) = 0
    or (s.module is null and '__untagged__' = any(p_modules))
    or (s.module is not null and s.module = any(p_modules))
  )
  and (
    coalesce(array_length(p_severities, 1), 0) = 0
    or (s.severity is null and 'Untagged' = any(p_severities))
    or (s.severity is not null and s.severity = any(p_severities))
  )
  and (
    coalesce(array_length(p_assignees, 1), 0) = 0
    or (s.assignee_name is not null and s.assignee_name = any(p_assignees))
  )
),
pending as (
  select *
  from scoped
  where not is_done
)
select jsonb_build_object(
  'title',
    'Committed but not delivered — ' ||
    coalesce((select name from target), 'selected sprint'),
  'value', (select count(*)::int from pending),
  'unit', 'issues',
  'n', (select count(*)::int from pending),
  'denominator', (select count(*)::int from scoped),
  'source', 'mv_sprint_commitment_scope',
  'definition',
    'Direct, non-subtask sprint members created by the commitment cutoff and not done.',
  'definition_ref', 'docs/metric-definitions.md',
  'row_type', 'issue',
  'rows_shown', (select count(*)::int from pending),
  'rows', coalesce(
    (select jsonb_agg(to_jsonb(p) order by p.resolved_at desc nulls last, p.created_at desc, p.issue_key)
     from pending p),
    '[]'::jsonb
  ),
  'issue_keys', coalesce(
    (select jsonb_agg(p.issue_key order by p.resolved_at desc nulls last, p.created_at desc, p.issue_key)
     from pending p),
    '[]'::jsonb
  ),
  'source_note', 'Published committed scope remainder.'
);
$function$;

-- jira.get_filtered_commitment_gap_submodule(bigint,text[],text[],text[],text[])
CREATE OR REPLACE FUNCTION jira.get_filtered_commitment_gap_submodule(p_sprint_id bigint, p_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[], p_sub_modules text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'jira', 'public', 'pg_catalog'
AS $function$
with target as (
  select id, name
  from jira.v_dashboard_sprints
  where id = p_sprint_id
),
scoped as (
  select s.*
  from jira.mv_sprint_commitment_scope s
  join target t on t.id = s.sprint_id
  where (
    coalesce(array_length(p_modules, 1), 0) = 0
    or (s.module is null and '__untagged__' = any(p_modules))
    or (s.module is not null and s.module = any(p_modules))
  )
  and (
    coalesce(array_length(p_sub_modules, 1), 0) = 0
    or (nullif(btrim(s.sub_module), '') is null and '__untagged__' = any(p_sub_modules))
    or (nullif(btrim(s.sub_module), '') is not null and btrim(s.sub_module) = any(p_sub_modules))
  )
  and (
    coalesce(array_length(p_severities, 1), 0) = 0
    or (s.severity is null and 'Untagged' = any(p_severities))
    or (s.severity is not null and s.severity = any(p_severities))
  )
  and (
    coalesce(array_length(p_assignees, 1), 0) = 0
    or (s.assignee_name is not null and s.assignee_name = any(p_assignees))
  )
),
pending as (
  select *
  from scoped
  where not is_done
)
select jsonb_build_object(
  'title',
    'Committed but not delivered — ' ||
    coalesce((select name from target), 'selected sprint'),
  'value', (select count(*)::int from pending),
  'unit', 'issues',
  'n', (select count(*)::int from pending),
  'denominator', (select count(*)::int from scoped),
  'source', 'mv_sprint_commitment_scope',
  'definition',
    'Direct, non-subtask sprint members created by the commitment cutoff and not done.',
  'definition_ref', 'docs/metric-definitions.md',
  'row_type', 'issue',
  'rows_shown', (select count(*)::int from pending),
  'rows', coalesce(
    (select jsonb_agg(to_jsonb(p) order by p.resolved_at desc nulls last, p.created_at desc, p.issue_key)
     from pending p),
    '[]'::jsonb
  ),
  'issue_keys', coalesce(
    (select jsonb_agg(p.issue_key order by p.resolved_at desc nulls last, p.created_at desc, p.issue_key)
     from pending p),
    '[]'::jsonb
  ),
  'source_note', 'Published committed scope remainder.'
);
$function$;

-- jira.get_filtered_dashboard_core(bigint,text[],text[],text[])
CREATE OR REPLACE FUNCTION jira.get_filtered_dashboard_core(p_sprint_id bigint DEFAULT NULL::bigint, p_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '20s'
AS $function$
declare
  result jsonb;
  sprint_row jsonb;
  summary_row jsonb;
  throughput_row jsonb;
  cohort_key text;
begin
  result := jira.get_filtered_dashboard_core_025_base(
    p_sprint_id, p_modules, p_severities, p_assignees
  );

  -- A selected sprint with no matching issues is still a real sprint. Keep it
  -- in the option and discipline arrays so the filter control can display its
  -- name and dates and the dashboard can show a published empty state.
  if p_sprint_id is not null then
    select jsonb_build_object(
      'sprint_id', ds.id,
      'sprint_name', ds.name,
      'state', ds.state,
      'start_date', ds.start_date,
      'end_date', ds.end_date,
      'scope_now', 0,
      'committed', 0,
      'committed_done', 0,
      'commitment_completion_pct', null,
      'added_mid_sprint', 0,
      'mid_sprint_add_pct', null,
      'done_now', 0,
      'scope_completion_pct', null,
      'carried_to_next', 0
    )
    into sprint_row
    from jira.v_dashboard_sprints ds
    where ds.id = p_sprint_id;

    select jsonb_build_object(
      'sprint_id', ds.id,
      'sprint_name', ds.name,
      'state', ds.state,
      'start_date', ds.start_date,
      'end_date', ds.end_date,
      'direct_issues', 0,
      'all_issues', 0,
      'done_issues', 0,
      'completion_pct', null,
      'open_bugs', 0,
      'done_bugs', 0,
      'open_highest', 0,
      'contributors', 0,
      'open_l1', 0,
      'done_points', 0,
      'total_points', 0,
      'added_after_start', 0,
      'goal', coalesce(s.goal, '')
    )
    into summary_row
    from jira.v_dashboard_sprints ds
    left join jira.sprints s on s.id = ds.id
    where ds.id = p_sprint_id;

    select jsonb_build_object(
      'sprint_id', ds.id,
      'sprint_name', ds.name,
      'sprint_start', ds.start_date,
      'sprint_complete', coalesce(s.complete_date, ds.end_date),
      'throughput', 0,
      'first_done_after_start', 0
    )
    into throughput_row
    from jira.v_dashboard_sprints ds
    left join jira.sprints s on s.id = ds.id
    where ds.id = p_sprint_id;

    if sprint_row is not null then
      if not exists (
        select 1
        from jsonb_array_elements(coalesce(result -> 'sprints', '[]'::jsonb)) item
        where item ->> 'sprint_id' = p_sprint_id::text
      ) then
        result := jsonb_set(result, '{sprints}', jsonb_build_array(sprint_row), true);
      end if;

      if not exists (
        select 1
        from jsonb_array_elements(coalesce(result -> 'sprint_discipline', '[]'::jsonb)) item
        where item ->> 'sprint_id' = p_sprint_id::text
      ) then
        result := jsonb_set(result, '{sprint_discipline}', jsonb_build_array(sprint_row), true);
      end if;
    end if;

    if summary_row is not null and not exists (
      select 1
      from jsonb_array_elements(coalesce(result -> 'sprint_summary', '[]'::jsonb)) item
      where item ->> 'sprint_id' = p_sprint_id::text
    ) then
      result := jsonb_set(result, '{sprint_summary}', jsonb_build_array(summary_row), true);
    end if;

    if throughput_row is not null and not exists (
      select 1
      from jsonb_array_elements(coalesce(result -> 'sprint_throughput', '[]'::jsonb)) item
      where item ->> 'sprint_id' = p_sprint_id::text
    ) then
      result := jsonb_set(result, '{sprint_throughput}', jsonb_build_array(throughput_row), true);
    end if;
  end if;

  -- A null filtered median is meaningful.  Do not let the 025 envelope's
  -- published fallback value make an empty filtered population look measured.
  foreach cohort_key in array array['cycle_org', 'cycle_s45'] loop
    if coalesce((result -> 'metric_cohorts' -> cohort_key ->> 'n')::bigint, -1) = 0 then
      result := jsonb_set(
        result,
        array['metric_cohorts', cohort_key, 'value'],
        'null'::jsonb,
        true
      );
    end if;
  end loop;

  return result;
end;
$function$;

-- jira.get_filtered_dashboard_core_025_base(bigint,text[],text[],text[])
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

-- jira.get_filtered_dashboard_core_025_base_submodule(bigint,text[],text[],text[],text[])
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

-- jira.get_filtered_dashboard_core_submodule(bigint,text[],text[],text[],text[])
CREATE OR REPLACE FUNCTION jira.get_filtered_dashboard_core_submodule(p_sprint_id bigint DEFAULT NULL::bigint, p_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[], p_sub_modules text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '20s'
AS $function$
declare
  result jsonb;
  sprint_row jsonb;
  summary_row jsonb;
  throughput_row jsonb;
  cohort_key text;
begin
  result := jira.get_filtered_dashboard_core_025_base_submodule(p_sprint_id, p_modules, p_severities, p_assignees, p_sub_modules);

  -- A selected sprint with no matching issues is still a real sprint. Keep it
  -- in the option and discipline arrays so the filter control can display its
  -- name and dates and the dashboard can show a published empty state.
  if p_sprint_id is not null then
    select jsonb_build_object(
      'sprint_id', ds.id,
      'sprint_name', ds.name,
      'state', ds.state,
      'start_date', ds.start_date,
      'end_date', ds.end_date,
      'scope_now', 0,
      'committed', 0,
      'committed_done', 0,
      'commitment_completion_pct', null,
      'added_mid_sprint', 0,
      'mid_sprint_add_pct', null,
      'done_now', 0,
      'scope_completion_pct', null,
      'carried_to_next', 0
    )
    into sprint_row
    from jira.v_dashboard_sprints ds
    where ds.id = p_sprint_id;

    select jsonb_build_object(
      'sprint_id', ds.id,
      'sprint_name', ds.name,
      'state', ds.state,
      'start_date', ds.start_date,
      'end_date', ds.end_date,
      'direct_issues', 0,
      'all_issues', 0,
      'done_issues', 0,
      'completion_pct', null,
      'open_bugs', 0,
      'done_bugs', 0,
      'open_highest', 0,
      'contributors', 0,
      'open_l1', 0,
      'done_points', 0,
      'total_points', 0,
      'added_after_start', 0,
      'goal', coalesce(s.goal, '')
    )
    into summary_row
    from jira.v_dashboard_sprints ds
    left join jira.sprints s on s.id = ds.id
    where ds.id = p_sprint_id;

    select jsonb_build_object(
      'sprint_id', ds.id,
      'sprint_name', ds.name,
      'sprint_start', ds.start_date,
      'sprint_complete', coalesce(s.complete_date, ds.end_date),
      'throughput', 0,
      'first_done_after_start', 0
    )
    into throughput_row
    from jira.v_dashboard_sprints ds
    left join jira.sprints s on s.id = ds.id
    where ds.id = p_sprint_id;

    if sprint_row is not null then
      if not exists (
        select 1
        from jsonb_array_elements(coalesce(result -> 'sprints', '[]'::jsonb)) item
        where item ->> 'sprint_id' = p_sprint_id::text
      ) then
        result := jsonb_set(result, '{sprints}', jsonb_build_array(sprint_row), true);
      end if;

      if not exists (
        select 1
        from jsonb_array_elements(coalesce(result -> 'sprint_discipline', '[]'::jsonb)) item
        where item ->> 'sprint_id' = p_sprint_id::text
      ) then
        result := jsonb_set(result, '{sprint_discipline}', jsonb_build_array(sprint_row), true);
      end if;
    end if;

    if summary_row is not null and not exists (
      select 1
      from jsonb_array_elements(coalesce(result -> 'sprint_summary', '[]'::jsonb)) item
      where item ->> 'sprint_id' = p_sprint_id::text
    ) then
      result := jsonb_set(result, '{sprint_summary}', jsonb_build_array(summary_row), true);
    end if;

    if throughput_row is not null and not exists (
      select 1
      from jsonb_array_elements(coalesce(result -> 'sprint_throughput', '[]'::jsonb)) item
      where item ->> 'sprint_id' = p_sprint_id::text
    ) then
      result := jsonb_set(result, '{sprint_throughput}', jsonb_build_array(throughput_row), true);
    end if;
  end if;

  -- A null filtered median is meaningful.  Do not let the 025 envelope's
  -- published fallback value make an empty filtered population look measured.
  foreach cohort_key in array array['cycle_org', 'cycle_s45'] loop
    if coalesce((result -> 'metric_cohorts' -> cohort_key ->> 'n')::bigint, -1) = 0 then
      result := jsonb_set(
        result,
        array['metric_cohorts', cohort_key, 'value'],
        'null'::jsonb,
        true
      );
    end if;
  end loop;

  return result;
end;
$function$;

-- jira.get_filtered_dashboard_flow(bigint,text[],text[],text[])
CREATE OR REPLACE FUNCTION jira.get_filtered_dashboard_flow(p_sprint_id bigint DEFAULT NULL::bigint, p_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '8s'
AS $function$
with
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
           sd.module, sd.severity, sd.assignee_name
    from v_sprint_drilldown sd
    join window_sprints ws on ws.sprint_id = sd.sprint_id
  ) d
  join stage_per_issue sp on sp.issue_id = d.issue_id
  where d.is_direct_member and not d.is_subtask
    and (p_sprint_id is null or d.sprint_id = p_sprint_id)
    and _dashboard_filter_matches(
      d.module, d.severity, d.assignee_name,
      p_modules, p_severities, p_assignees
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
         extract(epoch from fs.stale_calc_days) / 86400.0 as stale_calc_days,
         extract(epoch from fs.blocked_days) / 86400.0 as blocked_days,
         fs.is_stale_blocked, fs.is_open, fs.is_stale, fs.is_blocked,
         i.issue_type, i.priority, i.assignee_name, i.created_at,
         i.resolved_at, i.module
  from v_issue_flow_state fs
  join filtered_issues i on i.issue_id = fs.issue_id
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
$function$;

-- jira.get_filtered_dashboard_flow_submodule(bigint,text[],text[],text[],text[])
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
$function$;

-- jira.get_filtered_dashboard_quality(bigint,text[],text[],text[])
CREATE OR REPLACE FUNCTION jira.get_filtered_dashboard_quality(p_sprint_id bigint DEFAULT NULL::bigint, p_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '20s'
AS $function$
declare
  result jsonb;
  resolution_medians jsonb;
begin
  result := jira.get_filtered_dashboard_quality_025_base(
    p_sprint_id, p_modules, p_severities, p_assignees
  );

  -- Publish the same two rows as v_resolution_medians, but within the active
  -- dashboard filter. The values remain database-owned; React only formats
  -- them. A zero-row population publishes median_value null and rows_used 0.
  with filtered_issues as materialized (
    select
      i.issue_id,
      i.issue_key,
      i.created_at,
      i.resolved_at,
      i.issue_type,
      i.module,
      i.severity,
      i.assignee_name,
      i.status_name,
      i.status_category,
      i.is_done
    from jira.v_issue_normalized i
    where i.project_key = 'SPEND'
      and jira._dashboard_filter_matches(
        i.module,
        i.severity,
        i.assignee_name,
        p_modules,
        p_severities,
        p_assignees
      )
      and (
        p_sprint_id is null
        or exists (
          select 1
          from jira.sprint_issues si
          join jira.v_dashboard_sprints ds on ds.id = si.sprint_id
          where si.issue_id = i.issue_id
            and si.sprint_id = p_sprint_id
            and si.removed_at is null
        )
      )
  ),
  bug_stat as (
    select
      round(percentile_cont(0.5) within group (
        order by extract(epoch from (resolved_at - created_at)) / 86400.0
      )::numeric, 2) as median_value,
      count(*)::int as rows_used
    from filtered_issues
    where issue_type = 'Bug'
      and resolved_at is not null
  ),
  turnaround_rows as materialized (
    select (entry ->> 'turnaround_hours')::numeric as turnaround_hours
    from jira.metric_cohorts mc
    cross join lateral jsonb_array_elements(
      case
        when jsonb_typeof(coalesce(mc.rows, '[]'::jsonb)) = 'array'
          then coalesce(mc.rows, '[]'::jsonb)
        else '[]'::jsonb
      end
    ) entry
    join filtered_issues i on i.issue_key = entry ->> 'issue_key'
    where mc.key = 'qa_turnaround'
      and entry ->> 'turnaround_hours' is not null
  ),
  turnaround_stat as (
    select
      round(percentile_cont(0.5) within group (order by turnaround_hours)::numeric, 2) as median_value,
      count(*)::int as rows_used
    from turnaround_rows
  ),
  excluded_open as (
    select count(*)::int as count
    from filtered_issues
    where status_name ilike 'uat%'
      and is_done = false
      and status_category <> 'Done'
  ),
  rows_for_json as (
    select
      'bug_resolution'::text as metric,
      b.median_value,
      'days'::text as unit,
      b.rows_used,
      null::int as excluded_open
    from bug_stat b
    union all
    select
      'qa_turnaround'::text as metric,
      t.median_value,
      'hours'::text as unit,
      t.rows_used,
      e.count as excluded_open
    from turnaround_stat t
    cross join excluded_open e
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'metric', metric,
    'median_value', median_value,
    'unit', unit,
    'rows_used', rows_used,
    'excluded_open', excluded_open,
    'computed_at', now()
  ) order by metric), '[]'::jsonb)
  into resolution_medians
  from rows_for_json;

  return result || jsonb_build_object('resolution_medians', resolution_medians);
end;
$function$;

-- jira.get_filtered_dashboard_quality_025_base(bigint,text[],text[],text[])
CREATE OR REPLACE FUNCTION jira.get_filtered_dashboard_quality_025_base(p_sprint_id bigint DEFAULT NULL::bigint, p_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '20s'
AS $function$
with
window_sprints as (
  select ds.id::bigint as sprint_id
  from v_dashboard_sprints ds
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
qa_rows as materialized (
  select q.issue_id, q.issue_key, q.signoff_cycles, q.rejected_cycles,
         q.other_cycles, q.rejection_pct,
         i.summary, i.severity, i.status_name, i.priority, i.assignee_name,
         i.created_at, i.resolved_at, i.module
  from v_qa_rejection q
  join filtered_issues i on i.issue_id = q.issue_id
),
qa_display_rows as materialized (
  select * from qa_rows where rejected_cycles > 0
),
qa_org_base as (
  select coalesce(sum(signoff_cycles), 0)::numeric as signoff_cycles,
         coalesce(sum(rejected_cycles), 0)::numeric as rejected_cycles
  from qa_rows
),
qa_org_calc as (
  select signoff_cycles, rejected_cycles,
         signoff_cycles + rejected_cycles as denominator,
         rejected_cycles / nullif(signoff_cycles + rejected_cycles, 0) as proportion,
         3.841458820694124::numeric as z2
  from qa_org_base
),
qa_org_json as (
  select jsonb_build_object(
    'denominator', denominator,
    'signoff_cycles', signoff_cycles,
    'rejected_cycles', rejected_cycles,
    'rejection_pct', round(100.0 * proportion, 2),
    'wilson_lo', case when denominator = 0 then null else round(100.0 * (
      (proportion + z2 / (2 * denominator))
      - 1.959964 * sqrt(((proportion * (1 - proportion)) + z2 / (4 * denominator)) / denominator)
        / (1 + z2 / denominator)
    ), 2) end,
    'wilson_hi', case when denominator = 0 then null else round(100.0 * (
      (proportion + z2 / (2 * denominator))
      + 1.959964 * sqrt(((proportion * (1 - proportion)) + z2 / (4 * denominator)) / denominator)
        / (1 + z2 / denominator)
    ), 2) end
  ) as value
  from qa_org_calc
),
qa_rows_json as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'issue_id', issue_id,
    'issue_key', issue_key,
    'summary', summary,
    'severity', severity,
    'status_name', status_name,
    'priority', priority,
    'assignee_name', assignee_name,
    'created_at', created_at,
    'resolved_at', resolved_at,
    'module', module,
    'signoff_cycles', signoff_cycles,
    'rejected_cycles', rejected_cycles,
    'other_cycles', other_cycles,
    'rejection_pct', rejection_pct
  ) order by rejected_cycles desc, issue_key), '[]'::jsonb) as value
  from qa_display_rows
),
cohort_rows as materialized (
  select e.payload
  from metric_cohorts mc
  cross join lateral jsonb_array_elements(
    case when jsonb_typeof(coalesce(mc.rows, '[]'::jsonb)) = 'array'
      then coalesce(mc.rows, '[]'::jsonb) else '[]'::jsonb end
  ) e(payload)
  where mc.key = 'qa_turnaround'
),
turnaround_rows as materialized (
  select (e.payload ->> 'turnaround_hours')::numeric as turnaround_hours
  from cohort_rows e
  join filtered_issues i on i.issue_key = e.payload ->> 'issue_key'
  where e.payload ->> 'turnaround_hours' is not null
),
turnaround_stat as (
  select percentile_cont(0.5) within group (order by turnaround_hours) as median_hours,
         count(*)::int as n
  from turnaround_rows
),
resolution_rows as materialized (
  select extract(epoch from (i.resolved_at - i.created_at)) / 86400.0 as resolution_days
  from filtered_issues i
  where i.issue_type = 'Bug' and i.resolved_at is not null
),
resolution_stat as (
  select percentile_cont(0.5) within group (order by resolution_days) as median_days,
         count(*)::int as n
  from resolution_rows
),
published_quality as materialized (
  select metric, median_value, unit, rows_used
  from v_resolution_medians
),
status_events as materialized (
  select h.issue_id, h.changed_at,
         coalesce(s.category, 'unknown') as to_cat,
         lag(coalesce(s.category, 'unknown')) over (
           partition by h.issue_id order by h.changed_at, h.itemordinal
         ) as from_cat
  from issue_field_history h
  join filtered_issues i on i.issue_id = h.issue_id
  left join statuses s on lower(s.name) = lower(h.to_display)
  where h.field = 'status'
),
reopen_ids as (
  select distinct issue_id
  from status_events
  where from_cat = 'Done' and to_cat <> 'Done'
),
reopen_months as (
  select date_trunc('month', changed_at) as month,
         count(distinct issue_id) filter (where from_cat = 'Done' and to_cat <> 'Done')::int as reopened_issues,
         count(*) filter (where from_cat = 'Done' and to_cat <> 'Done')::int as reopened_events,
         count(distinct issue_id) filter (where to_cat = 'Done')::int as closed_issues,
         count(distinct issue_id) filter (
           where to_cat = 'Done' and issue_id in (select issue_id from reopen_ids)
         )::int as reopened_of_those
  from status_events
  group by date_trunc('month', changed_at)
),
org_reopen_json as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'month', month,
    'reopened_issues', reopened_issues,
    'closed_issues', closed_issues,
    'reopen_pct', round(100.0 * reopened_of_those / nullif(closed_issues, 0), 1),
    'reopened_events', reopened_events
  ) order by month), '[]'::jsonb) as value
  from reopen_months
),
reopen_latest as (
  select * from reopen_months order by month desc limit 1
),
field_base as (
  select date_trunc('quarter', i.created_at) as quarter,
         false as is_total,
         count(*)::int as bugs_total,
         count(*) filter (where i.module is not null)::int as with_module,
         count(*) filter (where i.severity is not null)::int as with_severity,
         count(*) filter (where i.source is not null)::int as with_source,
         count(*) filter (where i.severity in ('L1','L2'))::int as l1l2_total,
         count(*) filter (where i.severity in ('L1','L2') and i.root_cause is not null)::int as l1l2_with_root_cause,
         count(*) filter (where i.severity = 'L1' and i.priority = 'Highest')::int as l1_mapped_highest,
         count(*) filter (where i.severity = 'L2' and i.priority = 'High')::int as l2_mapped_high,
         count(*) filter (where i.team_id is not null)::int as with_team
  from filtered_issues i
  where i.issue_type = 'Bug'
  group by date_trunc('quarter', i.created_at)
),
field_total as (
  select to_timestamp(0) as quarter, true as is_total,
         count(*)::int as bugs_total,
         count(*) filter (where i.module is not null)::int as with_module,
         count(*) filter (where i.severity is not null)::int as with_severity,
         count(*) filter (where i.source is not null)::int as with_source,
         count(*) filter (where i.severity in ('L1','L2'))::int as l1l2_total,
         count(*) filter (where i.severity in ('L1','L2') and i.root_cause is not null)::int as l1l2_with_root_cause,
         count(*) filter (where i.severity = 'L1' and i.priority = 'Highest')::int as l1_mapped_highest,
         count(*) filter (where i.severity = 'L2' and i.priority = 'High')::int as l2_mapped_high,
         count(*) filter (where i.team_id is not null)::int as with_team
  from filtered_issues i
  where i.issue_type = 'Bug'
),
field_json as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'quarter', quarter,
    'bugs_total', bugs_total,
    'with_module', with_module,
    'with_severity', with_severity,
    'with_source', with_source,
    'l1l2_total', l1l2_total,
    'l1l2_with_root_cause', l1l2_with_root_cause,
    'l1_mapped_highest', l1_mapped_highest,
    'l2_mapped_high', l2_mapped_high,
    'is_total', is_total,
    'module_coverage_pct', round(100.0 * with_module / nullif(bugs_total, 0), 1),
    'severity_coverage_pct', round(100.0 * with_severity / nullif(bugs_total, 0), 1),
    'source_coverage_pct', round(100.0 * with_source / nullif(bugs_total, 0), 1),
    'rca_coverage_pct', round(100.0 * l1l2_with_root_cause / nullif(l1l2_total, 0), 1),
    'l1_highest_pct', round(100.0 * l1_mapped_highest / nullif(l1l2_total, 0), 1),
    'l2_high_pct', round(100.0 * l2_mapped_high / nullif(l1l2_total, 0), 1),
    'with_team', with_team,
    'team_coverage_pct', round(100.0 * with_team / nullif(bugs_total, 0), 1)
  ) order by is_total, quarter), '[]'::jsonb) as value
  from (select * from field_base union all select * from field_total) h
  where h.bugs_total > 0
),
engineer_base as (
  select i.assignee_id, i.assignee_name,
         count(*)::int as bugs_touched,
         count(*) filter (where coalesce(ct.reopen_count, 0) > 0)::int as reopened,
         round(100.0 * count(*) filter (where coalesce(ct.reopen_count, 0) > 0) / nullif(count(*), 0), 1) as reopen_pct,
         count(*) filter (where i.root_cause is null and i.is_done and i.severity in ('L1','L2'))::int as closed_l1l2_without_rca,
         round(avg(extract(epoch from (ct.done_at - i.created_at)) / 86400.0) filter (where ct.done_at is not null)::numeric, 1) as avg_lead_time_days
  from filtered_issues i
  left join v_issue_cycle_times ct on ct.issue_id = i.issue_id
  where i.assignee_id is not null
  group by i.assignee_id, i.assignee_name
),
engineer_json as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'assignee_id', b.assignee_id,
    'assignee_name', b.assignee_name,
    'bugs_touched', b.bugs_touched,
    'reopened', b.reopened,
    'reopen_pct', b.reopen_pct,
    'closed_l1l2_without_rca', b.closed_l1l2_without_rca,
    'avg_lead_time_days', b.avg_lead_time_days
  ) order by b.assignee_name), '[]'::jsonb) as value
  from engineer_base b
),
bug_sla_json as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'issue_key', b.issue_key,
    'summary', b.summary,
    'severity', b.severity,
    'priority', b.priority,
    'status_name', b.status_name,
    'eta_deviation_days', b.eta_deviation_days,
    'response_hours_ct', b.response_hours_ct,
    'assignee_name', b.assignee_name,
    'created_at', b.created_at
  ) order by b.issue_key), '[]'::jsonb) as value
  from v_bug_sla b
  join filtered_issues i on i.issue_key = b.issue_key
),
updates as (
  select jsonb_build_object(
    'reopen_latest', jsonb_build_object(
      'value', (select round(100.0 * reopened_of_those / nullif(closed_issues, 0), 1) from reopen_latest),
      'unit', 'pct',
      'n', (select reopened_of_those from reopen_latest),
      'denominator', (select closed_issues from reopen_latest)
    ),
    'qa_rejection', jsonb_build_object(
      'value', (select round(100.0 * proportion, 2) from qa_org_calc),
      'unit', 'pct',
      'n', (select rejected_cycles from qa_org_calc),
      'denominator', (select denominator from qa_org_calc)
    ),
    'bug_resolution', jsonb_build_object(
      'value', case when p_sprint_id is null
        and cardinality(coalesce(p_modules, '{}'::text[])) = 0
        and cardinality(coalesce(p_severities, '{}'::text[])) = 0
        and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
        then (select median_value from published_quality where metric = 'bug_resolution')
        else round((select median_days from resolution_stat)::numeric, 2) end,
      'unit', 'days',
      'n', case when p_sprint_id is null
        and cardinality(coalesce(p_modules, '{}'::text[])) = 0
        and cardinality(coalesce(p_severities, '{}'::text[])) = 0
        and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
        then (select rows_used from published_quality where metric = 'bug_resolution')
        else (select n from resolution_stat) end,
      'denominator', case when p_sprint_id is null
        and cardinality(coalesce(p_modules, '{}'::text[])) = 0
        and cardinality(coalesce(p_severities, '{}'::text[])) = 0
        and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
        then (select rows_used from published_quality where metric = 'bug_resolution')
        else (select n from resolution_stat) end
    ),
    'qa_turnaround', jsonb_build_object(
      'value', case when p_sprint_id is null
        and cardinality(coalesce(p_modules, '{}'::text[])) = 0
        and cardinality(coalesce(p_severities, '{}'::text[])) = 0
        and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
        then (select median_value from published_quality where metric = 'qa_turnaround')
        else round((select median_hours from turnaround_stat)::numeric, 2) end,
      'unit', 'hours',
      'n', case when p_sprint_id is null
        and cardinality(coalesce(p_modules, '{}'::text[])) = 0
        and cardinality(coalesce(p_severities, '{}'::text[])) = 0
        and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
        then (select rows_used from published_quality where metric = 'qa_turnaround')
        else (select n from turnaround_stat) end,
      'denominator', case when p_sprint_id is null
        and cardinality(coalesce(p_modules, '{}'::text[])) = 0
        and cardinality(coalesce(p_severities, '{}'::text[])) = 0
        and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
        then (select rows_used from published_quality where metric = 'qa_turnaround')
        else (select n from turnaround_stat) end
    )
  ) as value
)
select jsonb_build_object(
  'bug_sla', (select value from bug_sla_json),
  'org_reopen', (select value from org_reopen_json),
  'qa_rejection', (select value from qa_rows_json),
  'qa_rejection_org', (select value from qa_org_json),
  'field_hygiene', (select value from field_json),
  'field_hygiene_org', coalesce((
    select value from jsonb_array_elements((select value from field_json)) e(value)
    where (e.value ->> 'is_total')::boolean
    limit 1
  ), null),
  'engineer_quality', (select value from engineer_json),
  'metric_updates', (select value from updates)
);
$function$;

-- jira.get_filtered_dashboard_quality_025_base_submodule(bigint,text[],text[],text[],text[])
CREATE OR REPLACE FUNCTION jira.get_filtered_dashboard_quality_025_base_submodule(p_sprint_id bigint DEFAULT NULL::bigint, p_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[], p_sub_modules text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '20s'
AS $function$
with
window_sprints as (
  select ds.id::bigint as sprint_id
  from v_dashboard_sprints ds
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
qa_rows as materialized (
  select q.issue_id, q.issue_key, q.signoff_cycles, q.rejected_cycles,
         q.other_cycles, q.rejection_pct,
         i.summary, i.severity, i.status_name, i.priority, i.assignee_name,
         i.created_at, i.resolved_at, i.module
  from v_qa_rejection q
  join filtered_issues i on i.issue_id = q.issue_id
),
qa_display_rows as materialized (
  select * from qa_rows where rejected_cycles > 0
),
qa_org_base as (
  select coalesce(sum(signoff_cycles), 0)::numeric as signoff_cycles,
         coalesce(sum(rejected_cycles), 0)::numeric as rejected_cycles
  from qa_rows
),
qa_org_calc as (
  select signoff_cycles, rejected_cycles,
         signoff_cycles + rejected_cycles as denominator,
         rejected_cycles / nullif(signoff_cycles + rejected_cycles, 0) as proportion,
         3.841458820694124::numeric as z2
  from qa_org_base
),
qa_org_json as (
  select jsonb_build_object(
    'denominator', denominator,
    'signoff_cycles', signoff_cycles,
    'rejected_cycles', rejected_cycles,
    'rejection_pct', round(100.0 * proportion, 2),
    'wilson_lo', case when denominator = 0 then null else round(100.0 * (
      (proportion + z2 / (2 * denominator))
      - 1.959964 * sqrt(((proportion * (1 - proportion)) + z2 / (4 * denominator)) / denominator)
        / (1 + z2 / denominator)
    ), 2) end,
    'wilson_hi', case when denominator = 0 then null else round(100.0 * (
      (proportion + z2 / (2 * denominator))
      + 1.959964 * sqrt(((proportion * (1 - proportion)) + z2 / (4 * denominator)) / denominator)
        / (1 + z2 / denominator)
    ), 2) end
  ) as value
  from qa_org_calc
),
qa_rows_json as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'issue_id', issue_id,
    'issue_key', issue_key,
    'summary', summary,
    'severity', severity,
    'status_name', status_name,
    'priority', priority,
    'assignee_name', assignee_name,
    'created_at', created_at,
    'resolved_at', resolved_at,
    'module', module,
    'signoff_cycles', signoff_cycles,
    'rejected_cycles', rejected_cycles,
    'other_cycles', other_cycles,
    'rejection_pct', rejection_pct
  ) order by rejected_cycles desc, issue_key), '[]'::jsonb) as value
  from qa_display_rows
),
cohort_rows as materialized (
  select e.payload
  from metric_cohorts mc
  cross join lateral jsonb_array_elements(
    case when jsonb_typeof(coalesce(mc.rows, '[]'::jsonb)) = 'array'
      then coalesce(mc.rows, '[]'::jsonb) else '[]'::jsonb end
  ) e(payload)
  where mc.key = 'qa_turnaround'
),
turnaround_rows as materialized (
  select (e.payload ->> 'turnaround_hours')::numeric as turnaround_hours
  from cohort_rows e
  join filtered_issues i on i.issue_key = e.payload ->> 'issue_key'
  where e.payload ->> 'turnaround_hours' is not null
),
turnaround_stat as (
  select percentile_cont(0.5) within group (order by turnaround_hours) as median_hours,
         count(*)::int as n
  from turnaround_rows
),
resolution_rows as materialized (
  select extract(epoch from (i.resolved_at - i.created_at)) / 86400.0 as resolution_days
  from filtered_issues i
  where i.issue_type = 'Bug' and i.resolved_at is not null
),
resolution_stat as (
  select percentile_cont(0.5) within group (order by resolution_days) as median_days,
         count(*)::int as n
  from resolution_rows
),
published_quality as materialized (
  select metric, median_value, unit, rows_used
  from v_resolution_medians
),
status_events as materialized (
  select h.issue_id, h.changed_at,
         coalesce(s.category, 'unknown') as to_cat,
         lag(coalesce(s.category, 'unknown')) over (
           partition by h.issue_id order by h.changed_at, h.itemordinal
         ) as from_cat
  from issue_field_history h
  join filtered_issues i on i.issue_id = h.issue_id
  left join statuses s on lower(s.name) = lower(h.to_display)
  where h.field = 'status'
),
reopen_ids as (
  select distinct issue_id
  from status_events
  where from_cat = 'Done' and to_cat <> 'Done'
),
reopen_months as (
  select date_trunc('month', changed_at) as month,
         count(distinct issue_id) filter (where from_cat = 'Done' and to_cat <> 'Done')::int as reopened_issues,
         count(*) filter (where from_cat = 'Done' and to_cat <> 'Done')::int as reopened_events,
         count(distinct issue_id) filter (where to_cat = 'Done')::int as closed_issues,
         count(distinct issue_id) filter (
           where to_cat = 'Done' and issue_id in (select issue_id from reopen_ids)
         )::int as reopened_of_those
  from status_events
  group by date_trunc('month', changed_at)
),
org_reopen_json as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'month', month,
    'reopened_issues', reopened_issues,
    'closed_issues', closed_issues,
    'reopen_pct', round(100.0 * reopened_of_those / nullif(closed_issues, 0), 1),
    'reopened_events', reopened_events
  ) order by month), '[]'::jsonb) as value
  from reopen_months
),
reopen_latest as (
  select * from reopen_months order by month desc limit 1
),
field_base as (
  select date_trunc('quarter', i.created_at) as quarter,
         false as is_total,
         count(*)::int as bugs_total,
         count(*) filter (where i.module is not null)::int as with_module,
         count(*) filter (where i.severity is not null)::int as with_severity,
         count(*) filter (where i.source is not null)::int as with_source,
         count(*) filter (where i.severity in ('L1','L2'))::int as l1l2_total,
         count(*) filter (where i.severity in ('L1','L2') and i.root_cause is not null)::int as l1l2_with_root_cause,
         count(*) filter (where i.severity = 'L1' and i.priority = 'Highest')::int as l1_mapped_highest,
         count(*) filter (where i.severity = 'L2' and i.priority = 'High')::int as l2_mapped_high,
         count(*) filter (where i.team_id is not null)::int as with_team
  from filtered_issues i
  where i.issue_type = 'Bug'
  group by date_trunc('quarter', i.created_at)
),
field_total as (
  select to_timestamp(0) as quarter, true as is_total,
         count(*)::int as bugs_total,
         count(*) filter (where i.module is not null)::int as with_module,
         count(*) filter (where i.severity is not null)::int as with_severity,
         count(*) filter (where i.source is not null)::int as with_source,
         count(*) filter (where i.severity in ('L1','L2'))::int as l1l2_total,
         count(*) filter (where i.severity in ('L1','L2') and i.root_cause is not null)::int as l1l2_with_root_cause,
         count(*) filter (where i.severity = 'L1' and i.priority = 'Highest')::int as l1_mapped_highest,
         count(*) filter (where i.severity = 'L2' and i.priority = 'High')::int as l2_mapped_high,
         count(*) filter (where i.team_id is not null)::int as with_team
  from filtered_issues i
  where i.issue_type = 'Bug'
),
field_json as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'quarter', quarter,
    'bugs_total', bugs_total,
    'with_module', with_module,
    'with_severity', with_severity,
    'with_source', with_source,
    'l1l2_total', l1l2_total,
    'l1l2_with_root_cause', l1l2_with_root_cause,
    'l1_mapped_highest', l1_mapped_highest,
    'l2_mapped_high', l2_mapped_high,
    'is_total', is_total,
    'module_coverage_pct', round(100.0 * with_module / nullif(bugs_total, 0), 1),
    'severity_coverage_pct', round(100.0 * with_severity / nullif(bugs_total, 0), 1),
    'source_coverage_pct', round(100.0 * with_source / nullif(bugs_total, 0), 1),
    'rca_coverage_pct', round(100.0 * l1l2_with_root_cause / nullif(l1l2_total, 0), 1),
    'l1_highest_pct', round(100.0 * l1_mapped_highest / nullif(l1l2_total, 0), 1),
    'l2_high_pct', round(100.0 * l2_mapped_high / nullif(l1l2_total, 0), 1),
    'with_team', with_team,
    'team_coverage_pct', round(100.0 * with_team / nullif(bugs_total, 0), 1)
  ) order by is_total, quarter), '[]'::jsonb) as value
  from (select * from field_base union all select * from field_total) h
  where h.bugs_total > 0
),
engineer_base as (
  select i.assignee_id, i.assignee_name,
         count(*)::int as bugs_touched,
         count(*) filter (where coalesce(ct.reopen_count, 0) > 0)::int as reopened,
         round(100.0 * count(*) filter (where coalesce(ct.reopen_count, 0) > 0) / nullif(count(*), 0), 1) as reopen_pct,
         count(*) filter (where i.root_cause is null and i.is_done and i.severity in ('L1','L2'))::int as closed_l1l2_without_rca,
         round(avg(extract(epoch from (ct.done_at - i.created_at)) / 86400.0) filter (where ct.done_at is not null)::numeric, 1) as avg_lead_time_days
  from filtered_issues i
  left join v_issue_cycle_times ct on ct.issue_id = i.issue_id
  where i.assignee_id is not null
  group by i.assignee_id, i.assignee_name
),
engineer_json as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'assignee_id', b.assignee_id,
    'assignee_name', b.assignee_name,
    'bugs_touched', b.bugs_touched,
    'reopened', b.reopened,
    'reopen_pct', b.reopen_pct,
    'closed_l1l2_without_rca', b.closed_l1l2_without_rca,
    'avg_lead_time_days', b.avg_lead_time_days
  ) order by b.assignee_name), '[]'::jsonb) as value
  from engineer_base b
),
bug_sla_json as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'issue_key', b.issue_key,
    'summary', b.summary,
    'severity', b.severity,
    'priority', b.priority,
    'status_name', b.status_name,
    'eta_deviation_days', b.eta_deviation_days,
    'response_hours_ct', b.response_hours_ct,
    'assignee_name', b.assignee_name,
    'created_at', b.created_at
  ) order by b.issue_key), '[]'::jsonb) as value
  from v_bug_sla b
  join filtered_issues i on i.issue_key = b.issue_key
),
updates as (
  select jsonb_build_object(
    'reopen_latest', jsonb_build_object(
      'value', (select round(100.0 * reopened_of_those / nullif(closed_issues, 0), 1) from reopen_latest),
      'unit', 'pct',
      'n', (select reopened_of_those from reopen_latest),
      'denominator', (select closed_issues from reopen_latest)
    ),
    'qa_rejection', jsonb_build_object(
      'value', (select round(100.0 * proportion, 2) from qa_org_calc),
      'unit', 'pct',
      'n', (select rejected_cycles from qa_org_calc),
      'denominator', (select denominator from qa_org_calc)
    ),
    'bug_resolution', jsonb_build_object(
      'value', case when p_sprint_id is null
        and cardinality(coalesce(p_modules, '{}'::text[])) = 0
        and cardinality(coalesce(p_severities, '{}'::text[])) = 0
        and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
           and cardinality(coalesce(p_sub_modules, '{}'::text[])) = 0
        then (select median_value from published_quality where metric = 'bug_resolution')
        else round((select median_days from resolution_stat)::numeric, 2) end,
      'unit', 'days',
      'n', case when p_sprint_id is null
        and cardinality(coalesce(p_modules, '{}'::text[])) = 0
        and cardinality(coalesce(p_severities, '{}'::text[])) = 0
        and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
           and cardinality(coalesce(p_sub_modules, '{}'::text[])) = 0
        then (select rows_used from published_quality where metric = 'bug_resolution')
        else (select n from resolution_stat) end,
      'denominator', case when p_sprint_id is null
        and cardinality(coalesce(p_modules, '{}'::text[])) = 0
        and cardinality(coalesce(p_severities, '{}'::text[])) = 0
        and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
           and cardinality(coalesce(p_sub_modules, '{}'::text[])) = 0
        then (select rows_used from published_quality where metric = 'bug_resolution')
        else (select n from resolution_stat) end
    ),
    'qa_turnaround', jsonb_build_object(
      'value', case when p_sprint_id is null
        and cardinality(coalesce(p_modules, '{}'::text[])) = 0
        and cardinality(coalesce(p_severities, '{}'::text[])) = 0
        and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
           and cardinality(coalesce(p_sub_modules, '{}'::text[])) = 0
        then (select median_value from published_quality where metric = 'qa_turnaround')
        else round((select median_hours from turnaround_stat)::numeric, 2) end,
      'unit', 'hours',
      'n', case when p_sprint_id is null
        and cardinality(coalesce(p_modules, '{}'::text[])) = 0
        and cardinality(coalesce(p_severities, '{}'::text[])) = 0
        and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
           and cardinality(coalesce(p_sub_modules, '{}'::text[])) = 0
        then (select rows_used from published_quality where metric = 'qa_turnaround')
        else (select n from turnaround_stat) end,
      'denominator', case when p_sprint_id is null
        and cardinality(coalesce(p_modules, '{}'::text[])) = 0
        and cardinality(coalesce(p_severities, '{}'::text[])) = 0
        and cardinality(coalesce(p_assignees, '{}'::text[])) = 0
           and cardinality(coalesce(p_sub_modules, '{}'::text[])) = 0
        then (select rows_used from published_quality where metric = 'qa_turnaround')
        else (select n from turnaround_stat) end
    )
  ) as value
)
select jsonb_build_object(
  'bug_sla', (select value from bug_sla_json),
  'org_reopen', (select value from org_reopen_json),
  'qa_rejection', (select value from qa_rows_json),
  'qa_rejection_org', (select value from qa_org_json),
  'field_hygiene', (select value from field_json),
  'field_hygiene_org', coalesce((
    select value from jsonb_array_elements((select value from field_json)) e(value)
    where (e.value ->> 'is_total')::boolean
    limit 1
  ), null),
  'engineer_quality', (select value from engineer_json),
  'metric_updates', (select value from updates)
);
$function$;

-- jira.get_filtered_dashboard_quality_submodule(bigint,text[],text[],text[],text[])
CREATE OR REPLACE FUNCTION jira.get_filtered_dashboard_quality_submodule(p_sprint_id bigint DEFAULT NULL::bigint, p_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[], p_sub_modules text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '20s'
AS $function$
declare
  result jsonb;
  resolution_medians jsonb;
begin
  result := jira.get_filtered_dashboard_quality_025_base_submodule(p_sprint_id, p_modules, p_severities, p_assignees, p_sub_modules);

  -- Publish the same two rows as v_resolution_medians, but within the active
  -- dashboard filter. The values remain database-owned; React only formats
  -- them. A zero-row population publishes median_value null and rows_used 0.
  with filtered_issues as materialized (
    select
      i.issue_id,
      i.issue_key,
      i.created_at,
      i.resolved_at,
      i.issue_type,
      i.module,
      i.severity,
      i.assignee_name,
      i.status_name,
      i.status_category,
      i.is_done
    from jira.v_issue_normalized i
    where i.project_key = 'SPEND'
      and jira._dashboard_filter_matches_submodule(
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
          from jira.sprint_issues si
          join jira.v_dashboard_sprints ds on ds.id = si.sprint_id
          where si.issue_id = i.issue_id
            and si.sprint_id = p_sprint_id
            and si.removed_at is null
        )
      )
  ),
  bug_stat as (
    select
      round(percentile_cont(0.5) within group (
        order by extract(epoch from (resolved_at - created_at)) / 86400.0
      )::numeric, 2) as median_value,
      count(*)::int as rows_used
    from filtered_issues
    where issue_type = 'Bug'
      and resolved_at is not null
  ),
  turnaround_rows as materialized (
    select (entry ->> 'turnaround_hours')::numeric as turnaround_hours
    from jira.metric_cohorts mc
    cross join lateral jsonb_array_elements(
      case
        when jsonb_typeof(coalesce(mc.rows, '[]'::jsonb)) = 'array'
          then coalesce(mc.rows, '[]'::jsonb)
        else '[]'::jsonb
      end
    ) entry
    join filtered_issues i on i.issue_key = entry ->> 'issue_key'
    where mc.key = 'qa_turnaround'
      and entry ->> 'turnaround_hours' is not null
  ),
  turnaround_stat as (
    select
      round(percentile_cont(0.5) within group (order by turnaround_hours)::numeric, 2) as median_value,
      count(*)::int as rows_used
    from turnaround_rows
  ),
  excluded_open as (
    select count(*)::int as count
    from filtered_issues
    where status_name ilike 'uat%'
      and is_done = false
      and status_category <> 'Done'
  ),
  rows_for_json as (
    select
      'bug_resolution'::text as metric,
      b.median_value,
      'days'::text as unit,
      b.rows_used,
      null::int as excluded_open
    from bug_stat b
    union all
    select
      'qa_turnaround'::text as metric,
      t.median_value,
      'hours'::text as unit,
      t.rows_used,
      e.count as excluded_open
    from turnaround_stat t
    cross join excluded_open e
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'metric', metric,
    'median_value', median_value,
    'unit', unit,
    'rows_used', rows_used,
    'excluded_open', excluded_open,
    'computed_at', now()
  ) order by metric), '[]'::jsonb)
  into resolution_medians
  from rows_for_json;

  return result || jsonb_build_object('resolution_medians', resolution_medians);
end;
$function$;

-- jira.get_filtered_drilldown(integer[],text,text[],text[])
CREATE OR REPLACE FUNCTION jira.get_filtered_drilldown(p_sprint_ids integer[] DEFAULT NULL::integer[], p_module text DEFAULT NULL::text, p_severity text[] DEFAULT NULL::text[], p_assignee text[] DEFAULT NULL::text[])
 RETURNS SETOF jira.v_sprint_drilldown
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '5s'
AS $function$
declare
  valid_sprints int[];
begin
  if p_sprint_ids is null or cardinality(p_sprint_ids) = 0 then
    select coalesce(array_agg(id::int order by start_date desc, id desc), '{}'::int[])
      into valid_sprints
    from v_dashboard_sprints;
  else
    select coalesce(array_agg(id::int order by start_date desc, id desc), '{}'::int[])
      into valid_sprints
    from v_dashboard_sprints
    where id = any(p_sprint_ids);
  end if;

  return query
  select d.*
  from v_sprint_drilldown d
  where d.sprint_id = any(valid_sprints)
    and (
      p_module is null
      or (p_module = '__untagged__' and d.module is null)
      or d.module = p_module
    )
    and (
      p_severity is null
      or cardinality(p_severity) = 0
      or (d.severity is null and 'Untagged' = any(p_severity))
      or d.severity = any(p_severity)
    )
    and (
      p_assignee is null
      or cardinality(p_assignee) = 0
      or d.assignee_name = any(p_assignee)
    )
  order by d.sprint_id asc, d.issue_id asc;
end;
$function$;

-- jira.get_filtered_drilldown_submodule(integer[],text,text[],text[],text[])
CREATE OR REPLACE FUNCTION jira.get_filtered_drilldown_submodule(p_sprint_ids integer[] DEFAULT NULL::integer[], p_module text DEFAULT NULL::text, p_severity text[] DEFAULT NULL::text[], p_assignee text[] DEFAULT NULL::text[], p_sub_modules text[] DEFAULT NULL::text[])
 RETURNS SETOF jira.v_sprint_drilldown
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '5s'
AS $function$
declare
  valid_sprints int[];
begin
  if p_sprint_ids is null or cardinality(p_sprint_ids) = 0 then
    select coalesce(array_agg(id::int order by start_date desc, id desc), '{}'::int[])
      into valid_sprints
    from v_dashboard_sprints;
  else
    select coalesce(array_agg(id::int order by start_date desc, id desc), '{}'::int[])
      into valid_sprints
    from v_dashboard_sprints
    where id = any(p_sprint_ids);
  end if;

  return query
  select d.*
  from v_sprint_drilldown d
  where d.sprint_id = any(valid_sprints)
    and (
      p_module is null
      or (p_module = '__untagged__' and d.module is null)
      or d.module = p_module
    )
    and (
      p_sub_modules is null
      or cardinality(p_sub_modules) = 0
      or (nullif(btrim(d.sub_module), '') is null and '__untagged__' = any(p_sub_modules))
      or btrim(d.sub_module) = any(p_sub_modules)
    )
    and (
      p_severity is null
      or cardinality(p_severity) = 0
      or (d.severity is null and 'Untagged' = any(p_severity))
      or d.severity = any(p_severity)
    )
    and (
      p_assignee is null
      or cardinality(p_assignee) = 0
      or d.assignee_name = any(p_assignee)
    )
  order by d.sprint_id asc, d.issue_id asc;
end;
$function$;

-- jira.get_filtered_metric_cohort(text,integer[],text,text[],text[])
CREATE OR REPLACE FUNCTION jira.get_filtered_metric_cohort(p_key text, p_sprint_ids integer[] DEFAULT NULL::integer[], p_module text DEFAULT NULL::text, p_severity text[] DEFAULT NULL::text[], p_assignee text[] DEFAULT NULL::text[])
 RETURNS TABLE(key text, title text, value double precision, unit text, n integer, denominator integer, source text, definition text, definition_ref text, row_type text, rows_shown integer, rows jsonb, issue_keys jsonb, source_note text, is_filtered boolean, scope_note text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '5s'
AS $function$
  select *
  from get_filtered_metric_cohorts(p_sprint_ids, p_module, p_severity, p_assignee)
  where key = p_key;
$function$;

-- jira.get_filtered_metric_cohorts(integer[],text,text[],text[])
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
$function$;

-- jira.load_field_history(jsonb)
CREATE OR REPLACE FUNCTION jira.load_field_history(cl jsonb)
 RETURNS TABLE(loaded bigint)
 LANGUAGE plpgsql
 SET search_path TO 'jira', 'public', 'pg_catalog'
AS $function$
begin
  insert into issue_field_history as h
      (issue_id, change_id, itemOrdinal, field, fieldtype, field_id,
       from_value, from_display, to_value, to_display, changed_at, author_id, author_name)
  select e.issue_id::bigint,
         ch.h->>'id', it.ord,
         it.item->>'field', it.item->>'fieldtype', it.item->>'fieldId',
         it.item->>'from', it.item->>'fromString',
         it.item->>'to', it.item->>'toString',
         to_timestamp((ch.h->>'created')::bigint / 1000.0),
         ch.h#>>'{author,accountId}', ch.h#>>'{author,displayName}'
  from jsonb_each(coalesce(cl, '{}'::jsonb)) e(issue_id, obj)
  join issues i on i.issue_id = e.issue_id::bigint
  cross join lateral jsonb_array_elements(
    _jsonb_array_or_empty(e.obj->'changeHistories')
  ) with ordinality ch(h, ord)
  cross join lateral jsonb_array_elements(
    _jsonb_array_or_empty(ch.h->'items')
  ) with ordinality it(item, ord)
  on conflict (issue_id, change_id, itemOrdinal) do nothing;
  loaded := (select count(*) from issue_field_history);
  return next;
end;
$function$;

-- jira.reconcile_dashboard_sprint_membership(bigint,bigint[])
CREATE OR REPLACE FUNCTION jira.reconcile_dashboard_sprint_membership(p_sprint_id bigint, p_issue_ids bigint[])
 RETURNS TABLE(removed_count integer, active_count integer)
 LANGUAGE plpgsql
 SET search_path TO 'jira', 'public', 'pg_catalog'
AS $function$
DECLARE
  v_issue_ids bigint[] := coalesce(p_issue_ids, '{}'::bigint[]);
  v_removed integer := 0;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM v_dashboard_sprints WHERE id = p_sprint_id
  ) THEN
    RAISE EXCEPTION 'sprint % is outside the published dashboard window', p_sprint_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM unnest(v_issue_ids) AS requested(issue_id)
    LEFT JOIN issues i ON i.issue_id = requested.issue_id
    WHERE i.issue_id IS NULL OR i.project_key <> 'SPEND'
  ) THEN
    RAISE EXCEPTION 'sprint % contains unknown or out-of-project issue IDs', p_sprint_id;
  END IF;

  UPDATE sprint_issues si
     SET removed_at = now()
   WHERE si.sprint_id = p_sprint_id
     AND si.removed_at IS NULL
     AND NOT (si.issue_id = ANY(v_issue_ids));
  GET DIAGNOSTICS v_removed = ROW_COUNT;

  INSERT INTO sprint_issues AS current_membership (issue_id, sprint_id, added_at)
  SELECT DISTINCT requested.issue_id, p_sprint_id, now()
    FROM unnest(v_issue_ids) AS requested(issue_id)
  ON CONFLICT (issue_id, sprint_id) DO UPDATE
    SET removed_at = NULL
    WHERE current_membership.removed_at IS NOT NULL;

  RETURN QUERY
  SELECT v_removed,
         count(*)::integer
    FROM sprint_issues si
   WHERE si.sprint_id = p_sprint_id
     AND si.removed_at IS NULL;
END;
$function$;

-- jira.refresh_metric_cohorts()
CREATE OR REPLACE FUNCTION jira.refresh_metric_cohorts()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'jira', 'public', 'pg_catalog'
 SET statement_timeout TO '15min'
AS $function$
declare
  latest_sync_id bigint;
  last_refreshed_sync_id bigint;
begin
  if not pg_try_advisory_xact_lock(731942608317) then
    return;
  end if;

  select coalesce(max(id), 0)
    into latest_sync_id
  from jira.sync_log
  where finished_at is not null
    and errors_count = 0;

  select refreshed_sync_id
    into last_refreshed_sync_id
  from jira.dashboard_snapshot_refresh_state
  where singleton;

  if latest_sync_id <= coalesce(last_refreshed_sync_id, 0) then
    return;
  end if;

  refresh materialized view concurrently jira.metric_cohorts;
  refresh materialized view concurrently jira.v_module_counts;
  refresh materialized view concurrently jira.mv_sprint_commitment_scope;
  refresh materialized view concurrently jira.mv_sprint_commitment_pending;

  update jira.dashboard_snapshot_refresh_state
  set refreshed_sync_id = latest_sync_id,
      refreshed_at = now()
  where singleton;
end;
$function$;

-- jira.refresh_reference_tables()
CREATE OR REPLACE FUNCTION jira.refresh_reference_tables()
 RETURNS TABLE(ref text, rows integer)
 LANGUAGE plpgsql
 SET search_path TO 'jira', 'public', 'pg_catalog'
AS $function$
begin
  insert into users (account_id, display_name, is_former, synced_at)
  select distinct u.account_id, u.display_name, (u.display_name = 'Former user'), now()
  from raw_issues r
  cross join lateral (values
      (r.payload#>>'{fields,assignee,accountId}', r.payload#>>'{fields,assignee,displayName}'),
      (r.payload#>>'{fields,reporter,accountId}', r.payload#>>'{fields,reporter,displayName}'),
      (r.payload#>>'{fields,creator,accountId}', r.payload#>>'{fields,creator,displayName}')
  ) u(account_id, display_name)
  where u.account_id is not null
  on conflict (account_id) do update set display_name = excluded.display_name, synced_at = now();

  with actors as (
    select c#>>'{author,accountId}' aid, c#>>'{author,displayName}' dn
    from raw_issues r
    cross join lateral jsonb_array_elements(_jsonb_array_or_empty(r.payload#>'{fields,comment,comments}')) c
    union all
    select a#>>'{author,accountId}', a#>>'{author,displayName}'
    from raw_issues r
    cross join lateral jsonb_array_elements(_jsonb_array_or_empty(r.payload#>'{fields,attachment}')) a
    union all
    select w#>>'{author,accountId}', w#>>'{author,displayName}'
    from raw_issues r
    cross join lateral jsonb_array_elements(_jsonb_array_or_empty(r.payload#>'{fields,worklog,worklogs}')) w
    union all
    select w#>>'{updateAuthor,accountId}', w#>>'{updateAuthor,displayName}'
    from raw_issues r
    cross join lateral jsonb_array_elements(_jsonb_array_or_empty(r.payload#>'{fields,comment,comments}')) w
  )
  insert into users (account_id, display_name, is_former, synced_at)
  select distinct aid, dn, (dn = 'Former user'), now()
  from actors where aid is not null
  on conflict (account_id) do update set display_name = excluded.display_name, synced_at = now();
  ref := 'users'; rows := (select count(*) from users); return next;

  -- Jira renamed the SPEND project from KOREFI to AiA. Raw issue snapshots
  -- legitimately include both labels for the same key. DISTINCT across
  -- (key,name) does NOT dedupe a unique key. Pick one authoritative latest
  -- non-deleted snapshot, with stable issue-id tie breaking.
  insert into projects (key, name)
  select distinct on (r.payload#>>'{fields,project,key}')
         r.payload#>>'{fields,project,key}',
         r.payload#>>'{fields,project,name}'
  from raw_issues r
  where r.payload#>>'{fields,project,key}' is not null
    and r.deleted_at is null
  order by r.payload#>>'{fields,project,key}',
           r.jql_synced_at desc,
           r.issue_id desc
  on conflict (key) do update
    set name = excluded.name,
        synced_at = now();
  ref := 'projects'; rows := (select count(*) from projects); return next;

  insert into issue_types (id, name, subtask)
  select distinct (r.payload->'fields'->'issuetype'->>'id')::bigint,
         r.payload->'fields'->'issuetype'->>'name',
         coalesce((r.payload->'fields'->'issuetype'->>'subtask')::boolean, false)
  from raw_issues r where r.payload->'fields'->'issuetype'->>'id' is not null
  on conflict (id) do update set name = excluded.name, synced_at = now();
  ref := 'issue_types'; rows := (select count(*) from issue_types); return next;

  insert into statuses (id, name, category)
  select distinct (r.payload->'fields'->'status'->>'id')::bigint,
         r.payload->'fields'->'status'->>'name',
         r.payload->'fields'->'status'#>>'{statusCategory,name}'
  from raw_issues r where r.payload->'fields'->'status'->>'id' is not null
  on conflict (id) do update set name = excluded.name, category = excluded.category, synced_at = now();
  ref := 'statuses'; rows := (select count(*) from statuses); return next;

  insert into priorities (id, name)
  select distinct (r.payload->'fields'->'priority'->>'id')::bigint,
         r.payload->'fields'->'priority'->>'name'
  from raw_issues r where r.payload->'fields'->'priority'->>'id' is not null
  on conflict (id) do update set name = excluded.name, synced_at = now();
  ref := 'priorities'; rows := (select count(*) from priorities); return next;
  return;
end;
$function$;

-- read_jira_delivery_dashboard_v1(bigint,text[],text[],text[],text[])
CREATE OR REPLACE FUNCTION public.read_jira_delivery_dashboard_v1(p_sprint_id bigint DEFAULT NULL::bigint, p_modules text[] DEFAULT NULL::text[], p_sub_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_temp'
 SET statement_timeout TO '30s'
 SET enable_nestloop TO 'off'
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

-- read_jira_delivery_evidence_v1(text,bigint,text[],text[],text[],text[],integer,integer,bigint)
CREATE OR REPLACE FUNCTION public.read_jira_delivery_evidence_v1(p_key text, p_sprint_id bigint DEFAULT NULL::bigint, p_modules text[] DEFAULT NULL::text[], p_sub_modules text[] DEFAULT NULL::text[], p_severities text[] DEFAULT NULL::text[], p_assignees text[] DEFAULT NULL::text[], p_limit integer DEFAULT 40, p_offset integer DEFAULT 0, p_snapshot_id bigint DEFAULT NULL::bigint)
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
 IF p_key NOT IN ('commitment_gap','stage:Code Review') AND left(p_key,7)<>'status:' AND left(p_key,5)<>'type:' THEN
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
 ELSIF p_key='stage:Code Review' THEN
   -- Same per-issue stage intervals and direct sprint membership as
   -- jira.v_sprint_stage_summary and the filtered Flow dashboard.
   -- One issue may have multiple transitions; total hours are summed per
   -- issue/stage before computing the median. The reported sample is issues,
   -- not individual status events.
   v_selected := coalesce(p_sprint_id,
     (SELECT id FROM jira.v_dashboard_sprints
      ORDER BY (state='active') DESC,start_date DESC,id DESC LIMIT 1));
   IF v_selected IS NULL THEN RAISE EXCEPTION 'jira_delivery_missing_sprint'; END IF;
   v_flow := jira.get_filtered_dashboard_flow_submodule(
     p_sprint_id,p_modules,p_severities,p_assignees,p_sub_modules);
   SELECT item INTO v_stage
     FROM jsonb_array_elements(coalesce(v_flow->'stage_summary','[]'::jsonb)) item
     WHERE (item->>'sprint_id')::bigint=v_selected
       AND item->>'stage'='Code Review'
     LIMIT 1;
   WITH ev AS (
     SELECT h.issue_id,h.to_display raw_stage,h.changed_at,
       lead(h.changed_at) OVER(PARTITION BY h.issue_id ORDER BY h.changed_at) next_change
     FROM jira.issue_field_history h
     WHERE h.field='status'
   ), stage_secs AS (
     SELECT e.issue_id,initcap(e.raw_stage) stage,
       sum(extract(epoch from coalesce(e.next_change,now())-e.changed_at))/3600.0 AS hours
     FROM ev e
     WHERE lower(e.raw_stage) NOT IN ('done','issue resolved','spendlytics')
     GROUP BY e.issue_id,initcap(e.raw_stage)
   ), stage_issues AS (
     SELECT d.issue_key,d.summary,d.issue_type,d.status_name,
       d.priority,d.severity,d.module,d.sub_module,d.assignee_name,
       d.created_at,d.resolved_at,d.sprint_id,
       ss.hours
     FROM jira.v_sprint_drilldown d
     JOIN stage_secs ss ON ss.issue_id=d.issue_id
     WHERE d.sprint_id=v_selected AND d.is_direct_member AND NOT d.is_subtask
       AND ss.stage='Code Review'
       AND jira._dashboard_filter_matches_submodule(
         d.module,d.sub_module,d.severity,d.assignee_name,
         p_modules,p_sub_modules,p_severities,p_assignees)
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
   SELECT coalesce(name,'Selected sprint')||' · Code review' INTO v_label
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
    'resolved_at',e.row->>'resolved_at',
    'stage_hours',(e.row->>'stage_hours')::numeric
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

-- read_jira_delivery_evidence_v2(text,bigint,text[],text[],text[],text[],integer,integer,bigint,text,text,text)
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

-- read_jira_delivery_issue_v1(text,bigint)
CREATE OR REPLACE FUNCTION public.read_jira_delivery_issue_v1(p_issue_key text, p_snapshot_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'jira', 'public', 'pg_temp'
 SET statement_timeout TO '20s'
AS $function$
DECLARE
 v_issue jira.issues%ROWTYPE;
 v_snapshot bigint;
 v_latest bigint;
 v_status jsonb;
 v_comments jsonb;
 v_links jsonb;
 v_reopens integer;
 v_total_comments integer;
 v_total_links integer;
BEGIN
 IF p_issue_key IS NULL OR p_issue_key !~ '^SPEND-[0-9]{1,12}$'
   OR p_snapshot_id IS NULL THEN
   RAISE EXCEPTION 'jira_issue_invalid_request';
 END IF;
 SELECT refreshed_sync_id INTO v_snapshot
 FROM jira.dashboard_snapshot_refresh_state WHERE singleton;
 SELECT max(id) INTO v_latest FROM jira.sync_log;
 IF v_snapshot IS DISTINCT FROM p_snapshot_id OR v_latest IS DISTINCT FROM v_snapshot
   OR NOT EXISTS(SELECT 1 FROM jira.sync_log s WHERE s.id=v_snapshot
     AND s.finished_at IS NOT NULL AND s.errors_count=0) THEN
   RAISE EXCEPTION 'jira_issue_snapshot_mismatch';
 END IF;
 SELECT i.* INTO v_issue FROM jira.issues i
 JOIN jira.raw_issues r USING(issue_id)
 WHERE i.issue_key=p_issue_key AND i.project_key='SPEND'
   AND r.deleted_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'jira_issue_unavailable'; END IF;

 WITH history AS (
   SELECT h.from_display,h.to_display,h.changed_at,
     row_number() OVER(ORDER BY h.changed_at,h.change_id,h.itemordinal) rn,
     lead(h.changed_at) OVER(ORDER BY h.changed_at,h.change_id,h.itemordinal) next_changed
   FROM jira.issue_field_history h
   WHERE h.issue_id=v_issue.issue_id AND lower(h.field)='status'
 ), timeline AS (
   SELECT coalesce(nullif(h.from_display,''),v_issue.status_name) AS status,
     v_issue.created_at AS entered_at,h.changed_at AS exit_at,0::bigint AS seq
   FROM history h WHERE h.rn=1
   UNION ALL
   SELECT coalesce(nullif(h.to_display,''),'Unknown'),
     h.changed_at,h.next_changed,h.rn FROM history h
   UNION ALL
   SELECT v_issue.status_name,v_issue.created_at,
     NULL::timestamptz,0::bigint
   WHERE NOT EXISTS(SELECT 1 FROM history)
 )
 SELECT coalesce(jsonb_agg(jsonb_build_object(
   'status',status,'entered_at',entered_at,
   'dwell_hours',CASE WHEN exit_at IS NOT NULL AND exit_at>=entered_at
     THEN round((extract(epoch FROM exit_at-entered_at)/3600.0)::numeric,1)
     ELSE NULL END
 ) ORDER BY entered_at,seq),'[]'::jsonb) INTO v_status
 FROM timeline;

 SELECT CASE WHEN count(*)=0 THEN NULL
   ELSE count(*) FILTER (WHERE lower(coalesce(from_display,'')) IN
      ('done','closed','resolved') AND lower(coalesce(to_display,'')) NOT IN
      ('done','closed','resolved'))::integer END
 INTO v_reopens
 FROM jira.issue_field_history
 WHERE issue_id=v_issue.issue_id AND lower(field)='status';

 SELECT count(*)::integer INTO v_total_comments
 FROM jira.comments WHERE issue_id=v_issue.issue_id;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'author',author_name,'created_at',created,'body',left(coalesce(body_text,''),3000))
  ORDER BY created DESC),'[]'::jsonb) INTO v_comments
 FROM (SELECT author_name,created,body_text FROM jira.comments
   WHERE issue_id=v_issue.issue_id ORDER BY created DESC LIMIT 30) c;

 SELECT count(*)::integer INTO v_total_links
 FROM jira.issue_links WHERE issue_id=v_issue.issue_id;
 SELECT coalesce(jsonb_agg(jsonb_build_object(
  'direction',direction,'relationship',coalesce(description,link_type_name),
  'issue_key',related_issue_key) ORDER BY related_issue_key),'[]'::jsonb)
 INTO v_links
 FROM (SELECT direction,description,link_type_name,related_issue_key
   FROM jira.issue_links WHERE issue_id=v_issue.issue_id
   ORDER BY related_issue_key LIMIT 50) l;

 RETURN jsonb_build_object(
  'contract','jira_delivery_issue_v1','snapshot_id',v_snapshot,
  'issue_key',v_issue.issue_key,'summary',v_issue.summary,
  'issue_type',v_issue.issue_type,'status',v_issue.status_name,
  'priority',v_issue.priority,'severity',v_issue.severity,
  'module',v_issue.module,'sub_module',v_issue.sub_module,
  'assignee',v_issue.assignee_name,'created_at',v_issue.created_at,
  'updated_at',v_issue.updated_at,'resolved_at',v_issue.resolved_at,
  'due_date',v_issue.due_date,'story_points',v_issue.story_points,
  'labels',to_jsonb(v_issue.labels),
  'service_levels',jsonb_build_object(
    'first_response_hours',NULL,
    'eta_deviation_hours',NULL,
    'reopen_count',v_reopens,
    'qa_signoff_cycles',NULL,
    'qa_rejected_cycles',NULL),
  'status_trail',v_status,
  'comments',v_comments,'comment_count',v_total_comments,
  'links',v_links,'link_count',v_total_links);
END;
$function$;
