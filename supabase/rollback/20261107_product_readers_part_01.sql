-- Exact original public Product read RPCs, part 1/12, backed up 2026-11-07.
-- Rollback only. Original data and function grants remain in place.
-- Apply this together with all other Product rollback parts if a cutover must be reversed.
SET LOCAL lock_timeout='7s';

CREATE OR REPLACE FUNCTION public.read_companies_breakdown(p_company_id text, p_module text, p_user_key text DEFAULT NULL::text, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS TABLE(event text, subtype text, status text, events bigint, items bigint, instrumented bigint, latest_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH bounds AS (
    SELECT (p_from::text || 'T00:00:00+05:30')::timestamptz AS start_at,
           ((p_to + 1)::text || 'T00:00:00+05:30')::timestamptz AS end_at
  ),
  classified AS (
    SELECT e.event_name AS event,
           public.company_subtype_for(e.event_name,
             COALESCE(e.properties, '{}'::jsonb)) AS subtype,
           NULLIF(btrim(COALESCE(e.properties, '{}'::jsonb) ->> 'status'), '')
             AS status,
           public.company_items_for(e.event_name,
             COALESCE(e.properties, '{}'::jsonb)) AS items,
           e.event_time
    FROM public.events e
    CROSS JOIN bounds
    WHERE e.company_id = p_company_id
      AND NOT public.is_internal_email(e.email)
      AND (p_user_key IS NULL
           OR NULLIF(btrim(e.distinct_id), '') IS NOT DISTINCT FROM
              NULLIF(btrim(p_user_key), ''))
      AND (p_from IS NULL OR e.event_time >= bounds.start_at)
      AND (p_to IS NULL OR e.event_time < bounds.end_at)
      AND public.company_module_for(e.event_name,
            COALESCE(e.properties, '{}'::jsonb)) = p_module
  )
  SELECT classified.event,
         classified.subtype,
         classified.status,
         COUNT(*) AS events,
         SUM(classified.items) AS items,
         COUNT(classified.items) AS instrumented,
         MAX(classified.event_time) AS latest_at
  FROM classified
  GROUP BY classified.event, classified.subtype, classified.status
  ORDER BY COUNT(*) DESC, classified.event ASC
$function$
;

CREATE OR REPLACE FUNCTION public.read_companies_context()
 RETURNS TABLE(clients jsonb, directory jsonb, data_start date, data_end date, watermark timestamp with time zone, integrations jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    (SELECT jsonb_agg(c.company_id ORDER BY c.company_id)
     FROM public.client_company c),
    (SELECT jsonb_agg(jsonb_build_object(
              'company_uuid', d.company_uuid::text,
              'company_name', d.company_name,
              'is_test', d.is_test))
     FROM public.company_directory d),
    (SELECT min(e.event_time AT TIME ZONE 'Asia/Kolkata')::date
     FROM public.events e),
    (SELECT max(e.event_time AT TIME ZONE 'Asia/Kolkata')::date
     FROM public.events e),
    (SELECT w.last_success_at
     FROM public.export_watermarks w
     WHERE w.job_name = 'incremental' AND w.status = 'ok'
     ORDER BY w.last_success_at DESC LIMIT 1),
    (SELECT jsonb_agg(jsonb_build_object(
              'company_id', t.company_id, 'integration', t.integration))
     FROM (
       SELECT DISTINCT ON (e.company_id) e.company_id,
              CASE lower(e.properties ->> 'type')
                WHEN 'tally' THEN 'Tally'
                WHEN 'zoho' THEN 'Zoho Books'
                WHEN 'zoho books' THEN 'Zoho Books'
                ELSE 'Unknown' END AS integration
       FROM public.events e
       WHERE e.event_name = 'Integration status'
         AND lower(e.properties ->> 'status') IN ('success', 'successful')
         AND e.company_id IS NOT NULL AND e.company_id <> ''
       ORDER BY e.company_id, e.event_time DESC) t)
$function$
;

CREATE OR REPLACE FUNCTION public.read_companies_identity_fast(p_company_id text, p_user_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '2s'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_companies_lifecycle_breakdown(p_company_id text, p_module text, p_user_key text DEFAULT NULL::text, p_usage_week smallint DEFAULT 1)
 RETURNS TABLE(event text, subtype text, status text, events bigint, items bigint, instrumented bigint, latest_at timestamp with time zone, window_start timestamp with time zone, window_end timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '5s'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_companies_lifecycle_identity(p_company_id text, p_user_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '2s'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_companies_lifecycle_page(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_query text DEFAULT ''::text, p_usage text DEFAULT 'all'::text, p_integration text DEFAULT 'all'::text, p_sort text DEFAULT 'integration_date'::text, p_direction text DEFAULT 'desc'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '5s'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_companies_monthly_breakdown(p_company_id text, p_module text, p_user_key text DEFAULT NULL::text, p_usage_month date DEFAULT NULL::date)
 RETURNS TABLE(event text, subtype text, status text, events bigint, items bigint, instrumented bigint, latest_at timestamp with time zone, window_start timestamp with time zone, window_end timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '5s'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_companies_monthly_breakdown_v2(p_company_id text, p_module text, p_user_key text DEFAULT NULL::text, p_usage_month date DEFAULT NULL::date)
 RETURNS TABLE(event text, subtype text, status text, events bigint, items bigint, instrumented bigint, latest_at timestamp with time zone, window_start timestamp with time zone, window_end timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '5s'
AS $function$
with identity as (
  select i.integration_at,i.integration_month
  from metrics_private.company_monthly_identity i
  where i.company_id=p_company_id AND NOT i.is_test
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
  cross join metrics_private.company_monthly_meta_v2 m
  where m.singleton
    and e.ingested_at<=m.source_watermark_at
    and e.company_id=p_company_id
    and e.event_time>=a.start_at
    and e.event_time<a.end_at
    and not public.is_internal_email(e.email)
    and metrics_private.company_work_module_v2(e.event_name,coalesce(e.properties,'{}'::jsonb))=p_module
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_companies_monthly_grid(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_query text DEFAULT ''::text, p_usage text DEFAULT 'all'::text, p_integration text DEFAULT 'all'::text, p_sort text DEFAULT 'integration_month'::text, p_direction text DEFAULT 'desc'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 5000)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '8s'
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_companies_monthly_grid_v2(p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_query text DEFAULT ''::text, p_usage text DEFAULT 'all'::text, p_integration text DEFAULT 'all'::text, p_sort text DEFAULT 'integration_month'::text, p_direction text DEFAULT 'desc'::text, p_page integer DEFAULT 1, p_page_size integer DEFAULT 5000)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '8s'
AS $function$
with meta as (
  select *
  from metrics_private.company_monthly_meta_v2
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
  from metrics_private.company_calendar_month_module_usage_v2 u
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
    and not i.is_test
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
  from metrics_private.company_calendar_month_module_usage_v2 u
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
  from metrics_private.company_calendar_month_module_usage_v2 u
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
$function$
;

CREATE OR REPLACE FUNCTION public.read_companies_monthly_identity(p_company_id text, p_user_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '2s'
AS $function$
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
$function$
;
