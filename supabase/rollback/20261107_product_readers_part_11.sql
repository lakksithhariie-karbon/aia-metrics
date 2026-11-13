-- Exact original public Product read RPCs, part 11/12, backed up 2026-11-07.
-- Rollback only. Original data and function grants remain in place.
-- Apply this together with all other Product rollback parts if a cutover must be reversed.
SET LOCAL lock_timeout='7s';

CREATE OR REPLACE FUNCTION public.read_retention_dashboard_v3(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
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
  from metrics_private.retention_dashboard_meta_v3 m
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
  from metrics_private.retention_activation_v3 a
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
        from metrics_private.retention_core_day_v3 d
        where d.company_id=a.company_id
          and d.activity_date>=t.month_start
          and d.activity_date<(t.month_start+interval '1 month')::date
      )
    )::bigint as churned
  from churn_target t
  left join metrics_private.retention_activation_v3 a
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
  from metrics_private.retention_activation_v3 a
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
          from metrics_private.retention_core_day_v3 d
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
          from metrics_private.retention_core_day_v3 d
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_retention_dashboard_v4(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '5s'
AS $function$
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
monthly_state as (
  select
    m.month_start,
    a.company_id,
    a.activated_at,
    exists(
      select 1
      from metrics_private.retention_core_day_v3 d
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
      from metrics_private.retention_core_day_v3 d
      where d.company_id=a.company_id
        and d.activity_date>=(m.month_start-interval '1 month')::date
        and d.activity_date<m.month_start
    ) as prev_active
  from months m
  join metrics_private.retention_activation_v3 a
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
$function$
;

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
$function$
;

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
$function$
;

CREATE OR REPLACE FUNCTION public.read_retention_heatmap_cell_drill_v3(p_interval text, p_cohort_start date DEFAULT NULL::date, p_rel_period integer DEFAULT 1, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_segment text DEFAULT 'all'::text, p_query text DEFAULT ''::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 8)
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
  from metrics_private.retention_dashboard_meta_v3 m
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
  from metrics_private.retention_activation_v3 a
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
      from metrics_private.retention_core_day_v3 d
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
$function$
;
