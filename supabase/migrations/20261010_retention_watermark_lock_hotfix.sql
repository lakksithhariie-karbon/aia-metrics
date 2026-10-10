-- Prevent Retention refresh lock contention and loss of reporting eligibility.
-- Incremental export marked failed only because post-import Retention RPC timed out.
-- An export's retained last_success_at is trustworthy for that exact failure mode.
-- Other failed export statuses do NOT advance reporting data.

CREATE OR REPLACE FUNCTION public.refresh_retention_dashboard_v3(p_force boolean DEFAULT false)
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
  -- Avoid concurrent pg_cron + ingest refresh TRUNCATE lock contention.
  if not pg_try_advisory_xact_lock(20261010, 3) then
    return jsonb_build_object('refreshed',false,'reason','refresh_already_running');
  end if;

  select w.last_success_at
    into v_source_watermark
  from public.export_watermarks w
  where w.job_name='incremental'
    and w.last_success_at is not null
    and (w.status='ok' or
      (w.status='failed' and w.detail like 'refresh_retention RPC failed:%'))
  order by w.last_success_at desc
  limit 1;

  select m.source_watermark_at
    into v_current_watermark
  from metrics_private.retention_dashboard_meta_v3 m
  where m.singleton=true;

  -- Never replace a valid cache watermark with NULL.
  if v_source_watermark is null then
    raise exception 'retention_source_watermark_unavailable';
  end if;

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

  truncate table metrics_private.retention_activation_v3;

  insert into metrics_private.retention_activation_v3 (
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
    where public.is_successful_integration(e.event_name,e.properties)
      and not metrics_private.is_retention_internal_email_v2(e.email)
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

  truncate table metrics_private.retention_core_day_v3;

  insert into metrics_private.retention_core_day_v3 (
    company_id,
    activity_date
  )
  select
    e.company_id,
    (e.event_time at time zone 'Asia/Kolkata')::date
  from public.events e
  join metrics_private.retention_activation_v3 a
    on a.company_id=e.company_id
   and a.activated_at is not null
  where e.event_time>=a.activated_at
    and public.is_core_activity(e.event_name,e.properties)
    and lower(btrim(coalesce(e.properties->>'status',''))) <> 'failed'
    and not metrics_private.is_retention_internal_email_v2(e.email)
  group by
    e.company_id,
    (e.event_time at time zone 'Asia/Kolkata')::date;

  get diagnostics v_core_day_rows = row_count;

  insert into metrics_private.retention_dashboard_meta_v3 (
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
  -- Avoid concurrent pg_cron + ingest refresh TRUNCATE lock contention.
  if not pg_try_advisory_xact_lock(20261010, 4) then
    return jsonb_build_object('refreshed',false,'reason','refresh_already_running');
  end if;

  select w.last_success_at
    into v_source_watermark
  from public.export_watermarks w
  where w.job_name='incremental'
    and w.last_success_at is not null
    and (w.status='ok' or
      (w.status='failed' and w.detail like 'refresh_retention RPC failed:%'))
  order by w.last_success_at desc
  limit 1;

  select m.source_watermark_at
    into v_current_watermark
  from metrics_private.retention_dashboard_meta_v4 m
  where m.singleton=true;

  -- Never replace a valid cache watermark with NULL.
  if v_source_watermark is null then
    raise exception 'retention_source_watermark_unavailable';
  end if;

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

-- Avoid overlapping source exports at :05 and independent-cache jobs.
SELECT cron.schedule('retention-dashboard-v3-watch',
 '13,43 * * * *','select public.refresh_retention_dashboard_v3(false);');
SELECT cron.schedule('retention-independent-core-v5-watch',
 '19,49 * * * *','SELECT public.refresh_retention_dashboard_v4(false);');
