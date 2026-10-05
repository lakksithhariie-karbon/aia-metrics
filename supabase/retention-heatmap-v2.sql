-- Live Retention cohort heatmap read model.
-- Cohorts use the Retention KPI v2 activation contract.
-- Weekly retention = core activity in the next completed IST calendar weeks.
-- Monthly retention = core activity in the next completed IST calendar months.

create table if not exists metrics_private.retention_week_core_v2 (
  company_id text not null,
  week_start date not null,
  primary key (company_id, week_start)
);

create index if not exists retention_week_core_v2_week_idx
  on metrics_private.retention_week_core_v2 (week_start, company_id);

revoke all on metrics_private.retention_week_core_v2
  from public, anon, authenticated;

create or replace function public.refresh_retention_heatmap_v2()
returns jsonb
language plpgsql
security definer
set search_path = public, metrics_private, pg_temp
set statement_timeout = '60s'
as $function$
declare
  v_rows bigint;
begin
  truncate table metrics_private.retention_week_core_v2;

  insert into metrics_private.retention_week_core_v2 (
    company_id,
    week_start
  )
  select
    e.company_id,
    date_trunc(
      'week',
      e.event_time at time zone 'Asia/Kolkata'
    )::date
  from public.events e
  join metrics_private.retention_activation_v2 a
    on a.company_id=e.company_id
   and a.activated_at is not null
  where e.event_time>=a.activated_at
    and public.is_core_activity(e.event_name,e.properties)
    and not metrics_private.is_retention_internal_email_v2(e.email)
  group by
    e.company_id,
    date_trunc(
      'week',
      e.event_time at time zone 'Asia/Kolkata'
    )::date;

  get diagnostics v_rows = row_count;

  return jsonb_build_object(
    'week_core_rows',v_rows,
    'refreshed_at',now()
  );
end;
$function$;

create or replace function public.read_retention_heatmap_v2(
  p_interval text default 'weekly',
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
with args as (
  select
    case when p_interval='monthly' then 'monthly' else 'weekly' end as interval_kind,
    p_from as from_date,
    p_to as to_date,
    date_trunc('week',now() at time zone 'Asia/Kolkata')::date as current_week,
    date_trunc('month',now() at time zone 'Asia/Kolkata')::date as current_month
),
activated as (
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
  from metrics_private.retention_activation_v2 a
  cross join args x
  where a.activated_at is not null
    and (
      x.from_date is null
      or (a.activated_at at time zone 'Asia/Kolkata')::date>=x.from_date
    )
    and (
      x.to_date is null
      or (a.activated_at at time zone 'Asia/Kolkata')::date<=x.to_date
    )
),
weekly_cohorts as (
  select cohort_week as cohort_start,count(*)::bigint as cohort_size
  from activated
  group by cohort_week
),
weekly_cells as (
  select
    c.cohort_start,
    c.cohort_size,
    g.rel,
    (c.cohort_start + g.rel*7)::date as target_start,
    case
      when (c.cohort_start + g.rel*7)::date >= x.current_week then null::bigint
      else count(a.company_id) filter(
        where exists(
          select 1
          from metrics_private.retention_week_core_v2 w
          where w.company_id=a.company_id
            and w.week_start=(c.cohort_start + g.rel*7)::date
        )
      )::bigint
    end as retained_count
  from weekly_cohorts c
  join activated a on a.cohort_week=c.cohort_start
  cross join generate_series(1,8) g(rel)
  cross join args x
  group by c.cohort_start,c.cohort_size,g.rel,x.current_week
),
weekly_rows as (
  select
    cohort_start,
    cohort_size,
    jsonb_agg(retained_count order by rel) as values
  from weekly_cells
  group by cohort_start,cohort_size
),
monthly_cohorts as (
  select cohort_month as cohort_start,count(*)::bigint as cohort_size
  from activated
  group by cohort_month
),
monthly_cells as (
  select
    c.cohort_start,
    c.cohort_size,
    g.rel,
    (c.cohort_start + make_interval(months=>g.rel))::date as target_start,
    case
      when (c.cohort_start + make_interval(months=>g.rel))::date >= x.current_month
        then null::bigint
      else count(a.company_id) filter(
        where exists(
          select 1
          from metrics_private.retention_month_core_v2 m
          where m.company_id=a.company_id
            and m.month_start=(c.cohort_start + make_interval(months=>g.rel))::date
        )
      )::bigint
    end as retained_count
  from monthly_cohorts c
  join activated a on a.cohort_month=c.cohort_start
  cross join generate_series(1,6) g(rel)
  cross join args x
  group by c.cohort_start,c.cohort_size,g.rel,x.current_month
),
monthly_rows as (
  select
    cohort_start,
    cohort_size,
    jsonb_agg(retained_count order by rel) as values
  from monthly_cells
  group by cohort_start,cohort_size
),
chosen as (
  select
    w.cohort_start,w.cohort_size,w.values
  from weekly_rows w
  cross join args x
  where x.interval_kind='weekly'

  union all

  select
    m.cohort_start,m.cohort_size,m.values
  from monthly_rows m
  cross join args x
  where x.interval_kind='monthly'
),
meta as (
  select source_watermark_at,refreshed_at
  from metrics_private.retention_kpi_meta_v2
  where singleton=true
  limit 1
)
select jsonb_build_object(
  'interval',(select interval_kind from args),
  'columns',case
    when (select interval_kind from args)='monthly' then 6 else 8
  end,
  'rows',coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'cohort_start',c.cohort_start,
        'cohort_size',c.cohort_size,
        'values',c.values
      )
      order by c.cohort_start
    )
    from chosen c
  ),'[]'::jsonb),
  'source_watermark_at',(select source_watermark_at from meta),
  'refreshed_at',(select refreshed_at from meta)
);
$function$;

revoke all on function public.refresh_retention_heatmap_v2()
  from public,anon,authenticated;
revoke all on function public.read_retention_heatmap_v2(text,date,date)
  from public,anon,authenticated;

grant execute on function public.refresh_retention_heatmap_v2()
  to service_role;
grant execute on function public.read_retention_heatmap_v2(text,date,date)
  to service_role,product_metrics_fetcher;

select public.refresh_retention_heatmap_v2();

do $job$
declare current_job bigint;
begin
  select jobid into current_job
  from cron.job
  where jobname='retention-heatmap-v2-hourly'
  limit 1;

  if current_job is not null then
    perform cron.unschedule(current_job);
  end if;

  perform cron.schedule(
    'retention-heatmap-v2-hourly',
    '19 * * * *',
    'select public.refresh_retention_heatmap_v2();'
  );
end;
$job$;
