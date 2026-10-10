-- Data-quality v2: shadow pipeline. Does NOT alter existing production readers.
-- Promotes only verified independent core work and meaningful GST processes.
-- Excludes staff actors, explicitly failed attempts, and marked test companies.
CREATE OR REPLACE FUNCTION metrics_private.company_work_module_v2(p_event_name text,p_properties jsonb)
RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $fn$
 SELECT CASE
 WHEN lower(btrim(coalesce(p_properties->>'status','')))='failed' THEN NULL
 WHEN p_event_name='Accounting Sync' THEN NULL
 WHEN p_event_name='Invoice Bulk Edited' THEN 'ar'
 WHEN p_event_name <> 'Accounting Sync' AND public.is_core_activity(p_event_name,p_properties)
   THEN public.company_module_for(p_event_name,p_properties)
 WHEN p_event_name='Recon Processed'
  OR (p_event_name='Upload' AND lower(btrim(coalesce(p_properties->>'type',''))) IN ('gstr2b','purchase_register'))
   THEN 'gst'
 ELSE NULL END;
$fn$;
REVOKE ALL ON FUNCTION metrics_private.company_work_module_v2(text,jsonb) FROM PUBLIC,anon,authenticated;

CREATE TABLE IF NOT EXISTS metrics_private.company_calendar_month_module_usage_v2 (
 company_id text NOT NULL,user_key text NOT NULL,usage_month date NOT NULL,
 module text NOT NULL,events bigint NOT NULL,
 PRIMARY KEY(company_id,user_key,usage_month,module)
);
CREATE INDEX IF NOT EXISTS company_monthly_core_v2_month_idx
 ON metrics_private.company_calendar_month_module_usage_v2(usage_month,module,company_id);

CREATE TABLE IF NOT EXISTS metrics_private.company_monthly_meta_v2(
 singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
 first_integration_month date,data_month date,source_watermark_at timestamptz,
 refreshed_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.refresh_companies_monthly_core_v2()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','metrics_private','pg_temp'
SET statement_timeout TO '95s'
AS $fn$
DECLARE v_rows bigint;
BEGIN
 TRUNCATE metrics_private.company_calendar_month_module_usage_v2;
 INSERT INTO metrics_private.company_calendar_month_module_usage_v2
 (company_id,user_key,usage_month,module,events)
 WITH qualified AS MATERIALIZED(
  SELECT e.company_id,
  coalesce(nullif(btrim(e.distinct_id),''),'__unattributed__') user_key,
  date_trunc('month',e.event_time AT TIME ZONE 'Asia/Kolkata')::date usage_month,
  metrics_private.company_work_module_v2(e.event_name,coalesce(e.properties,'{}'::jsonb)) module
  FROM public.events e
  JOIN metrics_private.company_monthly_identity i ON i.company_id=e.company_id
  LEFT JOIN public.company_directory d ON d.company_uuid::text=e.company_id
  CROSS JOIN metrics_private.company_monthly_meta m
  WHERE m.singleton
   AND e.event_time>=i.integration_at
   AND e.ingested_at<=m.source_watermark_at
   AND NOT coalesce(i.is_test,false)
   AND NOT coalesce(d.is_test,false)
   AND NOT public.is_internal_email(e.email)
 )
 SELECT company_id,user_key,usage_month,module,count(*)::bigint
 FROM qualified WHERE module IN('ap','ar','transactions','gst')
 GROUP BY 1,2,3,4;
 GET DIAGNOSTICS v_rows=ROW_COUNT;

 INSERT INTO metrics_private.company_monthly_meta_v2
 (singleton,first_integration_month,data_month,source_watermark_at,refreshed_at)
 SELECT true, min(i.integration_month) FILTER(WHERE NOT i.is_test),
   max(m.data_month),max(m.source_watermark_at),now()
 FROM metrics_private.company_monthly_meta m
 LEFT JOIN metrics_private.company_monthly_identity i ON NOT i.is_test
 WHERE m.singleton
 ON CONFLICT(singleton) DO UPDATE SET
 first_integration_month=excluded.first_integration_month,
 data_month=excluded.data_month,
 source_watermark_at=excluded.source_watermark_at,
 refreshed_at=excluded.refreshed_at;

 RETURN jsonb_build_object('status','ok','usage_rows',v_rows,
 'source_watermark_at',(SELECT source_watermark_at FROM metrics_private.company_monthly_meta_v2 WHERE singleton));
END;
$fn$;
REVOKE ALL ON FUNCTION public.refresh_companies_monthly_core_v2() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_companies_monthly_core_v2() TO service_role;

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


REVOKE ALL ON FUNCTION public.read_companies_monthly_grid_v2(date,date,text,text,text,text,text,integer,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_companies_monthly_grid_v2(date,date,text,text,text,text,text,integer,integer) TO service_role;
REVOKE ALL ON FUNCTION public.read_companies_monthly_breakdown_v2(text,text,text,date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.read_companies_monthly_breakdown_v2(text,text,text,date) TO service_role;
