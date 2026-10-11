-- Repair jira.refresh_reference_tables project renames without modifying any
-- raw or derived issues. Keep the same return shape, grants and search path.
-- Latest jql_synced_at wins deterministically for each project key.
--
-- Existing issue, sprint and materialized snapshot readers are untouched.
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
$function$
