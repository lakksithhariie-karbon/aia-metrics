-- Companies calendar-month cohort reporting.
-- Population: companies whose FIRST successful integration month is in the selected range.
-- Usage: AP/AR/TXN/GST events by Asia/Kolkata calendar month, never before integration.

create table if not exists metrics_private.company_monthly_identity (
  company_id text primary key,
  company_name text not null,
  is_test boolean not null default false,
  integration text not null default 'Unknown',
  integration_at timestamptz not null,
  integration_month date not null
);

create table if not exists metrics_private.company_monthly_user (
  company_id text not null,
  user_key text not null,
  user_email text,
  first_seen_at timestamptz not null,
  last_seen_at timestamptz not null,
  primary key (company_id, user_key)
);

create table if not exists metrics_private.company_calendar_month_module_usage (
  company_id text not null,
  user_key text not null,
  usage_month date not null,
  module text not null check (module in ('ap','ar','transactions','gst')),
  events bigint not null check (events >= 0),
  primary key (company_id, user_key, usage_month, module)
);

create table if not exists metrics_private.company_monthly_meta (
  singleton boolean primary key default true check (singleton),
  first_integration_month date,
  data_month date,
  source_watermark_at timestamptz,
  refreshed_at timestamptz not null
);

create index if not exists company_monthly_identity_month_idx
  on metrics_private.company_monthly_identity (integration_month desc, integration_at desc, company_id);
create index if not exists company_monthly_user_email_idx
  on metrics_private.company_monthly_user (lower(user_email));
create index if not exists company_calendar_month_usage_month_idx
  on metrics_private.company_calendar_month_module_usage (usage_month, company_id);

revoke all on metrics_private.company_monthly_identity from public, anon, authenticated;
revoke all on metrics_private.company_monthly_user from public, anon, authenticated;
revoke all on metrics_private.company_calendar_month_module_usage from public, anon, authenticated;
revoke all on metrics_private.company_monthly_meta from public, anon, authenticated;

create or replace function public.refresh_companies_monthly_cache()
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
  delete from metrics_private.company_monthly_identity;

  insert into metrics_private.company_monthly_identity (
    company_id, company_name, is_test, integration, integration_at, integration_month
  )
  with first_integration as (
    select distinct on (e.company_id)
      e.company_id,
      e.event_time as integration_at,
      date_trunc('month', e.event_time at time zone 'Asia/Kolkata')::date as integration_month,
      case lower(btrim(coalesce(e.properties ->> 'type', '')))
        when 'tally' then 'Tally'
        when 'zoho' then 'Zoho Books'
        when 'zoho books' then 'Zoho Books'
        else 'Unknown'
      end as integration
    from public.events e
    join public.client_company c on c.company_id=e.company_id
    where e.event_name='Integration status'
      and lower(btrim(coalesce(e.properties ->> 'status',''))) in ('success','successful')
      and nullif(btrim(e.company_id),'') is not null
    order by e.company_id, e.event_time asc, e.insert_id asc
  ),
  event_names as (
    select distinct on (e.company_id)
      e.company_id,
      public.company_usable_name(e.properties ->> 'companyName') as company_name
    from public.events e
    join public.client_company c on c.company_id=e.company_id
    where e.properties ? 'companyName'
      and public.company_usable_name(e.properties ->> 'companyName') is not null
    order by e.company_id, e.event_time desc, e.insert_id desc
  )
  select
    c.company_id,
    coalesce(nullif(btrim(d.company_name),''),n.company_name,c.company_id),
    coalesce(d.is_test,false),
    fi.integration,
    fi.integration_at,
    fi.integration_month
  from public.client_company c
  join first_integration fi on fi.company_id=c.company_id
  left join public.company_directory d on d.company_uuid::text=c.company_id
  left join event_names n on n.company_id=c.company_id;

  get diagnostics v_company_rows = row_count;

  delete from metrics_private.company_monthly_user;

  insert into metrics_private.company_monthly_user (
    company_id,user_key,user_email,first_seen_at,last_seen_at
  )
  select
    e.company_id,
    nullif(btrim(e.distinct_id),'') as user_key,
    (
      array_agg(nullif(btrim(e.email),'') order by e.event_time desc,e.insert_id desc)
      filter (where nullif(btrim(e.email),'') is not null)
    )[1] as user_email,
    min(e.event_time),
    max(e.event_time)
  from public.events e
  join metrics_private.company_monthly_identity i on i.company_id=e.company_id
  where e.event_time>=i.integration_at
    and nullif(btrim(e.distinct_id),'') is not null
    and not public.is_internal_email(e.email)
  group by e.company_id,nullif(btrim(e.distinct_id),'');

  get diagnostics v_user_rows = row_count;

  delete from metrics_private.company_calendar_month_module_usage;

  insert into metrics_private.company_calendar_month_module_usage (
    company_id,user_key,usage_month,module,events
  )
  with classified as (
    select
      e.company_id,
      coalesce(nullif(btrim(e.distinct_id),''),'__unattributed__') as user_key,
      date_trunc('month',e.event_time at time zone 'Asia/Kolkata')::date as usage_month,
      public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb)) as module
    from public.events e
    join metrics_private.company_monthly_identity i on i.company_id=e.company_id
    where e.event_time>=i.integration_at
      and not public.is_internal_email(e.email)
  )
  select company_id,user_key,usage_month,module,count(*)::bigint
  from classified
  where module in ('ap','ar','transactions','gst')
  group by company_id,user_key,usage_month,module;

  get diagnostics v_usage_rows = row_count;

  select w.last_success_at
    into v_watermark
  from public.export_watermarks w
  where w.job_name='incremental' and w.status='ok'
  order by w.last_success_at desc
  limit 1;

  delete from metrics_private.company_monthly_meta;

  insert into metrics_private.company_monthly_meta (
    singleton,first_integration_month,data_month,source_watermark_at,refreshed_at
  )
  select
    true,
    min(i.integration_month),
    date_trunc(
      'month',
      coalesce(v_watermark,now()) at time zone 'Asia/Kolkata'
    )::date,
    v_watermark,
    now()
  from metrics_private.company_monthly_identity i;

  return jsonb_build_object(
    'company_rows',v_company_rows,
    'user_rows',v_user_rows,
    'usage_rows',v_usage_rows,
    'source_watermark_at',v_watermark,
    'refreshed_at',now()
  );
end;
$function$;

create or replace function public.read_companies_monthly_grid(
  p_from date default null,
  p_to date default null,
  p_query text default '',
  p_usage text default 'all',
  p_integration text default 'all',
  p_sort text default 'integration_month',
  p_direction text default 'desc',
  p_page integer default 1,
  p_page_size integer default 5000
)
returns jsonb
language sql
stable
security definer
set search_path = public, metrics_private, pg_temp
set statement_timeout = '8s'
as $function$
with meta as (
  select *
  from metrics_private.company_monthly_meta
  where singleton=true
  limit 1
),
args as (
  select
    greatest(coalesce(p_page,1),1) as page_no,
    least(greatest(coalesce(p_page_size,5000),1),5000) as page_size,
    lower(btrim(coalesce(p_query,''))) as q,
    case when p_usage in ('active','inactive') then p_usage else 'all' end as usage_filter,
    case when p_integration in ('Tally','Zoho Books','Unknown') then p_integration else 'all' end as integration_filter,
    case when p_sort='name' then 'name' else 'integration_month' end as sort_key,
    case when lower(coalesce(p_direction,''))='asc' then 'asc' else 'desc' end as sort_direction,
    date_trunc(
      'month',
      coalesce(p_from,(select data_month from meta),current_date)::timestamp
    )::date as from_month,
    date_trunc(
      'month',
      coalesce(p_to,p_from,(select data_month from meta),current_date)::timestamp
    )::date as to_month
),
normalized as (
  select
    a.*,
    least(a.from_month,a.to_month) as range_start,
    greatest(a.from_month,a.to_month) as range_end
  from args a
),
selected_months as (
  select gs::date as month_start
  from normalized a
  cross join lateral generate_series(
    a.range_start::timestamp,
    a.range_end::timestamp,
    interval '1 month'
  ) gs
),
company_usage as (
  select
    u.company_id,
    sum(u.events)::bigint as total_events
  from metrics_private.company_calendar_month_module_usage u
  cross join normalized a
  where u.usage_month between a.range_start and a.range_end
  group by u.company_id
),
filtered as (
  select
    i.company_id,i.company_name,i.is_test,i.integration,i.integration_at,i.integration_month,
    coalesce(cu.total_events,0)::bigint as total_events
  from metrics_private.company_monthly_identity i
  left join company_usage cu using(company_id)
  cross join normalized a
  where i.integration_month between a.range_start and a.range_end
    and (
      a.q=''
      or lower(i.company_name) like '%' || a.q || '%'
      or exists (
        select 1
        from metrics_private.company_monthly_user u
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
        case when a.sort_key='integration_month' and a.sort_direction='asc' then f.integration_month end asc,
        case when a.sort_key='integration_month' and a.sort_direction='desc' then f.integration_month end desc,
        case when a.sort_key='integration_month' and a.sort_direction='asc' then f.integration_at end asc,
        case when a.sort_key='integration_month' and a.sort_direction='desc' then f.integration_at end desc,
        case when a.sort_key='name' and a.sort_direction='asc' then lower(f.company_name) end asc,
        case when a.sort_key='name' and a.sort_direction='desc' then lower(f.company_name) end desc,
        case when a.sort_direction='asc' then f.company_id end asc,
        case when a.sort_direction='desc' then f.company_id end desc
    ) as rn
  from filtered f
  cross join normalized a
),
paged as (
  select r.*
  from ranked r
  cross join normalized a
  where r.rn>(a.page_no-1)*a.page_size
    and r.rn<=a.page_no*a.page_size
),
company_month as (
  select
    u.company_id,u.usage_month,
    coalesce(sum(u.events) filter(where u.module='ap'),0)::bigint as ap,
    coalesce(sum(u.events) filter(where u.module='ar'),0)::bigint as ar,
    coalesce(sum(u.events) filter(where u.module='transactions'),0)::bigint as transactions,
    coalesce(sum(u.events) filter(where u.module='gst'),0)::bigint as gst
  from metrics_private.company_calendar_month_module_usage u
  join paged p using(company_id)
  cross join normalized a
  where u.usage_month between a.range_start and a.range_end
  group by u.company_id,u.usage_month
),
user_month as (
  select
    u.company_id,u.user_key,u.usage_month,
    coalesce(sum(u.events) filter(where u.module='ap'),0)::bigint as ap,
    coalesce(sum(u.events) filter(where u.module='ar'),0)::bigint as ar,
    coalesce(sum(u.events) filter(where u.module='transactions'),0)::bigint as transactions,
    coalesce(sum(u.events) filter(where u.module='gst'),0)::bigint as gst
  from metrics_private.company_calendar_month_module_usage u
  join paged p using(company_id)
  cross join normalized a
  where u.usage_month between a.range_start and a.range_end
  group by u.company_id,u.user_key,u.usage_month
),
user_population as (
  select u.company_id,u.user_key,coalesce(u.user_email,u.user_key) as user_email
  from metrics_private.company_monthly_user u
  join paged p using(company_id)
  union
  select um.company_id,um.user_key,'Unattributed activity'
  from user_month um
  where um.user_key='__unattributed__'
),
rows_with_months as (
  select
    p.*,
    (
      select jsonb_agg(
        jsonb_build_object(
          'month',sm.month_start,
          'available',sm.month_start>=p.integration_month,
          'totals',jsonb_build_object(
            'ap',coalesce(cm.ap,0),
            'ar',coalesce(cm.ar,0),
            'transactions',coalesce(cm.transactions,0),
            'gst',coalesce(cm.gst,0)
          )
        )
        order by sm.month_start
      )
      from selected_months sm
      left join company_month cm
        on cm.company_id=p.company_id and cm.usage_month=sm.month_start
    ) as months,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',up.user_key,
          'email',up.user_email,
          'months',(
            select jsonb_agg(
              jsonb_build_object(
                'month',sm.month_start,
                'available',sm.month_start>=p.integration_month,
                'totals',jsonb_build_object(
                  'ap',coalesce(um.ap,0),
                  'ar',coalesce(um.ar,0),
                  'transactions',coalesce(um.transactions,0),
                  'gst',coalesce(um.gst,0)
                )
              )
              order by sm.month_start
            )
            from selected_months sm
            left join user_month um
              on um.company_id=up.company_id
             and um.user_key=up.user_key
             and um.usage_month=sm.month_start
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
  'months',coalesce((
    select jsonb_agg(sm.month_start order by sm.month_start)
    from selected_months sm
  ),'[]'::jsonb),
  'rows',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id',r.company_id,
        'name',r.company_name,
        'integration',r.integration,
        'integration_at',r.integration_at,
        'integration_month',r.integration_month,
        'is_test',r.is_test,
        'months',r.months,
        'users',r.users
      )
      order by r.rn
    )
    from rows_with_months r
  ),'[]'::jsonb),
  'total',(select count(*) from filtered),
  'data_start',(select first_integration_month from meta),
  'data_end',(select data_month from meta),
  'source_watermark_at',(select source_watermark_at from meta)
);
$function$;

create or replace function public.read_companies_monthly_breakdown(
  p_company_id text,
  p_module text,
  p_user_key text default null,
  p_usage_month date default null
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
with identity as (
  select i.integration_at,i.integration_month
  from metrics_private.company_monthly_identity i
  where i.company_id=p_company_id
),
month_window as (
  select
    date_trunc('month',coalesce(p_usage_month,current_date)::timestamp)::date as month_start
),
anchor as (
  select
    greatest(
      mw.month_start::timestamp at time zone 'Asia/Kolkata',
      i.integration_at
    ) as start_at,
    (mw.month_start + interval '1 month')::timestamp at time zone 'Asia/Kolkata' as end_at,
    mw.month_start,
    i.integration_month
  from identity i
  cross join month_window mw
  where mw.month_start>=i.integration_month
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

create or replace function public.read_companies_monthly_identity(
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
  'integration_month',i.integration_month,
  'user_label',case
    when p_user_key is null then null
    when p_user_key='__unattributed__' then 'Unattributed activity'
    else coalesce(u.user_email,p_user_key)
  end
)
from (select 1) seed
left join metrics_private.company_monthly_identity i on i.company_id=p_company_id
left join metrics_private.company_monthly_user u
  on u.company_id=p_company_id and u.user_key=p_user_key
limit 1;
$function$;

revoke all on function public.refresh_companies_monthly_cache() from public,anon,authenticated;
revoke all on function public.read_companies_monthly_grid(date,date,text,text,text,text,text,integer,integer) from public,anon,authenticated;
revoke all on function public.read_companies_monthly_breakdown(text,text,text,date) from public,anon,authenticated;
revoke all on function public.read_companies_monthly_identity(text,text) from public,anon,authenticated;

grant execute on function public.refresh_companies_monthly_cache() to service_role;
grant execute on function public.read_companies_monthly_grid(date,date,text,text,text,text,text,integer,integer) to service_role,product_metrics_fetcher;
grant execute on function public.read_companies_monthly_breakdown(text,text,text,date) to service_role,product_metrics_fetcher;
grant execute on function public.read_companies_monthly_identity(text,text) to service_role,product_metrics_fetcher;

select public.refresh_companies_monthly_cache();

do $job$
declare old_job bigint;
declare current_job bigint;
begin
  select jobid into old_job from cron.job where jobname='companies-fast-cache-hourly' limit 1;
  if old_job is not null then perform cron.unschedule(old_job); end if;

  select jobid into old_job from cron.job where jobname='companies-lifecycle-cache-hourly' limit 1;
  if old_job is not null then perform cron.unschedule(old_job); end if;

  select jobid into current_job from cron.job where jobname='companies-monthly-cache-hourly' limit 1;
  if current_job is not null then perform cron.unschedule(current_job); end if;

  perform cron.schedule(
    'companies-monthly-cache-hourly',
    '16 * * * *',
    'select public.refresh_companies_monthly_cache();'
  );
end;
$job$;
