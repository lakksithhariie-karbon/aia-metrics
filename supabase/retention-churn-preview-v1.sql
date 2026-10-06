-- Preview-only monthly churn trend + month drill.
-- Reads the current production Retention v3 snapshot and does not mutate it.

create or replace function public.read_retention_dashboard_preview_v4(
  p_from date default null,
  p_to date default null
)
returns jsonb
language sql
stable
security definer
set search_path = public, metrics_private, pg_temp
set statement_timeout = '5s'
as $function$
with base as (
  select public.read_retention_dashboard_v3(p_from,p_to) as dashboard
),
meta as (
  select
    m.source_watermark_at,
    (m.source_watermark_at at time zone 'Asia/Kolkata')::date as watermark_date,
    (
      date_trunc(
        'month',
        m.source_watermark_at at time zone 'Asia/Kolkata'
      ) - interval '1 month'
    )::date as last_complete_month
  from metrics_private.retention_dashboard_meta_v3 m
  where m.singleton=true
  limit 1
),
bounds as (
  select
    case
      when p_from is not null
        then date_trunc('month',p_from::timestamp)::date
      else (
        select
          (date_trunc(
            'month',
            min(a.activated_at) at time zone 'Asia/Kolkata'
          ) + interval '1 month')::date
        from metrics_private.retention_activation_v3 a
        where a.activated_at is not null
      )
    end as start_month,
    least(
      case
        when p_to is null then m.last_complete_month
        else date_trunc('month',p_to::timestamp)::date
      end,
      m.last_complete_month
    ) as end_month,
    m.source_watermark_at
  from meta m
),
months as (
  select gs::date as month_start
  from bounds b
  cross join lateral generate_series(
    b.start_month::timestamp,
    b.end_month::timestamp,
    interval '1 month'
  ) gs
  where b.start_month is not null
    and b.end_month is not null
    and b.start_month<=b.end_month
),
series as (
  select
    m.month_start,
    count(a.company_id)::bigint as eligible,
    count(a.company_id) filter(
      where not exists(
        select 1
        from metrics_private.retention_core_day_v3 d
        where d.company_id=a.company_id
          and d.activity_date>=m.month_start
          and d.activity_date<(m.month_start+interval '1 month')::date
      )
    )::bigint as churned
  from months m
  left join metrics_private.retention_activation_v3 a
    on a.activated_at is not null
   and a.activated_at<(m.month_start::timestamp at time zone 'Asia/Kolkata')
  group by m.month_start
)
select
  b.dashboard ||
  jsonb_build_object(
    'churn_series',
    jsonb_build_object(
      'rows',coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'month',to_char(s.month_start,'YYYY-MM'),
            'eligible',s.eligible,
            'churned',s.churned,
            'active',greatest(s.eligible-s.churned,0),
            'rate_pct',case
              when s.eligible>0
                then round(100.0*s.churned::numeric/s.eligible::numeric,1)
              else null
            end
          )
          order by s.month_start
        )
        from series s
        where s.eligible>0
      ),'[]'::jsonb),
      'source_watermark_at',(select source_watermark_at from bounds)
    )
  )
from base b;
$function$;

create or replace function public.read_retention_churn_month_drill_preview_v1(
  p_month date,
  p_segment text default 'all',
  p_query text default '',
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
    date_trunc('month',p_month::timestamp)::date as month_start,
    (date_trunc('month',p_month::timestamp)+interval '1 month')::date as month_end,
    case when p_segment in ('active','churned') then p_segment else 'all' end
      as segment_filter,
    lower(btrim(coalesce(p_query,''))) as q,
    greatest(coalesce(p_page,1),1) as page_no,
    least(greatest(coalesce(p_page_size,8),1),50) as page_size
),
meta as (
  select
    m.source_watermark_at,
    (m.source_watermark_at at time zone 'Asia/Kolkata')::date as watermark_date
  from metrics_private.retention_dashboard_meta_v3 m
  where m.singleton=true
  limit 1
),
eligible as (
  select
    a.company_id,
    a.integration_at,
    a.activated_at,
    x.month_start,
    x.month_end
  from metrics_private.retention_activation_v3 a
  cross join args x
  cross join meta m
  where a.activated_at is not null
    and a.activated_at<(x.month_start::timestamp at time zone 'Asia/Kolkata')
    and m.watermark_date>=x.month_end
),
classified as (
  select
    e.*,
    exists(
      select 1
      from metrics_private.retention_core_day_v3 d
      where d.company_id=e.company_id
        and d.activity_date>=e.month_start
        and d.activity_date<e.month_end
    ) as active
  from eligible e
),
identity as (
  select
    c.*,
    coalesce(i.company_name,c.company_id) as company_name,
    coalesce(i.is_test,false) as is_test,
    coalesce(i.integration,'Unknown') as integration
  from classified c
  left join metrics_private.company_monthly_identity i using(company_id)
),
with_search as (
  select i.*
  from identity i
  cross join args x
  where (
    x.segment_filter='all'
    or (x.segment_filter='active' and i.active)
    or (x.segment_filter='churned' and not i.active)
  )
  and (
    x.q=''
    or lower(i.company_name) like '%'||x.q||'%'
    or exists(
      select 1
      from public.events e
      where e.company_id=i.company_id
        and e.event_time>=i.integration_at
        and (e.event_time at time zone 'Asia/Kolkata')::date<i.month_end
        and nullif(btrim(e.distinct_id),'') is not null
        and not metrics_private.is_retention_internal_email_v2(e.email)
        and lower(
          coalesce(nullif(btrim(e.email),''),e.distinct_id)
        ) like '%'||x.q||'%'
    )
  )
),
counts as (
  select
    count(*)::bigint as total,
    count(*) filter(where active)::bigint as active,
    count(*) filter(where not active)::bigint as churned
  from identity
),
ranked as (
  select
    s.*,
    row_number() over(
      order by s.active asc,lower(s.company_name),s.company_id
    ) as rn
  from with_search s
),
paged as (
  select r.*
  from ranked r
  cross join args x
  where r.rn>(x.page_no-1)*x.page_size
    and r.rn<=x.page_no*x.page_size
),
observed_users as (
  select
    p.company_id,
    nullif(btrim(e.distinct_id),'') as user_key,
    (
      array_agg(
        coalesce(nullif(btrim(e.email),''),nullif(btrim(e.distinct_id),''))
        order by e.event_time desc,e.insert_id desc
      )
    )[1] as user_email,
    min(e.event_time) as first_seen_at,
    max(e.event_time) as last_seen_at
  from paged p
  join public.events e on e.company_id=p.company_id
  where e.event_time>=p.integration_at
    and (e.event_time at time zone 'Asia/Kolkata')::date<p.month_end
    and nullif(btrim(e.distinct_id),'') is not null
    and not metrics_private.is_retention_internal_email_v2(e.email)
  group by p.company_id,nullif(btrim(e.distinct_id),'')
),
period_events as (
  select
    p.company_id,
    coalesce(nullif(btrim(e.distinct_id),''),'__unattributed__') as user_key,
    e.event_name,
    e.event_time,
    e.properties,
    public.company_module_for(
      e.event_name,
      coalesce(e.properties,'{}'::jsonb)
    ) as module,
    lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
      as is_nonfailed,
    (
      public.is_core_activity(e.event_name,e.properties)
      and lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
    ) as is_core
  from paged p
  join public.events e on e.company_id=p.company_id
  where (e.event_time at time zone 'Asia/Kolkata')::date>=p.month_start
    and (e.event_time at time zone 'Asia/Kolkata')::date<p.month_end
    and not metrics_private.is_retention_internal_email_v2(e.email)
),
user_period as (
  select
    company_id,user_key,
    count(*) filter(where is_core)::bigint as core_events,
    count(*) filter(where is_nonfailed and module='ap')::bigint as ap,
    count(*) filter(where is_nonfailed and module='ar')::bigint as ar,
    count(*) filter(where is_nonfailed and module='transactions')::bigint
      as transactions,
    count(*) filter(where is_nonfailed and module='gst')::bigint as gst,
    count(*) filter(where is_nonfailed and module='sync')::bigint as sync
  from period_events
  group by company_id,user_key
),
user_population as (
  select
    o.company_id,o.user_key,o.user_email,o.first_seen_at,o.last_seen_at
  from observed_users o

  union

  select
    u.company_id,
    '__unattributed__'::text,
    'Unattributed activity'::text,
    min(e.event_time),
    max(e.event_time)
  from user_period u
  join period_events e
    on e.company_id=u.company_id
   and e.user_key='__unattributed__'
  where u.user_key='__unattributed__'
  group by u.company_id
),
company_period as (
  select
    company_id,
    count(*) filter(where is_core)::bigint as core_events,
    count(*) filter(where is_nonfailed and module='ap')::bigint as ap,
    count(*) filter(where is_nonfailed and module='ar')::bigint as ar,
    count(*) filter(where is_nonfailed and module='transactions')::bigint
      as transactions,
    count(*) filter(where is_nonfailed and module='gst')::bigint as gst,
    count(*) filter(where is_nonfailed and module='sync')::bigint as sync
  from period_events
  group by company_id
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
      'activated_at',p.activated_at,
      'active',p.active,
      'month_start',p.month_start,
      'month_end',p.month_end,
      'core_events',coalesce(cp.core_events,0),
      'totals',jsonb_build_object(
        'ap',coalesce(cp.ap,0),
        'ar',coalesce(cp.ar,0),
        'transactions',coalesce(cp.transactions,0),
        'gst',coalesce(cp.gst,0),
        'sync',coalesce(cp.sync,0)
      ),
      'active_users',coalesce((
        select count(*)
        from user_population up
        left join user_period ux
          on ux.company_id=up.company_id and ux.user_key=up.user_key
        where up.company_id=p.company_id
          and up.user_key<>'__unattributed__'
          and coalesce(ux.core_events,0)>0
      ),0),
      'observed_users',coalesce((
        select count(*)
        from user_population up
        where up.company_id=p.company_id
          and up.user_key<>'__unattributed__'
      ),0),
      'users',coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id',up.user_key,
            'email',up.user_email,
            'first_seen_at',up.first_seen_at,
            'last_seen_at',up.last_seen_at,
            'active',coalesce(ux.core_events,0)>0,
            'core_events',coalesce(ux.core_events,0),
            'totals',jsonb_build_object(
              'ap',coalesce(ux.ap,0),
              'ar',coalesce(ux.ar,0),
              'transactions',coalesce(ux.transactions,0),
              'gst',coalesce(ux.gst,0),
              'sync',coalesce(ux.sync,0)
            )
          )
          order by
            (up.user_key='__unattributed__'),
            (coalesce(ux.core_events,0)>0) desc,
            lower(up.user_email),
            up.user_key
        )
        from user_population up
        left join user_period ux
          on ux.company_id=up.company_id and ux.user_key=up.user_key
        where up.company_id=p.company_id
      ),'[]'::jsonb)
    ) as row
  from paged p
  left join company_period cp using(company_id)
)
select jsonb_build_object(
  'month',to_char((select month_start from args),'YYYY-MM'),
  'counts',jsonb_build_object(
    'all',(select total from counts),
    'active',(select active from counts),
    'churned',(select churned from counts)
  ),
  'rows',coalesce(
    (select jsonb_agg(row order by rn) from rows_json),
    '[]'::jsonb
  ),
  'total',(select count(*) from with_search),
  'page',(select page_no from args),
  'page_size',(select page_size from args),
  'source_watermark_at',(select source_watermark_at from meta)
);
$function$;

revoke all on function public.read_retention_dashboard_preview_v4(date,date)
  from public,anon,authenticated;
revoke all on function public.read_retention_churn_month_drill_preview_v1(
  date,text,text,integer,integer
) from public,anon,authenticated;

grant execute on function public.read_retention_dashboard_preview_v4(date,date)
  to service_role,product_metrics_fetcher;
grant execute on function public.read_retention_churn_month_drill_preview_v1(
  date,text,text,integer,integer
) to service_role,product_metrics_fetcher;
