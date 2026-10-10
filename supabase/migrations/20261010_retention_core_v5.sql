-- Nonbreaking Retention v5 shadow pipeline.
-- Alignment: real non-test client companies; staff-assisted integration allowed;
-- retained = independently performed, non-failed core work, excluding Accounting Sync.
-- Existing v3/v4 dashboard caches and readers remain untouched until preview approval.
CREATE TABLE IF NOT EXISTS metrics_private.retention_activation_v4
(LIKE metrics_private.retention_activation_v3 INCLUDING ALL);
CREATE TABLE IF NOT EXISTS metrics_private.retention_core_day_v4
(LIKE metrics_private.retention_core_day_v3 INCLUDING ALL);
CREATE TABLE IF NOT EXISTS metrics_private.retention_dashboard_meta_v4
(LIKE metrics_private.retention_dashboard_meta_v3 INCLUDING ALL);

CREATE OR REPLACE FUNCTION public.refresh_retention_dashboard_v4(p_force boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '90s'
AS $function$
declare
  v_source_watermark timestamptz;
  v_current_watermark timestamptz;
  v_activation_rows bigint;
  v_core_day_rows bigint;
begin
  select w.last_success_at
    into v_source_watermark
  from public.export_watermarks w
  where w.job_name='incremental' and w.status='ok'
  order by w.last_success_at desc
  limit 1;

  select m.source_watermark_at
    into v_current_watermark
  from metrics_private.retention_dashboard_meta_v4 m
  where m.singleton=true;

  if not coalesce(p_force,false)
     and v_source_watermark is not null
     and v_current_watermark is not null
     and v_source_watermark <= v_current_watermark then
    return jsonb_build_object(
      'refreshed',false,
      'source_watermark_at',v_current_watermark,
      'reason','source_unchanged'
    );
  end if;

  truncate table metrics_private.retention_activation_v4;

  insert into metrics_private.retention_activation_v4 (
    company_id,
    integration_at,
    integration_month,
    training_sync_at,
    post_training_core_at,
    activated_at
  )
  with first_integration as (
    select distinct on (e.company_id)
      e.company_id,
      e.event_time as integration_at
    from public.events e
    join public.client_company c on c.company_id=e.company_id
    left join public.company_directory d on d.company_uuid::text=e.company_id
    where public.is_successful_integration(e.event_name,e.properties)
      and not coalesce(d.is_test,false)
    order by e.company_id,e.event_time asc,e.insert_id asc
  )
  select
    i.company_id,
    i.integration_at,
    date_trunc('month',i.integration_at at time zone 'Asia/Kolkata')::date,
    training.training_sync_at,
    core.post_training_core_at,
    activation.activated_at
  from first_integration i
  left join lateral (
    select e.event_time as training_sync_at
    from public.events e
    where e.company_id=i.company_id
      and e.event_time>=i.integration_at
      and public.is_qualifying_sync(e.event_name,e.properties)
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.event_time asc,e.insert_id asc
    limit 1
  ) training on true
  left join lateral (
    select e.event_time as post_training_core_at
    from public.events e
    where e.company_id=i.company_id
      and training.training_sync_at is not null
      and (e.event_time at time zone 'Asia/Kolkata')::date
          > (training.training_sync_at at time zone 'Asia/Kolkata')::date
      and public.is_core_activity(e.event_name,e.properties)
      and e.event_name<>'Accounting Sync'
      and lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.event_time asc,e.insert_id asc
    limit 1
  ) core on true
  left join lateral (
    select e.event_time as activated_at
    from public.events e
    where e.company_id=i.company_id
      and core.post_training_core_at is not null
      and e.event_time>core.post_training_core_at
      and public.is_qualifying_sync(e.event_name,e.properties)
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.event_time asc,e.insert_id asc
    limit 1
  ) activation on true;

  get diagnostics v_activation_rows = row_count;

  truncate table metrics_private.retention_core_day_v4;

  insert into metrics_private.retention_core_day_v4 (
    company_id,
    activity_date
  )
  select
    e.company_id,
    (e.event_time at time zone 'Asia/Kolkata')::date
  from public.events e
  join metrics_private.retention_activation_v4 a
    on a.company_id=e.company_id
   and a.activated_at is not null
  where e.event_time>=a.activated_at
    and e.event_name<>'Accounting Sync'
    and public.is_core_activity(e.event_name,e.properties)
    and lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
    and not metrics_private.is_retention_internal_email_v2(e.email)
  group by
    e.company_id,
    (e.event_time at time zone 'Asia/Kolkata')::date;

  get diagnostics v_core_day_rows = row_count;

  insert into metrics_private.retention_dashboard_meta_v4 (
    singleton,source_watermark_at,refreshed_at
  )
  values (
    true,
    v_source_watermark,
    now()
  )
  on conflict (singleton) do update
    set source_watermark_at=excluded.source_watermark_at,
        refreshed_at=excluded.refreshed_at;

  return jsonb_build_object(
    'refreshed',true,
    'activation_rows',v_activation_rows,
    'core_day_rows',v_core_day_rows,
    'source_watermark_at',v_source_watermark,
    'refreshed_at',now()
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.read_retention_dashboard_v5_base(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '5s'
AS $function$
with meta as (
  select
    m.source_watermark_at,
    m.refreshed_at,
    (m.source_watermark_at at time zone 'Asia/Kolkata')::date as watermark_date
  from metrics_private.retention_dashboard_meta_v4 m
  where m.singleton=true
  limit 1
),
params as (
  select
    p_from as from_date,
    p_to as to_date,
    date_trunc(
      'month',
      ((select watermark_date from meta)-interval '1 month')::timestamp
    )::date as last_complete_month
),
integration_cohort as (
  select a.*
  from metrics_private.retention_activation_v4 a
  cross join params p
  where (p.from_date is null
         or (a.integration_at at time zone 'Asia/Kolkata')::date>=p.from_date)
    and (p.to_date is null
         or (a.integration_at at time zone 'Asia/Kolkata')::date<=p.to_date)
),
activation_summary as (
  select
    count(*)::bigint as integrated,
    count(*) filter(where training_sync_at is not null)::bigint as trained,
    count(*) filter(where post_training_core_at is not null)::bigint as post_training_core,
    count(*) filter(where activated_at is not null)::bigint as activated,
    avg(extract(epoch from (activated_at-integration_at))/3600.0)
      filter(where activated_at is not null) as avg_ttv_hours,
    percentile_cont(.5) within group(
      order by extract(epoch from (activated_at-integration_at))/3600.0
    ) filter(where activated_at is not null) as median_ttv_hours
  from integration_cohort
),
churn_target as (
  select case
    when p.from_date is not null
      and date_trunc(
        'month',
        least(coalesce(p.to_date,p.last_complete_month),p.last_complete_month)::timestamp
      )::date
        < date_trunc('month',p.from_date::timestamp)::date
      then null::date
    else date_trunc(
      'month',
      least(coalesce(p.to_date,p.last_complete_month),p.last_complete_month)::timestamp
    )::date
  end as month_start
  from params p
),
churn_summary as (
  select
    t.month_start,
    count(a.company_id)::bigint as eligible,
    count(a.company_id) filter(
      where not exists(
        select 1
        from metrics_private.retention_core_day_v4 d
        where d.company_id=a.company_id
          and d.activity_date>=t.month_start
          and d.activity_date<(t.month_start+interval '1 month')::date
      )
    )::bigint as churned
  from churn_target t
  left join metrics_private.retention_activation_v4 a
    on t.month_start is not null
   and a.activated_at is not null
   and a.activated_at<(t.month_start::timestamp at time zone 'Asia/Kolkata')
  group by t.month_start
),
activated_all as (
  select
    a.company_id,
    a.activated_at,
    date_trunc(
      'week',
      a.activated_at at time zone 'Asia/Kolkata'
    )::date as cohort_week,
    date_trunc(
      'month',
      a.activated_at at time zone 'Asia/Kolkata'
    )::date as cohort_month
  from metrics_private.retention_activation_v4 a
  where a.activated_at is not null
),
weekly_activated as (
  select a.*
  from activated_all a
  cross join params p
  where (p.from_date is null or a.cohort_week>=p.from_date)
    and (p.to_date is null or a.cohort_week<=p.to_date)
),
weekly_cohorts as (
  select cohort_week as cohort_start,count(*)::bigint as cohort_size
  from weekly_activated
  group by cohort_week
),
weekly_cells as (
  select
    c.cohort_start,
    c.cohort_size,
    g.rel,
    (c.cohort_start+g.rel*7)::date as target_start,
    case
      when (select watermark_date from meta)<(c.cohort_start+(g.rel+1)*7)::date
        then null::bigint
      else count(a.company_id) filter(
        where exists(
          select 1
          from metrics_private.retention_core_day_v4 d
          where d.company_id=a.company_id
            and d.activity_date>=(c.cohort_start+g.rel*7)::date
            and d.activity_date<(c.cohort_start+(g.rel+1)*7)::date
        )
      )::bigint
    end as retained_count
  from weekly_cohorts c
  join weekly_activated a on a.cohort_week=c.cohort_start
  cross join generate_series(1,8) g(rel)
  group by c.cohort_start,c.cohort_size,g.rel
),
weekly_rows as (
  select
    cohort_start,
    cohort_size,
    jsonb_agg(retained_count order by rel) as values
  from weekly_cells
  group by cohort_start,cohort_size
),
monthly_activated as (
  select a.*
  from activated_all a
  cross join params p
  where (
    p.from_date is null
    or a.cohort_month>=date_trunc('month',p.from_date::timestamp)::date
  )
  and (
    p.to_date is null
    or a.cohort_month<=date_trunc('month',p.to_date::timestamp)::date
  )
),
monthly_cohorts as (
  select cohort_month as cohort_start,count(*)::bigint as cohort_size
  from monthly_activated
  group by cohort_month
),
monthly_cells as (
  select
    c.cohort_start,
    c.cohort_size,
    g.rel,
    (c.cohort_start+make_interval(months=>g.rel))::date as target_start,
    case
      when (select watermark_date from meta)
           < (c.cohort_start+make_interval(months=>g.rel+1))::date
        then null::bigint
      else count(a.company_id) filter(
        where exists(
          select 1
          from metrics_private.retention_core_day_v4 d
          where d.company_id=a.company_id
            and d.activity_date>=(c.cohort_start+make_interval(months=>g.rel))::date
            and d.activity_date<(c.cohort_start+make_interval(months=>g.rel+1))::date
        )
      )::bigint
    end as retained_count
  from monthly_cohorts c
  join monthly_activated a on a.cohort_month=c.cohort_start
  cross join generate_series(1,6) g(rel)
  group by c.cohort_start,c.cohort_size,g.rel
),
monthly_rows as (
  select
    cohort_start,
    cohort_size,
    jsonb_agg(retained_count order by rel) as values
  from monthly_cells
  group by cohort_start,cohort_size
),
a as (
  select * from activation_summary
),
c as (
  select * from churn_summary
)
select jsonb_build_object(
  'kpis',jsonb_build_object(
    'activation',jsonb_build_object(
      'integrated',a.integrated,
      'trained',a.trained,
      'post_training_core',a.post_training_core,
      'activated',a.activated,
      'rate_pct',case when a.integrated>0
        then round(100.0*a.activated::numeric/a.integrated::numeric,1)
        else null end
    ),
    'ttv',jsonb_build_object(
      'companies',a.activated,
      'avg_hours',round(a.avg_ttv_hours::numeric,1),
      'median_hours',round(a.median_ttv_hours::numeric,1)
    ),
    'churn',jsonb_build_object(
      'month',case when c.month_start is null then null else to_char(c.month_start,'YYYY-MM') end,
      'eligible',c.eligible,
      'churned',c.churned,
      'rate_pct',case
        when c.month_start is not null and c.eligible>0
          then round(100.0*c.churned::numeric/c.eligible::numeric,1)
        else null end
    ),
    'source_watermark_at',(select source_watermark_at from meta),
    'refreshed_at',(select refreshed_at from meta)
  ),
  'weekly',jsonb_build_object(
    'interval','weekly',
    'columns',8,
    'rows',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'cohort_start',w.cohort_start,
          'cohort_size',w.cohort_size,
          'values',w.values
        )
        order by w.cohort_start
      )
      from weekly_rows w
    ),'[]'::jsonb),
    'source_watermark_at',(select source_watermark_at from meta),
    'refreshed_at',(select refreshed_at from meta)
  ),
  'monthly',jsonb_build_object(
    'interval','monthly',
    'columns',6,
    'rows',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'cohort_start',m.cohort_start,
          'cohort_size',m.cohort_size,
          'values',m.values
        )
        order by m.cohort_start
      )
      from monthly_rows m
    ),'[]'::jsonb),
    'source_watermark_at',(select source_watermark_at from meta),
    'refreshed_at',(select refreshed_at from meta)
  )
)
from a cross join c;
$function$;

CREATE OR REPLACE FUNCTION public.read_retention_dashboard_v5(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '5s'
AS $function$
with base as (
  select public.read_retention_dashboard_v5_base(p_from,p_to) as dashboard
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
  from metrics_private.retention_dashboard_meta_v4 m
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
        from metrics_private.retention_activation_v4 a
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
monthly_state as (
  select
    m.month_start,
    a.company_id,
    a.activated_at,
    exists(
      select 1
      from metrics_private.retention_core_day_v4 d
      where d.company_id=a.company_id
        and d.activity_date>=m.month_start
        and d.activity_date<(m.month_start+interval '1 month')::date
    ) as active,
    (
      a.activated_at<
        ((m.month_start-interval '1 month')::timestamp at time zone 'Asia/Kolkata')
    ) as prev_eligible,
    exists(
      select 1
      from metrics_private.retention_core_day_v4 d
      where d.company_id=a.company_id
        and d.activity_date>=(m.month_start-interval '1 month')::date
        and d.activity_date<m.month_start
    ) as prev_active
  from months m
  join metrics_private.retention_activation_v4 a
    on a.activated_at is not null
   and a.activated_at<(m.month_start::timestamp at time zone 'Asia/Kolkata')
),
series as (
  select
    s.month_start,
    count(*)::bigint as eligible,
    count(*) filter(where not s.active)::bigint as churned,
    count(*) filter(where s.active)::bigint as active,
    count(*) filter(
      where not s.active
        and (not s.prev_eligible or s.prev_active)
    )::bigint as entered,
    count(*) filter(
      where s.active
        and s.prev_eligible
        and not s.prev_active
    )::bigint as reactivated
  from monthly_state s
  group by s.month_start
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
            'active',s.active,
            'entered',s.entered,
            'reactivated',s.reactivated,
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

CREATE OR REPLACE FUNCTION public.read_retention_activation_drill_page_v2(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_query text DEFAULT ''::text, p_status text DEFAULT 'all'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '5s'
AS $function$
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
  from metrics_private.retention_activation_v4 a
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
observed_users as (
  select
    p.company_id,
    nullif(btrim(e.distinct_id),'') as user_key,
    (
      array_agg(
        nullif(btrim(e.email),'')
        order by e.event_time desc,e.insert_id desc
      )
      filter (where nullif(btrim(e.email),'') is not null)
    )[1] as user_email
  from paged p
  join public.events e on e.company_id=p.company_id
  where e.event_time>=p.integration_at
    and nullif(btrim(e.distinct_id),'') is not null
    and not metrics_private.is_retention_internal_email_v2(e.email)
  group by p.company_id,nullif(btrim(e.distinct_id),'')
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
user_population as (
  select
    ou.company_id,
    ou.user_key,
    coalesce(ou.user_email,ou.user_key) as user_email
  from observed_users ou

  union

  select
    ut.company_id,
    '__unattributed__'::text,
    'Unattributed activity'::text
  from user_totals ut
  where ut.user_key='__unattributed__'
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
            'id',up.user_key,
            'email',up.user_email,
            'totals',jsonb_build_object(
              'ap',coalesce(ut.ap,0),
              'ar',coalesce(ut.ar,0),
              'transactions',coalesce(ut.transactions,0),
              'gst',coalesce(ut.gst,0)
            )
          )
          order by
            (up.user_key='__unattributed__'),
            lower(up.user_email),
            up.user_key
        )
        from user_population up
        left join user_totals ut
          on ut.company_id=up.company_id and ut.user_key=up.user_key
        where up.company_id=p.company_id
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

CREATE OR REPLACE FUNCTION public.read_retention_activation_company_detail_v2(p_company_id text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '5s'
AS $function$
with identity as (
  select
    a.company_id,
    coalesce(i.company_name,a.company_id) as company_name,
    coalesce(i.is_test,false) as is_test,
    coalesce(i.integration,'Unknown') as integration,
    a.integration_at,a.training_sync_at,a.post_training_core_at,a.activated_at
  from metrics_private.retention_activation_v4 a
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

CREATE OR REPLACE FUNCTION public.read_retention_heatmap_cell_drill_v4(p_interval text, p_cohort_start date DEFAULT NULL::date, p_rel_period integer DEFAULT 1, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '5s'
AS $function$
with meta as (
  select
    m.source_watermark_at,
    (m.source_watermark_at at time zone 'Asia/Kolkata')::date as watermark_date
  from metrics_private.retention_dashboard_meta_v4 m
  where m.singleton=true
  limit 1
),
args as (
  select
    case when p_interval='monthly' then 'monthly' else 'weekly' end as interval_kind,
    greatest(coalesce(p_rel_period,1),1) as rel_period,
    case when p_segment in ('retained','churned') then p_segment else 'all' end as segment_filter,
    lower(btrim(coalesce(p_query,''))) as q,
    greatest(coalesce(p_page,1),1) as page_no,
    least(greatest(coalesce(p_page_size,8),1),50) as page_size
),
activated as (
  select
    a.company_id,
    a.integration_at,
    a.activated_at,
    date_trunc('week',a.activated_at at time zone 'Asia/Kolkata')::date as cohort_week,
    date_trunc('month',a.activated_at at time zone 'Asia/Kolkata')::date as cohort_month
  from metrics_private.retention_activation_v4 a
  where a.activated_at is not null
),
eligible_cohort as (
  select
    a.*,
    case when x.interval_kind='weekly' then a.cohort_week else a.cohort_month end as cohort_start,
    case when x.interval_kind='weekly'
      then (a.cohort_week+x.rel_period*7)::date
      else (a.cohort_month+make_interval(months=>x.rel_period))::date
    end as target_start,
    case when x.interval_kind='weekly'
      then (a.cohort_week+(x.rel_period+1)*7)::date
      else (a.cohort_month+make_interval(months=>x.rel_period+1))::date
    end as target_end
  from activated a
  cross join args x
  cross join meta m
  where (
    p_cohort_start is not null
    and (
      (x.interval_kind='weekly' and a.cohort_week=p_cohort_start)
      or (x.interval_kind='monthly' and a.cohort_month=p_cohort_start)
    )
  ) or (
    p_cohort_start is null
    and (
      (
        x.interval_kind='weekly'
        and (p_from is null or a.cohort_week>=p_from)
        and (p_to is null or a.cohort_week<=p_to)
      ) or (
        x.interval_kind='monthly'
        and (
          p_from is null
          or a.cohort_month>=date_trunc('month',p_from::timestamp)::date
        )
        and (
          p_to is null
          or a.cohort_month<=date_trunc('month',p_to::timestamp)::date
        )
      )
    )
  )
),
period_eligible as (
  select e.*
  from eligible_cohort e
  cross join meta m
  where m.watermark_date>=e.target_end
),
classified as (
  select
    e.*,
    exists(
      select 1
      from metrics_private.retention_core_day_v4 d
      where d.company_id=e.company_id
        and d.activity_date>=e.target_start
        and d.activity_date<e.target_end
    ) as retained
  from period_eligible e
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
    or (x.segment_filter='retained' and i.retained)
    or (x.segment_filter='churned' and not i.retained)
  )
  and (
    x.q=''
    or lower(i.company_name) like '%'||x.q||'%'
    or exists(
      select 1
      from public.events e
      where e.company_id=i.company_id
        and e.event_time>=i.integration_at
        and (e.event_time at time zone 'Asia/Kolkata')::date<i.target_end
        and nullif(btrim(e.distinct_id),'') is not null
        and not metrics_private.is_retention_internal_email_v2(e.email)
        and lower(coalesce(nullif(btrim(e.email),''),e.distinct_id)) like '%'||x.q||'%'
    )
  )
),
counts as (
  select
    count(*)::bigint as total,
    count(*) filter(where retained)::bigint as retained,
    count(*) filter(where not retained)::bigint as churned
  from identity
),
ranked as (
  select
    s.*,
    row_number() over(
      order by s.retained desc,lower(s.company_name),s.company_id
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
    and (e.event_time at time zone 'Asia/Kolkata')::date<p.target_end
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
    public.company_module_for(e.event_name,coalesce(e.properties,'{}'::jsonb)) as module,
    lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed' as is_nonfailed,
    (
      public.is_core_activity(e.event_name,e.properties)
      and lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
    ) as is_core
  from paged p
  join public.events e on e.company_id=p.company_id
  where (e.event_time at time zone 'Asia/Kolkata')::date>=p.target_start
    and (e.event_time at time zone 'Asia/Kolkata')::date<p.target_end
    and not metrics_private.is_retention_internal_email_v2(e.email)
),
user_period as (
  select
    company_id,user_key,
    count(*) filter(where is_core)::bigint as core_events,
    count(*) filter(where is_nonfailed and module='ap')::bigint as ap,
    count(*) filter(where is_nonfailed and module='ar')::bigint as ar,
    count(*) filter(where is_nonfailed and module='transactions')::bigint as transactions,
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
    on e.company_id=u.company_id and e.user_key='__unattributed__'
  where u.user_key='__unattributed__'
  group by u.company_id
),
company_period as (
  select
    company_id,
    count(*) filter(where is_core)::bigint as core_events,
    count(*) filter(where module='ap')::bigint as ap,
    count(*) filter(where module='ar')::bigint as ar,
    count(*) filter(where module='transactions')::bigint as transactions,
    count(*) filter(where module='sync')::bigint as sync
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
      'retained',p.retained,
      'cohort_start',p.cohort_start,
      'target_start',p.target_start,
      'target_end',p.target_end,
      'core_events',coalesce(cp.core_events,0),
      'totals',jsonb_build_object(
        'ap',coalesce(cp.ap,0),
        'ar',coalesce(cp.ar,0),
        'transactions',coalesce(cp.transactions,0),
        'sync',coalesce(cp.sync,0)
      ),
      'active_users',coalesce((
        select count(*)
        from user_population up
        left join user_period upx
          on upx.company_id=up.company_id and upx.user_key=up.user_key
        where up.company_id=p.company_id
          and coalesce(upx.core_events,0)>0
      ),0),
      'observed_users',coalesce((
        select count(*)
        from user_population up
        where up.company_id=p.company_id
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
  'interval',(select interval_kind from args),
  'relative_period',(select rel_period from args),
  'cohort_start',p_cohort_start,
  'counts',jsonb_build_object(
    'all',(select total from counts),
    'retained',(select retained from counts),
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

CREATE OR REPLACE FUNCTION public.read_retention_churn_month_drill_v2(p_month date, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '5s'
AS $function$
with args as (
  select
    date_trunc('month',p_month::timestamp)::date as month_start,
    (date_trunc('month',p_month::timestamp)+interval '1 month')::date as month_end,
    case
      when p_segment in ('active','churned','entered','reactivated')
        then p_segment
      else 'all'
    end as segment_filter,
    lower(btrim(coalesce(p_query,''))) as q,
    greatest(coalesce(p_page,1),1) as page_no,
    least(greatest(coalesce(p_page_size,8),1),50) as page_size
),
meta as (
  select
    m.source_watermark_at,
    (m.source_watermark_at at time zone 'Asia/Kolkata')::date as watermark_date
  from metrics_private.retention_dashboard_meta_v4 m
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
  from metrics_private.retention_activation_v4 a
  cross join args x
  cross join meta m
  where a.activated_at is not null
    and a.activated_at<(x.month_start::timestamp at time zone 'Asia/Kolkata')
    and m.watermark_date>=x.month_end
),
classified_base as (
  select
    e.*,
    exists(
      select 1
      from metrics_private.retention_core_day_v4 d
      where d.company_id=e.company_id
        and d.activity_date>=e.month_start
        and d.activity_date<e.month_end
    ) as active,
    (
      e.activated_at<
        ((e.month_start-interval '1 month')::timestamp at time zone 'Asia/Kolkata')
    ) as prev_eligible,
    exists(
      select 1
      from metrics_private.retention_core_day_v4 d
      where d.company_id=e.company_id
        and d.activity_date>=(e.month_start-interval '1 month')::date
        and d.activity_date<e.month_start
    ) as prev_active
  from eligible e
),
classified as (
  select
    b.*,
    (
      not b.active
      and (not b.prev_eligible or b.prev_active)
    ) as entered,
    (
      b.active
      and b.prev_eligible
      and not b.prev_active
    ) as reactivated
  from classified_base b
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
    or (x.segment_filter='entered' and i.entered)
    or (x.segment_filter='reactivated' and i.reactivated)
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
    count(*) filter(where not active)::bigint as churned,
    count(*) filter(where entered)::bigint as entered,
    count(*) filter(where reactivated)::bigint as reactivated
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
      'entered',p.entered,
      'reactivated',p.reactivated,
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
    'churned',(select churned from counts),
    'entered',(select entered from counts),
    'reactivated',(select reactivated from counts)
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

REVOKE ALL ON FUNCTION public.refresh_retention_dashboard_v4(boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_retention_dashboard_v4(boolean) TO service_role;

REVOKE ALL ON FUNCTION public.read_retention_dashboard_v5_base(date,date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_retention_dashboard_v5_base(date,date) TO service_role;

REVOKE ALL ON FUNCTION public.read_retention_dashboard_v5(date,date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_retention_dashboard_v5(date,date) TO service_role;

REVOKE ALL ON FUNCTION public.read_retention_activation_drill_page_v2(date,date,text,text,integer,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_retention_activation_drill_page_v2(date,date,text,text,integer,integer) TO service_role;

REVOKE ALL ON FUNCTION public.read_retention_activation_company_detail_v2(text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_retention_activation_company_detail_v2(text) TO service_role;

REVOKE ALL ON FUNCTION public.read_retention_heatmap_cell_drill_v4(text,date,integer,date,date,text,text,integer,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_retention_heatmap_cell_drill_v4(text,date,integer,date,date,text,text,integer,integer) TO service_role;

REVOKE ALL ON FUNCTION public.read_retention_churn_month_drill_v2(date,text,text,integer,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_retention_churn_month_drill_v2(date,text,text,integer,integer) TO service_role;
