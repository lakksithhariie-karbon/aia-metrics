-- Preview-only retention activation drill read path.
-- Additive, service-role-only RPCs. No production UI calls these until approved.

create or replace function public.read_retention_activation_drill_page_v1(
  p_from date default null,
  p_to date default null,
  p_query text default '',
  p_status text default 'all',
  p_page integer default 1,
  p_page_size integer default 8
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
    least(greatest(coalesce(p_page_size,8),1),50) as page_size,
    lower(btrim(coalesce(p_query,''))) as q,
    case
      when p_status in ('activated','awaiting_sync','no_core','no_training') then p_status
      else 'all'
    end as status_filter
),
base as (
  select
    a.company_id,
    coalesce(i.company_name,a.company_id) as company_name,
    coalesce(i.is_test,false) as is_test,
    coalesce(i.integration,'Unknown') as integration,
    a.integration_at,
    a.training_sync_at,
    a.post_training_core_at,
    a.activated_at,
    case
      when a.activated_at is not null then 'activated'
      when a.post_training_core_at is not null then 'awaiting_sync'
      when a.training_sync_at is not null then 'no_core'
      else 'no_training'
    end as status
  from metrics_private.retention_activation_v2 a
  left join metrics_private.company_monthly_identity i using(company_id)
),
filtered as (
  select b.*
  from base b
  cross join args x
  where
    (p_from is null or (b.integration_at at time zone 'Asia/Kolkata')::date >= p_from)
    and (p_to is null or (b.integration_at at time zone 'Asia/Kolkata')::date <= p_to)
    and (x.status_filter='all' or b.status=x.status_filter)
    and (
      x.q=''
      or lower(b.company_name) like '%' || x.q || '%'
      or exists (
        select 1
        from metrics_private.company_monthly_user u
        where u.company_id=b.company_id
          and lower(coalesce(u.user_email,u.user_key)) like '%' || x.q || '%'
      )
    )
),
ranked as (
  select
    f.*,
    row_number() over(order by f.integration_at desc,f.company_id) as rn
  from filtered f
),
paged as (
  select r.*
  from ranked r
  cross join args x
  where r.rn>(x.page_no-1)*x.page_size
    and r.rn<=x.page_no*x.page_size
),
window_events as (
  select
    p.company_id,
    coalesce(nullif(btrim(e.distinct_id),''),'__unattributed__') as user_key,
    e.event_name,
    e.event_time,
    public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb)) as module
  from paged p
  join public.events e on e.company_id=p.company_id
  where p.training_sync_at is not null
    and e.event_time >= (
      (((p.training_sync_at at time zone 'Asia/Kolkata')::date + 1)::timestamp)
      at time zone 'Asia/Kolkata'
    )
    and (p.activated_at is null or e.event_time<=p.activated_at)
    and not metrics_private.is_retention_internal_email_v2(e.email)
),
mapped as (
  select *
  from window_events
  where module in ('ap','ar','transactions','gst')
),
company_totals as (
  select
    company_id,
    count(*) filter(where module='ap')::bigint as ap,
    count(*) filter(where module='ar')::bigint as ar,
    count(*) filter(where module='transactions')::bigint as transactions,
    count(*) filter(where module='gst')::bigint as gst
  from mapped
  group by company_id
),
user_totals as (
  select
    company_id,user_key,
    count(*) filter(where module='ap')::bigint as ap,
    count(*) filter(where module='ar')::bigint as ar,
    count(*) filter(where module='transactions')::bigint as transactions,
    count(*) filter(where module='gst')::bigint as gst
  from mapped
  group by company_id,user_key
),
rows_json as (
  select
    p.rn,
    jsonb_build_object(
      'id',p.company_id,
      'name',p.company_name,
      'is_test',p.is_test,
      'integration',p.integration,
      'integration_at',p.integration_at,
      'training_sync_at',p.training_sync_at,
      'post_training_core_at',p.post_training_core_at,
      'activated_at',p.activated_at,
      'status',p.status,
      'ttv_hours',case when p.activated_at is null then null else
        extract(epoch from (p.activated_at-p.integration_at))/3600.0 end,
      'totals',jsonb_build_object(
        'ap',coalesce(ct.ap,0),
        'ar',coalesce(ct.ar,0),
        'transactions',coalesce(ct.transactions,0),
        'gst',coalesce(ct.gst,0)
      ),
      'users',coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id',ut.user_key,
            'email',case
              when ut.user_key='__unattributed__' then 'Unattributed activity'
              else coalesce(mu.user_email,ut.user_key)
            end,
            'totals',jsonb_build_object(
              'ap',ut.ap,'ar',ut.ar,'transactions',ut.transactions,'gst',ut.gst
            )
          )
          order by (ut.user_key='__unattributed__'),lower(coalesce(mu.user_email,ut.user_key))
        )
        from user_totals ut
        left join metrics_private.company_monthly_user mu
          on mu.company_id=ut.company_id and mu.user_key=ut.user_key
        where ut.company_id=p.company_id
      ),'[]'::jsonb)
    ) as row
  from paged p
  left join company_totals ct using(company_id)
)
select jsonb_build_object(
  'rows',coalesce((select jsonb_agg(row order by rn) from rows_json),'[]'::jsonb),
  'total',(select count(*) from filtered),
  'page',(select page_no from args),
  'page_size',(select page_size from args)
);
$function$;

create or replace function public.read_retention_activation_company_detail_v1(
  p_company_id text
)
returns jsonb
language sql
stable
security definer
set search_path = public, metrics_private, pg_temp
set statement_timeout = '5s'
as $function$
with identity as (
  select
    a.company_id,
    coalesce(i.company_name,a.company_id) as company_name,
    coalesce(i.is_test,false) as is_test,
    coalesce(i.integration,'Unknown') as integration,
    a.integration_at,a.training_sync_at,a.post_training_core_at,a.activated_at
  from metrics_private.retention_activation_v2 a
  left join metrics_private.company_monthly_identity i using(company_id)
  where a.company_id=p_company_id
),
week_bounds as (
  select
    (date_trunc('week',now() at time zone 'Asia/Kolkata')::date - 56) as start_date,
    (date_trunc('week',now() at time zone 'Asia/Kolkata')::date - 1) as end_date
),
weeks as (
  select
    gs::date as week_start,
    (gs::date+6) as week_end
  from week_bounds b
  cross join lateral generate_series(
    b.start_date::timestamp,
    b.end_date::timestamp,
    interval '7 days'
  ) gs
),
company_events as (
  select e.*
  from public.events e
  join identity i on i.company_id=e.company_id
  where not metrics_private.is_retention_internal_email_v2(e.email)
),
signup as (
  select
    coalesce(
      min(event_time) filter(where event_name='Company Created'),
      min(event_time)
    ) as signup_at,
    case
      when min(event_time) filter(where event_name='Company Created') is not null
      then 'Company Created'
      else 'First seen'
    end as signup_kind
  from company_events
),
role_events as (
  select
    (
      select nullif(btrim(e.distinct_id),'')
      from company_events e,identity i
      where i.post_training_core_at is not null
        and e.event_time=i.post_training_core_at
      order by e.insert_id
      limit 1
    ) as core_user_key,
    (
      select nullif(btrim(e.distinct_id),'')
      from company_events e,identity i
      where i.activated_at is not null
        and e.event_time=i.activated_at
      order by e.insert_id
      limit 1
    ) as sync_user_key
),
recent_mapped as (
  select
    e.company_id,
    coalesce(nullif(btrim(e.distinct_id),''),'__unattributed__') as user_key,
    e.event_name,e.event_time,
    public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb)) as module
  from company_events e
  cross join week_bounds b
  where (e.event_time at time zone 'Asia/Kolkata')::date between b.start_date and b.end_date
    and public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb))
      in ('ap','ar','transactions','gst','sync')
),
week_usage as (
  select
    w.week_start,w.week_end,
    count(r.*) filter(where r.module='ap')::bigint as ap,
    count(r.*) filter(where r.module='ar')::bigint as ar,
    count(r.*) filter(where r.module='transactions')::bigint as transactions,
    count(r.*) filter(where r.module='gst')::bigint as gst,
    count(r.*) filter(where r.module='sync')::bigint as sync
  from weeks w
  left join recent_mapped r
    on (r.event_time at time zone 'Asia/Kolkata')::date between w.week_start and w.week_end
  group by w.week_start,w.week_end
),
user_recent as (
  select
    r.user_key,
    count(*) filter(where r.module='ap')::bigint as ap,
    count(*) filter(where r.module='ar')::bigint as ar,
    count(*) filter(where r.module='transactions')::bigint as transactions,
    count(*) filter(where r.module='gst')::bigint as gst,
    count(*) filter(where r.module='sync')::bigint as sync
  from recent_mapped r
  group by r.user_key
),
user_identity as (
  select
    u.user_key,
    coalesce(u.user_email,u.user_key) as user_email,
    u.first_seen_at,u.last_seen_at
  from metrics_private.company_monthly_user u
  where u.company_id=p_company_id
  union
  select
    '__unattributed__','Unattributed activity',
    min(event_time),max(event_time)
  from company_events
  where nullif(btrim(distinct_id),'') is null
    and public.company_module_for(event_name,coalesce(properties,'{}'::jsonb))
      in ('ap','ar','transactions','gst','sync')
  having count(*)>0
),
evidence_ranked as (
  select
    e.event_time as at,
    e.event_name as event,
    case public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb))
      when 'ap' then 'AP'
      when 'ar' then 'AR'
      when 'transactions' then 'Transaction'
      when 'gst' then 'GST'
      when 'sync' then 'Sync'
      else null
    end as module,
    coalesce(nullif(btrim(e.email),''),nullif(btrim(e.distinct_id),'')) as user_label,
    row_number() over(order by e.event_time,e.insert_id) as rn
  from company_events e
  cross join identity i
  where i.training_sync_at is not null
    and (e.event_time at time zone 'Asia/Kolkata')::date
        > (i.training_sync_at at time zone 'Asia/Kolkata')::date
    and (i.activated_at is null or e.event_time<=i.activated_at)
    and public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb))
        in ('ap','ar','transactions','gst','sync')
),
evidence as (
  select er.*
  from evidence_ranked er
  where er.rn<=9
  union all
  select er.*
  from evidence_ranked er
  cross join identity i
  where i.activated_at is not null
    and er.at=i.activated_at
    and er.rn>9
),
last_core as (
  select max(e.event_time) as last_core_activity_at
  from company_events e
  cross join identity i
  where (i.activated_at is null or e.event_time>=i.activated_at)
    and public.is_core_activity(e.event_name,coalesce(e.properties,'{}'::jsonb))
),
active_weeks as (
  select count(*)::bigint as n
  from week_usage
  where ap+ar+transactions+gst+sync>0
),
recent_total as (
  select coalesce(sum(ap+ar+transactions+gst+sync),0)::bigint as n
  from week_usage
)
select jsonb_build_object(
  'id',i.company_id,
  'name',i.company_name,
  'is_test',i.is_test,
  'integration',i.integration,
  'signup_at',s.signup_at,
  'signup_kind',s.signup_kind,
  'integration_at',i.integration_at,
  'training_sync_at',i.training_sync_at,
  'post_training_core_at',i.post_training_core_at,
  'activated_at',i.activated_at,
  'ttv_hours',case when i.activated_at is null then null else
    extract(epoch from (i.activated_at-i.integration_at))/3600.0 end,
  'last_core_activity_at',(select last_core_activity_at from last_core),
  'observed_users',(select count(*) from user_identity),
  'active_weeks_8',(select n from active_weeks),
  'module_events_8',(select n from recent_total),
  'evidence',coalesce((
    select jsonb_agg(jsonb_build_object(
      'at',at,'event',event,'module',module,'user',user_label
    ) order by rn)
    from evidence
  ),'[]'::jsonb),
  'users',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id',u.user_key,
        'email',u.user_email,
        'first_seen_at',u.first_seen_at,
        'last_seen_at',u.last_seen_at,
        'activation_role',case
          when u.user_key=r.core_user_key and u.user_key=r.sync_user_key then 'both'
          when u.user_key=r.core_user_key then 'core_job'
          when u.user_key=r.sync_user_key then 'closing_sync'
          else null
        end,
        'recent_totals',jsonb_build_object(
          'ap',coalesce(ur.ap,0),
          'ar',coalesce(ur.ar,0),
          'transactions',coalesce(ur.transactions,0),
          'gst',coalesce(ur.gst,0),
          'sync',coalesce(ur.sync,0)
        )
      )
      order by (u.user_key='__unattributed__'),lower(u.user_email)
    )
    from user_identity u
    cross join role_events r
    left join user_recent ur on ur.user_key=u.user_key
  ),'[]'::jsonb),
  'weeks',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'week_start',week_start,
        'week_end',week_end,
        'totals',jsonb_build_object(
          'ap',ap,'ar',ar,'transactions',transactions,'gst',gst,'sync',sync
        )
      )
      order by week_start
    )
    from week_usage
  ),'[]'::jsonb)
)
from identity i
cross join signup s;
$function$;

revoke all on function public.read_retention_activation_drill_page_v1(date,date,text,text,integer,integer)
  from public,anon,authenticated;
revoke all on function public.read_retention_activation_company_detail_v1(text)
  from public,anon,authenticated;

grant execute on function public.read_retention_activation_drill_page_v1(date,date,text,text,integer,integer)
  to service_role,product_metrics_fetcher;
grant execute on function public.read_retention_activation_company_detail_v1(text)
  to service_role,product_metrics_fetcher;
