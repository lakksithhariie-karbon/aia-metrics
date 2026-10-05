-- Fast Companies reporting cache.
-- Raw events are compacted hourly into month-grain facts so page/search/sort
-- never rescan the warehouse. All tables live in an unexposed private schema.

create schema if not exists metrics_private;
revoke all on schema metrics_private from public;
revoke all on schema metrics_private from anon, authenticated;

create table if not exists metrics_private.company_month_module_usage (
  company_id text not null,
  user_key text not null,
  month_start date not null,
  module text not null check (module in ('ap','ar','transactions','gst','sync')),
  events bigint not null check (events >= 0),
  primary key (company_id, user_key, month_start, module)
);

create table if not exists metrics_private.company_observed_user (
  company_id text not null,
  user_key text not null,
  user_email text,
  first_seen_at timestamptz not null,
  last_seen_at timestamptz not null,
  primary key (company_id, user_key)
);

create table if not exists metrics_private.company_reporting_identity (
  company_id text primary key,
  company_name text not null,
  is_test boolean not null default false,
  integration text not null default 'Unknown'
);

create table if not exists metrics_private.company_reporting_meta (
  singleton boolean primary key default true check (singleton),
  data_start date,
  data_end date,
  source_watermark_at timestamptz,
  refreshed_at timestamptz not null
);

create index if not exists company_month_module_usage_month_idx
  on metrics_private.company_month_module_usage (month_start, company_id);
create index if not exists company_observed_user_email_idx
  on metrics_private.company_observed_user (lower(user_email));

revoke all on all tables in schema metrics_private from public, anon, authenticated;

create or replace function public.refresh_companies_fast_cache()
returns jsonb
language plpgsql
security definer
set search_path = public, metrics_private, pg_temp
set statement_timeout = '90s'
as $function$
declare
  v_usage_rows bigint;
  v_user_rows bigint;
  v_company_rows bigint;
  v_watermark timestamptz;
begin
  delete from metrics_private.company_month_module_usage;

  insert into metrics_private.company_month_module_usage (
    company_id, user_key, month_start, module, events
  )
  with classified as (
    select
      e.company_id,
      coalesce(nullif(btrim(e.distinct_id), ''), '__unattributed__') as user_key,
      date_trunc('month', e.event_time at time zone 'Asia/Kolkata')::date as month_start,
      public.company_module_for(e.event_name, coalesce(e.properties, '{}'::jsonb)) as module
    from public.events e
    join public.client_company c on c.company_id = e.company_id
    where not public.is_internal_email(e.email)
  )
  select company_id, user_key, month_start, module, count(*)::bigint
  from classified
  where module is not null
  group by company_id, user_key, month_start, module;

  get diagnostics v_usage_rows = row_count;

  delete from metrics_private.company_observed_user;

  insert into metrics_private.company_observed_user (
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
  join public.client_company c on c.company_id = e.company_id
  where nullif(btrim(e.distinct_id), '') is not null
    and not public.is_internal_email(e.email)
  group by e.company_id, nullif(btrim(e.distinct_id), '');

  get diagnostics v_user_rows = row_count;

  delete from metrics_private.company_reporting_identity;

  insert into metrics_private.company_reporting_identity (
    company_id, company_name, is_test, integration
  )
  with event_names as (
    select distinct on (e.company_id)
      e.company_id,
      public.company_usable_name(e.properties ->> 'companyName') as company_name
    from public.events e
    join public.client_company c on c.company_id = e.company_id
    where e.properties ? 'companyName'
      and public.company_usable_name(e.properties ->> 'companyName') is not null
    order by e.company_id, e.event_time desc, e.insert_id desc
  ),
  integrations as (
    select distinct on (e.company_id)
      e.company_id,
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
    order by e.company_id, e.event_time desc, e.insert_id desc
  )
  select
    c.company_id,
    coalesce(nullif(btrim(d.company_name), ''), n.company_name, c.company_id),
    coalesce(d.is_test, false),
    coalesce(i.integration, 'Unknown')
  from public.client_company c
  left join public.company_directory d on d.company_uuid::text = c.company_id
  left join event_names n on n.company_id = c.company_id
  left join integrations i on i.company_id = c.company_id;

  get diagnostics v_company_rows = row_count;

  select w.last_success_at
    into v_watermark
  from public.export_watermarks w
  where w.job_name = 'incremental' and w.status = 'ok'
  order by w.last_success_at desc
  limit 1;

  delete from metrics_private.company_reporting_meta;
  insert into metrics_private.company_reporting_meta (
    singleton, data_start, data_end, source_watermark_at, refreshed_at
  )
  select
    true,
    min(e.event_time at time zone 'Asia/Kolkata')::date,
    max(e.event_time at time zone 'Asia/Kolkata')::date,
    v_watermark,
    now()
  from public.events e;

  return jsonb_build_object(
    'usage_rows', v_usage_rows,
    'user_rows', v_user_rows,
    'company_rows', v_company_rows,
    'source_watermark_at', v_watermark,
    'refreshed_at', now()
  );
end;
$function$;

create or replace function public.read_companies_page_fast(
  p_from date default null,
  p_to date default null,
  p_query text default '',
  p_usage text default 'all',
  p_integration text default 'all',
  p_sort text default 'name',
  p_direction text default 'asc',
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
    greatest(coalesce(p_page, 1), 1) as page_no,
    least(greatest(coalesce(p_page_size, 10), 1), 50) as page_size,
    lower(btrim(coalesce(p_query, ''))) as q,
    case when p_usage in ('active','inactive') then p_usage else 'all' end as usage_filter,
    case when p_integration in ('Tally','Zoho Books','Unknown') then p_integration else 'all' end as integration_filter,
    case when p_sort in ('ap','ar','transactions','gst','sync') then p_sort else 'name' end as sort_key,
    case when lower(coalesce(p_direction, '')) = 'desc' then 'desc' else 'asc' end as sort_direction,
    case when p_from is null then null else date_trunc('month', p_from)::date end as from_month,
    case when p_to is null then null else date_trunc('month', p_to)::date end as to_month
),
company_usage as (
  select
    u.company_id,
    coalesce(sum(u.events) filter (where u.module='ap'),0)::bigint as ap,
    coalesce(sum(u.events) filter (where u.module='ar'),0)::bigint as ar,
    coalesce(sum(u.events) filter (where u.module='transactions'),0)::bigint as transactions,
    coalesce(sum(u.events) filter (where u.module='gst'),0)::bigint as gst,
    coalesce(sum(u.events) filter (where u.module='sync'),0)::bigint as sync
  from metrics_private.company_month_module_usage u
  cross join args a
  where (a.from_month is null or u.month_start >= a.from_month)
    and (a.to_month is null or u.month_start <= a.to_month)
  group by u.company_id
),
base as (
  select
    i.company_id,
    i.company_name,
    i.is_test,
    i.integration,
    coalesce(u.ap,0)::bigint as ap,
    coalesce(u.ar,0)::bigint as ar,
    coalesce(u.transactions,0)::bigint as transactions,
    coalesce(u.gst,0)::bigint as gst,
    coalesce(u.sync,0)::bigint as sync
  from metrics_private.company_reporting_identity i
  left join company_usage u using (company_id)
),
filtered as (
  select b.*
  from base b
  cross join args a
  where (
    a.q = ''
    or lower(b.company_name) like '%' || a.q || '%'
    or exists (
      select 1
      from metrics_private.company_observed_user ou
      where ou.company_id=b.company_id
        and lower(coalesce(ou.user_email, ou.user_key)) like '%' || a.q || '%'
    )
  )
  and (a.integration_filter='all' or b.integration=a.integration_filter)
  and (
    a.usage_filter='all'
    or (a.usage_filter='active' and b.ap+b.ar+b.transactions+b.gst+b.sync > 0)
    or (a.usage_filter='inactive' and b.ap+b.ar+b.transactions+b.gst+b.sync = 0)
  )
),
ranked as (
  select
    f.*,
    row_number() over (
      order by
        case when a.sort_key='name' and a.sort_direction='asc' then lower(f.company_name) end asc,
        case when a.sort_key='name' and a.sort_direction='desc' then lower(f.company_name) end desc,
        case when a.sort_key='ap' and a.sort_direction='asc' then f.ap end asc,
        case when a.sort_key='ap' and a.sort_direction='desc' then f.ap end desc,
        case when a.sort_key='ar' and a.sort_direction='asc' then f.ar end asc,
        case when a.sort_key='ar' and a.sort_direction='desc' then f.ar end desc,
        case when a.sort_key='transactions' and a.sort_direction='asc' then f.transactions end asc,
        case when a.sort_key='transactions' and a.sort_direction='desc' then f.transactions end desc,
        case when a.sort_key='gst' and a.sort_direction='asc' then f.gst end asc,
        case when a.sort_key='gst' and a.sort_direction='desc' then f.gst end desc,
        case when a.sort_key='sync' and a.sort_direction='asc' then f.sync end asc,
        case when a.sort_key='sync' and a.sort_direction='desc' then f.sync end desc,
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
  where r.rn > (a.page_no - 1) * a.page_size
    and r.rn <= a.page_no * a.page_size
),
user_usage as (
  select
    u.company_id,
    u.user_key,
    coalesce(sum(u.events) filter (where u.module='ap'),0)::bigint as ap,
    coalesce(sum(u.events) filter (where u.module='ar'),0)::bigint as ar,
    coalesce(sum(u.events) filter (where u.module='transactions'),0)::bigint as transactions,
    coalesce(sum(u.events) filter (where u.module='gst'),0)::bigint as gst,
    coalesce(sum(u.events) filter (where u.module='sync'),0)::bigint as sync
  from metrics_private.company_month_module_usage u
  join paged p using (company_id)
  cross join args a
  where (a.from_month is null or u.month_start >= a.from_month)
    and (a.to_month is null or u.month_start <= a.to_month)
  group by u.company_id, u.user_key
),
user_population as (
  select ou.company_id, ou.user_key, coalesce(ou.user_email, ou.user_key) as user_email
  from metrics_private.company_observed_user ou
  join paged p using (company_id)
  union
  select uu.company_id, uu.user_key, 'Unattributed activity'
  from user_usage uu
  where uu.user_key='__unattributed__'
),
rows_with_users as (
  select
    p.*,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', up.user_key,
          'email', up.user_email,
          'totals', jsonb_build_object(
            'ap', coalesce(uu.ap,0),
            'ar', coalesce(uu.ar,0),
            'transactions', coalesce(uu.transactions,0),
            'gst', coalesce(uu.gst,0),
            'sync', coalesce(uu.sync,0)
          )
        )
        order by (up.user_key='__unattributed__'), lower(up.user_email), up.user_key
      )
      from user_population up
      left join user_usage uu
        on uu.company_id=up.company_id and uu.user_key=up.user_key
      where up.company_id=p.company_id
    ), '[]'::jsonb) as users
  from paged p
),
meta as (
  select * from metrics_private.company_reporting_meta where singleton=true limit 1
)
select jsonb_build_object(
  'rows', coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', r.company_id,
        'name', r.company_name,
        'integration', r.integration,
        'is_test', r.is_test,
        'totals', jsonb_build_object(
          'ap', r.ap,
          'ar', r.ar,
          'transactions', r.transactions,
          'gst', r.gst,
          'sync', r.sync
        ),
        'users', r.users
      )
      order by r.rn
    )
    from rows_with_users r
  ), '[]'::jsonb),
  'total', (select count(*) from filtered),
  'page', (select page_no from args),
  'page_size', (select page_size from args),
  'available', coalesce((
    select
      case
        when p_from is null and p_to is null then true
        else m.data_start is not null and m.data_end is not null
          and (p_to is null or p_to >= m.data_start)
          and (p_from is null or p_from <= m.data_end)
      end
    from meta m
  ), false),
  'data_start', (select data_start from meta),
  'data_end', (select data_end from meta),
  'source_watermark_at', (select source_watermark_at from meta),
  'cache_refreshed_at', (select refreshed_at from meta)
);
$function$;

create or replace function public.read_companies_identity_fast(
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
  'company_name', coalesce(i.company_name, p_company_id),
  'user_label', case
    when p_user_key is null then null
    when p_user_key='__unattributed__' then 'Unattributed activity'
    else coalesce(u.user_email, p_user_key)
  end
)
from (select 1) seed
left join metrics_private.company_reporting_identity i
  on i.company_id=p_company_id
left join metrics_private.company_observed_user u
  on u.company_id=p_company_id and u.user_key=p_user_key
limit 1;
$function$;

revoke all on function public.refresh_companies_fast_cache() from public, anon, authenticated;
revoke all on function public.read_companies_page_fast(date,date,text,text,text,text,text,integer,integer) from public, anon, authenticated;
revoke all on function public.read_companies_identity_fast(text,text) from public, anon, authenticated;

grant execute on function public.refresh_companies_fast_cache() to service_role;
grant execute on function public.read_companies_page_fast(date,date,text,text,text,text,text,integer,integer) to service_role, product_metrics_fetcher;
grant execute on function public.read_companies_identity_fast(text,text) to service_role, product_metrics_fetcher;

select public.refresh_companies_fast_cache();

do $job$
declare existing_job bigint;
begin
  select jobid into existing_job from cron.job where jobname='companies-fast-cache-hourly' limit 1;
  if existing_job is not null then
    perform cron.unschedule(existing_job);
  end if;
  perform cron.schedule(
    'companies-fast-cache-hourly',
    '12 * * * *',
    'select public.refresh_companies_fast_cache();'
  );
end;
$job$;
