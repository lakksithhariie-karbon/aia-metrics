-- Repair Companies source provenance and prevent NULL watermark propagation.
-- Does not change live dashboard metric definitions; corrects freshness invariants.
CREATE OR REPLACE FUNCTION public.refresh_companies_monthly_cache()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '90s'
AS $function$
declare
  v_company_rows bigint;
  v_user_rows bigint;
  v_usage_rows bigint;
  v_watermark timestamptz;
begin
  -- Same-company refresh jobs must not contend with ingest-triggered refreshes.
  if not pg_try_advisory_xact_lock(20261010,11) then
    return jsonb_build_object('refreshed',false,'reason','refresh_already_running');
  end if;

  select w.last_success_at into v_watermark
  from public.export_watermarks w
  where w.job_name='incremental' and w.last_success_at is not null
    and (w.status='ok' or
      (w.status='failed' and w.detail like 'refresh_retention RPC failed:%'))
  order by w.last_success_at desc limit 1;
  if v_watermark is null then
    raise exception 'companies_source_watermark_unavailable';
  end if;

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

CREATE OR REPLACE FUNCTION public.refresh_companies_monthly_core_v2()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'metrics_private', 'pg_temp'
 SET statement_timeout TO '95s'
AS $function$
DECLARE v_rows bigint;
BEGIN
 IF NOT pg_try_advisory_xact_lock(20261010,12) THEN
  RETURN jsonb_build_object('status','skipped','reason','refresh_already_running');
 END IF;
 IF (SELECT source_watermark_at FROM metrics_private.company_monthly_meta WHERE singleton) IS NULL THEN
  RAISE EXCEPTION 'companies_core_v2_source_watermark_unavailable';
 END IF;
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
$function$;
