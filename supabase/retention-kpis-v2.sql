-- Retention KPI v2.
-- Cards-only data contract:
--   Activation starts from first successful integration.
--   First qualifying sync after integration is the guided/training sync.
--   Training day activity is excluded.
--   Activation closes only after a later-day non-sync core job (non-failed)
--   followed by a qualifying Accounting Sync.
--   TTV = first successful integration -> activation-closing sync.
--   Monthly churn = activated before month start + no core activity in month.
--   Internal staff events are excluded for aiaccountant.com, korefi.ai, and
--   karboncard.com (including subdomains) at every stage.

create table if not exists metrics_private.retention_activation_v2 (
  company_id text primary key,
  integration_at timestamptz not null,
  integration_month date not null,
  training_sync_at timestamptz,
  post_training_core_at timestamptz,
  activated_at timestamptz
);

create table if not exists metrics_private.retention_month_core_v2 (
  company_id text not null,
  month_start date not null,
  primary key (company_id, month_start)
);

create table if not exists metrics_private.retention_kpi_meta_v2 (
  singleton boolean primary key default true check (singleton),
  source_watermark_at timestamptz,
  refreshed_at timestamptz not null
);

create index if not exists events_qualifying_sync_idx
  on public.events (company_id, event_time)
  where public.is_qualifying_sync(event_name, properties);

create index if not exists retention_activation_v2_integration_idx
  on metrics_private.retention_activation_v2 (integration_at, company_id);
create index if not exists retention_activation_v2_activated_idx
  on metrics_private.retention_activation_v2 (activated_at, company_id)
  where activated_at is not null;
create index if not exists retention_month_core_v2_month_idx
  on metrics_private.retention_month_core_v2 (month_start, company_id);

revoke all on metrics_private.retention_activation_v2 from public, anon, authenticated;
revoke all on metrics_private.retention_month_core_v2 from public, anon, authenticated;
revoke all on metrics_private.retention_kpi_meta_v2 from public, anon, authenticated;


create or replace function metrics_private.is_retention_internal_email_v2(p_email text)
returns boolean
language plpgsql
immutable
parallel safe
set search_path = pg_catalog
as $function$
declare
  raw text;
  last_lt int;
  last_gt int;
  domain text;
begin
  if p_email is null or btrim(p_email) = '' then
    return false;
  end if;

  raw := lower(btrim(p_email));
  last_lt := case
    when strpos(raw, '<') = 0 then 0
    else length(raw) - strpos(reverse(raw), '<') + 1
  end;
  last_gt := case
    when strpos(raw, '>') = 0 then 0
    else length(raw) - strpos(reverse(raw), '>') + 1
  end;

  if last_lt > 0 and last_gt > 0 then
    raw := btrim(
      substring(
        raw
        from last_lt + 1
        for greatest(last_gt - last_lt - 1, 0)
      )
    );
  end if;

  if strpos(raw, '@') = 0 then
    return false;
  end if;

  domain := substring(raw from length(raw) - strpos(reverse(raw), '@') + 2);

  return domain in (
      'aiaccountant.com',
      'korefi.ai',
      'karboncard.com'
    )
    or domain like '%.aiaccountant.com'
    or domain like '%.korefi.ai'
    or domain like '%.karboncard.com';
end;
$function$;

revoke all on function metrics_private.is_retention_internal_email_v2(text)
  from public, anon, authenticated;

create or replace function public.refresh_retention_kpis_v2()
returns jsonb
language plpgsql
security definer
set search_path = public, metrics_private, pg_temp
set statement_timeout = '90s'
as $function$
declare
  v_integrated bigint;
  v_activated bigint;
  v_month_rows bigint;
  v_watermark timestamptz;
begin
  truncate table metrics_private.retention_activation_v2;

  insert into metrics_private.retention_activation_v2 (
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
    join public.client_company c on c.company_id = e.company_id
    where public.is_successful_integration(e.event_name, e.properties)
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.company_id, e.event_time asc, e.insert_id asc
  )
  select
    i.company_id,
    i.integration_at,
    date_trunc('month', i.integration_at at time zone 'Asia/Kolkata')::date,
    training.training_sync_at,
    core.post_training_core_at,
    activation.activated_at
  from first_integration i
  left join lateral (
    select e.event_time as training_sync_at
    from public.events e
    where e.company_id = i.company_id
      and e.event_time >= i.integration_at
      and public.is_qualifying_sync(e.event_name, e.properties)
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.event_time asc, e.insert_id asc
    limit 1
  ) training on true
  left join lateral (
    select e.event_time as post_training_core_at
    from public.events e
    where e.company_id = i.company_id
      and training.training_sync_at is not null
      and (e.event_time at time zone 'Asia/Kolkata')::date
          > (training.training_sync_at at time zone 'Asia/Kolkata')::date
      and public.is_core_activity(e.event_name, e.properties)
      and e.event_name <> 'Accounting Sync'
      and lower(btrim(coalesce(e.properties->>'status', ''))) <> 'failed'
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.event_time asc, e.insert_id asc
    limit 1
  ) core on true
  left join lateral (
    select e.event_time as activated_at
    from public.events e
    where e.company_id = i.company_id
      and core.post_training_core_at is not null
      and e.event_time > core.post_training_core_at
      and public.is_qualifying_sync(e.event_name, e.properties)
      and not metrics_private.is_retention_internal_email_v2(e.email)
    order by e.event_time asc, e.insert_id asc
    limit 1
  ) activation on true;

  get diagnostics v_integrated = row_count;

  select count(*) into v_activated
  from metrics_private.retention_activation_v2
  where activated_at is not null;

  truncate table metrics_private.retention_month_core_v2;

  insert into metrics_private.retention_month_core_v2 (company_id, month_start)
  select
    e.company_id,
    date_trunc('month', e.event_time at time zone 'Asia/Kolkata')::date
  from public.events e
  join metrics_private.retention_activation_v2 a
    on a.company_id = e.company_id
   and a.activated_at is not null
  where e.event_time >= a.activated_at
    and public.is_core_activity(e.event_name, e.properties)
    and not metrics_private.is_retention_internal_email_v2(e.email)
  group by
    e.company_id,
    date_trunc('month', e.event_time at time zone 'Asia/Kolkata')::date;

  get diagnostics v_month_rows = row_count;

  select w.last_success_at
    into v_watermark
  from public.export_watermarks w
  where w.job_name = 'incremental' and w.status = 'ok'
  order by w.last_success_at desc
  limit 1;

  insert into metrics_private.retention_kpi_meta_v2 (
    singleton, source_watermark_at, refreshed_at
  )
  values (true, v_watermark, now())
  on conflict (singleton) do update
    set source_watermark_at = excluded.source_watermark_at,
        refreshed_at = excluded.refreshed_at;

  return jsonb_build_object(
    'integrated_companies', v_integrated,
    'activated_companies', v_activated,
    'month_core_rows', v_month_rows,
    'source_watermark_at', v_watermark,
    'refreshed_at', now()
  );
end;
$function$;

create or replace function public.read_retention_kpis_v2(
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
with params as (
  select
    p_from as from_date,
    p_to as to_date,
    (date_trunc('month', now() at time zone 'Asia/Kolkata') - interval '1 month')::date
      as last_complete_month
),
cohort as (
  select a.*
  from metrics_private.retention_activation_v2 a
  cross join params p
  where (p.from_date is null
         or (a.integration_at at time zone 'Asia/Kolkata')::date >= p.from_date)
    and (p.to_date is null
         or (a.integration_at at time zone 'Asia/Kolkata')::date <= p.to_date)
),
activation_summary as (
  select
    count(*)::bigint as integrated,
    count(*) filter (where training_sync_at is not null)::bigint as trained,
    count(*) filter (where post_training_core_at is not null)::bigint as post_training_core,
    count(*) filter (where activated_at is not null)::bigint as activated,
    avg(extract(epoch from (activated_at - integration_at)) / 3600.0)
      filter (where activated_at is not null) as avg_ttv_hours,
    percentile_cont(0.5) within group (
      order by extract(epoch from (activated_at - integration_at)) / 3600.0
    ) filter (where activated_at is not null) as median_ttv_hours
  from cohort
),
churn_target as (
  select case
    when p.from_date is not null
      and date_trunc(
        'month',
        least(coalesce(p.to_date, p.last_complete_month), p.last_complete_month)::timestamp
      )::date
        < date_trunc('month', p.from_date::timestamp)::date
      then null::date
    else date_trunc(
      'month',
      least(coalesce(p.to_date, p.last_complete_month), p.last_complete_month)::timestamp
    )::date
  end as month_start
  from params p
),
churn_summary as (
  select
    t.month_start,
    count(a.company_id)::bigint as eligible,
    count(a.company_id) filter (
      where not exists (
        select 1
        from metrics_private.retention_month_core_v2 m
        where m.company_id = a.company_id
          and m.month_start = t.month_start
      )
    )::bigint as churned
  from churn_target t
  left join metrics_private.retention_activation_v2 a
    on t.month_start is not null
   and a.activated_at is not null
   and a.activated_at
       < (t.month_start::timestamp at time zone 'Asia/Kolkata')
  group by t.month_start
),
meta as (
  select source_watermark_at, refreshed_at
  from metrics_private.retention_kpi_meta_v2
  where singleton = true
  limit 1
)
select jsonb_build_object(
  'activation', jsonb_build_object(
    'integrated', s.integrated,
    'trained', s.trained,
    'post_training_core', s.post_training_core,
    'activated', s.activated,
    'rate_pct', case
      when s.integrated > 0
      then round(100.0 * s.activated::numeric / s.integrated::numeric, 1)
      else null
    end
  ),
  'ttv', jsonb_build_object(
    'companies', s.activated,
    'avg_hours', round(s.avg_ttv_hours::numeric, 1),
    'median_hours', round(s.median_ttv_hours::numeric, 1)
  ),
  'churn', jsonb_build_object(
    'month', case
      when c.month_start is null then null
      else to_char(c.month_start, 'YYYY-MM')
    end,
    'eligible', c.eligible,
    'churned', c.churned,
    'rate_pct', case
      when c.month_start is not null and c.eligible > 0
      then round(100.0 * c.churned::numeric / c.eligible::numeric, 1)
      else null
    end
  ),
  'source_watermark_at', (select source_watermark_at from meta),
  'refreshed_at', (select refreshed_at from meta)
)
from activation_summary s
cross join churn_summary c;
$function$;

revoke all on function public.refresh_retention_kpis_v2() from public, anon, authenticated;
revoke all on function public.read_retention_kpis_v2(date,date) from public, anon, authenticated;

grant execute on function public.refresh_retention_kpis_v2() to service_role;
grant execute on function public.read_retention_kpis_v2(date,date)
  to service_role, product_metrics_fetcher;

select public.refresh_retention_kpis_v2();

do $job$
declare current_job bigint;
begin
  select jobid into current_job
  from cron.job
  where jobname = 'retention-kpis-v2-hourly'
  limit 1;

  if current_job is not null then
    perform cron.unschedule(current_job);
  end if;

  perform cron.schedule(
    'retention-kpis-v2-hourly',
    '18 * * * *',
    'select public.refresh_retention_kpis_v2();'
  );
end;
$job$;
