-- Companies post-integration lifecycle reporting.
-- W1 = [integration, +7d), W2 = [+7d, +14d), W3 = [+14d, +21d),
-- W4 = [+21d, +28d). The anchor is the FIRST successful integration event.

create table if not exists metrics_private.company_lifecycle_identity (
  company_id text primary key,
  company_name text not null,
  is_test boolean not null default false,
  integration text not null default 'Unknown',
  integration_at timestamptz not null
);

create table if not exists metrics_private.company_lifecycle_user (
  company_id text not null,
  user_key text not null,
  user_email text,
  first_seen_at timestamptz not null,
  last_seen_at timestamptz not null,
  primary key (company_id, user_key)
);

create table if not exists metrics_private.company_lifecycle_week_module_usage (
  company_id text not null,
  user_key text not null,
  usage_week smallint not null check (usage_week between 1 and 4),
  module text not null check (module in ('ap','ar','transactions','gst')),
  events bigint not null check (events >= 0),
  primary key (company_id, user_key, usage_week, module)
);

create table if not exists metrics_private.company_lifecycle_meta (
  singleton boolean primary key default true check (singleton),
  first_integration_date date,
  latest_integration_date date,
  source_watermark_at timestamptz,
  refreshed_at timestamptz not null
);

create index if not exists company_lifecycle_identity_integration_at_idx
  on metrics_private.company_lifecycle_identity (integration_at desc, company_id);
create index if not exists company_lifecycle_user_email_idx
  on metrics_private.company_lifecycle_user (lower(user_email));
create index if not exists company_lifecycle_usage_company_week_idx
  on metrics_private.company_lifecycle_week_module_usage (company_id, usage_week);

revoke all on metrics_private.company_lifecycle_identity from public, anon, authenticated;
revoke all on metrics_private.company_lifecycle_user from public, anon, authenticated;
revoke all on metrics_private.company_lifecycle_week_module_usage from public, anon, authenticated;
revoke all on metrics_private.company_lifecycle_meta from public, anon, authenticated;

create or replace function public.refresh_companies_lifecycle_cache()
returns jsonb
language plpgsql
security definer
set search_path = public, metrics_private, pg_temp
set statement_timeout = '90s'
as $function$
declare
  v_company_rows bigint;
  v_user_rows bigint;
  v_usage_rows bigint;
  v_watermark timestamptz;
begin
  delete from metrics_private.company_lifecycle_identity;

  insert into metrics_private.company_lifecycle_identity (
    company_id, company_name, is_test, integration, integration_at
  )
  with first_integration as (
    select distinct on (e.company_id)
      e.company_id,
      e.event_time as integration_at,
      case lower(btrim(coalesce(e.properties ->> 'type', '')))
        when 'tally' then 'Tally'
        when 'zoho' then 'Zoho Books'
        when 'zoho books' then 'Zoho Books'
        else 'Unknown'
      end as integration
    from public.events e
    join public.client_company c on c.company_id = e.company_id
    where e.event_name = 'Integration status'
      and lower(btrim(coalesce(e.properties ->> 'status', ''))) in ('success','successful')
      and e.company_id is not null
      and e.company_id <> ''
    order by e.company_id, e.event_time asc, e.insert_id asc
  ),
  event_names as (
    select distinct on (e.company_id)
      e.company_id,
      public.company_usable_name(e.properties ->> 'companyName') as company_name
    from public.events e
    join public.client_company c on c.company_id = e.company_id
    where e.properties ? 'companyName'
      and public.company_usable_name(e.properties ->> 'companyName') is not null
    order by e.company_id, e.event_time desc, e.insert_id desc
  )
  select
    c.company_id,
    coalesce(nullif(btrim(d.company_name), ''), n.company_name, c.company_id),
    coalesce(d.is_test, false),
    fi.integration,
    fi.integration_at
  from public.client_company c
  join first_integration fi on fi.company_id = c.company_id
  left join public.company_directory d on d.company_uuid::text = c.company_id
  left join event_names n on n.company_id = c.company_id;

  get diagnostics v_company_rows = row_count;

  delete from metrics_private.company_lifecycle_user;

  insert into metrics_private.company_lifecycle_user (
    company_id, user_key, user_email, first_seen_at, last_seen_at
  )
  select
    e.company_id,
    nullif(btrim(e.distinct_id), '') as user_key,
    (
      array_agg(nullif(btrim(e.email), '') order by e.event_time desc, e.insert_id desc)
      filter (where nullif(btrim(e.email), '') is not null)
    )[1] as user_email,
    min(e.event_time),
    max(e.event_time)
  from public.events e
  join metrics_private.company_lifecycle_identity i on i.company_id = e.company_id
  where e.event_time >= i.integration_at
    and nullif(btrim(e.distinct_id), '') is not null
    and not public.is_internal_email(e.email)
  group by e.company_id, nullif(btrim(e.distinct_id), '');

  get diagnostics v_user_rows = row_count;

  delete from metrics_private.company_lifecycle_week_module_usage;

  insert into metrics_private.company_lifecycle_week_module_usage (
    company_id, user_key, usage_week, module, events
  )
  with classified as (
    select
      e.company_id,
      coalesce(nullif(btrim(e.distinct_id), ''), '__unattributed__') as user_key,
      (1 + floor(extract(epoch from (e.event_time - i.integration_at)) / 604800))::smallint as usage_week,
      public.company_module_for(e.event_name, coalesce(e.properties, '{}'::jsonb)) as module
    from public.events e
    join metrics_private.company_lifecycle_identity i on i.company_id = e.company_id
    where e.event_time >= i.integration_at
      and e.event_time < i.integration_at + interval '28 days'
      and not public.is_internal_email(e.email)
  )
  select company_id, user_key, usage_week, module, count(*)::bigint
  from classified
  where usage_week between 1 and 4
    and module in ('ap','ar','transactions','gst')
  group by company_id, user_key, usage_week, module;

  get diagnostics v_usage_rows = row_count;

  select w.last_success_at
    into v_watermark
  from public.export_watermarks w
  where w.job_name='incremental' and w.status='ok'
  order by w.last_success_at desc
  limit 1;

  delete from metrics_private.company_lifecycle_meta;
  insert into metrics_private.company_lifecycle_meta (
    singleton, first_integration_date, latest_integration_date,
    source_watermark_at, refreshed_at
  )
  select
    true,
    min(i.integration_at at time zone 'Asia/Kolkata')::date,
    max(i.integration_at at time zone 'Asia/Kolkata')::date,
    v_watermark,
    now()
  from metrics_private.company_lifecycle_identity i;

  return jsonb_build_object(
    'company_rows', v_company_rows,
    'user_rows', v_user_rows,
    'usage_rows', v_usage_rows,
    'source_watermark_at', v_watermark,
    'refreshed_at', now()
  );
end;
$function$;

create or replace function public.read_companies_lifecycle_page(
  p_from date default null,
  p_to date default null,
  p_query text default '',
  p_usage text default 'all',
  p_integration text default 'all',
  p_sort text default 'integration_date',
  p_direction text default 'desc',
  p_page integer default 1,
  p_page_size integer default 10
)
returns jsonb
language sql
stable
security definer
set search_path = public, metrics_private, pg_temp
set statement_timeout = '5s'
as $function$
with args as (
  select
    greatest(coalesce(p_page,1),1) as page_no,
    least(greatest(coalesce(p_page_size,1000),1),5000) as page_size,
    lower(btrim(coalesce(p_query,''))) as q,
    case when p_usage in ('active','inactive') then p_usage else 'all' end as usage_filter,
    case when p_integration in ('Tally','Zoho Books','Unknown') then p_integration else 'all' end as integration_filter,
    case when p_sort='name' then 'name' else 'integration_date' end as sort_key,
    case when lower(coalesce(p_direction,''))='asc' then 'asc' else 'desc' end as sort_direction,
    case when p_from is null then null else p_from::timestamp at time zone 'Asia/Kolkata' end as from_at,
    case when p_to is null then null else (p_to + 1)::timestamp at time zone 'Asia/Kolkata' end as to_at
),
company_usage as (
  select
    u.company_id,
    sum(u.events)::bigint as total_events
  from metrics_private.company_lifecycle_week_module_usage u
  group by u.company_id
),
filtered as (
  select
    i.company_id, i.company_name, i.is_test, i.integration, i.integration_at,
    coalesce(cu.total_events,0)::bigint as total_events
  from metrics_private.company_lifecycle_identity i
  left join company_usage cu using (company_id)
  cross join args a
  where (a.from_at is null or i.integration_at >= a.from_at)
    and (a.to_at is null or i.integration_at < a.to_at)
    and (
      a.q=''
      or lower(i.company_name) like '%' || a.q || '%'
      or exists (
        select 1
        from metrics_private.company_lifecycle_user u
        where u.company_id=i.company_id
          and lower(coalesce(u.user_email,u.user_key)) like '%' || a.q || '%'
      )
    )
    and (a.integration_filter='all' or i.integration=a.integration_filter)
    and (
      a.usage_filter='all'
      or (a.usage_filter='active' and coalesce(cu.total_events,0)>0)
      or (a.usage_filter='inactive' and coalesce(cu.total_events,0)=0)
    )
),
ranked as (
  select
    f.*,
    row_number() over (
      order by
        case when a.sort_key='integration_date' and a.sort_direction='asc' then f.integration_at end asc,
        case when a.sort_key='integration_date' and a.sort_direction='desc' then f.integration_at end desc,
        case when a.sort_key='name' and a.sort_direction='asc' then lower(f.company_name) end asc,
        case when a.sort_key='name' and a.sort_direction='desc' then lower(f.company_name) end desc,
        case when a.sort_direction='asc' then f.company_id end asc,
        case when a.sort_direction='desc' then f.company_id end desc
    ) as rn
  from filtered f
  cross join args a
),
paged as (
  select r.*
  from ranked r
  cross join args a
  where r.rn > (a.page_no-1)*a.page_size
    and r.rn <= a.page_no*a.page_size
),
company_week as (
  select
    u.company_id,
    u.usage_week,
    coalesce(sum(u.events) filter(where u.module='ap'),0)::bigint ap,
    coalesce(sum(u.events) filter(where u.module='ar'),0)::bigint ar,
    coalesce(sum(u.events) filter(where u.module='transactions'),0)::bigint transactions,
    coalesce(sum(u.events) filter(where u.module='gst'),0)::bigint gst
  from metrics_private.company_lifecycle_week_module_usage u
  join paged p using (company_id)
  group by u.company_id,u.usage_week
),
user_week as (
  select
    u.company_id,u.user_key,u.usage_week,
    coalesce(sum(u.events) filter(where u.module='ap'),0)::bigint ap,
    coalesce(sum(u.events) filter(where u.module='ar'),0)::bigint ar,
    coalesce(sum(u.events) filter(where u.module='transactions'),0)::bigint transactions,
    coalesce(sum(u.events) filter(where u.module='gst'),0)::bigint gst
  from metrics_private.company_lifecycle_week_module_usage u
  join paged p using (company_id)
  group by u.company_id,u.user_key,u.usage_week
),
user_population as (
  select u.company_id,u.user_key,coalesce(u.user_email,u.user_key) user_email
  from metrics_private.company_lifecycle_user u
  join paged p using(company_id)
  union
  select uw.company_id,uw.user_key,'Unattributed activity'
  from user_week uw
  where uw.user_key='__unattributed__'
),
meta as (
  select
    m.*,
    coalesce(m.source_watermark_at,m.refreshed_at) as as_of_at
  from metrics_private.company_lifecycle_meta m
  where m.singleton=true
  limit 1
),
rows_with_weeks as (
  select
    p.*,
    (
      select jsonb_agg(
        jsonb_build_object(
          'week', w.week_no,
          'reached', m.as_of_at >= p.integration_at + make_interval(days => (w.week_no-1)*7),
          'totals', jsonb_build_object(
            'ap', coalesce(cw.ap,0),
            'ar', coalesce(cw.ar,0),
            'transactions', coalesce(cw.transactions,0),
            'gst', coalesce(cw.gst,0)
          )
        )
        order by w.week_no
      )
      from generate_series(1,4) w(week_no)
      cross join meta m
      left join company_week cw
        on cw.company_id=p.company_id and cw.usage_week=w.week_no
    ) as weeks,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', up.user_key,
          'email', up.user_email,
          'weeks', (
            select jsonb_agg(
              jsonb_build_object(
                'week', w.week_no,
                'reached', m.as_of_at >= p.integration_at + make_interval(days => (w.week_no-1)*7),
                'totals', jsonb_build_object(
                  'ap', coalesce(uw.ap,0),
                  'ar', coalesce(uw.ar,0),
                  'transactions', coalesce(uw.transactions,0),
                  'gst', coalesce(uw.gst,0)
                )
              )
              order by w.week_no
            )
            from generate_series(1,4) w(week_no)
            cross join meta m
            left join user_week uw
              on uw.company_id=up.company_id
             and uw.user_key=up.user_key
             and uw.usage_week=w.week_no
          )
        )
        order by (up.user_key='__unattributed__'),lower(up.user_email),up.user_key
      )
      from user_population up
      where up.company_id=p.company_id
    ),'[]'::jsonb) as users
  from paged p
)
select jsonb_build_object(
  'rows',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id',r.company_id,
        'name',r.company_name,
        'integration',r.integration,
        'integration_at',r.integration_at,
        'is_test',r.is_test,
        'weeks',r.weeks,
        'users',r.users
      )
      order by r.rn
    )
    from rows_with_weeks r
  ),'[]'::jsonb),
  'total',(select count(*) from filtered),
  'page',(select page_no from args),
  'page_size',(select page_size from args),
  'data_start',(select first_integration_date from meta),
  'data_end',(select latest_integration_date from meta),
  'source_watermark_at',(select source_watermark_at from meta)
);
$function$;

create or replace function public.read_companies_lifecycle_breakdown(
  p_company_id text,
  p_module text,
  p_user_key text default null,
  p_usage_week smallint default 1
)
returns table(
  event text,
  subtype text,
  status text,
  events bigint,
  items bigint,
  instrumented bigint,
  latest_at timestamptz,
  window_start timestamptz,
  window_end timestamptz
)
language sql
stable
security definer
set search_path = public, metrics_private, pg_temp
set statement_timeout = '5s'
as $function$
with anchor as (
  select
    i.integration_at + make_interval(days => (greatest(least(p_usage_week,4),1)-1)*7) as start_at,
    i.integration_at + make_interval(days => greatest(least(p_usage_week,4),1)*7) as end_at
  from metrics_private.company_lifecycle_identity i
  where i.company_id=p_company_id
),
classified as (
  select
    e.event_name as event,
    public.company_subtype_for(e.event_name,coalesce(e.properties,'{}'::jsonb)) as subtype,
    nullif(btrim(coalesce(e.properties,'{}'::jsonb)->>'status'),'') as status,
    public.company_items_for(e.event_name,coalesce(e.properties,'{}'::jsonb)) as items,
    e.event_time,
    a.start_at,
    a.end_at
  from public.events e
  cross join anchor a
  where e.company_id=p_company_id
    and e.event_time>=a.start_at
    and e.event_time<a.end_at
    and not public.is_internal_email(e.email)
    and public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb))=p_module
    and p_module in ('ap','ar','transactions','gst')
    and (
      p_user_key is null
      or (p_user_key='' and nullif(btrim(e.distinct_id),'') is null)
      or (p_user_key<>'' and e.distinct_id=p_user_key)
    )
)
select
  c.event,c.subtype,c.status,count(*)::bigint,
  sum(c.items),count(c.items)::bigint,max(c.event_time),
  min(c.start_at),min(c.end_at)
from classified c
group by c.event,c.subtype,c.status
order by count(*) desc,c.event,c.subtype nulls first,c.status nulls first;
$function$;

create or replace function public.read_companies_lifecycle_identity(
  p_company_id text,
  p_user_key text default null
)
returns jsonb
language sql
stable
security definer
set search_path = public, metrics_private, pg_temp
set statement_timeout = '2s'
as $function$
select jsonb_build_object(
  'company_name',coalesce(i.company_name,p_company_id),
  'integration_at',i.integration_at,
  'user_label',case
    when p_user_key is null then null
    when p_user_key='__unattributed__' then 'Unattributed activity'
    else coalesce(u.user_email,p_user_key)
  end
)
from (select 1) seed
left join metrics_private.company_lifecycle_identity i on i.company_id=p_company_id
left join metrics_private.company_lifecycle_user u
  on u.company_id=p_company_id and u.user_key=p_user_key
limit 1;
$function$;

revoke all on function public.refresh_companies_lifecycle_cache() from public,anon,authenticated;
revoke all on function public.read_companies_lifecycle_page(date,date,text,text,text,text,text,integer,integer) from public,anon,authenticated;
revoke all on function public.read_companies_lifecycle_breakdown(text,text,text,smallint) from public,anon,authenticated;
revoke all on function public.read_companies_lifecycle_identity(text,text) from public,anon,authenticated;

grant execute on function public.refresh_companies_lifecycle_cache() to service_role;
grant execute on function public.read_companies_lifecycle_page(date,date,text,text,text,text,text,integer,integer) to service_role,product_metrics_fetcher;
grant execute on function public.read_companies_lifecycle_breakdown(text,text,text,smallint) to service_role,product_metrics_fetcher;
grant execute on function public.read_companies_lifecycle_identity(text,text) to service_role,product_metrics_fetcher;

select public.refresh_companies_lifecycle_cache();

do $job$
declare existing_job bigint;
begin
  select jobid into existing_job
  from cron.job
  where jobname='companies-lifecycle-cache-hourly'
  limit 1;
  if existing_job is not null then
    perform cron.unschedule(existing_job);
  end if;
  perform cron.schedule(
    'companies-lifecycle-cache-hourly',
    '16 * * * *',
    'select public.refresh_companies_lifecycle_cache();'
  );
end;
$job$;
